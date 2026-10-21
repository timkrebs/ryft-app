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
    /// Read after the value, e.g. a `GaugeNote` shown under the gauge ("Recalculating your baselines").
    var accessibilityNote: String?

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
                // One line when it fits; at large text sizes (German at AX3) the band word over the change,
                // wrapping: never cut off.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        bandText
                        if band != nil, delta != nil {
                            Text("·").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                        }
                        DeltaLabel(spec: spec, delta: delta, reference: deltaReference)
                    }
                    .lineLimit(1)
                    VStack(spacing: 2) {
                        bandText
                        DeltaLabel(spec: spec, delta: delta, reference: deltaReference)
                    }
                    .multilineTextAlignment(.center)
                }
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
        .onAppear { animate(fromZero: true) }
        // A new value moves the arc on from where it was (strain filling up as the day goes).
        .onChange(of: value) { animate(fromZero: false) }
    }

    @ViewBuilder
    private var bandText: some View {
        if let band {
            Text(band.label)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
                .contentTransition(reduceMotion ? .identity : .numericText(value: value ?? 0))
                .animation(Theme.Motion.respecting(reduceMotion), value: value)
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
        let spoken = parts.joined(separator: ", ")
        return accessibilityNote.map { "\(spoken). \($0)" } ?? spoken
    }

    /// First appearance fills from 0 (250 ms); later values move on from the current
    /// arc (600 ms), so a growing strain visibly accumulates toward its target.
    private func animate(fromZero: Bool) {
        let target = value.map(fraction) ?? 0
        if reduceMotion {
            shown = target
        } else {
            if fromZero { shown = 0 }
            withAnimation(fromZero ? Theme.ringAnimation : Theme.Motion.slow) { shown = target }
        }
    }
}

/// The readiness gauge's place while the baselines are learned: a segment per night of
/// the seven, filled for the nights behind them. Never an empty ring.
struct BaselineGauge: View {
    /// `DailyScore.baselineDays`, or with `countsHeartRateNights` the nights with HRV and resting HR.
    let nights: Int
    var required = DailyScore.baselineNightsRequired
    /// A long history short of heart-rate nights (`TodayPresentation.Note.needsVitals`): the caption
    /// says which nights count, never a bare "nights" beside a history of many.
    var countsHeartRateNights = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    private static let diameter: CGFloat = 160
    private static let stroke: CGFloat = 6
    /// Between segments, as a fraction of the circle.
    private static let gap = 0.014

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ForEach(0..<required, id: \.self) { i in
                    Circle()
                        .inset(by: Self.stroke / 2)
                        .trim(from: Double(i) / Double(required) + Self.gap / 2,
                              to: Double(i + 1) / Double(required) - Self.gap / 2)
                        .stroke(i < shown ? Theme.accent : Theme.surfaceRaised,
                                style: StrokeStyle(lineWidth: Self.stroke, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 3) {
                    RyftMark()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Baselines")
                        .font(.ryftNumber(size: 9, weight: .medium))
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(Theme.textSecondary)
                    Text(verbatim: "\(min(nights, required))")
                        .font(.ryftNumber(size: 46))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text(verbatim: "/ \(required)")
                        .font(.ryftNumber(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .padding(6)
            Group {
                if countsHeartRateNights {
                    Text("Baselines · \(min(nights, required)) of \(required) nights with heart-rate data")
                } else {
                    Text("Baselines · \(min(nights, required)) of \(required) nights")
                }
            }
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Baselines"))
        .accessibilityValue(countsHeartRateNights
            ? Text("\(min(nights, required)) of \(required) nights with heart-rate data. Readiness appears once the baselines are complete.")
            : Text("\(min(nights, required)) of \(required) nights. Readiness appears once the baselines are complete."))
        .onAppear {
            // One segment after another, unless motion is reduced.
            if reduceMotion { shown = nights } else {
                for i in 0...min(nights, required) {
                    withAnimation(Theme.Motion.quick.delay(Double(i) * 0.06)) { shown = i }
                }
            }
        }
        .onChange(of: nights) { shown = nights }
    }
}

/// A night not scored yet: the readiness gauge in outline only, the day before's value
/// dimmed with its date. Never a number that pretends to be today's.
struct PendingGauge: View {
    /// The latest readiness before today and its day.
    let previous: Double?
    let previousDay: Date?
    /// "Scoring your night…" and when to expect it.
    let title: String
    let detail: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let diameter: CGFloat = 160
    private static let stroke: CGFloat = 6

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                outline
                VStack(spacing: 3) {
                    RyftMark()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Overall readiness")
                        .font(.ryftNumber(size: 9, weight: .medium))
                        .textCase(.uppercase)
                        .tracking(1.4)
                        .foregroundStyle(Theme.textSecondary)
                    Text(previous.map { MetricSpec.readiness.number($0) } ?? Fmt.placeholder)
                        .font(.ryftNumber(size: 46))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                    if let previousDay {
                        Text(Fmt.dayTitle(previousDay))
                            .font(.ryftNumber(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, Self.stroke + 4)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .padding(6)
            VStack(spacing: 2) {
                Text(title)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Overall readiness"))
        .accessibilityValue(Text(spokenValue))
    }

    /// The 6 pt ring as two hairlines; it breathes while scoring, unless motion is reduced.
    private var outline: some View {
        ZStack {
            Circle().strokeBorder(Theme.textTertiary, lineWidth: Theme.Metrics.hairline)
            Circle()
                .strokeBorder(Theme.textTertiary, lineWidth: Theme.Metrics.hairline)
                .padding(Self.stroke)
        }
        .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { ring, opacity in
            ring.opacity(opacity)
        } animation: { _ in .easeInOut(duration: 1.4) }
    }

    private var spokenValue: String {
        var parts = [String(localized: "Not scored yet"), title]
        if let previous, let previousDay {
            parts.append(String(localized: "\(Fmt.dayTitle(previousDay)): \(MetricSpec.readiness.number(previous))"))
        }
        return parts.joined(separator: ". ")
    }
}

/// A plain line under a gauge (ui.md §1.2 D, §1.7): a static symbol and a caption in secondary
/// ink, centred, wrapping. Not a card and not an action: it says why the gauge reads as it does.
struct GaugeNote: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.ryft(.caption))
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Baseline and pending", traits: .sizeThatFitsLayout) {
    SchemePair {
        HStack(spacing: 16) {
            BaselineGauge(nights: 3)
            PendingGauge(previous: 78, previousDay: .now.addingTimeInterval(-86_400),
                         title: "Scoring your night…", detail: "Usually ready within 20 s.")
        }
    }
}

#Preview("Baseline and pending · de", traits: .sizeThatFitsLayout) {
    SchemePair {
        HStack(spacing: 16) {
            BaselineGauge(nights: 5)
            PendingGauge(previous: nil, previousDay: nil,
                         title: PendingNight(waitingForSleep: true).title, detail: PendingNight(waitingForSleep: true).detail)
        }
    }
    .environment(\.locale, Locale(identifier: "de"))
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

#Preview("Gauge notes", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                MetricGauge(spec: .readiness, value: 80, size: .large, title: String(localized: "Overall readiness"),
                            showsMark: true, accessibilityNote: String(localized: "Recalculating your baselines"))
                GaugeNote(text: String(localized: "Recalculating your baselines"), systemImage: "arrow.triangle.2.circlepath")
            }
            // Row B over a long history without HRV: the platform's readiness, the reason under it ...
            VStack(spacing: 8) {
                MetricGauge(spec: .readiness, value: 80, size: .large, title: String(localized: "Overall readiness"),
                            showsMark: true,
                            accessibilityNote: String(localized: "Baselines need heart-rate variability and resting heart rate from nights with your watch."))
                GaugeNote(text: String(localized: "Baselines need heart-rate variability and resting heart rate from nights with your watch."),
                          systemImage: "info.circle")
            }
            // ... or without a readiness, the baselines counting the nights that do count.
            VStack(spacing: 8) {
                BaselineGauge(nights: 2, countsHeartRateNights: true)
                GaugeNote(text: String(localized: "Baselines need heart-rate variability and resting heart rate from nights with your watch."),
                          systemImage: "info.circle")
            }
        }
    }
}

#Preview("Gauge notes · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            BaselineGauge(nights: 2, countsHeartRateNights: true)
            GaugeNote(text: String(localized: "Recalculating your baselines"), systemImage: "arrow.triangle.2.circlepath")
            GaugeNote(text: String(localized: "Baselines need heart-rate variability and resting heart rate from nights with your watch."),
                      systemImage: "info.circle")
        }
    }
    .environment(\.locale, Locale(identifier: "de"))
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("MetricGauge · large caption · de · AX3", traits: .sizeThatFitsLayout) {
    // "Hoch · ▲ +11 ggü. 7 Tg." doesn't fit one line here: the band word over the change, wrapping.
    SchemePair {
        VStack(spacing: 16) {
            MetricGauge(spec: .readiness, value: 84, size: .large, delta: MetricDelta(current: 84, reference: 73),
                        title: String(localized: "Overall readiness"), showsMark: true)
            MetricGauge(spec: .readiness, value: 80, size: .large, delta: MetricDelta(current: 80, reference: 79.6),
                        title: String(localized: "Overall readiness"), showsMark: true)
        }
    }
    .environment(\.locale, Locale(identifier: "de"))
    .environment(\.dynamicTypeSize, .accessibility3)
}
