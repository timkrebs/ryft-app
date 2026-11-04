import SwiftUI
import Testing
@testable import Ryft

/// The rest pill and its sheets as real views in a window (T3, design.md §2.7, §4c, §5.2): where the pill sits, when it shows,
/// what the sheet's −15 / +15 / Start / Skip / "Set as rest" do, and what VoiceOver is told. Taps go through
/// `accessibilityActivate`, the path VoiceOver's double tap takes. Synthetic values only.
@MainActor
@Suite("Rest pill, hosted", .serialized)
struct RestPillHostedTests {
    private func pill(_ w: HostedWindow) -> HostedWindow.Node? { w.node("Rest", exactly: true) }

    // MARK: where the pill sits

    struct SizeCase: Sendable, CustomTestStringConvertible {
        let width: CGFloat, height: CGFloat
        let typeSize: DynamicTypeSize
        let category: UIContentSizeCategory
        let pill: CGFloat
        var testDescription: String { "\(Int(width)) pt, \(typeSize)" }
    }

    nonisolated static let sizes = [
        SizeCase(width: 390, height: 844, typeSize: .large, category: .large, pill: 48),
        SizeCase(width: 320, height: 693, typeSize: .large, category: .large, pill: 48),
        SizeCase(width: 390, height: 844, typeSize: .accessibility2, category: .accessibilityLarge, pill: 48),
        SizeCase(width: 390, height: 844, typeSize: .accessibility3, category: .accessibilityExtraLarge, pill: 56),
    ]

    @Test("The pill row sits under the page, above the home indicator: 8 pt, the pill, 8 pt", arguments: sizes)
    func pillRowGeometry(_ s: SizeCase) async throws {
        #expect(RestPill.height(s.typeSize) == s.pill)
        #expect(RestPill.rowHeight(s.typeSize) == s.pill + 16)
        let c = FocusedPreview.controller(.restRunning)
        defer { c.stop() }
        try await HostedWindow.run(width: s.width, height: s.height, typeSize: s.typeSize, category: s.category,
                                   SessionView(controller: c)) { w in
            try await w.settle()
            let node = try #require(pill(w), "the running pill")
            let viewport = try #require(w.pageViewport())
            #expect(abs(node.frame.height - s.pill) < 0.5, "pill height \(node.frame.height)")
            #expect(abs(node.frame.minY - viewport.maxY - RestPill.rowPadding) < 0.5, "8 pt under the page")
            let homeIndicator = w.host.view.safeAreaInsets.bottom
            #expect(homeIndicator > 0)
            #expect(abs((s.height - homeIndicator) - node.frame.maxY - RestPill.rowPadding) < 0.5, "8 pt above the home indicator")
            #expect(abs(node.frame.midX - s.width / 2) < 0.5, "centred")
            #expect(node.frame.width >= 144 && node.frame.width <= s.width - 24, "running: at least 144 wide, inside the margins")
        }
    }

    @Test("Idle, the pill is an outline at least 112 wide")
    func idlePillWidth() async throws {
        let c = FocusedPreview.controller(.midSession)
        defer { c.stop() }
        try await HostedWindow.run(width: 320, height: 693, SessionView(controller: c)) { w in
            try await w.settle()
            let node = try #require(pill(w))
            #expect(node.frame.width >= 112 && node.frame.width < 144, "idle is narrower than running: \(node.frame.width)")
            #expect(node.value == "Not running. Starts at 2 minutes 30 seconds")
        }
    }

    // MARK: when it shows

    @Test("Under the keypad only a rest shows: idle hides, running and Rest over stay above the keys")
    func pillAndKeypad() async throws {
        for (scenario, value) in [(FocusedPreview.Scenario.midSession, nil), (.restRunning, "left, next"), (.restOver, "Rest over")] {
            let c = FocusedPreview.controller(scenario)
            defer { c.stop() }
            try await HostedWindow.run(width: 390, height: 844, SessionView(controller: c)) { w in
                try await w.settle()
                #expect(pill(w) != nil, "\(scenario): the pill shows without the keypad")
                c.edit(try #require(c.pageExercise).orderedSets[0], .kg)
                try await w.wait("the keypad") { w.node("Current value") != nil }
                try await w.settle()
                guard let value else {
                    #expect(pill(w) == nil, "idle: the keypad needs the room")
                    return
                }
                let node = try #require(pill(w), "\(scenario): the pill stays over the keypad")
                #expect(node.value?.contains(value) == true, "\(scenario): \(node.value ?? "nil")")
                let key = try #require(w.node("1", exactly: true), "the keypad's first key")
                #expect(node.frame.maxY + RestPill.rowPadding <= key.frame.minY + 0.5, "above the keys")
                let viewport = try #require(w.pageViewport())
                #expect(viewport.maxY <= node.frame.minY, "the page ends above the pill")
            }
        }
    }

    @Test("No exercises, or every set done: no pill", arguments: [FocusedPreview.Scenario.empty, .allDone])
    func noPill(_ scenario: FocusedPreview.Scenario) async throws {
        let c = FocusedPreview.controller(scenario)
        defer { c.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: c)) { w in
            try await w.settle()
            #expect(pill(w) == nil)
            #expect(c.restPillState == .hidden)
        }
    }

    // MARK: the strip beside the keypad (wiring of `hidesStrip`)

    struct StripCase: Sendable, CustomTestStringConvertible {
        let width: CGFloat, height: CGFloat
        let keypad: Bool
        let resting: Bool
        let strip: Bool
        var testDescription: String { "\(Int(width)) pt, keypad \(keypad), resting \(resting): strip \(strip)" }
    }

    nonisolated static let stripCases = [
        StripCase(width: 320, height: 693, keypad: false, resting: false, strip: true),
        StripCase(width: 320, height: 693, keypad: true, resting: false, strip: false),
        StripCase(width: 320, height: 693, keypad: true, resting: true, strip: false),
        StripCase(width: 390, height: 844, keypad: true, resting: false, strip: true),
        StripCase(width: 390, height: 844, keypad: true, resting: true, strip: true),
    ]

    @Test("The strip gives way to the keypad at 320 pt and only there", arguments: stripCases)
    func stripWiring(_ s: StripCase) async throws {
        let c = FocusedPreview.controller(s.resting ? .restRunning : .midSession)
        defer { c.stop() }
        try await HostedWindow.run(width: s.width, height: s.height, SessionView(controller: c)) { w in
            try await w.settle()
            #expect(w.node("Add exercise") != nil, "the strip shows to begin with")
            if s.keypad {
                c.edit(try #require(c.pageExercise).orderedSets[0], .kg)
                try await w.wait("the keypad") { w.node("Current value") != nil }
                try await w.settle()
            }
            #expect((w.node("Add exercise") != nil) == s.strip)
        }
    }

    // MARK: the idle sheet

    /// "Row" rests 2:30 (the rig's own default is not part of what is tested here).
    private func rig(rest: Int = 150) -> ReplaceRig {
        let r = ReplaceRig(sessionLayout: .focused)
        r.row.restSec = rest
        return r
    }

    private func value(_ w: HostedWindow) -> String? { w.node("Rest", exactly: true)?.value }

    @Test("−15 and +15 change the length Start begins, and nothing of the exercise")
    func idleSheetStepsLeaveTheExercise() async throws {
        let r = rig()
        let rest = r.row.restSec
        let updated = r.session.updatedAt
        try await HostedWindow.run(width: 390, height: 844, RestSheet(controller: r.controller, exercise: r.row)) { w in
            try await w.settle()
            #expect(value(w) == "2 minutes 30 seconds")
            #expect(w.node("Set as rest for this exercise") == nil, "nothing to save while the length is the exercise's")
            #expect(w.node("Start rest 2 minutes 30 seconds") != nil)

            #expect(w.node("Fifteen seconds more")?.activate() == true)
            try await w.wait("the longer length") { value(w) == "2 minutes 45 seconds" }
            #expect(w.node("Start rest 2 minutes 45 seconds") != nil, "Start names the new length")
            #expect(w.node("Set as rest for this exercise") != nil, "a changed length can be kept")
            #expect(r.row.restSec == rest, "the exercise keeps its rest")
            #expect(r.session.updatedAt == updated)
            #expect(!r.controller.rest.isRunning, "−15 and +15 start nothing")

            #expect(w.node("Fifteen seconds less")?.activate() == true)
            #expect(w.node("Fifteen seconds less")?.activate() == true)
            try await w.wait("the shorter length") { value(w) == "2 minutes 15 seconds" }
            #expect(r.row.restSec == rest)
        }
    }

    @Test("Start begins the shown length, once, and the exercise's rest stays")
    func startBeginsTheDraft() async throws {
        let r = rig()
        let rest = r.row.restSec
        try await HostedWindow.run(width: 390, height: 844, RestSheet(controller: r.controller, exercise: r.row)) { w in
            try await w.settle()
            w.node("Fifteen seconds more")?.activate()
            try await w.wait("the longer length") { value(w) == "2 minutes 45 seconds" }
            #expect(w.node("Start rest", exactly: false)?.activate() == true)
            #expect(r.controller.rest.isRunning)
            #expect(r.controller.rest.total == TimeInterval(rest + 15))
            #expect(r.row.restSec == rest)
            #expect(r.controller.setsChecked == 0)
            // The sheet is now the running one.
            try await w.wait("the running sheet") { w.node("Skip rest") != nil }
            #expect(w.node("Start rest") == nil)
            #expect(w.node("Set as rest for this exercise") == nil, "while running the length is the countdown's")
        }
    }

    @Test("“Set as rest for this exercise” is the only way the exercise changes, and then it hides")
    func saveChangesTheExercise() async throws {
        let r = rig()
        try await HostedWindow.run(width: 390, height: 844, RestSheet(controller: r.controller, exercise: r.row)) { w in
            try await w.settle()
            w.node("Fifteen seconds more")?.activate()
            try await w.wait("the save button") { w.node("Set as rest for this exercise") != nil }
            #expect(w.node("Set as rest for this exercise")?.activate() == true)
            #expect(r.row.restSec == 165)
            try await w.wait("it hides: the length is the exercise's now") { w.node("Set as rest for this exercise") == nil }
            #expect(!r.controller.rest.isRunning, "saving starts nothing")
            // Back to the old length: differs again.
            w.node("Fifteen seconds less")?.activate()
            try await w.wait("the save button") { w.node("Set as rest for this exercise") != nil }
        }
    }

    struct BoundCase: Sendable, CustomTestStringConvertible {
        let start: Int
        let disabled: String
        let enabled: String
        var testDescription: String { "from \(start) s, \(disabled) is off" }
    }

    nonisolated static let bounds = [
        BoundCase(start: 15, disabled: "Fifteen seconds less", enabled: "Fifteen seconds more"),
        BoundCase(start: 900, disabled: "Fifteen seconds more", enabled: "Fifteen seconds less"),
    ]

    @Test("−15 is off at 0:15 and +15 at 15:00", arguments: bounds)
    func sheetBounds(_ b: BoundCase) async throws {
        let r = rig()
        try await HostedWindow.run(width: 390, height: 844, RestSheet(controller: r.controller, exercise: r.row, seconds: b.start)) { w in
            try await w.settle()
            let off = try #require(w.node(b.disabled))
            #expect(!off.isEnabled, "\(b.disabled) is dimmed at \(b.start) s")
            #expect(w.node(b.enabled)?.isEnabled == true)
            off.activate()
            try await w.settle()
            #expect(w.node("Start rest")?.label.contains(RestSpeech.duration(b.start)) == true, "the length didn't move")
        }
    }

    @Test("An exercise that rests 0:00 can't start; +15 gets it going")
    func zeroRestCannotStart() async throws {
        let r = rig(rest: 0)
        try await HostedWindow.run(width: 390, height: 844, RestSheet(controller: r.controller, exercise: r.row)) { w in
            try await w.settle()
            #expect(w.node("Start rest")?.isEnabled == false)
            #expect(w.node("Fifteen seconds less")?.isEnabled == false)
            w.node("Fifteen seconds more")?.activate()
            try await w.wait("0:15") { value(w) == "15 seconds" }
            #expect(w.node("Start rest")?.isEnabled == true)
            w.node("Start rest")?.activate()
            #expect(r.controller.rest.total == 15)
            #expect(r.row.restSec == 0)
        }
    }

    // MARK: the running sheet

    @Test("Running, −15 and +15 move the countdown, not the exercise; Skip ends it")
    func runningSheetAdjustsAndSkips() async throws {
        let r = rig()
        let rest = r.row.restSec
        r.controller.startRest(for: r.row, seconds: 120)
        try await HostedWindow.run(width: 390, height: 844, RestSheet(controller: r.controller, exercise: r.row)) { w in
            try await w.settle()
            #expect(w.node("Skip rest") != nil)
            #expect(w.node("Start rest") == nil, "running: Skip, not Start")
            #expect(w.node("Fifteen seconds less")?.isEnabled == true)
            let before = r.controller.rest.remaining(at: .now)
            w.node("Fifteen seconds more")?.activate()
            let after = r.controller.rest.remaining(at: .now)
            #expect(abs((after - before) - 15) < 1, "+15 added to the countdown: \(after - before)")
            #expect(r.row.restSec == rest)
            w.node("Fifteen seconds less")?.activate()
            #expect(abs(r.controller.rest.remaining(at: .now) - before) < 1, "−15 took it back")
            #expect(r.controller.rest.isRunning)

            #expect(w.node("Skip rest")?.activate() == true)
            #expect(r.controller.rest.phase == .idle, "Skip ends the rest")
            #expect(r.session.restEndsAt == nil)
            #expect(r.controller.restsEnded == 0, "a skip is not a rest that ended")
            try await w.wait("the idle sheet") { w.node("Start rest") != nil }
            #expect(w.node("Skip rest") == nil)
        }
    }

    @Test("A −15 that runs the rest out turns the sheet into the idle one")
    func runningOutTurnsIdle() async throws {
        let r = rig()
        r.controller.startRest(for: r.row, seconds: 10)
        try await HostedWindow.run(width: 390, height: 844, RestSheet(controller: r.controller, exercise: r.row)) { w in
            try await w.settle()
            #expect(w.node("Skip rest") != nil)
            w.node("Fifteen seconds less")?.activate()
            #expect(r.controller.rest.phase == .finished)
            #expect(r.controller.restsEnded == 1)
            try await w.wait("the idle sheet") { w.node("Start rest") != nil }
            #expect(w.node("Skip rest") == nil, "nothing left to skip")
            #expect(value(w) == RestSpeech.duration(r.row.restSec), "the idle value is the exercise's rest")
            #expect(w.node("Fifteen seconds less")?.isEnabled == true)
            #expect(r.row.restSec == 150)
        }
    }

    // MARK: the Rest chip's choices

    @Test("The choices set the exercise's rest in one tap and start nothing")
    func choicesSetTheExercise() async throws {
        let r = rig()
        try await HostedWindow.run(width: 390, height: 844, RestChoicesSheet(controller: r.controller, exercise: r.row)) { w in
            try await w.settle()
            let labels = RestChoices.presets.map(RestSpeech.duration)
            #expect(labels == ["1 minute", "1 minute 30 seconds", "2 minutes", "2 minutes 30 seconds", "3 minutes", "4 minutes", "5 minutes"])
            for label in labels { #expect(w.node(label, exactly: true) != nil, "a row for \(label)") }
            #expect(w.node("2 minutes 30 seconds", exactly: true)?.isSelected == true, "the current rest is marked")
            #expect(w.node("1 minute", exactly: true)?.isSelected == false)
            #expect(w.node("Start rest") == nil, "the chip's sheet has no Start")
            #expect(w.node("Fifteen seconds more") == nil)

            #expect(w.node("1 minute", exactly: true)?.activate() == true)
            #expect(r.row.restSec == 60)
            #expect(!r.controller.rest.isRunning)
            try await w.wait("the mark moves") { w.node("1 minute", exactly: true)?.isSelected == true }
        }
    }

    // MARK: VoiceOver

    @Test("The running pill is one adjustable button with a Skip action; the idle one is neither")
    func pillAccessibility() async throws {
        let running = FocusedPreview.controller(.restRunning)
        defer { running.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: running)) { w in
            try await w.settle()
            let node = try #require(pill(w))
            #expect(node.value == "1 minute 55 seconds left, next Barbell row set 1 of 4", "\(node.value ?? "nil")")
            #expect(node.isAdjustable)
            #expect(node.actionNames == ["Skip rest"])
            let before = running.rest.remaining(at: .now)
            node.increment()
            #expect(abs(running.rest.remaining(at: .now) - before - 15) < 1, "up is +15 s")
            node.decrement()
            node.decrement()
            #expect(abs(running.rest.remaining(at: .now) - before + 15) < 1, "down is −15 s")
            #expect(node.perform(action: "Skip rest"))
            #expect(running.rest.phase == .idle)
            try await w.wait("the idle pill") { pill(w)?.value?.hasPrefix("Not running") == true }
            let idle = try #require(pill(w))
            #expect(!idle.isAdjustable, "an idle pill doesn't say it can be adjusted")
            #expect(idle.actionNames.isEmpty)
        }
    }

    // MARK: Focused or List

    @Test("Focused shows the pill and not the bar; List shows the bar and never the pill")
    func layoutsKeepToTheirOwnTimer() async throws {
        let focused = FocusedPreview.controller(.restRunning)
        defer { focused.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: focused)) { w in
            try await w.settle()
            #expect(pill(w) != nil)
            #expect(w.node("Rest timer") == nil, "RestBar is not in the Focused layout")
        }

        let list = rig()
        list.controller.startRest(for: list.row, seconds: 120)
        let listController = SessionController(session: list.session, sync: list.sync, liveActivity: nil, clock: list.clock,
                                               library: list.library, layout: .list)
        defer { listController.stop() }
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: listController)) { w in
            try await w.settle()
            #expect(w.node("Rest timer") != nil, "List keeps its RestBar")
            #expect(w.node("Skip rest") != nil)
            #expect(pill(w) == nil, "no pill in List")
            #expect(w.node("Rest over") == nil)

            listController.adjustRest(by: -RestTimer.maxRest)
            try await w.wait("List's banner") { w.node("Rest over") != nil }
            #expect(pill(w) == nil)
            list.clock.advance(by: SessionController.restOverHold * 10)
            try await w.settle()
            #expect(w.node("Rest over") != nil, "List's banner stays until it is dismissed")
        }
    }
}
