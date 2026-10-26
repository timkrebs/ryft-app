import Foundation
import Testing
@testable import Ryft

@Suite("Activity preferences")
@MainActor
struct ActivityPreferencesTests {
    private let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard

    private func prefs(_ account: String? = "account-a") -> ActivityPreferences {
        ActivityPreferences(defaults: defaults, account: account)
    }

    @Test func theRouteDefaultIsUnsetUntilChosen() {
        #expect(prefs().recordsRouteByDefault == nil)
        prefs().setRecordsRouteByDefault(false)
        #expect(prefs().recordsRouteByDefault == false)
        prefs().setRecordsRouteByDefault(true)
        #expect(prefs().recordsRouteByDefault == true)
    }

    @Test func eachAccountHasItsOwn() {
        prefs("account-a").setRecordsRouteByDefault(true)
        prefs("account-a").noteUsed(.yoga)
        prefs("account-a").setAutoPause(false, for: .running)
        #expect(prefs("account-b").recordsRouteByDefault == nil)
        #expect(prefs("account-b").recentSports.isEmpty)
        #expect(prefs("account-b").autoPause(for: .running))
    }

    @Test func recentsAreNewestFirstOnceEachAndAtMostFive() {
        let p = prefs()
        for sport in [Sport.running, .yoga, .cycling, .running, .padel, .hiking, .swimming, .rowing] { p.noteUsed(sport) }
        #expect(p.recentSports == [.rowing, .swimming, .hiking, .padel, .running])
        #expect(ActivityPreferences.recentLimit == 5)
    }

    @Test func autoPauseFollowsTheCatalogueUntilTheFamilyIsSet() {
        let p = prefs()
        #expect(p.autoPause(for: .running) && !p.autoPause(for: .walking) && !p.autoPause(for: .hiking))
        p.setAutoPause(true, for: .walking) // the foot family
        #expect(p.autoPause(for: .walking) && p.autoPause(for: .hiking) && p.autoPause(for: .running))
        p.setAutoPause(false, for: .running)
        #expect(!p.autoPause(for: .trailRunning))
        #expect(p.autoPause(for: .cycling)) // another family keeps the catalogue's
    }

    @Test func signedOutReadsTheDefaultsAndWritesNothing() {
        let p = prefs(nil)
        p.setRecordsRouteByDefault(true)
        p.noteUsed(.yoga)
        p.setAutoPause(false, for: .running)
        #expect(p.recordsRouteByDefault == nil && p.recentSports.isEmpty && p.autoPause(for: .running))
        let written = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(ActivityPreferences.keyPrefix) }
        #expect(written.isEmpty)
    }

    @Test func theWipeTakesEveryAccountsPreferencesAndNothingElse() {
        prefs("account-a").setRecordsRouteByDefault(true)
        prefs("account-b").noteUsed(.yoga)
        defaults.set(true, forKey: "health.saveWorkouts.account-a")
        ActivityPreferences.wipe(defaults: defaults)
        #expect(prefs("account-a").recordsRouteByDefault == nil && prefs("account-b").recentSports.isEmpty)
        #expect(defaults.bool(forKey: "health.saveWorkouts.account-a"))
    }

    @Test func forgettingRouteDefaultsKeepsTheRest() {
        prefs("account-a").setRecordsRouteByDefault(true)
        prefs("account-b").setRecordsRouteByDefault(false)
        prefs("account-a").noteUsed(.yoga)
        ActivityPreferences.forgetRouteDefaults(defaults: defaults)
        #expect(prefs("account-a").recordsRouteByDefault == nil && prefs("account-b").recordsRouteByDefault == nil)
        #expect(prefs("account-a").recentSports == [.yoga])
    }

    @Test func theEnvironmentsAreTheStoresAccount() {
        let env = AppEnvironment.test()
        let p = ActivityPreferences(env: env)
        #expect(p.account == env.auth.accountID && p.account != nil)
        p.noteUsed(.climbing)
        #expect(ActivityPreferences(defaults: env.defaults, account: env.auth.accountID).recentSports == [.climbing])
    }
}
