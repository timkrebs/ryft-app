#if DEBUG
import SwiftUI

/// The catalog's "Nocturne · tab bar" section (design.md §P5-11, T5.1): the bar with each of the five tabs selected, then at
/// AX3, where the labels stop at `xxLarge`. Taps move the selection; a tap on the selected tab does nothing here. The bars
/// run edge to edge of the catalog's column, without a home-indicator inset (44 high).
struct NocturneTabBarCatalog: View {
    @State private var tapped: AppTab = .today

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                caption("selected · \(tab.rawValue)")
                bar(tab)
            }
            caption("AX3 · the labels capped at xxLarge")
            bar(.insights)
                .dynamicTypeSize(.accessibility3)
            caption("tap to select · \(tapped.rawValue)")
            RyftTabBar(items: RyftTabBar.appTabs, selection: tapped.rawValue,
                       select: { tapped = AppTab(rawValue: $0) ?? tapped })
        }
    }

    private func bar(_ selected: AppTab) -> some View {
        RyftTabBar(items: RyftTabBar.appTabs, selection: selected.rawValue, select: { _ in })
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text).font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
    }
}

#Preview("Nocturne · tab bar") {
    ScrollView {
        NocturneTabBarCatalog()
            .padding(Theme.Metrics.screenPadding)
    }
    .background(Theme.background)
    .environment(\.colorScheme, .dark)
}
#endif
