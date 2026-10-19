// Persisted app settings in UserDefaults. The platform URL is baked into the
// build (Config/Production.xcconfig → Info.plist → `apiURL`); who the caller
// is lives in AuthService (the Supabase SDK keeps the session in the
// Keychain). The app stores no tokens itself, except the Debug-only developer
// API key. `deviceId` is minted once per install and sent with every sync so
// the backend can tell devices apart.
import Foundation
import Security

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var lastSync: Date? {
        didSet { defaults.set(lastSync, forKey: "lastSync") }
    }
    /// Serve the built-in mock history instead of the platform. On by default
    /// in the simulator (HealthKit has no data there); also settable with the
    /// launch argument `-demoMode YES`.
    @Published var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: "demoMode") }
    }
    @Published var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }
    /// The "Connect Apple Health" explanation was shown (and answered) for this
    /// account. Health access is only requested after it, never on a cold launch.
    @Published var healthIntroDone: Bool {
        didSet { defaults.set(healthIntroDone, forKey: "health.introDone") }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case dark, light, system
        var id: String { rawValue }
    }

    #if DEBUG
    // Profile → Developer. None of this is compiled into Release.

    /// Replaces the built-in API URL, e.g. `http://192.168.1.20:8082` for compose.
    @Published var devAPIURLOverride: String {
        didSet { defaults.set(devAPIURLOverride, forKey: "dev.apiURL") }
    }
    /// Compose serves ingest on its own port (`:8081`); behind the Ingress it's the API host.
    @Published var devIngestURLOverride: String {
        didSet { defaults.set(devIngestURLOverride, forKey: "dev.ingestURL") }
    }
    /// For a platform running `AUTH_MODE=apikey`: a static bearer replaces the Supabase session.
    @Published var apiKeyMode: Bool {
        didSet { defaults.set(apiKeyMode, forKey: "dev.apiKeyMode") }
    }
    @Published var devAPIKey: String {
        didSet { Keychain.set(devAPIKey.isEmpty ? nil : devAPIKey, for: "ryft.dev.apiKey") }
    }
    /// Lists recent failed requests with their `X-Request-ID` in Profile → Developer.
    @Published var showRequestIDs: Bool {
        didSet { defaults.set(showRequestIDs, forKey: "dev.showRequestIDs") }
    }
    #endif

    let deviceId: UUID

    private init() {
        // The shared API key and the per-user server fields are gone (Supabase
        // Auth, one production host); drop them once.
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
        appearance = defaults.string(forKey: "appearance").flatMap(Appearance.init(rawValue:)) ?? .dark
        healthIntroDone = defaults.bool(forKey: "health.introDone")
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

    /// One host serves `/v1/sync` and the API (Debug: or the compose ingest override).
    var ingestURL: URL? {
        #if DEBUG
        if let url = Self.url(devIngestURLOverride) { return url }
        #endif
        return apiURL
    }

    /// A platform URL is set. Whether there is a caller is `AuthService.isSignedIn`.
    var isConfigured: Bool { apiURL != nil }

    /// Per-user state on log-out and account deletion. Appearance, demo mode and
    /// the device ID stay; HealthKit anchors and cached responses are dropped
    /// by AuthService.
    func clearPerUserState() {
        lastSync = nil
        healthIntroDone = false
        defaults.removeObject(forKey: "insights.dismissed")
    }

    private static func url(_ string: String) -> URL? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }
}

enum Keychain {
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock // readable during background sync
        SecItemAdd(add as CFDictionary, nil)
    }
}
