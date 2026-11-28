import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The dot tab bar (docs/work/2026-11-16-nocturne/design.md §P5-2; §P5-12 tests 5, 12, 38 and 42): its constants, the
/// contrast it promises, the app's five tabs, `reselect`, and in a real window the bar alone (44 high above the home
/// indicator, five 44 pt buttons that read as tabs, the labels capped at `xxLarge`) and the app's tab host (`RootTabs`: no
/// system bar, the content ending at the bar's top, the bar last for VoiceOver, a re-tap rebuilding the tab at its top, a
/// tab's state kept across a switch).
@MainActor
@Suite("RyftTabBar", .serialized)
struct RyftTabBarTests {
    private typealias Tokens = NocturneTokenTests

    private static let titles = ["Today", "Sleep", "Strain", "Insights", "Profile"]

    // MARK: test 5, the constants

    @Test("Test 5: top 14, dot 6, gap 6, line 14, bottom 4, sides 16; items at least 44 × 44; 44 high; dot 30 %; cap xxLarge")
    func constants() {
        #expect(RyftTabBar.topPadding == 14 && RyftTabBar.dot == 6 && RyftTabBar.dotGap == 6)
        #expect(RyftTabBar.labelLine == 14 && RyftTabBar.bottomPadding == 4 && RyftTabBar.sidePadding == 16)
        #expect(RyftTabBar.minItemSize == 44 && RyftTabBar.minItemSize == Theme.Metrics.minHitTarget)
        #expect(RyftTabBar.contentHeight == 44, "14 + 6 + 6 + 14 + 4")
        #expect(RyftTabBar.unselectedDotOpacity == 0.30 && RyftTabBar.pressedOpacity == 0.6)
        #expect(RyftTabBar.maxLabelSize == .xxLarge)
        #expect(RyftTabBar.identifier == "tab.bar")
        // D5-3: the board's 76 is 42 + 34; ours is 44 + 34, and 44 on a phone without a home indicator.
        #expect(RyftTabBar.height(bottomInset: 34) == 78 && RyftTabBar.height(bottomInset: 0) == 44)
    }

    @Test("Reduce Motion: the selection jumps; otherwise it changes in 250 ms (Theme.Motion.quick)")
    func selectionMotion() {
        #expect(RyftTabBar.selectionAnimation(reduceMotion: true) == nil)
        #expect(RyftTabBar.selectionAnimation(reduceMotion: false) == Theme.Motion.quick)
    }

    @Test("A tab leaves the bar's room: from the bar's top to the host's bottom edge, 78 over a home indicator, 44 without")
    func room() {
        // 844 high with a 34 pt home indicator: the bar's top at 844 - 34 - 44 = 766.
        #expect(RyftTabBar.room(hostBottom: 844, barTop: 766) == 78)
        #expect(RyftTabBar.room(hostBottom: 667, barTop: 623) == 44, "no home indicator")
        #expect(RyftTabBar.room(hostBottom: 0, barTop: -RyftTabBar.contentHeight) == 44, "before the first measure")
        #expect(RyftTabBar.room(hostBottom: 0, barTop: 766) == 0, "never negative")
    }

    // MARK: test 12, contrast

    @Test("Test 12: the label textTertiary ≥ 4.5, selected textPrimary ≥ 17 on background; the 30 % dot is a mark under 3")
    func contrast() {
        let ground = Tokens.resolve(Theme.background)
        #expect(Tokens.ratio(Tokens.resolve(Theme.textTertiary), on: ground) >= 4.5)
        #expect(Tokens.ratio(Tokens.resolve(Theme.textPrimary), on: ground) >= 17)
        // The selected dot is a graphic: Volt needs 3:1, and has far more.
        #expect(Tokens.ratio(Tokens.resolve(Theme.signal), on: ground) >= 3)
        // D5-15: the unselected dot is decoration (2.45:1), not a boundary; the label beside it names the tab. Pinned so
        // a change to it is a decision.
        var dot = Tokens.resolve(Theme.textPrimary)
        dot.a = RyftTabBar.unselectedDotOpacity
        let ratio = Tokens.ratio(dot, on: ground)
        #expect(ratio < 3 && abs(ratio - 2.45) < 0.05, "\(ratio)")
    }

    // MARK: the app's tabs and reselect (test 42)

    @Test("The five tabs in order: titles, `tab.<rawValue>` identifiers, the bar's items")
    func appTabs() {
        let tabs = AppTab.tabs(structureV2: false)
        #expect(tabs.map { String(localized: $0.title) } == Self.titles)
        #expect(tabs.map(\.identifier) == ["tab.today", "tab.sleep", "tab.strain", "tab.insights", "tab.profile"])
        let items = RyftTabBar.appTabs
        #expect(items.map(\.tab) == tabs.map(\.rawValue))
        #expect(items.map(\.identifier) == tabs.map(\.identifier))
        #expect(items.map { String(localized: $0.title) } == Self.titles)
    }

    @Test("Test 42: reselect bumps only that tab's stack ID and keeps the selection")
    func reselectBumpsOneTab() {
        let state = AppState(env: .test())
        #expect(AppTab.allCases.allSatisfy { state.stackID(for: $0) == 0 })
        state.selectedTab = .strain
        state.reselect(.strain)
        #expect(state.stackID(for: .strain) == 1)
        #expect(AppTab.allCases.filter { $0 != .strain }.allSatisfy { state.stackID(for: $0) == 0 })
        state.reselect(.strain)
        state.reselect(.today)
        #expect(state.stackID(for: .strain) == 2 && state.stackID(for: .today) == 1 && state.stackID(for: .sleep) == 0)
        #expect(state.selectedTab == .strain, "a re-tap doesn't change the tab")
    }

    // MARK: the bar in a window

    @MainActor
    private final class Log {
        var selected: [String] = []
        var reselected: [String] = []
    }

    /// The bar under an empty page. The window's own home-indicator inset (34 on a phone with one); 34 is added when the
    /// simulator gives none, so the bar always sits over an inset.
    private func hostBar(selection: String = "sleep", log: Log? = nil, typeSize: DynamicTypeSize = .large,
                         category: UIContentSizeCategory = .large, _ body: (HostedWindow, CGFloat) async throws -> Void) async throws {
        let log = log ?? Log()
        let bar = RyftTabBar(items: RyftTabBar.appTabs, selection: selection,
                             select: { log.selected.append($0) }, reselect: { log.reselected.append($0) })
        let page = Theme.background.ignoresSafeArea().ryftTabBar(bar)
        try await HostedWindow.run(width: 390, height: 844, bottomInset: 0, typeSize: typeSize, category: category, page) { w in
            if w.host.view.safeAreaInsets.bottom < 1 { w.host.additionalSafeAreaInsets.bottom = 34 }
            try await w.wait("the bar") { w.nodes().contains { $0.identifier == "tab.today" } }
            try await w.settle()
            try await body(w, w.host.view.safeAreaInsets.bottom)
        }
    }

    private func items(_ w: HostedWindow) -> [HostedWindow.Node] {
        w.nodes().filter { $0.identifier?.hasPrefix("tab.") == true && $0.identifier != RyftTabBar.identifier }
    }

    @Test("Hosted: 44 over the inset, a hairline on top; five 44 pt buttons, 71.6 wide at 390, in order")
    func barGeometry() async throws {
        try await hostBar { w, inset in
            let height = w.window.bounds.height
            let tabs = items(w)
            try #require(tabs.count == 5, "\(w.nodes().map { $0.identifier ?? $0.label })")
            let width = (390 - 2 * RyftTabBar.sidePadding) / 5
            for (index, tab) in tabs.enumerated() {
                #expect(tab.frame.width >= 44 && tab.frame.height >= 44, "\(tab.label) \(tab.frame)")
                #expect(abs(tab.frame.width - width) < 0.5, "space-around: \(tab.frame.width), not \(width)")
                #expect(abs(tab.frame.minX - (RyftTabBar.sidePadding + CGFloat(index) * width)) < 0.5, "\(tab.label) \(tab.frame)")
                #expect(abs(tab.frame.height - RyftTabBar.contentHeight) < 0.5, "44 high at the default size: \(tab.frame)")
                #expect(abs(tab.frame.maxY - (height - inset)) < 0.5, "on the inset: \(tab.frame), inset \(inset)")
            }
            // Drawn: the hairline is the bar's top, `height(bottomInset:)` above the window's bottom (78 over 34).
            let top = height - RyftTabBar.height(bottomInset: inset)
            let rule = try #require(w.pixel(at: CGPoint(x: 195, y: top + 0.5)))
            let above = try #require(w.pixel(at: CGPoint(x: 195, y: top - 1)))
            let below = try #require(w.pixel(at: CGPoint(x: 195, y: top + 3)))
            let ground = Tokens.resolve(Theme.background)
            let line = Tokens.over(Tokens.resolve(Theme.separator), ground)
            #expect(abs(rule.r - line.r) < 3 / 255 && abs(rule.g - line.g) < 3 / 255, "the hairline at \(top): \(rule)")
            #expect(abs(above.r - ground.r) < 2 / 255 && abs(below.r - ground.r) < 2 / 255, "background around it: \(above) \(below)")
            if inset == 34 { #expect(height - top == 78) }
        }
    }

    @Test("Hosted: a container 'Tab bar'; buttons named by tab, 'Tab n of 5', the selected one selected, identifiers")
    func barAccessibility() async throws {
        try await hostBar(selection: "insights") { w, _ in
            let container = try #require(w.nodes().first { $0.identifier == RyftTabBar.identifier || $0.label == "Tab bar" },
                                         "the container in \(w.nodes().map { $0.identifier ?? $0.label })")
            #expect(container.label == "Tab bar")
            let tabs = items(w)
            #expect(tabs.map(\.label) == Self.titles)
            #expect(tabs.map(\.value) == (1...5).map { "Tab \($0) of 5" })
            #expect(tabs.map(\.identifier) == AppTab.tabs(structureV2: false).map(\.identifier))
            #expect(tabs.allSatisfy { $0.traits.contains(.button) })
            #expect(tabs.map(\.isSelected) == [false, false, false, true, false], "only Insights")
        }
    }

    @Test("Hosted: a tap on another tab selects it; on the selected tab it reselects")
    func barActions() async throws {
        let log = Log()
        try await hostBar(selection: "strain", log: log) { w, _ in
            let tabs = items(w)
            try #require(tabs.count == 5)
            tabs[1].activate()
            tabs[2].activate()
            tabs[4].activate()
            #expect(log.selected == ["sleep", "profile"])
            #expect(log.reselected == ["strain"])
        }
    }

    @Test("Hosted: the labels grow up to xxLarge and stop there; the bar with them")
    func labelsCapped() async throws {
        var heights: [CGFloat] = []
        for (typeSize, category) in [(DynamicTypeSize.large, UIContentSizeCategory.large), (.xxLarge, .extraExtraLarge),
                                     (.accessibility3, .accessibilityExtraLarge)] {
            try await hostBar(typeSize: typeSize, category: category) { w, inset in
                let tabs = items(w)
                try #require(tabs.count == 5)
                heights.append(tabs[0].frame.height)
                #expect(abs(tabs[0].frame.maxY - (w.window.bounds.height - inset)) < 0.5)
                #expect(tabs.allSatisfy { $0.frame.width >= 44 && $0.frame.height >= 44 })
            }
        }
        try #require(heights.count == 3)
        #expect(abs(heights[0] - 44) < 0.5, "44 at the default size: \(heights)")
        #expect(heights[1] > heights[0], "the label grows to xxLarge: \(heights)")
        #expect(abs(heights[2] - heights[1]) < 0.5, "AX3 is xxLarge's height: \(heights)")
    }

    // MARK: test 38, the app's tab host

    /// `RootTabs` on mock data in a 390 × 844 window, Today selected.
    private func hostTabs(_ state: AppState, _ body: (HostedWindow, CGFloat) async throws -> Void) async throws {
        try await HostedWindow.run(width: 390, height: 844, bottomInset: 0,
                                   RootTabs().previewEnvironment(state).environment(\.locale, Locale(identifier: "en_US"))) { w in
            if w.host.view.safeAreaInsets.bottom < 1 { w.host.additionalSafeAreaInsets.bottom = 34 }
            try await w.wait("Today and the bar") {
                w.nodes().contains { $0.identifier == "today.ruler" } && w.nodes().contains { $0.identifier == "tab.today" }
            }
            try await w.settle()
            try await body(w, w.host.view.safeAreaInsets.bottom)
        }
    }

    /// Every `UITabBar` in the window that could be seen.
    private func visibleSystemTabBars(_ w: HostedWindow) -> [UITabBar] {
        var found: [UITabBar] = []
        func walk(_ view: UIView) {
            if let bar = view as? UITabBar, !bar.isHidden, bar.alpha > 0.01, bar.window != nil,
               bar.convert(bar.bounds, to: w.window).intersects(w.window.bounds) {
                found.append(bar)
            }
            view.subviews.forEach(walk)
        }
        walk(w.window)
        return found
    }

    @Test("Test 38: no system bar; the bar 44 above the inset and last for VoiceOver; Today's content ends at its top")
    func tabHost() async throws {
        let state = AppState.preview()
        try await hostTabs(state) { w, inset in
            #expect(visibleSystemTabBars(w).isEmpty, "the system tab bar is hidden")
            let nodes = w.nodes()
            let barTop = w.window.bounds.height - inset - RyftTabBar.contentHeight
            let tabs = items(w)
            try #require(tabs.count == 5, "\(nodes.map { $0.identifier ?? $0.label })")
            #expect(tabs.allSatisfy { abs($0.frame.minY - barTop) < 0.5 }, "\(tabs.map(\.frame)), top \(barTop)")
            #expect(tabs.map(\.isSelected) == [true, false, false, false, false])
            // VoiceOver: the content first, the bar last, left to right.
            let first = try #require(nodes.firstIndex { $0.identifier == "tab.today" })
            #expect(nodes[first...].prefix(5).map(\.identifier) == AppTab.tabs(structureV2: false).map(\.identifier),
                    "the bar's items in order")
            let after = nodes[first...].filter { $0.identifier?.hasPrefix("tab.") != true && $0.label != "Tab bar" }
            #expect(after.isEmpty, "nothing after the bar: \(after.map(\.label))")
            // The viewport ends at the bar: scrolled to the end, nothing is under it.
            let scroll = try #require(w.pageScrollView())
            let viewport = scroll.convert(scroll.bounds, to: w.window)
            #expect(abs(viewport.maxY - barTop) < 0.5, "the page ends at the bar's top: \(viewport), bar \(barTop)")
            let end = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            scroll.setContentOffset(CGPoint(x: 0, y: end), animated: false)
            try await w.settle()
            let content = w.nodes().filter { $0.identifier?.hasPrefix("tab.") != true && $0.label != "Tab bar" }
                .filter { $0.frame.maxY > 0 && $0.frame.minY < w.window.bounds.height }
            let lowest = try #require(content.max { $0.frame.maxY < $1.frame.maxY })
            #expect(lowest.frame.maxY <= barTop + 0.5, "'\(lowest.label)' ends at \(lowest.frame.maxY), under the bar's top \(barTop)")
        }
    }

    @Test("Test 38/42: a re-tap on the selected tab rebuilds it at the top; a tap on another selects it")
    func reselectInTheHost() async throws {
        let state = AppState.preview()
        try await hostTabs(state) { w, _ in
            let scroll = try #require(w.pageScrollView())
            let top = -scroll.adjustedContentInset.top
            scroll.setContentOffset(CGPoint(x: 0, y: top + 400), animated: false)
            try await w.settle()
            try #require(abs((w.pageScrollView()?.contentOffset.y ?? top) - (top + 400)) < 1, "scrolled down")

            try #require(items(w).first { $0.identifier == "tab.today" }).activate()
            try await w.wait("Today rebuilt") { state.stackID(for: .today) == 1 }
            try await w.wait("Today at its top") {
                guard let page = w.pageScrollView() else { return false }
                return abs(page.contentOffset.y + page.adjustedContentInset.top) < 1
            }
            #expect(state.selectedTab == .today)
            #expect(AppTab.allCases.filter { $0 != .today }.allSatisfy { state.stackID(for: $0) == 0 })

            try #require(items(w).first { $0.identifier == "tab.sleep" }).activate()
            try await w.wait("Sleep selected") { state.selectedTab == .sleep }
            try await w.wait("its item selected") { items(w).first { $0.identifier == "tab.sleep" }?.isSelected == true }
            #expect(state.stackID(for: .sleep) == 0, "a switch is not a re-tap")
        }
    }

    /// Two tabs with the app's host modifiers; the second counts taps in its own `@State`.
    private struct KeepsState: View {
        @State private var selection = "first"
        @State private var stackIDs: [String: Int] = [:]

        var body: some View {
            TabView(selection: $selection) {
                Text(verbatim: "First page")
                    .id(stackIDs["first", default: 0]).ryftTab().tag("first")
                Counter()
                    .id(stackIDs["second", default: 0]).ryftTab().tag("second")
            }
            .ryftTabBar(RyftTabBar(items: [.init(tab: "first", title: "First", identifier: "tab.first"),
                                           .init(tab: "second", title: "Second", identifier: "tab.second")],
                                   selection: selection, select: { selection = $0 },
                                   reselect: { stackIDs[$0, default: 0] += 1 }))
        }
    }

    private struct Counter: View {
        @State private var count = 0

        var body: some View {
            Button { count += 1 } label: { Text(verbatim: "Count \(count)") }
        }
    }

    private func tap(_ w: HostedWindow, _ id: String) throws {
        try #require(w.nodes().first { $0.identifier == id }, "\(id)").activate()
    }

    @Test("Test 38: a tab keeps its @State across selection changes, and loses it on a re-tap")
    func aTabKeepsItsState() async throws {
        try await HostedWindow.run(width: 390, height: 844, bottomInset: 0, KeepsState()) { w in
            try await w.wait("the bar") { w.node("First", exactly: true) != nil }
            try tap(w, "tab.second")
            try await w.wait("the counter") { w.node("Count 0", exactly: true) != nil }
            try #require(w.node("Count 0", exactly: true)).activate()
            try await w.wait("counted") { w.node("Count 1", exactly: true) != nil }
            try tap(w, "tab.first")
            try await w.wait("the first page") { w.node("First page", exactly: true) != nil }
            try tap(w, "tab.second")
            try await w.wait("the counter again") { w.node("Count", exactly: false) != nil }
            #expect(w.node("Count 1", exactly: true) != nil, "kept: \(w.nodes().map(\.label))")
            try tap(w, "tab.second")
            try await w.wait("rebuilt by the re-tap") { w.node("Count 0", exactly: true) != nil }
        }
    }
}
