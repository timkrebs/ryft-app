// The stepper (Nocturne, docs/work/2026-11-16-nocturne/build-plan.md §2; PR 6 B S8; C §4.11, D6C-14): two `CircleButton`s,
// "−" and "+", around the value. Inline in a row (`RyftStepper`, `RyftStepperRow`: a plan's days per week, a set count, the
// Journal's drinks) the value is a 22 pt number; in an editor sheet (`HeroStepper`) it is the page's `DotNumeral`. Either way
// VoiceOver meets one adjustable element: swipe up and down to change it. It replaces `TargetStepper`'s tinted keys,
// `SettingStepper`'s raised discs and the system `Stepper`.
import SwiftUI

/// The stepper's numbers and its arithmetic.
enum RyftStepperSpec {
    /// The inline value: 22 pt (Light from 20 up, `RyftFonts.lightFloor`), at least 28 wide so "4" and "12" keep the circles
    /// where they are. A number in a row is fixed: it does not grow with the text (B §12).
    static let valueSize: CGFloat = 22
    static let valueMinWidth: CGFloat = 28
    /// Circle → value → circle, inline.
    static let spacing: CGFloat = 12
    /// A row that holds a stepper: 56 (B §1.3).
    static let rowMinHeight: CGFloat = 56
    /// Circle → numeral → circle in an editor (C §4.11), and the circles' gap when they go under the numeral.
    static let heroSpacing: CGFloat = 18
    static let heroStackedGap: CGFloat = 12

    /// `value` moved one `step` in `direction` (−1 or +1), kept in `range`.
    static func stepped(_ value: Int, direction: Int, step: Int, in range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value + direction.signum() * step))
    }

    /// VoiceOver's value: the value, and at either end of the range that it is the end ("2, minimum").
    static func spokenValue(_ value: String, canDecrement: Bool, canIncrement: Bool) -> String {
        if !canDecrement {
            return String(localized: "\(value), minimum",
                          comment: "VoiceOver value of a stepper at its lowest. 1: value.")
        }
        if !canIncrement {
            return String(localized: "\(value), maximum",
                          comment: "VoiceOver value of a stepper at its highest, e.g. 15:00 rest. 1: value.")
        }
        return value
    }

    /// The circles' labels, which their Large Content Viewer shows. The stepper is one adjustable element
    /// (`stepperAccessibility` ignores its children), so neither VoiceOver nor Voice Control reaches a circle: VoiceOver
    /// adjusts the element by swiping up and down, and Voice Control knows the element by the stepper's label.
    static var decrementLabel: Text { Text("Less", comment: "The minus circle of a stepper: makes the value smaller.") }
    static var incrementLabel: Text { Text("More", comment: "The plus circle of a stepper: makes the value larger.") }
}

/// What a stepper shows and does, shared by its three looks.
struct RyftStepperValue {
    /// The value as drawn ("4", "3:00", "62.5").
    let text: String
    /// As VoiceOver reads it when that differs from the text ("3 minutes"); the text when nil.
    var spoken: String?
    let canDecrement: Bool
    let canIncrement: Bool
    /// −1 or +1; the caller changes its value (a step of 2.5 kg, 15 s, a clamp of its own).
    let step: (Int) -> Void

    /// An `Int` in `range`, one `step` at a time, drawn by `format`.
    init(_ value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1, format: @escaping (Int) -> String = { "\($0)" },
         spoken: ((Int) -> String)? = nil) {
        text = format(value.wrappedValue)
        self.spoken = spoken?(value.wrappedValue)
        canDecrement = value.wrappedValue > range.lowerBound
        canIncrement = value.wrappedValue < range.upperBound
        self.step = { direction in
            value.wrappedValue = RyftStepperSpec.stepped(value.wrappedValue, direction: direction, step: step, in: range)
        }
    }

    /// Any value the caller steps itself.
    init(text: String, spoken: String? = nil, canDecrement: Bool, canIncrement: Bool, step: @escaping (Int) -> Void) {
        self.text = text
        self.spoken = spoken
        self.canDecrement = canDecrement
        self.canIncrement = canIncrement
        self.step = step
    }

    var accessibilityValue: String {
        RyftStepperSpec.spokenValue(spoken ?? text, canDecrement: canDecrement, canIncrement: canIncrement)
    }
}

extension View {
    /// One adjustable element for a stepper: `label`, its value, swipe up and down.
    fileprivate func stepperAccessibility(_ label: Text, _ value: RyftStepperValue) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(Text(verbatim: value.accessibilityValue))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment where value.canIncrement: value.step(1)
                case .decrement where value.canDecrement: value.step(-1)
                default: break
                }
            }
    }
}

/// The two circles, with the repeat-on-hold of `TargetStepper` and the disabled 35 % at either end.
private struct StepperCircle: View {
    let direction: Int
    let value: RyftStepperValue

    var body: some View {
        CircleButton(systemImage: direction < 0 ? "minus" : "plus",
                     accessibilityLabel: direction < 0 ? RyftStepperSpec.decrementLabel : RyftStepperSpec.incrementLabel) {
            value.step(direction)
        }
        .buttonRepeatBehavior(.enabled)
        .disabled(direction < 0 ? !value.canDecrement : !value.canIncrement)
    }
}

/// The inline `− value +`: a 40 pt circle in its 44 pt box each side of a 22 pt number. The caller's `label` names it for
/// VoiceOver (the row's title); use `RyftStepperRow` for a row of a grouped card.
struct RyftStepper: View {
    private let label: Text
    private let value: RyftStepperValue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ label: Text, value: RyftStepperValue) {
        self.label = label
        self.value = value
    }

    /// An `Int` in `range`, one `step` at a time.
    init(_ label: Text, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         format: @escaping (Int) -> String = { "\($0)" }) {
        self.init(label, value: RyftStepperValue(value, in: range, step: step, format: format))
    }

    var body: some View {
        HStack(spacing: RyftStepperSpec.spacing) {
            StepperCircle(direction: -1, value: value)
            Text(verbatim: value.text)
                .font(.ryftNumber(size: RyftStepperSpec.valueSize))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(Theme.Motion.respecting(reduceMotion), value: value.text)
                .frame(minWidth: RyftStepperSpec.valueMinWidth)
            StepperCircle(direction: 1, value: value)
        }
        .stepperAccessibility(label, value)
    }
}

/// A grouped card's row that holds a stepper (B §1.3: 56 high): the title leading, `RyftStepper` trailing; from AX1 the
/// stepper goes under the title. The whole row is the one adjustable element, named by the title. `quiet` sets the title in
/// `textSecondary` for a sub-row (a set count under its exercise, the drinks under "Alcohol").
struct RyftStepperRow: View {
    private let title: Text
    private let detail: Text?
    private let quiet: Bool
    private let value: RyftStepperValue

    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: Text, detail: Text? = nil, quiet: Bool = false, value: RyftStepperValue) {
        self.title = title
        self.detail = detail
        self.quiet = quiet
        self.value = value
    }

    init(_ title: Text, detail: Text? = nil, quiet: Bool = false, value: Binding<Int>, in range: ClosedRange<Int>,
         step: Int = 1, format: @escaping (Int) -> String = { "\($0)" }) {
        self.init(title, detail: detail, quiet: quiet, value: RyftStepperValue(value, in: range, step: step, format: format))
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: GroupedListSpec.rowSpacing))
        layout {
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                title
                    .font(.ryft(.callout))
                    .foregroundStyle(quiet ? Theme.textSecondary : Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    detail
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RyftStepper(title, value: value)
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: RyftStepperSpec.rowMinHeight, alignment: .leading)
        .groupedRowHairline()
        .stepperAccessibility(title, value)
    }
}

/// An editor's number between its two circles (C §4.11): "Less", 18, the numeral (`DotNumeral`, or a Light number), 18, "More",
/// centred. Where the row would not fit (the Light numeral at AX3) the circles go under the numeral, side by side. One
/// adjustable element (`label`, the value); the circles still take taps but VoiceOver doesn't stop on them, and the numeral's
/// own label is replaced. The ruler under it belongs to the caller, hidden from VoiceOver: it repeats the value.
struct HeroStepper<Numeral: View>: View {
    private let label: Text
    private let value: RyftStepperValue
    private let numeral: Numeral

    init(_ label: Text, value: RyftStepperValue, @ViewBuilder numeral: () -> Numeral) {
        self.label = label
        self.value = value
        self.numeral = numeral()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RyftStepperSpec.heroSpacing) {
                StepperCircle(direction: -1, value: value)
                numeral.fixedSize()
                StepperCircle(direction: 1, value: value)
            }
            VStack(spacing: RyftStepperSpec.heroStackedGap) {
                numeral
                HStack(spacing: RyftStepperSpec.heroSpacing) {
                    StepperCircle(direction: -1, value: value)
                    StepperCircle(direction: 1, value: value)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .stepperAccessibility(label, value)
    }
}

// MARK: - previews (dark only; verbatim: the screens own the strings)

private struct RyftStepperPreviewBoard: View {
    @State private var days = 4
    @State private var sets = 1
    @State private var drinks = 2
    @State private var minutes = 465

    var body: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
            GroupedCard(Text(verbatim: "Plan")) {
                RyftStepperRow(Text(verbatim: "Days per week"), value: $days, in: 1...7)
                RyftStepperRow(Text(verbatim: "Sets"), quiet: true, value: $sets, in: 1...10)
                RyftStepperRow(Text(verbatim: "Count"), detail: Text(verbatim: "Drinks"), quiet: true, value: $drinks, in: 1...50)
            }
            HeroStepper(Text(verbatim: "Baseline sleep need"),
                        value: RyftStepperValue($minutes, in: 240...720, step: 15, format: Self.clock)) {
                DotNumeral(Self.clock(minutes), glyphGap: DotNumeral.glyphGapDetail, placeholder: "0:00",
                           accessibilityLabel: Text(verbatim: "Baseline sleep need"))
            }
            RulerScale(range: 240...720, value: Double(minutes), tickCount: 33, labels: ["4 h", "8 h", "12 h"],
                       accessibilityLabel: Text(verbatim: "Baseline sleep need"), accessibilityValue: Text(verbatim: ""))
                .accessibilityHidden(true)
        }
    }

    static func clock(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }
}

#Preview("RyftStepper", traits: .sizeThatFitsLayout) {
    DarkPreview { RyftStepperPreviewBoard() }
}

#Preview("RyftStepper · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { RyftStepperPreviewBoard() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
