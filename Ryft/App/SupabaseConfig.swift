// Supabase project values, read from Info.plist (RyftSupabaseURL,
// RyftSupabaseAnonKey). project.yml fills those from the git-ignored
// Config/*.xcconfig, so nothing project-specific is hard-coded in Swift.
// The anon key is a publishable key; it's fine in the binary.
import Foundation

struct SupabaseConfig: Equatable {
    let url: URL
    let anonKey: String

    /// `nil` when the xcconfig is missing or still holds the example placeholders;
    /// the app then runs without sign-in (demo mode, or API key mode in Debug).
    static let current = SupabaseConfig(info: Bundle.main.infoDictionary ?? [:])

    init?(info: [String: Any]) {
        guard let urlString = Bundle.configValue("RyftSupabaseURL", in: info),
              let url = URL(string: urlString), url.host != nil,
              let key = Bundle.configValue("RyftSupabaseAnonKey", in: info) else { return nil }
        self.url = url
        self.anonKey = key
    }

    /// GoTrue lives under `/auth/v1` of the project URL.
    var authURL: URL { url.appendingPathComponent("auth/v1") }
}

extension Bundle {
    /// An Info.plist value filled from a build setting. Empty, unexpanded
    /// (`$(…)`) and example placeholder (`YOUR-…`) values count as missing.
    static func configValue(_ key: String, in info: [String: Any]? = Bundle.main.infoDictionary) -> String? {
        guard let raw = info?[key] as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$("), !value.contains("YOUR-") else { return nil }
        return value
    }
}
