// The four build-time values every build needs: the RYFT platform's two hosts
// (API and ingest) and the Supabase project (URL + publishable key). They come from
// Config/Production.xcconfig (Debug: Config/Debug.xcconfig, which includes it)
// through Info.plist (RyftAPIURL, RyftIngestURL, RyftSupabaseURL, RyftSupabasePublishableKey).
//
// A build without them is a broken build, never a silent fallback host:
// Debug stops at launch, Release shows `MisconfiguredBuildView` and nothing else.
import SwiftUI

enum PlatformConfig {
    /// The base URL of every route except `POST /v1/sync`.
    static let apiURL: URL? = url(Bundle.configValue("RyftAPIURL"))

    /// The base URL of `POST /v1/sync`, and of nothing else.
    static let ingestURL: URL? = url(Bundle.configValue("RyftIngestURL"))

    static let supabase: SupabaseConfig? = SupabaseConfig.current

    /// Build settings that are missing or invalid, by their xcconfig name.
    static func problems(info: [String: Any]? = Bundle.main.infoDictionary, release: Bool = isRelease) -> [String] {
        var out: [String] = []
        for (key, setting) in [("RyftAPIURL", "RYFT_API_URL"), ("RyftIngestURL", "RYFT_INGEST_URL")] {
            let host = url(Bundle.configValue(key, in: info))
            if host == nil {
                out.append(setting)
            } else if release, host?.scheme != "https" {
                out.append("\(setting) (HTTPS only in Release)")
            }
        }
        if url(Bundle.configValue("RyftSupabaseURL", in: info)) == nil { out.append("RYFT_SUPABASE_URL") }
        if Bundle.configValue("RyftSupabasePublishableKey", in: info) == nil { out.append("RYFT_SUPABASE_PUBLISHABLE_KEY") }
        return out
    }

    static let missing = problems()
    static var isComplete: Bool { missing.isEmpty }

    static var isRelease: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    /// Debug builds stop here with the reason; Release builds show the blocking screen.
    static func checkAtLaunch() {
        #if DEBUG
        guard isComplete || isRunningTests else {
            fatalError("Misconfigured build: \(missing.joined(separator: ", ")). Fill Config/Production.xcconfig (or Config/Debug.xcconfig).")
        }
        #endif
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func url(_ string: String?) -> URL? {
        guard let s = string, let url = URL(string: s), url.host != nil else { return nil }
        return url
    }
}

/// Release only: a build without its platform values can't do anything useful.
struct MisconfiguredBuildView: View {
    var body: some View {
        VStack(spacing: 18) {
            RyftMark()
                .frame(width: 56, height: 56)
                .foregroundStyle(Theme.textPrimary)
            Text("This build is misconfigured")
                .font(.ryft(.title))
                .foregroundStyle(Theme.textPrimary)
            Text("It's missing \(PlatformConfig.missing.formatted(.list(type: .and))). Install the version from the App Store.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.graphite.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}

#Preview("Misconfigured build") {
    MisconfiguredBuildView()
}

/// What a request tells the platform about this install (sync, consent, feedback).
enum AppInfo {
    /// "1.0.0 (20261021.081500)": marketing version and build.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// "iOS 27.1".
    @MainActor static var osVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }
}
