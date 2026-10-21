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

    init(sync: TrainSyncService? = nil, library: TrainLibrary? = nil) {
        self.sync = sync ?? .shared
        self.library = library ?? .shared
        active = self.sync.store.activeSession()
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
        switch kind {
        case .auto where library.today != nil:
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
        let controller = live?.session.id == s.id ? live : SessionController(session: s, sync: sync, liveActivity: .shared)
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
    /// is a deep link to a logged session, for `DeepLinkRouter`); `ryft://train/start`
    /// (`?kind=empty|repeatLast`) starts or resumes a workout.
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "ryft", url.host == "train" else { return false }
        switch url.path {
        case "/session", "":
            resume()
            return true
        case "/start":
            let kind = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "kind" }?.value.flatMap(QuickStart.init(rawValue:)) ?? .auto
            Task { await WorkoutLauncher.start(kind, coordinator: self) }
            return true
        default:
            return false
        }
    }

    // MARK: ending

    func finish(_ controller: SessionController, bodyweightKg: Double? = nil) async {
        let s = controller.session
        let result = await controller.finish(bodyweightKg: bodyweightKg)
        active = nil
        // Shown over the session; Done closes both (`summaryDone`).
        summary = FinishSummary(sessionID: s.id, completed: result)
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

/// Quick actions, App Intents (Siri, Shortcuts, Spotlight, the Action Button), the Control
/// Center control and `ryft://train/start`: signed in (or in demo mode), each lands in
/// `TrainCoordinator.quickStart`. A start that arrives while the session is still being
/// restored (a cold launch from the home screen) waits for it (`runPending`).
@MainActor
enum WorkoutLauncher {
    /// Set by `RyftApp`: whether a workout can start now, and whether that's still unknown.
    static var canStart: () -> Bool = { false }
    static var isRestoring: () -> Bool = { false }
    private static var pending: TrainCoordinator.QuickStart?

    static func start(_ kind: TrainCoordinator.QuickStart, coordinator: TrainCoordinator? = nil) async {
        guard canStart() else {
            if isRestoring() { pending = kind }
            return
        }
        await (coordinator ?? .shared).quickStart(kind)
    }

    /// After the session is restored (bootstrap): the start that waited for it.
    static func runPending(coordinator: TrainCoordinator? = nil) async {
        guard let kind = pending else { return }
        pending = nil
        await start(kind, coordinator: coordinator)
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
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let item = connectionOptions.shortcutItem else { return }
        Task { @MainActor in _ = WorkoutLauncher.handle(item) }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in completionHandler(WorkoutLauncher.handle(shortcutItem)) }
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

    @MainActor
    func perform() async throws -> some IntentResult {
        TrainCoordinator.shared.resume()
        return .result()
    }
}

/// The Control Center / Lock Screen control's action. Keep identical to
/// `RyftWidgets/OpenWorkoutIntent.swift`: the control (in the widget extension) runs it, and
/// with `openAppWhenRun` the system performs it here, in the app, by its type name.
struct OpenWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or resume workout"
    static let openAppWhenRun = true
    static let isDiscoverable = false

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
