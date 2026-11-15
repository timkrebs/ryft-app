import Foundation
import Testing
@testable import Ryft

@Suite("Platform configuration")
struct PlatformConfigTests {
    private let complete: [String: Any] = [
        "RyftAPIURL": "https://api.ryftlab.de",
        "RyftIngestURL": "https://ingest.ryftlab.de",
        "RyftSupabaseURL": "https://ydgbemufggwnegbnjhkm.supabase.co",
        "RyftSupabasePublishableKey": "sb_publishable_x",
    ]

    @Test func completeConfigHasNoProblems() {
        #expect(PlatformConfig.problems(info: complete, release: true).isEmpty)
    }

    @Test func thisBuildIsComplete() {
        #expect(PlatformConfig.missing.isEmpty, "Config/Production.xcconfig must carry all four values")
    }

    /// The built app has its own ingest host: `POST /v1/sync` never goes to the API host.
    @Test func thisBuildHasAnIngestHostOfItsOwn() throws {
        let ingest = try #require(PlatformConfig.ingestURL)
        #expect(ingest != PlatformConfig.apiURL)
    }

    @Test func aMissingIngestURLIsAProblem() {
        var info = complete
        info["RyftIngestURL"] = nil
        #expect(PlatformConfig.problems(info: info, release: true) == ["RYFT_INGEST_URL"])
        info["RyftIngestURL"] = "ingest.ryftlab.de" // no scheme, so no host
        #expect(PlatformConfig.problems(info: info, release: false) == ["RYFT_INGEST_URL"])
    }

    @Test func placeholdersAndUnexpandedValuesCountAsMissing() {
        var info = complete
        info["RyftSupabaseURL"] = "https://<project-ref>.supabase.co"
        info["RyftSupabasePublishableKey"] = "$(RYFT_SUPABASE_PUBLISHABLE_KEY)"
        info["RyftAPIURL"] = ""
        info["RyftIngestURL"] = "$(RYFT_INGEST_URL)"
        #expect(PlatformConfig.problems(info: info, release: false)
                == ["RYFT_API_URL", "RYFT_INGEST_URL", "RYFT_SUPABASE_URL", "RYFT_SUPABASE_PUBLISHABLE_KEY"])
    }

    @Test func releaseRequiresHTTPS() {
        var info = complete
        info["RyftAPIURL"] = "http://192.168.1.20:8082"
        #expect(PlatformConfig.problems(info: info, release: false).isEmpty) // Debug may use compose on the LAN
        #expect(PlatformConfig.problems(info: info, release: true) == ["RYFT_API_URL (HTTPS only in Release)"])
    }

    @Test func releaseRequiresHTTPSForIngestToo() {
        var info = complete
        info["RyftIngestURL"] = "http://192.168.1.20:8081"
        #expect(PlatformConfig.problems(info: info, release: false).isEmpty)
        #expect(PlatformConfig.problems(info: info, release: true) == ["RYFT_INGEST_URL (HTTPS only in Release)"])
        info["RyftAPIURL"] = "http://192.168.1.20:8082"
        #expect(PlatformConfig.problems(info: info, release: true)
                == ["RYFT_API_URL (HTTPS only in Release)", "RYFT_INGEST_URL (HTTPS only in Release)"])
    }

    /// `Config/Production.xcconfig` as committed (read from the repo: the simulator sees the Mac's paths), so a
    /// Release archive gets both production hosts, not only what this Debug build happens to carry.
    @Test func productionConfigNamesBothHosts() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/Production.xcconfig")
        let values = Self.settings(try String(contentsOf: file, encoding: .utf8))
        #expect(values["RYFT_API_URL"] == "https://api.ryftlab.de")
        #expect(values["RYFT_INGEST_URL"] == "https://ingest.ryftlab.de")
    }

    /// The `KEY = value` lines of an xcconfig; `$()` (the escape that keeps `//` from starting a comment) is empty.
    private static func settings(_ xcconfig: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in xcconfig.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.hasPrefix("//"), !s.hasPrefix("#"), let eq = s.firstIndex(of: "=") else { continue }
            let key = s[..<eq].trimmingCharacters(in: .whitespaces)
            out[key] = s[s.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "$()", with: "")
        }
        return out
    }
}
