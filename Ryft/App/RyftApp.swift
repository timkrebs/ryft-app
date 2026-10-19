// xcode: set sdk=iOS

import SwiftUI
import BackgroundTasks
import UIKit

@main
struct RyftApp: App {
    @StateObject private var settings = Settings.shared
    @StateObject private var auth = AuthService.shared
    @StateObject private var sync = SyncService.shared
    @StateObject private var state = AppState()
    @StateObject private var trainLibrary = TrainLibrary.shared
    @StateObject private var trainSync = TrainSyncService.shared
    @StateObject private var trainCoordinator = TrainCoordinator.shared
    @StateObject private var connectivity = ConnectivityMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // A build without its platform values stops here (Debug) or shows only the
        // misconfigured-build screen (Release, RootView). Never a fallback host.
        PlatformConfig.checkAtLaunch()
        // Opportunistic refresh when iOS gives us background time (in addition
        // to HealthKit background delivery). Identifier must match Info.plist →
        // BGTaskSchedulerPermittedIdentifiers.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            Self.handleRefresh(task)
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
                .environmentObject(settings)
                .environmentObject(auth)
                .environmentObject(sync)
                .environmentObject(state)
                .environmentObject(trainLibrary)
                .environmentObject(trainSync)
                .environmentObject(trainCoordinator)
                .environmentObject(connectivity)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(Theme.accent)
                // Signed out, or a different account: forget the previous user's screens.
                .onChange(of: auth.accountID) { old, _ in
                    if old != nil { state.reset() }
                }
                // Back online: upload what HealthKit collected meanwhile, then reload.
                .onChange(of: connectivity.isOnline) { _, online in
                    guard online else { return }
                    Task { await state.syncAndRefresh(using: sync) }
                    Task { await refreshTrain() }
                }
                // Runs at launch (restored session) and again after each sign-in.
                .task(id: auth.accountID) { await bootstrap() }
                // ryft://auth/callback — email confirmation and password reset (PKCE);
                // ryft://train/session — the rest timer Live Activity.
                .onOpenURL { url in
                    if trainCoordinator.handle(url) { return }
                    Task { await auth.handle(url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await state.syncAndRefresh(using: sync) }
                Task { await refreshTrain() }
            } else if phase == .background {
                Self.scheduleRefresh()
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
        guard HealthKitManager.isAvailable, !settings.demoMode else {
            await state.refresh()
            return
        }
        // Welcome first; HealthKit is asked for right after sign-in.
        guard auth.isSignedIn else { return }
        // First sign-in: create the platform user and set its timezone before anything syncs.
        if state.user == nil { await state.loadUserAfterSignIn() }
        try? await HealthKitManager.shared.requestAuthorization()
        await HealthKitManager.shared.enableBackgroundDelivery()
        HealthKitManager.shared.startObserving {
            await SyncService.shared.syncNow()
        }
        await state.syncAndRefresh(using: sync)
    }

    // MARK: background refresh

    static let refreshTaskID = "dev.timkrebs.ryft.refresh"

    static func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleRefresh()
        let work = Task { await SyncService.shared.syncNow() }
        task.expirationHandler = { work.cancel() }
        Task { await work.value; task.setTaskCompleted(success: true) }
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
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var train: TrainCoordinator

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
                case .signedIn: tabs.transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: settings.demoMode ? .signedIn : auth.state)
        // The live workout, from Today, Strain or the Live Activity.
        .fullScreenCover(item: $train.live) { SessionView(controller: $0) }
        // A password-reset link signed the user in; ask for the new password now.
        .sheet(isPresented: $auth.needsNewPassword) {
            SetNewPasswordView(mode: .recovery)
        }
    }

    private var tabs: some View {
        TabView(selection: $state.selectedTab) {
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