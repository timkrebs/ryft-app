import BackgroundTasks
import Foundation
import UIKit

/// Work the system runs for us, and the app's own background time:
/// - `BGAppRefreshTask` (every ~2 h when iOS allows): a background sync through the coordinator.
/// - `BGProcessingTask` "backfill": the rest of an import the app was left during (network
///   required; power too when more than `backfillPowerThreshold` is left).
/// - `BGProcessingTask` (nightly, on power): compacting the read-model cache.
/// - Going to the background: the page in flight finishes in a `beginBackgroundTask`.
/// - The phone unlocked: a sync that found HealthKit locked runs again.
/// The identifiers must match Info.plist → `BGTaskSchedulerPermittedIdentifiers`.
enum BackgroundWork {
    static let refreshTaskID = "dev.timkrebs.ryft.refresh"
    static let compactionTaskID = "dev.timkrebs.ryft.compact"
    static let backfillTaskID = "dev.timkrebs.ryft.backfill"

    /// Above this much left, the backfill waits for power.
    static let backfillPowerThreshold = 10_000_000

    /// Before launch finishes (App.init). `backlogBytes` is `SyncService.backlogBytes`. `expired`: the refresh
    /// task's time ran out; work `afterRefresh` started outside its own task stops there (the activity uploads).
    /// `settled`: the read-model writes submitted so far are readable (`Repository.settledBeforeCompletion`, waited for
    /// at most 2 s, then only the batch in progress); each task completes after it, so the widget and Today are current
    /// before iOS suspends the app, and no save is open then (ADR 0013, 0018). `compact` returns once its write
    /// committed, after 2 s at most, and when cancelled (the task's expiry).
    @MainActor
    static func register(coordinator: SyncCoordinator, backlogBytes: @escaping @MainActor () -> Int?,
                         afterRefresh: @escaping @MainActor () async -> Void = {},
                         expired: @escaping @MainActor () -> Void = {},
                         settled: @escaping @MainActor () async -> Void = {},
                         compact: @escaping @MainActor () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            scheduleRefresh()
            Task { @MainActor in
                runRefresh(task, coordinator: coordinator, afterRefresh: afterRefresh, expired: expired, settled: settled)
            }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backfillTaskID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            Task { @MainActor in
                await runBackfill(task, coordinator: coordinator, backlogBytes: backlogBytes, settled: settled)
            }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: compactionTaskID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            scheduleCompaction()
            Task { @MainActor in runCompaction(task, compact: compact, settled: settled) }
        }
    }

    /// The compaction task's run: the compaction, then the completion once `settled` returns. At expiry both stop (the
    /// write itself goes on, and lands when the app runs next if it must): the task completes while there's still
    /// time. Returns the completion's task (tests).
    @MainActor
    @discardableResult
    static func runCompaction(_ task: BackgroundTaskHandle, compact: @escaping @MainActor () async -> Void,
                              settled: @escaping @MainActor () async -> Void = {}) -> Task<Void, Never> {
        let work = Task { @MainActor in await compact() }
        let completion = Task { @MainActor in
            await work.value
            await settled()
            task.setTaskCompleted(success: !work.isCancelled)
        }
        task.expirationHandler = {
            work.cancel()
            completion.cancel()
        }
        return completion
    }

    /// The refresh task's run: the sync, then what follows from it (tonight's bedtime moves with the day's strain),
    /// then the completion once `settled` returns. At expiry the run stops, and so does the wait for the writes: the
    /// task completes while there's still time. Returns the completion's task (tests).
    @MainActor
    @discardableResult
    static func runRefresh(_ task: BackgroundTaskHandle, coordinator: SyncCoordinator,
                           afterRefresh: @escaping @MainActor () async -> Void = {},
                           expired: @escaping @MainActor () -> Void = {},
                           settled: @escaping @MainActor () async -> Void = {}) -> Task<Void, Never> {
        let work = Task {
            let outcome = await coordinator.run(.background)
            await afterRefresh()
            return outcome
        }
        let completion = Task { @MainActor in
            let outcome = await work.value
            await settled()
            task.setTaskCompleted(success: !outcome.cancelled && outcome.error == nil)
        }
        task.expirationHandler = {
            work.cancel()
            completion.cancel()
            Task { await coordinator.cancel() }
            Task { @MainActor in expired() }
        }
        return completion
    }

    static func scheduleRefresh(now: Date = .now) {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = now.addingTimeInterval(2 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func scheduleCompaction(now: Date = .now) {
        let req = BGProcessingTaskRequest(identifier: compactionTaskID)
        req.earliestBeginDate = nextCompaction(after: now)
        req.requiresExternalPower = true
        req.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(req)
    }

    /// The next 03:00 local after `now`.
    static func nextCompaction(after now: Date, calendar: Calendar = .current) -> Date {
        let today3 = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: now) ?? now
        return today3 > now ? today3 : calendar.date(byAdding: .day, value: 1, to: today3) ?? today3
    }

    // MARK: backfill

    /// As soon as iOS allows: network required, power too above the threshold.
    static func backfillRequest(backlogBytes: Int) -> BGProcessingTaskRequest {
        let req = BGProcessingTaskRequest(identifier: backfillTaskID)
        req.requiresNetworkConnectivity = true
        req.requiresExternalPower = backlogBytes >= backfillPowerThreshold
        return req
    }

    static func scheduleBackfill(backlogBytes: Int) {
        try? BGTaskScheduler.shared.submit(backfillRequest(backlogBytes: backlogBytes))
    }

    /// Runs the backfill until it's done or the system's time is up. At expiry the run is
    /// cancelled at once (the page in flight goes again next time: uploads are
    /// idempotent), the rest is scheduled and the task completed while there's still time:
    /// the wait for `settled` stops there too.
    @MainActor
    static func runBackfill(_ task: BackgroundTaskHandle, coordinator: SyncCoordinator,
                            backlogBytes: @escaping @MainActor () -> Int?,
                            schedule: @escaping (Int) -> Void = scheduleBackfill(backlogBytes:),
                            settled: @escaping @MainActor () async -> Void = {}) async {
        let expired = ExpiryFlag()
        task.expirationHandler = {
            expired.set()
            Task { await coordinator.cancel() }
        }
        var outcome = await coordinator.run(.processing)
        // The first score's window went first: the backfill itself follows in the same task.
        while outcome.backlog, !expired.isSet, outcome.error == nil, !outcome.cancelled {
            outcome = await coordinator.run(.processing)
        }
        if let left = backlogBytes() { schedule(left) }
        // Expired (before or during the wait): the time left is for the completion, not for the writes.
        await expired.unlessExpired(Task { @MainActor in await settled() })
        task.setTaskCompleted(success: outcome.error == nil && !outcome.cancelled)
    }

    // MARK: leaving the app

    /// The app went to the background: the page being uploaded finishes (its anchor
    /// committed) inside a background task, then what's left goes to the backfill task.
    /// If the system's time runs out first, the run is cancelled (the anchor stays).
    @MainActor
    static func finishInBackground(coordinator: SyncCoordinator, app: BackgroundTaskRunning,
                                   backlogBytes: @escaping @MainActor () -> Int?,
                                   schedule: @escaping (Int) -> Void = scheduleBackfill(backlogBytes:),
                                   settled: @escaping @MainActor () async -> Void = {}) -> Task<Void, Never> {
        let token = BackgroundTaskToken(app: app)
        token.begin {
            Task { await coordinator.cancel() }
        }
        return Task { @MainActor in
            await coordinator.windDown()
            if let left = backlogBytes() { schedule(left) }
            await settled()
            token.end()
        }
    }

    // MARK: unlock

    /// A sync that found HealthKit locked runs again as soon as protected data is
    /// available (the phone unlocked), also in a background launch.
    @MainActor
    static func resumeOnUnlock(coordinator: SyncCoordinator, isWaiting: @escaping @MainActor () -> Bool) {
        guard unlockObserver == nil else { return }
        unlockObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard isWaiting() else { return }
                Task { await coordinator.run(.healthKit) }
            }
        }
    }

    @MainActor private static var unlockObserver: NSObjectProtocol?
}

/// `UIApplication`'s background time, behind a seam for tests.
@MainActor
protocol BackgroundTaskRunning: AnyObject {
    func beginBackgroundTask(withName taskName: String?,
                             expirationHandler handler: (@MainActor @Sendable () -> Void)?) -> UIBackgroundTaskIdentifier
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier)
}

extension UIApplication: BackgroundTaskRunning {}

/// A `BGTask`, behind a seam for tests.
@MainActor
protocol BackgroundTaskHandle: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGTask: BackgroundTaskHandle {}

/// One background task, ended exactly once (by the work or by the expiration).
@MainActor
private final class BackgroundTaskToken {
    private let app: BackgroundTaskRunning
    private var id = UIBackgroundTaskIdentifier.invalid

    init(app: BackgroundTaskRunning) { self.app = app }

    func begin(onExpiry: @escaping @MainActor () -> Void) {
        id = app.beginBackgroundTask(withName: "Finish the sync") { [weak self] in
            onExpiry()
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        app.endBackgroundTask(id)
        id = .invalid
    }
}

/// Set from the expiration handler (any thread), read by the work; cancels the waits it was given.
private final class ExpiryFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    private var waits: [Task<Void, Never>] = []
    var isSet: Bool { lock.withLock { value } }

    func set() {
        let waiting = lock.withLock { () -> [Task<Void, Never>] in
            value = true
            defer { waits = [] }
            return waits
        }
        for wait in waiting { wait.cancel() }
    }

    /// Awaits `wait`, cancelled at the expiry (at once if it came already).
    func unlessExpired(_ wait: Task<Void, Never>) async {
        let expired = lock.withLock { () -> Bool in
            if !value { waits.append(wait) }
            return value
        }
        if expired { wait.cancel() }
        await wait.value
    }
}
