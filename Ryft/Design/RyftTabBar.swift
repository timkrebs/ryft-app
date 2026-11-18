// The dot tab bar (Nocturne, docs/work/2026-11-16-nocturne/design.md §P5-2, brief §1 "Tab-Leiste"): a flat bar pinned to
// the bottom, a 6 pt dot over an 11 pt label per tab, the active dot Volt. It replaces the system tab bar, which stays a
// floating glass capsule on iOS 26+ whatever its appearance says: each tab hides the system bar and keeps room for this
// one (`ryftTab()`), and this bar is drawn over the `TabView`'s bottom edge (`ryftTabBar(_:)`), so every tab's content,
// pushed screens included, ends at its top.
import SwiftUI

/// Five (or any number of) items, space-around. The bar is `contentHeight` plus the home-indicator inset, on `background`
/// with a 1 pt `separator` rule on top. Selected: a Volt dot, the label in full `textPrimary` and Medium. Unselected: a
/// dot at 30 % and the label in `textTertiary`. The item is the tap target: at least 44 × 44, as high as the bar's content.
/// Labels follow Dynamic Type up to `xxLarge` (the system tab bar caps its labels too); from `accessibility1` the Large
/// Content Viewer shows the label. Container: "Tab bar" (`tab.bar`); each item is a button, "selected" when it is, with its
/// position ("Tab 2 of 5") as the value, because SwiftUI has no tab-bar trait. Tapping the selected item calls `reselect`.
///
/// Non-generic (a generic view can't hold static stored properties): items are `String` ids; the app maps `AppTab`.
struct RyftTabBar: View {
    typealias Tab = String
    struct Item {
        let tab: Tab
        let title: LocalizedStringResource
        /// `tab.today`, … for UI tests (the system bar's buttons were found by title in `app.tabBars`).
        let identifier: String
    }

    /// Board: padding 14 top, dot 6, gap 6, an 11 pt label line; 42 above the home-indicator inset (42 + 34 = the
    /// board's 76). Here 44 (bottom padding 4, not 2, D5-3), so an item is a 44 pt target on a phone without an indicator.
    nonisolated static let topPadding: CGFloat = 14, dot: CGFloat = 6, dotGap: CGFloat = 6
    nonisolated static let bottomPadding: CGFloat = 4, sidePadding: CGFloat = 16
    /// The label's line box at the default size: the 11 pt line (Satoshi's is 14.85, SF's 13.1, centred in it). It grows
    /// with the label up to `maxLabelSize`.
    nonisolated static let labelLine: CGFloat = 14
    /// An item is at least this wide and this high: the tap target.
    nonisolated static let minItemSize: CGFloat = 44
    /// The item's height at the default size, 14 + 6 + 6 + 14 + 4: a 44 pt target.
    nonisolated static let contentHeight: CGFloat = topPadding + dot + dotGap + labelLine + bottomPadding
    nonisolated static let unselectedDotOpacity = 0.30
    /// A pressed item; no scale.
    nonisolated static let pressedOpacity = 0.6
    /// Labels stop growing here (Large Content Viewer from `.accessibility1`); so does the bar.
    nonisolated static let maxLabelSize = DynamicTypeSize.xxLarge
    /// The container's identifier for UI tests.
    nonisolated static let identifier = "tab.bar"

    /// The bar as drawn at the default size over a home-indicator inset: 44 + 34 = 78 on a phone with an indicator.
    static func height(bottomInset: CGFloat) -> CGFloat { contentHeight + bottomInset }

    /// The dot's colour and the label's weight change in 250 ms; under Reduce Motion they jump.
    static func selectionAnimation(reduceMotion: Bool) -> Animation? { Theme.Motion.respecting(reduceMotion) }

    let items: [Item]
    let selection: Tab
    let select: (Tab) -> Void
    /// Tapping the selected item: back to the root, scrolled to the top (the system bar did both).
    var reselect: (Tab) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                tabButton(item, index: index)
            }
        }
        .padding(.horizontal, Self.sidePadding)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            Theme.background.ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Theme.separator.frame(height: Theme.Metrics.hairline) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tab bar", comment: "VoiceOver: the container of the five tabs."))
        .accessibilityIdentifier(Self.identifier)
    }

    private func tabButton(_ item: Item, index: Int) -> some View {
        let isSelected = item.tab == selection
        return Button {
            if isSelected { reselect(item.tab) } else { select(item.tab) }
        } label: {
            VStack(spacing: Self.dotGap) {
                Circle()
                    .fill(isSelected ? Theme.signal : Theme.textPrimary.opacity(Self.unselectedDotOpacity))
                    .frame(width: Self.dot, height: Self.dot)
                TabItemLabel(title: Text(item.title), selected: isSelected)
                    .dynamicTypeSize(...Self.maxLabelSize)
            }
            .padding(.top, Self.topPadding)
            .padding(.bottom, Self.bottomPadding)
            .frame(maxWidth: .infinity, minHeight: Self.minItemSize)
            .frame(minWidth: Self.minItemSize)
            .contentShape(Rectangle())
            .animation(Self.selectionAnimation(reduceMotion: reduceMotion), value: isSelected)
        }
        .buttonStyle(TabItemStyle())
        .accessibilityLabel(Text(item.title))
        .accessibilityValue(Text("Tab \(index + 1) of \(items.count)", comment: "VoiceOver value of a tab: its position."))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(item.identifier)
        .accessibilityShowsLargeContentViewer { Text(item.title) }
    }
}

extension RyftTabBar {
    /// 11 pt (`.tab`), Medium when selected: a second cue besides brightness and the dot (D5-16). Without Satoshi, SF Pro
    /// Rounded at the same weights.
    static func labelFont(selected: Bool) -> Font {
        guard selected else { return .ryft(.tab) }
        let name = RyftFonts.postScriptName(for: .medium)
        guard RyftFonts.isAvailable(name) else { return .system(.caption2, design: .rounded).weight(.medium).monospacedDigit() }
        return .custom(name, size: RyftTextStyle.tab.size, relativeTo: .caption2).monospacedDigit()
    }
}

// MARK: the host

extension View {
    /// On a `TabView` (design.md §P5-2): draws `bar` over the bottom edge, after the tabs for VoiceOver, and tells each tab
    /// marked `ryftTab()` how far up the bar reaches. Not a `safeAreaInset` (the spec's first plan): on iOS 27.2 a safe area
    /// added outside the `TabView` doesn't reach its tabs, and VoiceOver reads an inset before the tab's content. The
    /// keyboard covers the bar, as it covered the system bar.
    func ryftTabBar(_ bar: RyftTabBar) -> some View {
        modifier(RyftTabBarHost(bar: bar))
    }

    /// A tab's root inside a `TabView` with `ryftTabBar(_:)`: the system tab bar hidden, and the tab ending at the bar's top,
    /// so its content, pushed screens included, scrolls to an end above the bar. Put it outside the tab's stack: it shortens
    /// the tab (`padding`), because a safe area added outside a `NavigationStack` doesn't reach the stack's screens. The
    /// keyboard still takes its part of the tab's safe area, so a focused field ends above it.
    func ryftTab() -> some View {
        modifier(RyftTabContent())
    }
}

extension EnvironmentValues {
    /// How far the tab bar reaches up from the host's bottom edge: its content and the home-indicator inset under it.
    /// `ryftTab()` shortens the tab by it. 0 outside a tab host.
    @Entry var ryftTabBarRoom: CGFloat = 0
}

extension RyftTabBar {
    /// The room a tab leaves for the bar: from the bar's top (`barTop`) down to the host's bottom edge (`hostBottom`), both
    /// in one space; 78 on a phone with a home indicator, 44 without one. The keyboard doesn't change it: it covers the bar.
    nonisolated static func room(hostBottom: CGFloat, barTop: CGFloat) -> CGFloat {
        max(0, hostBottom - barTop)
    }
}

private struct RyftTabBarHost: ViewModifier {
    let bar: RyftTabBar
    /// The host's bottom edge and the bar's top, in the window; until they are measured, a 44 pt room.
    @State private var hostBottom: CGFloat = 0
    @State private var barTop = -RyftTabBar.contentHeight

    func body(content: Content) -> some View {
        content
            .environment(\.ryftTabBarRoom, RyftTabBar.room(hostBottom: hostBottom, barTop: barTop))
            .background {
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }, action: { hostBottom = $0 })
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottom) {
                bar
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }, action: { barTop = $0 })
                    // The keyboard covers the bar; it doesn't lift it.
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    // After the tab's content for VoiceOver, as the system bar was.
                    .accessibilitySortPriority(-1)
            }
    }
}

private struct RyftTabContent: ViewModifier {
    @Environment(\.ryftTabBarRoom) private var room

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .padding(.bottom, room)
    }
}

/// The label in its line box (`labelLine`, scaled with the label up to the bar's cap), so the item is 44 high at the
/// default size whichever face draws it.
private struct TabItemLabel: View {
    let title: Text
    let selected: Bool
    @ScaledMetric(relativeTo: .caption2) private var line = RyftTabBar.labelLine

    var body: some View {
        title
            .font(RyftTabBar.labelFont(selected: selected))
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .lineLimit(1)
            .frame(height: line)
    }
}

private struct TabItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? RyftTabBar.pressedOpacity : 1)
    }
}

// MARK: previews (dark only; design.md §P5-11: five selected states, AX3, the keyboard up)

/// The bar under a page, on the screen colour, with `selection` selected; taps move it.
private struct RyftTabBarPreview: View {
    @State var selection: AppTab

    var body: some View {
        Theme.background
            .ignoresSafeArea()
            .ryftTabBar(RyftTabBar(items: RyftTabBar.appTabs, selection: selection.rawValue,
                                   select: { selection = AppTab(rawValue: $0) ?? selection }))
            .environment(\.colorScheme, .dark)
    }
}

#Preview("RyftTabBar · Today") { RyftTabBarPreview(selection: .today) }
#Preview("RyftTabBar · Sleep") { RyftTabBarPreview(selection: .sleep) }
#Preview("RyftTabBar · Strain") { RyftTabBarPreview(selection: .strain) }
#Preview("RyftTabBar · Insights") { RyftTabBarPreview(selection: .insights) }
#Preview("RyftTabBar · Profile") { RyftTabBarPreview(selection: .profile) }

#Preview("RyftTabBar · AX3") {
    RyftTabBarPreview(selection: .insights)
        .environment(\.dynamicTypeSize, .accessibility3)
}

/// A focused field over the bar: the keyboard covers the bar (run the preview live).
private struct RyftTabBarKeyboardPreview: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack {
            TextField(text: $text) { Text(verbatim: "Name") }
                .focused($focused)
                .padding()
                .background(Theme.surface)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .ryftTabBar(RyftTabBar(items: RyftTabBar.appTabs, selection: AppTab.profile.rawValue, select: { _ in }))
        .onAppear { focused = true }
        .environment(\.colorScheme, .dark)
    }
}

#Preview("RyftTabBar · keyboard up") { RyftTabBarKeyboardPreview() }
