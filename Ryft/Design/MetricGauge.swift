import SwiftUI

/// A score ring as an instrument: 6 pt butt-capped stroke on a flat track, tick
/// marks at 0 and the band thresholds, an optional lighter target arc, the value
/// in tabular Satoshi Medium with its scale under it, and the band word with the
/// delta below. No glow, no gradient; the arc settles in 250 ms.
struct MetricGauge: View {
    enum Size {
        case small, medium, large

        var diameter: CGFloat {
            switch self {
            case .small: return 72
            case .medium: return 112
            case .large: return 160
            }
        }

        fileprivate var valueSize: CGFloat {
            switch self {
            case .small: return 20
            case .medium: return 32
            case .large: return 46
            }
        }
    }

    let spec: MetricSpec
    let value: Double?
    var size: Size = .medium
    /// Lighter arc between `lo` and `hi`, e.g. a strain target.
    var target: ClosedRange<Double>? = nil
    var delta: MetricDelta? = nil
    var deltaReference: String = String(localized: "vs 7 d")
    /// Small caps above the value (large gauges only).
    var title: String? = nil
    /// The orbit mark above the value (large gauges only).
    var showsMark = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private static let stroke: CGFloat = 6
    private static let tickLength: CGFloat = 4
    private static let tickGap: CGFloat = 2

    private var scale: ClosedRange<Double> { spec.scale ?? 0...100 }

    private func fraction(_ v: Double) -> Double {
        let span = scale.upperBound - scale.lowerBound
        return min(max((v - scale.lowerBound) / span, 0), 1)
    }

    private var band: (label: String, color: Color)? { value.flatMap { spec.band?($0) } }
    private var arcColor: Color {
        // Readiness and recovery colour by band (semantic trio); others keep the metric colour.
        guard spec.polarity != .neutral, let band else { return spec.color }
        return band.color
    }

    var body: some View {
        VStack(spacing: size == .small ? 4 : 8) {
            dial
            if size == .large {
                HStack(spacing: 6) {
                    bandText
                    if band != nil, delta != nil {
                        Text("·").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                    }
                    DeltaLabel(spec: spec, delta: delta, reference: deltaReference)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            } else if size == .medium {
                // Two short lines fit the 112 pt width where one long one wouldn't.
                VStack(spacing: 2) {
                    bandText
                    DeltaLabel(spec: spec, delta: delta, reference: deltaReference)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title ?? spec.title))
        .accessibilityValue(Text(spokenValue))
        .onAppear(perform: animate)
        .onChange(of: value) { animate() }
    }

    @ViewBuilder
    private var bandText: some View {
        if let band {
            Text(band.label)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var dial: some View {
        let d = size.diameter
        let outer = d + 2 * (Self.tickGap + Self.tickLength)
        return ZStack {
            Circle()
                .inset(by: Self.stroke / 2)
                .stroke(Theme.surfaceRaised, lineWidth: Self.stroke)
                .frame(width: d, height: d)
            if let target {
                Circle()
                    .inset(by: Self.stroke / 2)
                    .trim(from: fraction(target.lowerBound), to: fraction(target.upperBound))
                    .stroke(spec.color.opacity(0.35), style: StrokeStyle(lineWidth: Self.stroke, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .frame(width: d, height: d)
            }
            Circle()
                .inset(by: Self.stroke / 2)
                .trim(from: 0, to: shown)
                .stroke(arcColor, style: StrokeStyle(lineWidth: Self.stroke, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .frame(width: d, height: d)
            ForEach([scale.lowerBound] + spec.thresholds, id: \.self) { t in
                Rectangle()
                    .fill(Theme.textTertiary)
                    .frame(width: 1, height: Self.tickLength)
                    .offset(y: -(d / 2 + Self.tickGap + Self.tickLength / 2))
                    .rotationEffect(.degrees(fraction(t) * 360))
            }
            center
        }
        .frame(width: outer, height: outer)
    }

    private var center: some View {
        VStack(spacing: size == .large ? 3 : 1) {
            if size == .large, showsMark {
                RyftMark()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.textPrimary)
            }
            if size == .large, let title {
                Text(title)
                    .font(.ryftNumber(size: 9, weight: .medium))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(value.map(spec.number) ?? Fmt.placeholder)
                .font(.ryftNumber(size: size.valueSize))
                .monospacedDigit()
                .foregroundStyle(value == nil ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !spec.scaleLabel.isEmpty {
                Text(spec.scaleLabel)
                    .font(.ryftNumber(size: size == .small ? 9 : 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, Self.stroke + 4)
    }

    private var spokenValue: String {
        guard let value else { return String(localized: "No data") }
        var parts = [String(localized: "\(spec.number(value)) of \(spec.number(scale.upperBound))")]
        if let band { parts.append(band.label) }
        if let delta { parts.append(DeltaLabel.spoken(delta, spec: spec, reference: deltaReference)) }
        return parts.joined(separator: ", ")
    }

    private func animate() {
        let target = value.map(fraction) ?? 0
        if reduceMotion {
            shown = target
        } else {
            shown = 0
            withAnimation(Theme.ringAnimation) { shown = target }
        }
    }
}

#Preview("MetricGauge", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 20) {
            MetricGauge(spec: .readiness, value: 84, size: .large,
                        delta: MetricDelta(current: 84, reference: 78),
                        title: "Readiness", showsMark: true)
            HStack(spacing: 16) {
                MetricGauge(spec: .strain, value: 12.4, size: .medium, target: 11...14,
                            delta: MetricDelta(current: 12.4, reference: 10.1))
                MetricGauge(spec: .recovery, value: 41, size: .medium,
                            delta: MetricDelta(current: 41, reference: 63))
                MetricGauge(spec: .recovery, value: nil, size: .small)
            }
        }
    }
}
