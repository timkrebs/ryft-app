import SwiftUI
import UIKit

/// The tiles of "What do you wear?" (ui.md §2.2; Nocturne PR 6 A §A-11): two columns 10 apart, "Other" and "Just my iPhone"
/// full width and last, each a `SelectableTile` (selected: the 1.5 pt ink border and the filled check, never colour alone).
/// One column at accessibility sizes, and whenever a name's longest word wouldn't fit a tile on this screen at
/// this text size (a word is never broken). Several may be picked; "Just my iPhone" only on its own. Profile's
/// `TrackerPickerSheet` shows the same grid.
struct TrackerPickerGrid: View {
    let catalog: TrackerCatalog
    @Binding var picked: [String]

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0

    /// Full-width rows at the end.
    private static let wide = ["other", TrackerSelectionStore.iPhone]
    static let gap: CGFloat = 10

    private var regular: [Tracker] { catalog.trackers.filter { !Self.wide.contains($0.id) } }
    private var wide: [Tracker] { Self.wide.compactMap(catalog.tracker) }

    var body: some View {
        VStack(spacing: Self.gap) {
            if Self.fitsTwoColumns(regular.map(\.title), width: width, size: typeSize) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: 2), spacing: Self.gap) {
                    ForEach(regular) { tile($0) }
                }
            } else {
                ForEach(regular) { tile($0) }
            }
            ForEach(wide) { tile($0) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("What do you wear?"))
        .accessibilityHint(Text("Choose all that apply"))
    }

    /// Two columns while every word of every name fits a tile's room at `size` (not at accessibility sizes).
    /// Before the width is known, as at the default size.
    static func fitsTwoColumns(_ names: [String], width: CGFloat, size: DynamicTypeSize) -> Bool {
        guard !size.isAccessibilitySize else { return false }
        guard width > 0 else { return true }
        let room = (width - gap) / 2 - SelectableTile.chrome(size)
        return widestWord(names, size: size) <= room - 1
    }

    /// The widest single word among `names` in the tiles' font (Satoshi callout, 15 pt, scaled like `.ryft(.callout)`).
    static func widestWord(_ names: [String], size: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        let points = RyftTextStyle.callout.size
        let base = UIFont(name: RyftFonts.postScriptName(for: RyftTextStyle.callout.weight), size: points)
            ?? .systemFont(ofSize: points)
        let font = UIFontMetrics(forTextStyle: .callout).scaledFont(for: base, compatibleWith: traits)
        let words = names.flatMap { $0.split(whereSeparator: \.isWhitespace) }
        return words.map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    }

    private func tile(_ tracker: Tracker) -> some View {
        SelectableTile(symbol: tracker.symbol, title: tracker.title, isSelected: picked.contains(tracker.id),
                       hint: tracker.id == TrackerSelectionStore.iPhone ? "Clears your other choices" : nil) {
            let next = TrackerSelectionStore.toggled(tracker.id, in: picked)
            withAnimation(Theme.Motion.respecting(reduceMotion)) { picked = next.picked }
            if next.cleared {
                AccessibilityNotification.Announcement(String(localized: "Other choices cleared")).post()
            }
        }
        .accessibilityIdentifier("wear.tile.\(tracker.id)")
    }
}
