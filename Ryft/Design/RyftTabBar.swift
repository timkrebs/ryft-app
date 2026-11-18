// The dot tab bar (Nocturne, docs/work/2026-11-16-nocturne/design.md §P5-2, brief §1 "Tab-Leiste"): a flat bar pinned to
// the bottom, a 6 pt dot over an 11 pt label per tab, the active dot Volt. It replaces the system tab bar (hidden with
// `.toolbar(.hidden, for: .tabBar)`) and sits in the `TabView`'s bottom safe-area inset, so content ends above it.
import SwiftUI

/// Five (or any number of) items, space-around. The bar is `contentHeight` plus the home-indicator inset, on `background`
/// with a 1 pt `separator` rule on top. Selected: a Volt dot, the label in full `textPrimary` and Medium. Unselected: a
/// dot at 30 % and the label in `textTertiary`. The item is the tap target: at least 44 pt wide and as high as the bar.
/// Labels follow Dynamic Type up to `xxLarge` (the system tab bar caps its labels too); from there the Large Content
/// Viewer shows the label. Container: one accessibility group; each item is a button, "selected" when it is, with its
/// position ("Tab 2 of 5") as the value, because SwiftUI has no tab-bar trait.
struct RyftTabBar: View {
    typealias Tab = String
    struct Item {
        let tab: Tab
        let title: LocalizedStringKey
        /// `tab.today`, … for UI tests (the system bar's buttons were found by title in `app.tabBars`).
        let identifier: String
    }

    /// Board: padding 14 top, dot 6, gap 6, an 11 pt label line; 42 above the home-indicator inset (42 + 34 = the
    /// board's 76). Here 44 (bottom padding 4, not 2), so an item is a 44 pt target on a device without an indicator. Sides 16; an item is at least 44 wide.
    nonisolated static let topPadding: CGFloat = 14, dot: CGFloat = 6, dotGap: CGFloat = 6
    nonisolated static let bottomPadding: CGFloat = 4, sidePadding: CGFloat = 16, minItemWidth: CGFloat = 44
    /// The item's height at the default size: 14 + 6 + 6 + 14 (the 11 pt line) + 4, so it is a 44 pt target.
    nonisolated static let contentHeight: CGFloat = 44
    nonisolated static let unselectedDotOpacity = 0.30
    /// Labels stop growing here (Large Content Viewer from `.accessibility1`).
    nonisolated static let maxLabelSize = DynamicTypeSize.xxLarge

    let items: [Item]
    let selection: Tab
    let select: (Tab) -> Void
    /// Tapping the selected item: scroll to the top / pop to the root (the system bar did both).
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
                Text(item.title)
                    .font(Self.labelFont(selected: isSelected))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                    .dynamicTypeSize(...Self.maxLabelSize)
            }
            .padding(.top, Self.topPadding)
            .padding(.bottom, Self.bottomPadding)
            .frame(maxWidth: .infinity, minHeight: Self.contentHeight)
            .frame(minWidth: Self.minItemWidth)
            .contentShape(Rectangle())
            .animation(Theme.Motion.respecting(reduceMotion), value: isSelected)
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
    /// 11 pt (`.tab`), Medium when selected: a second cue besides brightness and the dot.
    static func labelFont(selected: Bool) -> Font {
        let name = RyftFonts.postScriptName(for: .medium)
        guard selected, RyftFonts.isAvailable(name) else { return .ryft(.tab) }
        return .custom(name, size: RyftTextStyle.tab.size, relativeTo: .caption2).monospacedDigit()
    }
}

private struct TabItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

#Preview("RyftTabBar") {
    struct Demo: View {
        @State var tab = "today"
        var body: some View {
            VStack(spacing: 0) {
                Spacer()
                RyftTabBar(items: [
                    .init(tab: "today", title: "Today", identifier: "tab.today"),
                    .init(tab: "sleep", title: "Sleep", identifier: "tab.sleep"),
                    .init(tab: "strain", title: "Strain", identifier: "tab.strain"),
                    .init(tab: "insights", title: "Insights", identifier: "tab.insights"),
                    .init(tab: "profile", title: "Profile", identifier: "tab.profile"),
                ], selection: tab, select: { tab = $0 })
            }
            .frame(width: 390, height: 300)
            .background(Theme.background)
        }
    }
    return Demo().environment(\.colorScheme, .dark)
}

#Preview("RyftTabBar · AX3") {
    RyftTabBar(items: [
        .init(tab: "0", title: "Today", identifier: "tab.today"),
        .init(tab: "1", title: "Sleep", identifier: "tab.sleep"),
        .init(tab: "2", title: "Strain", identifier: "tab.strain"),
        .init(tab: "3", title: "Insights", identifier: "tab.insights"),
        .init(tab: "4", title: "Profile", identifier: "tab.profile"),
    ], selection: "3", select: { _ in })
    .frame(width: 390)
    .background(Theme.background)
    .environment(\.colorScheme, .dark)
    .environment(\.dynamicTypeSize, .accessibility3)
}
