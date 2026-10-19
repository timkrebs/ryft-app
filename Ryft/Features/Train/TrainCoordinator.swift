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
        guard url.scheme == "ryft", url.host == "train", DeepLink(url: url) == nil else { return false }
        resume()
        return true
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
