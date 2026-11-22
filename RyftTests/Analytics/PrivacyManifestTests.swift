import Foundation
import Testing
@testable import Ryft

/// The app's `PrivacyInfo.xcprivacy` as the bundle ships it (the hosted tests run inside the app, so its bundle is
/// the app's). Loading it as a property list also proves the file is valid.
@Suite("Privacy manifest")
struct PrivacyManifestTests {
    private static let typePrefix = "NSPrivacyCollectedDataType"

    private func manifest() throws -> [String: Any] {
        let bundle = Bundle(for: AppEnvironment.self)
        let url = try #require(bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                               "PrivacyInfo.xcprivacy isn't in the app bundle")
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func collected(_ type: String) throws -> [String: Any] {
        let all = try #require(try manifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        return try #require(all.first { $0["NSPrivacyCollectedDataType"] as? String == "\(Self.typePrefix)\(type)" },
                            "\(type) isn't declared")
    }

    @Test func theAppTracksNoOne() throws {
        let manifest = try manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
    }

    @Test(arguments: ["ProductInteraction", "OtherUsageData"])
    func usageAnalyticsAreDeclaredNotLinkedNotTrackingForAnalytics(_ type: String) throws {
        let entry = try collected(type)
        #expect(entry["\(Self.typePrefix)Linked"] as? Bool == false)
        #expect(entry["\(Self.typePrefix)Tracking"] as? Bool == false)
        #expect(entry["\(Self.typePrefix)Purposes"] as? [String] == ["\(Self.typePrefix)PurposeAnalytics"])
    }

    /// The ids and the diagnostics the app sends to its own platform are also what the analytics events carry (the SDK's
    /// anonymous id, app and OS versions, error codes): both purposes, still linked for the account's own use.
    @Test(arguments: ["DeviceID", "OtherDiagnosticData"])
    func deviceIDAndDiagnosticsListAppFunctionalityAndAnalytics(_ type: String) throws {
        let entry = try collected(type)
        #expect(entry["\(Self.typePrefix)Linked"] as? Bool == true)
        #expect(entry["\(Self.typePrefix)Tracking"] as? Bool == false)
        let purposes = try #require(entry["\(Self.typePrefix)Purposes"] as? [String])
        #expect(Set(purposes) == ["\(Self.typePrefix)PurposeAppFunctionality", "\(Self.typePrefix)PurposeAnalytics"])
    }

    @Test func noDeclaredTypeTracksAnyone() throws {
        let all = try #require(try manifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        #expect(!all.isEmpty)
        for entry in all {
            #expect(entry["\(Self.typePrefix)Tracking"] as? Bool == false, "\(entry["NSPrivacyCollectedDataType"] ?? "?")")
        }
    }

    @Test func systemBootTimeIsDeclaredForThePostHogSDK() throws {
        let apis = try #require(try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let boot = try #require(apis.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategorySystemBootTime" })
        #expect(boot["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["35F9.1"])
    }
}
