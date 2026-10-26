import SwiftUI

/// Perceived effort, 1 to 10 (ui.md §3.3): two rows of five round buttons (three columns at accessibility sizes).
/// Selected is accent-filled, bold and outlined, so it isn't colour alone; tapping it again clears it. VoiceOver
/// reads one adjustable element ("Perceived effort, 6 of 10, Moderate") with a Clear action; the buttons are for
/// touch.
struct EffortScale: View {
    @Binding var value: Int?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let range = 1...10

    /// "Very easy" … "Maximal" (1–2, 3–4, 5–6, 7–8, 9–10).
    static func word(_ value: Int) -> String {
        switch value {
        case ...2: return String(localized: "Very easy", comment: "Perceived effort 1–2.")
        case 3...4: return String(localized: "Easy", comment: "Perceived effort 3–4.")
        case 5...6: return String(localized: "Moderate", comment: "Perceived effort 5–6.")
        case 7...8: return String(localized: "Hard", comment: "Perceived effort 7–8.")
        default: return String(localized: "Maximal", comment: "Perceived effort 9–10.")
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 3 : 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(Self.range), id: \.self) { n in
                    button(n)
                }
            }
            // Only once a value is picked: no empty line under the grid before.
            if let value {
                Text(verbatim: "\(value) · \(Self.word(value))")
                    .font(.ryft(.callout))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Perceived effort", comment: "VoiceOver: the effort scale's name."))
        .accessibilityValue(value.map {
            Text("\($0) of 10, \(Self.word($0))", comment: "VoiceOver: the selected effort, e.g. '6 of 10, Moderate'.")
        } ?? Text("Not set", comment: "VoiceOver: no effort chosen."))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(Self.range.upperBound, (value ?? 0) + 1)
            case .decrement: value = max(Self.range.lowerBound, (value ?? 2) - 1)
            @unknown default: break
            }
        }
        .accessibilityActions {
            if value != nil {
                Button(String(localized: "Clear", comment: "VoiceOver action: remove the effort rating.")) { value = nil }
            }
        }
        .accessibilityIdentifier("effortScale")
    }

    private func button(_ n: Int) -> some View {
        let selected = value == n
        return Button {
            value = selected ? nil : n
        } label: {
            Text(verbatim: "\(n)")
                .font(.ryft(.body).weight(selected ? .bold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                // The circle grows with the number, so "10" stays inside it at the largest sizes.
                .padding(typeSize.isAccessibilitySize ? 14 : 4)
                .frame(minWidth: 44, minHeight: 44)
                .background(selected ? Theme.accent : Theme.surfaceRaised, in: Circle())
                .overlay {
                    if selected { Circle().strokeBorder(Theme.textPrimary, lineWidth: 2) }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("effortScale.\(n)")
    }
}

#Preview("Effort scale", traits: .sizeThatFitsLayout) {
    struct Host: View {
        @State var a: Int? = 6
        @State var b: Int?
        var body: some View {
            SchemePair {
                VStack(spacing: 20) {
                    EffortScale(value: $a)
                    EffortScale(value: $b)
                }
            }
        }
    }
    return Host()
}

#Preview("Effort scale · AX3", traits: .sizeThatFitsLayout) {
    struct Host: View {
        @State var a: Int? = 9
        var body: some View { SchemePair { EffortScale(value: $a) } }
    }
    return Host().environment(\.dynamicTypeSize, .accessibility3)
}
