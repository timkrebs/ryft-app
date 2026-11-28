import Foundation
import Testing
@testable import Ryft

@Suite("Structure V2")
@MainActor
struct StructureV2Tests {
    @Test func visibleTabsKeepTheirOrderAndIdentifiers() {
        let legacy = AppTab.tabs(structureV2: false)
        #expect(legacy == [.today, .sleep, .strain, .insights, .profile])
        #expect(legacy.map(\.identifier) == ["tab.today", "tab.sleep", "tab.strain", "tab.insights", "tab.profile"])

        let updated = AppTab.tabs(structureV2: true)
        #expect(updated == [.today, .sleep, .strain, .nutrition, .insights])
        #expect(updated.map(\.identifier) == ["tab.today", "tab.sleep", "tab.strain", "tab.nutrition", "tab.insights"])
        #expect(RyftTabBar.appTabs(structureV2: true).map(\.identifier) == updated.map(\.identifier))
    }

    @Test func onlyHiddenTabsFallBackToToday() {
        for tab in AppTab.allCases {
            #expect(AppTab.visible(tab, structureV2: true) == (tab == .profile ? .today : tab))
            #expect(AppTab.visible(tab, structureV2: false) == (tab == .nutrition ? .today : tab))
        }
        #expect(String(localized: AppTab.strain.title(structureV2: true)) == "Fitness")
        #expect(String(localized: AppTab.strain.title(structureV2: false)) == "Strain")
    }

    @Test func profileOpensInTheCurrentLayout() {
        let legacy = AppState(env: .test())
        legacy.openProfile()
        #expect(legacy.selectedTab == .profile)
        #expect(!legacy.showsProfile)

        let updated = AppState(env: .test(flags: [.structureV2: true]))
        updated.selectedTab = .sleep
        updated.openProfile()
        #expect(updated.selectedTab == .sleep)
        #expect(updated.showsProfile)
    }

    @Test func flagFlipsDropHiddenSelectionsWithoutOpeningProfile() throws {
        let state = AppState(env: .test())
        let flags = try #require(state.env.flags as? StaticFlags)
        state.selectedTab = .profile
        flags.overrides[.structureV2] = true
        #expect(state.selectedTab == .today)
        state.normalizeTabSelection()
        #expect(!state.showsProfile)

        state.selectedTab = .nutrition
        flags.overrides[.structureV2] = false
        #expect(state.selectedTab == .today)
        state.normalizeTabSelection()
        flags.overrides[.structureV2] = true
        #expect(state.selectedTab == .today)
        #expect(!state.showsProfile)
    }

    @Test func journalLinkWaitsForProfileToDismiss() async {
        let state = AppState(env: .test(flags: [.structureV2: true]))
        let router = DeepLinkRouter(state: state, sleep: SleepViewModel(state: state),
                                    strain: StrainViewModel(state: state, store: TrainStore(inMemory: true)),
                                    insights: InsightsViewModel(state: state))
        state.selectedTab = .sleep
        state.openProfile()
        router.profileAppeared()

        let yesterday = DayFormat.shift(state.env.clock.now(), days: -1)
        await router.open(.journal(yesterday))
        #expect(!state.showsProfile)
        #expect(state.selectedTab == .sleep)
        #expect(router.requestedJournalDay == nil)

        router.profileDismissed()
        #expect(state.selectedTab == .today)
        #expect(router.requestedJournalDay == DayFormat.string(from: yesterday))
    }

    @Test func aGateOverProfileKeepsItOpenAndTheLinkWaits() async {
        let state = AppState(env: .test(flags: [.structureV2: true]))
        let router = DeepLinkRouter(state: state, sleep: SleepViewModel(state: state),
                                    strain: StrainViewModel(state: state, store: TrainStore(inMemory: true)),
                                    insights: InsightsViewModel(state: state))
        var gateShown = true
        router.holdsProfile = { gateShown }
        state.openProfile()
        router.profileAppeared()

        await router.open(.insightsBehaviors)
        #expect(state.showsProfile, "a gate over Profile keeps the sheet")
        #expect(state.selectedTab == .today)

        gateShown = false
        state.showsProfile = false
        router.profileDismissed()
        #expect(state.selectedTab == .insights, "the link routes once Profile has gone")
    }

    @Test func anAuthCallbackLeavesProfileOpen() async throws {
        let state = AppState(env: .test(flags: [.structureV2: true]))
        let router = DeepLinkRouter(state: state, sleep: SleepViewModel(state: state),
                                    strain: StrainViewModel(state: state, store: TrainStore(inMemory: true)),
                                    insights: InsightsViewModel(state: state))
        state.openProfile()
        router.profileAppeared()
        await router.open(.authCallback(try #require(URL(string: "ryft://auth/callback"))))
        #expect(state.showsProfile)
    }

    @Test func quickLogUsesNutritionTrainJournalAndManualActivityGates() {
        let signedOut = AuthService.preview(signedIn: false)
        let demo = AppEnvironment.preview(auth: signedOut, flags: [.nutritionDiaryEnabled: true])
        let live = AppEnvironment.test(flags: [.nutritionDiaryEnabled: true])
        #expect(!demo.showsNutritionEntry)
        #expect(live.showsNutritionEntry)
        #expect(!AppEnvironment.test(auth: signedOut, flags: [.nutritionEnabled: true]).showsNutritionEntry)
        #expect(!AppEnvironment.test().showsNutritionEntry)

        #expect(QuickLogAction.available(nutrition: demo.showsNutritionEntry, train: true, myDay: false,
                                        canAddActivity: false, journal: false, offersAddSleep: false) == [.workout])
        #expect(QuickLogAction.available(nutrition: live.showsNutritionEntry, train: true, myDay: true,
                                        canAddActivity: true, journal: true, offersAddSleep: true) == QuickLogAction.allCases)
        #expect(QuickLogAction.available(nutrition: true, train: false, myDay: true,
                                        canAddActivity: false, journal: true, offersAddSleep: false) == [.meal, .barcode, .journal])
        #expect(QuickLogAction.available(nutrition: false, train: false, myDay: false,
                                        canAddActivity: true, journal: false, offersAddSleep: true).isEmpty)
    }

    @Test func addActivityUsesTheFitnessDateOrToday() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let earlier = DayFormat.shift(today, days: -3)
        for tab in AppTab.tabs(structureV2: true) {
            #expect(QuickLogAction.activityDay(selectedTab: tab, fitnessDay: earlier, today: today)
                    == (tab == .strain ? earlier : today))
        }
    }

    @Test func badgeAndSpokenValueForEverySyncState() {
        let states: [(SyncIndicatorState, AvatarSyncBadge, String)] = [
            (.upToDate, .upToDate, "Up to date"),
            (.syncing, .syncing, "Syncing"),
            (.stale(.old), .none, "Sync needed"),
            (.stale(.neverSynced), .none, "Sync needed"),
            (.stale(.offline), .none, "Offline"),
            (.stale(.scoresPending), .none, "Scores are still being calculated"),
            (.stale(.awaitingReload), .none, "Sync needed"),
            (.error(.uploadFailed), .error, "Sync problem"),
            (.error(.healthAccess), .error, "Apple Health access needed"),
            (.error(.source), .error, "Sync problem"),
        ]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lastSync = now.addingTimeInterval(-4 * 60)
        let source = SyncSource(source: "healthkit", lastSyncAt: lastSync, status: .ok, reason: nil)
        let age = SyncDetailsModel.lastSyncWords(lastSync, now: now)
        for (state, badge, value) in states {
            #expect(AvatarSyncBadge(state: state) == badge)
            #expect(SyncStatusText(state: state, sources: [], now: now).accessibilityValue == "\(value), never synced")
            #expect(SyncStatusText(state: state, sources: [source], now: now).accessibilityValue == "\(value), synced \(age)")
        }
    }
}
