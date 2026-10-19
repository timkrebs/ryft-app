import BackgroundTasks
import Foundation
import UserNotifications

/// Time-scheduled work the system runs for us:
/// - `BGAppRefreshTask` (every ~2 h when iOS allows): a background sync through the coordinator.
/// - `BGProcessingTask` (nightly, on power): compacting the read-model cache.
/// The identifiers must match Info.plist → `BGTaskSchedulerPermittedIdentifiers`.
enum BackgroundWork {
    static let refreshTaskID = "dev.timkrebs.ryft.refresh"
    static let compactionTaskID = "dev.timkrebs.ryft.compact"

    /// Before launch finishes (App.init).
    static func register(coordinator: SyncCoordinator, compact: @escaping @MainActor () -> Void) {
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
