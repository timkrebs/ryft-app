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
    /// The band word under the dial (and in VoiceOver); off where a note takes its line. The arc keeps its colour.
    var showsBand = true

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
    /// The band word, where it's shown.
    private var bandLabel: String? { showsBand ? band?.label : nil }
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
                        if bandLabel != nil, delta != nil {
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
        if let bandLabel {
            Text(bandLabel)
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
        // The note too when there's no number: the line under an empty gauge says why.
        guard let value else { return accessibilityNote.map { "\(String(localized: "No data")). \($0)" } ?? String(localized: "No data") }
        var parts = [String(localized: "\(spec.number(value)) of \(spec.number(scale.upperBound))")]
        if let bandLabel { parts.append(bandLabel) }
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

/// A plain line under a gauge (ui.md §1.2 D, §1.7): a static symbol and a caption in secondary
/// ink, centred, wrapping. Not a card and not an action: it says why the gauge reads as it does.
struct GaugeNote: View {
    let text: String
    let systemImage: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Wrapped over several lines, the symbol leads the first one and the paragraph is centred as a whole,
                // instead of sitting at the edge beside short centred lines. A figure space doesn't break.
                (Text(Image(systemName: systemImage)) + Text(verbatim: "\u{2007}") + Text(text))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(text))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                    Text(text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.ryft(.caption))
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

/// The way to a fix under a `GaugeNote` (design.md §7 rev. 2 §5): "How to set up Garmin Connect ›" in `callout`
/// and `Theme.accent`, centred and wrapping, at least 44 pt tall, its own VoiceOver button. It opens a sheet;
/// nothing on it moves.
struct GaugeNoteLink: View {
    let title: String
    let action: () -> Void

    /// Above and below the title, scaled with the text: at large sizes the title outgrows the 44 pt minimum, which
    /// then no longer leaves room between the note and the link. At the default size the minimum still decides.
    @ScaledMetric(relativeTo: .callout) private var inset: CGFloat = 6

    var body: some View {
        Button(action: action) {
            // One text, so the chevron follows the last word when the title wraps (German at AX3).
            (Text(title) + Text(verbatim: "\u{00A0}") + Text(Image(systemName: "chevron.right")).font(.ryft(.caption)))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, inset)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        // No press motion: the plain style only dims the label.
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .accessibilityLabel(Text(title))
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
                OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 2, signal: .heartRateNights)), size: .large,
                           caption: OrbitGauge.Caption(title: String(localized: "Baselines")), animatesFill: false)
                GaugeNote(text: String(localized: "Baselines need heart-rate variability and resting heart rate from nights with your watch."),
                          systemImage: "info.circle")
            }
        }
    }
}

/// F3: only resting heart rate fills (no HRV arrives), no readiness yet: the gauge counts its nights and says so.
#Preview("Gauge note · one signal", traits: .sizeThatFitsLayout) {
    let progress = CalibrationProgress(nights: 3, signals: [.restingHR],
                                       absent: CalibrationBlocker(signals: [.hrv], source: .unknown, link: nil))
    SchemePair {
        VStack(spacing: 8) {
            OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3, signal: .restingHR)), size: .large,
                       caption: OrbitGauge.Caption(title: String(localized: "Baselines")), animatesFill: false)
            GaugeNote(text: progress.text, systemImage: "info.circle")
        }
    }
}

#Preview("Gauge notes · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 2, signal: .heartRateNights)), size: .large,
                       caption: OrbitGauge.Caption(title: String(localized: "Baselines")), animatesFill: false)
            GaugeNote(text: String(localized: "Recalculating your baselines"), systemImage: "arrow.triangle.2.circlepath")
            GaugeNote(text: String(localized: "Baselines need heart-rate variability and resting heart rate from nights with your watch."),
                      systemImage: "info.circle")
        }
    }
    .environment(\.locale, Locale(identifier: "de"))
    .environment(\.dynamicTypeSize, .accessibility3)
}

/// N1 under the gauge (design.md §7 rev. 2): Garmin chosen, no HRV in the window. The band word gives the note its
/// line; the link opens Garmin Connect's card.
@MainActor
private func blockedNotePreview() -> some View {
    let blocker = CalibrationBlocker.resolve([.hrv], trackers: [MockData.tracker("garmin")], devicesSetup: true)
    return VStack(spacing: 8) {
        MetricGauge(spec: .readiness, value: 74, size: .large, title: String(localized: "Overall readiness"),
                    showsMark: true, accessibilityNote: blocker.text, showsBand: false)
        GaugeNote(text: blocker.text, systemImage: "info.circle")
        if let link = blocker.link { GaugeNoteLink(title: link.title) {} }
    }
}

#Preview("Gauge note · link", traits: .sizeThatFitsLayout) {
    SchemePair { blockedNotePreview() }
}

#Preview("Gauge note · link · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair { blockedNotePreview() }
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
