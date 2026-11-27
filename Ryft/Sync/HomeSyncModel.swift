import Foundation
import Observation

typealias SyncTriggerSource = AnalyticsSyncTrigger

@MainActor
@Observable
final class HomeSyncModel {
    private let app: AppState
    private let upload: SyncService
    private let coordinator: SyncCoordinator
    private var clock: AppClock { app.env.clock }

    private var healthAccess: HealthAccess = .unknown
    private var clockRevision = 0
    @ObservationIgnored private var foregroundBinding: AccountBinding?
    @ObservationIgnored private var foregroundCheck: Task<Void, Never>?

    private struct Run {
        let spinner: Task<(Task<SyncCoordinator.Outcome, Never>?, Bool), Never>
        let completion: Task<AnalyticsSyncStatus, Never>
    }

    @ObservationIgnored private var active: Run?
    @ObservationIgnored private var generation = 0

    init(state: AppState, sync: SyncService, coordinator: SyncCoordinator) {
        app = state
        upload = sync
        self.coordinator = coordinator
        state.forgetsAccountState { [weak self] in self?.reset() }
    }

    var state: SyncIndicatorState {
        let now = now
        let localUpload = app.isDemo ? app.demoSyncAt : app.env.settings.lastSync
        return .resolve(.init(uploading: app.isDemo ? app.demoSyncInFlight : upload.isPostingPage,
                              lastUpload: localUpload,
                              uploadFailure: app.isDemo ? nil : upload.uploadFailure,
                              healthAccessMissing: healthAccessMissing, status: app.syncStatus,
                              scoringWaitStartedAt: scoringWaitStartedAt,
                              todayReloaded: app.todayReloadedSinceLastUpload,
                              online: app.isDemo || app.env.connectivity.isOnline, now: now))
    }

    var lastSync: Date? { app.appleHealthLastSync }
    var canSync: Bool { app.hasDataSource }

    var now: Date {
        _ = clockRevision
        return clock.now()
    }

    private var healthAccessMissing: Bool {
        !app.isDemo && (healthAccess == .notAsked || healthAccess == .unavailable || upload.healthAccessDenied)
    }

    /// A status asked for inside the platform's cache window cannot answer a page that queued scores.
    var hasUnconfirmedUpload: Bool { scoringWaitStartedAt != nil }

    private var scoringWaitStartedAt: Date? {
        app.isDemo ? nil : upload.pendingUploadReceipt?.at
    }

    var nextStateChange: Date? {
        let now = now
        let hasSyncTime = lastSync != nil || app.syncStatus?.sources?.contains(where: { $0.lastSyncAt != nil }) == true
        let nextMinute = hasSyncTime ? now.addingTimeInterval(60 - now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)) : nil
        let dates = [scoringWaitStartedAt?.addingTimeInterval(SyncIndicatorState.scoringLimit),
                     app.syncStatus?.scoresPendingSince?.addingTimeInterval(SyncIndicatorState.scoringLimit),
                     lastSync?.addingTimeInterval(SyncIndicatorState.freshnessLimit), nextMinute]
        return dates.compactMap { $0 }.filter { $0 > now }.min()
    }

    func updateState(at deadline: Date?) async {
        guard let deadline else { return }
        do {
            try await clock.sleep(for: .seconds(deadline.timeIntervalSince(now)))
            try Task.checkCancellation()
            clockRevision += 1
        } catch {}
    }

    var sources: [SyncSource] {
        let sources = app.syncStatus?.sources ?? []
        let apple = sources.first { $0.source == "healthkit" }
        let failed = healthAccessMissing || (!app.isDemo && upload.uploadFailure == .server)
        let health = SyncSource(source: "healthkit", lastSyncAt: lastSync,
                                status: failed ? .error : apple?.status ?? .ok,
                                reason: apple?.reason)
        return [health] + sources.filter { $0.source == "garmin" || $0.source == "suunto" }
    }

    var scoresTakingLonger: Bool {
        let start = app.syncStatus?.scoresPendingSince ?? scoringWaitStartedAt ?? upload.scoringWaitStart
        return start.map { now.timeIntervalSince($0) >= SyncIndicatorState.scoringLimit } ?? false
    }

    /// The scene became active (or bootstrap made the account eligible after it did, `checkedSince`: when its onboarding
    /// check began, whose status read this one may reuse). More than 5 minutes since the last sync, or none: the quiet
    /// `auto_foreground` sync. Otherwise one status read, the "once at the next foreground" after a scoring wait.
    func enterForeground(eligible: Bool = true, checkedSince: Date? = nil) async {
        await coordinator.enterForeground()
        guard eligible, app.hasDataSource, !app.isDemo else { return }
        if let foregroundCheck { return await foregroundCheck.value }
        guard active == nil else { return }
        let binding = AccountBinding(app.env)
        if checkedSince != nil, foregroundBinding == binding { return }
        foregroundBinding = binding
        let generation = generation
        let check = Task {
            let started = checkedSince ?? now
            let access = await app.env.health.accessStatus()
            guard !Task.isCancelled, binding.isCurrent(in: app.env) else { return }
            healthAccess = access
            guard app.env.connectivity.isOnline else { return }
            let alreadyRead = app.syncStatusAskedAt.map { $0 >= started } ?? false
            if let pending = scoringWaitStartedAt, now.timeIntervalSince(pending) >= SyncIndicatorState.scoringLimit {
                // A previous wait expired. Give it the foreground read even if a new upload is due.
                await coordinator.refreshHomeStatus(alreadyRead: alreadyRead)
            } else if let lastSync, now.timeIntervalSince(lastSync) <= SyncIndicatorState.foregroundInterval {
                await coordinator.refreshHomeStatus(alreadyRead: alreadyRead)
                return
            }
            if lastSync.map({ now.timeIntervalSince($0) > SyncIndicatorState.foregroundInterval }) ?? true {
                await sync(trigger: .autoForeground)
            }
        }
        foregroundCheck = check
        await check.value
        if generation == self.generation { foregroundCheck = nil }
    }

    func resumeHeldSync() async {
        guard active == nil, !(await coordinator.hasWork) else { return }
        await sync(trigger: .autoForeground)
    }

    /// Pulls stop at the spinner cap. Button and foreground callers can wait for the full shared outcome.
    @discardableResult
    func sync(trigger: SyncTriggerSource) async -> AnalyticsSyncStatus? {
        let run = active ?? start(trigger)
        if trigger == .homescreenPullToRefresh {
            _ = await run.spinner.value
            return nil
        }
        return await run.completion.value
    }

    private func start(_ trigger: SyncTriggerSource) -> Run {
        let previous = state
        let started = clock.uptime()
        let binding = AccountBinding(app.env)
        let generation = generation
        let spinner = Task<(Task<SyncCoordinator.Outcome, Never>?, Bool), Never> {
            let joining = await coordinator.hasWork
            guard binding.isCurrent(in: app.env), !Task.isCancelled else {
                return (nil as Task<SyncCoordinator.Outcome, Never>?, false)
            }
            if !joining {
                let token: AnalyticsSyncPreviousState
                switch previous {
                case .upToDate: token = .upToDate
                case .error: token = .error
                case .stale, .syncing: token = .stale
                }
                app.env.analytics.track(.syncTriggered(trigger, previousState: token))
            }
            let run = await app.pullToRefreshRun(coordinator: coordinator,
                                                homeTrigger: trigger == .autoForeground ? .appActive : .userInitiated)
            return (run, !joining)
        }
        let completion = Task {
            let (run, track) = await spinner.value
            let duration = AnalyticsSyncDuration(clock.uptime() - started)
            let outcome = await run?.value
            // The run is over for this model whatever follows; a reset (another account) already cleared it.
            if generation == self.generation { active = nil }
            guard generation == self.generation, binding.isCurrent(in: app.env) else { return AnalyticsSyncStatus.failed }
            let status: AnalyticsSyncStatus
            if let outcome {
                if outcome.cancelled || outcome.error != nil { status = .failed }
                else if outcome.waitingForUnlock { status = .deferred }
                else if outcome.scoringTimedOut { status = .partial }
                else { status = .success }
            } else {
                status = .skipped
            }
            if track {
                let count = app.syncStatus?.sources?.filter { $0.source != "healthkit" }.count ?? 0
                app.env.analytics.track(.syncCompleted(trigger, status: status, duration: duration,
                                                       connectedProviders: .init(count: count)))
            }
            return status
        }
        let run = Run(spinner: spinner, completion: completion)
        active = run
        return run
    }

    private func reset() {
        generation += 1
        active?.spinner.cancel()
        active = nil
        foregroundCheck?.cancel()
        foregroundCheck = nil
        foregroundBinding = nil
        healthAccess = .unknown
    }
}
