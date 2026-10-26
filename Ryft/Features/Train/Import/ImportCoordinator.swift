import Foundation
import Observation

/// One import flow for the whole app (ui.md §2, §3): My Plans, Profile → Data and "Open in" all open the same cover.
/// Holds an opened file in memory while it can't be shown yet (signed out, a workout running, another import
/// uploading) and never anywhere else: if the app ends meanwhile, the file is gone and Files still has it.
@MainActor
@Observable
final class ImportCoordinator {
    /// The flow on screen (a full-screen cover over the tabs); nil: none.
    var flow: ImportFlowModel?
    /// E10: a file opened with `train.import` off. Nothing was read.
    var showsUnavailable = false
    /// E8: a file arrived while another import is being set up; the alert decides.
    var replacement: [ImportFileAccess.Loaded]?
    /// E7 and E9: a file waiting for the workout (or the upload) to finish.
    private(set) var waitingFiles: [ImportFileAccess.Loaded]?
    /// Why it waits.
    private(set) var waitingFor: Waiting?

    enum Waiting: Equatable, Sendable {
        /// E7: a workout is running.
        case workout
        /// E9: an earlier import is still uploading.
        case upload
    }
    /// E6: opened while signed out; shown after sign-in.
    private(set) var signedOutFiles: [ImportFileAccess.Loaded]?

    /// A workout is running (`TrainCoordinator.active`): never interrupt it (E7). Set by the app.
    var isWorkoutActive: @MainActor () -> Bool = { false }

    private let env: AppEnvironment
    private let library: TrainLibrary
    private let mappings: ImportMappingStore
    /// The account's import job: step 6, the resume row, and "one import at a time".
    let uploader: TrainImportUploader
    /// Shows the Strain tab (where the cover belongs, ui.md §3.3).
    private let showStrain: @MainActor () -> Void
    /// Opens a Train screen on Strain (Open plan, Open history).
    private let openRoute: @MainActor (TrainRoute) -> Void

    init(env: AppEnvironment, library: TrainLibrary, uploader: TrainImportUploader,
         showStrain: @escaping @MainActor () -> Void, openRoute: @escaping @MainActor (TrainRoute) -> Void) {
        self.env = env
        self.library = library
        self.uploader = uploader
        mappings = ImportMappingStore(env: env)
        self.showStrain = showStrain
        self.openRoute = openRoute
    }

    /// `train.import`: with it off no entry point shows and an opened file isn't read.
    var isEnabled: Bool { env.flags.isOn(.trainImport) }
    private var hasAccount: Bool { env.isDemo || env.auth.isSignedIn }

    /// The name of the file waiting (E7, E9), for the quiet row on My Plans and Profile → Data.
    var waitingFileName: String? { waitingFiles?.first?.name }
    /// "Open now" on the waiting row: only once no workout runs and no import uploads.
    var canOpenWaitingFile: Bool { waitingFiles != nil && !isWorkoutActive() && !uploader.hasUnfinishedJob }
    /// The resume row (E3) shows on My Plans and Profile → Data: a job that isn't done, or done and not seen yet.
    var showsResumeRow: Bool { isEnabled && uploader.status.map { !$0.resultSeen } ?? false }
    /// The sign-in screen's line "Your file is ready. Sign in to continue." (E6).
    var hasFileForSignIn: Bool { signedOutFiles != nil && !hasAccount }

    // MARK: Entry points

    /// My Plans → New plan → Import from file, Profile → Data → Import training data: step 1, or step 6 of the job
    /// while one is unfinished or its result unseen (a second import never starts, ui.md §8.2).
    func start() {
        guard isEnabled, flow == nil else { return }
        let flow = makeFlow()
        if let job = uploader.status, !job.resultSeen {
            flow.path = [.result]
            flow.blockedByRunningJob = !job.isFinished
        }
        self.flow = flow
    }

    /// The resume row: step 6 of the job.
    func resume() {
        guard isEnabled, flow == nil, uploader.status != nil else { return }
        let flow = makeFlow()
        flow.path = [.result]
        self.flow = flow
    }

    /// "Dismiss" on a finished row the user never opened.
    func dismissFinished() {
        uploader.markResultSeen()
    }

    /// "Open in RYFT" (`onOpenURL` with a file URL). Returns false for anything that isn't a file.
    @discardableResult
    func open(_ urls: [URL]) async -> Bool {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return false }
        // Flags are per account: signed out, the file is read (no network, no account needed) and waits (E6).
        guard !hasAccount || isEnabled else {
            // E10: nothing is read.
            showsUnavailable = true
            return true
        }
        let loaded = await ImportFileAccess.load(files)
        await receive(loaded)
        return true
    }

    /// Files already in memory, routed by what the app is doing (ui.md §3.3).
    func receive(_ loaded: [ImportFileAccess.Loaded]) async {
        guard !loaded.isEmpty else { return }
        if !hasAccount {
            signedOutFiles = loaded
            return
        }
        guard isEnabled else {
            // E10 after a sign-in: this account doesn't import yet; the file is dropped (Files still has it).
            showsUnavailable = true
            return
        }
        if isWorkoutActive() || uploader.hasUnfinishedJob {
            waitingFiles = loaded
            waitingFor = isWorkoutActive() ? .workout : .upload
            return
        }
        if let flow, flow.step != .result {
            replacement = loaded
            return
        }
        await present(loaded)
    }

    /// E8 → Replace: the import being set up is dropped (nothing of it was stored).
    func replaceCurrent() async {
        guard let loaded = replacement else { return }
        replacement = nil
        flow = nil
        await present(loaded)
    }

    /// E8 → Keep current: the new file is dropped; Files still has it.
    func keepCurrent() {
        replacement = nil
    }

    /// "Open now" on the waiting row (E7, E9).
    func openWaitingFile() async {
        guard let loaded = waitingFiles, canOpenWaitingFile else { return }
        waitingFiles = nil
        waitingFor = nil
        flow = nil
        await receive(loaded)
    }

    /// Signed in, signed out or another account. A file opened while signed out is shown now; anything of a previous
    /// account (a flow, a waiting file) is forgotten.
    func accountChanged(signedIn: Bool) async {
        flow = nil
        replacement = nil
        waitingFiles = nil
        waitingFor = nil
        guard signedIn, let loaded = signedOutFiles else { return }
        signedOutFiles = nil
        await receive(loaded)
    }

    // MARK: Private

    private func present(_ loaded: [ImportFileAccess.Loaded]) async {
        showStrain()
        let flow = makeFlow()
        // Step 1 is skipped: the user already picked. Back goes to it, where "Add another file" is.
        flow.path = [.detected]
        self.flow = flow
        await flow.receive(loaded)
    }

    private func makeFlow() -> ImportFlowModel {
        let env = env
        var deps = ImportFlowModel.Dependencies(
            library: library, mappings: mappings, uploader: uploader, clock: env.clock, zone: .current,
            account: { env.isDemo ? ImportMappingStore.demoAccount : env.auth.accountID },
            isOnline: { env.connectivity.isOnline })
        #if DEBUG
        if let names = ImportDemoFiles.requested {
            deps.scriptedFiles = { ImportDemoFiles.load(names, now: env.clock.now()) }
        }
        #endif
        let flow = ImportFlowModel(deps: deps)
        flow.onFinish = { [weak self] how in self?.finish(how) }
        flow.waitingFileName = { [weak self] in self?.waitingFor == .upload ? self?.waitingFileName : nil }
        flow.openWaitingFile = { [weak self] in await self?.openWaitingFile() }
        return flow
    }

    private func finish(_ how: ImportFlowModel.Finish) {
        flow = nil
        switch how {
        case .close: break
        case let .openPlan(id): openRoute(.plan(id))
        case .openHistory: openRoute(.history)
        }
    }
}
