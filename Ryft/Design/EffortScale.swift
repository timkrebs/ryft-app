// Perceived effort, 1 to 10 (Nocturne PR 6 B §10.1, §14.2; the draft `b-19`): ten outlined circles in two rows of five, the
// picked one filled in ink. L27: the selection is ink (`textPrimary` fill, `background` number), never Volt or teal.
import SwiftUI

/// The scale's numbers (P2-D9: tests read them).
enum EffortScaleSpec {
    /// A circle: 46 at the default size, a 1 pt outline in `textPrimary` at 16 % (the circle button's ring).
    nonisolated static let diameter: CGFloat = 46
    nonisolated static let ringOpacity = CircleButton.borderOpacity
    /// The circle grows with the text up to these (5 across fit the Add activity card at xxxLarge on 390 pt; 3 across from AX1),
    /// and never past its column less `minGap`, so two circles never touch (a 320 pt screen from xLarge).
    nonisolated static let maxDiameter: CGFloat = 54, maxLargeTextDiameter: CGFloat = 84, minGap: CGFloat = 4
    /// The number: 17 at the default size (`ryftNumber`), growing with the text, never past 42 % of the circle.
    nonisolated static let numberSize: CGFloat = 17, numberShare: CGFloat = 0.42
    /// Five per row; three from AX1 (B §10.1).
    nonisolated static let columns = 5, largeTextColumns = 3
    /// Between rows, and the grid → "7 · Hard" under it.
    nonisolated static let rowSpacing: CGFloat = 10, wordGap: CGFloat = 12

    /// The columns at a text size.
    nonisolated static func columns(for typeSize: DynamicTypeSize) -> Int {
        typeSize.isAccessibilitySize ? largeTextColumns : columns
    }

    /// The circle for the text's `scaled` size in a grid `width` wide (0: not measured yet): capped by the size's maximum and
    /// by the column less `minGap`.
    nonisolated static func diameter(scaled: CGFloat, typeSize: DynamicTypeSize, width: CGFloat) -> CGFloat {
        let capped = min(scaled, typeSize.isAccessibilitySize ? maxLargeTextDiameter : maxDiameter)
        guard width > 0 else { return capped }
        return max(1, min(capped, width / CGFloat(columns(for: typeSize)) - minGap))
    }

    /// The selected circle: an ink fill with the number in `background` and Bold (17.35:1), so the pick is a shape and a weight,
    /// not a hue. The others: no fill, the 16 % ring, the number in `textPrimary` and Regular.
    static func fill(selected: Bool) -> Color { selected ? Theme.textPrimary : .clear }
    static func ink(selected: Bool) -> Color { selected ? Theme.background : Theme.textPrimary }
    static func weight(selected: Bool) -> Font.Weight { selected ? .bold : .regular }
}

/// Perceived effort, 1 to 10. Tapping a circle picks it, tapping it again clears it; once picked, "7 · Hard" (`callout`,
/// `textPrimary`) stands under the grid. VoiceOver reads one adjustable element, "Perceived effort", value "7 of 10, Hard"
/// (or "Not set"), with a Clear action; the circles are for touch. Identifiers: `effortScale` and `effortScale.<n>`.
struct EffortScale: View {
    @Binding var value: Int?
    private let label: Text
    private let word: @MainActor (Int) -> String
    private let identifier: String
    private let fractionalValue: Double?

    init(value: Binding<Int?>, label: Text = Text("Perceived effort", comment: "VoiceOver: the effort scale's name."),
         word: @escaping @MainActor (Int) -> String = { EffortScale.word($0) },
         identifier: String = "effortScale", fractionalValue: Double? = nil) {
        _value = value
        self.label = label
        self.word = word
        self.identifier = identifier
        self.fractionalValue = fractionalValue
    }

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = EffortScaleSpec.diameter
    @ScaledMetric(relativeTo: .body) private var scaledNumber: CGFloat = EffortScaleSpec.numberSize
    /// The grid's width, measured: the circles fit their columns.
    @State private var width: CGFloat = 0

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

    /// What VoiceOver reads after "Perceived effort": "7 of 10, Hard", or "Not set".
    static func spokenValue(_ value: Int?) -> String {
        guard let value else { return String(localized: "Not set", comment: "VoiceOver: no effort chosen.") }
        return String(localized: "\(value) of 10, \(word(value))", comment: "VoiceOver: the selected effort, e.g. '6 of 10, Moderate'.")
    }

    /// The line under the grid: "7 · Hard".
    static func caption(_ value: Int) -> String { "\(value) · \(word(value))" }

    private var fraction: Double? { fractionalValue.flatMap { (1...10).contains($0) ? $0 : nil } }

    private var rating: (number: String, word: String)? {
        if let value { return ("\(value)", word(value)) }
        guard let fraction else { return nil }
        let number = fraction.formatted(.number.precision(.fractionLength(1)).locale(locale))
        return (number, word(Int(fraction)))
    }

    private var accessibilityValue: String {
        if let value {
            return String(localized: "\(value) of 10, \(word(value))",
                          comment: "VoiceOver: the selected effort, e.g. '6 of 10, Moderate'.")
        }
        if let rating {
            return String(localized: "\(rating.number) of 10, \(rating.word)",
                          comment: "VoiceOver: a fractional effort rating, e.g. '7.5 of 10, Hard'.")
        }
        return Self.spokenValue(nil)
    }

    private var diameter: CGFloat {
        EffortScaleSpec.diameter(scaled: scaledDiameter, typeSize: typeSize, width: width)
    }

    private var numberSize: CGFloat { min(scaledNumber, diameter * EffortScaleSpec.numberShare) }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: EffortScaleSpec.columns(for: typeSize))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EffortScaleSpec.wordGap) {
            LazyVGrid(columns: columns, spacing: EffortScaleSpec.rowSpacing) {
                ForEach(Array(Self.range), id: \.self) { n in
                    circle(n)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // Only once a value is picked: no empty line under the grid before.
            if let rating {
                Text(verbatim: "\(rating.number) · \(rating.word)")
                    .font(.ryft(.callout))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                let previous = value ?? fraction.map { Int($0) } ?? 0
                value = min(Self.range.upperBound, previous + 1)
            case .decrement:
                let previous = value ?? fraction.map { Int($0.rounded(.up)) } ?? 2
                value = max(Self.range.lowerBound, previous - 1)
            @unknown default: break
            }
        }
        .accessibilityActions {
            if rating != nil {
                Button(String(localized: "Clear", comment: "VoiceOver action: remove the effort rating.")) { value = nil }
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private func circle(_ n: Int) -> some View {
        let selected = value == n
        return Button {
            value = selected ? nil : n
        } label: {
            Text(verbatim: "\(n)")
                .font(.ryftNumber(size: numberSize, weight: EffortScaleSpec.weight(selected: selected)))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(EffortScaleSpec.ink(selected: selected))
                .frame(width: diameter, height: diameter)
                .background(EffortScaleSpec.fill(selected: selected), in: Circle())
                .overlay {
                    if !selected {
                        Circle().strokeBorder(Theme.textPrimary.opacity(EffortScaleSpec.ringOpacity), lineWidth: Theme.Metrics.hairline)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(identifier).\(n)")
    }
}

#Preview("Effort scale", traits: .sizeThatFitsLayout) {
    struct Host: View {
        @State var picked: Int? = 7
        @State var none: Int?
        var body: some View {
            DarkPreview {
                VStack(spacing: 24) {
                    EffortScale(value: $picked)
                    EffortScale(value: $none)
                }
            }
        }
    }
    return Host()
}

#Preview("Effort scale · AX3", traits: .sizeThatFitsLayout) {
    struct Host: View {
        @State var picked: Int? = 10
        var body: some View { DarkPreview { EffortScale(value: $picked) } }
    }
    return Host().environment(\.dynamicTypeSize, .accessibility3)
}
