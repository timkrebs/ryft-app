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
    private(set) var active: LocalSession?

    init(sync: TrainSyncService? = nil, library: TrainLibrary? = nil) {
        self.sync = sync ?? .shared
        self.library = library ?? .shared
        active = self.sync.store.activeSession()
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
    /// is a deep link to a logged session, for `DeepLinkRouter`).
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "ryft", url.host == "train", url.path == "/session" || url.path.isEmpty else { return false }
        resume()
        return true
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
