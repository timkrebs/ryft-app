import SwiftUI
import Testing
import UIKit
@testable import Ryft

// Nocturne gate G3 (docs/work/2026-11-20-nocturne-gate/design.md §2.5 D5, §2.9 D9 rows 4–6, test hooks §5.3): the keyboard's
// Done joins Send in Report a problem's pinned bar; ruler labels at the accessibility sizes keep their ends and drop the
// rest; About you's wheel is a menu row from AX1; the journal's day chips stop growing at AX3 and keep 10 inside.

@MainActor
struct NocturneGateAXTests {
    @Test("From AX1 a ruler tries all its labels, then the two ends, then the first alone; never a subset of the middle")
    func accessibilityLabelSets() {
        let today = ["0", "low", "moderate", "high", "100"]
        #expect(RulerScale.accessibilityLabelSets(today) == [today, ["0", "100"], ["0"]])
        #expect(RulerScale.accessibilityLabelSets(["0 h", "need 8:18", "10 h"]) == [["0 h", "need 8:18", "10 h"], ["0 h", "10 h"], ["0 h"]])
        #expect(RulerScale.accessibilityLabelSets(["0", "21"]) == [["0", "21"], ["0"]], "two labels are already the ends")
        #expect(RulerScale.accessibilityLabelSets(["0"]) == [["0"]])
        #expect(RulerScale.accessibilityLabelSets([]).isEmpty)
    }

    @Test("A day chip keeps 6 at the sides below AX1 and 10 on every side from AX1")
    func journalChipInsets() {
        for size in [DynamicTypeSize.large, .xxxLarge] {
            #expect(JournalLayout.chipInsets(for: size) == EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6), "\(size)")
        }
        for size in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
            #expect(JournalLayout.chipInsets(for: size) == EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10), "\(size)")
        }
        #expect(JournalLayout.chipMaxTypeSize == .accessibility3)
    }
}

@MainActor
@Suite(.serialized) struct NocturneGateAXHostedTests {
    struct SizeCase: Sendable, CustomStringConvertible {
        let size: DynamicTypeSize
        let category: UIContentSizeCategory
        var description: String { "\(size)" }
    }

    nonisolated static let standard = SizeCase(size: .large, category: .large)
    nonisolated static let ax3 = SizeCase(size: .accessibility3, category: .accessibilityExtraLarge)
    nonisolated static let ax5 = SizeCase(size: .accessibility5, category: .accessibilityExtraExtraExtraLarge)

    /// iPhone 17 Pro: 402 × 874, the home indicator's 34 at the bottom and (`deviceTop`) the status bar's 62 at the top.
    private nonisolated static let width: CGFloat = 402, height: CGFloat = 874, bottomInset: CGFloat = 34
    private nonisolated static let deviceTop: CGFloat = 62
    private nonisolated static let english = Locale(identifier: "en_US")

    private func run(_ s: SizeCase, height: CGFloat = Self.height, _ content: some View,
                     body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: Self.width, height: height, bottomInset: Self.bottomInset, typeSize: s.size,
                                   category: s.category, content, body: body)
    }

    private func node(_ w: HostedWindow, id: String) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.identifier == id }, "'\(id)' in \(w.nodes().map { $0.identifier ?? $0.label })")
    }

    private func has(_ w: HostedWindow, id: String) -> Bool { w.nodes().contains { $0.identifier == id } }

    /// Every view of type `T` under `view`.
    private static func views<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
    }

    // MARK: D9 row 4: ruler labels

    /// The three screens' label sets: Today's readiness (with its band), Sleep's need, Strain's moderate range.
    private static var rulerLabelSets: [(name: String, labels: [String])] {
        [("today", ["0", "low", "moderate", "high", "100"]),
         ("sleep", SleepRuler(totalMin: 468, needMin: 498, locale: english).labels),
         ("strain", StrainHero.rulerLabels)]
    }

    @Test("Rulers at AX3 and AX5: labels on one line, 16 or more apart, the first at the ruler's start and the last at its end, never joined",
          arguments: [ax3, ax5])
    func rulerLabels(_ s: SizeCase) async throws {
        // The ruler's width on Today, Sleep and Strain: the window less the screen padding.
        let rulerWidth = Self.width - 2 * Theme.Metrics.screenPadding
        for (name, labels) in Self.rulerLabelSets {
            let frames = TwoUpFrames()
            let row = RulerLabels(labels: labels)
                .font(.ryft(.axis))
                .frame(width: rulerWidth, alignment: .leading)
                .reportFrame("ruler", to: frames)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 60)
            try await run(s, height: 400, row) { w in
                try await w.wait("the labels") { frames.byName["ruler"] != nil && !w.nodes().isEmpty }
                try await w.settle()
                let ruler = try #require(frames.byName["ruler"])
                let nodes = w.nodes().sorted { $0.frame.minX < $1.frame.minX }
                let shown = nodes.map(\.label)
                let where_ = "\(name) at \(s): \(nodes.map { "'\($0.label)' \($0.frame)" }) in \(ruler)"
                #expect(shown.count >= 2 && shown.first == labels.first && shown.last == labels.last, "both ends: \(where_)")
                #expect(shown == labels || shown == [labels[0], labels[labels.count - 1]], "all, or the ends alone: \(where_)")
                #expect(!shown.contains { $0.contains("·") }, "nothing joined: \(where_)")
                if let first = nodes.first, let last = nodes.last {
                    #expect(abs(first.frame.minX - ruler.minX) < 0.5, "the first under the first tick: \(where_)")
                    #expect(abs(last.frame.maxX - ruler.maxX) < 0.5, "the last under the last tick: \(where_)")
                }
                for node in nodes {
                    #expect(node.frame.minX >= ruler.minX - 0.5 && node.frame.maxX <= ruler.maxX + 0.5, "inside the ruler: \(where_)")
                    #expect(abs(node.frame.minY - (nodes.first?.frame.minY ?? 0)) < 0.5, "one line: \(where_)")
                }
                for (left, right) in zip(nodes, nodes.dropFirst()) {
                    #expect(right.frame.minX - left.frame.maxX >= RulerScale.labelMinGap - 0.5,
                            "'\(left.label)' and '\(right.label)' 16 or more apart: \(where_)")
                }
                if s.size == .accessibility3 {
                    // Today's five don't fit at AX3 ("0 · low · moderate · high" filled the line): its ends only. Sleep's and
                    // Strain's three do.
                    #expect(shown == (name == "today" ? ["0", "100"] : labels), "at AX3: \(where_)")
                }
            }
        }
    }

    // MARK: D9 row 5: About you

    /// About you at `s` with the phone's status bar: the wheel's absence, the menu row, and the pinned bar's top.
    private func aboutYou(_ s: SizeCase, body: (HostedWindow, _ barTop: () throws -> CGFloat) async throws -> Void) async throws {
        try await run(s, OnboardingStepPreview(step: .aboutYou)) { w in
            w.host.additionalSafeAreaInsets.top = Self.deviceTop
            try await w.wait("About you") { has(w, id: "aboutYou.save") }
            try await w.settle()
            #expect(Self.views(UIPickerView.self, in: w.window).isEmpty, "no wheel at \(s)")
            let row = try node(w, id: "aboutYou.year")
            #expect(row.traits.contains(.button), "a button: \(row.traits)")
            #expect(row.label == "Birth year" && row.value == "Choose", "'\(row.label)' '\(row.value ?? "")'")
            #expect(row.frame.height >= 56, "56 or more high: \(row.frame)")
            try await body(w) { try node(w, id: "aboutYou.save").frame.minY - PinnedBarSpec.topPadding }
        }
    }

    /// Scrolls the page to its end.
    private func scrollToEnd(_ w: HostedWindow) async throws {
        let scroll = try #require(w.pageScrollView(), "the page's scroll view")
        let inset = scroll.adjustedContentInset
        let end = max(-inset.top, scroll.contentSize.height + inset.bottom - scroll.bounds.height)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: end), animated: false)
        try await w.settle()
    }

    @Test("About you at AX3: no wheel; Birth year is a menu row that starts above the pinned bar at rest, wholly above it scrolled")
    func aboutYouMenuRowAtAX3() async throws {
        try await aboutYou(Self.ax3) { w, barTop in
            // With the status bar and the home indicator the lead's 8 lines leave the row's top above the bar, not all of
            // it (the draft had neither inset); a short scroll brings it whole.
            let atRest = try node(w, id: "aboutYou.year").frame, barAtRest = try barTop()
            #expect(atRest.minY < barAtRest - 20, "the row shows above the bar without scrolling: \(atRest), bar at \(barAtRest)")
            try await scrollToEnd(w)
            let row = try node(w, id: "aboutYou.year").frame, bar = try barTop()
            #expect(row.minY >= Self.deviceTop && row.maxY < bar, "above the bar: \(row), bar at \(bar)")
            let save = try node(w, id: "aboutYou.save")
            #expect(!save.isEnabled, "Continue waits for a year")
        }
    }

    @Test("About you at AX5: no wheel; Birth year is a menu row above the pinned bar once the page is scrolled to it")
    func aboutYouMenuRowAtAX5() async throws {
        try await aboutYou(Self.ax5) { w, barTop in
            // At AX5 the lead alone is taller than the screen: the row is under the fold until the page scrolls.
            try await scrollToEnd(w)
            let row = try node(w, id: "aboutYou.year").frame, bar = try barTop()
            #expect(row.minY >= Self.deviceTop && row.maxY < bar, "above the bar: \(row), bar at \(bar)")
        }
    }

    @Test("About you at the default size keeps its wheel")
    func aboutYouWheelAtTheDefaultSize() async throws {
        try await run(Self.standard, OnboardingStepPreview(step: .aboutYou)) { w in
            try await w.wait("About you") { has(w, id: "aboutYou.save") }
            try await w.settle()
            #expect(Self.views(UIPickerView.self, in: w.window).count == 1, "the wheel")
            #expect(!(w.nodes().first { $0.identifier == "aboutYou.year" }?.traits.contains(.button) ?? false), "no menu row")
        }
    }

    // MARK: D9 row 6: the journal strip

    /// The sheet with `selected` the selected day, in US English.
    private func journal(selecting selected: String) -> some View {
        var content = MockJournalStates.content(.answered)
        content.selected = selected
        return JournalSheetBody(content: content)
            .toggleStyle(.ryft)
            .environment(\.locale, Self.english)
    }

    /// The day chips, left to right.
    private func chips(_ w: HostedWindow) -> [HostedWindow.Node] {
        w.nodes().filter { $0.identifier?.hasPrefix("journal.day.") == true }.sorted { $0.frame.minX < $1.frame.minX }
    }

    @Test("Journal strip at AX5: chips of 44 or more, each day's words 8 or more inside its chip, capped at AX3; the full date")
    func journalStripAtAX5() async throws {
        let day = MockJournalStates.day(1)
        var capped: CGSize?
        try await run(Self.ax3, journal(selecting: day)) { w in
            try await w.wait("the strip") { !chips(w).isEmpty }
            try await w.settle()
            capped = try #require(chips(w).first).frame.size
        }
        try await run(Self.ax5, journal(selecting: day)) { w in
            try await w.wait("the strip") { !chips(w).isEmpty }
            try await w.settle()
            let all = chips(w)
            #expect(all.count == JournalSheetModel.daysBack)
            for chip in all {
                #expect(chip.frame.width >= Theme.Metrics.minHitTarget && chip.frame.height >= Theme.Metrics.minHitTarget,
                        "\(chip.identifier ?? "") \(chip.frame)")
            }
            let first = try #require(all.first)
            let date = try #require(DayFormat.date(from: day))
            #expect(first.label == date.formatted(Date.FormatStyle(locale: Self.english).weekday(.wide).month(.wide).day()),
                    "VoiceOver: the full date, '\(first.label)'")
            #expect(first.isSelected)
            if let capped {
                #expect(abs(first.frame.height - capped.height) < 0.5 && abs(first.frame.width - capped.width) < 0.5,
                        "the words stop growing at AX3: \(first.frame.size) at AX5, \(capped) at AX3")
            }
            // The words' ink inside each chip that's wholly on screen and not selected (ink on `surface`; the ground's
            // corners outside the rounded chip are dark too, so only the words are bright).
            let pixels = try WindowPixels(w, scale: 3)
            let column = Theme.Metrics.screenPadding...(Self.width - Theme.Metrics.screenPadding)
            let shown = all.filter { !$0.isSelected && column.contains($0.frame.minX) && column.contains($0.frame.maxX) }
            #expect(shown.count >= 2, "yesterday and more in view: \(all.map(\.frame))")
            for chip in shown {
                let ink = try #require(pixels.box(in: chip.frame) { ($0.r + $0.g + $0.b) / 3 > 0.45 }, "the words of \(chip.label)")
                let gaps = [ink.minX - chip.frame.minX, chip.frame.maxX - ink.maxX, ink.minY - chip.frame.minY, chip.frame.maxY - ink.maxY]
                #expect(gaps.allSatisfy { $0 >= 8 }, "\(chip.label): the words \(ink) in \(chip.frame), gaps \(gaps)")
            }
        }
    }

    @Test("Journal strip at AX5: an older selected day is in view when the sheet appears")
    func journalStripSelectedInView() async throws {
        let day = MockJournalStates.day(9)
        try await run(Self.ax5, journal(selecting: day)) { w in
            try await w.wait("the strip") { !chips(w).isEmpty }
            try await w.settle()
            let selected = try node(w, id: "journal.day.\(day)")
            #expect(selected.isSelected)
            #expect(selected.frame.minX >= Theme.Metrics.screenPadding - 0.5 && selected.frame.maxX <= Self.width - Theme.Metrics.screenPadding + 0.5,
                    "in view: \(selected.frame)")
        }
    }

    // MARK: D5: Report a problem's bar while the message has focus

    // A hosted window shows no software keyboard (its frame stays `.zero`), so these checks are the bar's layout while the
    // message has focus; that Done and Send ride above a real keyboard is `RyftUITests/NocturneGateKeyboardUITests`' proof.

    /// The message's text view (a vertical `TextField` is a `UITextView`).
    private static func messageField(_ w: HostedWindow) throws -> UITextView {
        try #require(views(UITextView.self, in: w.window).first, "the message's text view")
    }

    private func reportPage() -> AnyView {
        SubpageShotScreen.report { $0.stage(message: SubpageShotScreen.message, category: .data) }
    }

    @Test("D5: with the message focused the bar is Done · Send, equal and 12 apart, inside the window; Done ends the focus")
    func reportBarWhileTyping() async throws {
        try await run(Self.standard, reportPage()) { w in
            try await w.wait("the form") { has(w, id: "report.send") }
            try await w.settle()
            #expect(!has(w, id: "report.done"), "no Done without focus")
            let alone = try node(w, id: "report.send").frame
            let field = try Self.messageField(w)
            w.window.makeKey()
            #expect(field.becomeFirstResponder(), "the message takes focus")
            try await w.wait("Done in the bar") { has(w, id: "report.done") }
            try await w.settle()
            let send = try node(w, id: "report.send"), done = try node(w, id: "report.done")
            #expect(done.frame.maxX <= send.frame.minX, "Done leading, Send trailing: \(done.frame) \(send.frame)")
            #expect(abs(send.frame.minX - done.frame.maxX - ReportProblemLayout.barButtonGap) < 0.5, "12 apart")
            #expect(abs(send.frame.width - done.frame.width) < 0.5, "equal: \(done.frame.width) \(send.frame.width)")
            #expect(abs(done.frame.minY - send.frame.minY) < 0.5, "one row")
            #expect(abs(done.frame.minX - alone.minX) < 0.5 && abs(send.frame.maxX - alone.maxX) < 0.5, "the row spans Send's width")
            #expect(done.isEnabled && send.isEnabled)
            #expect(w.window.bounds.contains(send.frame) && w.window.bounds.contains(done.frame), "inside the window: \(send.frame) \(done.frame)")
            #expect(done.label == "Done" && !done.traits.contains(.notEnabled))
            #expect(done.activate(), "Done is a button")
            try await w.wait("the focus ended") { !field.isFirstResponder }
            try await w.wait("Send alone") { !has(w, id: "report.done") }
            try await w.settle()
            #expect(try node(w, id: "report.send").frame.width > send.frame.width, "Send full width again")
            #expect(field.text == SubpageShotScreen.message, "what was typed stays")
        }
    }

    @Test("D5 at AX3: Send above Done, 8 apart, both 44 or more, inside the window")
    func reportBarWhileTypingAtAX3() async throws {
        try await run(Self.ax3, reportPage()) { w in
            try await w.wait("the form") { has(w, id: "report.send") }
            try await w.settle()
            let field = try Self.messageField(w)
            w.window.makeKey()
            #expect(field.becomeFirstResponder(), "the message takes focus")
            try await w.wait("Done in the bar") { has(w, id: "report.done") }
            try await w.settle()
            let send = try node(w, id: "report.send"), done = try node(w, id: "report.done")
            #expect(send.frame.maxY <= done.frame.minY, "Send above Done: \(send.frame) \(done.frame)")
            #expect(abs(done.frame.minY - send.frame.maxY - PinnedBarSpec.spacing) < 0.5, "8 apart")
            for pill in [send, done] {
                #expect(pill.frame.width >= Theme.Metrics.minHitTarget && pill.frame.height >= Theme.Metrics.minHitTarget, "\(pill.label) \(pill.frame)")
            }
            #expect(w.window.bounds.contains(send.frame) && w.window.bounds.contains(done.frame), "inside the window: \(send.frame) \(done.frame)")
            _ = field.resignFirstResponder()
        }
    }
}
