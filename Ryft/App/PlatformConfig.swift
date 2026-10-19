// The three build-time values every build needs: the RYFT platform URL and
// the Supabase project (URL + publishable key). They come from
// Config/Production.xcconfig (Debug: Config/Debug.xcconfig, which includes it)
// through Info.plist (RyftAPIURL, RyftSupabaseURL, RyftSupabasePublishableKey).
//
// A build without them is a broken build, never a silent fallback host:
// Debug stops at launch, Release shows `MisconfiguredBuildView` and nothing else.
import SwiftUI

enum PlatformConfig {
    /// One base URL for every route, `/v1/sync` included.
    static let apiURL: URL? = url(Bundle.configValue("RyftAPIURL"))

    static let supabase: SupabaseConfig? = SupabaseConfig.current

    /// Build settings that are missing or invalid, by their xcconfig name.
    static func problems(info: [String: Any]? = Bundle.main.infoDictionary, release: Bool = isRelease) -> [String] {
        var out: [String] = []
        let api = url(Bundle.configValue("RyftAPIURL", in: info))
        if api == nil {
            out.append("RYFT_API_URL")
        } else if release, api?.scheme != "https" {
            out.append("RYFT_API_URL (HTTPS only in Release)")
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
