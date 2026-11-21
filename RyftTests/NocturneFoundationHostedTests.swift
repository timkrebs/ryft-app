import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// T6.0's pieces in a real window, read from the accessibility tree (`HostedWindow`): the subpage header (Back, the centred
/// title's header trait, the 40 pt row, the stacked title at AX3, the back swipe kept with the bar hidden, the pinned bar never
/// covering the last row), the sheet header (centred title, reading order), the field (one element, the focus bar), the
/// steppers (one adjustable element each, the ends), the banner (44 pt buttons, stacking, retrying, the plain action,
/// `readsAsOne`), the selectable tile's trait, the legend mark hidden.
@MainActor
@Suite("Nocturne foundation: VoiceOver and layout", .serialized)
struct NocturneFoundationHostedTests {
    private typealias Tokens = NocturneTokenTests

    @MainActor
    private final class Log {
        var events: [String] = []
    }

    private func host<V: View>(_ view: V, width: CGFloat = 390, height: CGFloat = 1_000, typeSize: DynamicTypeSize = .large,
                               category: UIContentSizeCategory = .large,
                               _ body: (HostedWindow) async throws -> Void) async throws {
        let content = view.padding(.horizontal, Theme.Metrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Theme.background)
        try await HostedWindow.run(width: width, height: height, bottomInset: 0, typeSize: typeSize, category: category, content,
                                   body: body)
    }

    private func node(_ w: HostedWindow, _ label: String) throws -> HostedWindow.Node {
        try #require(w.node(label, exactly: true), "'\(label)' in \(w.nodes().map(\.label))")
    }

    private func node(_ w: HostedWindow, id: String) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.identifier == id }, "'\(id)' in \(w.nodes().map { $0.identifier ?? $0.label })")
    }

    // MARK: the subpage

    private struct Rows: View {
        var count = 3

        var body: some View {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                ForEach(0..<count, id: \.self) { group in
                    GroupedCard(Text(verbatim: "Group \(group + 1)")) {
                        ForEach(0..<4, id: \.self) { row in
                            GroupedRow.value(Text(verbatim: "Row \(group + 1).\(row + 1)"), value: Text(verbatim: "On"))
                        }
                    }
                }
            }
        }
    }

    /// A page pushed on a stack (`path` starts at one page), or the stack's root (`pushed: false`).
    private struct Stack<Page: View>: View {
        let pushed: Bool
        @ViewBuilder let page: () -> Page
        @State private var path: [Int] = []

        var body: some View {
            NavigationStack(path: $path) {
                Group {
                    if pushed { Text(verbatim: "Root page") } else { page() }
                }
                .navigationDestination(for: Int.self) { _ in page() }
            }
            .onAppear { if pushed { path = [1] } }
        }
    }

    private func navigationController(_ w: HostedWindow) -> UINavigationController? {
        func find(_ controller: UIViewController) -> UINavigationController? {
            if let nav = controller as? UINavigationController { return nav }
            return controller.children.lazy.compactMap(find).first ?? controller.presentedViewController.flatMap(find)
        }
        return find(w.host)
    }

    @Test("The header (DG-6): Back (44 pt, 'Back') leading, the title centred, a header; 22 to the content; no system bar")
    func subpageHeader() async throws {
        let page = Stack(pushed: true) { SubpageScaffold(Text(verbatim: "Display")) { Rows(count: 1) } }
        try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, page) { w in
            try await w.wait("the pushed page") { w.node("Display", exactly: true) != nil }
            try await w.settle()
            let back = try node(w, "Back")
            let title = try node(w, "Display")
            #expect(back.traits.contains(.button) && back.frame.width >= 44 && back.frame.height >= 44, "\(back.frame)")
            #expect(back.identifier == "subpage.back" && title.identifier == "subpage.header")
            #expect(title.traits.contains(.header), "the title is a header")
            #expect(abs(back.frame.minX - (20 - ScreenHeaderSpec.buttonOverhang)) < 1, "the circle's edge on the inset: \(back.frame)")
            #expect(abs(title.frame.midX - 195) < 1, "the title centred on the row: \(title.frame)")
            #expect(abs(title.frame.midY - back.frame.midY) < 1.5, "one row")
            let group = try node(w, "Group 1")
            let headerBottom = back.frame.midY + SubpageSpec.headerHeight / 2
            #expect(abs(group.frame.minY - headerBottom - SubpageSpec.contentGap) < 3, "22 to the content: \(group.frame.minY)")
            #expect(!w.nodes().contains { $0.label == "Root page" }, "the system bar's back button isn't there")
        }
    }

    @Test("At AX3 a title that doesn't fit beside the buttons goes under them, whole")
    func subpageHeaderAX3() async throws {
        let page = Stack(pushed: true) { SubpageScaffold(Text(verbatim: "Baseline sleep need")) { Rows(count: 1) } }
        try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: .accessibility3,
                                   category: .accessibilityExtraLarge, page) { w in
            try await w.wait("the pushed page") { w.node("Baseline sleep need", exactly: true) != nil }
            try await w.settle()
            let back = try node(w, "Back")
            let title = try node(w, "Baseline sleep need")
            #expect(title.frame.minY >= back.frame.maxY - ScreenHeaderSpec.buttonOverhang - 0.5,
                    "the title under the Back row: \(title.frame) \(back.frame)")
            #expect(title.frame.maxX <= 390 - 20 + 0.5, "inside the inset")
            let order = w.nodes().map(\.label)
            #expect((order.firstIndex(of: "Back") ?? .max) < (order.firstIndex(of: "Baseline sleep need") ?? -1))
        }
    }

    @Test("C §2.9: from AX1 a short title goes under Back and the trailing button too; at xxxLarge it stays on their row",
          arguments: [false, true])
    func subpageHeaderShortTitleAtAX(_ ax: Bool) async throws {
        let page = Stack(pushed: true) {
            SubpageScaffold(Text(verbatim: "Journal")) {
                CircleButton(systemImage: "plus", accessibilityLabel: Text(verbatim: "Add a habit")) {}
            } content: {
                Rows(count: 1)
            }
        }
        try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: ax ? .accessibility1 : .xxxLarge,
                                   category: ax ? .accessibilityMedium : .extraExtraExtraLarge, page) { w in
            try await w.wait("the pushed page") { w.node("Journal", exactly: true) != nil }
            try await w.settle()
            let back = try node(w, "Back"), add = try node(w, "Add a habit"), title = try node(w, "Journal")
            #expect(abs(back.frame.midY - add.frame.midY) < 1, "Back and + share a row: \(back.frame) \(add.frame)")
            let order = w.nodes().map(\.label)
            let (backAt, addAt, titleAt) = (order.firstIndex(of: "Back") ?? .max, order.firstIndex(of: "Add a habit") ?? .max,
                                            order.firstIndex(of: "Journal") ?? .max)
            if ax {
                #expect(title.frame.minY >= back.frame.maxY - ScreenHeaderSpec.buttonOverhang - 0.5,
                        "the title under the buttons' row: \(title.frame) \(back.frame)")
                #expect(abs(title.frame.minX - 20) < 1, "the title from the inset: \(title.frame)")
                #expect(backAt < addAt && addAt < titleAt, "the buttons' row, then the title: \(order)")
            } else {
                #expect(abs(title.frame.midY - back.frame.midY) < 1.5, "one row: \(title.frame) \(back.frame)")
                #expect(backAt < titleAt && titleAt < addAt, "Back, the title, +: \(order)")
            }
        }
    }

    @Test("The back swipe stays on with the bar hidden: allowed on a pushed page, refused on the root")
    func backSwipe() async throws {
        for pushed in [true, false] {
            let page = Stack(pushed: pushed) { SubpageScaffold(Text(verbatim: "Display"), navigation: pushed ? .back() : .none) {
                Rows(count: 1)
            } }
            try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, page) { w in
                try await w.wait("the page") { w.node("Display", exactly: true) != nil }
                try await w.settle()
                let nav = try #require(navigationController(w), "a navigation controller")
                let pop = try #require(nav.interactivePopGestureRecognizer)
                #expect(pop.isEnabled, "pushed: \(pushed)")
                let keeper = try #require(pop.delegate as? InteractivePopGestureKeeper, "the keeper is the delegate: \(pushed)")
                #expect(keeper.gestureRecognizerShouldBegin(pop) == pushed, "pushed: \(pushed), \(nav.viewControllers.count)")
            }
        }
    }

    /// Back and close (D4 rule 6): Back leading, the title centred, the close circle trailing, after the caller's circle.
    @Test("Custom actions: Back and the close circle run the caller's, the close circle says 'Close' or the caller's word")
    func headerActions() async throws {
        let log = Log()
        let pushed = Stack(pushed: true) {
            SubpageScaffold(Text(verbatim: "Import"),
                            navigation: .backAndClose(back: .perform { log.events.append("back") }, closeLabel: Text(verbatim: "Cancel"),
                                                      close: .perform { log.events.append("close") })) {
                CircleButton(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "More")) { log.events.append("more") }
            } content: {
                Rows(count: 1)
            }
        }
        try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, pushed) { w in
            try await w.wait("the pushed page") { w.node("Import", exactly: true) != nil }
            try await w.settle()
            let back = try node(w, "Back"), title = try node(w, "Import"), more = try node(w, "More"), cancel = try node(w, "Cancel")
            #expect(cancel.identifier == "subpage.close")
            #expect(abs(back.frame.minX - 18) < 1 && abs(cancel.frame.maxX - 372) < 1, "\(back.frame) \(cancel.frame)")
            #expect(abs(cancel.frame.minX - more.frame.maxX - (SubpageSpec.trailingSpacing - 4)) < 1,
                    "8 between the circles: \(more.frame) \(cancel.frame)")
            #expect(abs(title.frame.midX - 195) < 1, "the title centred whatever the slots hold: \(title.frame)")
            #expect(back.activate() && cancel.activate())
            try await w.wait("the taps") { log.events.count == 2 }
            #expect(log.events == ["back", "close"])
            let order = w.nodes().map(\.label)
            let at = { (label: String) in order.firstIndex(of: label) ?? .max }
            #expect(at("Back") < at("Import") && at("Import") < at("More") && at("More") < at("Cancel"), "\(order)")
        }
        let sheet = SubpageScaffold(Text(verbatim: "What do you wear?"), navigation: .close(label: nil, .perform { log.events.append("x") }),
                                    isSheet: true) { Rows(count: 1) }
        try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, sheet) { w in
            try await w.wait("the sheet's page") { w.node("Close", exactly: true) != nil }
            try await w.settle()
            let close = try node(w, "Close")
            #expect(close.identifier == "subpage.close")
            #expect(close.activate())
            try await w.wait("the tap") { log.events.count == 3 }
            #expect(log.events == ["back", "close", "x"])
        }
    }

    @Test("The pinned bar never covers the page: scrolled to the end, the last row sits above the bar's pill")
    func pinnedBar() async throws {
        let page = Stack(pushed: true) {
            SubpageScaffold(Text(verbatim: "Report a problem")) { Rows(count: 4) }
                .pinnedBar(caption: Text(verbatim: "Write a message first.")) {
                    PillButton(Text(verbatim: "Send"), systemImage: PillButton.Icon.send) {}
                }
        }
        try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, page) { w in
            try await w.wait("the page") { w.node("Send", exactly: true) != nil }
            try await w.settle()
            let scroll = try #require(w.pageScrollView(), "the page's scroll view")
            let end = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top, end)), animated: false)
            try await w.settle()
            let send = try node(w, "Send")
            let caption = try node(w, "Write a message first.")
            let last = try node(w, "Row 4.4")
            #expect(last.frame.maxY <= caption.frame.minY - PinnedBarSpec.topPadding + 0.5,
                    "the last row above the bar: \(last.frame) \(caption.frame)")
            #expect(caption.frame.maxY <= send.frame.minY, "the caption above the pill")
            #expect(send.frame.maxY <= 844 - 34 + 0.5, "the pill above the home indicator")
        }
    }

    // MARK: the sheet header

    @Test("The sheet header: the title centred whatever the slots hold, read first; close and Save at least 44")
    func sheetHeader() async throws {
        let header = SheetHeader(Text(verbatim: "Add activity"), closeLabel: Text(verbatim: "Cancel")) {
            PillButton(Text(verbatim: "Save"), size: .compact) {}
        }
        try await host(header.padding(.top, SheetHeaderSpec.topInset)) { w in
            try await w.settle()
            let title = try node(w, "Add activity")
            let cancel = try node(w, "Cancel")
            let save = try node(w, "Save")
            #expect(title.traits.contains(.header))
            #expect(abs(title.frame.midX - 195) < 1, "centred under the grabber: \(title.frame)")
            #expect(cancel.frame.width >= 44 && cancel.frame.height >= 44 && save.frame.height >= 44)
            #expect(abs(cancel.frame.minX - (20 - ScreenHeaderSpec.buttonOverhang)) < 1, "the circle's edge on the inset")
            #expect(save.frame.maxX <= 370 + 0.5 && save.frame.maxX >= 370 - 4, "the pill at the trailing inset: \(save.frame)")
            let order = w.nodes().map(\.label)
            let t = try #require(order.firstIndex(of: "Add activity")), c = try #require(order.firstIndex(of: "Cancel"))
            let s = try #require(order.firstIndex(of: "Save"))
            #expect(t < c && c < s, "title, close, then the commit: \(order)")
        }
    }

    @Test("With nothing trailing the title is still centred; a slot too wide at AX3 puts the title under the buttons, whole")
    func sheetHeaderEdges() async throws {
        try await host(SheetHeader(Text(verbatim: "Start workout")).padding(.top, 26)) { w in
            try await w.settle()
            let title = try node(w, "Start workout"), close = try node(w, "Close")
            #expect(abs(title.frame.midX - 195) < 1 && abs(title.frame.midY - close.frame.midY) < 1, "\(title.frame)")
        }
        let wide = SheetHeader(Text(verbatim: "Add sleep")) {
            PillButton(Text(verbatim: "Saving…"), size: .compact, busy: true) {}
        }
        try await host(wide.padding(.top, 26), typeSize: .accessibility3, category: .accessibilityExtraLarge) { w in
            try await w.settle()
            let title = try node(w, "Add sleep"), close = try node(w, "Close")
            #expect(title.frame.minY >= close.frame.maxY - ScreenHeaderSpec.buttonOverhang - 0.5, "under the buttons")
            #expect(title.frame.width > 120 && title.frame.minX >= 20 - 0.5 && title.frame.maxX <= 370 + 0.5, "\(title.frame)")
            #expect(abs(title.frame.midX - 195) < 1, "centred")
        }
    }

    // MARK: the field

    private struct FieldHost: View {
        let focused: Bool
        @State private var email = "alex@example.com"

        var body: some View {
            GroupedCard {
                FormField(Text(verbatim: "Email"), isFocused: focused) {
                    TextField(text: $email) { Text(verbatim: "Email field") }
                }
                FormField(Text(verbatim: "Password")) {
                    SecureField(text: .constant("")) { Text(verbatim: "Password field") }
                }
            }
        }
    }

    /// The window's text fields (UIKit's, outside SwiftUI's accessibility nodes), top to bottom.
    private func textFields(_ w: HostedWindow) -> [UITextField] {
        func walk(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(walk)
        }
        return walk(w.window).sorted { $0.convert($0.bounds, to: w.window).minY < $1.convert($1.bounds, to: w.window).minY }
    }

    @Test("A field is one element named by its label; focus draws the 2 pt bar 6 in from the card's edge, no fill")
    func formField() async throws {
        for focused in [true, false] {
            try await host(FieldHost(focused: focused).padding(.top, 20)) { w in
                try await w.settle()
                let fields = textFields(w)
                try #require(fields.count == 2, "two text fields")
                let email = fields[0]
                #expect(email.accessibilityLabel == "Email", "named by the row's label: \(email.accessibilityLabel ?? "nil")")
                #expect(email.text == "alex@example.com")
                #expect(fields[1].accessibilityLabel == "Password")
                #expect(!w.nodes().contains { $0.label == "Email" || $0.label == "Password" }, "the visual labels aren't read")
                let field = email.convert(email.bounds, to: w.window)
                let next = fields[1].convert(fields[1].bounds, to: w.window)
                #expect(next.minY - field.minY >= FormFieldSpec.minHeight - 0.5, "56 a row: \(field) \(next)")
                let bar = try #require(w.pixel(at: CGPoint(x: 20 + FormFieldSpec.focusInset + 1, y: field.midY - 4)))
                let fill = try #require(w.pixel(at: CGPoint(x: 20 + 3, y: field.midY - 4)))
                let surface = Tokens.resolve(Theme.surface)
                #expect(abs(fill.r - surface.r) < 3.0 / 255 && abs(fill.g - surface.g) < 3.0 / 255, "no fill: \(fill)")
                if focused {
                    #expect(bar.r > 0.8 && bar.g > 0.8, "the focus bar in ink: \(bar)")
                } else {
                    #expect(abs(bar.r - surface.r) < 3.0 / 255, "no bar without focus: \(bar)")
                }
            }
        }
    }

    private struct ChipHost: View {
        @State private var start = Date(timeIntervalSince1970: 1_795_500_720)

        var body: some View {
            GroupedCard {
                ValueChipRow(Text(verbatim: "Start")) {
                    ValueChip(Text(verbatim: "Start date"), date: $start, displayedComponents: .date)
                    ValueChip(Text(verbatim: "Start time"), date: $start, displayedComponents: .hourAndMinute)
                }
            }
            .environment(\.locale, Locale(identifier: "en_US"))
        }
    }

    /// The system date pickers over the chips (UIKit's, outside SwiftUI's nodes), in window points, top to bottom, then left
    /// to right.
    private func datePickerFrames(_ w: HostedWindow) -> [CGRect] {
        func walk(_ view: UIView) -> [UIDatePicker] {
            if let picker = view as? UIDatePicker { return [picker] }
            return view.subviews.flatMap(walk)
        }
        let frames: [CGRect] = walk(w.window).map { picker in picker.convert(picker.bounds, to: w.window) }
        return frames.sorted { (a: CGRect, b: CGRect) -> Bool in
            if abs(a.minY - b.minY) > 0.5 { return a.minY < b.minY }
            return a.minX < b.minX
        }
    }

    @Test("A chip row keeps its label and both chips on one line at the default size; at AX3 the chips go under it, inside",
          arguments: [false, true])
    func chipRow(ax3: Bool) async throws {
        try await host(ChipHost().padding(.top, 20), typeSize: ax3 ? .accessibility3 : .large,
                       category: ax3 ? .accessibilityExtraLarge : .large) { w in
            try await w.settle()
            let label = try node(w, "Start")
            // The system pickers over the chips (UIKit's, outside SwiftUI's nodes): where the chips are, and their names.
            let pickers: [CGRect] = datePickerFrames(w)
            try #require(pickers.count == 2, "the two date pickers")
            for frame in pickers {
                #expect(frame.minX >= 20 - 0.5 && frame.maxX <= 370 + 0.5, "inside the card: \(frame)")
            }
            if ax3 {
                // The system picker is taller than the chip it covers at AX3 (62 against the chip's line): its centre is the chip's.
                #expect(pickers[0].midY > label.frame.maxY + ValueChipSpec.spacing, "under the label: \(pickers[0]) \(label.frame)")
                #expect(pickers[1].midY > pickers[0].midY, "one under the other")
            } else {
                #expect(abs(pickers[0].midY - pickers[1].midY) < 1, "side by side: \(pickers)")
                #expect(abs(pickers[0].midY - label.frame.midY) < 2, "beside the label")
            }
            #expect(!w.nodes().contains { $0.label.contains("2026") && $0.label != "Start" }, "the chip's own text isn't read twice")
        }
    }

    // MARK: the steppers

    private struct StepperHost: View {
        @State var days = 7
        @State var minutes = 465

        var body: some View {
            VStack(spacing: 24) {
                GroupedCard {
                    RyftStepperRow(Text(verbatim: "Days per week"), value: $days, in: 1...7)
                    RyftStepperRow(Text(verbatim: "Sets"), quiet: true, value: .constant(3), in: 1...10)
                }
                HeroStepper(Text(verbatim: "Baseline sleep need"),
                            value: RyftStepperValue($minutes, in: 240...720, step: 15, format: NocturneFoundationCatalog.clock)) {
                    DotNumeral(NocturneFoundationCatalog.clock(minutes), glyphGap: DotNumeral.glyphGapDetail, placeholder: "0:00",
                               accessibilityLabel: Text(verbatim: "Sleep need numeral"))
                }
            }
        }
    }

    @Test("A stepper row and a hero stepper are one adjustable element each; the circles aren't stops; the ends are said",
          arguments: [false, true])
    func steppers(ax3: Bool) async throws {
        try await host(StepperHost().padding(.top, 20), typeSize: ax3 ? .accessibility3 : .large,
                       category: ax3 ? .accessibilityExtraLarge : .large) { w in
            try await w.settle()
            let row = try node(w, "Days per week")
            #expect(row.isAdjustable && row.value == "7, maximum", "\(row.value ?? "nil")")
            let sets = try node(w, "Sets")
            #expect(sets.frame.midY - row.frame.midY >= RyftStepperSpec.rowMinHeight - 0.5, "56 a row: \(row.frame) \(sets.frame)")
            #expect(!w.nodes().contains { $0.label == "Less" || $0.label == "More" }, "the circles aren't VoiceOver stops")
            #expect(!w.nodes().contains { $0.label == "Sleep need numeral" }, "the numeral's own label is replaced")
            row.decrement()
            try await w.wait("6") { w.node("Days per week", exactly: true)?.value == "6" }
            let hero = try node(w, "Baseline sleep need")
            #expect(hero.isAdjustable && hero.value == "7:45")
            hero.increment()
            try await w.wait("8:00") { w.node("Baseline sleep need", exactly: true)?.value == "8:00" }
            #expect(w.nodes().filter { $0.label == "Baseline sleep need" }.count == 1)
        }
    }

    // MARK: the banner

    @Test("The banner's buttons: 44 pt targets, 18 apart in a row, one under the other at AX3", arguments: [false, true])
    func bannerButtons(ax3: Bool) async throws {
        let banner = InlineMessage(message: "Couldn't reach RYFT. Showing what was loaded earlier.", retry: {},
                                   caption: "Showing data from 9:20", onDetails: {}, identifier: "t60",
                                   action: ("Open Settings", {}), announces: false)
        try await host(banner.padding(.top, 20), typeSize: ax3 ? .accessibility3 : .large,
                       category: ax3 ? .accessibilityExtraLarge : .large) { w in
            try await w.settle()
            let retry = try node(w, id: "t60.retry")
            let action = try node(w, id: "t60.action")
            let details = try node(w, id: "t60.details")
            #expect(retry.label == "Try again" && action.label == "Open Settings" && details.label == "Details")
            for button in [retry, action, details] {
                #expect(button.traits.contains(.button) && button.frame.width >= 43.99 && button.frame.height >= 43.99,
                        "\(button.label): \(button.frame)")
            }
            #expect(abs(retry.frame.minX - (20 + InlineMessageSpec.horizontalPadding)) < 1, "from the card's leading inset")
            if ax3 {
                #expect(action.frame.minY >= retry.frame.maxY - 0.5 && details.frame.minY >= action.frame.maxY - 0.5,
                        "stacked: \(retry.frame) \(action.frame) \(details.frame)")
            } else {
                #expect(abs(retry.frame.midY - details.frame.midY) < 1, "one row")
                #expect(abs(action.frame.minX - retry.frame.maxX - InlineMessageSpec.buttonSpacing) < 1, "18 apart")
            }
            let message = try node(w, "Couldn't reach RYFT. Showing what was loaded earlier.")
            #expect(message.frame.maxY <= retry.frame.minY + 0.5, "the sentence above the buttons")
        }
    }

    @Test("C §2.9: the glyph beside the sentence by default, above it from AX1, where the sentence takes the card's width",
          arguments: [false, true])
    func noticeGlyphAtAX(_ ax: Bool) async throws {
        let notice = InlineMessage(message: "Notifications are being rolled out", systemImage: "bell",
                                   caption: "We'll let you know here when notifications reach your account.", announces: false)
        try await host(notice.padding(.top, 20), typeSize: ax ? .accessibility1 : .large,
                       category: ax ? .accessibilityMedium : .large) { w in
            try await w.settle()
            let sentence = try node(w, "Notifications are being rolled out")
            let caption = try node(w, "We'll let you know here when notifications reach your account.")
            let inset = 20 + InlineMessageSpec.horizontalPadding
            if ax {
                #expect(abs(sentence.frame.minX - inset) < 1, "from the card's inset, under the glyph: \(sentence.frame)")
                #expect(sentence.frame.minY > 20 + InlineMessageSpec.topPadding + InlineMessageSpec.glyphSize, "the glyph above")
            } else {
                #expect(sentence.frame.minX >= inset + InlineMessageSpec.glyphSize + InlineMessageSpec.glyphGap - 1,
                        "beside the glyph: \(sentence.frame)")
            }
            #expect(abs(caption.frame.minX - sentence.frame.minX) < 1, "the caption under the sentence")
        }
    }

    /// PR 6 ui-validator (Welcome's two banners): the sentences started at x 153 and 162 under glyphs of different widths.
    @Test("The glyph sits in a fixed column: banners with narrow and wide glyphs start their sentences on one line")
    func bannerGlyphColumn() async throws {
        let messages = [("You were signed out. Log in again to continue.", "person.crop.circle.badge.exclamationmark"),
                        ("2 activities or nights you added haven't reached RYFT yet.", "icloud.and.arrow.up"),
                        ("This day can't be changed any more.", "lock"),
                        ("Nothing logged yet today.", "dumbbell")]
        let banners = VStack(spacing: 12) {
            ForEach(messages, id: \.0) { InlineMessage(message: $0.0, systemImage: $0.1, announces: false) }
        }
        try await host(banners.padding(.top, 20)) { w in
            try await w.settle()
            let column = 20 + InlineMessageSpec.horizontalPadding + InlineMessageSpec.glyphColumn + InlineMessageSpec.glyphGap
            for (message, glyph) in messages {
                let sentence = try node(w, message)
                #expect(abs(sentence.frame.minX - column) < 1, "\(glyph): \(sentence.frame) from \(column)")
            }
        }
    }

    /// C §2.6: an action inside a notice is a text link, 16 Medium in ink with a 1 pt underline in ink at 35 %. Read in pixels:
    /// the underline is a row under the word's middle whose pixels sit at 35 % ink over `surface` along most of the word (the
    /// system skips descenders, so "Try again" breaks at y and g); a glyph's edges reach that level only here and there.
    @Test("A banner's ink actions are text links: 'Try again' and a plain action are underlined in ink at 35 %, Details is not")
    func bannerActionsAreTextLinks() async throws {
        let banner = InlineMessage(message: "2 activities or nights you added haven't reached RYFT yet.",
                                   systemImage: "icloud.and.arrow.up", retry: {}, onDetails: {}, identifier: "link",
                                   action: ("Delete from this iPhone", {}), announces: false)
        try await host(banner.padding(.top, 20)) { w in
            try await w.settle()
            let pixels = try WindowPixels(w)
            let surface = NocturneTokenTests.resolve(Theme.surface)
            let ink = NocturneTokenTests.resolve(Theme.textPrimary)
            let underline = surface.g + (ink.g - surface.g) * InlineMessageSpec.linkUnderlineOpacity
            for id in ["link.retry", "link.action", "link.details"] {
                let frame = try #require(w.nodes().first { $0.identifier == id }, "\(id)").frame
                let text = try #require(pixels.box(in: frame) { $0.g > surface.g + 0.12 }, "\(id) is drawn")
                // Below the word's middle: an underline, not a strike-through.
                let lower = CGRect(x: text.minX, y: text.midY, width: text.width, height: frame.maxY - text.midY)
                let row = Self.fullestRow(pixels, in: lower) { abs($0.g - underline) < 0.1 }
                if id == "link.details" {
                    #expect(row < text.width * 0.3, "Details has no underline: \(row) of \(text.width)")
                } else {
                    #expect(row > text.width * 0.55, "\(id) is underlined in ink at 35 %: \(row) of \(text.width)")
                }
            }
        }
    }

    /// The most pixels on one row inside `rect` for which `match` holds, in points (gaps allowed).
    private static func fullestRow(_ pixels: WindowPixels, in rect: CGRect, where match: (WindowPixels.RGBA) -> Bool) -> CGFloat {
        let step = 1 / pixels.scale
        var best = 0
        var y = rect.minY + step / 2
        while y < rect.maxY {
            var count = 0
            var x = rect.minX + step / 2
            while x < rect.maxX {
                if match(pixels.at(x, y)) { count += 1 }
                x += step
            }
            best = max(best, count)
            y += step
        }
        return CGFloat(best) * step
    }

    @Test("Retrying reads 'Trying again…' and is disabled; a notice has no buttons; readsAsOne is one element")
    func bannerStates() async throws {
        let banners = VStack(spacing: 12) {
            InlineMessage(message: "Couldn't reach RYFT.", retry: {}, isRetrying: true, identifier: "busy", announces: false)
            InlineMessage(message: "Your file is ready. Sign in to continue.", systemImage: "doc.text", announces: false)
            InlineMessage(message: "Your account is being deleted.", systemImage: "trash", caption: "Request ID r-1",
                          severity: .destructive, announces: false, readsAsOne: true)
        }
        try await host(banners.padding(.top, 20)) { w in
            try await w.settle()
            let busy = try node(w, id: "busy.retry")
            #expect(busy.label == "Trying again…" && !busy.isEnabled, "\(busy.label)")
            #expect(try node(w, "Your file is ready. Sign in to continue.").traits.contains(.staticText))
            let one = try #require(w.nodes().first { $0.label.hasPrefix("Your account is being deleted.") })
            #expect(one.label.contains("Request ID r-1"), "the caption in the same element: \(one.label)")
            #expect(!w.nodes().contains { $0.label == "Request ID r-1" })
            // An opaque surface, no stroke: the card's edge is surface right up to the corner's curve.
            let notice = try node(w, "Your file is ready. Sign in to continue.")
            let edge = try #require(w.pixel(at: CGPoint(x: 20.5, y: notice.frame.midY)))
            let surface = Tokens.resolve(Theme.surface)
            #expect(abs(edge.r - surface.r) < 3.0 / 255 && abs(edge.g - surface.g) < 3.0 / 255, "no stroke: \(edge)")
        }
    }

    // MARK: tiles and the legend

    @Test("A chosen tile says selected; the legend mark is never read")
    func tilesAndLegend() async throws {
        let view = VStack(spacing: 12) {
            HStack(spacing: 10) {
                SelectableTile(symbol: "watch.analog", title: "Garmin", isSelected: true) {}
                SelectableTile(symbol: "circle.circle", title: "Oura", isSelected: false) {}
            }
            HStack(spacing: 14) {
                LegendMark(Theme.recovery)
                Text(verbatim: "Recovery")
            }
        }
        try await host(view.padding(.top, 20)) { w in
            try await w.settle()
            let garmin = try node(w, "Garmin"), oura = try node(w, "Oura")
            #expect(garmin.isSelected && garmin.traits.contains(.button))
            #expect(!oura.isSelected && oura.traits.contains(.button))
            #expect(garmin.frame.height >= SelectableTileSpec.minHeight - 0.5)
            let recovery = try node(w, "Recovery")
            #expect(w.nodes().filter { $0.frame.maxX <= recovery.frame.minX && abs($0.frame.midY - recovery.frame.midY) < 20 }
                .isEmpty, "nothing read for the mark")
        }
    }
}
