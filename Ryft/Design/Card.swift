import SwiftUI
import UIKit

/// The card's numbers (Nocturne, docs/work/2026-11-16-nocturne/build-plan.md §2): the grouped card's radius, 22, and 16
/// inside, so a `Card` and a `GroupedCard` on one page have the same corners and the same text inset.
enum CardSpec {
    // TODO(T6.0, lead): set `Theme.Metrics.cardRadius` to 22 and `cardPadding` to 16 and point these at them; the screens
    // that read the two tokens directly (InsightCard, CoachMarks, Today's tiles, the exercise pages, Add activity) still
    // draw 18 / 18 until then.
    static let radius = Theme.Metrics.neutralTileRadius
    static let padding: CGFloat = 16
}

/// The `surface` card every grouped block sits on: radius 22, 16 inside, no stroke.
struct Card<Content: View>: View {
    var padding: CGFloat = CardSpec.padding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: CardSpec.radius, style: .continuous))
    }
}

/// Card title row: "Trends" … "7 days ›".
struct CardHeader: View {
    let title: LocalizedStringKey
    var trailing: LocalizedStringKey?
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let trailing {
                HStack(spacing: 4) {
                    Text(trailing)
                    if showsChevron { Image(systemName: "chevron.right").imageScale(.small) }
                }
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// A label/value row inside a card ("Bedtime  23:05").
struct StatRow: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String?
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.ryft(.body))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                if let detail {
                    Text(detail)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Subtle press feedback for tappable cards and tiles.
struct PressableButtonStyle: ButtonStyle {
    /// The press: 150 ms ease-out, none under Reduce Motion (the scale and the dimming then just happen).
    static let pressAnimation = Animation.easeOut(duration: 0.15)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.Motion.respecting(reduceMotion, Self.pressAnimation), value: configuration.isPressed)
    }
}

/// The selectable tile's numbers (PR 6 A §A-11): the grouped card's radius; selected draws a 1.5 pt `textPrimary` border
/// at 90 % (15.6:1 against `background`, where c-07's 30 % border was 2.3:1, under the 3:1 a state needs).
enum SelectableTileSpec {
    static let radius = Theme.Metrics.neutralTileRadius
    static let minHeight: CGFloat = 56
    static let borderWidth = Theme.Metrics.controlOutline
    static let borderOpacity = 0.9
}

/// A choice in a multi-select grid ("What do you wear?", ui.md §2.2): symbol, name, a trailing mark, on `surface` whether
/// chosen or not. Selected is carried by the border, the check's shape, the glyph's ink and the VoiceOver trait, never by
/// colour alone, and never by teal.
struct SelectableTile: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    /// VoiceOver, after the name ("Clears your other choices").
    var hint: LocalizedStringKey?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The glyph, its column and the mark grow with the name.
    @ScaledMetric(relativeTo: .callout) private var glyph: CGFloat = Self.baseGlyph
    @ScaledMetric(relativeTo: .callout) private var glyphColumn: CGFloat = Self.baseColumn
    @ScaledMetric(relativeTo: .callout) private var mark: CGFloat = Self.baseMark

    private static let baseGlyph: CGFloat = 20, baseColumn: CGFloat = 22, baseMark: CGFloat = 20
    private static let padding: CGFloat = 12, spacing: CGFloat = 8

    /// Everything in a tile but its name at a text size: the room a name has is the tile's width minus this.
    static func chrome(_ size: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        let scaled = { UIFontMetrics(forTextStyle: .callout).scaledValue(for: $0, compatibleWith: traits) }
        return 2 * padding + 2 * spacing + scaled(baseColumn) + scaled(baseMark)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Self.spacing) {
                Image(systemName: symbol)
                    .font(.system(size: glyph, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: glyphColumn)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: mark, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, Self.padding)
            .frame(maxWidth: .infinity, minHeight: SelectableTileSpec.minHeight, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: SelectableTileSpec.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SelectableTileSpec.radius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(SelectableTileSpec.borderOpacity),
                                  lineWidth: SelectableTileSpec.borderWidth)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: SelectableTileSpec.radius, style: .continuous))
            .animation(Theme.Motion.respecting(reduceMotion), value: isSelected)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityHint(hint.map { Text($0) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// How one signal reaches RYFT from a tracker (ui.md §3.2): a fact, never a fault. Only shape and word tell the
/// states apart; "no" is quiet (no tint, no ✗).
enum CapabilityState: Equatable, Sendable {
    case yes, partial, no, unverified
    /// The honest-limit cards (a tracker that writes nothing, the iPhone alone): "Not available".
    case notAvailable

    init(_ capability: Capability) {
        switch capability {
        case .yes: self = .yes
        case .partial: self = .partial
        case .no: self = .no
        case .unverified: self = .unverified
        }
    }

    var symbol: String {
        switch self {
        case .yes: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .no, .notAvailable: return "minus.circle"
        case .unverified: return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .yes: return Theme.textPrimary
        case .partial: return Theme.textSecondary
        case .no, .unverified, .notAvailable: return Theme.textTertiary
        }
    }

    var word: String {
        switch self {
        case .yes: return String(localized: "Arrives")
        case .partial: return String(localized: "Partly")
        case .no: return String(localized: "Not shared")
        case .unverified: return String(localized: "Not confirmed")
        case .notAvailable: return String(localized: "Not available")
        }
    }
}

/// One signal in "What reaches RYFT": glyph, name, state word, and an optional reason under the name. One
/// VoiceOver element: the name, then the word and the reason.
struct CapabilityRow: View {
    let title: String
    /// The full name for VoiceOver ("Heart rate variability" for "HRV").
    var spokenTitle: String?
    let state: CapabilityState
    /// Why, from the catalog ("Garmin keeps HRV in its own app."), or a detail ("Newer models only").
    var detail: String?
    /// Replaces the state's word ("From your iPhone").
    var word: String?

    @Environment(\.dynamicTypeSize) private var typeSize

    private var stateWord: String { word ?? state.word }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: state.symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(state.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if typeSize.isAccessibilitySize {
                    name
                    value
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        name
                        Spacer(minLength: 8)
                        value
                    }
                }
                if let detail {
                    Text(verbatim: detail)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // A reason under the name gets room above and below it.
        .padding(.vertical, detail == nil ? 0 : 6)
        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.listRowHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenTitle ?? title))
        .accessibilityValue(Text(verbatim: [stateWord, detail].compactMap { $0 }.joined(separator: ". ")))
    }

    private var name: some View {
        Text(verbatim: title)
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var value: some View {
        Text(verbatim: stateWord)
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Card", traits: .sizeThatFitsLayout) {
    DarkPreview {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Trends", trailing: "7 days", showsChevron: true)
                StatRow(title: "Bedtime", value: "22:50")
                StatRow(title: "Sleep debt", value: "25m", detail: "Need 8h 06m", valueColor: Theme.warning)
            }
        }
    }
}

private struct SelectableTileStates: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SelectableTile(symbol: "watch.analog", title: "Garmin", isSelected: false) {}
                SelectableTile(symbol: "circle.circle", title: "Oura", isSelected: true) {}
            }
            HStack(spacing: 10) {
                SelectableTile(symbol: "watch.analog", title: "Samsung Galaxy Watch", isSelected: false) {}
                SelectableTile(symbol: "watch.analog", title: "Amazfit (Zepp)", isSelected: true) {}
            }
            SelectableTile(symbol: "iphone", title: "Just my iPhone", isSelected: false, hint: "Clears your other choices") {}
        }
    }
}

private struct CapabilityRowStates: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                CapabilityRow(title: "Heart rate", state: .yes)
                Divider().overlay(Theme.separator)
                CapabilityRow(title: "Sleep", state: .partial, detail: "Sleep stages not confirmed")
                Divider().overlay(Theme.separator)
                CapabilityRow(title: "HRV", spokenTitle: "Heart rate variability", state: .no,
                              detail: "Garmin keeps HRV in its own app.")
                Divider().overlay(Theme.separator)
                CapabilityRow(title: "Breathing rate", state: .unverified)
                Divider().overlay(Theme.separator)
                CapabilityRow(title: "SpO₂", spokenTitle: "Blood oxygen", state: .notAvailable)
            }
        }
    }
}

#Preview("SelectableTile · states", traits: .sizeThatFitsLayout) {
    DarkPreview { SelectableTileStates() }
}

#Preview("SelectableTile · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { SelectableTileStates() }
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("CapabilityRow · states", traits: .sizeThatFitsLayout) {
    DarkPreview { CapabilityRowStates() }
}

#Preview("CapabilityRow · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { CapabilityRowStates() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
