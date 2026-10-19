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

    @Test func releaseRequiresHTTPS() {
        var info = complete
        info["RyftAPIURL"] = "http://192.168.1.20:8082"
        #expect(PlatformConfig.problems(info: info, release: false).isEmpty) // Debug may use compose on the LAN
        #expect(PlatformConfig.problems(info: info, release: true) == ["RYFT_API_URL (HTTPS only in Release)"])
    }
}
