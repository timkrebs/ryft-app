// xcode: set sdk=iOS

import SwiftUI
import BackgroundTasks
import UIKit

@main
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
        let state = AppState(env: .live)
        // The JSON response cache of earlier versions moves into SwiftData once.
        LegacyCacheMigration.runOnce(into: state.repository, train: .shared, defaults: .standard)
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: .shared), clock: AppEnvironment.live.clock)
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
        // Background refresh (in addition to HealthKit delivery) and the nightly cache compaction.
        BackgroundWork.register(coordinator: coordinator) { [repository = state.repository] in
            repository.compact()
        }
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
                    if old != nil {
                        state.reset()
                        // Flags are per account: drop the old ones, ask for the new.
                        (env.flags as? FlagStore)?.reset()
                    }
                    guard new != nil else { return }
                    Task { await screens.featureFlags?.refresh(force: true) }
                    // A link that arrived signed out; this account's push registration.
                    screens.router.openPending()
                    Task { await screens.push.refresh() }
                }
                // The first successful sync unlocks the push pre-prompt on Today.
                .onChange(of: sync.phase) { _, phase in
                    if phase == .done { screens.push.syncSucceeded() }
                }
                // GET /v1/config now, then whenever its ttl_sec (6 h) has passed.
                .task { await screens.featureFlags?.run() }
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
                .task(id: BootstrapKey(account: auth.accountID, healthIntroDone: settings.healthIntroDone)) {
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
                Task { await coordinator.run(.appActive) }
                Task { await refreshTrain() }
                // Allowed in Settings meanwhile, a new token or language: tell the platform.
                Task { await screens.push.refresh() }
                Task { await screens.featureFlags?.refresh() }
            } else if phase == .background {
                // Foreground work stops; the system's background tasks take over.
                Task { await coordinator.cancel() }
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
        guard env.health.isAvailable, !env.isDemo else {
            await state.refresh()
            return
        }
        // Welcome first; HealthKit is asked for right after sign-in.
        guard auth.isSignedIn else { return }
        // First sign-in: create the platform user and set its timezone before anything syncs.
        if state.user == nil { await state.loadUserAfterSignIn() }
        // Health access only after the explanation screen (RootView); reruns when it's answered.
        guard settings.healthIntroDone else {
            await state.refresh()
            return
        }
        try? await env.health.requestAuthorization()
        await env.health.enableBackgroundDelivery()
        env.health.startObserving { [coordinator] in
            await coordinator.run(.healthKit)
        }
        await coordinator.run(.appActive)
    }

    private struct BootstrapKey: Equatable {
        let account: String?
        let healthIntroDone: Bool
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

/// Welcome until there's a session (or demo data), then the tabs.
struct RootView: View {
    @Environment(\.appEnvironment) private var env
    @Environment(AppState.self) private var state
    @Environment(AuthService.self) private var auth
    @Environment(Settings.self) private var settings
    @Environment(TrainCoordinator.self) private var train

    var body: some View {
        ZStack {
            if !PlatformConfig.isComplete {
                MisconfiguredBuildView()
            } else if settings.demoMode {
                tabs.transition(.opacity)
            } else {
                // Nothing personal is built before there is a session.
                switch auth.state {
                case .restoring: SplashView().transition(.opacity)
                case .signedOut: WelcomeView().transition(.opacity)
                case .signedIn where needsHealthIntro: HealthPermissionView().transition(.opacity)
                case .signedIn: tabs.transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: settings.demoMode ? .signedIn : auth.state)
        .animation(.easeInOut(duration: 0.3), value: needsHealthIntro)
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

    private var tabs: some View {
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