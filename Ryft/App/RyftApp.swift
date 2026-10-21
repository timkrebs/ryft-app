// xcode: set sdk=iOS

import SwiftUI
import BackgroundTasks
import UIKit
import os

/// The entry point. Under unit tests the app is only their host: an empty window
/// and none of the live work (bootstrap, HealthKit, background tasks, demo loads),
/// so tests never share the main actor with the real app. A fresh CI simulator
/// starts in demo mode, which made the live app load data while tests ran. UI
/// tests launch the app as a separate process without this variable, so they get
/// the real one.
@main
enum AppLauncher {
    static var isUnitTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    static func main() {
        if isUnitTestHost {
            TestHostApp.main()
        } else {
            RyftApp.main()
        }
    }
}

private struct TestHostApp: App {
    var body: some Scene {
        WindowGroup { Color.clear }
    }
}

struct RyftApp: App {
    /// APNs callbacks, the silent refresh and notification taps.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Every dependency, built once (`docs/ARCHITECTURE.md`).
    private let env = AppEnvironment.live
    @State private var settings = Settings.shared
    @State private var auth = AuthService.shared
    @State private var sync = SyncService.shared
    @State private var state: AppState
    @State private var screens: ScreenModels
    /// Every sync runs through it: one in flight, priorities, cancellation.
    private let coordinator: SyncCoordinator
    @State private var trainLibrary = TrainLibrary.shared
    @State private var trainSync = TrainSyncService.shared
    @State private var trainCoordinator = TrainCoordinator.shared
    @State private var connectivity = ConnectivityMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LaunchSignpost.begin()
        let state = AppState(env: .live)
        // The JSON response cache of earlier versions moves into SwiftData once.
        LegacyCacheMigration.runOnce(into: state.repository, train: .shared, defaults: .standard)
        // Launched straight into the background (a HealthKit delivery, a BG task): the
        // coordinator starts there; the scene's activation brings it to the foreground.
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: .shared),
                                          clock: AppEnvironment.live.clock,
                                          inBackground: UIApplication.shared.applicationState == .background) {
            // A run in the background left a backlog: the backfill task takes it.
            if let left = SyncService.shared.backlogBytes { BackgroundWork.scheduleBackfill(backlogBytes: left) }
        }
        self.coordinator = coordinator
        _state = State(initialValue: state)
        let screens = ScreenModels(state: state, sync: .shared, coordinator: coordinator,
                                   store: .shared, library: .shared)
        _screens = State(initialValue: screens)
        // Sign-out first deletes this phone's push registration, while the session still works.
        AuthService.shared.beforeSignOut = { [push = screens.push] in await push.signOut() }
        // A build without its platform values stops here (Debug) or shows only the
        // misconfigured-build screen (Release, RootView). Never a fallback host.
        PlatformConfig.checkAtLaunch()
        // Background refresh, the backfill (in addition to HealthKit delivery) and the nightly
        // cache compaction.
        BackgroundWork.register(coordinator: coordinator, backlogBytes: { SyncService.shared.backlogBytes }) {
            [repository = state.repository] in repository.compact()
        }
        // HealthKit wakes the app for deliveries, possibly in a background launch where the
        // scene's tasks don't run: the observers exist before launch finishes. Only for an
        // account that has seen the Health explanation (bootstrap covers the first time).
        if AuthService.shared.isSignedIn, Settings.shared.healthIntroDone, HealthKitManager.isAvailable {
            Self.observeHealthKit(HealthKitManager.shared, coordinator: coordinator)
        }
        // A sync that found HealthKit locked runs again once the phone is unlocked.
        BackgroundWork.resumeOnUnlock(coordinator: coordinator) { SyncService.shared.waitingForUnlock }
        Self.configureAppearance()
        #if DEBUG
        // UI tests: `-RyftResetTrain YES` starts without sessions or a queue.
        if UserDefaults.standard.bool(forKey: "RyftResetTrain") { TrainStore.shared.wipe() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appEnvironment, env)
                .environment(screens)
                .environment(settings)
                .environment(auth)
                .environment(sync)
                .environment(state)
                .environment(trainLibrary)
                .environment(trainSync)
                .environment(trainCoordinator)
                .environment(connectivity)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(Theme.accent)
                // Signed out, or a different account: forget the previous user's screens.
                .onChange(of: auth.accountID) { old, new in
                    Task { await coordinator.cancel() }
                    if old != nil { state.reset() }
                    // That account's gates, steps and sync state are its own.
                    screens.onboarding.switchAccount(new)
                    sync.accountChanged()
                    // Flags are per account: that account's cached answer, then a fresh one.
                    (env.flags as? FlagStore)?.switchAccount(new)
                    guard new != nil else { return }
                    Task { await screens.featureFlags?.refresh(force: true) }
                    // A link that arrived signed out; this account's push registration.
                    screens.router.openPending()
                    Task { await screens.push.refresh() }
                }
                // A gate the platform reported (a 403 with a code, or X-RYFT-Gate): what's missing now.
                .onChange(of: APIStatus.shared.gates) { _, _ in
                    Task { await screens.onboarding.check(force: true) }
                }
                // A flag flip that arrived meanwhile takes effect as the next screen appears.
                .onChange(of: state.selectedTab) { _, _ in (env.flags as? FlagStore)?.applyPending() }
                // The first successful sync unlocks the push pre-prompt on Today.
                .onChange(of: sync.phase) { _, phase in
                    if phase == .done { screens.push.syncSucceeded() }
                }
                // GET /v1/config after the first frame, then whenever its ttl_sec (6 h) has
                // passed; below the work the user waits for.
                .task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await screens.featureFlags?.run()
                }
                .task {
                    appDelegate.handlers = PushHandlers(registrar: screens.push, router: screens.router,
                                                        coordinator: coordinator)
                }
                // Back online: upload what HealthKit collected meanwhile, then reload.
                .onChange(of: connectivity.isOnline) { _, online in
                    guard online else { return }
                    Task { await coordinator.run(.reconnect) }
                    Task { await refreshTrain() }
                }
                // Runs at launch (restored session) and again after each sign-in.
                .task(id: BootstrapKey(account: auth.accountID, healthIntroDone: settings.healthIntroDone,
                                       inviteBlocked: APIStatus.shared.inviteBlocked)) {
                    await bootstrap()
                }
                // ryft://train/session — the rest timer Live Activity; everything else
                // (universal links, ryft://…, the auth callback) goes through the router.
                .onOpenURL { url in
                    if trainCoordinator.handle(url) { return }
                    Task {
                        if await screens.router.open(url) { return }
                        _ = await auth.handle(url)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                (env.flags as? FlagStore)?.applyPending()
                Task {
                    await coordinator.enterForeground()
                    await coordinator.run(.appActive)
                }
                // After the first frame (at launch), concurrently and below the sync: Today
                // shows the cache meanwhile. The sync and bootstrap's gate check don't wait.
                Task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await refreshTrain()
                }
                // Allowed in Settings meanwhile, a new token or language: tell the platform.
                Task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await screens.push.refresh()
                }
                Task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await screens.featureFlags?.refresh()
                }
                Task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await screens.onboarding.check()
                }
                // Saving workouts follows what Health allows now; a watch workout that arrived
                // after a session replaces RYFT's in Fitness.
                Task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await WorkoutHealthExport.shared.appBecameActive(now: .now)
                }
            } else if phase == .background {
                // Not a cancel: the page in flight finishes (in a background task), and what's
                // left of an import goes to the backfill task.
                _ = BackgroundWork.finishInBackground(coordinator: coordinator, app: UIApplication.shared,
                                                      backlogBytes: { sync.backlogBytes })
                BackgroundWork.scheduleRefresh()
                BackgroundWork.scheduleCompaction()
            }
        }
    }

    /// Queued sessions go up first; then the library, plans and today's plan.
    private func refreshTrain() async {
        guard settings.demoMode || auth.isSignedIn else { return }
        trainCoordinator.refreshActive()
        await trainSync.flush()
        await trainLibrary.refresh()
    }

    private func bootstrap() async {
        guard !env.isDemo else {
            await state.refresh()
            return
        }
        // Welcome first; HealthKit is asked for right after sign-in.
        guard auth.isSignedIn else { return }
        // Every start and sign-in: what the account still needs (invite, consent, about you).
        // This also creates the platform user and sets its timezone before anything syncs.
        await screens.onboarding.check()
        // Behind an enforced invite gate nothing but onboarding answers; this reruns once
        // it's passed (`BootstrapKey.inviteBlocked`). A warning blocks nothing.
        guard !APIStatus.shared.inviteBlocked else { return }
        guard env.health.isAvailable else {
            await state.refresh()
            return
        }
        // Health access only after the explanation screen (RootView); reruns when it's answered.
        guard settings.healthIntroDone else {
            await state.refresh()
            return
        }
        try? await env.health.requestAuthorization()
        Self.observeHealthKit(env.health, coordinator: coordinator)
        await coordinator.run(.appActive)
    }

    /// The observers (once; launch or bootstrap, whichever comes first) and `.immediate`
    /// delivery (every launch, idempotent). A delivery completes right after its upload.
    @MainActor
    static func observeHealthKit(_ health: HealthStore, coordinator: SyncCoordinator) {
        health.startObserving { done in
            Task { await coordinator.run(.healthKit, afterUpload: done) }
        }
        Task { await health.enableBackgroundDelivery() }
    }

    private struct BootstrapKey: Equatable {
        let account: String?
        let healthIntroDone: Bool
        let inviteBlocked: Bool
    }

    // MARK: appearance

    /// Inactive tab items in Mist (or Graphite in light mode) at 50 %.
    private static func configureAppearance() {
        let inactive = UIColor { traits in
            let base = UIColor(named: "TextPrimary") ?? .label
            return base.resolvedColor(with: traits).withAlphaComponent(0.5)
        }
        UITabBarItem.appearance().setTitleTextAttributes([.foregroundColor: inactive], for: .normal)
        UITabBar.appearance().unselectedItemTintColor = inactive
        if #unavailable(iOS 26) {
            // Pre-Liquid-Glass: an opaque Graphite bar like the board.
            let bar = UITabBarAppearance()
            bar.configureWithOpaqueBackground()
            bar.backgroundColor = UIColor(named: "Background")
            bar.shadowColor = UIColor(named: "Separator")
            for layout in [bar.stackedLayoutAppearance, bar.inlineLayoutAppearance, bar.compactInlineLayoutAppearance] {
                layout.normal.iconColor = inactive
                layout.normal.titleTextAttributes = [.foregroundColor: inactive]
            }
            UITabBar.appearance().standardAppearance = bar
            UITabBar.appearance().scrollEdgeAppearance = bar
        }
    }
}

extension Settings.Appearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

/// Welcome until there's a session (or demo data); then what onboarding still needs
/// (invite, consent, about you, Apple Health), then the tabs.
struct RootView: View {
    @Environment(\.appEnvironment) private var env
    @Environment(ScreenModels.self) private var screens
    @Environment(AppState.self) private var state
    @Environment(AuthService.self) private var auth
    @Environment(Settings.self) private var settings
    @Environment(TrainCoordinator.self) private var train

    var body: some View {
        #if DEBUG
        // `-RyftScreen consent` (or invite, aboutYou, accountHint, signInMethods): one screen
        // on mock data, for screenshots of states demo mode never reaches.
        if let screen = DebugScreen.requested {
            screen.view
        } else {
            content
        }
        #else
        content
        #endif
    }

    private var content: some View {
        ZStack {
            if !PlatformConfig.isComplete {
                MisconfiguredBuildView()
            } else if settings.demoMode {
                tabs.transition(.opacity).onAppear(perform: LaunchSignpost.screenAppeared)
            } else {
                // Nothing personal is built before there is a session. Every screen but the
                // splash opens the launch barrier.
                switch auth.state {
                case .restoring: SplashView().transition(.opacity)
                case .signedOut: WelcomeView().transition(.opacity).onAppear(perform: LaunchSignpost.screenAppeared)
                // The account's first run waits for the platform's answer: no flash of the tabs.
                case .signedIn where onboarding.holdsFirstRun: SplashView().transition(.opacity)
                case .signedIn where onboarding.flowStep != nil:
                    OnboardingFlowView(model: onboarding).transition(.opacity)
                        .onAppear(perform: LaunchSignpost.screenAppeared)
                case .signedIn where needsHealthIntro:
                    HealthPermissionView().transition(.opacity).onAppear(perform: LaunchSignpost.screenAppeared)
                case .signedIn: tabs.transition(.opacity).onAppear(perform: LaunchSignpost.screenAppeared)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: settings.demoMode ? .signedIn : auth.state)
        .animation(.easeInOut(duration: 0.3), value: needsHealthIntro)
        .animation(.easeInOut(duration: 0.3), value: onboarding.flowStep)
        // "This is a new RYFT account": once, before the steps.
        .sheet(item: Binding(get: { onboarding.accountHint }, set: { if $0 == nil { onboarding.keepThisAccount() } })) { hint in
            AccountHintSheet(hint: hint, keep: { onboarding.keepThisAccount() },
                             useOther: { await onboarding.useOtherAccount() })
        }
        // Someone who already answered the system prompt (an earlier version) skips the intro.
        .task(id: auth.accountID) {
            guard needsHealthIntro else { return }
            if await env.health.accessStatus() == .asked { settings.healthIntroDone = true }
        }
        // The live workout, from Today, Strain or the Live Activity.
        .fullScreenCover(item: Bindable(train).live) { SessionView(controller: $0) }
        // A password-reset link signed the user in; ask for the new password now.
        .sheet(isPresented: Bindable(auth).needsNewPassword) {
            SetNewPasswordView(mode: .recovery)
        }
    }

    /// After sign-in, once per account: explain Apple Health before iOS asks.
    private var needsHealthIntro: Bool {
        env.health.isAvailable && !settings.healthIntroDone
    }

    private var onboarding: OnboardingCoordinator { screens.onboarding }

    private var tabs: some View {
        tabView
            // From now on this account's gates are sheets, not the full-screen flow.
            .onAppear { onboarding.reachedTabs() }
            // A gate after the first run (policy updated, consent withdrawn): over the
            // current screen, never a reset to Welcome.
            .sheet(item: Bindable(onboarding).sheetStep) { step in
                OnboardingStepView(step: step, model: onboarding)
                    .interactiveDismissDisabled(!onboarding.canDefer(step))
            }
    }

    private var tabView: some View {
        TabView(selection: Bindable(state).selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "house.fill") }
                .tag(AppTab.today)
            SleepView()
                .tabItem { Label("Sleep", systemImage: "moon.fill") }
                .tag(AppTab.sleep)
            StrainView()
                .tabItem { Label("Strain", systemImage: "bolt.fill") }
                .tag(AppTab.strain)
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
                .tag(AppTab.insights)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(AppTab.profile)
        }
    }
}

#if DEBUG
/// Screens a screenshot run can open directly (`scripts/screenshots.sh`, `-RyftScreen <name>`).
enum DebugScreen: String {
    case invite, consent, aboutYou, accountHint, signInMethods, syncDetails

    static var requested: DebugScreen? {
        UserDefaults.standard.string(forKey: "RyftScreen").flatMap(DebugScreen.init(rawValue:))
    }

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .invite: OnboardingStepPreview(step: .invite)
        case .consent: OnboardingStepPreview(step: .consent)
        case .aboutYou: OnboardingStepPreview(step: .aboutYou)
        case .accountHint:
            AccountHintSheet(hint: AccountHint(kind: "other_account_on_device", otherProvider: "email",
                                               otherLastSync: .now.addingTimeInterval(-86_400)),
                             keep: {}, useOther: {})
        case .signInMethods:
            NavigationStack { SignInMethodsView() }.environment(Self.emailAccount)
        case .syncDetails:
            DebugSyncDetails()
        }
    }

    /// One instance for the run: the screen loads its sign-in methods into it.
    @MainActor private static let emailAccount = AuthService.preview(provider: "email")
}

/// Profile → Data → Sync details, without the taps.
private struct DebugSyncDetails: View {
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        NavigationStack { SyncDetailsView(model: screens.profile.syncDetails) }
    }
}
#endif

/// Cold launch → the first Today frame (with or without cached data), for Instruments;
/// and the barrier optional startup work waits behind (flags, push, Train, the gate
/// re-check): the first frame of a screen that stays, not the splash.
@MainActor
enum LaunchSignpost {
    private static var state: OSSignpostIntervalState?
    private static var presented = false
    private static var waiting: [CheckedContinuation<Void, Never>] = []

    static func begin() {
        state = Signposts.launch.beginInterval("launch", id: Signposts.launch.makeSignpostID())
    }

    /// Today appeared: its first frame has been committed by the next display refresh,
    /// which ends the interval (only the first time).
    static func todayAppeared(cached: Bool) {
        guard state != nil else { return }
        NextFrame.after {
            guard let state else { return }
            Signposts.launch.endInterval("launch", state, "\(cached ? "cached data" : "no data")")
            Self.state = nil
        }
    }

    /// The tabs, welcome or onboarding appeared: after their first frame, what waits in
    /// `afterFirstFrame()` runs.
    static func screenAppeared() {
        guard !presented else { return }
        NextFrame.after {
            presented = true
            let resumed = waiting
            waiting = []
            resumed.forEach { $0.resume() }
        }
    }

    /// Returns once the first screen is on screen (right away after that). Launched into
    /// the background, that's when the scene first comes to the foreground.
    static func afterFirstFrame() async {
        guard !presented else { return }
        await withCheckedContinuation { waiting.append($0) }
    }
}

/// Calls `body` on the next display refresh: the frame committed in this run loop turn
/// has gone to the render server by then.
@MainActor
private final class NextFrame: NSObject {
    private var body: (@MainActor () -> Void)?
    private var link: CADisplayLink?

    static func after(_ body: @escaping @MainActor () -> Void) {
        let frame = NextFrame()
        frame.body = body
        // The link holds its target until it's invalidated.
        let link = CADisplayLink(target: frame, selector: #selector(tick))
        frame.link = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        link?.invalidate()
        link = nil
        body?()
        body = nil
    }
}

/// While the SDK reads the Keychain: the mark on Graphite, like the launch screen.
struct SplashView: View {
    var body: some View {
        RyftMark()
            .frame(width: 64, height: 64)
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .accessibilityLabel(Text("RYFT"))
    }
}

#Preview("Splash · dark") {
    SplashView().preferredColorScheme(.dark)
}

#Preview("Splash · light") {
    SplashView().preferredColorScheme(.light)
}

#Preview("App · dark") {
    RootView().previewEnvironment()
}

#Preview("App · light") {
    RootView().previewEnvironment(scheme: .light)
}
