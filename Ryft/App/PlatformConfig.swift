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

/// Release only: a build without its platform values can't do anything useful. Nocturne (PR 6 A §A-15): the mark (56), 24
/// below the title (26 Light, centred), 12 below the reason (16 pt `textSecondary`, centred), 32 from the sides, on
/// `background`. A dead end by design: no button.
struct MisconfiguredBuildView: View {
    /// The build settings it lacks, by their xcconfig names; previews pass a sample.
    var missing: [String] = PlatformConfig.missing

    var body: some View {
        VStack(spacing: 0) {
            RyftMark()
                .frame(width: MisconfiguredBuildSpec.markSide, height: MisconfiguredBuildSpec.markSide)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityHidden(true)
            Text("This build is misconfigured")
                .font(.ryft(.title))
                .tracking(ScreenHeaderSpec.titleTracking)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, MisconfiguredBuildSpec.titleGap)
            if let message = Self.message(missing: missing) {
                Text(verbatim: message)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, MisconfiguredBuildSpec.textGap)
            }
        }
        .padding(.horizontal, MisconfiguredBuildSpec.sidePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    /// "It's missing RYFT_API_URL. Install the latest version of RYFT.", or nothing when the list is empty (never "It's
    /// missing ."). Beta testers install from TestFlight, so it names no store.
    static func message(missing: [String]) -> String? {
        guard !missing.isEmpty else { return nil }
        let list = missing.formatted(.list(type: .and))
        return String(localized: "It's missing \(list). Install the latest version of RYFT.",
                      comment: "Misconfigured build (Release only): the build settings it lacks, by their xcconfig names.")
    }
}

/// The misconfigured build's numbers (A §A-15).
enum MisconfiguredBuildSpec {
    static let markSide: CGFloat = 56
    static let titleGap: CGFloat = 24, textGap: CGFloat = 12
    static let sidePadding: CGFloat = 32
}

// Dark only (NOCTURNE_STYLE §1).
#Preview("Misconfigured build") {
    MisconfiguredBuildView(missing: ["RYFT_API_URL"])
}

#Preview("Misconfigured build · AX3") {
    MisconfiguredBuildView(missing: ["RYFT_API_URL", "RYFT_SUPABASE_URL"])
        .dynamicTypeSize(.accessibility3)
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
