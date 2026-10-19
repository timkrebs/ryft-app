import Foundation
import Observation
import UserNotifications

/// APNs registration with the platform (`POST` / `DELETE /v1/devices/{id}/push`).
///
/// - After the first successful sync, Today offers a pre-prompt card. "Turn on"
///   asks iOS; "Not now" hides the card for good (Profile → Notifications can
///   still ask).
/// - Once allowed, the app registers with APNs on every launch. The token,
///   environment and language go to the platform only when one of them (or the
///   account) changed since the last time.
/// - Before sign-out the registration is deleted, so the next account on this
///   phone doesn't get the previous one's notifications.
/// Everything is gated by the `push.enabled` flag.
@MainActor
@Observable
final class PushRegistrar {
    private let env: AppEnvironment

    static let firstSyncKey = "push.firstSyncDone"
    static let dismissedKey = "push.prePromptDismissed"
    static let tokenKey = "push.token"
    /// `account|token|env|locale` as last accepted by the platform.
    static let sentKey = "push.sent"

    private(set) var status: UNAuthorizationStatus = .notDetermined
    private(set) var hasSynced: Bool
    private(set) var promptDismissed: Bool
    private(set) var token: String?
    private(set) var lastError: String?

    init(env: AppEnvironment) {
        self.env = env
        hasSynced = env.defaults.bool(forKey: Self.firstSyncKey)
        promptDismissed = env.defaults.bool(forKey: Self.dismissedKey)
        token = env.defaults.string(forKey: Self.tokenKey)
    }

    private var defaults: UserDefaults { env.defaults }
    private var isEnabled: Bool { env.flags.isOn(.pushEnabled) && !env.isDemo }
    var isAllowed: Bool { status == .authorized || status == .provisional || status == .ephemeral }

    /// Today's card: after a sync, before iOS was ever asked, unless dismissed.
    var showsPrePrompt: Bool {
        isEnabled && env.auth.isSignedIn && hasSynced && status == .notDetermined && !promptDismissed
    }

    // MARK: lifecycle

    /// At launch and on every return to the app: picks up a change in Settings
    /// and re-registers, so a new token or language reaches the platform.
    func refresh() async {
        status = await env.notifier.authorizationStatus()
        env.notifier.setCategories(PushCategories.all)
        guard isEnabled, env.auth.isSignedIn, isAllowed else { return }
        env.notifier.registerForRemoteNotifications()
        await send()
    }

    /// The coordinator finished a sync; the card may show from now on.
    func syncSucceeded() {
        guard !hasSynced else { return }
        hasSynced = true
        defaults.set(true, forKey: Self.firstSyncKey)
    }

    // MARK: pre-prompt

    /// "Turn on": the system prompt, then APNs.
    func accept() async {
        dismissPrompt()
        let granted = (try? await env.notifier.requestAuthorization()) ?? false
        status = await env.notifier.authorizationStatus()
        if granted { env.notifier.registerForRemoteNotifications() }
    }

    /// "Not now".
    func dismissPrompt() {
        promptDismissed = true
        defaults.set(true, forKey: Self.dismissedKey)
    }

    // MARK: APNs callbacks

    func didRegister(deviceToken: Data) async {
        let hex = Self.hex(deviceToken)
        token = hex
        defaults.set(hex, forKey: Self.tokenKey)
        await send()
    }

    func didFailToRegister(_ error: Error) {
        lastError = error.localizedDescription
    }

    /// `POST /v1/devices/{id}/push`, unless the platform already has exactly this.
    func send() async {
        guard isEnabled, let token, let account = env.auth.accountID else { return }
        let registration = PushRegistration(token: token, env: Self.environment, locale: Self.locale())
        let key = [account, token, registration.env.rawValue, registration.locale].joined(separator: "|")
        guard defaults.string(forKey: Self.sentKey) != key else { return }
        do {
            try await env.liveAPI.registerPush(deviceID: env.settings.deviceId, registration)
            defaults.set(key, forKey: Self.sentKey)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Before sign-out (while the session still authorises the call).
    func signOut() async {
        if defaults.string(forKey: Self.sentKey) != nil {
            try? await env.liveAPI.deletePush(deviceID: env.settings.deviceId)
        }
        defaults.removeObject(forKey: Self.sentKey)
        defaults.removeObject(forKey: Self.tokenKey)
        token = nil
        env.notifier.unregisterForRemoteNotifications()
    }

    // MARK: values sent

    /// The build's `aps-environment`: Xcode debug builds talk to the sandbox,
    /// TestFlight and the App Store to production.
    static var environment: PushEnvironment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }

    /// The app's language with the phone's region, e.g. `de-DE`.
    static func locale(bundle: Bundle = .main, locale: Locale = .current) -> String {
        let language = bundle.preferredLocalizations.first ?? "en"
        guard let region = locale.region?.identifier else { return language }
        return "\(language)-\(region)"
    }

    static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}

/// The notification categories the app registers. The four remote ones come
/// from the platform (`NotificationCategory`); `BEDTIME` is the local reminder.
enum PushCategories {
    static let bedtime = "BEDTIME"
    static let syncNowAction = "SYNC_NOW"

    static var all: Set<UNNotificationCategory> {
        var categories = Set(NotificationCategory.allCases.map { category in
            UNNotificationCategory(identifier: category.rawValue,
                                   actions: category == .syncStale ? [syncNow] : [],
                                   intentIdentifiers: [], options: [])
        })
        categories.insert(UNNotificationCategory(identifier: bedtime, actions: [], intentIdentifiers: [], options: []))
        return categories
    }

    private static var syncNow: UNNotificationAction {
        UNNotificationAction(identifier: syncNowAction, title: String(localized: "Sync now"), options: [.foreground])
    }
}

/// What the app does with a notification's `userInfo`.
enum PushMessage: Equatable {
    /// The silent push: refresh that day, no upload.
    case refresh(day: String)
    /// An alert; tapping it opens `url` (if any).
    case alert(category: NotificationCategory?, url: URL?)

    init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["ryft"],
              JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let info = try? APIClient.jsonDecoder.decode(RyftPushInfo.self, from: data) else { return nil }
        if info.kind == "refresh" {
            self = .refresh(day: info.day)
        } else {
            self = .alert(category: info.category.flatMap(NotificationCategory.init(rawValue:)),
                          url: info.url.flatMap(URL.init(string:)))
        }
    }
}
