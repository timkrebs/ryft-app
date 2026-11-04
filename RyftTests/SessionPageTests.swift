import Foundation
import Testing
@testable import Ryft

/// The Focused layout's page rules, pure (architecture.md §1, §2; ADR 0013): which exercise shows, where the page goes
/// when one leaves, and which layout a session opens in. No SwiftData, no clock.
struct SessionPageTests {
    private typealias A = SessionAdvance

    /// `done` marks completed sets by index, `warmups` the warm-up indices.
    private func ex(sets n: Int, done: Set<Int> = [], warmups: Set<Int> = []) -> A.ExerciseState {
        A.ExerciseState(id: UUID(), supersetGroup: nil, sets: (0..<n).map {
            A.SetState(id: UUID(), isWarmup: warmups.contains($0), isCompleted: done.contains($0))
        })
    }

    // MARK: resolve

    @Test func theStoredPageWinsWhileItsRowExists() {
        let a = ex(sets: 2), b = ex(sets: 2), c = ex(sets: 2)
        #expect(SessionPage.resolve(stored: c.id, in: [a, b, c]) == c.id)
        #expect(SessionPage.resolve(stored: b.id, in: [a, b, c]) == b.id)
    }

    @Test func aStoredPageThatIsDoneStillShows() {
        let a = ex(sets: 2), b = ex(sets: 2, done: [0, 1])
        #expect(SessionPage.resolve(stored: b.id, in: [a, b]) == b.id, "finished exercises are reachable and don't move")
    }

    @Test func withNothingStoredTheFirstExerciseWithAnOpenWorkingSetShows() {
        let a = ex(sets: 2, done: [0, 1]), b = ex(sets: 3, done: [0]), c = ex(sets: 2)
        #expect(SessionPage.resolve(stored: nil, in: [a, b, c]) == b.id)
    }

    @Test func aStoredPageWhoseRowIsGoneFallsBackTheSameWay() {
        let a = ex(sets: 2, done: [0, 1]), b = ex(sets: 2)
        #expect(SessionPage.resolve(stored: UUID(), in: [a, b]) == b.id)
    }

    @Test func anOpenWarmUpAloneDoesNotMakeAnExerciseTheFallback() {
        let a = ex(sets: 2, done: [1], warmups: [0]), b = ex(sets: 2)
        #expect(SessionPage.resolve(stored: nil, in: [a, b]) == b.id)
    }

    @Test func withEverythingDoneTheLastExerciseShows() {
        let a = ex(sets: 2, done: [0, 1]), b = ex(sets: 2, done: [0, 1])
        #expect(SessionPage.resolve(stored: nil, in: [a, b]) == b.id)
        #expect(SessionPage.resolve(stored: UUID(), in: [a, b]) == b.id)
    }

    @Test func noExercisesMeansNoPage() {
        #expect(SessionPage.resolve(stored: nil, in: []) == nil)
        #expect(SessionPage.resolve(stored: UUID(), in: []) == nil)
    }

    // MARK: neighbour

    @Test func removingTheMiddleGoesToTheNextOne() {
        let ids = (0..<3).map { _ in UUID() }
        #expect(SessionPage.neighbour(of: ids[1], in: ids) == ids[2])
        #expect(SessionPage.neighbour(of: ids[0], in: ids) == ids[1])
    }

    @Test func removingTheLastGoesToThePreviousOne() {
        let ids = (0..<3).map { _ in UUID() }
        #expect(SessionPage.neighbour(of: ids[2], in: ids) == ids[1])
        #expect(SessionPage.neighbour(of: ids[1], in: Array(ids[0...1])) == ids[0])
    }

    @Test func theOnlyExerciseHasNoNeighbour() {
        let id = UUID()
        #expect(SessionPage.neighbour(of: id, in: [id]) == nil)
    }

    @Test func anIdThatIsNotInTheOrderHasNoNeighbour() {
        let ids = (0..<2).map { _ in UUID() }
        #expect(SessionPage.neighbour(of: UUID(), in: ids) == nil)
        #expect(SessionPage.neighbour(of: UUID(), in: []) == nil)
    }

    // MARK: the layout a session opens in (plan.md L5)

    struct LayoutCase: Sendable, CustomTestStringConvertible {
        let flagOn: Bool
        let stored: SessionLayout
        let expected: SessionLayout
        var testDescription: String { "flag \(flagOn ? "on" : "off"), stored \(stored.rawValue) -> \(expected.rawValue)" }
    }

    static let layoutCases: [LayoutCase] = [
        LayoutCase(flagOn: false, stored: .focused, expected: .list),
        LayoutCase(flagOn: false, stored: .list, expected: .list),
        LayoutCase(flagOn: true, stored: .focused, expected: .focused),
        LayoutCase(flagOn: true, stored: .list, expected: .list),
    ]

    @Test(arguments: layoutCases)
    func theEffectiveLayoutIsTheStoredChoiceOnlyWithTheFlagOn(_ c: LayoutCase) {
        #expect(SessionLayout.effective(flagOn: c.flagOn, stored: c.stored) == c.expected)
    }

    @Test func everyLayoutIsCoveredByTheTable() {
        for layout in SessionLayout.allCases {
            #expect(Self.layoutCases.contains { $0.stored == layout }, "\(layout)")
        }
        #expect(Self.layoutCases.count == 2 * SessionLayout.allCases.count)
    }

    /// The flag as the app asks it: absent (no config yet) is off, so List, with Focused stored.
    @MainActor
    @Test func anAbsentFlagIsOffAndOpensList() {
        let defaults = UserDefaults(suiteName: "ryft.test.layout.\(UUID().uuidString)") ?? .standard
        let flags = FlagStore(store: TrainStore(inMemory: true), defaults: defaults)
        #expect(!flags.isOn(.focusedSession), "absent means off")
        #expect(SessionLayout.effective(flagOn: flags.isOn(.focusedSession), stored: .focused) == .list)
    }

    @MainActor
    @Test func theRemoteFlagTurnsTheStoredChoiceOn() {
        let defaults = UserDefaults(suiteName: "ryft.test.layout.\(UUID().uuidString)") ?? .standard
        let flags = FlagStore(store: TrainStore(inMemory: true), defaults: defaults)
        flags.apply(RemoteConfig(flags: ["train.focused_session": true], evaluatedAt: .now, ttlSec: 3600), fetchedAt: .now)
        #expect(flags.isOn(.focusedSession))
        #expect(SessionLayout.effective(flagOn: flags.isOn(.focusedSession), stored: .focused) == .focused)
        #expect(SessionLayout.effective(flagOn: flags.isOn(.focusedSession), stored: .list) == .list)
    }

    @MainActor
    @Test func noStoredChoiceMeansFocusedAndANonsenseOneToo() {
        let defaults = UserDefaults(suiteName: "ryft.test.layout.\(UUID().uuidString)") ?? .standard
        #expect(Settings(defaults: defaults).sessionLayout == .focused)
        defaults.set("carousel", forKey: "train.sessionLayout")
        #expect(Settings(defaults: defaults).sessionLayout == .focused)
        defaults.set("list", forKey: "train.sessionLayout")
        #expect(Settings(defaults: defaults).sessionLayout == .list)
    }

    @MainActor
    @Test func theChoiceIsStoredUnderItsKey() {
        let defaults = UserDefaults(suiteName: "ryft.test.layout.\(UUID().uuidString)") ?? .standard
        let settings = Settings(defaults: defaults)
        settings.sessionLayout = .list
        #expect(defaults.string(forKey: "train.sessionLayout") == "list")
        #expect(Settings(defaults: defaults).sessionLayout == .list)
    }

    @Test func theFlagsRawKeyIsTheOneTheRemoteConfigSends() {
        #expect(FeatureFlag.focusedSession.rawValue == "train.focused_session")
        #expect(FeatureFlag.focusedSession.compiledDefault == false, "ships dark")
    }
}
