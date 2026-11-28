import Foundation

/// The one list of what may leave the phone as product analytics: every event name, its property keys and each key's
/// values (plan 2026-11-27, decisions 1 and 2). `Analytics.deliver` checks every event against it before the gate, so
/// an unknown event, an unknown or denied key, a value off its list or an unsafe value never reaches the sink, whatever
/// the call site built. The SDK's own lifecycle events and `$` keys are listed apart (`sdkEventNames`,
/// `sdkPropertyKeys`): they never pass through `deliver`, but the sink's `beforeSend` keeps exactly these and the
/// catalogue's, nothing else (#137).
enum AnalyticsCatalog {
    /// Event name → property key → allowed values. The keys are literals (a renamed key in `AnalyticsEvent` fails the
    /// tests instead of silently widening this list); the values come from the tokens' `allCases`, a `Bool` is
    /// `"true"`/`"false"`. Must equal what `AnalyticsEvent.everyCase` produces.
    static let events: [String: [String: Set<String>]] = [
        "onboarding_step": ["step": values(OnboardingStepName.self)],
        "health_access_requested": [:],
        "first_sync_completed": [:],
        "screen_viewed": ["screen": values(AnalyticsScreen.self)],
        "feature_used": ["feature": values(AnalyticsFeature.self)],
        "error_shown": ["status": values(AnalyticsErrorStatus.self), "code": values(AnalyticsErrorCode.self)],
        "nutrition_search_completed": [
            "lookup": values(AnalyticsSearchLookup.self),
            "query_length": values(AnalyticsQueryLength.self),
            "results_count": values(AnalyticsResultCount.self),
            "has_results": bools,
            "latency_ms": values(AnalyticsLatency.self),
        ],
        "nutrition_food_opened": [
            "rank_position": values(AnalyticsRank.self),
            "is_canonical_staple": bools,
            "has_default_portion": bools,
            "has_last_used_portion": bools,
        ],
        "nutrition_food_logged": [
            "entry_point": values(AnalyticsNutritionEntryPoint.self),
            "unit_mode": values(AnalyticsUnitMode.self),
            "is_fractional": bools,
        ],
        "nutrition_diary_reopened": ["has_preserved_portion_label": bools],
        "sync_triggered": [
            "trigger_source": values(AnalyticsSyncTrigger.self),
            "previous_state": values(AnalyticsSyncPreviousState.self),
        ],
        "sync_completed": [
            "trigger_source": values(AnalyticsSyncTrigger.self),
            "status": values(AnalyticsSyncStatus.self),
            "duration_ms": values(AnalyticsSyncDuration.self),
            "connected_providers_count": values(AnalyticsConnectedProviders.self),
        ],
    ]

    /// Every event name of ours.
    static var eventNames: Set<String> { Set(events.keys) }

    /// Every property key of ours, across all events.
    static var propertyKeys: Set<String> { Set(events.values.flatMap(\.keys)) }

    /// What #137's `beforeSend` keeps besides ours: the lifecycle events (`captureApplicationLifecycleEvents`, the
    /// only autocapture `AnalyticsSDKSettings.required` leaves on).
    static let sdkEventNames: Set<String> = ["Application Installed", "Application Opened", "Application Backgrounded"]

    /// And the SDK's own keys: the app's and OS's version, the device type, the library, the session, the person-profile
    /// and GeoIP switches, and the lifecycle events' version and background fields. Nothing that names a person.
    static let sdkPropertyKeys: Set<String> = [
        "$app_version", "$app_build", "$os_name", "$os_version", "$device_type", "$lib", "$lib_version", "$session_id",
        "$process_person_profile", "$geoip_disable",
        "version", "build", "previous_version", "previous_build", "from_background",
    ]

    /// Keys that would carry what rule 3 forbids (a food, a query, a health or body value, a person): refused on any
    /// event, also on a listed one, so a future event can't add them by accident. Exact, and by prefix for `sleep_` and
    /// `quality`; case-insensitive.
    static func isDeniedKey(_ key: String) -> Bool {
        let key = key.lowercased()
        return deniedKeys.contains(key) || deniedPrefixes.contains { key.hasPrefix($0) }
    }

    /// A value that isn't a token: email-like (an `@` with a dot after it), longer than 40, or not
    /// `^[a-z0-9_+]{1,40}$`. Every allowed value is safe (a test pins it); this catches what a call site smuggled.
    static func isUnsafeValue(_ value: String) -> Bool {
        if let at = value.firstIndex(of: "@"), value[at...].contains(".") { return true }
        let scalars = value.unicodeScalars
        return scalars.isEmpty || scalars.count > maximumValueLength || !scalars.allSatisfy(tokenScalars.contains)
    }

    /// Why an event didn't reach the sink. Its description names the event and the key, never the value: the value is
    /// what may be the leak.
    enum Refusal: Error, Equatable, CustomStringConvertible {
        case unknownEvent
        case unknownKey(event: String, key: String)
        case deniedKey(event: String, key: String)
        case valueNotAllowed(event: String, key: String)
        case unsafeValue(event: String, key: String)
        case missingKey(event: String, key: String)

        var description: String {
            switch self {
            // The name itself isn't on the list, so it isn't repeated either.
            case .unknownEvent: return "analytics refused an event that isn't in the catalogue"
            case .unknownKey(let event, let key): return "analytics refused \(event): unknown key \(key)"
            case .deniedKey(let event, let key): return "analytics refused \(event): denied key \(key)"
            case .valueNotAllowed(let event, let key): return "analytics refused \(event): \(key) has a value off its list"
            case .unsafeValue(let event, let key): return "analytics refused \(event): \(key) has an unsafe value"
            case .missingKey(let event, let key): return "analytics refused \(event): missing key \(key)"
            }
        }
    }

    /// nil: the event may go on to the gate. In order: an unknown event; then per key (sorted, so the first refusal
    /// is stable): a denied key, an unknown key, an unsafe value, a value off the key's list; then any listed key
    /// that's missing.
    static func check(name: String, properties: [String: String]) -> Refusal? {
        guard let allowed = events[name] else { return .unknownEvent }
        for key in properties.keys.sorted() {
            if isDeniedKey(key) { return .deniedKey(event: name, key: key) }
            guard let values = allowed[key] else { return .unknownKey(event: name, key: key) }
            let value = properties[key] ?? ""
            if isUnsafeValue(value) { return .unsafeValue(event: name, key: key) }
            if !values.contains(value) { return .valueNotAllowed(event: name, key: key) }
        }
        if let missing = allowed.keys.sorted().first(where: { properties[$0] == nil }) {
            return .missingKey(event: name, key: missing)
        }
        return nil
    }

    // MARK: private

    private static let bools: Set<String> = ["true", "false"]
    private static let maximumValueLength = 40
    private static let deniedKeys: Set<String> = [
        "food_name", "query", "raw_query", "search", "hrv", "hrv_ms", "rhr", "weight", "kcal", "calories", "protein",
        "email", "name",
    ]
    private static let deniedPrefixes = ["sleep_", "quality"]
    /// `[a-z0-9_+]`.
    private static let tokenScalars = Set("abcdefghijklmnopqrstuvwxyz0123456789_+".unicodeScalars)

    private static func values<T: AnalyticsToken>(_: T.Type) -> Set<String> { Set(T.allCases.map(\.rawValue)) }
}

/// The SDK settings the design allows, as a value with no SDK type in it (plan 2026-11-27, decision 1). #137's
/// `PostHogSink.configuration(for:)` builds a `PostHogConfig` with exactly these; whichever PR lands second makes it
/// assert `AnalyticsSDKSettings(config) == .required`, and a test pins `.required` itself. Anything the SDK would
/// collect on its own is off, so the only things that leave the phone are `AnalyticsCatalog`'s events and the
/// lifecycle events.
struct AnalyticsSDKSettings: Equatable, Sendable {
    /// Who gets a person profile in PostHog.
    enum PersonProfiles: Equatable, Sendable {
        case never, identifiedOnly, always
    }

    /// Session replay records the screen: health values and food names would leave the phone.
    var sessionReplay: Bool
    /// Automatic screen views name UIKit view controllers; ours are `screen_viewed` with a closed token.
    var captureScreenViews: Bool
    /// UIKit autocapture sends tapped elements' text and hierarchy: free text, food names.
    var captureElementInteractions: Bool
    /// The same for SwiftUI views.
    var captureSwiftUIElementInteractions: Bool
    /// Rage-click detection (`rageClickConfig.enabled`) is element autocapture again.
    var rageClicks: Bool
    /// Surveys fetch and show remote UI and send free-text answers.
    var surveys: Bool
    /// Feature flags come from `GET /v1/config`, not from PostHog: no flag request at start.
    var preloadFeatureFlags: Bool
    /// No `$feature_flag_called` events: no flags are read from PostHog.
    var sendFeatureFlagEvent: Bool
    /// The SDK's default person properties (device, OS, locale) would sit on a profile; there is none.
    var setDefaultPersonProperties: Bool
    /// Push-token registration capture sends the device's APNs token to PostHog.
    var capturePushNotificationSubscriptions: Bool
    /// Push-open capture sends the APNs token too (and an event per opened notification).
    var capturePushNotificationOpened: Bool
    /// Crash autocapture (`errorTrackingConfig.autoCapture`) sends stack traces and app state; not part of the
    /// consented analytics. Off by default in 3.98.2, stated anyway.
    var crashAutocapture: Bool
    /// Method swizzling (`enableSwizzling`) is how autocapture and push capture hook in; off, nothing can by accident.
    var swizzling: Bool
    /// Debug logging prints every event and the project key to the console.
    var debug: Bool
    /// The one autocapture left on: Installed, Opened, Backgrounded (`AnalyticsCatalog.sdkEventNames`), for retention.
    var captureApplicationLifecycleEvents: Bool
    /// `never`: no person profile is made, not even by a stray `identify` (the brief: person profiles off; the user's
    /// decision: the anonymous per-install id only). `identifies == false` keeps RYFT from calling it anyway.
    var personProfiles: PersonProfiles
    /// Whether RYFT ever calls `identify` (or `alias`): never, so events stay on the anonymous per-install id.
    var identifies: Bool
    /// PostHog derives a location from the IP when this is off; on, no location is stored.
    var disableGeoIp: Bool

    /// What the design allows: everything off except the lifecycle events and the GeoIP switch; person profiles never,
    /// and nobody is ever identified.
    static let required = AnalyticsSDKSettings(
        sessionReplay: false, captureScreenViews: false, captureElementInteractions: false,
        captureSwiftUIElementInteractions: false, rageClicks: false, surveys: false, preloadFeatureFlags: false,
        sendFeatureFlagEvent: false, setDefaultPersonProperties: false, capturePushNotificationSubscriptions: false,
        capturePushNotificationOpened: false, crashAutocapture: false, swizzling: false, debug: false,
        captureApplicationLifecycleEvents: true, personProfiles: .never, identifies: false, disableGeoIp: true
    )
}
