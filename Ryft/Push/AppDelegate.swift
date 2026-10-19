import UIKit
import UserNotifications

/// What the delegate hands notification events to, once `RyftApp` has built them.
@MainActor
struct PushHandlers {
    let registrar: PushRegistrar
    let router: DeepLinkRouter
    let coordinator: SyncCoordinator
}

/// UIKit's half of push: APNs token callbacks, the silent refresh, and taps
/// (also the one that launched the app). Events that arrive before `handlers`
/// is set (a cold launch from a notification) wait for it.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var handlers: PushHandlers? {
        didSet { flush() }
    }

    private var waiting: [(PushHandlers) async -> Void] = []

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Before launch finishes, or the tap that launched the app is lost.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: APNs

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        perform { await $0.registrar.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        perform { $0.registrar.didFailToRegister(error) }
    }

    /// The silent push (`content-available`): refresh the day it names.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard case .refresh(let day) = PushMessage(userInfo: userInfo) else {
            completionHandler(.noData)
            return
        }
        perform { handlers in
            let outcome = await handlers.coordinator.run(.silentPush(days: [day]))
            completionHandler(outcome.error == nil && !outcome.cancelled ? .newData : .failed)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// In the foreground: a banner too, since the score is the news.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let action = response.actionIdentifier
        let message = PushMessage(userInfo: content.userInfo)
        perform { handlers in
            if action == PushCategories.syncNowAction || content.categoryIdentifier == NotificationCategory.syncStale.rawValue {
                await handlers.coordinator.run(.userInitiated)
            } else if case .alert(_, let url?) = message {
                await handlers.router.open(url)
            }
            completionHandler()
        }
    }

    // MARK: queue

    private func perform(_ work: @escaping (PushHandlers) async -> Void) {
        if let handlers {
            Task { await work(handlers) }
        } else {
            waiting.append(work)
        }
    }

    private func flush() {
        guard let handlers else { return }
        let queued = waiting
        waiting = []
        for work in queued { Task { await work(handlers) } }
    }
}
