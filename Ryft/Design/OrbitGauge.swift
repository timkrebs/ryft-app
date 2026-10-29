import SwiftUI

/// The RYFT mark as the readiness gauge: the centre ring is Readiness (its number inside), the inner orbit
/// carries Recovery (counter-clockwise from the top) and Sleep (clockwise), the outer orbit carries Strain
/// (clockwise, 21 = a whole turn). Arc length is the score, the dot at its head is where you are today. A score
/// that is missing is a hollow dot at the start, never an arc and never a zero. Nothing rotates on its own.
///
/// Geometry, mapping and colours: `OrbitGaugeGeometry`, docs/work/2026-10-29-orbit-gauge/design.md.
/// `.calibrating`, `.assembling` and `.pending` only draw the tracks and the hollow dots until PR 2 / PR 3.
struct OrbitGauge: View {
    enum Size: Equatable {
        case small, medium, large
        /// An exact dial, for the widget's other families and for checks. Screens use the three above.
        case custom(dial: CGFloat)

        /// The drawing's diameter: `MetricGauge`'s dial, so nothing around the gauge moves.
        var dial: CGFloat {
            switch self {
            case .small: return 72
            case .medium: return 112
            case .large: return 160
            case .custom(let dial): return dial
            }
        }

        /// The frame: the dial plus the 6 pt `MetricGauge` keeps free on every side for its ticks. Here the
        /// outer dot's overshoot and the Today padding use it.
        var frame: CGFloat { dial + 12 }
    }

    let mode: OrbitGaugeMode
    var size: Size = .large
    /// Read after the value, e.g. a `GaugeNote` shown under the gauge ("Recalculating your baselines").
    var accessibilityNote: String?
    /// Today uses `today.readinessGauge`.
    var identifier: String = "orbitGauge"

    /// Below this dial the number would be under 10.5 pt: the gauge is the mark only (VoiceOver still has the value).
    static let minDialForNumber: CGFloat = 56

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var values: OrbitGaugeValues? {
        if case .scored(let v) = mode { return v }
        return nil
    }

    var body: some View {
        ZStack {
            drawing
                // Reduce Motion: no arc moves; a new value cross-fades (250 ms) instead.
                .id(reduceMotion ? AnyHashable(mode) : AnyHashable(0))
                .transition(.opacity)
        }
        .frame(width: size.frame, height: size.frame)
        // The arcs and the dots ride the same animation; the number rolls with it.
        .animation(reduceMotion ? Theme.Motion.quick : Theme.Motion.slow, value: mode)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Overall readiness"))
        .accessibilityValue(Text(spokenValue))
        .accessibilityIdentifier(identifier)
    }

    // MARK: drawing

    private var drawing: some View {
        let m = OrbitGaugeGeometry.metrics(forDial: size.dial)
        return ZStack {
            tracks(m)
            ForEach(OrbitGaugeGeometry.Orbit.allCases, id: \.self) { orbit in
                orbitMarks(orbit, m)
            }
            centre(m)
        }
    }

    /// Tracks in `surfaceRaised`, with the air around every dot cut out of them, as the mark cuts its rings.
    private func tracks(_ m: OrbitGaugeGeometry.Metrics) -> some View {
        ZStack {
            ForEach(OrbitGaugeGeometry.Orbit.allCases, id: \.self) { orbit in
                OrbitArc(radius: m.radius(of: orbit), start: orbit.startDegrees, sweep: orbit.trackSweep)
                    .stroke(Theme.surfaceRaised, style: StrokeStyle(lineWidth: m.stroke(of: orbit), lineCap: .round))
            }
            ForEach(OrbitGaugeGeometry.Orbit.allCases, id: \.self) { orbit in
                OrbitDot(radius: m.radius(of: orbit), start: orbit.startDegrees,
                         sweep: orbit.sweep(for: fraction(of: orbit) ?? 0), dotRadius: m.dotRadius + m.dotAir)
                    .fill(.black)
                    .blendMode(.destinationOut)
            }
            if values == nil {
                Circle()
                    .inset(by: m.centreStroke / 2)
                    .stroke(Theme.surfaceRaised, lineWidth: m.centreStroke)
                    .frame(width: m.centreRadius * 2 + m.centreStroke, height: m.centreRadius * 2 + m.centreStroke)
            }
        }
        .compositingGroup()
    }

    /// The arc and the filled dot of a present score, or the hollow dot of a missing one.
    @ViewBuilder
    private func orbitMarks(_ orbit: OrbitGaugeGeometry.Orbit, _ m: OrbitGaugeGeometry.Metrics) -> some View {
        let colour = colour(of: orbit)
        if let f = fraction(of: orbit) {
            OrbitArc(radius: m.radius(of: orbit), start: orbit.startDegrees, sweep: orbit.sweep(for: f))
                .stroke(colour, style: StrokeStyle(lineWidth: m.stroke(of: orbit), lineCap: .round))
            OrbitDot(radius: m.radius(of: orbit), start: orbit.startDegrees, sweep: orbit.sweep(for: f),
                     dotRadius: m.dotRadius)
                .fill(colour)
        } else {
            OrbitDot(radius: m.radius(of: orbit), start: orbit.startDegrees, sweep: 0, dotRadius: m.dotRadius)
                .stroke(colour, lineWidth: m.hollowStroke)
        }
    }

    /// The centre ring in the band colour, or `textPrimary` without a readiness, with the number inside.
    @ViewBuilder
    private func centre(_ m: OrbitGaugeGeometry.Metrics) -> some View {
        if let values {
            let d = m.centreRadius * 2 + m.centreStroke
            Circle()
                .inset(by: m.centreStroke / 2)
                .stroke(values.readiness.map { Theme.band(forScore: $0) } ?? Theme.textPrimary, lineWidth: m.centreStroke)
                .frame(width: d, height: d)
            if size.dial >= Self.minDialForNumber {
                Text(values.readiness.map { String($0) } ?? Fmt.placeholder)
                    .font(.ryftNumber(size: size.dial * 0.19))
                    .monospacedDigit()
                    .foregroundStyle(values.readiness == nil ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: m.centreInnerDiameter - 10)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(values.readiness ?? 0)))
            }
        }
    }

    private func fraction(of orbit: OrbitGaugeGeometry.Orbit) -> Double? {
        guard let values else { return nil }
        switch orbit {
        case .recovery: return values.recoveryFraction
        case .sleep: return values.sleepFraction
        case .strain: return values.strainFraction
        }
    }

    private func colour(of orbit: OrbitGaugeGeometry.Orbit) -> Color {
        switch orbit {
        case .recovery: return Theme.accent
        case .sleep: return Theme.metricSleep
        case .strain: return Theme.metricStrain
        }
    }

    // MARK: VoiceOver

    /// "71, High. Recovery 71 percent, Sleep 88 percent, Strain 9.6 of 21." plus the note. A missing score is
    /// named as missing, never skipped.
    private var spokenValue: String {
        let spoken: String
        switch mode {
        case .scored(let v):
            spoken = Self.spokenValue(v)
        case .calibrating, .assembling, .pending:
            // PR 2 / PR 3 give these their own sentences.
            spoken = String(localized: "Not scored yet")
        }
        return accessibilityNote.map { "\(spoken). \($0)" } ?? spoken
    }

    static func spokenValue(_ v: OrbitGaugeValues) -> String {
        if v.isEmpty { return String(localized: "No data") }
        let noData = { (title: String) in String(localized: "\(title), no data") }
        var scores: [String] = []
        scores.append(v.recoveryFraction.map { String(localized: "Recovery \(Self.percent($0)) percent") }
                      ?? noData(String(localized: "Recovery")))
        scores.append(v.sleepFraction.map { String(localized: "Sleep \(Self.percent($0)) percent") }
                      ?? noData(String(localized: "Sleep")))
        scores.append(v.strain.map { String(localized: "Strain \(Self.strainText($0)) of 21") }
                      ?? noData(String(localized: "Strain")))
        let readiness = v.readiness.map { "\($0), \(MetricSpec.scoreBand(Double($0)).label)" }
            ?? String(localized: "Overall readiness, no data")
        return "\(readiness). \(scores.joined(separator: ", "))"
    }

    private static func percent(_ fraction: Double) -> String {
        Int((fraction * 100).rounded()).formatted()
    }

    private static func strainText(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(1)))
    }
}


// MARK: shapes

/// An arc of an orbit: starts at `start` (degrees clockwise from the top) and sweeps `sweep` degrees, negative
/// counter-clockwise. The sweep animates, so the arc grows with `trim`'s feel and a changing score moves on from
/// where it was.
struct OrbitArc: Shape {
    var radius: CGFloat
    var start: Double
    var sweep: Double

    var animatableData: Double {
        get { sweep }
        set { sweep = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        // A zero sweep with a round cap would still leave a dot: the start dot is the dot's job.
        guard abs(sweep) > 0.05 else { return p }
        // SwiftUI's `clockwise` is mirrored in y-down space: false = visually clockwise.
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                 startAngle: .degrees(start - 90), endAngle: .degrees(start + sweep - 90),
                 clockwise: sweep < 0)
        return p
    }
}

/// The dot at the head of an arc: a circle centred on the orbit at `start + sweep`. Fill it for a score, stroke
/// it for a missing one (sweep 0). It rides the same animatable sweep as the arc.
struct OrbitDot: Shape {
    var radius: CGFloat
    var start: Double
    var sweep: Double
    var dotRadius: CGFloat

    var animatableData: Double {
        get { sweep }
        set { sweep = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = OrbitGaugeGeometry.point(centre: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                                         degrees: start + sweep)
        return Path(ellipseIn: CGRect(x: c.x - dotRadius, y: c.y - dotRadius,
                                      width: dotRadius * 2, height: dotRadius * 2))
    }
}

// MARK: previews (synthetic values only)

extension OrbitGaugeValues {
    /// 71 / 71 % / 88 % / 9.6, the values the previews, the screenshots and the tests share.
    static let previewScored = OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)
}

private struct OrbitCaption: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
    }
}

#Preview("OrbitGauge · sizes", traits: .sizeThatFitsLayout) {
    SchemePair {
        HStack(alignment: .center, spacing: 12) {
            OrbitGauge(mode: .scored(.previewScored), size: .large)
            VStack(spacing: 8) {
                OrbitGauge(mode: .scored(.previewScored), size: .medium)
                OrbitGauge(mode: .scored(.previewScored), size: .small)
            }
        }
    }
}

#Preview("OrbitGauge · missing and edges", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                VStack { OrbitGauge(mode: .scored(OrbitGaugeValues()), size: .medium); OrbitCaption(text: "all missing") }
                VStack {
                    // A watch without HRV: Recovery from what the platform scored, no sleep yet.
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, strain: 6.2)), size: .medium)
                    OrbitCaption(text: "sleep missing")
                }
                VStack {
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, sleep: 0.81)), size: .medium)
                    OrbitCaption(text: "strain missing")
                }
            }
            HStack(spacing: 8) {
                VStack {
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 1, recovery: 0, sleep: 0, strain: 0)), size: .medium)
                    OrbitCaption(text: "0")
                }
                VStack {
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 100, recovery: 1, sleep: 1, strain: 21)), size: .medium)
                    OrbitCaption(text: "100")
                }
                VStack {
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 28, recovery: 0.24, sleep: 0.41, strain: 17.8)), size: .medium)
                    OrbitCaption(text: "low")
                }
            }
        }
    }
}

#Preview("OrbitGauge · bands and stubs", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 82, recovery: 0.8, sleep: 0.9, strain: 12)), size: .small)
                OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 50, recovery: 0.5, sleep: 0.7, strain: 12)), size: .small)
                OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 20, recovery: 0.2, sleep: 0.3, strain: 12)), size: .small)
            }
            HStack(spacing: 8) {
                OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .small)
                OrbitGauge(mode: .assembling, size: .small)
                OrbitGauge(mode: .pending(previous: 71), size: .small)
            }
        }
    }
}

#Preview("OrbitGauge · AX3", traits: .sizeThatFitsLayout) {
    // The gauge keeps its size; the caption around it scales.
    SchemePair {
        VStack(spacing: 8) {
            OrbitGauge(mode: .scored(.previewScored), size: .large)
            Text("Moderate · 4 up on 7 d").font(.ryft(.caption)).foregroundStyle(Theme.textSecondary)
            OrbitGauge(mode: .scored(.previewScored), size: .small)
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("OrbitGauge · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 8) {
            OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 100, recovery: 1, sleep: 1, strain: 21)), size: .large)
            Text(OrbitGauge.spokenValue(.previewScored)).font(.ryft(.caption)).foregroundStyle(Theme.textSecondary)
        }
    }
    .environment(\.locale, Locale(identifier: "de"))
    .environment(\.dynamicTypeSize, .accessibility3)
}
