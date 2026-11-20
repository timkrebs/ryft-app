// A form's field row and its value chip (Nocturne, docs/work/2026-11-16-nocturne/build-plan.md §2; PR 6 A G4, G5, §3
// `FormGroup` / `FormRow`, D6A-1, D6A-8; B §1.3, S9). A field is a row of a `GroupedCard`: the label above the value, 56 high,
// and focus is a 2 × 28 bar at the card's edge, never a fill (a 6 % fill is 1.15:1 against `surface` and tells nobody
// anything). Errors are banners (`InlineMessage`), not field states.
import SwiftUI

/// The field row's and the chip's numbers.
enum FormFieldSpec {
    /// A row with a label above its value: 56 (a list row is 46). PR 6 A asked for `Theme.Metrics.fieldRowHeight = 56`;
    /// until the lead adds it, the number lives here. TODO(T6.0, lead): `Theme.Metrics.fieldRowHeight`.
    static let minHeight: CGFloat = 56
    /// 8 above and below, 16 at the sides (the grouped row's inset).
    static let verticalPadding: CGFloat = 8
    static let horizontalPadding = GroupedListSpec.rowInset
    /// The label → the value.
    static let labelGap: CGFloat = 2
    /// Between the text column and a trailing view (the eye, a unit, chips).
    static let trailingSpacing = Theme.Metrics.itemSpacing
    /// The focus bar: a 2 × 28 capsule in `textPrimary`, 6 in from the card's leading edge, centred on the row.
    static let focusBar = CGSize(width: 2, height: 28)
    static let focusInset: CGFloat = 6
    /// `.large` values (a plan's name, a distance): 22 Light at the default size, growing with the text.
    static let largeValueSize: CGFloat = 22
    /// A prompt in an empty field: `textSecondary` (6.8:1 on `surface`), so it reads as a prompt and not as a value.
    static let promptColor = Theme.textSecondary
}

/// One field of a form: `FormField(Text("Email"), isFocused: focus == .email) { TextField(…) }` in a `GroupedCard`.
///
/// - The label is 13 pt (`.label`), `textSecondary`, `textPrimary` while focused; 2 below it the value, 16 pt `textPrimary`
///   (`.regular`) or 22 Light (`.large`); the caret is `textPrimary`.
/// - Focus: the label's ink and the bar at the leading edge; it appears with `Theme.Motion.quick`, at once under Reduce Motion.
/// - A trailing view (the eye button, a unit, a paste chip) sits after the value; from AX1 it goes under it.
/// - The row draws its hairline in a `GroupedCard` and is at least `minHeight` high (a multi-line field passes more).
/// - VoiceOver: the field is one element named by the label (its value is what is typed); the visual label is hidden, so it
///   isn't read twice. The trailing view keeps its own element.
struct FormField<Field: View, Trailing: View>: View {
    enum ValueSize { case regular, large }

    private let label: Text
    private let isFocused: Bool
    private let valueSize: ValueSize
    private let minHeight: CGFloat
    private let field: Field
    private let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var largeValue: CGFloat = FormFieldSpec.largeValueSize

    init(_ label: Text, isFocused: Bool = false, valueSize: ValueSize = .regular, minHeight: CGFloat = FormFieldSpec.minHeight,
         @ViewBuilder field: () -> Field, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.isFocused = isFocused
        self.valueSize = valueSize
        self.minHeight = minHeight
        self.field = field()
        self.trailing = trailing()
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: FormFieldSpec.labelGap))
            : AnyLayout(HStackLayout(alignment: .center, spacing: FormFieldSpec.trailingSpacing))
        layout {
            VStack(alignment: .leading, spacing: FormFieldSpec.labelGap) {
                label
                    .font(.ryft(.label))
                    .foregroundStyle(isFocused ? Theme.textPrimary : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                field
                    .font(valueFont)
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.textPrimary)
                    .accessibilityLabel(label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, FormFieldSpec.verticalPadding)
        .padding(.horizontal, FormFieldSpec.horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .overlay(alignment: .leading) { focusBar }
        .animation(Theme.Motion.respecting(reduceMotion), value: isFocused)
        .groupedRowHairline()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var focusBar: some View {
        if isFocused {
            Capsule()
                .fill(Theme.textPrimary)
                .frame(width: FormFieldSpec.focusBar.width, height: FormFieldSpec.focusBar.height)
                .padding(.leading, FormFieldSpec.focusInset)
                .accessibilityHidden(true)
        }
    }

    private var valueFont: Font {
        switch valueSize {
        case .regular: return .ryft(.body)
        case .large: return .ryftNumber(size: largeValue, weight: .light)
        }
    }
}

extension FormField where Trailing == EmptyView {
    init(_ label: Text, isFocused: Bool = false, valueSize: ValueSize = .regular, minHeight: CGFloat = FormFieldSpec.minHeight,
         @ViewBuilder field: () -> Field) {
        self.init(label, isFocused: isFocused, valueSize: valueSize, minHeight: minHeight, field: field) { EmptyView() }
    }
}

extension Text {
    /// A field's prompt in `FormFieldSpec.promptColor`: `TextField(text: $email, prompt: Text("name@example.com").fieldPrompt())`.
    func fieldPrompt() -> Text {
        foregroundStyle(FormFieldSpec.promptColor)
    }
}

// MARK: - value chip

/// The chip's numbers (B §1.3).
enum ValueChipSpec {
    /// A capsule 36 high on `surfaceRaised`, 14 at the sides; its text `callout` `textPrimary` (11.6:1 on `surfaceRaised`).
    static let height: CGFloat = 36
    static let horizontalPadding: CGFloat = 14
    /// Between two chips, side by side or one under the other.
    static let spacing: CGFloat = 8
}

/// A value in a capsule, in a row's trailing slot: a date and a time ("Nov 18, 2026", "10:12 AM"), a count, a menu's choice.
///
/// - `ValueChip(Text("3:00"))`: the look only, for a `Menu`'s or a `Button`'s label.
/// - `ValueChip(Text("Start"), date: $start, displayedComponents: .date)`: a date or time the chip edits. The system's compact
///   `DatePicker` sits over the chip, invisible but tappable, so a tap opens its own calendar or wheel (dark, tinted
///   `textPrimary`) and VoiceOver, Voice Control and Switch Control reach it as a date picker named by `label`.
/// - It keeps one line; from AX1 a row puts its chips under its label, and `ValueChipGroup` stacks two that don't fit.
struct ValueChip: View {
    private enum Kind {
        case text(Text)
        case date(label: Text, selection: Binding<Date>, range: ClosedRange<Date>?, components: DatePickerComponents)
    }

    private let kind: Kind

    @Environment(\.locale) private var locale

    init(_ text: Text) {
        kind = .text(text)
    }

    init(_ label: Text, date: Binding<Date>, in range: ClosedRange<Date>? = nil, displayedComponents: DatePickerComponents) {
        kind = .date(label: label, selection: date, range: range, components: displayedComponents)
    }

    var body: some View {
        switch kind {
        case .text(let text):
            chip(text)
        case .date(let label, let selection, let range, let components):
            chip(Text(verbatim: Self.format(selection.wrappedValue, components: components, locale: locale)))
                .accessibilityHidden(true)
                .overlay { picker(label, selection: selection, range: range, components: components) }
        }
    }

    private func chip(_ text: Text) -> some View {
        text
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, ValueChipSpec.horizontalPadding)
            .frame(minHeight: ValueChipSpec.height)
            .background(Theme.surfaceRaised, in: Capsule())
    }

    /// The system picker, drawn transparent (`colorMultiply(.clear)` keeps it hit-testable, unlike `opacity(0)`), as big as
    /// the chip or bigger, so every point of the chip opens it.
    @ViewBuilder
    private func picker(_ label: Text, selection: Binding<Date>, range: ClosedRange<Date>?,
                        components: DatePickerComponents) -> some View {
        Group {
            if let range {
                DatePicker(selection: selection, in: range, displayedComponents: components) { label }
            } else {
                DatePicker(selection: selection, displayedComponents: components) { label }
            }
        }
        .labelsHidden()
        .datePickerStyle(.compact)
        .tint(Theme.textPrimary)
        .colorMultiply(.clear)
    }

    /// "Nov 18, 2026" for a date, "10:12 AM" for a time (the locale's order and clock), both for a date and time.
    nonisolated static func format(_ date: Date, components: DatePickerComponents, locale: Locale) -> String {
        let day = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        switch (components.contains(.date), components.contains(.hourAndMinute)) {
        case (true, true): return "\(date.formatted(day)) \(date.formatted(time))"
        case (false, true): return date.formatted(time)
        default: return date.formatted(day)
        }
    }
}

/// A row's chips: side by side while they fit on the line, one under the other when they don't (a date and a time at AX3),
/// so a chip never pushes the page wider than the screen. `ValueChipGroup { ValueChip(…); ValueChip(…) }`.
struct ValueChipGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ValueChipSpec.spacing) { content }
            VStack(alignment: .leading, spacing: ValueChipSpec.spacing) { content }
        }
    }
}

/// A grouped card's row of chips (B §1.3, S9: Start, End, Went to bed): the label leading in `callout` `textSecondary`, the
/// chips trailing, while the label keeps its line beside them (so it never breaks inside a word); otherwise, and always
/// from AX1, the label goes above and the chips under it at the leading edge, one under the other if they don't fit. 56 high
/// (a field row); the row draws its hairline in a `GroupedCard`. VoiceOver reads the label, then each chip.
struct ValueChipRow<Chips: View>: View {
    private let label: Text
    private let chips: Chips

    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ label: Text, @ViewBuilder chips: () -> Chips) {
        self.label = label
        self.chips = chips()
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                // Side by side only if the label fits on its line beside both chips; squeezed, it would wrap inside a
                // word at large text. Stacked, the label and the chips each take the whole width.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: FormFieldSpec.trailingSpacing) {
                        styledLabel.frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: ValueChipSpec.spacing) { chips }
                            .fixedSize()
                    }
                    stacked
                }
            }
        }
        .padding(.vertical, FormFieldSpec.verticalPadding)
        .padding(.horizontal, FormFieldSpec.horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: FormFieldSpec.minHeight, alignment: .leading)
        .groupedRowHairline()
        .accessibilityElement(children: .contain)
    }

    private var styledLabel: some View {
        label
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The label above; the chips under it, side by side while they fit the whole width.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: ValueChipSpec.spacing) {
            styledLabel
            ValueChipGroup { chips }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - previews (dark only; verbatim: the screens own the strings)

private struct FormFieldPreviewBoard: View {
    @State private var email = "alex@example.com"
    @State private var password = "correct horse"
    @State private var name = ""
    @State private var distance = ""
    @State private var start = Date(timeIntervalSince1970: 1_795_500_720)
    @State private var shows = false

    var body: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
            GroupedCard {
                FormField(Text(verbatim: "Email"), isFocused: true) {
                    TextField(text: $email, prompt: Text(verbatim: "name@example.com").fieldPrompt()) { Text(verbatim: "Email") }
                }
                FormField(Text(verbatim: "Password")) {
                    SecureField(text: $password) { Text(verbatim: "Password") }
                } trailing: {
                    Button { shows.toggle() } label: {
                        Image(systemName: shows ? "eye.slash" : "eye")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: Theme.Metrics.minHitTarget, height: Theme.Metrics.minHitTarget)
                    }
                    .accessibilityLabel(Text(verbatim: shows ? "Hide password" : "Show password"))
                }
            }
            GroupedCard {
                FormField(Text(verbatim: "Name"), valueSize: .large) {
                    TextField(text: $name, prompt: Text(verbatim: "Upper/Lower 4×").fieldPrompt()) { Text(verbatim: "Name") }
                }
            }
            GroupedCard {
                FormField(Text(verbatim: "Distance (optional)"), valueSize: .large) {
                    TextField(text: $distance, prompt: Text(verbatim: "Optional").fieldPrompt()) { Text(verbatim: "Distance") }
                } trailing: {
                    Text(verbatim: "mi").font(.ryft(.callout)).foregroundStyle(Theme.textTertiary)
                }
            }
            GroupedCard {
                ValueChipRow(Text(verbatim: "Start")) {
                    ValueChip(Text(verbatim: "Start date"), date: $start, displayedComponents: .date)
                    ValueChip(Text(verbatim: "Start time"), date: $start, displayedComponents: .hourAndMinute)
                }
                GroupedRow.custom(Text(verbatim: "Rest")) {
                    Menu { Button { } label: { Text(verbatim: "2:00") } } label: { ValueChip(Text(verbatim: "3:00")) }
                }
            }
        }
        .environment(\.locale, Locale(identifier: "en_US"))
    }
}

#Preview("FormField and ValueChip", traits: .sizeThatFitsLayout) {
    DarkPreview { FormFieldPreviewBoard() }
}

#Preview("FormField and ValueChip · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { FormFieldPreviewBoard() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
