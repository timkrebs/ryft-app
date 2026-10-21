import AppIntents
import Foundation
import SwiftUI
import UIKit

/// Owns the live session so Today, Strain and the Live Activity's deep link can
/// all open (and resume) it. The session itself lives in SwiftData, so it
/// survives app kills; `resumeIfNeeded()` finds it again.
@MainActor
@Observable
final class TrainCoordinator {
    static let shared = TrainCoordinator()

    /// Presented full screen while set.
    var live: SessionController?
    /// Shown after Finish, over whatever screen the user returns to.
    var summary: FinishSummary?
    var showsStart = false

    let sync: TrainSyncService
    let library: TrainLibrary
    /// The in-progress session, presented or not ("Workout in progress · 23 min").
    private(set) var active: LocalSession? {
        didSet { if (oldValue == nil) != (active == nil) { onActiveChange?(active != nil) } }
    }
    /// The home-screen quick action says Start or Resume (`WorkoutLauncher`).
    @ObservationIgnored var onActiveChange: ((Bool) -> Void)?

    /// The workout's Live Activity; `nil` in tests.
    private let liveActivity: RestActivityController?

    init(sync: TrainSyncService? = nil, library: TrainLibrary? = nil, liveActivities: Bool = true) {
        self.sync = sync ?? .shared
        self.library = library ?? .shared
        liveActivity = liveActivities ? .shared : nil
        active = self.sync.store.activeSession()
        // An activity left from a workout that's over (or an older version) goes.
        liveActivity?.endAll(except: active?.id)
    }

    // MARK: quick start

    /// What a start from outside the Train screens asks for.
    enum QuickStart: String, CaseIterable, Sendable {
        /// Today's plan day when there is one, else an empty session.
        case auto
        case empty
        /// The last completed workout again.
        case repeatLast
    }

    /// What `quickStart` did.
    enum QuickStartOutcome: Equatable {
        case resumed, plan, empty, repeated
    }

    /// Every "start a workout" entry point (Today, quick actions, App Intents, the control):
    /// a session in progress is resumed, never a second one started; otherwise today's plan
    /// day, an empty session, or the last workout again (empty when there's none).
    @discardableResult
    func quickStart(_ kind: QuickStart = .auto) async -> QuickStartOutcome {
        refreshActive()
        if active != nil {
            resume()
            return .resumed
        }
        // The cached plan day has no date: one from another day is asked for again first.
        var planned = library.today != nil
        if planned, kind == .auto, library.todayIsStale() {
            planned = await library.refreshToday() && library.today != nil
            refreshActive()
            if active != nil {
                resume()
                return .resumed
            }
        }
        switch kind {
        case .auto where planned:
            startFromToday()
            return .plan
        case .repeatLast:
            if let last = await library.lastSession() {
                // A session may have started while the last one loaded.
                refreshActive()
                guard active == nil else {
                    resume()
                    return .resumed
                }
                repeatSession(last)
                return .repeated
            }
            startEmpty()
            return .empty
        case .auto, .empty:
            startEmpty()
            return .empty
        }
    }

    private var store: TrainStore { sync.store }

    // MARK: starting

    func start(_ s: LocalSession) {
        active = s
        open(s)
    }

    func startFromToday() {
        guard let today = library.today else { return }
        start(SessionFactory.fromPlan(day: today.day, today: today, library: library.exercises, in: store))
    }

    func start(day: PlanDay) {
        let today = library.today?.day.id == day.id ? library.today : nil
        start(SessionFactory.fromPlan(day: day, today: today, library: library.exercises, in: store))
    }

    func startEmpty() {
        start(SessionFactory.empty(in: store))
    }

    func repeatSession(_ last: TrainSession) {
        start(SessionFactory.repeating(last, library: library.exercises, in: store))
    }

    // MARK: presenting

    /// Opens the workout in progress (Today/Strain banner, Live Activity "Done").
    func resume() {
        refreshActive()
        guard let s = active else { return }
        open(s)
    }

    private func open(_ s: LocalSession) {
        let controller = live?.session.id == s.id ? live : SessionController(session: s, sync: sync, liveActivity: liveActivity)
        if live !== controller { live?.stop() }
        // The start sheet must be gone before the full-screen session can appear.
        guard showsStart else {
            live = controller
            return
        }
        showsStart = false
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            live = controller
        }
    }

    /// Minimise: back to the app, the session keeps running.
    func close() {
        live = nil
    }

    func refreshActive() {
        active = store.activeSession()
    }

    /// `ryft://train/session` from the Live Activity (`ryft://train/session/<id>`
    /// is a deep link to a logged session, for `DeepLinkRouter`). Only resumes: a link (any app
    /// can open one) never starts a workout.
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "ryft", url.host == "train", url.path == "/session" || url.path.isEmpty else { return false }
        WorkoutLauncher.resume(coordinator: self)
        return true
    }

    /// Signed out or another account: the previous account's workout closes (it stays stored
    /// for that account) and leaves the lock screen.
    func accountChanged() {
        live?.stop()
        live = nil
        summary = nil
        showsStart = false
        liveActivity?.end()
        refreshActive()
    }

    // MARK: ending

    func finish(_ controller: SessionController, bodyweightKg: Double? = nil, export: WorkoutHealthExport? = nil) async {
        // A second tap while the first one finishes changes nothing.
        guard controller.phase != .finishing, controller.phase != .completed else { return }
        let s = controller.session
        let result = await controller.finish(bodyweightKg: bodyweightKg)
        active = nil
        // Shown over the session; Done closes both (`summaryDone`).
        summary = FinishSummary(sessionID: s.id, completed: result)
        // To Apple Health, if you turned that on, once it is complete here.
        if s.status == .completed, let end = s.endedAt {
            await (export ?? .shared).save(sessionID: s.id, start: s.startedAt, end: end)
        }
        await library.sessionCompleted()
    }

    func summaryDone() {
        summary = nil
        live = nil
    }

    func discard(_ controller: SessionController) {
        controller.discard()
        live = nil
        active = nil
    }
}

/// What the summary sheet shows: the server's answer, or "will sync".
struct FinishSummary: Identifiable {
    let sessionID: UUID
    var completed: TrainSession?
    var id: UUID { sessionID }
}

/// Keeps the screen awake while a workout is open.
struct KeepsScreenAwake: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

// MARK: - previews

/// In-memory Train objects shared by previews (no SwiftData on disk, no server).
@MainActor
enum TrainPreview {
    static let store = TrainStore(inMemory: true)
    static let sync = TrainSyncService(store: store, remote: { MockTrainSource.shared }, monitorsNetwork: false)
    static let library = TrainLibrary.preview(store: store)
    static let coordinator = TrainCoordinator(sync: sync, library: library)

    /// The live session preview's controller (no Live Activity from previews).
    static func liveController() -> SessionController {
        let s = store.activeSession() ?? MockTrain.liveSession(in: store)
        coordinator.refreshActive()
        return SessionController(session: s, sync: sync, liveActivity: nil)
    }
}

// MARK: - starting from outside the app's screens

/// Quick actions, App Intents (Siri, Shortcuts, Spotlight, the Action Button) and the Control
/// Center control: each lands in `TrainCoordinator.quickStart`, but only once the tabs are on
/// screen for an account (or demo data). Asked for earlier (the session being restored on a cold
/// launch, onboarding or the Health explanation still showing), it waits for the tabs; signing
/// out or another account drops it.
@MainActor
enum WorkoutLauncher {
    /// Set by `RyftApp`: a signed-in account or demo data; the session still being restored.
    static var hasAccount: () -> Bool = { false }
    static var isRestoring: () -> Bool = { false }
    /// The tabs are on screen (`RootView`), not onboarding or the Health explanation.
    private(set) static var tabsVisible = false
    private static var pending: TrainCoordinator.QuickStart?

    static func start(_ kind: TrainCoordinator.QuickStart, coordinator: TrainCoordinator? = nil) async {
        if hasAccount(), tabsVisible {
            pending = nil
            await (coordinator ?? .shared).quickStart(kind)
        } else if hasAccount() || isRestoring() {
            pending = kind
        }
    }

    /// Opens the workout in progress (the Live Activity, Siri's "resume"); `false` without one.
    @discardableResult
    static func resume(coordinator: TrainCoordinator? = nil) -> Bool {
        let c = coordinator ?? .shared
        guard hasAccount(), tabsVisible else { return false }
        c.refreshActive()
        guard c.active != nil else { return false }
        c.resume()
        return true
    }

    /// The tabs appeared: a start that waited for them runs now.
    static func tabsAppeared(coordinator: TrainCoordinator? = nil) async {
        tabsVisible = true
        guard let kind = pending else { return }
        pending = nil
        await start(kind, coordinator: coordinator)
    }

    static func tabsDisappeared() {
        tabsVisible = false
    }

    /// Signed out (also a restore that ended signed out), or another account: nothing carries over.
    static func discardPending() {
        pending = nil
    }

    // MARK: home-screen quick actions

    static let startType = "dev.timkrebs.ryft.workout.start"
    static let resumeType = "dev.timkrebs.ryft.workout.resume"

    /// "Start workout", or "Resume workout" while one runs.
    static func updateShortcutItems(resume: Bool) {
        let item = resume
            ? UIApplicationShortcutItem(type: resumeType, localizedTitle: String(localized: "Resume workout"),
                                        localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "play.fill"))
            : UIApplicationShortcutItem(type: startType, localizedTitle: String(localized: "Start workout"),
                                        localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "dumbbell.fill"))
        UIApplication.shared.shortcutItems = [item]
    }

    /// `true` when the item was ours.
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == startType || item.type == resumeType else { return false }
        // Resume or start: `quickStart` resumes whatever is running either way.
        Task { await start(.auto) }
        return true
    }
}

/// UIKit's half of the quick actions: the one that launched the app, and later ones.
@MainActor
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let item = connectionOptions.shortcutItem else { return }
        _ = WorkoutLauncher.handle(item)
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(WorkoutLauncher.handle(shortcutItem))
    }
}

// MARK: - App Intents (Siri, Shortcuts, Spotlight, the Action Button)

/// Which workout an intent starts.
enum WorkoutChoice: String, AppEnum {
    case today, empty, repeatLast

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workout")
    static let caseDisplayRepresentations: [WorkoutChoice: DisplayRepresentation] = [
        .today: DisplayRepresentation(title: "Today's plan"),
        .empty: DisplayRepresentation(title: "Empty workout"),
        .repeatLast: DisplayRepresentation(title: "Repeat last workout"),
    ]

    var quickStart: TrainCoordinator.QuickStart {
        switch self {
        case .today: return .auto
        case .empty: return .empty
        case .repeatLast: return .repeatLast
        }
    }
}

struct StartStrengthWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start strength workout"
    static let description = IntentDescription("Starts a strength workout in RYFT: today's plan, an empty workout or your last one again. A workout in progress is resumed.")
    static let openAppWhenRun = true
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Workout")
    var workout: WorkoutChoice?

    init() {}

    init(workout: WorkoutChoice?) {
        self.workout = workout
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutLauncher.start(workout?.quickStart ?? .auto)
        return .result()
    }
}

struct ResumeWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume workout"
    static let description = IntentDescription("Opens the strength workout in progress in RYFT.")
    static let openAppWhenRun = true
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if WorkoutLauncher.resume() { return .result(dialog: "Here's your workout.") }
        return .result(dialog: "No workout is running. Say “Start a RYFT workout” to start one.")
    }
}

/// The Control Center / Lock Screen control's action. Keep identical to
/// `RyftWidgets/OpenWorkoutIntent.swift`: the control (in the widget extension) runs it, and
/// with `openAppWhenRun` the system performs it here, in the app, by its type name.
struct OpenWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or resume workout"
    static let openAppWhenRun = true
    static let isDiscoverable = false
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutLauncher.start(.auto)
        return .result()
    }
}

/// "Start a RYFT workout", "Resume my RYFT workout".
struct RyftShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartStrengthWorkoutIntent(),
                    phrases: ["Start a \(.applicationName) workout",
                              "Start a strength workout in \(.applicationName)"],
                    shortTitle: "Start workout", systemImageName: "dumbbell.fill")
        AppShortcut(intent: ResumeWorkoutIntent(),
                    phrases: ["Resume my \(.applicationName) workout"],
                    shortTitle: "Resume workout", systemImageName: "play.fill")
    }
}

// MARK: - Apple Health (opt-in)

/// "Save strength workouts to Apple Health": off until you say so. Asked once at the end of
/// the first completed workout, and in Profile → Data. Turning it on asks iOS for write access
/// to workouts only; RYFT then writes one `HKWorkout` per completed session and nothing else,
/// not when the watch recorded the session itself, and never in demo mode.
@MainActor
@Observable
final class WorkoutHealthExport {
    static let shared = WorkoutHealthExport(health: HealthKitManager.shared, defaults: .standard)
    static let keyPrefix = "health.saveWorkouts."
    /// How far back a later watch workout still replaces RYFT's.
    static let tidyWindow: TimeInterval = 3 * 24 * 3_600

    enum Choice: String {
        case on, off
    }

    private let health: HealthStore
    private let defaults: UserDefaults
    private let account: () -> String?
    private let isDemo: () -> Bool
    /// Bumped on every change and when the app comes back (iOS may have changed the access
    /// meanwhile), so readers of `choice` and `canWrite` update.
    private var revision = 0
    /// Turning it on was refused by iOS (now, or earlier, so it showed no sheet).
    private(set) var refused = false
    @ObservationIgnored private var saving: Set<UUID> = []

    init(health: HealthStore, defaults: UserDefaults, account: (() -> String?)? = nil, isDemo: (() -> Bool)? = nil) {
        self.health = health
        self.defaults = defaults
        self.account = account ?? { AccountScope.current(defaults) }
        self.isDemo = isDemo ?? { Settings.shared.demoMode }
    }

    private var key: String { Self.keyPrefix + (account() ?? "signed-out") }

    /// `nil`: not asked yet. Per account.
    var choice: Choice? {
        _ = revision
        return defaults.string(forKey: key).flatMap(Choice.init(rawValue:))
    }

    var isOn: Bool { choice == .on }
    /// iOS allows it (Health → Sharing → Apps → RYFT → Workouts).
    var canWrite: Bool {
        _ = revision
        return health.canWriteWorkouts
    }
    /// What the switch shows: on, and still allowed in iOS.
    var isWriting: Bool { isOn && canWrite }
    /// Where to allow it: refused when turned on, or the access was taken away since.
    var needsAccess: Bool { refused || (isOn && !canWrite) }
    /// The first summary asks (Apple Health on this device, nothing chosen yet).
    var shouldAsk: Bool { choice == nil && health.isAvailable }

    private func set(_ choice: Choice) {
        defaults.set(choice.rawValue, forKey: key)
        revision += 1
    }

    /// Asks iOS for write access to workouts; on only when granted. `false` otherwise.
    @discardableResult
    func turnOn() async -> Bool {
        let granted = (try? await health.requestWorkoutWriteAccess()) ?? false
        refused = !granted
        set(granted ? .on : .off)
        return granted
    }

    /// Off, and the first summary's "Not now" (not asked again; Profile still has the switch).
    func turnOff() {
        refused = false
        set(.off)
    }

    /// After a completed session: written when on and still allowed in iOS, once per session.
    func save(sessionID: UUID, start: Date, end: Date) async {
        guard isOn, !isDemo(), health.canWriteWorkouts, end > start, !saving.contains(sessionID) else { return }
        saving.insert(sessionID)
        defer { saving.remove(sessionID) }
        do {
            let result = try await health.saveStrengthWorkout(sessionID: sessionID, start: start, end: end)
            if result != .saved { TrainStore.log.info("Workout not written to Apple Health again: \(String(describing: result), privacy: .public)") }
        } catch {
            TrainStore.log.notice("Workout not saved to Apple Health: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The app came back: the switch follows what iOS allows now, and a watch workout that
    /// arrived after the session replaces RYFT's in Fitness.
    func appBecameActive(now: Date) async {
        revision += 1
        guard isWriting, !isDemo() else { return }
        do {
            let removed = try await health.removeOwnWorkoutsRecordedElsewhere(since: now.addingTimeInterval(-Self.tidyWindow))
            if removed > 0 { TrainStore.log.info("Removed \(removed) RYFT workouts the watch recorded too") }
        } catch {
            TrainStore.log.notice("Apple Health tidy failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The sign-out wipe: every account's choice on this phone.
    static func wipe(defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
