import Foundation
import Observation
import UIKit

/// Uploads a confirmed import (design §7): one job per account, stored until it's done, sent in order (custom
/// exercises one at a time, then plans and sessions in batches, then the enrolment), resumable after a relaunch.
///
/// - **Never another account:** the job is bound to the account the flow started with (or demo), and every answer is
///   dropped unless that binding is still current. Sign-out wipes it with the store.
/// - **Consent first:** `gate(.data)` (`uploadGate(for: .trainImport, write: .data)`) is asked before the first request
///   and before every batch; a held job waits, never dropped (ADR 0008).
/// - **Before the contract** (`TrainImportAPI.publishesTrainImport == false`) or with `train.import` off, nothing is
///   sent: the job is "saved on this iPhone".
@MainActor
@Observable
final class TrainImportUploader {
    /// ≤ 50 sessions and ≤ 5 plans per request (T9); halved after a `413`.
    static let sessionsPerRequest = 50
    static let plansPerRequest = 5
    /// A request body stays under the platform's 1 MiB with room for headers.
    static let maxBodyBytes = (1 << 20) - (16 << 10)
    /// A job that isn't done is removed after this long (design §7).
    static let retention: TimeInterval = 30 * 86_400

    /// What stands between the account and the import's requests (`OnboardingCoordinator.uploadGate(for:
    /// .trainImport, write:)`). **Closed until the app connects it** (ScreenModels); tests open it explicitly.
    @ObservationIgnored var gate: @MainActor (UploadWrite) -> UploadGate? = { _ in .gate(.consentRequired) }

    /// The current binding's job; nil when there's none (or nothing is signed in).
    private(set) var status: ImportJobStatus?

    @ObservationIgnored private weak var env: AppEnvironment?
    @ObservationIgnored private let library: TrainLibrary?
    @ObservationIgnored private let coordinator: SyncCoordinator?

    init(env: AppEnvironment, library: TrainLibrary? = nil, coordinator: SyncCoordinator? = nil) {
        self.env = env
        self.library = library
        self.coordinator = coordinator
    }

    /// Previews: a fixed status, nothing runs.
    static func preview(_ status: ImportJobStatus?, env: AppEnvironment? = nil) -> TrainImportUploader {
        let uploader = TrainImportUploader(env: env ?? .preview())
        uploader.status = status
        return uploader
    }

    /// The binding a flow starts with and passes to `start`: the signed-in account's id, or
    /// `ImportMappingStore.demoAccount` with demo data; nil signed out.
    var currentAccount: String? {
        guard let env else { return nil }
        return env.isDemo ? ImportMappingStore.demoAccount : env.auth.accountID
    }

    /// The job exists and isn't finished: a second import never starts (ui.md §8.2).
    var hasUnfinishedJob: Bool { status.map { !$0.isFinished } ?? false }

    /// Uploads go now: the platform takes imports and `train.import` is on. False: step 5 offers "Keep on this
    /// iPhone" (V5).
    var uploadsAvailable: Bool {
        guard let env else { return false }
        return env.api.publishesTrainImport && env.flags.isOn(.trainImport)
    }

    // MARK: the flow

    /// What the account already has (design §6): its plans with the import's derived ids, the derived sessions already
    /// there, and the sessions logged in RYFT on the import's days. Offline or on an error: `.unchecked`.
    func checkExisting(_ query: ImportExistingQuery) async -> ImportExisting {
        .unchecked
    }

    /// Import tapped: the job is stored for `account` (the flow's, `currentAccount` when it started) and the upload
    /// starts. Returns false, and stores nothing, when that account isn't the current binding any more or a job is
    /// still unfinished. Without uploads (`uploadsAvailable` false) the job is kept as "saved on this iPhone".
    @discardableResult
    func start(_ plan: ImportUploadPlan, account: String, source: ImportFormatID, zone: TimeZone,
               duplicatesChecked: Bool) async -> Bool {
        false
    }

    // MARK: triggers

    /// Continue: app active, reconnect, sign-in, the gate opening, the flag turning on. Does nothing while a pass runs.
    func resume() async {}

    /// "Retry N": the rejected and blocked items are sent again; the rest isn't resubmitted.
    func retryRejected() async {}

    /// "Import these too": the sessions the uploader's own duplicate check skipped are sent.
    func importDuplicatesFound() async {}

    /// The user saw the finished result (I3): a finished job is removed.
    func markResultSeen() {}

    /// Discard (a job that can't or shouldn't finish): removed; nothing more is sent.
    func discard() {}

    /// Signed out, another account, or the Demo data switch: the pass stops, answers in flight are dropped, and the
    /// status follows the new binding.
    func accountChanged() {}

    /// The app became active: jobs older than 30 days go, and the current one continues.
    func appBecameActive() async {}

    /// The app went to the background: the request in flight finishes inside a background task; the rest waits for
    /// the next trigger. Nil when nothing runs.
    @discardableResult
    func finishInBackground(app: BackgroundTaskRunning) -> Task<Void, Never>? { nil }
}
