// Where a row came from (ui.md §2.3; Nocturne, docs/work/2026-11-16-nocturne/design-pr6-b-train.md §9.1 and S6, the `b-17` and
// `b-18` drafts): a quiet outline capsule with the source's name, on a row's second meta line. Names only: no vendor's logo and,
// since Nocturne, no glyph (the row's disc already shows the sport).
import SwiftUI

/// The badge's numbers (B §9.1).
enum SourceBadgeSpec {
    /// At least 22 high (it grows with a wrapped name at large sizes), 8 at the sides.
    nonisolated static let minHeight: CGFloat = 22, horizontalPadding: CGFloat = 8
    /// Two lines' worth of padding when the name wraps (accessibility sizes).
    nonisolated static let verticalPadding: CGFloat = 3
    /// The outline: 1 pt ink at 12 %; at 35 % with Increase Contrast (the 3:1 of a boundary).
    nonisolated static let outlineOpacity = 0.12, increasedContrastOpacity = 0.35
    /// Between two badges, and between two lines of them.
    nonisolated static let spacing: CGFloat = 6
}

/// An outline capsule, at least 22 high: the name in `axis` (11) `textTertiary` (4.54:1 on `surface`), 8 at the sides, a 1 pt
/// outline at ink 12 %. No fill, so it reads the same on a tile, in a card and on the screen. One line, middle-truncated; from
/// the accessibility sizes on up to two lines, never cut in the middle. The row it sits in speaks its sources.
struct SourceBadge: View {
    /// The name as shown: a tracker's display name verbatim, or RYFT's own wording, already localized.
    let title: String

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(verbatim: title)
            .font(.ryft(.axis))
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            .truncationMode(typeSize.isAccessibilitySize ? .tail : .middle)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, SourceBadgeSpec.horizontalPadding)
            .padding(.vertical, SourceBadgeSpec.verticalPadding)
            .frame(minHeight: SourceBadgeSpec.minHeight)
            .overlay {
                Capsule().strokeBorder(Theme.textPrimary.opacity(contrast == .increased ? SourceBadgeSpec.increasedContrastOpacity
                                                                                          : SourceBadgeSpec.outlineOpacity),
                                       lineWidth: Theme.Metrics.hairline)
            }
    }
}

extension SourceBadge {
    init(_ source: MyDayItem.Source) {
        self.init(title: source.title)
    }
}

extension MyDayItem.Source {
    /// The badge's words (ui.md §2.3): RYFT's name, "Added by you", Train, or the tracker's display name.
    var title: String {
        switch self {
        case .ryftRecorded, .ryft: return "RYFT"
        case .ryftManual, .addedByYou: return String(localized: "Added by you", comment: "Source badge: typed in by the user.")
        case .tracker(let name, _): return name
        case .train: return String(localized: "Train")
        }
    }

    /// The source's glyph (ui.md §2.3). The Nocturne badge draws the name only (B §9.1); the glyph stays the model's answer to
    /// "what kind of source", for a view that shows one.
    var glyph: String {
        switch self {
        // Without GPS (an indoor run, yoga…) a neutral "recorded" mark: the row's icon already shows the sport.
        case .ryftRecorded(let indoor): return indoor ? "record.circle" : "location.fill"
        case .ryftManual, .addedByYou: return "pencil"
        // An origin this build doesn't know: the neutral "unknown source" glyph (ui.md §2.3).
        case .ryft: return "ellipsis.circle"
        case .tracker(_, let symbol): return symbol
        case .train: return "dumbbell.fill"
        }
    }
}

/// Badges by name, side by side 6 apart, wrapping to the next line where they don't fit (AX sizes, narrow rows).
/// `ActivityListRow` puts it on its second meta line and speaks the sources in the row's sentence.
struct SourceBadgeRow: View {
    let titles: [String]

    var body: some View {
        FlowLayout(spacing: SourceBadgeSpec.spacing, lineSpacing: SourceBadgeSpec.spacing) {
            ForEach(Array(titles.enumerated()), id: \.offset) { _, title in
                SourceBadge(title: title)
            }
        }
    }
}

/// A row's sources on their own (the activity detail): the badges, read by VoiceOver as one element, "Sources: Garmin Connect
/// and RYFT, merged".
struct SourceBadges: View {
    let sources: [MyDayItem.Source]
    /// The platform merged the row's activity with a tracker's workout.
    var merged = false

    var body: some View {
        SourceBadgeRow(titles: sources.map(\.title))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Self.spoken(sources, merged: merged)))
    }

    /// "Source: Garmin Connect", "Sources: Garmin Connect and RYFT, merged".
    static func spoken(_ sources: [MyDayItem.Source], merged: Bool) -> String {
        let names = sources.map(\.title).formatted(.list(type: .and))
        switch sources.count {
        case 0: return ""
        case 1: return String(localized: "Source: \(names)", comment: "VoiceOver: where a My Day row came from.")
        default:
            return merged
                ? String(localized: "Sources: \(names), merged", comment: "VoiceOver: an activity the platform combined with a tracker's workout.")
                : String(localized: "Sources: \(names)", comment: "VoiceOver: where a My Day row came from.")
        }
    }
}

/// Lays its subviews out left to right and wraps them onto new lines, leading-aligned.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: size.width, height: size.height))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Greedy lines; a subview wider than the line gets the line to itself, measured at the line's width (it
    /// wraps or truncates there).
    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            row.sizes.append(size)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - previews (dark only)

private struct SourceBadgesPreviewList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SourceBadges(sources: [.tracker(name: "Garmin Connect", symbol: "watch.analog"), .ryftRecorded(indoor: false)],
                         merged: true)
            SourceBadges(sources: [.tracker(name: "Alex's Apple Watch", symbol: "applewatch"), .train])
            SourceBadges(sources: [.ryftManual])
            SourceBadges(sources: [.tracker(name: "Oura", symbol: "circle.circle")])
            SourceBadges(sources: [.tracker(name: MyDayAssembler.appleHealth, symbol: MyDayAssembler.appleHealthSymbol)])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Source badges", traits: .sizeThatFitsLayout) {
    DarkPreview { SourceBadgesPreviewList() }
}

#Preview("Source badges · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { SourceBadgesPreviewList().frame(width: 240, alignment: .leading) }
        .environment(\.dynamicTypeSize, .accessibility3)
}
