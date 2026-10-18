// Build-time configuration: the RYFT platform URL and the Supabase project,
// from Info.plist (RyftAPIURL, RyftSupabaseURL, RyftSupabasePublishableKey).
// Those are filled from Config/Production.xcconfig (Debug: Config/Debug.xcconfig,
// which includes it), so nothing project-specific is hard-coded in Swift.
// All values are publishable; the key is fine in the binary.
import Foundation

struct SupabaseConfig: Equatable {
    let url: URL
    let publishableKey: String

    /// `nil` when a value is missing; `problem` says which. The app then shows
    /// that on Welcome instead of crashing (demo data still works).
    static let current = SupabaseConfig(info: Bundle.main.infoDictionary ?? [:])

    init?(info: [String: Any]) {
        guard let urlString = Bundle.configValue("RyftSupabaseURL", in: info),
              let url = URL(string: urlString), url.host != nil,
              let key = Bundle.configValue("RyftSupabasePublishableKey", in: info) else { return nil }
        self.url = url
        self.publishableKey = key
    }

    /// GoTrue lives under `/auth/v1` of the project URL.
    var authURL: URL { url.appendingPathComponent("auth/v1") }

    /// Where Supabase sends confirmation and password-reset links. Must be in
    /// the project's redirect URLs (Authentication → URL Configuration).
    static let redirectURL = URL(string: "ryft://auth/callback")!

    /// The build settings that are missing, for an in-app message.
    static func missingSettings(info: [String: Any]? = Bundle.main.infoDictionary) -> [String] {
        [("RyftAPIURL", "RYFT_API_URL"),
         ("RyftSupabaseURL", "RYFT_SUPABASE_URL"),
         ("RyftSupabasePublishableKey", "RYFT_SUPABASE_PUBLISHABLE_KEY")]
            .filter { Bundle.configValue($0.0, in: info) == nil }
            .map(\.1)
    }

    /// "This build is missing …", or `nil` when everything is set.
    static var problem: String? {
        let missing = missingSettings()
        guard !missing.isEmpty else { return nil }
        return String(localized: "This build is missing \(missing.formatted(.list(type: .and))). Fill them in Config/Production.xcconfig and rebuild.")
    }
}

extension Bundle {
    /// An Info.plist value filled from a build setting. Empty, unexpanded
    /// (`$(…)`) and placeholder (`<…>`, `YOUR-…`) values count as missing.
    static func configValue(_ key: String, in info: [String: Any]? = Bundle.main.infoDictionary) -> String? {
        guard let raw = info?[key] as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$("), !value.contains("<"), !value.contains("YOUR-") else { return nil }
        return value
    }
}
