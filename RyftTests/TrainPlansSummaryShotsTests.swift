import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes T6B.3/T6B.4's screens (the workout summary, the resume banner, Plans, plan detail, the plan builder) as 3x PNGs, whole
/// pages (`PagedWindowShot`), at the default size and at AX3 when `TRAIN_PLANS_SHOTS_DIR` is set; otherwise does nothing. For
/// comparing with the approved drafts (`b-09`, `b-10`, `b-25`, `b-11`, `b-12`, `b-23`) before and after a change:
/// `TEST_RUNNER_TRAIN_PLANS_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/TrainPlansSummaryShotsTests test-without-building`
/// (`TEST_RUNNER_TRAIN_PLANS_SHOTS_ONLY=plans,banner` draws a subset).
/// Drawn from a real window (`drawHierarchy`); not a golden-file test.
@MainActor
@Suite("T6B.3/T6B.4: summary, banner and Plans, shots", .serialized)
struct TrainPlansSummaryShotsTests {
    /// The screens, each its own test (a test has a minute).
    nonisolated static let screens = ["summary", "summary-no-records", "summary-pending", "banner", "plans", "plans-paused",
                                      "plans-empty-mine", "plans-import", "plan-detail", "plan-detail-active", "plan-builder",
                                      "plan-builder-new"]

    /// The screen and its window's height at the default size and at AX3. The summary's window holds the whole sheet, so its
    /// pinned Done shows once (a paged shot repeats what floats over the page, and hides what sits under it); the banner's
    /// is tall enough for its stacked AX3 layout.
    private static func view(_ name: String) -> (AnyView, CGFloat, CGFloat) {
        switch name {
        case "summary": return (AnyView(TrainShotFixtures.summary(completed: MockTrain.completed)), 1_200, 2_650)
        case "summary-no-records": return (AnyView(TrainShotFixtures.summary(completed: MockTrain.completedWithoutRecords)), 1_000, 2_300)
        case "summary-pending": return (AnyView(TrainShotFixtures.pendingSummary()), 1_000, 2_300)
        case "banner": return (AnyView(TrainShotFixtures.banner()), 300, 500)
        case "plans": return (AnyView(TrainShotFixtures.plans(MockTrain.catalog())), 844, 844)
        // Paused as the platform reports it: no enrolment, the plan remembered on this iPhone (set in `writeScreen`).
        case "plans-paused": return (AnyView(TrainShotFixtures.plans(MockTrain.catalog(enrolled: false))), 844, 844)
        case "plans-import": return (AnyView(TrainShotFixtures.importPlans()), 844, 844)
        case "plans-empty-mine": return (AnyView(TrainShotFixtures.plans(MockTrain.catalog(enrolled: false, mine: false))), 844, 844)
        case "plan-detail": return (AnyView(TrainShotFixtures.planDetail(MockTrain.fullBody.id)), 844, 844)
        case "plan-detail-active": return (AnyView(TrainShotFixtures.planDetail(MockTrain.upperLower.id)), 844, 844)
        case "plan-builder": return (AnyView(PlanBuilderView(plan: MockTrain.upperLower.copy())), 844, 844)
        default: return (AnyView(PlanBuilderView(plan: .blank())), 844, 844)
        }
    }

    /// `TRAIN_PLANS_SHOTS_ONLY`: a comma-separated subset of `screens`.
    @Test(arguments: screens)
    func writeScreen(_ name: String) async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["TRAIN_PLANS_SHOTS_DIR"] else { return }
        if let only = env["TRAIN_PLANS_SHOTS_ONLY"], !only.split(separator: ",").contains(Substring(name)) { return }
        let previous = TrainShotFixtures.setPausedPlan(name == "plans-paused" ? MockTrain.upperLower.id : nil)
        defer { TrainShotFixtures.setPausedPlan(previous) }
        let (view, height, ax3Height) = Self.view(name)
        for (size, typeSize, category, h) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large, height),
                                              ("ax3", .accessibility3, .accessibilityExtraLarge, ax3Height)] {
            // As the app's root sets it; without the scroll edge effect, a paged shot's later parts stay sharp at the top.
            try await HostedWindow.run(width: 390, height: h, typeSize: typeSize, category: category,
                                       view.toggleStyle(.ryft).shotsWithoutEdgeEffect()
                                           .environment(\.locale, Locale(identifier: "en_US"))) { w in
                try await w.settle()
                try await w.settle()
                let image = name == "plans-import" ? try await Self.openMenu(w) : try await PagedWindowShot.image(w)
                let data = try #require(image.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(size).png"))
            }
        }
    }
}

extension TrainPlansSummaryShotsTests {
    /// New plan's menu open over Plans: the window, and the scene's window that holds the menu drawn over it. Without a
    /// menu (it didn't open), the page alone.
    private static func openMenu(_ w: HostedWindow) async throws -> UIImage {
        let newPlan = try #require(w.nodes().first { $0.identifier == "plans.newPlan" })
        _ = newPlan.activate()
        try? await w.wait("the menu") { w.menuItem("Start from scratch") != nil }
        try await w.settle()
        let menuWindow = (w.menuItem("Start from scratch") as? UIView)?.window
        let bounds = w.window.bounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            w.window.drawHierarchy(in: bounds, afterScreenUpdates: true)
            if let menuWindow, menuWindow !== w.window {
                menuWindow.drawHierarchy(in: menuWindow.convert(menuWindow.bounds, to: w.window), afterScreenUpdates: true)
            }
        }
    }
}

private extension View {
    /// iOS 26 blurs what scrolls under a scroll view's top edge: in a paged shot that is the top of every later part.
    @ViewBuilder func shotsWithoutEdgeEffect() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}

/// The platform out of reach: every call fails as a dropped connection does.
struct OfflineTrainSource: TrainDataSource {
    private var offline: URLError { URLError(.notConnectedToInternet) }
    func exercises() async throws -> [Exercise] { throw offline }
    func createExercise(_ e: Exercise) async throws -> Exercise { throw offline }
    func exerciseHistory(id: UUID) async throws -> ExerciseHistory { throw offline }
    func plans() async throws -> PlansOverview { throw offline }
    func plan(id: UUID) async throws -> Plan { throw offline }
    func savePlan(_ p: Plan) async throws -> Plan { throw offline }
    func deletePlan(id: UUID) async throws { throw offline }
    func enroll(planID: UUID) async throws -> Enrollment { throw offline }
    func pauseEnrollment() async throws { throw offline }
    func planToday() async throws -> PlanToday? { throw offline }
    func sessions(from: Date, to: Date) async throws -> [SessionSummary] { throw offline }
    func session(id: UUID) async throws -> TrainSession { throw offline }
    func putSession(_ s: TrainSession) async throws -> SessionPutResult { throw offline }
    func completeSession(id: UUID, _ body: SessionComplete) async throws -> TrainSession { throw offline }
    func deleteSession(id: UUID) async throws { throw offline }
}

/// The states the shots draw, each from its own store where it needs one.
@MainActor
enum TrainShotFixtures {
    /// Sets the plan remembered as paused (`train.pausedPlanID`; nil: none) and returns the one that was there, to put back.
    @discardableResult
    static func setPausedPlan(_ id: UUID?) -> UUID? {
        let key = "train.pausedPlanID"
        let previous = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:))
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return previous
    }

    /// Runs `body` with `id` remembered as paused, then puts back what was there.
    static func withPausedPlan(_ id: UUID?, _ body: () -> Void) {
        let previous = setPausedPlan(id)
        defer { setPausedPlan(previous) }
        body()
    }

    /// Offline for the reads (nothing is sent); kept alive, as the scheduler holds its environment weakly.
    private static let offlineEnvironment = AppEnvironment.test(online: false)

    /// Plans with nothing cached, offline.
    static func offlinePlans() -> some View {
        let library = TrainLibrary.testing(store: TrainStore(inMemory: true), remote: { MockTrainSource.shared }, restore: true)
        library.reads = offlineEnvironment.reads
        return NavigationStack { PlansView().trainDestinations() }
            .environment(library)
    }

    /// A plan page whose plan is neither cached nor loadable.
    static func unloadablePlan(_ id: UUID) -> some View {
        NavigationStack { PlanDetailView(planID: id) }
            .environment(TrainLibrary.testing(store: TrainStore(inMemory: true), remote: { OfflineTrainSource() }, restore: true))
    }

    /// Plans with `train.import` on: New plan is a menu (Start from scratch, Import from file).
    static func importPlans() -> some View {
        plans(MockTrain.catalog())
            .previewEnvironment(AppState.preview(flags: [.trainImport: true]))
    }

    /// A library whose cached catalog is `catalog` (an active, a paused or no enrolment), restored as the app restores it.
    static func library(_ catalog: PlansOverview) -> TrainLibrary {
        let store = TrainStore(inMemory: true)
        store.cache(exercises: MockTrain.exercises)
        store.cache(plans: MockTrain.plans)
        store.saveDocument(catalog, key: "train.plans")
        if catalog.active?.status == .active { store.saveDocument(MockTrain.planToday, key: "train.today") }
        return TrainLibrary.testing(store: store, remote: { MockTrainSource.shared }, restore: true)
    }

    static func plans(_ catalog: PlansOverview) -> some View {
        NavigationStack { PlansView().trainDestinations() }
            .environment(library(catalog))
    }

    static func planDetail(_ id: UUID) -> some View {
        NavigationStack { PlanDetailView(planID: id) }
            .environment(library(MockTrain.catalog()))
    }

    /// The summary as `…/complete` answered it: no local session needed.
    static func summary(completed: TrainSession) -> some View {
        SessionSummarySheet(summary: FinishSummary(sessionID: completed.id, completed: completed))
    }

    /// Finished offline: the local session waits for `…/complete`.
    static func pendingSummary() -> some View {
        let store = TrainStore(inMemory: true)
        let sync = TrainSyncService(store: store, remote: { MockTrainSource.shared }, owner: { TrainSyncService.demoOwner },
                                    monitorsNetwork: false)
        let s = MockTrain.liveSession(in: store, started: -52 * 60, checked: 17)
        s.status = .completed
        s.endedAt = .now
        s.pendingCompletion = true
        return SessionSummarySheet(summary: FinishSummary(sessionID: s.id, completed: nil))
            .environment(sync)
    }

    /// The banner's session lives in this store: a `LocalSession` dies with its store's context.
    private static let bannerStore = TrainStore(inMemory: true)

    /// The resume banner where Strain places it: Upper A, 23 minutes in, six sets done.
    static func banner() -> some View {
        let session = MockTrain.liveSession(in: bannerStore, checked: 6)
        return VStack(alignment: .leading, spacing: 12) {
            WorkoutInProgressBanner(session: session) {}
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
    }
}
