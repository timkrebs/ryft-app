import Foundation
import Testing
@testable import Ryft

/// The import flow's steps and guards (ui.md §1, §4–§7): files read into steps, the choices, the matches and the
/// bodyweight question, on synthetic files only.
@MainActor
@Suite("Import flow model")
struct TrainImportFlowModelTests {
    final class Spoken {
        var lines: [String] = []
    }

    let store = TrainStore(inMemory: true)
    /// The uploader holds its environment weakly.
    let env = AppEnvironment.test()
    let spoken = Spoken()
    let zone = TimeZone(identifier: "Europe/Berlin") ?? .current

    /// A flow on the demo library (MockTrain); `enrolled`: an active plan exists. Real time, so demo's files are recent.
    func flow(enrolled: Bool = false, library: TrainLibrary? = nil, now: Date = .now,
              read: [ImportFileAccess.Loaded] = []) -> ImportFlowModel {
        let library = library ?? TrainLibrary.preview(store: store, enrolled: enrolled)
        let deps = ImportFlowModel.Dependencies(
            library: library, mappings: ImportMappingStore(persistence: store) { "account-a" },
            uploader: TrainImportUploader(env: env), clock: TestClock(now: now), zone: zone,
            account: { "account-a" }, isOnline: { true }, readURLs: { _ in read },
            aliases: { ExerciseAliases.bundled }, scriptedFiles: nil,
            announce: { [spoken] in spoken.lines.append($0) })
        return ImportFlowModel(deps: deps)
    }

    static func loaded(_ name: String, _ data: Data) -> ImportFileAccess.Loaded {
        ImportFileAccess.Loaded(name: name, result: .success(data))
    }

    var demoFiles: [ImportFileAccess.Loaded] {
        [Self.loaded("plans.csv", ImportDemoFiles.plans(now: .now)), Self.loaded("workouts.csv", ImportDemoFiles.workouts(now: .now))]
    }

    // MARK: Steps 1 and 2

    @Test func readFilesMoveToStepTwo() async throws {
        let model = flow(read: demoFiles)
        await model.picked(.success([URL(fileURLWithPath: "/tmp/plans.csv"), URL(fileURLWithPath: "/tmp/workouts.csv")]))
        #expect(model.path == [.detected])
        #expect(model.detection.state == .detected)
        let summary = try #require(model.detection.summary)
        #expect(summary.plans == 1 && summary.days == 2 && summary.exercises == 6)
        #expect(summary.workouts == 4)
        #expect(spoken.lines == ["Reading 2 files"])
    }

    /// P3 to P6 keep the user on step 1 with each file's reason; a pick replaces them.
    @Test func filesThatCantBeReadStayOnStepOne() async {
        let model = flow()
        await model.receive([ImportFileAccess.Loaded(name: "a.csv", result: .failure(.tooLarge)),
                             ImportFileAccess.Loaded(name: "b.csv", result: .failure(.empty)),
                             ImportFileAccess.Loaded(name: "c.heic", result: .failure(.notText))])
        #expect(model.path.isEmpty)
        #expect(model.pickProblems.map(\.problem) == [.tooLarge, .empty, .notCSV])
        await model.receive(demoFiles)
        #expect(model.files.count == 2)
        #expect(model.path == [.detected])
    }

    /// P7: more than 6 files are refused before anything is read.
    @Test func tooManyFiles() async {
        let model = flow()
        await model.receive((0..<7).map { Self.loaded("\($0).csv", ImportMockData.plans) })
        #expect(model.tooManyFiles)
        #expect(model.files.isEmpty)
    }

    /// D5: a file no format reads goes on to step 2, which says so and offers another file, never Continue.
    @Test func unsupportedFileIsStepTwosD5() async {
        let model = flow()
        await model.receive([Self.loaded("notes.txt", ImportMockData.garbage)])
        #expect(model.path == [.detected])
        #expect(model.detection.state == .notSupported(name: "notes.txt"))
        #expect(!model.detection.canContinue)
    }

    /// D6: a valid file and an unsupported one: the valid one carries on, the other is listed and can be removed.
    @Test func mixedFilesCarryOn() async {
        let model = flow()
        await model.receive([Self.loaded("plans.csv", ImportMockData.plans), Self.loaded("notes.txt", ImportMockData.garbage)])
        #expect(model.detection.state == .detected)
        #expect(model.detection.showsFileList)
        #expect(model.detection.isPlanOnly)
        let failed = model.files.first { $0.problem == .notSupported }
        model.removeFile(failed?.id ?? -1)
        #expect(model.files.count == 1)
        #expect(!model.detection.showsFileList)
        model.removeFile(model.files.first?.id ?? -1)
        #expect(model.path.isEmpty) // nothing left: back to step 1
    }

    /// D2 and D3, and step 2's time-zone line only with workouts.
    @Test func planOnlyAndWorkoutsOnly() async {
        let plans = flow()
        await plans.receive([Self.loaded("plans.csv", ImportMockData.plans)])
        #expect(plans.detection.isPlanOnly && !plans.detection.hasWorkouts)
        let workouts = flow()
        await workouts.receive([Self.loaded("workouts.csv", ImportMockData.workouts)])
        #expect(workouts.detection.isWorkoutsOnly && workouts.detection.hasWorkouts)
    }

    /// Step 2's warnings: problems counted apart from notes, and a weak file opens them by default (D8).
    @Test func warningsCountProblemsAndNotes() {
        let detection = ImportDetection(files: ImportMockData.withWarnings(ImportMockData.bothFiles))
        #expect(detection.problems.count == 4) // two per file: unrecognised line, unreadable number
        #expect(detection.notes.count == 4) // two per file: assumed kg, assumed duration
        #expect(detection.hasWarnings)
        let weak = ImportDetection(files: [ImportMockData.file(0, "w.csv", ImportMockData.workouts, confidence: .weak)])
        #expect(weak.isWeak)
    }

    /// D7: recognised, but nothing in it.
    @Test func recognisedButEmpty() {
        let empty = ImportBundle(format: .alphaProgression, plans: [], sessions: [], warnings: [], suppressedWarnings: 0, lineCount: 3)
        let detection = ImportDetection(files: [ImportPickedFile(id: 0, name: "x.csv", status: .read(empty, confidence: .strong))])
        #expect(detection.state == .nothingInFile)
        #expect(!detection.canContinue)
    }

    // MARK: Step 3

    /// No plan active: everything on, all time, and the imported plan becomes the active one.
    @Test func choicesWithoutAnActivePlan() async throws {
        let model = flow()
        await model.receive(demoFiles)
        model.continueFromDetected()
        let selection = try #require(model.selection)
        #expect(model.path == [.detected, .choose])
        #expect(selection.plans == [ImportSelection.PlanChoice(isOn: true, state: .importable)])
        #expect(selection.includesHistory && selection.preset == .allTime)
        #expect(selection.activePlan == 0)
        #expect(model.selectionBlock == nil)
        model.continueFromChoose()
        #expect(model.path == [.detected, .choose, .map])
    }

    /// C2: with a plan active, "make active" starts off; importing never changes someone's training silently.
    @Test func anActivePlanKeepsMakeActiveOff() async {
        let model = flow(enrolled: true)
        await model.receive(demoFiles)
        model.continueFromDetected()
        #expect(model.hasEnrollment)
        #expect(model.selection?.activePlan == nil)
    }

    /// C3 and C4.
    @Test func continueNeedsSomethingToImport() async {
        let model = flow()
        await model.receive(demoFiles)
        model.continueFromDetected()
        model.selection?.setPlan(0, on: false)
        #expect(model.selection?.activePlan == nil) // turning the plan off clears "make active"
        model.selection?.includesHistory = false
        #expect(model.selectionBlock == .nothingSelected)
        model.selection?.includesHistory = true
        model.selection?.preset = .custom
        model.selection?.from = model.today
        model.selection?.to = model.today
        #expect(model.selectionBlock == .emptyRange)
    }

    /// A plan of more than 7 days can't be imported (history still can); a plan already in RYFT is off until the
    /// user asks for the file's version.
    @Test func planStates() {
        let bundle = ImportMockData.bundle(ImportMockData.plans)
        var long = bundle
        long.plans[0].days = (1...9).map { ImportedDay(number: $0, name: "Day \($0)", exercises: []) }
        let refused = ImportSelection(bundle: long, today: ImportMockData.day(2026, 4, 28), hasEnrollment: false)
        #expect(refused.plans.first?.state == .tooManyDays(9))
        #expect(refused.activePlan == nil && refused.importedPlans.isEmpty)
        var existing = ImportSelection(bundle: bundle, today: ImportMockData.day(2026, 4, 28), hasEnrollment: false)
        existing.markExisting([true])
        #expect(existing.plans.first == ImportSelection.PlanChoice(isOn: false, state: .alreadyInRYFT(replace: false)))
        #expect(existing.activePlan == nil)
        existing.setPlan(0, on: true)
        #expect(existing.plans.first?.isOn == false) // only "Replace with the file's version" turns it on
        existing.replaceExisting(0)
        #expect(existing.plans.first == ImportSelection.PlanChoice(isOn: true, state: .alreadyInRYFT(replace: true)))
    }

    /// The range presets and workouts in the future, on a fixed "today".
    @Test func rangesCountWorkouts() {
        let bundle = ImportMockData.bundle(ImportMockData.workouts)
        let today = ImportMockData.day(2026, 4, 28)
        var selection = ImportSelection(bundle: bundle, today: today, hasEnrollment: true)
        #expect(selection.sessions(in: bundle, today: today, zone: zone).count == 10)
        selection.preset = .last3Months // from 28 Jan
        #expect(selection.sessions(in: bundle, today: today, zone: zone).count == 10)
        selection.preset = .custom
        selection.from = ImportMockData.day(2026, 4, 1)
        selection.to = ImportMockData.day(2026, 4, 30)
        #expect(selection.sessions(in: bundle, today: today, zone: zone).count == 4)
        let earlier = ImportMockData.day(2026, 4, 14)
        selection.preset = .allTime
        #expect(selection.sessions(in: bundle, today: earlier, zone: zone).count == 8) // 20 and 27 Apr are in the future
        #expect(ImportSelection.futureSessions(in: bundle, today: earlier) == 2)
        #expect(ImportSelection.performedSets(in: Array(bundle.sessions.prefix(1))) == 8) // one of 9 skipped
    }

    // MARK: Step 4

    func mapped(enrolled: Bool = false) async -> ImportFlowModel {
        let model = flow(enrolled: enrolled)
        await model.receive(demoFiles)
        model.continueFromDetected()
        model.path.append(.map)
        await model.prepareMapping()
        return model
    }

    /// Demo's files: one likely match to check, one exercise the library lacks, the rest matched. Both block, the
    /// bodyweight question never does.
    @Test func demoFilesMapWithOneCheckAndOneNew() async throws {
        let model = await mapped()
        let mapping = try #require(model.mapping)
        #expect(model.libraryState == .ready)
        #expect(mapping.checkCount == 1)
        #expect(mapping.newCount == 1)
        #expect(mapping.leftToCheck == 2)
        #expect(mapping.likelyChecks.count == 1)
        let check = try #require(mapping.rows.first { if case .check = $0.decision { true } else { false } })
        #expect(check.source.name == "Leg Press Wide")
        #expect(mapping.exercise(for: check)?.slug == "leg-press")
        let new = try #require(mapping.rows.first { $0.draft != nil })
        #expect(new.source.name == "Nordic Curl")
        #expect(mapping.status(of: new) == .new(ready: false))
        // Every other row is matched without a tap.
        #expect(mapping.rows.filter { if case .matched = $0.decision { true } else { false } }.count == mapping.rows.count - 2)
    }

    /// Accept, choose the muscle, answer: Continue opens; VoiceOver hears each row resolve.
    @Test func resolvingRowsOpensContinue() async throws {
        let model = await mapped()
        let mapping = try #require(model.mapping)
        let new = try #require(mapping.rows.first { $0.draft != nil })
        model.acceptLikely()
        #expect(model.mapping?.leftToCheck == 1)
        #expect(spoken.lines.last == "1 match accepted")
        model.setMuscle(new.id, .hamstrings)
        #expect(model.mapping?.leftToCheck == 0)
        #expect(spoken.lines.last == "Nordic Curl, now matched. 0 left to check.")
        model.continueFromMap()
        #expect(model.path.last == .preview)
    }

    /// The bodyweight question (design §5): `+20` on dips is asked once, as a bodyweight exercise with two options
    /// (20 kg isn't a plausible body weight), "Added weight" pre-selected; it sits in "Needs your attention" until a
    /// tap, and never blocks.
    @Test func bodyweightQuestion() async throws {
        let model = await mapped()
        let mapping = try #require(model.mapping)
        let dips = try #require(mapping.rows.first { $0.source.plusLoads != nil })
        #expect(dips.source.name == "Dips")
        #expect(mapping.rows.filter { $0.source.plusLoads != nil }.count == 1)
        #expect(mapping.loadType(of: dips) == .bodyweight)
        #expect(mapping.bodyweightOptions(dips) == [.addedWeight, .ignore])
        #expect(mapping.bodyweightAnswer(dips) == .addedWeight)
        #expect(mapping.isQuestionOpen(dips) && !mapping.blocks(dips))
        #expect(mapping.attention.contains(dips))
        model.answer(dips.id, .addedWeight)
        let answered = try #require(model.mapping?.row(dips.id))
        #expect(model.mapping?.isQuestionOpen(answered) == false)
        #expect(model.mapping?.attention.contains(answered) == false)
    }

    /// Options follow the matched exercise's load type: a loaded exercise gets two, time and distance none.
    @Test func bodyweightOptionsByLoadType() async throws {
        let model = await mapped()
        let dips = try #require(model.mapping?.rows.first { $0.source.plusLoads != nil })
        model.choose(dips.id, MockTrain.bench) // a loaded exercise, by the user's pick
        let loaded = try #require(model.mapping?.row(dips.id))
        #expect(model.mapping?.status(of: loaded) == .yourChoice)
        #expect(model.mapping?.bodyweightOptions(loaded) == [.addedWeight, .ignore])
        model.choose(dips.id, MockTrain.plank) // time
        let timed = try #require(model.mapping?.row(dips.id))
        #expect(model.mapping?.bodyweightOptions(timed) == [])
        #expect(model.mapping?.dropsPlusLoad(timed) == true)
        model.skip(dips.id)
        let skipped = try #require(model.mapping?.row(dips.id))
        #expect(model.mapping?.isQuestionOpen(skipped) == false)
    }

    /// A plausible uniform `+N` offers "Body weight" and pre-selects it.
    @Test func plausibleBodyWeightIsTheDefault() throws {
        let plus = try #require(PlusLoadSummary(kilograms: [75, 75, 75]))
        #expect(BodyweightAnswer.options(for: .bodyweight, plus: plus) == [.addedWeight, .bodyWeight, .ignore])
        #expect(BodyweightAnswer.defaultAnswer(for: .bodyweight, plus: plus) == .bodyWeight)
    }

    /// Going back to step 3 and on again keeps every decision by key.
    @Test func decisionsSurviveGoingBack() async throws {
        let model = await mapped()
        let new = try #require(model.mapping?.rows.first { $0.draft != nil })
        model.setMuscle(new.id, .hamstrings)
        model.acceptLikely()
        await model.prepareMapping()
        #expect(model.mapping?.leftToCheck == 0)
    }

    /// M5: offline with nothing cached, no partial matching.
    @Test func noLibraryNoMatching() async {
        let api = MockPlatformAPI()
        api.failure = URLError(.notConnectedToInternet)
        let library = TrainLibrary(store: TrainStore(inMemory: true), remote: { api }, restore: false)
        let model = flow(library: library)
        await model.receive(demoFiles)
        model.continueFromDetected()
        await model.prepareMapping()
        #expect(model.libraryState == .unavailable)
        #expect(model.mapping == nil)
    }

    /// The choices go to the builder as library exercises, a new one under its derived id, and are remembered the
    /// same way (never per tap).
    @Test func decisionsForTheBuilder() async throws {
        let model = await mapped()
        let new = try #require(model.mapping?.rows.first { $0.draft != nil })
        model.acceptLikely()
        model.setMuscle(new.id, .hamstrings)
        let decisions = try #require(model.decisions())
        #expect(decisions.account == "account-a")
        #expect(decisions.zone == zone)
        #expect(decisions.plans == [ImportPlanChoice(included: true, replaceExisting: false)])
        #expect(decisions.enrolPlanIndex == 0)
        #expect(decisions.history.included && decisions.history.from == nil)
        let custom = try #require(decisions.exercises[new.id]?.target)
        let derived = ImportCustomExercise.id(account: "account-a", source: .alphaProgression, key: new.id)
        guard case let .custom(exercise) = custom else {
            Issue.record("a new row is a custom exercise")
            return
        }
        #expect(exercise.id == derived)
        #expect(exercise.primaryMuscles == [.hamstrings])
        #expect(exercise.loadType == .bodyweight)
        let remembered = try #require(model.mapping?.rememberedChoices(account: "account-a", source: .alphaProgression))
        #expect(remembered[new.id]?.exerciseID == derived)
        #expect(!ImportMappingStore(persistence: store) { "account-a" }.hasEntries) // nothing saved before Import
    }

    // MARK: Step 5

    /// A rebuild keeps the user's toggles; workouts the earlier build didn't offer start at their default.
    @Test func rebuildKeepsToggles() {
        let build = ImportMockData.build()
        let duplicate = build.sessions[1].id
        let first = build.sessions[0].id
        var included = build.defaultIncluded
        included.insert(duplicate)
        included.remove(first)
        #expect(ImportFlowModel.toggles(after: build, previous: build, included: included) == included)
        #expect(ImportFlowModel.toggles(after: build, previous: nil, included: included) == build.defaultIncluded)
        #expect(!build.defaultIncluded.contains(duplicate)) // duplicates start off
    }

    /// Step 5's numbers and the Import button's words.
    @Test func previewWords() {
        let build = ImportMockData.build()
        let totals = build.totals(including: build.defaultIncluded)
        #expect(ImportPreviewSummary.importTitle(totals) == "Import 1 plan and \(totals.sessions) workouts")
        #expect(ImportPreviewSummary.subline(totals, duplicatesChecked: true)?.contains("looks like one you already logged") == true)
        #expect(ImportPreviewSummary.subline(totals, duplicatesChecked: false)?.contains("already logged") != true)
    }

    // MARK: Cancel

    /// Step 1 closes at once; steps 2 to 5 ask first; Discard forgets everything.
    @Test func cancelAsksFromStepTwo() async {
        var closed: [ImportFlowModel.Finish] = []
        let model = flow()
        model.onFinish = { closed.append($0) }
        model.cancel()
        #expect(closed == [.close])
        await model.receive(demoFiles)
        model.cancel()
        #expect(model.confirmsDiscard)
        #expect(closed.count == 1)
        model.discard()
        #expect(model.files.isEmpty && closed == [.close, .close])
    }
}
