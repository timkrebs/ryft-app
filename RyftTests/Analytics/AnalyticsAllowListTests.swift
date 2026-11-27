import Foundation
import Testing
@testable import Ryft

/// What the refusal tests send: `nutrition_food_opened` with all four of its keys, valid.
enum AllowListFixture {
    static let event = "nutrition_food_opened"
    static let valid: [String: String] = [
        "rank_position": "1", "is_canonical_staple": "true", "has_default_portion": "true",
        "has_last_used_portion": "false",
    ]
    static let validKeys = valid.keys.sorted()

    /// The deny-list of the brief (A1), exact names.
    static let deniedKeys = [
        "food_name", "query", "raw_query", "search", "hrv", "hrv_ms", "rhr", "weight", "kcal", "calories", "protein",
        "email", "name", "sleep_duration", "sleep_quality", "quality", "quality_score",
    ]
    /// The same words in other casings, and the two prefixes with another tail.
    static let deniedKeyVariants = ["Sleep_Hours", "QualityBucket", "HRV", "Food_Name", "EMAIL", "sleep_anything", "qualityX"]

    static func validWith(_ extra: [String: String]) -> [String: String] {
        valid.merging(extra) { _, new in new }
    }

    static let longLowercase = String(repeating: "a", count: 41)

    /// Values that must never show up in a refusal's description.
    static let secrets = ["secret_value_x", "someone@example.com", longLowercase, "Haferflocken"]
}

struct AnalyticsBadValueRow: Sendable, CustomTestStringConvertible {
    let why: String
    let value: String
    var testDescription: String { why }

    static let unsafe: [AnalyticsBadValueRow] = [
        AnalyticsBadValueRow(why: "an email", value: "someone@example.com"),
        AnalyticsBadValueRow(why: "41 lowercase characters", value: AllowListFixture.longLowercase),
        AnalyticsBadValueRow(why: "a food name", value: "Haferflocken"),
        AnalyticsBadValueRow(why: "two words", value: "two words"),
        AnalyticsBadValueRow(why: "empty", value: ""),
        AnalyticsBadValueRow(why: "a trailing newline", value: "1\n"),
        AnalyticsBadValueRow(why: "a hyphen", value: "oat-meal"),
    ]

    /// Safe words that aren't on `rank_position`'s list.
    static let unlisted: [AnalyticsBadValueRow] = [
        AnalyticsBadValueRow(why: "a bool word", value: "true"),
        AnalyticsBadValueRow(why: "an off-by-one rank", value: "11"),
        AnalyticsBadValueRow(why: "zero", value: "0"),
        AnalyticsBadValueRow(why: "a spelled-out plus", value: "10_plus"),
        AnalyticsBadValueRow(why: "a plain word", value: "secret_value_x"),
    ]
}

struct AnalyticsKeyRow: Sendable, CustomTestStringConvertible {
    let key: String
    let denied: Bool
    var testDescription: String { "\(key) -> \(denied ? "denied" : "allowed")" }

    static let all: [AnalyticsKeyRow] = AllowListFixture.deniedKeys.map { AnalyticsKeyRow(key: $0, denied: true) }
        + [
            // Case-insensitive, and the two prefixes.
            "Sleep_Hours", "QualityBucket", "FOOD_NAME", "Email", "HRV_MS", "sleep_", "sleep_hours", "quality", "quality_bucket",
        ].map { AnalyticsKeyRow(key: $0, denied: true) }
        + [
            // What the catalogue uses, which must stay clear of the list (`query_length` is not `query`).
            "step", "screen", "feature", "status", "code", "lookup", "query_length", "results_count", "has_results",
            "latency_ms", "rank_position", "is_canonical_staple", "entry_point", "unit_mode", "trigger_source", "duration_ms",
            // The SDK's own.
            "$lib", "$app_version",
            // Not a prefix match in the middle.
            "my_name_is", "weighted",
        ].map { AnalyticsKeyRow(key: $0, denied: false) }
}

struct AnalyticsValueRow: Sendable, CustomTestStringConvertible {
    let value: String
    let unsafe: Bool
    var testDescription: String { "\(value.debugDescription) ->\(unsafe ? "unsafe" : "safe")" }

    static let all: [AnalyticsValueRow] = [
        "1", "true", "false", "1_2", "3_5", "21+", "10+", "5000+", "lt_250", "profile_button", "a",
        String(repeating: "a", count: 40), String(repeating: "9", count: 40),
    ].map { AnalyticsValueRow(value: $0, unsafe: false) }
        + [
            "", "someone@example.com", "a@b", AllowListFixture.longLowercase, String(repeating: "a", count: 100), "Haferflocken",
            "two words", "oat-meal", "a.b", "1\n", "\n", "é", "True", "A", " ", "1 ", "$lib", "a,b", "a/b", "😀",
        ].map { AnalyticsValueRow(value: $0, unsafe: true) }
}

@Suite("Analytics: the allow-list")
@MainActor
struct AnalyticsAllowListTests {
    private func openRig() -> AnalyticsRig {
        let rig = AnalyticsRig()
        rig.optIn()
        // Everything below rests on this: a refusal is the only reason nothing arrives.
        #expect(rig.analytics.running != nil)
        #expect(rig.sink.captures.isEmpty)
        return rig
    }

    private func expectRefused(_ rig: AnalyticsRig, _ refusal: AnalyticsCatalog.Refusal, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(rig.sink.captures.isEmpty, sourceLocation: sourceLocation)
        #expect(rig.sink.queued.isEmpty, sourceLocation: sourceLocation)
        #expect(rig.refusals == [refusal], sourceLocation: sourceLocation)
    }

    // MARK: the control: a valid event gets through

    @Test func aValidEventReachesTheSinkAndRefusesNothing() {
        let rig = openRig()
        rig.analytics.deliver(AllowListFixture.event, properties: AllowListFixture.valid)
        #expect(rig.sink.captures == [.init(name: AllowListFixture.event, properties: AllowListFixture.valid)])
        #expect(rig.refusals.isEmpty)
    }

    @Test func aTypedEventReachesTheSinkWithItsNameAndProperties() {
        let rig = openRig()
        rig.analytics.track(AnalyticsEventFixture.foodOpened)
        #expect(rig.sink.captures == [.init(name: AllowListFixture.event, properties: [
            "rank_position": "3", "is_canonical_staple": "true", "has_default_portion": "true",
            "has_last_used_portion": "false",
        ])])
        #expect(rig.refusals.isEmpty)
    }

    @Test func everyTypedEventPassesTheCheckAndTheSink() {
        let rig = openRig()
        for event in AnalyticsEvent.everyCase {
            #expect(AnalyticsCatalog.check(name: event.name, properties: event.properties) == nil, "\(event)")
            rig.analytics.track(event)
        }
        #expect(rig.refusals.isEmpty)
        #expect(rig.sink.captures.count == AnalyticsEvent.everyCase.count)
    }

    // MARK: A1: a denied key never reaches the sink, even on a listed event

    @Test(arguments: AllowListFixture.deniedKeys + AllowListFixture.deniedKeyVariants)
    func aDeniedKeyOnAListedEventIsRefused(_ key: String) {
        let rig = openRig()
        rig.analytics.deliver(AllowListFixture.event, properties: AllowListFixture.validWith([key: "1"]))
        expectRefused(rig, .deniedKey(event: AllowListFixture.event, key: key))
    }

    @Test(arguments: AllowListFixture.deniedKeys)
    func aDeniedKeyIsRefusedAsDeniedAlsoWithAnUnsafeValue(_ key: String) {
        let rig = openRig()
        rig.analytics.deliver(AllowListFixture.event, properties: AllowListFixture.validWith([key: "someone@example.com"]))
        expectRefused(rig, .deniedKey(event: AllowListFixture.event, key: key))
    }

    // MARK: A1: an unsafe value never reaches the sink, even on a listed key

    @Test(arguments: AnalyticsBadValueRow.unsafe)
    func anUnsafeValueOnAListedKeyIsRefused(_ row: AnalyticsBadValueRow) {
        let rig = openRig()
        rig.analytics.deliver(AllowListFixture.event, properties: AllowListFixture.validWith(["rank_position": row.value]))
        // The unsafe check runs before the list check, so an unsafe value is always `.unsafeValue`.
        expectRefused(rig, .unsafeValue(event: AllowListFixture.event, key: "rank_position"))
    }

    @Test(arguments: AnalyticsBadValueRow.unlisted)
    func aSafeValueThatIsNotOnTheKeysListIsRefused(_ row: AnalyticsBadValueRow) {
        let rig = openRig()
        rig.analytics.deliver(AllowListFixture.event, properties: AllowListFixture.validWith(["rank_position": row.value]))
        expectRefused(rig, .valueNotAllowed(event: AllowListFixture.event, key: "rank_position"))
    }

    @Test(arguments: ["is_canonical_staple", "has_default_portion", "has_last_used_portion"])
    func aBoolKeyTakesOnlyTrueOrFalse(_ key: String) {
        for value in ["yes", "1", "TRUE", "True", "nil"] {
            let rig = openRig()
            rig.analytics.deliver(AllowListFixture.event, properties: AllowListFixture.validWith([key: value]))
            #expect(rig.sink.captures.isEmpty, "\(key) = \(value)")
            #expect(rig.refusals.count == 1, "\(key) = \(value)")
        }
    }

    // MARK: A1: unknown names and keys, missing keys

    @Test(arguments: ["nutrition_food_searched", "unknown_event", "", "Nutrition_Food_Opened", "nutrition_food_opened ", "$pageview"])
    func anUnknownEventNameIsRefused(_ name: String) {
        let rig = openRig()
        rig.analytics.deliver(name, properties: AllowListFixture.valid)
        expectRefused(rig, .unknownEvent)
    }

    @Test func anUnknownEventWithNoPropertiesIsRefused() {
        let rig = openRig()
        rig.analytics.deliver("made_up", properties: [:])
        expectRefused(rig, .unknownEvent)
    }

    @Test func aListedEventWithAnExtraUnknownKeyIsRefused() {
        let rig = openRig()
        rig.analytics.deliver(AllowListFixture.event, properties: AllowListFixture.validWith(["extra_key": "1"]))
        expectRefused(rig, .unknownKey(event: AllowListFixture.event, key: "extra_key"))
    }

    @Test func aKeyOfAnotherEventIsUnknownHere() {
        let rig = openRig()
        rig.analytics.deliver(AllowListFixture.event, properties: AllowListFixture.validWith(["lookup": "name"]))
        expectRefused(rig, .unknownKey(event: AllowListFixture.event, key: "lookup"))
    }

    @Test(arguments: AllowListFixture.validKeys)
    func aListedEventWithAKeyMissingIsRefused(_ missing: String) {
        let rig = openRig()
        var properties = AllowListFixture.valid
        properties[missing] = nil
        rig.analytics.deliver(AllowListFixture.event, properties: properties)
        expectRefused(rig, .missingKey(event: AllowListFixture.event, key: missing))
    }

    @Test func aListedEventWithNoPropertiesAtAllIsRefused() {
        let rig = openRig()
        rig.analytics.deliver(AllowListFixture.event, properties: [:])
        #expect(rig.sink.captures.isEmpty)
        #expect(rig.refusals.count == 1)
    }

    @Test func aPropertyOnAnEventThatTakesNoneIsRefused() {
        let rig = openRig()
        rig.analytics.deliver("health_access_requested", properties: ["screen": "today"])
        expectRefused(rig, .unknownKey(event: "health_access_requested", key: "screen"))
    }

    // MARK: the refusal comes before the gate, and a closed gate is not a refusal

    @Test func aRefusalIsReportedAlsoWhileTheGateIsClosed() {
        let rig = AnalyticsRig()
        rig.analytics.deliver("made_up", properties: [:])
        #expect(rig.sink.calls.isEmpty)
        #expect(rig.refusals == [.unknownEvent])
    }

    @Test func aValidEventWhileTheGateIsClosedIsDroppedWithoutARefusal() {
        let rig = AnalyticsRig()
        rig.analytics.deliver(AllowListFixture.event, properties: AllowListFixture.valid)
        #expect(rig.sink.calls.isEmpty)
        #expect(rig.refusals.isEmpty)
    }

    @Test func eachRefusalIsReportedOnceAndOnlyForItself() {
        let rig = openRig()
        rig.analytics.deliver("made_up", properties: [:])
        rig.analytics.deliver(AllowListFixture.event, properties: AllowListFixture.validWith(["email": "1"]))
        rig.analytics.deliver(AllowListFixture.event, properties: AllowListFixture.valid)
        #expect(rig.refusals == [.unknownEvent, .deniedKey(event: AllowListFixture.event, key: "email")])
        #expect(rig.sink.captures.count == 1)
    }

    // MARK: the checks themselves

    @Test(arguments: AnalyticsKeyRow.all)
    func theDenyList(_ row: AnalyticsKeyRow) {
        #expect(AnalyticsCatalog.isDeniedKey(row.key) == row.denied)
    }

    @Test(arguments: AnalyticsValueRow.all)
    func theUnsafeValueCheck(_ row: AnalyticsValueRow) {
        #expect(AnalyticsCatalog.isUnsafeValue(row.value) == row.unsafe)
    }

    @Test func aFortyCharacterWordIsSafeAndFortyOneIsNot() {
        #expect(!AnalyticsCatalog.isUnsafeValue(String(repeating: "a", count: 40)))
        #expect(AnalyticsCatalog.isUnsafeValue(String(repeating: "a", count: 41)))
    }

    // MARK: A2: the catalogue is what the typed events produce, both ways

    private struct Triple: Hashable {
        let name: String
        let key: String
        let value: String
    }

    /// name → key → values, from what every typed event produces. An event with no properties still has its name.
    private func produced() -> [String: [String: Set<String>]] {
        var result: [String: [String: Set<String>]] = [:]
        for event in AnalyticsEvent.everyCase {
            var keys = result[event.name, default: [:]]
            for (key, value) in event.properties { keys[key, default: []].insert(value) }
            result[event.name] = keys
        }
        return result
    }

    private func triples(_ events: [String: [String: Set<String>]]) -> Set<Triple> {
        var result: Set<Triple> = []
        for (name, keys) in events {
            for (key, values) in keys {
                for value in values { result.insert(Triple(name: name, key: key, value: value)) }
            }
        }
        return result
    }

    @Test func theCatalogueEqualsWhatTheTypedEventsProduce() {
        #expect(produced() == AnalyticsCatalog.events)
    }

    @Test func noTypedEventProducesAnythingTheCatalogueLacks() {
        let extra = triples(produced()).subtracting(triples(AnalyticsCatalog.events))
        #expect(extra.isEmpty, "\(extra)")
    }

    @Test func theCatalogueListsNothingNoTypedEventProduces() {
        let unused = triples(AnalyticsCatalog.events).subtracting(triples(produced()))
        #expect(unused.isEmpty, "\(unused)")
    }

    @Test func theCatalogueAndTheTypedEventsAgreeOnTheEventNames() {
        #expect(Set(produced().keys) == Set(AnalyticsCatalog.events.keys))
        #expect(AnalyticsCatalog.eventNames == Set(AnalyticsCatalog.events.keys))
        #expect(AnalyticsCatalog.eventNames == Set(AnalyticsEvent.everyCase.map(\.name)))
    }

    @Test func thePropertyKeysAreTheUnionOfEveryEventsKeys() {
        let union = AnalyticsCatalog.events.values.reduce(into: Set<String>()) { $0.formUnion($1.keys) }
        #expect(AnalyticsCatalog.propertyKeys == union)
        #expect(AnalyticsCatalog.propertyKeys == Set(AnalyticsEvent.everyCase.flatMap { $0.properties.keys }))
    }

    @Test func everyCatalogueKeyHasAtLeastOneValue() {
        for (name, keys) in AnalyticsCatalog.events {
            for (key, values) in keys { #expect(!values.isEmpty, "\(name).\(key)") }
        }
    }

    /// The design's table, as literals: the dashboards' contract, independent of the token types.
    @Test func theNewEventsAreExactlyThePlansTable() {
        let bools: Set<String> = ["true", "false"]
        #expect(AnalyticsCatalog.events["nutrition_search_completed"] == [
            "lookup": ["name", "barcode"],
            "query_length": ["1_2", "3_5", "6_10", "11_20", "21+"],
            "results_count": ["0", "1", "2_5", "6_10", "11_20", "21+"],
            "has_results": bools,
            "latency_ms": ["lt_250", "250_499", "500_999", "1000_1999", "2000_4999", "5000+"],
        ])
        #expect(AnalyticsCatalog.events["nutrition_food_opened"] == [
            "rank_position": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "10+"],
            "is_canonical_staple": bools, "has_default_portion": bools, "has_last_used_portion": bools,
        ])
        #expect(AnalyticsCatalog.events["nutrition_food_logged"] == [
            "entry_point": ["quick_add_button", "detail_sheet", "barcode", "suggestion", "private_food"],
            "unit_mode": ["curated_portion", "last_used_portion", "grams", "ml"],
            "is_fractional": bools,
        ])
        #expect(AnalyticsCatalog.events["nutrition_diary_reopened"] == ["has_preserved_portion_label": bools])
        #expect(AnalyticsCatalog.events["sync_triggered"] == ["trigger_source": ["profile_button"]])
        #expect(AnalyticsCatalog.events["sync_completed"] == [
            "trigger_source": ["profile_button"], "status": ["success", "failed", "skipped", "deferred"],
            "duration_ms": ["lt_1000", "1000_4999", "5000_14999", "15000_59999", "60000+"],
        ])
    }

    @Test func theExistingEventsKeepTheirKeys() {
        #expect(AnalyticsCatalog.events["onboarding_step"]?.keys.sorted() == ["step"])
        #expect(AnalyticsCatalog.events["screen_viewed"]?.keys.sorted() == ["screen"])
        #expect(AnalyticsCatalog.events["feature_used"]?.keys.sorted() == ["feature"])
        #expect(AnalyticsCatalog.events["error_shown"]?.keys.sorted() == ["code", "status"])
        #expect(AnalyticsCatalog.events["health_access_requested"] == [:])
        #expect(AnalyticsCatalog.events["first_sync_completed"] == [:])
    }

    // MARK: A3: nothing allowed is denied or unsafe

    @Test func noCatalogueKeyIsDenied() {
        let denied = AnalyticsCatalog.propertyKeys.filter(AnalyticsCatalog.isDeniedKey)
        #expect(denied.isEmpty, "\(denied.sorted())")
    }

    @Test func noCatalogueValueIsUnsafe() {
        for (name, keys) in AnalyticsCatalog.events {
            for (key, values) in keys {
                for value in values { #expect(!AnalyticsCatalog.isUnsafeValue(value), "\(name).\(key) = \(value)") }
            }
        }
    }

    @Test func catalogueNamesAndKeysAreLowercaseWords() {
        for word in AnalyticsCatalog.eventNames.union(AnalyticsCatalog.propertyKeys) {
            #expect(word.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil, "\(word)")
        }
    }

    @Test func theSDKListsAreNotEmptyAndDoNotOverlapOurs() {
        #expect(!AnalyticsCatalog.sdkEventNames.isEmpty)
        #expect(!AnalyticsCatalog.sdkPropertyKeys.isEmpty)
        #expect(AnalyticsCatalog.sdkEventNames.isDisjoint(with: AnalyticsCatalog.eventNames))
        #expect(AnalyticsCatalog.sdkPropertyKeys.isDisjoint(with: AnalyticsCatalog.propertyKeys))
    }

    @Test func noSDKKeyIsDenied() {
        let denied = AnalyticsCatalog.sdkPropertyKeys.filter(AnalyticsCatalog.isDeniedKey)
        #expect(denied.isEmpty, "\(denied.sorted())")
    }

    // MARK: a refusal never carries a value

    @Test(arguments: AllowListFixture.secrets)
    func aRefusalForAValueNamesTheEventAndTheKeyButNotTheValue(_ secret: String) throws {
        let refusal = try #require(AnalyticsCatalog.check(
            name: AllowListFixture.event, properties: AllowListFixture.validWith(["rank_position": secret])))
        let text = refusal.description
        #expect(!text.contains(secret), "\(text)")
        #expect(!"\(refusal)".contains(secret))
        #expect(!String(reflecting: refusal).contains(secret))
        #expect(text.contains(AllowListFixture.event) && text.contains("rank_position"), "\(text)")
    }

    @Test(arguments: AllowListFixture.secrets)
    func aRefusalForADeniedKeyDoesNotCarryItsValue(_ secret: String) throws {
        let refusal = try #require(AnalyticsCatalog.check(
            name: AllowListFixture.event, properties: AllowListFixture.validWith(["food_name": secret])))
        #expect(refusal == .deniedKey(event: AllowListFixture.event, key: "food_name"))
        #expect(!refusal.description.contains(secret))
        #expect(refusal.description.contains("food_name"))
    }

    @Test func everyRefusalNamesItsEventAndKey() {
        let refusals: [AnalyticsCatalog.Refusal] = [
            .unknownKey(event: "event_aa", key: "key_bb"), .deniedKey(event: "event_aa", key: "key_bb"),
            .valueNotAllowed(event: "event_aa", key: "key_bb"), .unsafeValue(event: "event_aa", key: "key_bb"),
            .missingKey(event: "event_aa", key: "key_bb"),
        ]
        for refusal in refusals {
            #expect(refusal.description.contains("event_aa") && refusal.description.contains("key_bb"), "\(refusal)")
        }
        #expect(!AnalyticsCatalog.Refusal.unknownEvent.description.isEmpty)
    }
}
