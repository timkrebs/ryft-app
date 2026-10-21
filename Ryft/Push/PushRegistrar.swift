import Foundation
import Observation
import OSLog
import UserNotifications

/// APNs registration with the platform (`POST` / `DELETE /v1/devices/{id}/push`).
///
/// - After this account's first successful sync, Today asks in one sentence
///   ("Get your recovery each morning", Allow / Not now). "Not now" is
///   remembered per user; the question comes back once, 14 days later.
/// - Once allowed, the app registers with APNs on every launch. The token,
///   environment and language go to the platform only when one of them (or the
///   account) changed since the last accepted registration, which is kept in
///   SwiftData (`CachedDocument` "push.registration").
/// - Before sign-out and before account deletion the registration is deleted
///   (a failure is logged and ignored).
/// Everything is gated by the `push.enabled` flag.
@MainActor
@Observable
final class PushRegistrar {
    private let env: AppEnvironment

    static let firstSyncKey = "push.firstSyncDone"
    static let dismissedAtKey = "push.prePromptDismissedAt"
    static let dismissCountKey = "push.prePromptDismissals"
    static let recordKey = "push.registration"
    static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "push")
    /// "Not now" brings the question back after this long, once.
    static let askAgainAfter: TimeInterval = 14 * 24 * 3600

    /// What the platform last accepted.
    struct Record: Codable, Equatable {
        let account: String
        let token: String
        let env: PushEnvironment
        let locale: String
    }

    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// The current APNs token (in memory; APNs hands it over on every launch).
    private(set) var token: String?
    private(set) var lastError: String?
    /// The last registration call's outcome, for Profile → Developer.
    private(set) var lastResult: String?
    /// Bumped when a per-user setting changes, so observers re-read the defaults.
    private var revision = 0

    init(env: AppEnvironment) {
        self.env = env
    }

    private var defaults: UserDefaults { env.defaults }
    private var account: String? { env.auth.accountID }
    private func key(_ base: String) -> String { "\(base).\(account ?? "signed-out")" }
    private var isEnabled: Bool { env.flags.isOn(.pushEnabled) && !env.isDemo }
    var isAllowed: Bool { status == .authorized || status == .provisional || status == .ephemeral }

    var hasSynced: Bool {
        _ = revision
        return defaults.bool(forKey: key(Self.firstSyncKey))
    }

    /// Today's question: after a sync, before iOS was asked; after "Not now"
    /// only once more, 14 days later.
    var showsPrePrompt: Bool {
        _ = revision
        guard isEnabled, env.auth.isSignedIn, hasSynced, status == .notDetermined else { return false }
        switch defaults.integer(forKey: key(Self.dismissCountKey)) {
        case 0: return true
        case 1:
            let at = defaults.object(forKey: key(Self.dismissedAtKey)) as? Date ?? .distantFuture
            return env.clock.now().timeIntervalSince(at) >= Self.askAgainAfter
        default: return false
        }
    }

    /// The first import's question ("Tell me when my first scores are ready"): before the
    /// first sync has finished, while iOS hasn't asked and it wasn't dismissed yet.
    var showsImportPrompt: Bool {
        _ = revision
        guard isEnabled, env.auth.isSignedIn, status == .notDetermined else { return false }
        return defaults.integer(forKey: key(Self.dismissCountKey)) == 0
    }

    // MARK: lifecycle

    /// At launch, on every return to the app and after sign-in: picks up a change
    /// in Settings and re-registers, so a new token or language reaches the platform.
    func refresh() async {
        status = await env.notifier.authorizationStatus()
        env.notifier.setCategories(PushCategories.all)
        guard isEnabled, env.auth.isSignedIn, isAllowed else { return }
        env.notifier.registerForRemoteNotifications()
        await send()
    }

    /// The coordinator finished a sync; the question may show from now on.
    func syncSucceeded() {
        guard account != nil, !hasSynced else { return }
        defaults.set(true, forKey: key(Self.firstSyncKey))
        revision += 1
    }

    // MARK: pre-prompt

    /// "Allow": the system prompt, then APNs.
    func accept() async {
        let granted = (try? await env.notifier.requestAuthorization()) ?? false
        status = await env.notifier.authorizationStatus()
        if granted { env.notifier.registerForRemoteNotifications() }
        revision += 1
    }

    /// "Not now".
    func dismissPrompt() {
        defaults.set(defaults.integer(forKey: key(Self.dismissCountKey)) + 1, forKey: key(Self.dismissCountKey))
        defaults.set(env.clock.now(), forKey: key(Self.dismissedAtKey))
        revision += 1
    }

    // MARK: APNs callbacks

    func didRegister(deviceToken: Data) async {
        token = Self.hex(deviceToken)
        await send()
    }

    func didFailToRegister(_ error: Error) {
        lastError = error.localizedDescription
    }

    /// `POST /v1/devices/{id}/push`, unless the platform already has exactly this.
    func send() async {
        guard isEnabled, let token, let account else { return }
        let record = Record(account: account, token: token, env: PushEnvironment.current(), locale: Self.locale())
        guard env.persistence.document(Record.self, key: Self.recordKey) != record else { return }
        do {
            try await env.liveAPI.registerPush(deviceID: env.settings.deviceId,
                                               PushRegistration(token: token, env: record.env, locale: record.locale))
            env.persistence.saveDocument(record, key: Self.recordKey, at: env.clock.now())
            lastError = nil
            lastResult = "POST 204 · \(record.env.rawValue) · \(record.locale)"
            // Once per accepted registration: on TestFlight (no Developer section) this
            // is how to confirm the build registered with production APNs.
            Self.log.notice("push registration env=\(record.env.rawValue, privacy: .public) locale=\(record.locale, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            lastResult = "POST failed · \(error.diagnosticDetails ?? error.localizedDescription)"
        }
    }

    /// Before sign-out and account deletion, while the session still authorises
    /// the `DELETE`. A failure is logged and ignored.
    func signOut() async {
        if env.persistence.document(Record.self, key: Self.recordKey) != nil {
            do {
                try await env.liveAPI.deletePush(deviceID: env.settings.deviceId)
                lastResult = "DELETE 204"
            } catch {
                lastResult = "DELETE failed · \(error.localizedDescription)"
                Self.log.error("DELETE /v1/devices/{id}/push failed, continuing: \(error.localizedDescription, privacy: .public)")
            }
        }
        env.persistence.removeDocument(key: Self.recordKey)
        token = nil
        env.notifier.unregisterForRemoteNotifications()
    }

    // MARK: values sent

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

extension PushEnvironment {
    /// The signed `aps-environment`, read at runtime from the embedded
    /// provisioning profile: `development` → sandbox, `production` → production.
    /// App Store builds carry no profile and use production; the simulator, sandbox.
    static func current(profile: Data? = embeddedProfile()) -> PushEnvironment {
        #if targetEnvironment(simulator)
        return .sandbox
        #else
        guard let profile else { return .production }
        return fromProfile(profile) ?? .production
        #endif
    }

    /// `aps-environment` out of a `.mobileprovision` (CMS data around an XML plist).
    static func fromProfile(_ data: Data) -> PushEnvironment? {
        guard let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex),
              let xml = text[start.lowerBound..<end.upperBound].data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let aps = entitlements["aps-environment"] as? String else { return nil }
        return aps == "production" ? .production : .sandbox
    }

    private static func embeddedProfile() -> Data? {
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap { try? Data(contentsOf: $0) }
    }
}

/// The notification categories the app registers. The four remote ones come
/// from the platform (`NotificationCategory`); `BEDTIME` is the local reminder.
enum PushCategories {
    static let bedtime = "BEDTIME"

    /// No actions yet: a tap opens the app (`ryft.url`, or Today for `SYNC_STALE`).
    static var all: Set<UNNotificationCategory> {
        var categories = Set(NotificationCategory.allCases.map {
            UNNotificationCategory(identifier: $0.rawValue, actions: [], intentIdentifiers: [], options: [])
        })
        categories.insert(UNNotificationCategory(identifier: bedtime, actions: [], intentIdentifiers: [], options: []))
        return categories
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
