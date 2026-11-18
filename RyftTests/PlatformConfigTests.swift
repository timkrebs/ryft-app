import Foundation
import Testing
@testable import Ryft

@Suite("Platform configuration")
struct PlatformConfigTests {
    private let complete: [String: Any] = [
        "RyftAPIURL": "https://api.ryftapp.de",
        "RyftSupabaseURL": "https://ydgbemufggwnegbnjhkm.supabase.co",
        "RyftSupabasePublishableKey": "sb_publishable_x",
    ]

    @Test func completeConfigHasNoProblems() {
        #expect(PlatformConfig.problems(info: complete, release: true).isEmpty)
    }

    @Test func thisBuildIsComplete() {
        #expect(PlatformConfig.missing.isEmpty, "Config/Production.xcconfig must carry all three values")
    }

    @Test func placeholdersAndUnexpandedValuesCountAsMissing() {
        var info = complete
        info["RyftSupabaseURL"] = "https://<project-ref>.supabase.co"
        info["RyftSupabasePublishableKey"] = "$(RYFT_SUPABASE_PUBLISHABLE_KEY)"
        info["RyftAPIURL"] = ""
        #expect(PlatformConfig.problems(info: info, release: false)
                == ["RYFT_API_URL", "RYFT_SUPABASE_URL", "RYFT_SUPABASE_PUBLISHABLE_KEY"])
    }

    /// The misconfigured screen (PR 6 A §A-15): the missing names in one sentence that names no store, and no sentence at all
    /// for an empty list (never "It's missing .").
    @Test func misconfiguredScreenSaysWhatIsMissing() {
        #expect(MisconfiguredBuildView.message(missing: []) == nil)
        let one = MisconfiguredBuildView.message(missing: ["RYFT_API_URL"])
        #expect(one == String(localized: "It's missing \("RYFT_API_URL"). Install the latest version of RYFT."))
        #expect(one?.contains("App Store") == false)
        let two = MisconfiguredBuildView.message(missing: ["RYFT_API_URL", "RYFT_SUPABASE_URL"]) ?? ""
        #expect(two.contains("RYFT_API_URL") && two.contains("RYFT_SUPABASE_URL"), "\(two)")
    }

    @Test func releaseRequiresHTTPS() {
        var info = complete
        info["RyftAPIURL"] = "http://192.168.1.20:8082"
        #expect(PlatformConfig.problems(info: info, release: false).isEmpty) // Debug may use compose on the LAN
        #expect(PlatformConfig.problems(info: info, release: true) == ["RYFT_API_URL (HTTPS only in Release)"])
    }
}
