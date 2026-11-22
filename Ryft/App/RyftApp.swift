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
    /// The launch sequence, for the life of the process (ADR 0017): a re-created scene reads it terminal.
    @State private var launch: LaunchSequenceModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LaunchSignpost.begin()
        // Read once: the coordinator and the launch sequence's decision both use it.
        let launchedInBackground = UIApplication.shared.applicationState == .background
        let state = AppState(env: .live)
        // The JSON response cache of earlier versions moves into SwiftData once.
        LegacyCacheMigration.runOnce(into: state.repository, train: .shared, defaults: .standard)
        // The store's copy from before the App Group, and export files an earlier run left: off the main actor, at
        // utility priority, so the first frame doesn't wait. After the store opened (`OrphanedStoreCleanup`).
        let liveStore = TrainStore.shared.storeURL
        Task(priority: .utility) {
            await OrphanedStoreCleanup.runOnce(live: liveStore)
            await DataExport.removeLeftoverFiles()
        }
        // Launched straight into the background (a HealthKit delivery, a BG task): the
        // coordinator starts there; the scene's activation brings it to the foreground.
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: state, sync: .shared),
                                          clock: AppEnvironment.live.clock,
                                          inBackground: launchedInBackground) {
            // A run in the background left a backlog: the backfill task takes it.
            if let left = SyncService.shared.backlogBytes { BackgroundWork.scheduleBackfill(backlogBytes: left) }
        }
        self.coordinator = coordinator
        _state = State(initialValue: state)
        // Training logs are health data: Train's outbox waits for the same rule as every upload (ADR 0008).
        let screens = ScreenModels(state: state, sync: .shared, coordinator: coordinator,
                                   store: .shared, library: .shared, trainSync: .shared, train: .shared)
        _screens = State(initialValue: screens)
        // Sign-out first deletes this phone's push registration, while the session still works.
        AuthService.shared.beforeSignOut = { [push = screens.push] in await push.signOut() }
        // Activities: another account's rows go and the upload stops inside the sign-in, sign-out or wipe itself,
        // before anything reads (design.md §8.4).
        state.bindAccountHooks(.shared)
        // A build without its platform values stops here (Debug) or shows only the
        // misconfigured-build screen (Release, RootView). Never a fallback host.
        PlatformConfig.checkAtLaunch()
        // Background refresh, the backfill (in addition to HealthKit delivery) and the nightly
        // cache compaction.
        BackgroundWork.register(coordinator: coordinator, backlogBytes: { SyncService.shared.backlogBytes },
                                afterRefresh: { [bedtime = screens.bedtime, uploader = state.env.uploader] in
                                    await bedtime.refresh()
                                    // Activities and nights still to send, on the background session, waited for
                                    // at most 20 s (the expiry stops the replay).
                                    await APIClient.$runsInBackground.withValue(true) {
                                        await uploader.flush(upTo: ActivityUploader.backgroundLimit, userInitiated: false)
                                    }
                                },
                                expired: { [uploader = state.env.uploader] in uploader.stopReplay() },
                                settled: { [repository = state.repository] in
                                    await repository.settledBeforeCompletion()
                                },
                                compact: { [repository = state.repository, env = state.env, train = TrainCoordinator.shared, bedtime = screens.bedtime] in
                                    await repository.compact()
                                    // A background-only run reaches an owed wipe here.
                                    await env.auth.finishOwedWipe(train: train, bedtime: bedtime)
                                    // Rows a session expiry parked more than 30 days ago.
                                    env.activities.deleteExpiredParked()
                                })
        // HealthKit wakes the app for deliveries, possibly in a background launch where the
        // scene's tasks don't run: the observers exist before launch finishes. Only for an
        // account that has seen the Health explanation (bootstrap covers the first time).
        if AuthService.shared.isSignedIn, Settings.shared.healthIntroDone, HealthKitManager.isAvailable {
            Self.observeHealthKit(HealthKitManager.shared, coordinator: coordinator)
        }
        // A sync that found HealthKit locked runs again once the phone is unlocked.
        BackgroundWork.resumeOnUnlock(coordinator: coordinator) { SyncService.shared.waitingForUnlock }
        // Quick actions, App Intents and the control start a workout once the tabs are on screen
        // for an account (or demo data); before that they wait (`WorkoutLauncher`).
        WorkoutLauncher.hasAccount = { AuthService.shared.isSignedIn || Settings.shared.demoMode }
        WorkoutLauncher.isRestoring = { AuthService.shared.state == .restoring }
        TrainCoordinator.shared.onActiveChange = { WorkoutLauncher.updateShortcutItems(resume: $0) }
        TrainCoordinator.shared.analytics = { [env = AppEnvironment.live] in env.analytics.track($0) }
        // The demo's workouts (ADR 0019): the list's one-time seed for workouts logged before it, then, with Demo data
        // off, the sweep. "Signed in" also counts the account `auth.lastUserID` still names (`AccountScope`): its wipe may
        // have failed, and its workouts must never be seeded as the demo's. Before the first unlock that id (and the
        // Keychain session) can't be read, so the seed waits for protected data.
        TrainCoordinator.shared.demoAtLaunch(demoMode: Settings.shared.demoMode,
                                             signedIn: AuthService.shared.isSignedIn || AccountScope.current() != nil,
                                             protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
        let workoutActive = TrainCoordinator.shared.active != nil
        WorkoutLauncher.updateShortcutItems(resume: workoutActive)
        // The launch sequence: decided now from a few reads, armed (the launch screen's colour) until the scene's
        // first `.active`; nothing waits for it. Links, notifications and quick actions at connect end it
        // (`QuickActionSceneDelegate`).
        let launch = LaunchSequenceModel(
            decision: LaunchPolicy.decide(.current(launchedInBackground: launchedInBackground,
                                                   workoutActive: workoutActive)),
            clock: AppEnvironment.live.clock)
        _launch = State(initialValue: launch)
        LaunchInterruptions.post = { [launch] in launch.send(.interrupted($0)) }
        // "Open in" never interrupts a workout: the file waits (ui.md E7).
        screens.importer.isWorkoutActive = { TrainCoordinator.shared.active != nil }
        #if DEBUG
        // UI tests: `-RyftResetTrain YES` starts without sessions or a queue.
        // The coordinator already holds the last run's session: it lets go of it, or a banner reads a deleted row.
        if UserDefaults.standard.bool(forKey: "RyftResetTrain") {
            TrainStore.shared.wipe()
            TrainCoordinator.shared.refreshActive()
            Settings.shared.setColumn = nil
            Settings.shared.sessionLayout = .focused
        }
        // UI tests: `-importUploadsUnavailable YES`, the import before the platform's contract (V5).
        ImportDemoFiles.applyLaunchArguments(to: env)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            // The launch sequence over the root, never instead of it (ADR 0017).
            LaunchHost(model: launch) { RootView() }
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
                // Dark only (NOCTURNE_STYLE §1). `UIUserInterfaceStyle` in Info.plist does the same for the
                // launch screen, alerts, share sheets and the rest of UIKit's chrome.
                .preferredColorScheme(.dark)
                // Teal is recovery only (design.md §P5-1): controls, menus, pickers and links take the ink.
                .tint(Theme.textPrimary)
                // Every toggle is the Nocturne switch (§P5-1.4); a screen that needs another style sets its own.
                // Presented content doesn't inherit the style: every sheet and cover ends with `presentedRoot()`.
                .toggleStyle(.ryft)
                // Signed out, or a different account: forget the previous user's screens.
                .onChange(of: auth.accountID) { old, new in
                    Task { await coordinator.cancel() }
                    // A workout asked for before, or the previous account's open one, doesn't carry over.
                    WorkoutLauncher.discardPending()
                    trainCoordinator.accountChanged()
                    state.accountChanged(from: old)
                    // That account's gates, steps and sync state are its own.
                    screens.onboarding.switchAccount(new)
                    // What it wears too (the previous account's choice was wiped with the store), and the
                    // catalog's copy, which went with it.
                    screens.devices.accountChanged()
                    env.catalogStore.accountChanged()
                    // Its last requests and a report's draft too: nothing of A's goes out as B.
                    screens.profile.accountChanged(from: old)
                    // A file opened while signed out is shown now; another account's import flow goes.
                    Task { await screens.importer.accountChanged(signedIn: new != nil) }
                    // The previous account's reminders and alarms go; this one's come back.
                    Task { await screens.bedtime.accountChanged() }
                    sync.accountChanged()
                    // The training import's job is the account's: the previous one's pass stops, answers are dropped.
                    screens.trainImport.accountChanged()
                    // Flags are per account: that account's cached answer, then a fresh one.
                    (env.flags as? FlagStore)?.switchAccount(new)
                    guard new != nil else { return }
                    Task { await screens.featureFlags?.refresh(force: true) }
                    // This account's activities and nights waiting on this iPhone (a sign-in after an expiry).
                    Task { await env.uploader.flush() }
                    // And an import it saved here.
                    Task { await screens.trainImport.resume() }
                    // A link that arrived signed out; this account's push registration.
                    screens.router.openPending()
                    Task { await screens.push.refresh() }
                }
                // Demo data on or off: its flags, or the account's, asked for again now.
                .onChange(of: settings.demoMode) { _, on in
                    (env.flags as? FlagStore)?.setDemo(on)
                    // Which day is being scored is the side's own (`ScoringWord`).
                    sync.forgetScoringWords()
                    // Train's outbox: demo's ops go when it's off, and the count follows the binding in use.
                    trainSync.demoModeChanged(on)
                    // Train's cache is one store for both sides (ADR 0019): what was read for the other side goes, and
                    // the plans and today's plan day are read for this one.
                    screens.trainDemoModeChanged()
                    // A start asked for in the demo doesn't carry over, as one doesn't across an account change.
                    if !on { WorkoutLauncher.discardPending() }
                    // Demo's remembered import matches and its import job go with it (also when it's switched off
                    // elsewhere); the import follows the binding in use.
                    if !on {
                        ImportMappingStore.forgetDemo(in: env.persistence)
                        TrainImportUploader.forgetDemo(in: env.persistence)
                    }
                    screens.trainImport.accountChanged()
                    // The import flow and any file it holds stay with the side they arrived on.
                    screens.importer.demoModeChanged()
                    // Tonight's plan, schedule and planned nights are the side's: the other side's went with the reset
                    // (`BedtimePlanner.forget`), and this one's plan is asked for now. Reminders and alarms are only ever
                    // the account's: demo data sets none and leaves the account's as they are; off again, they're set
                    // afresh.
                    Task { await screens.bedtime.refresh() }
                    Task { await screens.featureFlags?.refresh(force: true) }
                }
                // A restore that ended signed out: a start asked for during it doesn't wait for a sign-in.
                .onChange(of: auth.state) { _, now in
                    if now == .signedOut { WorkoutLauncher.discardPending() }
                }
                // A gate the platform reported (a 403 with a code, or X-RYFT-Gate): what's missing now.
                .onChange(of: APIStatus.shared.gates) { _, _ in
                    Task { await screens.onboarding.check(force: true) }
                }
                // A path's data gate opened (consent, invite, the policy in force known): its queue goes, and a held
                // sync runs again (`ScreenModels.gateChanged`); never when one appears.
                .onChange(of: screens.onboarding.uploadGate(for: .healthKit)) { _, gate in
                    screens.gateChanged(.healthKit, to: gate)
                }
                .onChange(of: screens.onboarding.uploadGate(for: .activities)) { _, gate in
                    screens.gateChanged(.activities, to: gate)
                }
                .onChange(of: screens.onboarding.uploadGate(for: .train)) { _, gate in
                    screens.gateChanged(.train, to: gate)
                }
                .onChange(of: screens.onboarding.uploadGate(for: .trainImport)) { _, gate in
                    screens.gateChanged(.trainImport, to: gate)
                }
                // A flag flip that arrived meanwhile takes effect as the next screen appears.
                .onChange(of: state.selectedTab) { _, _ in (env.flags as? FlagStore)?.applyPending() }
                .onChange(of: state.selectedTab) { _, tab in env.analytics.track(.screenViewed(AnalyticsScreen(tab))) }
                // The first successful sync unlocks the push pre-prompt on Today.
                .onChange(of: sync.phase) { _, phase in
                    if phase == .done, !screens.push.hasSynced { env.analytics.track(.firstSyncCompleted) }
                    if phase == .done { screens.push.syncSucceeded() }
                }
                // Today was fetched again (after a sync that touched it): tonight's bedtime moves
                // with the day's strain.
                .onChange(of: state.lastUpdated) { _, _ in
                    Task(priority: .utility) { await screens.bedtime.refresh() }
                }
                // GET /v1/config after the first frame, then whenever its ttl_sec (6 h) has
                // passed; below the work the user waits for.
                .task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await auth.finishOwedWipe(train: trainCoordinator, bedtime: screens.bedtime)
                    // Usage analytics from the cached config (its sink starts only if the user opted in), after an
                    // owed wipe has forgotten the last account's answer.
                    env.analytics.reevaluate()
                    // Activities a session expiry parked more than 30 days ago go (design.md §8.4).
                    env.activities.deleteExpiredParked()
                    // The tracker catalog: decoded off the main actor, its cached download re-validated.
                    await env.catalogStore.load()
                    await screens.featureFlags?.run()
                }
                .task {
                    appDelegate.handlers = PushHandlers(registrar: screens.push, router: screens.router,
                                                        coordinator: coordinator, reads: state.env.reads,
                                                        settled: { [repository = state.repository] in
                                                            await repository.settledBeforeCompletion()
                                                        })
                }
                // Back online: upload what HealthKit collected meanwhile, then reload.
                .onChange(of: connectivity.isOnline) { _, online in
                    guard online else { return }
                    Task { await coordinator.run(.reconnect) }
                    Task { await refreshTrain() }
                    // Reports saved offline (Profile → Report a problem).
                    Task(priority: .utility) { await screens.profile.report.flush() }
                }
                // Runs at launch (restored session) and again after each sign-in.
                .task(id: BootstrapKey(account: auth.accountID, healthIntroDone: settings.healthIntroDone,
                                       inviteBlocked: APIStatus.shared.inviteBlocked)) {
                    await bootstrap()
                }
                // ryft://train/session — the rest timer Live Activity; everything else
                // (universal links, ryft://…, the auth callback) goes through the router.
                .onOpenURL { url in
                    // "Open in RYFT" from Files or the Share sheet: a file, never a route (design §9).
                    if url.isFileURL {
                        Task { await screens.importer.open([url]) }
                        return
                    }
                    if trainCoordinator.handle(url) { return }
                    Task {
                        if await screens.router.open(url) { return }
                        _ = await auth.handle(url)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Writes paused at a background completion go on: iOS doesn't suspend the app in the foreground.
                state.repository.resumeWrites()
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
                    // ryftlab.de's tracker catalog once a day (behind `devices.setup`, never in demo mode).
                    await env.catalogStore.refreshIfDue()
                }
                Task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await screens.onboarding.check()
                }
                // Tonight's bedtime, with what the day brought so far.
                Task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await screens.bedtime.refresh()
                }
                // Reports still waiting (saved offline, or the platform was busy).
                Task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await screens.profile.report.flush()
                }
                // Saving workouts follows what Health allows now; a watch workout that arrived
                // after a session replaces RYFT's in Fitness.
                Task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await WorkoutHealthExport.shared.appBecameActive(now: .now)
                }
                // Activities and nights still to send ("not available yet" is asked again).
                Task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await env.uploader.appBecameActive()
                }
                // A training import still to upload; old jobs go.
                Task(priority: .utility) {
                    await LaunchSignpost.afterFirstFrame()
                    await screens.trainImport.appBecameActive()
                }
            } else if phase == .background {
                // A reopen within 10 minutes, even of an evicted process, shows no launch sequence (L9).
                LaunchContext.recordBackground(at: env.clock.now())
                // What failed in the last 1.5 s is still waiting for its coalesced save: write it
                // before iOS may suspend (or kill) the app.
                state.env.reads.savePendingNow()
                // Not a cancel: the page in flight finishes (in a background task), and what's
                // left of an import goes to the backfill task.
                _ = BackgroundWork.finishInBackground(coordinator: coordinator, app: UIApplication.shared,
                                                      backlogBytes: { sync.backlogBytes },
                                                      settled: { [repository = state.repository] in
                                                          await repository.settledBeforeCompletion()
                                                      })
                // An activity upload in flight finishes too; the rest waits for the next trigger.
                env.uploader.finishInBackground(app: UIApplication.shared)
                screens.trainImport.finishInBackground(app: UIApplication.shared)
                BackgroundWork.scheduleRefresh()
                BackgroundWork.scheduleCompaction()
            }
        }
    }

    /// Queued sessions go up first (waited for 3 s at most: a slow upload goes on); then the
    /// library, plans and today's plan.
    private func refreshTrain() async {
        guard settings.demoMode || auth.isSignedIn else { return }
        trainCoordinator.refreshActive()
        await trainSync.flush(upTo: .seconds(3))
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
    /// delivery (every launch, idempotent). A delivery completes right after its upload: HealthKit stops delivering
    /// after three late completions, and the run's own read-model writes come after it anyway (the refreshes follow
    /// the upload), so waiting for the writes would delay it for none of them.
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
    @Environment(\.launchInterrupt) private var launchInterrupt
    /// The root's cross-fades (splash, Welcome, the steps, the tabs) are `Theme.Motion.quick`, none under Reduce Motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The tabs are on screen: the only place the analytics prompt presents from.
    @State private var tabsShown = false

    var body: some View {
        Group {
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
        // "Send to RYFT" on the refresh Details sheet (Today's error card).
        .environment(\.reportProblemDestination, reportProblem)
        // A sheet or cover never slides over the launch sequence: it skips it, or hands off at once (ADR 0017).
        .onChange(of: presentsSomething, initial: true) { _, presents in
            if presents { launchInterrupt(.presentation) }
        }
    }

    /// Everything RootView presents. A new root sheet or cover joins this list (ADR 0017).
    private var presentsSomething: Bool {
        presentsBesidesAnalytics || (tabsShown && env.analytics.showsPrompt)
    }

    /// The other root presentations: the analytics prompt waits for them (`analyticsOptInPrompt(blocked:)`).
    private var presentsBesidesAnalytics: Bool {
        onboarding.accountHint != nil || train.live != nil || auth.needsNewPassword || onboarding.sheetStep != nil
            || screens.importer.flow != nil || screens.importer.showsUnavailable
    }

    /// The onboarding screen on show, for `onboarding_step`; nil on the tabs, Welcome and in demo mode.
    private var analyticsStep: OnboardingStepName? {
        guard !settings.demoMode, auth.state == .signedIn, !onboarding.holdsFirstRun else { return nil }
        if let step = onboarding.flowStep ?? onboarding.sheetStep { return OnboardingStepName(step) }
        if needsHealthIntro { return .health }
        return onboarding.showsTrackerSetup ? .trackerSetup : nil
    }

    /// Report a problem, pre-filled with what failed, pushed onto the Details sheet's stack.
    private var reportProblem: ReportProblemDestination {
        { [screens] resource, status, code, requestID in
            AnyView(ReportProblemView(model: screens.profile.report,
                                      context: ReportContext(resource: resource, status: status, requestID: requestID,
                                                             code: code)))
        }
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
                case .signedOut:
                    WelcomeView()
                        .safeAreaInset(edge: .top) { importSignInNote }
                        .transition(.opacity).onAppear(perform: LaunchSignpost.screenAppeared)
                // The account's first run waits for the platform's answer: no flash of the tabs.
                case .signedIn where onboarding.holdsFirstRun: SplashView().transition(.opacity)
                case .signedIn where onboarding.flowStep != nil:
                    OnboardingFlowView(model: onboarding).transition(.opacity)
                        .onAppear(perform: LaunchSignpost.screenAppeared)
                case .signedIn where needsHealthIntro:
                    HealthPermissionView().transition(.opacity).onAppear(perform: LaunchSignpost.screenAppeared)
                // After Apple Health, once: the chosen trackers' setup (`devices.setup`). The first sync runs.
                case .signedIn where onboarding.showsTrackerSetup:
                    TrackerSetupStepView(model: onboarding).transition(.opacity)
                        .onAppear(perform: LaunchSignpost.screenAppeared)
                case .signedIn: tabs.transition(.opacity).onAppear(perform: LaunchSignpost.screenAppeared)
                }
            }
        }
        .animation(rootFade, value: settings.demoMode ? .signedIn : auth.state)
        .animation(rootFade, value: needsHealthIntro)
        .animation(rootFade, value: onboarding.flowStep)
        .animation(rootFade, value: onboarding.showsTrackerSetup)
        .onChange(of: analyticsStep, initial: true) { _, step in if let step { env.analytics.track(.onboardingStep(step)) } }
        // The step on screen, full screen or as the sheet: after Agree and continue, the agree line's `shown`.
        .onChange(of: onboarding.flowStep ?? onboarding.sheetStep) { _, step in onboarding.stepShown(step) }
        // "This is a new RYFT account": once, before the steps.
        .sheet(item: Binding(get: { onboarding.accountHint }, set: { if $0 == nil { onboarding.keepThisAccount() } })) { hint in
            AccountHintSheet(hint: hint, keep: { onboarding.keepThisAccount() },
                             useOther: { await onboarding.useOtherAccount() })
                .presentedRoot()
        }
        // Someone who already answered the system prompt (an earlier version) skips the intro.
        .task(id: auth.accountID) {
            guard needsHealthIntro else { return }
            if await env.health.accessStatus() == .asked { settings.healthIntroDone = true }
        }
        // The live workout, from Today, Strain or the Live Activity.
        .fullScreenCover(item: Bindable(train).live) { SessionView(controller: $0).presentedRoot() }
        // A password-reset link signed the user in; ask for the new password now.
        .sheet(isPresented: Bindable(auth).needsNewPassword) {
            SetNewPasswordView(mode: .recovery).presentedRoot()
        }
    }

    /// One screen of the root replacing another (PR 6 A G10): `quick`, or none under Reduce Motion.
    private var rootFade: Animation? { Theme.Motion.respecting(reduceMotion, Theme.Motion.quick) }

    /// After sign-in, once per account: explain Apple Health before iOS asks.
    private var needsHealthIntro: Bool {
        env.health.isAvailable && !settings.healthIntroDone
    }

    private var onboarding: OnboardingCoordinator { screens.onboarding }

    /// The tabs: a workout asked for from the home screen, Siri or the control starts here.
    private var tabs: some View {
        tabBar
            .onAppear { Task { await WorkoutLauncher.tabsAppeared() } }
            .onDisappear { WorkoutLauncher.tabsDisappeared() }
            .onAppear {
                tabsShown = true
                env.analytics.track(.screenViewed(AnalyticsScreen(state.selectedTab)))
            }
            .onDisappear { tabsShown = false }
            .analyticsOptInPrompt(blocked: presentsBesidesAnalytics)
    }

    /// E6: a file opened while signed out waits in memory for the sign-in.
    @ViewBuilder
    private var importSignInNote: some View {
        if screens.importer.hasFileForSignIn {
            InlineMessage(message: String(localized: "Your file is ready. Sign in to continue.",
                                          comment: "Training import E6: a file was opened while signed out."),
                          systemImage: "doc.text")
                .padding(.horizontal, Theme.Metrics.screenPadding)
        }
    }

    private var tabBar: some View {
        RootTabs()
            // The training import: one cover for My Plans, Profile → Data and "Open in" (ui.md §2).
            .importPresentations(screens.importer)
            // From now on this account's gates are sheets, not the full-screen flow.
            .onAppear { onboarding.reachedTabs() }
            // A gate after the first run (policy updated, consent withdrawn): over the
            // current screen, never a reset to Welcome.
            .sheet(item: Bindable(onboarding).sheetStep) { step in
                OnboardingStepView(step: step, model: onboarding)
                    .interactiveDismissDisabled(!onboarding.canDefer(step))
                    .presentedRoot()
            }
    }
}

/// The five tabs (design.md §P5-2): still a `TabView`, so each tab keeps its stack and scroll while another shows, but its
/// system bar is hidden and `RyftTabBar` is drawn over the bottom edge, each tab ending at its top (`ryftTab()`). Tapping
/// the selected tab bumps its stack ID (`AppState.reselect`): the tab is rebuilt at its root, scrolled to the top. Its own
/// view so the hosted tests and shots draw the same host as the app.
struct RootTabs: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabView(selection: Bindable(state).selectedTab) {
            tab(.today) { TodayView() }
            tab(.sleep) { SleepView() }
            tab(.strain) { StrainView() }
            tab(.insights) { InsightsView() }
            tab(.profile) { ProfileView() }
        }
        .ryftTabBar(RyftTabBar(items: RyftTabBar.appTabs, selection: state.selectedTab.rawValue,
                               select: { state.selectedTab = AppTab(rawValue: $0) ?? state.selectedTab },
                               reselect: { if let tab = AppTab(rawValue: $0) { state.reselect(tab) } }))
    }

    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .id(state.stackID(for: tab))
            .ryftTab()
            .tag(tab)
    }
}

extension RyftTabBar {
    /// The app's five tabs, in `AppTab` order, identified `tab.<rawValue>`.
    static var appTabs: [Item] {
        AppTab.allCases.map { Item(tab: $0.rawValue, title: $0.title, identifier: $0.identifier) }
    }
}

#if DEBUG
/// Screens a screenshot run can open directly (`scripts/screenshots.sh`, `-RyftScreen <name>`).
enum DebugScreen: String {
    /// Profile → Notifications.
    case notifications
    case invite, consent, aboutYou, aboutYouSaved, accountHint, signInMethods, syncDetails, baselineSleepNeed, sleepNeed
    /// Bedtime & wake's editor, and Tonight with the default schedule.
    case bedtime, tonight
    /// Profile → About → Report a problem: the form, from Details, and its results.
    case reportProblem = "report-problem", reportProblemDetails = "report-problem-details"
    case reportProblemSent = "report-problem-sent", reportProblemQueued = "report-problem-queued"
    case reportProblemRateLimited = "report-problem-rate-limited"
    /// "What's included" open, scrolled to it.
    case reportProblemIncluded = "report-problem-included"
    /// Today's refresh Details sheet (503, 3 failures) with "Send to RYFT".
    case refreshDetailsSend = "refresh-details-send"
    /// "What do you wear?", the setup screen after Apple Health, Profile → Devices & sync, and one tracker's card
    /// (`-RyftTrackers garmin,oura` picks, `-RyftTracker fitbit` the card, `-RyftScrollBottom YES` starts at the end).
    case wear, trackerSetup = "tracker-setup", devices, trackerCard = "tracker-card"
    /// Check sync, pushed; with `-RyftSyncCheck <scenario>` in demo mode (`SyncCheckScenario`).
    case syncCheck = "sync-check"
    /// Welcome after a session expiry, with a parked run and night on a preview store (`activities.manual` off).
    case welcomeParked = "welcome-parked"
    /// The usage analytics prompt, and Profile → Privacy's switch (phase 1 shows neither to anyone).
    case analyticsPrompt = "analytics-prompt", analyticsRow = "analytics-row"

    static var requested: DebugScreen? {
        UserDefaults.standard.string(forKey: "RyftScreen").flatMap(DebugScreen.init(rawValue:))
    }

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .notifications: NavigationStack { NotificationSettingsView() }
        case .invite: OnboardingStepPreview(step: .invite)
        case .consent: OnboardingStepPreview(step: .consent)
        case .aboutYou: OnboardingStepPreview(step: .aboutYou)
        case .aboutYouSaved: OnboardingStepPreview(step: .aboutYou, saved: true)
        case .accountHint:
            AccountHintSheet(hint: AccountHint(kind: "other_account_on_device", otherProvider: "email",
                                               otherLastSync: .now.addingTimeInterval(-86_400)),
                             keep: {}, useOther: {})
        case .signInMethods:
            NavigationStack { SignInMethodsView() }.environment(Self.emailAccount)
        case .syncDetails:
            DebugSyncDetails()
        case .baselineSleepNeed, .sleepNeed:
            DebugBodySettings(screen: self)
        case .bedtime, .tonight:
            DebugBedtime(screen: self)
        case .reportProblem, .reportProblemDetails, .reportProblemSent, .reportProblemQueued,
             .reportProblemRateLimited, .reportProblemIncluded:
            DebugReportProblem(screen: self)
        case .refreshDetailsSend:
            DebugRefreshDetails()
        case .wear, .trackerSetup, .devices, .trackerCard:
            DebugDevices(screen: self)
        case .syncCheck:
            DebugSyncCheck()
        case .welcomeParked:
            DebugWelcomeParked()
        case .analyticsPrompt: AnalyticsOptInSheet { _ in }
        case .analyticsRow: AnalyticsOptInRowCapture()
        }
    }

    /// One instance for the run: the screen loads its sign-in methods into it.
    @MainActor private static let emailAccount = AuthService.preview(provider: "email")
}

/// Welcome signed out after a session expiry, its parked activities and nights on a store of their own.
private struct DebugWelcomeParked: View {
    @State private var env = AppEnvironment.previewWithParkedRows()
    @State private var auth: AuthService = {
        let auth = AuthService.preview(signedIn: false)
        auth.signOutNotice = AuthService.SignOutReason.sessionExpired.notice
        return auth
    }()

    var body: some View {
        WelcomeView()
            .environment(auth)
            .environment(\.appEnvironment, env)
    }
}

/// Bedtime & wake, or Tonight planned with the default schedule.
private struct DebugBedtime: View {
    let screen: DebugScreen
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        NavigationStack {
            if screen == .bedtime {
                SleepScheduleView(planner: screens.bedtime, placement: .root)
            } else {
                ScrollView { TonightCard(planner: screens.bedtime).padding() }
                    .background(Theme.background.ignoresSafeArea())
                    .task { if screens.bedtime.schedule == nil { await screens.bedtime.update(.default) } }
            }
        }
    }
}

/// The baseline sleep need editor, or Sleep's need breakdown, without the taps.
private struct DebugBodySettings: View {
    let screen: DebugScreen
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        if screen == .sleepNeed {
            SleepNeedSheet(need: MockData.todayDetail.sleep?.need, total: "8h 58m", editor: screens.bodySettings)
        } else {
            NavigationStack { BaselineSleepNeedForm(editor: screens.bodySettings, showsClose: true) }
        }
    }
}

/// Today with its refresh Details sheet open at the opening (medium) detent: the issue a pull left after three
/// 503s, data from 14:05.
private struct DebugRefreshDetails: View {
    @State private var showsDetails = true

    var body: some View {
        TodayView()
            .sheet(isPresented: $showsDetails) { RefreshDetailsSheet(issue: Self.issue).presentedRoot() }
    }

    private static var issue: RefreshIssue {
        let calendar = Calendar.current
        let at = { (h: Int, m: Int) in calendar.date(bySettingHour: h, minute: m, second: 12, of: .now) ?? .now }
        let error = ResourceError(kind: .transient, status: 503, code: nil,
                                  requestID: "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c", transport: nil, attempts: 3,
                                  at: at(14, 7))
        return RefreshIssue(reason: .busy, resource: .today, dataFrom: at(14, 5), failures: 3, error: error)
    }
}

/// Report a problem in one state: staged before the screen appears, so it isn't reset.
private struct DebugReportProblem: View {
    let screen: DebugScreen
    @Environment(ScreenModels.self) private var screens
    @State private var ready = false

    var body: some View {
        NavigationStack {
            if ready {
                ReportProblemView(model: screens.profile.report,
                                  context: screen == .reportProblemDetails ? .preview : nil,
                                  showsIncluded: screen == .reportProblemIncluded)
                    .defaultScrollAnchor(screen == .reportProblemIncluded ? .bottom : .top)
            }
        }
        .task {
            let model = screens.profile.report
            let message = "Pulling to refresh on Today showed an error, then the numbers came back."
            switch screen {
            case .reportProblemSent: model.stage(result: .sent)
            case .reportProblemQueued: model.stage(result: .queued, waiting: 1)
            case .reportProblemRateLimited: model.stage(message: message, result: .rateLimited)
            default: break
            }
            ready = true
        }
    }
}

/// The tracker setup's screens on demo data (`devices.setup` on), staged before they appear.
private struct DebugDevices: View {
    let screen: DebugScreen
    @Environment(\.appEnvironment) private var env
    @Environment(ScreenModels.self) private var screens
    @State private var ready = false

    var body: some View {
        ZStack {
            // Something to hang the staging task on before the screen exists.
            Theme.background.ignoresSafeArea()
            if ready {
                switch screen {
                case .wear: TrackerPickerView(model: screens.onboarding)
                case .trackerSetup: TrackerSetupStepView(model: screens.onboarding)
                case .trackerCard:
                    NavigationStack {
                        TrackerDetailView(tracker: tracker, model: screens.profile.devices, placement: .root) {}
                    }
                default: NavigationStack { DevicesAndSyncView(model: screens.profile.devices, placement: .root) }
                }
            }
        }
        // `-RyftScrollBottom YES`: the end of a long card (its store button) for a capture.
        .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "RyftScrollBottom") ? .bottom : .top)
        .task {
            // The demo choice is an Apple Watch, which needs no setup: the setup screen shows two that do. A real
            // account shows its own choice (or `-RyftTrackers`), nothing staged.
            if env.isDemo, screen == .trackerSetup, UserDefaults.standard.string(forKey: "RyftTrackers") == nil {
                screens.devices.stage(["garmin", "oura"])
            }
            ready = true
        }
    }

    /// `-RyftTracker <id>`, else the first chosen.
    private var tracker: Tracker {
        let catalog = env.trackerCatalog
        let id = UserDefaults.standard.string(forKey: "RyftTracker") ?? screens.devices.trackers.first ?? "garmin"
        return catalog.tracker(id) ?? MockData.tracker("garmin")
    }
}

/// Check sync as Devices & sync pushes it; the scenario picks the trackers in demo mode.
private struct DebugSyncCheck: View {
    @Environment(\.appEnvironment) private var env
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        NavigationStack { TrackerCheckView(model: .make(env: env, trackers: screens.devices.trackers), placement: .root) }
    }
}

/// Profile → Data → Sync details, without the taps.
private struct DebugSyncDetails: View {
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        NavigationStack { SyncDetailsView(model: screens.profile.syncDetails, placement: .root) }
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
            // Once: `presented` is set here. Under a playing launch sequence too, which proves startup doesn't wait.
            if !presented { Signposts.launch.emitEvent("first-screen") }
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

#Preview("App · dark") {
    RootView().previewEnvironment()
}

#Preview("Tabs · Today") {
    RootTabs().previewEnvironment()
}

#Preview("Tabs · Today · AX3") {
    RootTabs().previewEnvironment().environment(\.dynamicTypeSize, .accessibility3)
}
