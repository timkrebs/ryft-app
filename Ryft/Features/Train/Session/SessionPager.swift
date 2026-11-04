import SwiftUI

/// The paging container, and the only file that knows which one it is. Contract: `pages` in order, `selection` the page
/// on screen, a builder per page, `onDrag` for any finger on it. Going to a paging `ScrollView` is this file plus a
/// `scrollTo` on an order change (architecture.md §6).
///
/// `TabView(.page)` won the probe on iOS 27: it follows the id through a reorder, writes nothing on a programmatic move
/// and keeps only the current page in the accessibility tree. It has had no run on iOS 17 yet: that run is a condition
/// for turning `train.focused_session` on (L15).
struct SessionPager<Page: View>: View {
    let pages: [UUID]
    @Binding var selection: UUID?
    var onDrag: () -> Void
    @ViewBuilder var page: (UUID) -> Page

    var body: some View {
        TabView(selection: $selection) {
            ForEach(pages, id: \.self) { id in
                page(id)
                    .accessibilityHidden(id != selection)
                    .tag(Optional(id))
            }
        }
        // The strip is the page indicator.
        .tabViewStyle(.page(indexDisplayMode: .never))
        // A swipe writes `selection` at its halfway point, so the planner's window starts from the first drag event. Both
        // axes count, as in List. iOS 18's scroll phase can't see a `TabView`, so this is a plain drag on every version.
        .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in onDrag() })
    }
}

private struct SessionPagerPreview: View {
    @State private var selection: UUID?
    private let pages = [UUID(), UUID(), UUID()]

    var body: some View {
        SessionPager(pages: pages, selection: $selection, onDrag: {}) { id in
            VStack(spacing: 8) {
                Text("Page \((pages.firstIndex(of: id) ?? 0) + 1)")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                Text("Swipe sideways")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: 240)
        .background(Theme.background)
        .onAppear { selection = pages.first }
    }
}

#Preview("Pager · dark") {
    SessionPagerPreview().previewEnvironment()
}

#Preview("Pager · light") {
    SessionPagerPreview().previewEnvironment(scheme: .light)
}
