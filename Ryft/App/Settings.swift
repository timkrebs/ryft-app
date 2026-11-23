// Persisted app settings in UserDefaults. The platform's two URLs are baked into the
// build (Config/Production.xcconfig → Info.plist → `apiURL`, `ingestURL`); who the caller
// is lives in AuthService (the Supabase SDK keeps the session in the
// Keychain). The app stores no tokens itself, except the Debug-only developer
// API key. `deviceId` is minted once per install and sent with every sync so
// the backend can tell devices apart.
import Foundation
import Observation
import Security

@Observable
final class Settings {
    static let shared = Settings()
    private let defaults: UserDefaults

    var lastSync: Date? {
        didSet { defaults.set(lastSync, forKey: "lastSync") }
    }
    /// Serve the built-in mock history instead of the platform. On by default
    /// in the simulator (HealthKit has no data there); also settable with the
    /// launch argument `-demoMode YES`.
    var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: "demoMode") }
    }
    /// The "Connect Apple Health" explanation was shown (and answered) for this
    /// account. Health access is only requested after it, never on a cold launch.
    var healthIntroDone: Bool {
        didSet { defaults.set(healthIntroDone, forKey: HealthPermissionLedger.introDoneKey) }
    }
    /// Profile → Training: after the last set of an exercise the session collapses it and scrolls to the next set.
    /// On by default; a device preference, so it stays on log-out.
    var jumpToNextExercise: Bool {
        didSet { defaults.set(jumpToNextExercise, forKey: "train.jumpToNext") }
    }
    /// Profile → Training → Session layout. Counts only with `train.focused_session` on (`SessionLayout.effective`);
    /// a device preference, so it stays on log-out.
    var sessionLayout: SessionLayout {
        didSet { defaults.set(sessionLayout.rawValue, forKey: "train.sessionLayout") }
    }
    /// The Focused table's fourth column, picked with its header. `nil`: never picked, the default rule decides
    /// (`SetColumn.shown`). Per user, unlike the two above: it goes on log-out.
    var setColumn: SetColumn? {
        didSet { defaults.set(setColumn?.rawValue, forKey: "train.setColumn") }
    }
    /// Profile → Display → Hero numbers: the large numerals on Today, Sleep and Strain as the dot grid or in thin digits
    /// (L19). A device preference, so it stays on log-out; an unknown stored value reads as the default, Dots.
    var heroNumerals: HeroNumerals {
        didSet { defaults.set(heroNumerals.rawValue, forKey: HeroNumerals.defaultsKey) }
    }

    #if DEBUG
    // Profile → Developer. None of this is compiled into Release.

    /// Replaces the built-in API URL, e.g. `http://192.168.1.20:8082` for compose. Comes as a pair with
    /// `devIngestURLOverride`: set alone, the sync has no host (`ingestURL`).
    var devAPIURLOverride: String {
        didSet { defaults.set(devAPIURLOverride, forKey: "dev.apiURL") }
    }
    /// Replaces the built-in ingest URL (`POST /v1/sync`), e.g. `http://192.168.1.20:8081` for compose.
    /// Needed with an API override; against a single-host stack, the same URL goes in both.
    var devIngestURLOverride: String {
        didSet { defaults.set(devIngestURLOverride, forKey: "dev.ingestURL") }
    }
    /// For a platform running `AUTH_MODE=apikey`: a static bearer replaces the Supabase session.
    var apiKeyMode: Bool {
        didSet { defaults.set(apiKeyMode, forKey: "dev.apiKeyMode") }
    }
    var devAPIKey: String {
        didSet { Keychain.set(devAPIKey.isEmpty ? nil : devAPIKey, for: "ryft.dev.apiKey") }
    }
    /// Lists recent failed requests with their `X-Request-ID` in Profile → Developer.
    var showRequestIDs: Bool {
        didSet { defaults.set(showRequestIDs, forKey: "dev.showRequestIDs") }
    }
    #endif

    let deviceId: UUID

    /// `defaults` is injectable so a test owns its settings; the app uses `.shared` (standard defaults).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // The shared API key and the per-user server fields are gone (Supabase
        // Auth, hosts from the build); drop them once.
        if !defaults.bool(forKey: "migrated.apiKeyRemoved") {
            Keychain.set(nil, for: "ryft.apiKey")
            defaults.removeObject(forKey: "apiURL")
            defaults.removeObject(forKey: "ingestURL")
            defaults.set(true, forKey: "migrated.apiKeyRemoved")
        }
        lastSync = defaults.object(forKey: "lastSync") as? Date
        #if targetEnvironment(simulator)
        let demoDefault = true
        #else
        let demoDefault = false
        #endif
        // `bool(forKey:)` also understands "YES"/"NO" strings from launch arguments.
        demoMode = defaults.object(forKey: "demoMode") != nil ? defaults.bool(forKey: "demoMode") : demoDefault
        healthIntroDone = defaults.bool(forKey: HealthPermissionLedger.introDoneKey)
        jumpToNextExercise = defaults.object(forKey: "train.jumpToNext") == nil || defaults.bool(forKey: "train.jumpToNext")
        sessionLayout = defaults.string(forKey: "train.sessionLayout").flatMap(SessionLayout.init(rawValue:)) ?? .focused
        setColumn = defaults.string(forKey: "train.setColumn").flatMap(SetColumn.init(rawValue:))
        heroNumerals = defaults.string(forKey: HeroNumerals.defaultsKey).flatMap(HeroNumerals.init(rawValue:)) ?? .dots
        #if DEBUG
        devAPIURLOverride = defaults.string(forKey: "dev.apiURL") ?? ""
        devIngestURLOverride = defaults.string(forKey: "dev.ingestURL") ?? ""
        apiKeyMode = defaults.bool(forKey: "dev.apiKeyMode")
        devAPIKey = Keychain.get("ryft.dev.apiKey") ?? "dev-api-key-change-me" // compose default
        showRequestIDs = defaults.bool(forKey: "dev.showRequestIDs")
        #endif
        if let s = defaults.string(forKey: "deviceId"), let id = UUID(uuidString: s) {
            deviceId = id
        } else {
            deviceId = UUID()
            defaults.set(deviceId.uuidString, forKey: "deviceId")
        }
    }

    /// The RYFT platform: `RYFT_API_URL` from the build (Debug: or the developer override).
    var apiURL: URL? {
        #if DEBUG
        if let url = Self.url(devAPIURLOverride) { return url }
        #endif
        return PlatformConfig.apiURL
    }

    /// The host of `POST /v1/sync`: `RYFT_INGEST_URL` from the build, never the API host. Debug: the ingest
    /// override; with an API override but none for ingest, `nil` (the sync fails `notConfigured`), so a compose
    /// stack's dev bearer never reaches production ingest.
    var ingestURL: URL? {
        #if DEBUG
        if let url = Self.url(devIngestURLOverride) { return url }
        if Self.url(devAPIURLOverride) != nil { return nil }
        #endif
        return PlatformConfig.ingestURL
    }

    /// A platform URL is set. Whether there is a caller is `AuthService.isSignedIn`.
    var isConfigured: Bool { apiURL != nil }

    /// Per-user state on log-out and account deletion. Demo mode, the training
    /// preferences (jump to next, session layout), the hero numerals and the device ID stay;
    /// HealthKit anchors and cached responses are dropped by AuthService.
    func clearPerUserState() {
        lastSync = nil
        healthIntroDone = false
        setColumn = nil
        defaults.removeObject(forKey: "insights.dismissed")
    }

    private static func url(_ string: String) -> URL? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }
}

/// How the live session shows its exercises: one per page, or all in one list.
enum SessionLayout: String, CaseIterable, Identifiable {
    case focused, list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focused: return String(localized: "Focused", comment: "Profile → Training → Session layout: one exercise per page.")
        case .list: return String(localized: "List", comment: "Profile → Training → Session layout: all exercises in one list.")
        }
    }

    /// What a session opens in: the stored choice while `train.focused_session` is on, List otherwise (plan.md, L5).
    static func effective(flagOn: Bool, stored: SessionLayout) -> SessionLayout {
        flagOn ? stored : .list
    }
}

/// How the hero numbers are drawn (Today's gauge, Sleep's duration, Strain's value; design.md §P4-6): the dot grid, or
/// thin Light digits. From AX1 and for characters the grid lacks both are Light (`DotNumeral.rendersDots`).
enum HeroNumerals: String, CaseIterable, Identifiable, Sendable {
    case dots, thin

    /// The `UserDefaults` key.
    static let defaultsKey = "ui.heroNumerals"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dots: return String(localized: "Dots", comment: "Profile → Display → Hero numbers: large numbers drawn as a grid of dots.")
        case .thin: return String(localized: "Thin", comment: "Profile → Display → Hero numbers: large numbers in thin digits.")
        }
    }

    /// The numeral style the screens pass to `OrbitGauge(numeral:)` and `DotNumeral(style:)`.
    var style: DotNumeral.Style {
        switch self {
        case .dots: return .dots
        case .thin: return .light
        }
    }
}

/// Generic-password items of this app, by account name. Never `kSecAttrSynchronizable`: no item leaves the device
/// through iCloud Keychain (and the queries match only items that don't sync).
enum Keychain {
    /// A Keychain status other than "no such item": before the first unlock, `errSecInteractionNotAllowed`.
    struct Failure: Error, Equatable {
        let status: OSStatus
    }

    static func get(_ key: String) -> String? {
        (try? read(key)) ?? nil
    }

    /// The item's text; nil only when there is no such item. Throws for anything else (a locked device's Keychain is
    /// not "no item").
    static func read(_ key: String) throws -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return (out as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Replaces the item (nil: deletes it). `accessible` defaults to "after the first unlock", readable during
    /// background sync. The status is the add's (or the delete's, for nil).
    @discardableResult
    static func set(_ value: String?, for key: String,
                    accessible: CFString = kSecAttrAccessibleAfterFirstUnlock) -> OSStatus {
        let deleted = SecItemDelete(query(key) as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return deleted }
        return SecItemAdd(attributes(for: key, data: data, accessible: accessible) as CFDictionary, nil)
    }

    /// What `set` adds (tests read the attributes here).
    static func attributes(for key: String, data: Data, accessible: CFString) -> [String: Any] {
        var add = query(key)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = accessible
        return add
    }

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
    }
}
