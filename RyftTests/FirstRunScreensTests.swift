import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The first run's other screens (docs/work/2026-11-23-first-run/ui.md §5–§7): Today during the first import, tracker setup's
/// lead, the splash's captions.
@MainActor
@Suite("First run: Today's first import, tracker setup, the splash", .serialized)
struct FirstRunScreensTests {
    // MARK: G5, Today while the first sync runs

    @Test("The empty orbit holds the gauge's place below AX3; from AX3 the card is the page")
    func orbitBelowAX3() {
        #expect(TodayView.showsImportOrbit(.large) && TodayView.showsImportOrbit(.xxxLarge)
            && TodayView.showsImportOrbit(.accessibility2))
        #expect(!TodayView.showsImportOrbit(.accessibility3) && !TodayView.showsImportOrbit(.accessibility5))
        #expect(!TodayGaugeEntrance.hasSomethingToShow(TodayView.importOrbit), "a placeholder: the gauge assembles over it")
    }

    @Test("Hosted: the import card sits under the orbit's 260 pt (hidden from VoiceOver), or right under the status at AX3",
          arguments: [false, true])
    func importCardUnderTheOrbit(_ ax3: Bool) async throws {
        let size: DynamicTypeSize = ax3 ? .accessibility3 : .large
        let category: UIContentSizeCategory = ax3 ? .accessibilityExtraLarge : .large
        let today = TodayView().previewEnvironment(.preview(scenario: .importing)).environment(\.locale, Locale(identifier: "en_US"))
        try await HostedWindow.run(width: 390, height: 2_600, typeSize: size, category: category, today) { w in
            try await w.wait("the import card") { w.node("Setting up RYFT") != nil }
            try await w.settle()
            let nodes = w.nodes()
            let index = try #require(nodes.firstIndex { $0.label.hasPrefix("Setting up RYFT") })
            let above = try #require(index > 0 ? nodes[index - 1] : nil)
            let gap = nodes[index].frame.minY - above.frame.maxY
            #expect(!nodes.contains { $0.identifier == "today.importGauge" }, "the orbit is never read")
            if TodayView.showsImportOrbit(size) {
                #expect(gap >= TodayLayout.heroFrame, "the orbit's place above the card: \(gap) under '\(above.label)'")
            } else {
                #expect(gap < TodayLayout.heroFrame, "no orbit at \(size): \(gap)")
            }
            #expect(w.node("Allow") == nil, "the card asks nothing")
        }
    }

    // MARK: G6, tracker setup

    @Test("Tracker setup's lead says the sync runs only when it does")
    func trackerSetupLead() {
        let runs = String(localized: TrackerSetupLead.choose(syncRuns: true))
        let waits = String(localized: TrackerSetupLead.choose(syncRuns: false))
        #expect(runs.hasPrefix("Your first sync is already running."))
        #expect(!waits.contains("already running") && waits.contains("reaches Apple Health"))
    }

    @Test("The first sync runs once consent is in force and Apple Health was asked; not before either")
    func firstSyncRuns() async {
        let health = MockHealthStore()
        health.access = .notAsked
        let state = AppState(env: .test(health: health, flags: [.devicesSetup: true]))
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        #expect(!(await model.firstSyncRuns()), "nothing known of the account yet: consent holds the upload")
        await model.check()
        #expect(model.uploadGate(for: .healthKit) == nil)
        #expect(!(await model.firstSyncRuns()), "Apple Health not asked (its Not now)")
        health.access = .asked
        #expect(await model.firstSyncRuns())
    }

    // MARK: G8, the splash

    @Test("The splash's captions: restoring after 3 s; the first run after 1 s, and slow from 5 s; never a count")
    func splashCaptions() {
        #expect(SplashCaption.at(elapsed: .milliseconds(2_900), firstRun: false) == .none)
        #expect(SplashCaption.at(elapsed: .seconds(3), firstRun: false) == .checking)
        #expect(SplashCaption.at(elapsed: .seconds(9), firstRun: false) == .checking, "restoring never says slow")
        #expect(SplashCaption.at(elapsed: .milliseconds(900), firstRun: true) == .none)
        #expect(SplashCaption.at(elapsed: .seconds(1), firstRun: true) == .checking)
        #expect(SplashCaption.at(elapsed: .milliseconds(4_900), firstRun: true) == .checking)
        #expect(SplashCaption.at(elapsed: .seconds(5), firstRun: true) == .slow)
        #expect(SplashCaption.none.text == nil)
        for caption in [SplashCaption.checking, .slow] {
            let text = caption.text ?? ""
            #expect(!text.isEmpty && text.rangeOfCharacter(from: .decimalDigits) == nil, "no count: \(text)")
        }
        // The schedule is the same rule, step by step.
        for firstRun in [false, true] {
            for step in SplashCaption.schedule(firstRun: firstRun) {
                #expect(SplashCaption.at(elapsed: step.at, firstRun: firstRun) == step.caption)
            }
        }
    }

    @Test("Hosted: the first run's splash says it is checking after 1 s and that it is slow at 5 s; the mark never moves")
    func firstRunSplash() async throws {
        let clock = TestClock()
        let env = AppEnvironment.test(clock: clock)
        let checking = String(localized: "Checking your account…")
        let slow = try #require(SplashCaption.slow.text)
        try await HostedWindow.run(width: 390, height: 844, SplashView(firstRun: true).environment(\.appEnvironment, env)) { w in
            try await w.wait("the wait") { clock.pendingSleeps == 1 }
            try await w.settle()
            let mark = try #require(w.nodes().first { $0.identifier == "splash.mark" })
            #expect(w.node(checking) == nil)
            clock.advance(by: .seconds(1))
            try await w.wait("checking") { w.node(checking) != nil }
            try await w.wait("the next wait") { clock.pendingSleeps == 1 }
            clock.advance(by: .seconds(3))
            try await w.settle()
            #expect(w.node(slow) == nil, "not before 5 s")
            clock.advance(by: .seconds(1))
            try await w.wait("slow") { w.node(slow) != nil }
            try await w.settle()
            #expect(w.node(checking) == nil, "one caption at a time")
            let after = try #require(w.nodes().first { $0.identifier == "splash.mark" })
            #expect(after.frame == mark.frame, "the mark never moves")
        }
    }

    // MARK: the first run's actions (ui.md §3 row 7, §4.2 row 5, §6 row 5)

    @Test("From AX1 a step's actions end the page; below it they are pinned")
    func actionsEndThePageFromAX1() {
        #expect(!OnboardingSpec.actionsEndPage(at: .large) && !OnboardingSpec.actionsEndPage(at: .xxxLarge))
        #expect(OnboardingSpec.actionsEndPage(at: .accessibility1) && OnboardingSpec.actionsEndPage(at: .accessibility5))
    }

    @Test("Hosted: the primer's whole caption shows above the pinned bar; from AX1 Continue and Not now follow it on the page",
          arguments: [false, true])
    func primerActions(_ ax1: Bool) async throws {
        let env = AppEnvironment.preview()
        let primer = NotificationPrimerStep(model: NotificationPrimerModel(push: PushRegistrar(env: env), analytics: env.analytics),
                                            example: .morningScore, progress: FirstRunProgress(step: 6, count: 7))
            .environment(\.appEnvironment, env)
            .environment(\.locale, Locale(identifier: "en_US"))
        let caption = NotificationPrimerExample.caption
        try await HostedWindow.run(width: 390, height: 844, typeSize: ax1 ? .accessibility1 : .large,
                                   category: ax1 ? .accessibilityMedium : .large, primer) { w in
            try await w.wait("Continue") { w.nodes().contains { $0.identifier == "notifications.continue" } }
            try await w.settle()
            let scroll = try #require(w.pageScrollView())
            let end = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top, end)), animated: false)
            try await w.settle()
            let nodes = w.nodes()
            let text = try #require(nodes.firstIndex { $0.label == caption }, "the caption, whole, as one element")
            let pill = try #require(nodes.firstIndex { $0.identifier == "notifications.continue" })
            let later = try #require(nodes.firstIndex { $0.identifier == "notifications.notNow" })
            #expect(text < pill && pill < later, "read in page order: the caption, Continue, Not now")
            let bottom = nodes[text].frame.maxY, top = nodes[pill].frame.minY
            if ax1 {
                #expect(top - bottom >= OnboardingSpec.primaryGap - 1, "Continue \(top - bottom) pt under the caption")
                #expect(nodes[later].frame.maxY <= w.window.bounds.maxY, "Not now on screen at the page's end")
            } else {
                // The bar's rule sits `topPadding` above the pill: the caption's last line ends above it.
                #expect(bottom <= top - PinnedBarSpec.topPadding + 0.5, "the caption ends at \(bottom), the bar starts at \(top - 12)")
                #expect(nodes[later].frame.maxY >= w.window.bounds.maxY - 120, "pinned at the window's foot")
            }
        }
    }
}
