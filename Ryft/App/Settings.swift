// Persisted app settings in UserDefaults. Who the caller is lives in
// AuthService (the Supabase SDK keeps the session in the Keychain); the app
// stores no tokens itself, except the Debug-only developer API key.
// `deviceId` is minted once per install and sent with every sync so the
// backend can tell devices apart.
import Foundation
import Security

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var apiURLString: String {
        didSet { defaults.set(apiURLString, forKey: "apiURL") }
    }
    @Published var ingestURLString: String {
        didSet { defaults.set(ingestURLString, forKey: "ingestURL") }
    }
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

    enum Appearance: String, CaseIterable, Identifiable {
        case dark, light, system
        var id: String { rawValue }
    }

    #if DEBUG
    /// Developer mode for a `docker compose` platform running with `AUTH_MODE=apikey`:
    /// a static bearer replaces the Supabase session. Not compiled into Release.
    @Published var apiKeyMode: Bool {
        didSet { defaults.set(apiKeyMode, forKey: "dev.apiKeyMode") }
    }
    @Published var devAPIKey: String {
        didSet { Keychain.set(devAPIKey.isEmpty ? nil : devAPIKey, for: "ryft.dev.apiKey") }
    }
    #endif

    let deviceId: UUID

    private init() {
        // Defaults come from Config/*.xcconfig (RYFT_API_URL, RYFT_INGEST_URL) via Info.plist.
        apiURLString = defaults.string(forKey: "apiURL") ?? Bundle.configValue("RyftAPIURL") ?? "https://ryft.example.com"
        ingestURLString = defaults.string(forKey: "ingestURL") ?? Bundle.configValue("RyftIngestURL") ?? ""
        // The shared API key is gone (Supabase Auth); drop it once from the Keychain.
        if !defaults.bool(forKey: "migrated.apiKeyRemoved") {
            Keychain.set(nil, for: "ryft.apiKey")
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
        #if DEBUG
        apiKeyMode = defaults.bool(forKey: "dev.apiKeyMode")
        devAPIKey = Keychain.get("ryft.dev.apiKey") ?? "dev-api-key-change-me" // compose default
        #endif
        if let s = defaults.string(forKey: "deviceId"), let id = UUID(uuidString: s) {
            deviceId = id
        } else {
            deviceId = UUID()
            defaults.set(deviceId.uuidString, forKey: "deviceId")
        }
    }

    var apiURL: URL? { URL(string: apiURLString.trimmingCharacters(in: .whitespaces)) }
    var ingestURL: URL? {
        let s = ingestURLString.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? apiURL : URL(string: s)
    }
    /// A platform URL is set. Whether there is a caller is `AuthService.isSignedIn`.
    var isConfigured: Bool { apiURL?.host != nil }
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
