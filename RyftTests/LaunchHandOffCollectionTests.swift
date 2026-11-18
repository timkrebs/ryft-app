import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// CR3: Today's header lock-up reports its frames to the launch only while the launch is on screen. Before, `LaunchHost`
/// handed every root a registrar for the process's lifetime, and the target measured itself on every scroll of Today.
/// Hosted: `LaunchHost` over a scrolling page with the lock-up, a counter between them; the page scrolls while the
/// launch plays (the lock-up reports) and after it is done (nothing is reported, the targets stay as they landed).
@MainActor
@Suite(.serialized) struct LaunchHandOffCollectionTests {
    @MainActor
    final class Counter {
        var reports = 0
    }

    /// Counts what reaches the registrar `LaunchHost` provides, and passes it on; passes a non-collecting one through.
    private struct Counting<Content: View>: View {
        let counter: Counter
        @ViewBuilder var content: Content
        @Environment(\.launchHandOffRegistrar) private var outer

        var body: some View {
            content.environment(\.launchHandOffRegistrar, outer.isCollecting ? LaunchHandOffRegistrar { [outer, counter] role, frame in
                counter.reports += 1
                outer(role, frame)
            } : outer)
        }
    }

    private let created = Date(timeIntervalSince1970: 1_792_600_000)

    private func page(_ model: LaunchSequenceModel, counter: Counter) -> some View {
        LaunchHost(model: model) {
            Counting(counter: counter) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        WordmarkLockup(handOff: true)
                            .padding(.leading, 20)
                            .padding(.top, 7)
                        Color.clear.frame(height: 3_000)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .environment(\.scenePhase, .active)
    }

    private func scroll(_ w: HostedWindow, to y: CGFloat) async throws {
        let scrollView = try #require(w.pageScrollView(), "the page's scroll view")
        scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        scrollView.layoutIfNeeded()
        try await w.settle()
    }

    @Test func afterTheLaunchScrollingReportsNothing() async throws {
        let clock = TestClock(now: created)
        let model = LaunchSequenceModel(decision: .play(.full), clock: clock, signposts: false)
        let counter = Counter()
        try await HostedWindow.run(width: 390, height: 844, page(model, counter: counter)) { w in
            try await w.wait("the lock-up registered while the launch plays") {
                model.phase == .playing && model.targets[.mark] != nil && counter.reports > 0
            }
            // While the launch is on screen the lock-up follows the page.
            let before = counter.reports
            try await scroll(w, to: 40)
            #expect(counter.reports > before, "a scroll during the launch reports the new frame")

            clock.advance(by: .seconds(LaunchFrame.duration + 1))
            try await w.wait("done and off screen") { model.phase == .done && !model.isOnScreen }
            try await w.settle()
            let landed = model.targets
            let after = counter.reports
            for y in [CGFloat(0), 120, 300, 10] {
                try await scroll(w, to: y)
            }
            #expect(counter.reports == after, "nothing reported after the launch: \(counter.reports - after) reports")
            #expect(model.targets == landed, "the targets stay as they were")
        }
    }
}
