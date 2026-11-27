import Foundation
import Testing
@testable import Ryft

/// One Boolean field of `AnalyticsSDKSettings` and the value the design requires of it. Note the polarity of
/// `disableGeoIp`: it is on, so PostHog stores no location.
struct AnalyticsSDKFieldRow: @unchecked Sendable, CustomTestStringConvertible {
    let field: String
    let keyPath: WritableKeyPath<AnalyticsSDKSettings, Bool>
    let expected: Bool
    var testDescription: String { "\(field) is \(expected ? "on" : "off")" }

    static let all: [AnalyticsSDKFieldRow] = [
        // Everything the SDK would collect on its own is off.
        AnalyticsSDKFieldRow(field: "sessionReplay", keyPath: \.sessionReplay, expected: false),
        AnalyticsSDKFieldRow(field: "captureScreenViews", keyPath: \.captureScreenViews, expected: false),
        AnalyticsSDKFieldRow(field: "captureElementInteractions (UIKit)", keyPath: \.captureElementInteractions, expected: false),
        AnalyticsSDKFieldRow(field: "captureSwiftUIElementInteractions", keyPath: \.captureSwiftUIElementInteractions,
                             expected: false),
        AnalyticsSDKFieldRow(field: "rageClicks", keyPath: \.rageClicks, expected: false),
        AnalyticsSDKFieldRow(field: "surveys", keyPath: \.surveys, expected: false),
        AnalyticsSDKFieldRow(field: "preloadFeatureFlags", keyPath: \.preloadFeatureFlags, expected: false),
        AnalyticsSDKFieldRow(field: "sendFeatureFlagEvent", keyPath: \.sendFeatureFlagEvent, expected: false),
        AnalyticsSDKFieldRow(field: "setDefaultPersonProperties", keyPath: \.setDefaultPersonProperties, expected: false),
        AnalyticsSDKFieldRow(field: "capturePushNotificationSubscriptions", keyPath: \.capturePushNotificationSubscriptions,
                             expected: false),
        AnalyticsSDKFieldRow(field: "capturePushNotificationOpened", keyPath: \.capturePushNotificationOpened, expected: false),
        AnalyticsSDKFieldRow(field: "crashAutocapture", keyPath: \.crashAutocapture, expected: false),
        AnalyticsSDKFieldRow(field: "swizzling", keyPath: \.swizzling, expected: false),
        AnalyticsSDKFieldRow(field: "debug", keyPath: \.debug, expected: false),
        AnalyticsSDKFieldRow(field: "identifies", keyPath: \.identifies, expected: false),
        // The two that are on.
        AnalyticsSDKFieldRow(field: "captureApplicationLifecycleEvents", keyPath: \.captureApplicationLifecycleEvents,
                             expected: true),
        AnalyticsSDKFieldRow(field: "disableGeoIp", keyPath: \.disableGeoIp, expected: true),
    ]
}

@Suite("Analytics: the SDK settings")
struct AnalyticsSDKSettingsTests {
    private let settings = AnalyticsSDKSettings.required

    // MARK: A5: every field, pinned

    @Test(arguments: AnalyticsSDKFieldRow.all)
    func theRequiredSettingPinsItsField(_ row: AnalyticsSDKFieldRow) {
        #expect(settings[keyPath: row.keyPath] == row.expected, "\(row.field)")
    }

    @Test func noPersonProfileIsEverMadeAndNobodyIsEverIdentified() {
        #expect(settings.personProfiles == .never)
        #expect(settings.identifies == false)
    }

    @Test func onlyLifecycleAndGeoIPOffAreOn() {
        let on = AnalyticsSDKFieldRow.all.filter { settings[keyPath: $0.keyPath] }.map(\.field)
        #expect(on == ["captureApplicationLifecycleEvents", "disableGeoIp"])
    }

    /// A new field must be pinned here: the rows plus `personProfiles` are all of them (18 in all).
    @Test func everyFieldHasARowHere() {
        #expect(Mirror(reflecting: settings).children.count == AnalyticsSDKFieldRow.all.count + 1)
        #expect(Mirror(reflecting: settings).children.count == 18)
    }

    // MARK: A5: no field can be loosened silently

    @Test(arguments: AnalyticsSDKFieldRow.all)
    func flippingAnySingleFieldMakesItUnequal(_ row: AnalyticsSDKFieldRow) {
        var changed = settings
        changed[keyPath: row.keyPath].toggle()
        #expect(changed != settings, "\(row.field)")
        #expect(changed[keyPath: row.keyPath] != settings[keyPath: row.keyPath])
        changed[keyPath: row.keyPath].toggle()
        #expect(changed == settings, "\(row.field)")
    }

    @Test func anotherPersonProfilesModeMakesItUnequal() {
        var always = settings
        always.personProfiles = .always
        #expect(always != settings)
        var identifiedOnly = settings
        identifiedOnly.personProfiles = .identifiedOnly
        #expect(identifiedOnly != settings)
    }

    @Test func theSettingsAreAValue() {
        #expect(AnalyticsSDKSettings.required == AnalyticsSDKSettings.required)
        var copy = settings
        copy.sessionReplay = true
        #expect(settings.sessionReplay == false, "a copy changes only itself")
    }
}
