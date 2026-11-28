import Foundation
import Testing
@testable import Ryft

/// An integer input and the bucket's raw value (the dashboards' word) it must land in.
struct AnalyticsIntBucketRow: Sendable, CustomTestStringConvertible {
    let input: Int
    let expected: String
    var testDescription: String { "\(input) -> \(expected)" }

    private static func rows(_ pairs: [(Int, String)]) -> [AnalyticsIntBucketRow] {
        pairs.map { AnalyticsIntBucketRow(input: $0.0, expected: $0.1) }
    }

    static let queryLength = rows([
        (Int.min, "1_2"), (-1, "1_2"), (0, "1_2"), (1, "1_2"), (2, "1_2"), (3, "3_5"), (5, "3_5"), (6, "6_10"), (10, "6_10"),
        (11, "11_20"), (20, "11_20"), (21, "21+"), (100, "21+"), (Int.max, "21+"),
    ])

    static let results = rows([
        (Int.min, "0"), (-1, "0"), (0, "0"), (1, "1"), (2, "2_5"), (5, "2_5"), (6, "6_10"), (10, "6_10"), (11, "11_20"),
        (20, "11_20"), (21, "21+"), (500, "21+"), (Int.max, "21+"),
    ])

    static let rank = rows([
        (Int.min, "1"), (-1, "1"), (0, "1"), (1, "1"), (2, "2"), (3, "3"), (4, "4"), (5, "5"), (6, "6"), (7, "7"), (8, "8"),
        (9, "9"), (10, "10"), (11, "10+"), (1000, "10+"), (Int.max, "10+"),
    ])
}

/// A duration in milliseconds and the bucket it must land in.
struct AnalyticsDurationBucketRow: Sendable, CustomTestStringConvertible {
    let milliseconds: Int64
    let expected: String
    var testDescription: String { "\(milliseconds) ms -> \(expected)" }

    private static func rows(_ pairs: [(Int64, String)]) -> [AnalyticsDurationBucketRow] {
        pairs.map { AnalyticsDurationBucketRow(milliseconds: $0.0, expected: $0.1) }
    }

    static let latency = rows([
        (Int64.min, "lt_250"), (-1, "lt_250"), (0, "lt_250"), (249, "lt_250"), (250, "250_499"), (499, "250_499"),
        (500, "500_999"), (999, "500_999"), (1000, "1000_1999"), (1999, "1000_1999"), (2000, "2000_4999"),
        (4999, "2000_4999"), (5000, "5000+"), (3_600_000, "5000+"), (Int64.max, "5000+"),
    ])

    static let syncDuration = rows([
        (Int64.min, "lt_1000"), (-1, "lt_1000"), (0, "lt_1000"), (999, "lt_1000"), (1000, "1000_4999"),
        (4999, "1000_4999"), (5000, "5000_14999"), (14999, "5000_14999"), (15000, "15000_59999"),
        (59999, "15000_59999"), (60000, "60000+"), (3_600_000, "60000+"), (Int64.max, "60000+"),
    ])
}

struct AnalyticsBoolRow: Sendable, CustomTestStringConvertible {
    let first: Bool
    let second: Bool
    let third: Bool
    var testDescription: String { "\(first), \(second), \(third)" }

    static let all: [AnalyticsBoolRow] = [false, true].flatMap { first in
        [false, true].flatMap { second in [false, true].map { AnalyticsBoolRow(first: first, second: second, third: $0) } }
    }
}

@Suite("Analytics: the buckets")
@MainActor
struct AnalyticsBucketTests {
    // MARK: A4: boundaries (each init is total, so every row has an answer)

    @Test(arguments: AnalyticsIntBucketRow.queryLength)
    func queryLengthBuckets(_ row: AnalyticsIntBucketRow) {
        #expect(AnalyticsQueryLength(characters: row.input).rawValue == row.expected)
    }

    @Test(arguments: AnalyticsIntBucketRow.results)
    func resultCountBuckets(_ row: AnalyticsIntBucketRow) {
        #expect(AnalyticsResultCount(row.input).rawValue == row.expected)
    }

    @Test(arguments: AnalyticsIntBucketRow.rank)
    func rankBuckets(_ row: AnalyticsIntBucketRow) {
        #expect(AnalyticsRank(position: row.input).rawValue == row.expected)
    }

    @Test(arguments: AnalyticsDurationBucketRow.latency)
    func latencyBuckets(_ row: AnalyticsDurationBucketRow) {
        #expect(AnalyticsLatency(.milliseconds(row.milliseconds)).rawValue == row.expected)
    }

    @Test(arguments: AnalyticsDurationBucketRow.syncDuration)
    func syncDurationBuckets(_ row: AnalyticsDurationBucketRow) {
        #expect(AnalyticsSyncDuration(.milliseconds(row.milliseconds)).rawValue == row.expected)
    }

    @Test func aDurationInSecondsLandsWhereItsMillisecondsDo() {
        #expect(AnalyticsLatency(.seconds(2)).rawValue == "2000_4999")
        #expect(AnalyticsSyncDuration(.seconds(15)).rawValue == "15000_59999")
        #expect(AnalyticsSyncDuration(.seconds(60) - .milliseconds(1)).rawValue == "15000_59999")
        #expect(AnalyticsSyncDuration(.seconds(60)).rawValue == "60000+")
    }

    // MARK: A4: every bucket is reachable and nothing falls outside the list

    @Test func theRowsReachEveryBucketOfEveryType() {
        #expect(Set(AnalyticsIntBucketRow.queryLength.map(\.expected)) == AnalyticsQueryLength.rawValues)
        #expect(Set(AnalyticsIntBucketRow.results.map(\.expected)) == AnalyticsResultCount.rawValues)
        #expect(Set(AnalyticsIntBucketRow.rank.map(\.expected)) == AnalyticsRank.rawValues)
        #expect(Set(AnalyticsDurationBucketRow.latency.map(\.expected)) == AnalyticsLatency.rawValues)
        #expect(Set(AnalyticsDurationBucketRow.syncDuration.map(\.expected)) == AnalyticsSyncDuration.rawValues)
    }

    @Test func rankIsItsOwnPositionUpToTenAndTenPlusAfter() {
        for position in 1...10 { #expect(AnalyticsRank(position: position).rawValue == String(position)) }
        for position in 11...40 { #expect(AnalyticsRank(position: position).rawValue == "10+", "\(position)") }
    }

    @Test func aSweepOfEveryCountAndDurationAlwaysLandsOnAListedToken() {
        for value in -5...700 {
            #expect(AnalyticsQueryLength.rawValues.contains(AnalyticsQueryLength(characters: value).rawValue), "\(value)")
            #expect(AnalyticsResultCount.rawValues.contains(AnalyticsResultCount(value).rawValue), "\(value)")
            #expect(AnalyticsRank.rawValues.contains(AnalyticsRank(position: value).rawValue), "\(value)")
        }
        for milliseconds in stride(from: Int64(-5), through: 70_000, by: 53) {
            #expect(AnalyticsLatency.rawValues.contains(AnalyticsLatency(.milliseconds(milliseconds)).rawValue))
            #expect(AnalyticsSyncDuration.rawValues.contains(AnalyticsSyncDuration(.milliseconds(milliseconds)).rawValue))
        }
    }

    @Test func theBucketsAreMonotonic() {
        func order<T: AnalyticsToken>(_ type: T.Type) -> [String] { T.allCases.map(\.rawValue) }
        func indices(_ raws: [String], in order: [String]) -> [Int] { raws.map { order.firstIndex(of: $0) ?? -1 } }
        let latency = indices(stride(from: Int64(0), through: 6000, by: 50).map { AnalyticsLatency(.milliseconds($0)).rawValue },
                              in: order(AnalyticsLatency.self))
        #expect(latency == latency.sorted() && !latency.contains(-1))
        let sync = indices(stride(from: Int64(0), through: 70_000, by: 500).map {
            AnalyticsSyncDuration(.milliseconds($0)).rawValue
        }, in: order(AnalyticsSyncDuration.self))
        #expect(sync == sync.sorted() && !sync.contains(-1))
        let query = indices((0...40).map { AnalyticsQueryLength(characters: $0).rawValue }, in: order(AnalyticsQueryLength.self))
        #expect(query == query.sorted() && !query.contains(-1))
        let results = indices((0...40).map { AnalyticsResultCount($0).rawValue }, in: order(AnalyticsResultCount.self))
        #expect(results == results.sorted() && !results.contains(-1))
    }

    // MARK: has_results is derived from the results bucket

    @Test func hasResultsIsFalseExactlyForTheZeroBucket() {
        for results in AnalyticsResultCount.allCases {
            let event = AnalyticsEvent.nutritionSearchCompleted(
                lookup: .fixture("name"), queryLength: AnalyticsQueryLength(characters: 4), results: results,
                latency: AnalyticsLatency(.milliseconds(100)))
            #expect(event.properties["has_results"] == (results.rawValue == "0" ? "false" : "true"), "\(results.rawValue)")
            #expect(event.properties["results_count"] == results.rawValue)
        }
    }

    @Test func noResultsAndSomeResultsDisagreeWithNothing() {
        func hasResults(_ count: Int) -> String? {
            AnalyticsEvent.nutritionSearchCompleted(
                lookup: .fixture("barcode"), queryLength: AnalyticsQueryLength(characters: 13), results: AnalyticsResultCount(count),
                latency: AnalyticsLatency(.milliseconds(100))).properties["has_results"]
        }
        #expect(hasResults(0) == "false")
        #expect(hasResults(-3) == "false")
        #expect(hasResults(1) == "true")
        #expect(hasResults(500) == "true")
    }

    // MARK: bools are "true" or "false"

    @Test(arguments: AnalyticsBoolRow.all)
    func foodOpenedSerializesItsBools(_ row: AnalyticsBoolRow) {
        let properties = AnalyticsEvent.nutritionFoodOpened(
            rank: AnalyticsRank(position: 1), isCanonicalStaple: row.first, hasDefaultPortion: row.second,
            hasLastUsedPortion: row.third).properties
        #expect(properties["is_canonical_staple"] == (row.first ? "true" : "false"))
        #expect(properties["has_default_portion"] == (row.second ? "true" : "false"))
        #expect(properties["has_last_used_portion"] == (row.third ? "true" : "false"))
    }

    @Test(arguments: [false, true])
    func theOtherBoolsSerializeToo(_ flag: Bool) {
        let word = flag ? "true" : "false"
        #expect(AnalyticsEvent.nutritionFoodLogged(entryPoint: .fixture("barcode"), unitMode: .fixture("ml"),
                                                   isFractional: flag).properties["is_fractional"] == word)
        #expect(AnalyticsEvent.nutritionDiaryReopened(hasPreservedPortionLabel: flag)
            .properties == ["has_preserved_portion_label": word])
    }

    // MARK: the exact properties of one example per new event

    @Test func nutritionSearchCompletedProperties() {
        #expect(AnalyticsEventFixture.searchCompleted.name == "nutrition_search_completed")
        #expect(AnalyticsEventFixture.searchCompleted.properties == [
            "lookup": "name", "query_length": "3_5", "results_count": "2_5", "has_results": "true", "latency_ms": "250_499",
        ])
    }

    @Test func nutritionFoodOpenedProperties() {
        #expect(AnalyticsEventFixture.foodOpened.name == "nutrition_food_opened")
        #expect(AnalyticsEventFixture.foodOpened.properties == [
            "rank_position": "3", "is_canonical_staple": "true", "has_default_portion": "true",
            "has_last_used_portion": "false",
        ])
    }

    @Test func nutritionFoodLoggedProperties() {
        #expect(AnalyticsEventFixture.foodLogged.name == "nutrition_food_logged")
        #expect(AnalyticsEventFixture.foodLogged.properties == [
            "entry_point": "quick_add_button", "unit_mode": "curated_portion", "is_fractional": "false",
        ])
    }

    @Test func nutritionDiaryReopenedProperties() {
        #expect(AnalyticsEventFixture.diaryReopened.name == "nutrition_diary_reopened")
        #expect(AnalyticsEventFixture.diaryReopened.properties == ["has_preserved_portion_label": "true"])
    }

    @Test func syncTriggeredProperties() {
        #expect(AnalyticsEventFixture.syncTriggered.name == "sync_triggered")
        #expect(AnalyticsEventFixture.syncTriggered.properties == ["trigger_source": "profile_button", "previous_state": "stale"])
    }

    @Test func syncCompletedProperties() {
        #expect(AnalyticsEventFixture.syncCompleted.name == "sync_completed")
        #expect(AnalyticsEventFixture.syncCompleted.properties == [
            "trigger_source": "profile_button", "status": "success", "duration_ms": "1000_4999",
            "connected_providers_count": "1",
        ])
    }

    @Test func aBarcodeLookupIsNotMixedIntoTheNameLookup() {
        let barcode = AnalyticsEvent.nutritionSearchCompleted(
            lookup: .fixture("barcode"), queryLength: AnalyticsQueryLength(characters: 13), results: AnalyticsResultCount(1),
            latency: AnalyticsLatency(.milliseconds(700)))
        #expect(barcode.properties["lookup"] == "barcode")
        #expect(barcode.properties["query_length"] == "11_20")
    }
}
