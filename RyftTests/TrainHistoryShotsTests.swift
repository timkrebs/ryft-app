import os
import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes T6B.5's screens (History, the session detail, the exercise page) as 3x PNGs, whole pages (`PagedWindowShot`), at
/// the default size and at AX3 when `TRAIN_HISTORY_SHOTS_DIR` is set; otherwise does nothing. For comparing with the approved
/// drafts (`b-13`, `b-14`, `b-15`) before and after a change:
/// `TEST_RUNNER_TRAIN_HISTORY_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/TrainHistoryShotsTests test-without-building`
/// (`TEST_RUNNER_TRAIN_HISTORY_SHOTS_ONLY=history,exercise` draws a subset). Drawn from a real window (`drawHierarchy`); not a
/// golden-file test.
@MainActor
@Suite("T6B.5: History, session detail and exercise page, shots", .serialized)
struct TrainHistoryShotsTests {
    /// The screens, each its own test (a test has a minute).
    nonisolated static let screens = ["history", "history-empty", "history-failed", "history-offline", "session-detail",
                                      "session-detail-unscored", "exercise", "exercise-first-time", "exercise-failed",
                                      "exercise-offline", "exercise-timed", "exercise-bodyweight"]

    /// Three hours ago: the offline line's time.
    private static var fetched: Date { .now.addingTimeInterval(-3 * 3600) }

    private static func view(_ name: String) -> AnyView {
        switch name {
        case "history":
            return AnyView(NavigationStack { TrainHistoryView().trainDestinations() }.environment(TrainHistoryFixtures.library()))
        case "history-empty":
            let library = TrainLibrary(store: TrainStore(inMemory: true), remote: { MockTrainSource(start: .empty) },
                                       restore: false)
            return AnyView(NavigationStack { TrainHistoryView().trainDestinations() }.environment(library))
        case "history-failed":
            return AnyView(NavigationStack { TrainHistoryView() }.environment(TrainHistoryFixtures.library(cached: false, fails: true)))
        case "history-offline":
            let library = TrainHistoryFixtures.library()
            let copy = TrainHistoryViewModel(library: library, sessions: MockTrain.history.reversed().map(SessionSummary.init),
                                             fresh: false, fetchedAt: fetched)
            return AnyView(NavigationStack { TrainHistoryPage(model: copy) }.environment(library))
        case "session-detail", "session-detail-unscored":
            let session = name == "session-detail" ? MockTrain.completed : MockTrain.completedUnscored
            return AnyView(NavigationStack { SessionDetailView(sessionID: session.id).trainDestinations() }
                .environment(TrainHistoryFixtures.library(session: session)))
        case "exercise":
            return AnyView(NavigationStack { ExerciseDetailView(exerciseID: MockTrain.bench.id).trainDestinations() }
                .environment(TrainHistoryFixtures.library()))
        case "exercise-failed":
            return AnyView(NavigationStack { ExerciseDetailView(exerciseID: MockTrain.bench.id, name: MockTrain.bench.name) }
                .environment(TrainHistoryFixtures.library(cached: false, fails: true)))
        case "exercise-offline":
            return AnyView(NavigationStack { page(MockTrain.exerciseHistory(for: MockTrain.bench.id, sessions: MockTrain.history),
                                                  MockTrain.bench, fresh: false) })
        case "exercise-timed":
            let holds = (0..<3).map { SessionSet(setIndex: $0, durationSec: 45) }
            return AnyView(NavigationStack { page(ExerciseDetailPreview.withoutEstimates(MockTrain.plank, sets: holds), MockTrain.plank) })
        case "exercise-bodyweight":
            let reps = (0..<3).map { SessionSet(setIndex: $0, reps: 8) }
            return AnyView(NavigationStack { page(ExerciseDetailPreview.withoutEstimates(MockTrain.pullUp, sets: reps), MockTrain.pullUp) })
        default:
            let history = MockTrain.firstTimeHistory(for: MockTrain.bench.id)
            return AnyView(NavigationStack { ExerciseDetailView(exerciseID: MockTrain.bench.id).trainDestinations() }
                .environment(TrainHistoryFixtures.library(history: history)))
        }
    }

    /// The exercise page as read: `fresh` false is the copy on this phone, fetched three hours ago.
    private static func page(_ history: ExerciseHistory, _ exercise: Exercise, fresh: Bool = true) -> some View {
        let library = TrainHistoryFixtures.library()
        let model = ExerciseDetailViewModel(exerciseID: exercise.id, history: history, library: library, clock: SystemClock(),
                                            fresh: fresh, fetchedAt: fresh ? nil : fetched)
        return ExerciseDetailPage(model: model).environment(library)
    }

    /// `TRAIN_HISTORY_SHOTS_ONLY`: a comma-separated subset of `screens`.
    @Test(arguments: screens)
    func writeScreen(_ name: String) async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["TRAIN_HISTORY_SHOTS_DIR"] else { return }
        if let only = env["TRAIN_HISTORY_SHOTS_ONLY"], !only.split(separator: ",").contains(Substring(name)) { return }
        for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                           ("ax3", .accessibility3, .accessibilityExtraLarge)] {
            // As the app's root sets it; without the scroll edge effect, a paged shot's later parts stay sharp at the top.
            try await HostedWindow.run(width: 390, height: 844, typeSize: typeSize, category: category,
                                       Self.view(name).toggleStyle(.ryft).historyShotsWithoutEdgeEffect()
                                           .environment(\.locale, Locale(identifier: "en_US"))) { w in
                try await w.settle()
                try await w.settle()
                let image = try await PagedWindowShot.image(w)
                let data = try #require(image.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(size).png"))
            }
        }
    }
}

private extension View {
    /// iOS 26 blurs what scrolls under a scroll view's top edge: in a paged shot that is the top of every later part.
    @ViewBuilder func historyShotsWithoutEdgeEffect() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}

/// Libraries for History's tests and shots: demo data with the exercises cached, a session or an exercise history of the
/// test's own, or a platform that never answers or can't be reached.
@MainActor
enum TrainHistoryFixtures {
    static func library(session: TrainSession? = nil, history: ExerciseHistory? = nil, hangs: Bool = false,
                        cached: Bool = true, fails: Bool = false) -> TrainLibrary {
        rig(session: session, history: history, hangs: hangs, cached: cached, fails: fails).library
    }

    /// The library with its store and its platform, whose `fails` a test switches (offline, then back).
    static func rig(session: TrainSession? = nil, history: ExerciseHistory? = nil, hangs: Bool = false, cached: Bool = true,
                    fails: Bool = false, list: [SessionSummary]? = nil)
        -> (library: TrainLibrary, source: TrainHistoryFixtureSource, store: TrainStore) {
        let store = TrainStore(inMemory: true)
        if cached { store.cache(exercises: MockTrain.exercises) }
        let source = TrainHistoryFixtureSource(session: session, history: history, hangs: hangs, list: list)
        source.fails = fails
        return (TrainLibrary(store: store, remote: { source }, restore: cached), source, store)
    }
}

/// Demo data's platform, with one session, one exercise history or the session list replaced, no answer at all (loading
/// states), or none to be had (`fails`: offline).
final class TrainHistoryFixtureSource: TrainDataSource, @unchecked Sendable {
    private let base = MockTrainSource()
    private let session: TrainSession?
    private let history: ExerciseHistory?
    private let hangs: Bool
    private let list: [SessionSummary]?
    private let failing = OSAllocatedUnfairLock(initialState: false)
    private let reads = OSAllocatedUnfairLock(initialState: 0)

    /// How often a whole session was asked for (the session detail reads it again when it reappears).
    var sessionReads: Int { reads.withLock { $0 } }

    /// The reads History's pages make (the list, a session, an exercise's history) throw, as offline.
    var fails: Bool {
        get { failing.withLock { $0 } }
        set { failing.withLock { $0 = newValue } }
    }

    init(session: TrainSession?, history: ExerciseHistory?, hangs: Bool, list: [SessionSummary]? = nil) {
        self.session = session
        self.history = history
        self.hangs = hangs
        self.list = list
    }

    private func hang() async throws {
        if hangs { try await Task.sleep(for: .seconds(60)) }
        if fails { throw URLError(.notConnectedToInternet) }
    }

    func exercises() async throws -> [Exercise] { try await base.exercises() }
    func createExercise(_ e: Exercise) async throws -> Exercise { try await base.createExercise(e) }
    func exerciseHistory(id: UUID) async throws -> ExerciseHistory {
        try await hang()
        if let history, history.exerciseId == id { return history }
        return try await base.exerciseHistory(id: id)
    }
    func plans() async throws -> PlansOverview { try await base.plans() }
    func plan(id: UUID) async throws -> Plan { try await base.plan(id: id) }
    func savePlan(_ p: Plan) async throws -> Plan { try await base.savePlan(p) }
    func deletePlan(id: UUID) async throws { try await base.deletePlan(id: id) }
    func enroll(planID: UUID) async throws -> Enrollment { try await base.enroll(planID: planID) }
    func pauseEnrollment() async throws { try await base.pauseEnrollment() }
    func planToday() async throws -> PlanToday? { try await base.planToday() }
    func sessions(from: Date, to: Date) async throws -> [SessionSummary] {
        try await hang()
        if let list { return list.filter { $0.startedAt >= from && $0.startedAt <= to } }
        let all = try await base.sessions(from: from, to: to)
        guard let session else { return all }
        return all.map { $0.id == session.id ? SessionSummary(session) : $0 }
    }
    func session(id: UUID) async throws -> TrainSession {
        reads.withLock { $0 += 1 }
        try await hang()
        if let session, session.id == id { return session }
        return try await base.session(id: id)
    }
    func putSession(_ s: TrainSession) async throws -> SessionPutResult { try await base.putSession(s) }
    func completeSession(id: UUID, _ body: SessionComplete) async throws -> TrainSession {
        try await base.completeSession(id: id, body)
    }
    func deleteSession(id: UUID) async throws { try await base.deleteSession(id: id) }
}
