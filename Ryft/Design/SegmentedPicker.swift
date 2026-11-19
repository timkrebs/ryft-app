// The segmented control ("Day · Week · Month"). Two looks: PR 4's capsule (44 pt segments on a raised capsule, Sleep → Day
// today) and Nocturne's ink fill (docs/work/2026-11-16-nocturne/design.md §P5-7.1: 34 pt segments in a 40 pt `surface`
// control, the selected one filled with ink). The capsule stays the default until Sleep's modes move (T5.5), so Sleep → Day
// keeps its layout; Insights and Sleep opt in with `look: .inkFill`.
import SwiftUI

/// The control's numbers (a separate, non-generic type: `SegmentedPicker` is generic).
enum SegmentedPickerSpec {
    enum Look: Equatable, Sendable {
        /// PR 4's: `surface` capsule, 44 pt segments, `.callout`, the selection a `surfaceRaised` capsule, others `textSecondary`.
        case capsule
        /// §P5-7.1: `surface`, radius 20, 40 high; segments 34 high, radius 17, `.label`; the selection `textPrimary` with
        /// `background` text (17.35:1), others `textTertiary` (4.54:1 on `surface`).
        case inkFill
    }

    enum Width: Equatable, Sendable {
        /// Equal segments across the available width (Sleep).
        case fill
        /// Each segment as wide as its title plus 12 a side (Insights' header, about 168 for three); full width from AX1.
        case content
    }

    // .inkFill
    static let padding: CGFloat = 3, gap: CGFloat = 4
    static let controlRadius: CGFloat = 20, controlHeight: CGFloat = 40
    static let segmentHeight: CGFloat = 34, segmentRadius: CGFloat = 17
    /// From AX1 the control (under its title, full width) is 44 high: its segments are at least 38 (§P5-5.1).
    static let accessibilitySegmentHeight: CGFloat = 38
    /// A segment's text inset at each side (`.content`), and its least width.
    static let segmentInset: CGFloat = 12, minSegmentWidth = Theme.Metrics.minHitTarget
    /// A segment's tap box is 44 high: it reaches 5 above and below the 34 pt segment, 2 past the control's edge.
    static let hitHeight = Theme.Metrics.minHitTarget

    // .capsule (PR 4)
    static let capsulePadding: CGFloat = 4, capsuleGap: CGFloat = 4

    /// The AX1+ menu (§P5-7.1, `SegmentedMenu`): `surface`, radius 20, 44 high.
    static let menuHeight = Theme.Metrics.minHitTarget, menuRadius: CGFloat = 20
}

/// A row of segments, one selected. VoiceOver: a container of buttons, the selected one with the selected trait; `spokenTitle`
/// gives a segment a fuller name ("7 days" for "7 D").
struct SegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let look: SegmentedPickerSpec.Look
    let width: SegmentedPickerSpec.Width
    let spokenTitle: ((Value) -> String)?
    let title: (Value) -> String

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - look: `.capsule` (PR 4's, the default until T5.5) or `.inkFill` (§P5-7.1).
    ///   - width: `.inkFill` only; `.capsule` always fills.
    init(selection: Binding<Value>, options: [Value], look: SegmentedPickerSpec.Look = .capsule,
         width: SegmentedPickerSpec.Width = .fill, spokenTitle: ((Value) -> String)? = nil,
         title: @escaping (Value) -> String) {
        _selection = selection
        self.options = options
        self.look = look
        self.width = width
        self.spokenTitle = spokenTitle
        self.title = title
    }

    var body: some View {
        switch look {
        case .capsule: capsule
        case .inkFill: inkFill
        }
    }

    private func choose(_ option: Value) {
        withAnimation(Theme.Motion.respecting(reduceMotion)) { selection = option }
    }

    // MARK: .capsule (PR 4, unchanged)

    private var capsule: some View {
        HStack(spacing: SegmentedPickerSpec.capsuleGap) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    choose(option)
                } label: {
                    Text(title(option))
                        .font(.ryft(.callout))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minHitTarget)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Theme.surfaceRaised)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(spokenTitle?(option) ?? title(option)))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(SegmentedPickerSpec.capsulePadding)
        .background(Theme.surface, in: Capsule())
        .accessibilityElement(children: .contain)
    }

    // MARK: .inkFill (§P5-7.1)

    /// `.content` fills from AX1, where the control has its own line under the title.
    private var fills: Bool { width == .fill || typeSize.isAccessibilitySize }

    private var inkFill: some View {
        let segmentHeight = typeSize.isAccessibilitySize ? SegmentedPickerSpec.accessibilitySegmentHeight
            : SegmentedPickerSpec.segmentHeight
        let reach = max(0, (SegmentedPickerSpec.hitHeight - segmentHeight) / 2)
        return HStack(spacing: SegmentedPickerSpec.gap) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    choose(option)
                } label: {
                    Text(title(option))
                        .font(.ryft(.label))
                        .foregroundStyle(isSelected ? Theme.background : Theme.textTertiary)
                        .lineLimit(1)
                        .padding(.horizontal, SegmentedPickerSpec.segmentInset)
                        .frame(minWidth: SegmentedPickerSpec.minSegmentWidth, maxWidth: fills ? .infinity : nil,
                               minHeight: segmentHeight)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: SegmentedPickerSpec.segmentRadius, style: .continuous)
                                    .fill(Theme.textPrimary)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        // The 44 pt tap box: the segment and 5 above and below it (3 from AX1).
                        .padding(.vertical, reach)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(spokenTitle?(option) ?? title(option)))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, SegmentedPickerSpec.padding)
        // The control is 40 (44 from AX1): the tap boxes reach 2 past its top and bottom edges (none from AX1).
        .padding(.vertical, SegmentedPickerSpec.padding - reach)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: SegmentedPickerSpec.controlRadius, style: .continuous))
        .fixedSize(horizontal: !fills, vertical: false)
        .accessibilityElement(children: .contain)
    }
}

/// The picker as one row from AX1 (§P5-7.1, PR 4's Sleep menu restyled), where segments would cut their titles: a `Menu` with the
/// current value and a chevron, `.label` `textPrimary` on `surface`, radius 20, 44 high, full width; its items have the
/// checkmark on the current one. Sleep's modes (T5.5) and any other picker that must not wrap use it. VoiceOver hears what the
/// menu picks, then the current value ("Range, Week"), not the value alone.
struct SegmentedMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    /// What the menu picks ("Range"): its VoiceOver label; the current value is its VoiceOver value.
    let label: Text
    let title: (Value) -> String

    init(selection: Binding<Value>, options: [Value], label: Text, title: @escaping (Value) -> String) {
        _selection = selection
        self.options = options
        self.label = label
        self.title = title
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SegmentedPickerSpec.menuRadius, style: .continuous)
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(title(option), systemImage: "checkmark")
                    } else {
                        Text(title(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title(selection))
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(.ryft(.label))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, SegmentedPickerSpec.segmentInset)
            .frame(maxWidth: .infinity, minHeight: SegmentedPickerSpec.menuHeight)
            .background(Theme.surface, in: shape)
            .contentShape(shape)
        }
        .accessibilityLabel(label)
        .accessibilityValue(Text(title(selection)))
    }
}

// MARK: previews

private struct SegmentedPickerPreview: View {
    @State private var mode = "Day"
    @State private var range = "30 D"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: "capsule (PR 4, the default)").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
            SegmentedPicker(selection: $mode, options: ["Day", "Week", "Month", "Bedtime"]) { $0 }
            Text(verbatim: "inkFill · fill").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
            SegmentedPicker(selection: $mode, options: ["Day", "Week", "Month", "Bedtime"], look: .inkFill) { $0 }
            Text(verbatim: "inkFill · content").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
            HStack {
                Text(verbatim: "Insights").font(.ryft(.title)).foregroundStyle(Theme.textPrimary)
                Spacer()
                SegmentedPicker(selection: $range, options: ["7 D", "30 D", "90 D"], look: .inkFill, width: .content,
                                spokenTitle: { "\($0.dropLast(2)) days" }) { $0 }
            }
            Text(verbatim: "menu (AX1+)").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
            SegmentedMenu(selection: $mode, options: ["Day", "Week", "Month", "Bedtime"], label: Text(verbatim: "Range")) { $0 }
        }
    }
}

#Preview("SegmentedPicker", traits: .sizeThatFitsLayout) {
    DarkPreview { SegmentedPickerPreview() }
}

#Preview("SegmentedPicker · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { SegmentedPickerPreview() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
