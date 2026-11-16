// A row of day dots (Nocturne, docs/work/2026-11-16-nocturne/design.md §P2-4): one per night or day, left to right.
// Full and missed differ by shape (fill or outline), not colour; `today` is the Volt position marker, put last.
import SwiftUI

/// Dots of 6 pt with a 4 pt gap, in one row. One accessibility element: the caller's summary ("Slept enough on 5 of
/// the last 7 nights; tonight is marked"), which names today because Volt and `textPrimary` have the same luminance.
struct DotRow: View {
    enum Mark { case full, missed, today }

    /// Dot diameter, the gap between dots, the missed dot's outline (`textPrimary` at 50 %, 1 pt).
    nonisolated static let dot: CGFloat = 6, gap: CGFloat = 4, outlineOpacity = 0.5
    static let outlineWidth: CGFloat = 1

    private let marks: [Mark]
    private let accessibilityLabel: Text

    init(_ marks: [Mark], accessibilityLabel: Text) {
        self.marks = marks
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                dot(mark).frame(width: Self.dot, height: Self.dot)
            }
        }
        .frame(width: Self.size(count: marks.count).width, height: Self.size(count: marks.count).height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private func dot(_ mark: Mark) -> some View {
        switch mark {
        case .full: Circle().fill(Theme.textPrimary)
        case .missed: Circle().strokeBorder(Theme.textPrimary.opacity(Self.outlineOpacity), lineWidth: Self.outlineWidth)
        case .today: Circle().fill(Theme.signal)
        }
    }

    /// `(n·6 + (n−1)·4) × 6`; no dots, no size.
    nonisolated static func size(count: Int) -> CGSize {
        guard count > 0 else { return .zero }
        return CGSize(width: CGFloat(count) * dot + CGFloat(count - 1) * gap, height: dot)
    }
}

#Preview("DotRow", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 16) {
            DotRow(Array(repeating: .full, count: 7), accessibilityLabel: Text("Slept enough on 7 of the last 7 nights"))
            DotRow([.full, .missed, .full, .full, .missed, .full, .today],
                   accessibilityLabel: Text("Slept enough on 4 of the last 6 nights; tonight is marked"))
            DotRow(Array(repeating: .missed, count: 7), accessibilityLabel: Text("Slept enough on none of the last 7 nights"))
            DotRow([.today], accessibilityLabel: Text("Tonight is marked"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("DotRow · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        DotRow([.full, .missed, .full, .full, .missed, .full, .today],
               accessibilityLabel: Text("Slept enough on 4 of the last 6 nights; tonight is marked"))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
