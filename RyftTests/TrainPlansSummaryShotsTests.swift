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
                          "plans-empty-mine", "plan-detail", "plan-detail-active", "plan-builder", "plan-builder-new"]

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
        case "plans-paused": return (AnyView(TrainShotFixtures.plans(MockTrain.catalog(paused: true))), 844, 844)
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
        UserDefaults.standard.removeObject(forKey: "train.pausedPlanID")
        let (view, height, ax3Height) = Self.view(name)
        for (size, typeSize, category, h) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large, height),
                                              ("ax3", .accessibility3, .accessibilityExtraLarge, ax3Height)] {
            // As the app's root sets it; without the scroll edge effect, a paged shot's later parts stay sharp at the top.
            try await HostedWindow.run(width: 390, height: h, typeSize: typeSize, category: category,
                                       view.toggleStyle(.ryft).shotsWithoutEdgeEffect()
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
    @ViewBuilder func shotsWithoutEdgeEffect() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}

/// The states the shots draw, each from its own store where it needs one.
@MainActor
enum TrainShotFixtures {
    /// A library whose cached catalog is `catalog` (an active, a paused or no enrolment), restored as the app restores it.
    static func library(_ catalog: PlansOverview) -> TrainLibrary {
        let store = TrainStore(inMemory: true)
        store.cache(exercises: MockTrain.exercises)
        store.cache(plans: MockTrain.plans)
        store.saveDocument(catalog, key: "train.plans")
        if catalog.active?.status == .active { store.saveDocument(MockTrain.planToday, key: "train.today") }
        return TrainLibrary(store: store, remote: { MockTrainSource.shared }, restore: true)
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
