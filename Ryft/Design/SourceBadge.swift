import SwiftUI

/// Where a row came from (ui.md §2.3): a quiet capsule with the source's glyph and name. Names only, never a
/// vendor's logo; Apple's silhouettes only for the Apple Watch and the iPhone themselves (`Tracker.symbol`).
struct SourceBadge: View {
    /// The name as shown: a tracker's display name verbatim, or RYFT's own wording, already localized.
    let title: String
    let glyph: String

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: glyph)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            // One line, middle-truncated; from the accessibility sizes on up to two lines, never cut in the middle.
            Text(verbatim: title)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(typeSize.isAccessibilitySize ? .tail : .middle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.surfaceRaised, in: Capsule())
        // The outline carries the capsule on light surfaces, and in dark with Increase Contrast.
        .overlay {
            if scheme == .light || contrast == .increased {
                Capsule().strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline)
            }
        }
    }
}

extension SourceBadge {
    init(_ source: MyDayItem.Source) {
        self.init(title: source.title, glyph: source.glyph)
    }
}

extension MyDayItem.Source {
    /// The badge's words (ui.md §2.3): RYFT's name, "Added by you", Train, or the tracker's display name.
    var title: String {
        switch self {
        case .ryftRecorded: return "RYFT"
        case .ryftManual, .addedByYou: return String(localized: "Added by you", comment: "Source badge: typed in by the user.")
        case .tracker(let name, _): return name
        case .train: return String(localized: "Train")
        }
    }

    var glyph: String {
        switch self {
        // Without GPS (an indoor run, yoga…) a neutral "recorded" mark: the row's icon already shows the sport.
        case .ryftRecorded(let indoor): return indoor ? "record.circle" : "location.fill"
        case .ryftManual, .addedByYou: return "pencil"
        case .tracker(_, let symbol): return symbol
        case .train: return "dumbbell.fill"
        }
    }
}

/// One to a few badges side by side, 6 pt apart, wrapping to the next line where they don't fit (AX sizes,
/// narrow rows). VoiceOver reads them as one: "Sources: Garmin Connect and RYFT, merged".
struct SourceBadges: View {
    let sources: [MyDayItem.Source]
    /// The platform merged the row's activity with a tracker's workout.
    var merged = false

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                SourceBadge(source)
            }
        }
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

#Preview("Source badges", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 12) {
            SourceBadges(sources: [.tracker(name: "Garmin Connect", symbol: "watch.analog"), .ryftRecorded(indoor: false)],
                         merged: true)
            SourceBadges(sources: [.tracker(name: "Tim's Apple Watch", symbol: "applewatch"), .train])
            SourceBadges(sources: [.ryftManual])
            SourceBadges(sources: [.ryftRecorded(indoor: true)])
            SourceBadges(sources: [.tracker(name: "Oura", symbol: "circle.circle")])
            SourceBadges(sources: [.tracker(name: MyDayAssembler.appleHealth, symbol: MyDayAssembler.appleHealthSymbol)])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Source badges · AX3 · de", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 12) {
            SourceBadges(sources: [.tracker(name: "Garmin Connect", symbol: "watch.analog"), .ryftRecorded(indoor: false)],
                         merged: true)
            SourceBadges(sources: [.ryftManual])
        }
        .frame(width: 240, alignment: .leading)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
    .environment(\.locale, Locale(identifier: "de"))
}
