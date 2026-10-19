import Foundation
import Testing
import UIKit
@testable import Ryft

// MARK: - DeepLink

struct DeepLinkTests {
    private func link(_ s: String) -> DeepLink? { URL(string: s).flatMap(DeepLink.init(url:)) }
    private let day = DayFormat.date(from: "2026-10-19")!
    private let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    @Test func universalLinksForEveryScreen() {
        #expect(link("https://ryftapp.de/day/2026-10-19") == .day(day))
        #expect(link("https://ryftapp.de/sleep/2026-10-19") == .sleep(day))
        #expect(link("https://ryftapp.de/insights/hrv") == .insights(.hrv))
        #expect(link("https://ryftapp.de/insights/sleep_min") == .insights(.sleepMin))
        #expect(link("https://ryftapp.de/train/session/6f9619ff-8b86-d011-b42d-00c04fc964ff") == .trainSession(id))
        #expect(link("https://ryftapp.de/train/plan/6F9619FF-8B86-D011-B42D-00C04FC964FF") == .trainPlan(id))
        #expect(link("https://www.ryftapp.de/day/2026-10-19") == .day(day))
    }

    @Test func customSchemeHasTheSamePaths() {
        #expect(link("ryft://day/2026-10-19") == .day(day))
        #expect(link("ryft://insights/rhr") == .insights(.rhr))
        #expect(link("ryft://train/plan/6f9619ff-8b86-d011-b42d-00c04fc964ff") == .trainPlan(id))
    }

    @Test func authCallbackKeepsItsURL() throws {
        let url = try #require(URL(string: "https://ryftapp.de/auth/callback?code=abc"))
        #expect(DeepLink(url: url) == .authCallback(url))
        #expect(DeepLink(url: url)?.needsSession == false)
        #expect(link("ryft://auth/callback?code=abc") != nil)
    }

    @Test func foreignOrMalformedURLsAreNotOurs() {
        #expect(link("https://example.com/day/2026-10-19") == nil)
        #expect(link("http://ryftapp.de/day/2026-10-19") == nil)
        #expect(link("https://ryftapp.de/day/19-10-2026") == nil)
        #expect(link("https://ryftapp.de/insights/vo2") == nil)
        #expect(link("https://ryftapp.de/train/session/not-a-uuid") == nil)
        #expect(link("https://ryftapp.de/train/workout/6f9619ff-8b86-d011-b42d-00c04fc964ff") == nil)
        #expect(link("https://ryftapp.de/") == nil)
        #expect(link("https://ryftapp.de/day/2026-10-19/extra") == nil)
        // The rest timer's Live Activity link stays TrainCoordinator's.
        #expect(link("ryft://train/session") == nil)
    }

    @Test func urlRoundTrips() {
        for l in [DeepLink.day(day), .sleep(day), .insights(.activeKcal), .trainSession(id), .trainPlan(id)] {
            #expect(l.url.flatMap(DeepLink.init(url:)) == l)
        }
        #expect(DeepLink.day(day).url?.absoluteString == "https://ryftapp.de/day/2026-10-19")
    }
}

// MARK: - DeepLinkRouter

@MainActor
struct DeepLinkRouterTests {
    let state: AppState
    let sleep: SleepViewModel
    let strain: StrainViewModel
    let insights: InsightsViewModel
    let router: DeepLinkRouter

    init() { self.init(signedIn: true) }

    init(signedIn: Bool) {
        state = AppState(env: .test(auth: .preview(signedIn: signedIn)))
        sleep = SleepViewModel(state: state)
        strain = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        insights = InsightsViewModel(state: state)
        router = DeepLinkRouter(state: state, sleep: sleep, strain: strain, insights: insights)
        state.selectedTab = .profile
    }

    private var today: Date { Calendar.current.startOfDay(for: state.env.clock.now()) }

    @Test func todayOpensTodayAnEarlierDayOpensStrain() async {
        await router.open(.day(today))
        #expect(state.selectedTab == .today)

        let earlier = DayFormat.shift(today, days: -3)
        await router.open(.day(earlier))
        #expect(state.selectedTab == .strain)
        #expect(strain.date == earlier)
    }

    @Test func sleepOpensThatNightInDayMode() async {
        sleep.mode = .week
        let night = DayFormat.shift(today, days: -2)
        await router.open(.sleep(night))
        #expect(state.selectedTab == .sleep)
        #expect(sleep.mode == .day && sleep.date == night)
        // Never past today.
        await router.open(.sleep(DayFormat.shift(today, days: 5)))
        #expect(sleep.date == today)
    }

    @Test func insightsFocusesTheMetric() async {
        await router.open(.insights(.hrv))
        #expect(state.selectedTab == .insights)
        #expect(insights.focusedMetric == .hrv)
    }

    @Test func trainLinksPushOnStrain() async {
        let id = UUID()
        await router.open(.trainSession(id))
        #expect(state.selectedTab == .strain && strain.requestedRoute == .session(id))
        await router.open(.trainPlan(id))
        #expect(strain.requestedRoute == .plan(id))
    }

    @Test func openingAURLSaysWhetherItWasOurs() async throws {
        #expect(await router.open(try #require(URL(string: "https://ryftapp.de/insights/strain"))))
        #expect(insights.focusedMetric == .strain)
        #expect(await !router.open(try #require(URL(string: "https://example.com/x"))))
    }

    @Test func signedOutLinksWaitUntilSignIn() async {
        let t = DeepLinkRouterTests(signedIn: false)
        await t.router.open(.insights(.rhr))
        #expect(t.router.pending == .insights(.rhr))
        #expect(t.state.selectedTab == .profile)
        t.router.openPending() // still signed out: nothing happens
        #expect(t.router.pending == .insights(.rhr))
    }
}

// MARK: - push payloads

struct PushMessageTests {
    private func userInfo(_ fixture: String) throws -> [AnyHashable: Any] {
        try #require(try JSONSerialization.jsonObject(with: Fixture.data(fixture)) as? [AnyHashable: Any])
    }

    @Test func alertCarriesItsCategoryAndLink() throws {
        let message = PushMessage(userInfo: try userInfo("push_alert"))
        #expect(message == .alert(category: .morningScore, url: URL(string: "https://ryftapp.de/day/2026-10-19")))
    }

    @Test func silentPushRefreshesTheDay() throws {
        #expect(PushMessage(userInfo: try userInfo("push_refresh")) == .refresh(day: "2026-10-19"))
    }

    @Test func foreignPayloadsAreIgnored() {
        #expect(PushMessage(userInfo: ["aps": ["alert": "hi"]]) == nil)
        #expect(PushMessage(userInfo: ["ryft": "nope"]) == nil)
    }

    @Test func theRingReadsTheRecoveryFromTheTitleArguments() throws {
        #expect(NotificationRing.score(in: try userInfo("push_alert")) == 82)
        #expect(NotificationRing.score(in: try userInfo("push_refresh")) == nil)
        #expect(NotificationRing.score(fromArgument: "82 %") == 82)
        #expect(NotificationRing.score(fromArgument: "82\u{00A0}%") == 82)
        #expect(NotificationRing.score(fromArgument: "120%") == nil)
        #expect(NotificationRing.score(fromArgument: "—") == nil)
    }

    @Test func theRingIsDrawnInTheAppsBands() throws {
        let image = NotificationRing.image(score: 82)
        #expect(image.size == CGSize(width: 180, height: 180))
        #expect(NotificationRing.bandColor(67) != NotificationRing.bandColor(66))
        #expect(NotificationRing.bandColor(34) != NotificationRing.bandColor(33))
        let dir = FileManager.default.temporaryDirectory
        #expect(NotificationRing.attachment(for: try userInfo("push_alert"), directory: dir) != nil)
    }

    @Test func categoriesIncludeTheLocalBedtimeReminder() {
        let ids = Set(PushCategories.all.map(\.identifier))
        #expect(ids == ["MORNING_SCORE", "SESSION_SCORED", "PR", "SYNC_STALE", "BEDTIME"])
        let stale = PushCategories.all.first { $0.identifier == "SYNC_STALE" }
        #expect(stale?.actions.map(\.identifier) == [PushCategories.syncNowAction])
    }
}

// MARK: - PushRegistrar

@MainActor
struct PushRegistrarTests {
    let api = MockPlatformAPI()
    let notifier = MockNotifier()
    let env: AppEnvironment

    init() {
        env = .test(api: api, notifier: notifier, flags: [.pushEnabled: true])
    }

    private let token = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01])

    @Test func thePrePromptWaitsForTheFirstSync() async {
        let push = PushRegistrar(env: env)
        await push.refresh()
        #expect(!push.showsPrePrompt)
        push.syncSucceeded()
        #expect(push.showsPrePrompt)
        // Remembered across launches.
        #expect(PushRegistrar(env: env).hasSynced)
    }

    @Test func thePrePromptNeedsTheFlag() async {
        let push = PushRegistrar(env: .test(api: api, notifier: notifier))
        push.syncSucceeded()
        #expect(!push.showsPrePrompt)
    }

    @Test func notNowHidesItForGood() {
        let push = PushRegistrar(env: env)
        push.syncSucceeded()
        push.dismissPrompt()
        #expect(!push.showsPrePrompt)
        #expect(!PushRegistrar(env: env).showsPrePrompt)
        #expect(notifier.authorizationPrompts == 0)
    }

    @Test func turningOnAsksIOSThenRegistersWithAPNs() async {
        let push = PushRegistrar(env: env)
        push.syncSucceeded()
        await push.accept()
        #expect(notifier.authorizationPrompts == 1)
        #expect(push.isAllowed && notifier.registeredForRemote)
        #expect(!push.showsPrePrompt)
    }

    @Test func aRefusalDoesNotRegister() async {
        notifier.grants = false
        let push = PushRegistrar(env: env)
        await push.accept()
        #expect(push.status == .denied && !notifier.registeredForRemote)
    }

    @Test func theTokenIsSentOnceUntilItChanges() async {
        let push = PushRegistrar(env: env)
        await push.didRegister(deviceToken: token)
        await push.didRegister(deviceToken: token)
        #expect(api.count("registerPush") == 1)
        let sent = api.pushRegistrations.first
        #expect(sent?.token == "deadbeef01")
        #expect(sent?.env == .sandbox) // a Debug build
        #expect(sent?.locale.isEmpty == false)

        await push.didRegister(deviceToken: Data([0x01, 0x02]))
        #expect(api.count("registerPush") == 2)
        #expect(api.pushRegistrations.last?.token == "0102")
    }

    @Test func aFailedRegistrationIsRetriedNextTime() async {
        api.failNext = APIError.http(500, "")
        let push = PushRegistrar(env: env)
        await push.didRegister(deviceToken: token)
        #expect(push.lastError != nil)
        await push.send()
        #expect(api.count("registerPush") == 2 && push.lastError == nil)
    }

    @Test func launchReregistersWhenAllowed() async {
        notifier.status = .authorized
        let push = PushRegistrar(env: env)
        await push.refresh()
        #expect(notifier.registeredForRemote)
        #expect(notifier.categories.count == 5)
    }

    @Test func signOutDeletesTheRegistration() async {
        let push = PushRegistrar(env: env)
        await push.didRegister(deviceToken: token)
        notifier.registerForRemoteNotifications()
        await push.signOut()
        #expect(api.count("deletePush") == 1)
        #expect(push.token == nil && !notifier.registeredForRemote)
        // The next account sends it again.
        await push.didRegister(deviceToken: token)
        #expect(api.count("registerPush") == 2)
    }

    @Test func nothingIsSentWithoutTheFlagOrSignedOut() async {
        let off = PushRegistrar(env: .test(api: api, notifier: notifier))
        await off.didRegister(deviceToken: token)
        let signedOut = PushRegistrar(env: .test(api: api, notifier: notifier, auth: .preview(signedIn: false),
                                                 flags: [.pushEnabled: true]))
        await signedOut.didRegister(deviceToken: token)
        #expect(api.count("registerPush") == 0)
    }

    @Test func localeIsTheAppLanguageWithTheRegion() {
        let locale = PushRegistrar.locale(locale: Locale(identifier: "de_DE"))
        #expect(locale.hasSuffix("-DE"))
        #expect(PushRegistrar.hex(Data([0x0A, 0xFF])) == "0aff")
    }

    @Test func todayShowsTheCardOnlyWithoutCoachMarks() async {
        let state = AppState(env: env)
        let push = PushRegistrar(env: env)
        push.syncSucceeded()
        let today = TodayViewModel(state: state, sync: SyncService(env: env),
                                   coordinator: SyncCoordinator(steps: NoSteps(), clock: env.clock), push: push)
        #expect(today.showsPushPrompt)
        today.dismissPushPrompt()
        #expect(!today.showsPushPrompt)
    }
}

/// A coordinator that's never run in these tests.
private final class NoSteps: SyncSteps {
    func upload() async throws -> [String] { [] }
    func isScored(_ days: [String], since: Date) async throws -> Bool { true }
    func refreshDays(_ days: [String]) async throws {}
    func refreshTrends() async throws {}
    func refreshInsights() async throws {}
    func refreshStale() async {}
    func report(_ phase: SyncPhase) {}
}

// MARK: - sign-out hook

@MainActor
struct SignOutHookTests {
    @Test func aUserSignOutRunsTheHookFirst() async {
        let auth = AuthService.preview()
        var ran = false
        auth.beforeSignOut = { ran = true }
        await auth.signOut()
        #expect(ran)
    }

    @Test func anExpiredSessionSkipsIt() async {
        let auth = AuthService.preview()
        var ran = false
        auth.beforeSignOut = { ran = true }
        await auth.signOut(reason: .sessionExpired)
        #expect(!ran)
    }
}

// MARK: - Profile → Notifications

@MainActor
struct NotificationSettingsViewModelTests {
    let api = MockPlatformAPI()
    let state: AppState
    let model: NotificationSettingsViewModel

    init() {
        let env = AppEnvironment.test(api: api, flags: [.pushEnabled: true])
        state = AppState(env: env)
        state.user = MockData.user
        model = NotificationSettingsViewModel(state: state, push: PushRegistrar(env: env))
    }

    @Test func aToggleIsSavedAndKeptOnTheUser() async {
        #expect(model.isOn(.pr))
        await model.set(.pr, on: false)
        #expect(api.count("patchNotifications") == 1)
        #expect(!model.isOn(.pr) && model.isOn(.morningScore))
        #expect(state.user?.notifications.isOn(.pr) == false)
    }

    @Test func aRefusedChangeRollsBack() async {
        api.failNext = APIError.http(422, "")
        await model.set(.syncStale, on: false)
        #expect(model.isOn(.syncStale))
        #expect(model.error != nil)
    }

    @Test func quietHoursStartAtTheDefaultAndCanMove() async {
        #expect(!model.quietHoursOn)
        await model.setQuietHours(on: true)
        #expect(model.prefs.quietHours == NotificationSettingsViewModel.defaultQuietHours)
        await model.setQuietFrom(NotificationSettingsViewModel.date("21:30"))
        #expect(model.prefs.quietHours == QuietHours(from: "21:30", to: "07:00"))
        await model.setQuietHours(on: false)
        #expect(model.prefs.quietHours == nil && api.prefs.quietHours == nil)
    }

    @Test func anUnchangedTimeSendsNothing() async {
        await model.setQuietHours(on: true)
        await model.setQuietTo(NotificationSettingsViewModel.date("07:00"))
        #expect(api.count("patchNotifications") == 1)
    }

    @Test func hhmmConversions() {
        #expect(NotificationSettingsViewModel.string(NotificationSettingsViewModel.date("06:05")) == "06:05")
        #expect(NotificationSettingsViewModel.string(NotificationSettingsViewModel.date("23:59")) == "23:59")
    }
}
