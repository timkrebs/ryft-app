import Foundation
import Testing
@testable import Ryft

/// Design note §8: the Health sheet's text names every type a requestable group reads, and none that no shipped
/// feature reads. Reads the built app's Info.plist (the test host), as `DarkOnlyTests` does.
@Suite("Health usage description")
struct HealthUsageDescriptionTests {
    private static let key = "NSHealthShareUsageDescription"

    private static func description() throws -> String {
        try #require(Bundle.main.infoDictionary?[key] as? String, "Ryft/Info.plist: \(key)")
    }

    /// Info.plist and InfoPlist.xcstrings carry the same text (two copies, which drifted before).
    @Test func infoPlistAndTheCatalogAgree() throws {
        let plain = try Self.description()
        let localized = try #require(Bundle.main.localizedInfoDictionary?[Self.key] as? String,
                                     "Ryft/Resources/InfoPlist.xcstrings: \(Self.key)")
        #expect(plain == localized)
    }

    @Test func itNamesEveryTypeOfARequestableGroup() throws {
        let text = try Self.description()
        for group in HealthPermissionGroup.allCases where group.isRequestable {
            for type in group.types {
                #expect(text.localizedCaseInsensitiveContains(type.usageName), "\(group): \(type.usageName)")
            }
        }
    }

    /// Making a group requestable fails here until its words are in the sheet's text (and App Review's notes).
    @Test func itNamesNoTypeOfAGroupThatIsNotRequestable() throws {
        let text = try Self.description()
        for group in HealthPermissionGroup.allCases where !group.isRequestable {
            for type in group.types {
                #expect(!text.localizedCaseInsensitiveContains(type.usageName), "\(group): \(type.usageName)")
            }
        }
    }

    /// The ten names, pinned once against 1.x's text, and the date of birth.
    @Test func theNamesArePinned() {
        #expect(HealthPermissionGroup.core.types.map(\.usageName)
            == ["heart rate", "HRV", "resting heart rate", "breathing rate", "blood oxygen", "VO₂ max", "active energy",
                "steps", "sleep", "workouts"])
        #expect(HealthPermissionGroup.about.types.map(\.usageName) == ["date of birth"])
        let names = HealthDataType.allCases.map(\.usageName)
        #expect(Set(names).count == names.count)
    }

    /// Connect Apple Health's "What RYFT reads" names core's types, and nothing else.
    @Test func connectAppleHealthNamesCore() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Ryft/Features/Onboarding/HealthPermissionView.swift"),
                                encoding: .utf8)
        let pattern = #/title: "What RYFT reads",\s*text: "([^"]*)"/#
        let match = try #require(source.firstMatch(of: pattern), "HealthPermissionView: the What RYFT reads point")
        let text = String(match.output.1)
        for type in HealthPermissionGroup.core.types {
            #expect(text.localizedCaseInsensitiveContains(type.usageName), "\(type.usageName)")
        }
        for group in HealthPermissionGroup.allCases where group != .core {
            for type in group.types {
                #expect(!text.localizedCaseInsensitiveContains(type.usageName), "\(group): \(type.usageName)")
            }
        }
    }
}
