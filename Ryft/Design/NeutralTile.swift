// The neutral tile (Nocturne, docs/work/2026-11-16-nocturne/build-plan.md §2; design.md §P5-3.1 row 8, §P5-4 row 4; PR 6 B §1.3
// S5): a number on `surface` with its label and unit, for the values that are not a metric of the rings (steps, energy, a
// workout's duration and heart rate). No icon and no tint: the colours belong to the legend. Replaces `MetricTile` once
// Strain no longer uses it (T5.2 deletes it).
import SwiftUI

/// 80 high (it grows with its text), radius 22, `surface`, padding 14 / 16 / 12: the label (13, `textSecondary`) top-left, the
/// value (24 Light, `textPrimary`) bottom-left with its unit (12, `textTertiary`, 3 after) and an optional note (12,
/// `textTertiary`) at the right of the value's line. From AX1 the note goes under the value. One accessibility element: the
/// label, then the value, the unit and the note (or the caller's `accessibilityValue`). Not a button. It fills the height its
/// row gives it: a pair sits in an `HStack(spacing: 12)` with `.fixedSize(horizontal: false, vertical: true)`, so both match the
/// taller one at large sizes (in a scroll view a row gives it no more than its content).
struct NeutralTile: View {
    nonisolated static let height: CGFloat = 80
    static let radius = Theme.Metrics.neutralTileRadius
    static let padding = EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16)
    /// The value's size at the default text size; it scales with Dynamic Type like `.title2`.
    nonisolated static let valueSize: CGFloat = 24
    /// Value → unit, and the least space between the label and the value's line.
    nonisolated static let unitGap: CGFloat = 3, labelGap: CGFloat = 4
    /// The least space between the value (with its unit) and the note.
    nonisolated static let noteGap: CGFloat = 8
    /// AX1+: the value's line → the note under it.
    nonisolated static let stackedNoteGap: CGFloat = 2

    private let label: Text
    private let value: Text
    private let unit: Text?
    private let note: Text?
    private let accessibilityValue: Text?

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var scaledValueSize: CGFloat = NeutralTile.valueSize

    /// - Parameters:
    ///   - value: the number, or "–" while there is none (the caller's `Text`; `.foregroundStyle` on it wins).
    ///   - accessibilityValue: what VoiceOver reads after the label; `nil` is the value, the unit and the note.
    init(_ label: Text, value: Text, unit: Text? = nil, note: Text? = nil, accessibilityValue: Text? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
        self.note = note
        self.accessibilityValue = accessibilityValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            label
                .font(.ryft(.label))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Self.labelGap)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Self.stackedNoteGap) {
                    valueLine
                    noteText
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Self.noteGap) {
                    valueLine
                    Spacer(minLength: 0)
                    noteText
                }
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue ?? spokenValue)
    }

    private var valueLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.unitGap) {
            value
                .font(.ryftNumber(size: scaledValueSize, weight: .light))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                // A number is never cut: in a narrow column at a large size it gets smaller instead.
                .minimumScaleFactor(0.6)
            if let unit {
                unit
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder private var noteText: some View {
        if let note {
            note
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var spokenValue: Text {
        var spoken = value
        if let unit { spoken = spoken + Text(verbatim: " ") + unit }
        if let note { spoken = spoken + Text(verbatim: ", ") + note }
        return spoken
    }
}
