import Foundation
import Testing
import UIKit
@testable import Ryft

// MARK: - AppRoute

struct AppRouteTests {
    private func link(_ s: String) -> AppRoute? { URL(string: s).flatMap(AppRoute.init(url:)) }
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
        #expect(AppRoute(url: url) == .authCallback(url))
        #expect(AppRoute(url: url)?.needsSession == false)
        #expect(link("ryft://auth/callback?code=abc").map { if case .authCallback = $0 { return true } else { return false } } == true)
    }

    @Test func foreignURLsAreNotOurs() {
        #expect(link("https://example.com/day/2026-10-19") == nil)
        #expect(link("http://ryftapp.de/day/2026-10-19") == nil)
        #expect(link("mailto:tim@example.com") == nil)
    }

    @Test func unknownOrMalformedPathsOpenToday() {
        for s in ["https://ryftapp.de/", "https://ryftapp.de/day/19-10-2026", "https://ryftapp.de/insights/vo2",
                  "https://ryftapp.de/train/session/not-a-uuid", "https://ryftapp.de/train/workout/6f9619ff-8b86-d011-b42d-00c04fc964ff",
                  "https://ryftapp.de/day/2026-10-19/extra", "ryft://somewhere"] {
            #expect(link(s) == .today, "\(s)")
        }
    }

    @Test func theBriefsPaths() {
        #expect(link("https://ryftapp.de/train/sessions/6f9619ff-8b86-d011-b42d-00c04fc964ff") == .trainSession(id))
        #expect(link("https://ryftapp.de/train/exercises/6f9619ff-8b86-d011-b42d-00c04fc964ff") == .trainExercise(id))
        #expect(link("https://ryftapp.de/insights/behaviors") == .insightsBehaviors)
        #expect(link("https://ryftapp.de/sleep/plan") == .sleepPlan)
        #expect(link("ryft://sleep/plan") == .sleepPlan)
        #expect(link("ryft://train/history") == .trainHistory)
    }

    /// Every `ryft.url` example in API.md → Push notifications.
    @Test func everyPushTableURLParses() {
        #expect(link("https://ryftapp.de/day/2026-10-19") == .day(day))
        #expect(link("https://ryftapp.de/train/session/6f9619ff-8b86-d011-b42d-00c04fc964ff") == .trainSession(id))
    }

    @Test func insightsLeadToTheirRoute() {
        func insight(_ id: String, _ metric: String) -> Insight {
            Insight(id: id, severity: .info, title: "", body: "", metric: metric)
        }
        #expect(AppRoute.forInsight(insight("behavior-impact", "recovery")) == .insightsBehaviors)
        #expect(AppRoute.forInsight(insight("pr", "volume_kg")) == .trainHistory)
        #expect(AppRoute.forInsight(insight("sleep-consistency-low", "sleep_consistency")) == .insights(.sleepConsistency))
        #expect(AppRoute.forInsight(insight("new-rule", "unknown_metric")) == nil)
    }

    @Test func urlRoundTrips() {
        for l in [AppRoute.day(day), .sleep(day), .insights(.activeKcal), .trainSession(id), .trainPlan(id),
                  .trainExercise(id), .insightsBehaviors, .sleepPlan, .trainHistory] {
            #expect(l.url.flatMap(AppRoute.init(url:)) == l)
        }
        #expect(AppRoute.day(day).url?.absoluteString == "https://ryftapp.de/day/2026-10-19")
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

    @Test func newRoutesDriveTheirScreens() async {
        await router.open(.sleepPlan)
        #expect(state.selectedTab == .sleep && sleep.mode == .plan)
        await router.open(.insightsBehaviors)
        #expect(state.selectedTab == .insights && insights.focusesBehaviors)
        let id = UUID()
        await router.open(.trainExercise(id))
        #expect(state.selectedTab == .strain && strain.requestedRoute == .exercise(id))
        await router.open(.trainHistory)
        #expect(strain.requestedRoute == .history)
        await router.open(.today)
        #expect(state.selectedTab == .today)
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
        // No actions yet: a tap opens the app.
        let withActions = PushCategories.all.filter { !$0.actions.isEmpty }
        #expect(withActions.isEmpty)
    }

    @Test func theEnvironmentComesFromTheSignedProfile() throws {
        func profile(_ aps: String?) throws -> Data {
            var ents: [String: Any] = ["application-identifier": "M77SKHKG63.dev.timkrebs.ryft"]
            if let aps { ents["aps-environment"] = aps }
            let xml = try PropertyListSerialization.data(fromPropertyList: ["Name": "RYFT", "Entitlements": ents],
                                                         format: .xml, options: 0)
            // A real profile wraps the plist in CMS bytes.
            return Data([0x30, 0x82, 0x1F, 0x00]) + xml + Data([0xA0, 0x82, 0x00])
        }
        #expect(PushEnvironment.fromProfile(try profile("development")) == .sandbox)
        #expect(PushEnvironment.fromProfile(try profile("production")) == .production)
        #expect(PushEnvironment.fromProfile(try profile(nil)) == nil)
        #expect(PushEnvironment.fromProfile(Data("garbage".utf8)) == nil)
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

    @Test func notNowAsksOnceMoreAfterFourteenDays() throws {
        let clock = try #require(env.clock as? TestClock)
        let push = PushRegistrar(env: env)
        push.syncSucceeded()
        push.dismissPrompt()
        #expect(!push.showsPrePrompt)
        #expect(!PushRegistrar(env: env).showsPrePrompt) // remembered
        clock.advance(by: .seconds(13 * 24 * 3600))
        #expect(!push.showsPrePrompt)
        clock.advance(by: .seconds(24 * 3600))
        #expect(push.showsPrePrompt)
        push.dismissPrompt()
        clock.advance(by: .seconds(60 * 24 * 3600))
        #expect(!push.showsPrePrompt) // at most once more
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
        #expect(sent?.env == .sandbox) // the simulator
        #expect(sent?.locale.isEmpty == false)

        await push.didRegister(deviceToken: Data([0x01, 0x02]))
        #expect(api.count("registerPush") == 2)
        #expect(api.pushRegistrations.last?.token == "0102")
    }

    @Test func aRestartDoesNotRegisterAgain() async {
        await PushRegistrar(env: env).didRegister(deviceToken: token)
        // Relaunch: APNs hands over the same token; the record in SwiftData matches.
        await PushRegistrar(env: env).didRegister(deviceToken: token)
        #expect(api.count("registerPush") == 1)
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
        let today = TodayViewModel(state: state, sync: SyncService.ungated(env: env),
                                   coordinator: SyncCoordinator(steps: NoSteps(), clock: env.clock), push: push)
        #expect(today.showsPushPrompt)
        today.dismissPushPrompt()
        #expect(!today.showsPushPrompt)
    }
}

/// A coordinator that's never run in these tests.
private final class NoSteps: SyncSteps {
    func upload() async throws -> [String] { [] }
    var hasBacklog: Bool { false }
    var isWaitingForUnlock: Bool { false }
    var isUploading: Bool { false }
    func stopAfterCurrentPage() async {}
    var expectedScoringSeconds: Int? { nil }
    func syncStatus() async throws -> SyncStatus { try await MockPlatformAPI().syncStatus() }
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

    @Test func accountDeletionRunsTheHookFirst() async {
        let auth = AuthService.preview()
        var ran = false
        auth.beforeSignOut = { ran = true }
        _ = await auth.deleteAccount()
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

    @Test func theScreenShowsWhatCanHappenNow() async {
        // Off for the account: no switches at all (none that look on), the list in words.
        let off = AppState(env: .test(api: api))
        let rolling = NotificationSettingsViewModel(state: off, push: PushRegistrar(env: off.env))
        #expect(rolling.mode == .rollingOut && !rolling.showsSwitches)

        // On, iOS hasn't asked: switches and "Allow".
        let notifier = MockNotifier()
        let on = AppState(env: .test(api: api, notifier: notifier, flags: [.pushEnabled: true]))
        let push = PushRegistrar(env: on.env)
        let live = NotificationSettingsViewModel(state: on, push: push)
        await live.load()
        #expect(live.mode == .notAsked && live.showsSwitches)

        // Turned off in iOS Settings: switches stay, with "Open Settings".
        notifier.status = .denied
        await live.load()
        #expect(live.mode == .denied && live.showsSwitches)

        notifier.status = .authorized
        await live.load()
        #expect(live.mode == .allowed && live.showsSwitches)
    }

    @Test func quietHoursSwitchedOnSaveHalfPastTenUntilSeven() async {
        await model.setQuietHours(on: true)
        #expect(api.prefs.quietHours == QuietHours(from: "22:30", to: "07:00"))
    }

    /// The live flag store, the way the app has it: an answer that arrives while screens show
    /// waits until one appears.
    private func flagged(_ notifier: MockNotifier) -> (AppState, FlagStore) {
        let suite = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let flags = FlagStore(store: TrainStore(inMemory: true), defaults: suite)
        flags.apply(RemoteConfig(flags: ["push.enabled": false], evaluatedAt: .now, ttlSec: 3600), fetchedAt: .now)
        let env = AppEnvironment(settings: .shared, health: MockHealthStore(), liveAPI: api, demoAPI: api, auth: .preview(),
                                 persistence: TrainStore(inMemory: true), clock: TestClock(), notifier: notifier,
                                 flags: flags, connectivity: .preview(online: true), defaults: suite, demoOverride: false)
        return (AppState(env: env), flags)
    }

    @Test func theFlagReachingTheAccountSwitchesTheScreenWhenItOpens() async {
        let (state, flags) = flagged(MockNotifier())
        let screen = NotificationSettingsViewModel(state: state, push: PushRegistrar(env: state.env))
        #expect(screen.mode == .rollingOut)
        flags.apply(RemoteConfig(flags: ["push.enabled": true], evaluatedAt: .now, ttlSec: 3600), fetchedAt: .now)
        #expect(screen.mode == .rollingOut) // waits for a screen to appear
        await screen.load()
        #expect(screen.mode == .notAsked && screen.showsSwitches)
    }

    @Test func afterTheFlipTodayAsksOnceForAnAlreadySyncedAccount() async {
        let (state, flags) = flagged(MockNotifier())
        let push = PushRegistrar(env: state.env)
        let sync = SyncService.ungated(env: state.env)
        let today = TodayViewModel(state: state, sync: sync,
                                   coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                clock: state.env.clock),
                                   push: push, apiStatus: APIStatus())
        push.syncSucceeded()
        #expect(!today.showsPushPrompt) // not rolled out yet
        flags.apply(RemoteConfig(flags: ["push.enabled": true], evaluatedAt: .now, ttlSec: 3600), fetchedAt: .now)
        flags.applyPending()
        #expect(today.showsPushPrompt)
        today.dismissPushPrompt()
        #expect(!today.showsPushPrompt)
    }

    @Test func hhmmConversions() {
        #expect(NotificationSettingsViewModel.string(NotificationSettingsViewModel.date("06:05")) == "06:05")
        #expect(NotificationSettingsViewModel.string(NotificationSettingsViewModel.date("23:59")) == "23:59")
    }
}

@Suite("Invite links")
struct InviteLinkTests {
    @Test func inviteLinksCarryTheCode() {
        #expect(AppRoute(url: URL(string: "ryft://invite/RYFT-7K3M-QX9P")!) == .invite(code: "RYFT-7K3M-QX9P"))
        #expect(AppRoute(url: URL(string: "https://ryftapp.de/invite/RYFT-7K3M-QX9P")!) == .invite(code: "RYFT-7K3M-QX9P"))
        #expect(AppRoute.invite(code: "RYFT-7K3M-QX9P").url?.absoluteString == "https://ryftapp.de/invite/RYFT-7K3M-QX9P")
        #expect(AppRoute(url: URL(string: "ryft://invite")!) == .today)
    }
}
