import Foundation
import Testing
@testable import Ryft

@MainActor
private func makeStore(api: MockPlatformAPI = MockPlatformAPI(), online: Bool = true) -> (JournalStore, AppEnvironment) {
    // The mock answers relative to the real date, so the clock starts there too.
    let env = AppEnvironment.test(api: api, clock: TestClock(now: .now), online: online)
    return (JournalStore(env: env), env)
}

@MainActor
struct JournalStoreTests {
    @Test func a404HidesTheFeatureWithoutAnError() async {
        let api = MockPlatformAPI()
        api.journalLive = false
        let (store, _) = makeStore(api: api)
        await store.load()
        #expect(store.availability == .notLive && !store.isLive)
        #expect(store.error == nil)
    }

    @Test func theCatalogMakesItLiveAndIsCached() async {
        let (store, env) = makeStore()
        await store.load()
        #expect(store.isLive && store.behaviors.count == MockJournal.behaviors.count)
        // A relaunch offline has the catalog.
        #expect(JournalStore(env: env).behaviors.count == MockJournal.behaviors.count)
    }

    @Test func yesterdaysSummaryReadsLikeTheCard() async {
        let (store, _) = makeStore()
        await store.load()
        let day = await store.loadDay(store.yesterday)
        let summary = try? #require(day.flatMap(store.summary(of:)))
        #expect(summary?.contains("Drinks · 2") == true && summary?.contains("16:30") == true)
        #expect(summary?.contains("Screens in bed") == false)   // a "no" isn't listed
    }

    @Test func writesNeedTheNetwork() async {
        let api = MockPlatformAPI()
        let (store, _) = makeStore(api: api, online: false)
        await #expect(throws: JournalStore.JournalError.offline) {
            try await store.save(day: store.yesterday, entries: [])
        }
        #expect(api.count("putJournal") == 0)
    }

    @Test func aTakenIDIsReplacedOnce() async throws {
        let api = MockPlatformAPI()
        let (store, _) = makeStore(api: api)
        await store.load()
        // The built-in alcohol id is "taken": the store retries with a fresh one.
        let created = try await store.create(name: "Late screen work", nameDe: nil, kind: .yesNo, category: nil,
                                             id: MockJournal.alcohol)
        #expect(created.id != MockJournal.alcohol && created.isCustom)
        #expect(api.count("createBehavior") == 2)
        await #expect(throws: JournalStore.JournalError.idTaken) {
            try await store.create(name: "X", nameDe: nil, kind: .yesNo, category: nil,
                                   id: MockJournal.alcohol, retryID: MockJournal.sauna)
        }
    }

    @Test func onlyCustomBehaviorsAreDeleted() async throws {
        let api = MockPlatformAPI()
        let (store, _) = makeStore(api: api)
        await store.load()
        try await store.delete(MockJournal.alcohol)   // built-in: not offered, nothing sent
        #expect(api.count("deleteBehavior") == 0)
        try await store.delete(MockJournal.meeting)
        #expect(api.count("deleteBehavior") == 1 && store.behavior(MockJournal.meeting) == nil)
    }

    @Test func togglingReplacesTheCacheWithTheServersList() async throws {
        let (store, _) = makeStore()
        await store.load()
        try await store.setEnabled(MockJournal.magnesium, true)
        #expect(store.behavior(MockJournal.magnesium)?.enabled == true)
    }

    @Test func savingYesterdayRefreshesTheImpacts() async throws {
        let api = MockPlatformAPI()
        let (store, _) = makeStore(api: api)
        await store.load()
        try await store.save(day: store.yesterday, entries: [JournalEntry(behaviorId: MockJournal.sauna, valueBool: true)])
        #expect(await eventually { api.count("behaviorImpact") == 1 })
    }
}

@MainActor
struct JournalSheetTests {
    private func sheet(_ api: MockPlatformAPI = MockPlatformAPI(), day: String? = nil) async -> (JournalSheetModel, JournalStore) {
        let (store, _) = makeStore(api: api)
        await store.load()
        let model = JournalSheetModel(store: store, day: day)
        await model.load()
        return (model, store)
    }

    @Test func kindsGetTheirControls() {
        #expect(JournalSheetModel.Control(.yesNo) == .toggle)
        #expect(JournalSheetModel.Control(.count) == .stepper)
        #expect(JournalSheetModel.Control(.time) == .time)
    }

    @Test func rowsFollowTheServersOrderGroupedByCategory() async {
        let (model, store) = await sheet(day: "2026-01-01")   // nothing answered: enabled only
        let expected = store.behaviors.filter(\.enabled).map(\.id)
        #expect(model.groups.flatMap(\.rows).map(\.id) == expected)
        #expect(model.groups.map(\.category) == [.substances, .sleep, .recovery, .lifestyle, .custom])
        #expect(model.groups.flatMap(\.rows).allSatisfy { !$0.on })   // unanswered rows start off
    }

    @Test func thePutContainsEveryShownRow() async throws {
        let api = MockPlatformAPI()
        let (store, _) = makeStore(api: api)
        await store.load()
        let day = DayFormat.string(from: DayFormat.shift(.now, days: -3))
        let model = JournalSheetModel(store: store, day: day)
        await model.load()
        model.set(MockJournal.drinks, on: true)
        model.set(MockJournal.drinks, count: 3)
        model.set(MockJournal.lastCaffeine, on: true)
        model.set(MockJournal.lastCaffeine, time: "15:45")
        await model.save()
        let sent = try #require(api.journalPuts[day])
        #expect(sent.entries.map(\.behaviorId) == model.groups.flatMap(\.rows).map(\.id))
        #expect(sent.entries.first { $0.behaviorId == MockJournal.drinks }?.valueNum == 3)
        #expect(sent.entries.first { $0.behaviorId == MockJournal.lastCaffeine }?.valueTime == "15:45")
        let alcohol = try #require(sent.entries.first { $0.behaviorId == MockJournal.alcohol })
        #expect(!alcohol.valueBool && alcohol.valueNum == nil && alcohol.valueTime == nil)   // an explicit "no"
        #expect(model.saved)
    }

    @Test func yesterdayOpensWithItsAnswers() async {
        let (model, _) = await sheet()
        let drinks = model.groups.flatMap(\.rows).first { $0.id == MockJournal.drinks }
        #expect(drinks?.on == true && drinks?.count == 2)
    }

    @Test func oldDaysAreReadOnly() async {
        let old = DayFormat.string(from: DayFormat.shift(.now, days: -30))
        let (model, _) = await sheet(day: old)
        #expect(!model.editable && model.readOnlyReason != nil)
        model.set(MockJournal.alcohol, on: true)
        #expect(model.groups.flatMap(\.rows).first { $0.id == MockJournal.alcohol }?.on == false)
        #expect(model.stripDays.count == 14)
    }
}

struct ImpactFormatTests {
    @Test func pointsHaveOneDecimalOnlyUnderTen() {
        #expect(ImpactFormat.points(-14.2) == "−14")
        #expect(ImpactFormat.points(4.6) == "+" + 4.6.formatted(.number.precision(.fractionLength(1))))
        #expect(ImpactFormat.points(-3.0) == "−" + 3.0.formatted(.number.precision(.fractionLength(1))))
    }

    @Test func lockedSaysWhatsMissing() {
        #expect(ImpactFormat.locked(ImpactNeeded(yes: 3, no: 0)) == String(localized: "3 more days with it to unlock"))
        #expect(ImpactFormat.locked(ImpactNeeded(yes: 0, no: 2)) == String(localized: "2 more days without it to unlock"))
    }

    @Test func headlineAndN() throws {
        let impacts = try Fixture.decode(BehaviorImpacts.self, "behavior_impact")
        #expect(ImpactFormat.headline(impacts.impacts[0]) == String(localized: "Alcohol · −14 recovery"))
        #expect(ImpactFormat.n(try #require(impacts.impacts[0].recovery)) == "n = 12/31")
        // The platform's order is kept: unlocked first, then locked.
        #expect(impacts.impacts.map(\.status) == [.unlocked, .locked])
    }
}
