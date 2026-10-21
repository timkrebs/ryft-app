import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

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

    /// Before launch finishes (App.init). `backlogBytes` is `SyncService.backlogBytes`.
    @MainActor
    static func register(coordinator: SyncCoordinator, backlogBytes: @escaping @MainActor () -> Int?,
                         compact: @escaping @MainActor () -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            scheduleRefresh()
            let work = Task { await coordinator.run(.background) }
            task.expirationHandler = {
                work.cancel()
                Task { await coordinator.cancel() }
            }
            Task {
                let outcome = await work.value
                task.setTaskCompleted(success: !outcome.cancelled && outcome.error == nil)
            }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backfillTaskID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            Task { @MainActor in
                await runBackfill(task, coordinator: coordinator, backlogBytes: backlogBytes)
            }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: compactionTaskID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            scheduleCompaction()
            Task { @MainActor in
                compact()
                task.setTaskCompleted(success: true)
            }
        }
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

    /// Runs the backfill until it's done or the system's time is up (then the page in
    /// flight finishes and the rest is scheduled again).
    @MainActor
    static func runBackfill(_ task: BackgroundTaskHandle, coordinator: SyncCoordinator,
                            backlogBytes: @escaping @MainActor () -> Int?,
                            schedule: @escaping (Int) -> Void = scheduleBackfill(backlogBytes:)) async {
        let expired = ExpiryFlag()
        task.expirationHandler = {
            expired.set()
            Task { await coordinator.windDown() }
        }
        var outcome = await coordinator.run(.processing)
        // The first score's window went first: the backfill itself follows in the same task.
        while outcome.backlog, !expired.isSet, outcome.error == nil, !outcome.cancelled {
            outcome = await coordinator.run(.processing)
        }
        if let left = backlogBytes() { schedule(left) }
        task.setTaskCompleted(success: outcome.error == nil && !outcome.cancelled)
    }

    // MARK: leaving the app

    /// The app went to the background: the page being uploaded finishes (its anchor
    /// committed) inside a background task, then what's left goes to the backfill task.
    /// If the system's time runs out first, the run is cancelled (the anchor stays).
    @MainActor
    static func finishInBackground(coordinator: SyncCoordinator, app: BackgroundTaskRunning,
                                   backlogBytes: @escaping @MainActor () -> Int?,
                                   schedule: @escaping (Int) -> Void = scheduleBackfill(backlogBytes:)) -> Task<Void, Never> {
        let token = BackgroundTaskToken(app: app)
        token.begin {
            Task { await coordinator.cancel() }
        }
        return Task { @MainActor in
            await coordinator.windDown()
            if let left = backlogBytes() { schedule(left) }
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

extension BGProcessingTask: BackgroundTaskHandle {}

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

/// Set from the expiration handler (any thread), read by the work.
private final class ExpiryFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// User-facing timers as local notifications on a `UNCalendarNotificationTrigger`
/// (e.g. the bedtime reminder): daily at a local time, until cancelled.
@MainActor
final class ReminderScheduler {
    private let notifier: Notifier

    init(notifier: Notifier) {
        self.notifier = notifier
    }

    static func dailyTrigger(hour: Int, minute: Int) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
    }

    /// Replaces any reminder with the same `id`.
    func scheduleDaily(id: String, hour: Int, minute: Int, title: String, body: String,
                       category: String? = nil) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        notifier.removePending(ids: [id])
        try await notifier.add(UNNotificationRequest(identifier: id, content: content,
                                                     trigger: Self.dailyTrigger(hour: hour, minute: minute)))
    }

    func cancel(id: String) {
        notifier.removePending(ids: [id])
    }
}
