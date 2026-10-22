import SwiftUI

/// Rounded Slate surface used for every grouped block.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Metrics.cardPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
    }
}

/// Card title row: "Trends" … "7 days ›".
struct CardHeader: View {
    let title: LocalizedStringKey
    var trailing: LocalizedStringKey? = nil
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
    var detail: String? = nil
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A choice in a multi-select grid ("What do you wear?", ui.md §2.2): symbol, name, a trailing mark. Selected is
/// carried by the border, the check's shape and the VoiceOver trait, never by colour alone.
struct SelectableTile: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    /// VoiceOver, after the name ("Clears your other choices").
    var hint: LocalizedStringKey?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isSelected ? Theme.surfaceRaised : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Theme.separator, lineWidth: isSelected ? 1.5 : Theme.Metrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
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
        case .yes: return Theme.accent
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
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
    SchemePair {
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
    SchemePair { SelectableTileStates() }
}

#Preview("SelectableTile · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair { SelectableTileStates() }
        .environment(\.locale, Locale(identifier: "de"))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("CapabilityRow · states", traits: .sizeThatFitsLayout) {
    SchemePair { CapabilityRowStates() }
}

#Preview("CapabilityRow · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair { CapabilityRowStates() }
        .environment(\.locale, Locale(identifier: "de"))
        .environment(\.dynamicTypeSize, .accessibility3)
}
