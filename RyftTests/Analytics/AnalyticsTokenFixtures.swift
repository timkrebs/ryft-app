import Foundation
@testable import Ryft

extension AnalyticsToken {
    /// Every raw value of the token, as the dashboards see them.
    static var rawValues: Set<String> { Set(allCases.map(\.rawValue)) }

    /// A token by its raw value, so a test names the dashboards' word and not the Swift case. A raw value the token
    /// doesn't have is a programming error in the test (and a loud one).
    static func fixture(_ raw: String) -> Self {
        guard let token = Self(rawValue: raw) else {
            preconditionFailure("\(Self.self) has no raw value \"\(raw)\"")
        }
        return token
    }
}

/// One example of each new event, with typed parameters from the buckets' own initialisers where there is one.
enum AnalyticsEventFixture {
    static let searchCompleted = AnalyticsEvent.nutritionSearchCompleted(
        lookup: .fixture("name"), queryLength: AnalyticsQueryLength(characters: 4), results: AnalyticsResultCount(3),
        latency: AnalyticsLatency(.milliseconds(300)))
    static let foodOpened = AnalyticsEvent.nutritionFoodOpened(
        rank: AnalyticsRank(position: 3), isCanonicalStaple: true, hasDefaultPortion: true, hasLastUsedPortion: false)
    static let foodLogged = AnalyticsEvent.nutritionFoodLogged(
        entryPoint: .fixture("quick_add_button"), unitMode: .fixture("curated_portion"), isFractional: false)
    static let diaryReopened = AnalyticsEvent.nutritionDiaryReopened(hasPreservedPortionLabel: true)
    static let syncTriggered = AnalyticsEvent.syncTriggered(.fixture("profile_button"))
    static let syncCompleted = AnalyticsEvent.syncCompleted(
        .fixture("profile_button"), status: .fixture("success"), duration: AnalyticsSyncDuration(.seconds(2)))
}

/// Records what `Analytics` refuses (`onRefused`), in order.
@MainActor
final class RefusalLog {
    private(set) var all: [AnalyticsCatalog.Refusal] = []
    func record(_ refusal: AnalyticsCatalog.Refusal) { all.append(refusal) }
}
