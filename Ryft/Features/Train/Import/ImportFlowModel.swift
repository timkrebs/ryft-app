import Foundation
import Observation
import SwiftUI

/// The training import's six steps (ui.md §2): the files read into memory, the choices, the matches and the bodyweight
/// answers. Everything stays in memory until Import is tapped, so going back and forth, the keyboard and the background
/// never lose a choice, and an abandoned flow changes nothing. The views read it and call its actions; the decisions
/// live in the pure `ImportDetection`, `ImportSelection` and `ImportMappingState`.
@MainActor
@Observable
final class ImportFlowModel: Identifiable {
    enum Step: Int, CaseIterable, Hashable, Sendable {
        case pick = 1, detected, choose, map, preview, result

        var title: String {
            switch self {
            case .pick: String(localized: "Import training data", comment: "Training import: the flow's title, and Profile → Data's row.")
            case .detected: String(localized: "Detected", comment: "Training import: step 2's title.")
            case .choose: String(localized: "What to import", comment: "Training import: step 3's title.")
            case .map: String(localized: "Match exercises", comment: "Training import: step 4's title.")
            case .preview: String(localized: "Preview", comment: "Training import: step 5's title.")
            case .result: String(localized: "Import", comment: "Training import: step 6's title, and step 5's button without counts.")
            }
        }
    }

    static let stepCount = Step.allCases.count

    /// How the flow ends: closed, or closed onto a screen of Strain (ui.md §8.2).
    enum Finish: Equatable, Sendable {
        case close
        case openPlan(UUID)
        case openHistory
    }

    struct Dependencies {
        var library: TrainLibrary
        var mappings: ImportMappingStore
        /// What the account already has (step 3's plans, step 5), and the upload from Import on (step 6).
        var uploader: TrainImportUploader
        var clock: AppClock
        /// Captured when the flow starts and named on screen; no override in v1.
        var zone: TimeZone
        var account: @MainActor () -> String?
        var isOnline: @MainActor () -> Bool
        var readURLs: @Sendable ([URL]) async -> [ImportFileAccess.Loaded] = { await ImportFileAccess.load($0) }
        var aliases: @Sendable () async -> ExerciseAliases = { await ExerciseAliases.loadBundled() }
        /// What the account already has (the uploader's; tests hold it to order two builds).
        var checkExisting: (@MainActor (ImportExistingQuery) async -> ImportExisting)?
        /// Debug and UI tests (`-uiTestImportFiles`): these files in place of the system picker.
        var scriptedFiles: (@MainActor () -> [ImportFileAccess.Loaded])?
        var announce: @MainActor (String) -> Void = { text in
            AccessibilityNotification.Announcement(text).post()
        }
    }

    let id = UUID()
    let deps: Dependencies
    /// The account the flow started with (or demo's): every derived id and the remembered choices are its own.
    let account: String?
    /// Called when the flow closes; the coordinator dismisses the cover.
    var onFinish: (@MainActor (Finish) -> Void)?

    /// The steps pushed on top of step 1. Leaving step 5 or 4 (back, or a swipe) drops any build or matching still
    /// running for it, so a later one always wins.
    var path: [Step] = [] {
        didSet {
            if !path.contains(.preview), oldValue.contains(.preview) { invalidateBuild() }
            if !path.contains(.map), oldValue.contains(.map) { invalidateMapping() }
        }
    }
    var step: Step { path.last ?? .pick }

    // MARK: Steps 1 and 2

    /// Set by reading; previews seed it.
    var files: [ImportPickedFile] = [] {
        didSet { detection = ImportDetection(files: files) }
    }
    private var nextFileID = 0
    /// The system picker (`.fileImporter`).
    var showsPicker = false
    /// P7: more files than one import takes.
    var tooManyFiles = false
    /// The warnings list in step 2: open by default for a partly recognised file (D8).
    var showsWarnings = false

    /// Step 2's facts, merged once per change of the files (views read it often).
    private(set) var detection = ImportDetection(files: [])
    /// P2 on step 1: files are being read.
    var isReading: Bool { files.contains(where: \.isReading) }
    /// Step 1's messages: the files that couldn't be read, while none could.
    var pickProblems: [ImportPickedFile] {
        guard !isReading, files.allSatisfy({ $0.problem?.isPickProblem == true }) else { return [] }
        return files
    }

    // MARK: Step 3

    var selection: ImportSelection?
    private var selectionBundle: ImportBundle?

    // MARK: Step 4

    enum LibraryState: Equatable, Sendable {
        /// M4: no cached library yet, or matching runs.
        case loading
        case ready
        /// M5: offline and nothing cached.
        case unavailable
    }

    enum MapFilter: Hashable, Sendable { case all, needsCheck }

    var libraryState: LibraryState = .loading
    var mapping: ImportMappingState?
    var search = ""
    var filter: MapFilter = .all
    var aliases: ExerciseAliases?

    // MARK: Cancel

    /// N1: "Discard this import?"
    var confirmsDiscard = false

    // MARK: Steps 5 and 6

    enum BuildState: Equatable, Sendable {
        case building, ready
        /// The preview couldn't be built (the account changed, or it was cancelled).
        case failed
    }

    enum PreviewSegment: Hashable, Sendable { case plan, history }

    var buildState: BuildState = .building
    var build: ImportBuild?
    /// Step 5's workout toggles: starts as `build.defaultIncluded` (duplicates off).
    var included: Set<UUID> = []
    /// Step 5's plan names by plan id; a missing entry is the file's name.
    var planNames: [UUID: String] = [:]
    var previewSegment: PreviewSegment = .plan
    /// What the account already has, from the last check (step 3's "Already in RYFT").
    private(set) var existing: ImportExisting?
    /// Import was tapped and the job is being stored.
    private(set) var isStarting = false
    /// The uploader refused to start: an earlier import is still unfinished.
    var startRefused = false
    /// Opened on step 6 from an entry point while a job uploads: "An import is in progress…" first.
    var blockedByRunningJob = false
    /// A file that arrived while this job uploaded (E9): "Open the file you just received" on the result.
    var waitingFileName: @MainActor () -> String? = { nil }
    /// Opens that file in a new flow (the coordinator's).
    var openWaitingFile: (@MainActor () async -> Void)?

    init(deps: Dependencies) {
        self.deps = deps
        account = deps.account()
    }

    /// Today in the flow's zone (the range presets, workouts in the future).
    var today: LocalDate { LocalDate(deps.clock.now(), in: deps.zone) ?? .fallback }

    // MARK: Files

    /// "Choose files" (step 1), "Add another file" and "Add plan file" (step 2): the system picker, or in Debug the
    /// scripted files.
    func chooseFiles() {
        tooManyFiles = false
        if let scripted = deps.scriptedFiles {
            let loaded = scripted()
            Task { await receive(loaded) }
            return
        }
        showsPicker = true
    }

    /// The picker's answer. A cancelled picker changes nothing.
    func picked(_ result: Result<[URL], Error>) async {
        guard case let .success(urls) = result, !urls.isEmpty else { return }
        guard admits(urls.count) else { return }
        let rows = startReading(urls.map(\.lastPathComponent))
        deps.announce(String(localized: "Reading \(urls.count) files",
                             comment: "Training import, VoiceOver: files were picked and are being read."))
        let loaded = await deps.readURLs(urls)
        await finishReading(rows, loaded)
    }

    /// Files already read into memory (Open in, the scripted files).
    func receive(_ loaded: [ImportFileAccess.Loaded]) async {
        guard !loaded.isEmpty, admits(loaded.count) else { return }
        let rows = startReading(loaded.map(\.name))
        await finishReading(rows, loaded)
    }

    /// D6: a file the user doesn't want (or that failed). With none left, back to step 1.
    func removeFile(_ id: Int) {
        files.removeAll { $0.id == id }
        if files.isEmpty { path = [] }
    }

    private func admits(_ count: Int) -> Bool {
        let kept = step == .pick || !files.contains(where: { $0.bundle != nil }) ? 0 : files.count
        let total = kept + count
        tooManyFiles = total > ImportLimits.standard.maxFiles
        return !tooManyFiles
    }

    private func startReading(_ names: [String]) -> [Int] {
        // On step 1 (or when nothing could be used) a new pick replaces what failed before; on step 2 it adds.
        if step == .pick || !files.contains(where: { $0.bundle != nil }) { files = [] }
        var ids: [Int] = []
        for name in names {
            files.append(ImportPickedFile(id: nextFileID, name: name, status: .reading))
            ids.append(nextFileID)
            nextFileID += 1
        }
        return ids
    }

    private func finishReading(_ ids: [Int], _ loaded: [ImportFileAccess.Loaded]) async {
        for (id, file) in zip(ids, loaded) {
            let status: ImportPickedFile.Status
            switch file.result {
            case let .failure(problem): status = .failed(ImportFileProblem(problem))
            case let .success(data): status = await ImportFileReading.read(ImportFile(name: file.name, data: data), index: id)
            }
            if let index = files.firstIndex(where: { $0.id == id }) { files[index].status = status }
        }
        showsWarnings = detection.isWeak
        // Step 1 moves on once one file is recognised or none could be read as a format (D5 lives in step 2).
        if step == .pick, files.contains(where: { $0.bundle != nil || $0.problem == .notSupported }) {
            path = [.detected]
        }
    }

    // MARK: Continue

    func continueFromDetected() {
        guard let bundle = detection.bundle, detection.canContinue else { return }
        if selection == nil || selectionBundle != bundle {
            selection = ImportSelection(bundle: bundle, today: today, hasEnrollment: hasEnrollment)
            selectionBundle = bundle
            Task { await checkExistingPlans() }
        }
        path.append(.choose)
    }

    /// Step 3's "Already in RYFT": the account's plans with the file's derived ids. Offline: nothing is marked.
    func checkExistingPlans() async {
        guard let bundle = detection.bundle, let account else { return }
        let query = ImportBuilder.query(for: bundle, decisions: ImportDecisions(account: account, zone: deps.zone))
        let existing = await checkExisting(query)
        guard detection.bundle == bundle else { return }
        self.existing = existing
        selection?.markExisting(query.planIDs.map { existing.plans.keys.contains($0) })
    }

    /// The bundle as chosen in step 3: what step 4 maps.
    var chosenBundle: ImportBundle? {
        guard let bundle = detection.bundle, let selection else { return nil }
        return selection.chosen(from: bundle, today: today, zone: deps.zone)
    }

    var selectionBlock: ImportSelection.Block? {
        guard let bundle = detection.bundle, let selection else { return .nothingSelected }
        return selection.block(bundle: bundle, today: today, zone: deps.zone)
    }

    func continueFromChoose() {
        guard selectionBlock == nil else { return }
        path.append(.map)
        mappingTask?.cancel()
        mappingTask = Task { await prepareMapping() }
    }

    func continueFromMap() {
        guard let mapping, mapping.leftToCheck == 0, libraryState == .ready else { return }
        path.append(.preview)
        buildTask?.cancel()
        buildTask = Task { await prepareBuild() }
    }

    /// The matching or build running now; a newer one, or leaving its step, cancels it and its answer is dropped.
    private(set) var mappingTask: Task<Void, Never>?
    private(set) var buildTask: Task<Void, Never>?
    @ObservationIgnored private var mappingGeneration = 0
    @ObservationIgnored private var buildGeneration = 0

    private func invalidateBuild() {
        buildGeneration += 1
        buildTask?.cancel()
        buildTask = nil
        buildState = .building
    }

    private func invalidateMapping() {
        mappingGeneration += 1
        mappingTask?.cancel()
        mappingTask = nil
    }

    // MARK: Step 3 facts

    /// An active or paused plan exists: "make active" starts off and its footer says what it replaces (C2).
    var hasEnrollment: Bool { deps.library.activeEnrollment != nil || deps.library.isPaused }
    var currentPlanName: String? { deps.library.activePlanName }
    var currentWeek: Int? { deps.library.activeEnrollment?.currentWeek }
    var currentPlanIsPaused: Bool { deps.library.isPaused }

    // MARK: Step 4

    /// Matches the chosen exercises (the library from the cache; without one, a refresh first).
    func prepareMapping() async {
        guard let bundle = chosenBundle else { return }
        mappingGeneration += 1
        let generation = mappingGeneration
        if deps.library.exercises.isEmpty {
            libraryState = .loading
            await deps.library.refresh()
            guard generation == mappingGeneration else { return }
        }
        let library = deps.library.exercises.filter { !$0.archived }
        guard !library.isEmpty else {
            libraryState = .unavailable
            return
        }
        libraryState = .loading
        let aliases = await deps.aliases()
        guard generation == mappingGeneration else { return }
        self.aliases = aliases
        let remembered = deps.mappings.remembered(source: bundle.format)
        let result = await ImportMatching.run(bundle, library: library, aliases: aliases,
                                              remembered: remembered.mapValues(\.exerciseID))
        // Another matching started meanwhile (back to step 3 and on again): its answer is the one that counts.
        guard generation == mappingGeneration else { return }
        mapping = ImportMappingState(sources: result.sources, matches: result.matches, library: library,
                                     remembered: remembered, aliases: aliases, previous: mapping?.rows ?? [])
        libraryState = .ready
    }

    /// The rows step 4 lists now: the search (the file's name or the match's) and the filter.
    func visibleRows(attention: Bool) -> [ImportMappingRow] {
        guard let mapping else { return [] }
        let query = search.trimmingCharacters(in: .whitespaces)
        return (attention ? mapping.attention : mapping.resolved).filter { row in
            if filter == .needsCheck, !mapping.blocks(row) { return false }
            guard !query.isEmpty else { return true }
            let matched = mapping.exercise(for: row)?.name ?? row.draft?.name ?? ""
            return row.source.name.localizedCaseInsensitiveContains(query) || matched.localizedCaseInsensitiveContains(query)
        }
    }

    /// Search and the filter show with more than 8 exercises (ui.md 7.1).
    var showsMapControls: Bool { (mapping?.rows.count ?? 0) > 8 }

    func accept(_ key: SourceExerciseKey) {
        mapping?.accept(key)
        announceMatched(key)
    }

    func acceptLikely() {
        let count = mapping?.acceptLikely() ?? 0
        guard count > 0 else { return }
        deps.announce(String(localized: "\(count) matches accepted",
                             comment: "Training import, VoiceOver: the bulk action accepted this many suggestions."))
    }

    func choose(_ key: SourceExerciseKey, _ exercise: Exercise) {
        mapping?.choose(key, exercise)
        announceMatched(key)
    }

    func create(_ key: SourceExerciseKey, _ draft: ImportCustomDraft) {
        mapping?.create(key, draft)
        announceMatched(key)
    }

    func setMuscle(_ key: SourceExerciseKey, _ muscle: Muscle) {
        guard let aliases else { return }
        mapping?.setMuscle(key, muscle, aliases: aliases)
        announceMatched(key)
    }

    func skip(_ key: SourceExerciseKey) {
        mapping?.skip(key)
    }

    func answer(_ key: SourceExerciseKey, _ answer: BodyweightAnswer) {
        mapping?.answer(key, answer)
    }

    /// "<name>, now matched. 3 left to check." once a row stops blocking.
    private func announceMatched(_ key: SourceExerciseKey) {
        guard let mapping, let row = mapping.row(key), !mapping.blocks(row) else { return }
        let left = mapping.leftToCheck
        deps.announce(String(localized: "\(row.source.name), now matched. \(left) left to check.",
                             comment: "Training import, VoiceOver: a row was resolved; the rows still blocking."))
    }

    /// A new custom exercise's draft for "Create a custom exercise…" (the file's name and equipment).
    func draft(for key: SourceExerciseKey) -> ImportCustomDraft? {
        guard let row = mapping?.row(key), let aliases else { return nil }
        return row.draft ?? ImportCustomDraft(row.source, aliases: aliases)
    }

    // MARK: Step 5

    /// What the builder gets from steps 3 and 4: the full bundle's plans and sessions are judged against these.
    func decisions() -> ImportDecisions? {
        guard let account, let selection, let mapping, let bundle = detection.bundle else { return nil }
        let (from, to) = selection.bounds(today: today, zone: deps.zone)
        return ImportDecisions(
            account: account, zone: deps.zone,
            exercises: mapping.choices(account: account, source: bundle.format, aliases: aliases ?? .fallback),
            plans: selection.plans.map { choice in
                ImportPlanChoice(included: choice.isOn && choice.state.canImport,
                                 replaceExisting: choice.state == .alreadyInRYFT(replace: true))
            },
            history: ImportHistoryChoice(included: selection.includesHistory, from: from, to: to),
            enrolPlanIndex: selection.activePlan)
    }

    /// Builds step 5 off the main actor, after asking what the account already has (offline: unchecked).
    func prepareBuild() async {
        guard let bundle = detection.bundle, let decisions = decisions() else {
            buildState = .failed
            return
        }
        buildGeneration += 1
        let generation = buildGeneration
        buildState = .building
        let query = ImportBuilder.query(for: bundle, decisions: decisions)
        let existing = await checkExisting(query)
        // A newer build (back to step 4, a change, Continue again) or leaving step 5: this answer is stale.
        guard generation == buildGeneration else { return }
        self.existing = existing
        do {
            let build = try await ImportBuilder.build(bundle, decisions: decisions, existing: existing,
                                                      now: deps.clock.now())
            guard generation == buildGeneration else { return }
            included = Self.toggles(after: build, previous: self.build, included: included)
            self.build = build
            if !build.plans.contains(where: \.willBeSent) { previewSegment = .history }
            buildState = .ready
        } catch {
            guard generation == buildGeneration else { return }
            buildState = .failed
        }
    }

    private func checkExisting(_ query: ImportExistingQuery) async -> ImportExisting {
        if let check = deps.checkExisting { return await check(query) }
        return await deps.uploader.checkExisting(query)
    }

    var totals: ImportTotals? { build?.totals(including: included) }

    /// A rebuild (back to step 3 or 4 and forward again) keeps the user's toggles for workouts that are still
    /// toggleable; workouts the earlier build didn't offer start at their default.
    static func toggles(after build: ImportBuild, previous: ImportBuild?, included: Set<UUID>) -> Set<UUID> {
        guard let previous else { return build.defaultIncluded }
        let offeredBefore = Set(previous.sessions.filter(\.verdict.isToggleable).map(\.id))
        var out = Set<UUID>()
        for session in build.sessions where session.verdict.isToggleable {
            let on = offeredBefore.contains(session.id) ? included.contains(session.id) : session.verdict.isIncludedByDefault
            if on { out.insert(session.id) }
        }
        return out
    }

    /// The name step 5 shows and sends for a plan: the user's edit, else the file's.
    func planName(_ preview: ImportPlanPreview) -> String {
        planNames[preview.id] ?? preview.plan?.name ?? ""
    }

    func setPlanName(_ name: String, for preview: ImportPlanPreview) {
        planNames[preview.id] = String(name.prefix(ImportCustomExercise.maxNameLength))
    }

    /// "Give the plan a name.": a plan that will be sent has an empty name.
    var hasUnnamedPlan: Bool {
        build?.plans.contains { $0.willBeSent && planName($0).trimmingCharacters(in: .whitespaces).isEmpty } ?? false
    }

    func setIncluded(_ id: UUID, _ on: Bool) {
        if on { included.insert(id) } else { included.remove(id) }
    }

    /// Uploads aren't available yet (the contract, or the flag): step 5 offers "Keep on this iPhone" (V5).
    var uploadsAvailable: Bool { deps.uploader.uploadsAvailable }

    /// V4: everything in the file is already in RYFT.
    var isAlreadyImported: Bool {
        guard let build, let totals, totals.isNothing else { return false }
        let plansThere = build.plans.allSatisfy { $0.state == .alreadyInRYFT || !$0.willBeSent }
        return totals.alreadyImported > 0 && plansThere
    }

    var canImport: Bool {
        guard buildState == .ready, let totals, !totals.isNothing, !hasUnnamedPlan, !isStarting else { return false }
        return true
    }

    /// Import (or "Keep on this iPhone"): the choices are remembered now, the job is stored and the upload starts.
    func startImport() async {
        guard canImport, let build, let account else { return }
        isStarting = true
        defer { isStarting = false }
        let plan = build.uploadPlan(including: included, planNames: planNames)
        let started = await deps.uploader.start(plan, account: account, source: build.source, zone: deps.zone,
                                                duplicatesChecked: build.duplicatesChecked)
        guard started else {
            startRefused = true
            return
        }
        if let mapping {
            deps.mappings.remember(mapping.rememberedChoices(account: account, source: build.source),
                                   source: build.source, account: account, at: deps.clock.now())
        }
        path.append(.result)
    }

    // MARK: Step 6

    var job: ImportJobStatus? { deps.uploader.status }

    func retryRejected() async { await deps.uploader.retryRejected() }
    func importDuplicatesFound() async { await deps.uploader.importDuplicatesFound() }

    /// The result is on screen. A finished import with nothing refused counts as seen (its resume row goes); one with
    /// refused items (I4) stays unseen, so its "needs attention" row and Retry survive a relaunch, until Done or a
    /// Retry that leaves nothing refused.
    func resultShown() {
        guard let job, job.isFinished, !job.hasRejected else { return }
        deps.uploader.markResultSeen()
    }

    /// Close (step 6's leading button): leaves; the import continues, an I4 result stays unseen.
    func close() {
        resultShown()
        finish(.close)
    }

    /// Done (I3, I4, I9): a finished job was seen, refused items included.
    func done() {
        if job?.isFinished == true { deps.uploader.markResultSeen() }
        finish(.close)
    }

    /// "Discard import" on a paused or saved job (S2): nothing more is sent; what's already in RYFT stays.
    var confirmsDiscardJob = false

    func discardJob() {
        deps.uploader.discard()
        finish(.close)
    }

    func openPlan() {
        let id = job?.enrolledPlanID ?? job?.planIDs.first
        resultShown()
        finish(id.map(Finish.openPlan) ?? .close)
    }

    /// "Open the file you just received": this job's result counts as seen, the new file starts its own flow.
    func openReceivedFile() async {
        resultShown()
        await openWaitingFile?()
    }

    func openHistory() {
        resultShown()
        finish(.openHistory)
    }

    // MARK: Cancel

    /// Step 1 closes at once (nothing read yet); steps 2 to 5 ask first (N1); step 6 only closes.
    func cancel() {
        switch step {
        case .pick, .result: finish(.close)
        case .detected, .choose, .map, .preview: confirmsDiscard = true
        }
    }

    /// N1 → Discard: forget the files and every choice. The file itself is not changed.
    func discard() {
        files = []
        selection = nil
        mapping = nil
        finish(.close)
    }

    func finish(_ how: Finish) {
        onFinish?(how)
    }
}
