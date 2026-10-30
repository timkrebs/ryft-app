import SwiftUI

// The launch entrance of `OrbitGauge` (PR 3): the gauge assembles once, then is the real mode. Presentation only:
// the mode is data and never says "assembling". View state and one linear animation of a clock; the curves are
// applied inside `OrbitEntranceFrame`, so a test can ask for any moment (docs/work/2026-10-29-orbit-gauge/design.md §10).

extension OrbitGauge {
    /// Whether the gauge plays its launch entrance. The view latches the value when it first appears: later changes
    /// are ignored by that instance, and it plays at most once per instance.
    enum Entrance: Hashable, Sendable {
        case none
        case assemble
    }
}

/// The entrance as numbers. Seconds from the start; every curve is ease-out, none overshoots.
struct OrbitEntranceFrame: Equatable {
    // MARK: timings (seconds)

    /// The tracks draw themselves; the centre ring last.
    static let tracksEnd = 0.25
    /// The dots fly in and make a part of one turn: 150 ms to 600 ms, each dot `dotStagger` after the one before.
    static let flightStart = 0.15
    static let flightEnd = 0.60
    static let dotStagger = 0.03
    /// The dots glide to their value positions while the arcs fill behind them: `Theme.Motion.quick`'s 250 ms.
    static let glideStart = flightEnd
    static let glideDuration = 0.25
    static let end = glideStart + glideDuration
    /// Reduce Motion and Low Power Mode: a cross-fade at the values, `Theme.Motion.quick`.
    static let fadeDuration = 0.25
    /// The turn the dots make during the flight.
    static let turnDegrees = 40.0

    /// ease-out cubic of the linear progress of `t` through `from...to`.
    static func eased(_ t: Double, _ from: Double, _ to: Double) -> Double {
        let x = min(max((t - from) / (to - from), 0), 1)
        return 1 - pow(1 - x, 3)
    }

    var seconds: Double

    /// How much of its track an orbit has drawn, 0...1: strain first, the inner orbit next, the centre ring last.
    func trim(_ track: Track) -> Double {
        switch track {
        case .strain: return Self.eased(seconds, 0, 0.15)
        case .inner: return Self.eased(seconds, 0.05, 0.20)
        case .centre: return Self.eased(seconds, 0.10, Self.tracksEnd)
        }
    }

    enum Track { case strain, inner, centre }

    /// The dot's flight, 0 (outside the bounds) ... 1 (on its orbit, turned by `turnDegrees`).
    func flight(_ orbit: OrbitGaugeGeometry.Orbit) -> Double {
        let delay: Double
        switch orbit {
        case .strain: delay = 0
        case .recovery: delay = Self.dotStagger
        case .sleep: delay = 2 * Self.dotStagger
        }
        return Self.eased(seconds, Self.flightStart + delay, Self.flightEnd - (2 * Self.dotStagger - delay))
    }

    /// The glide to the values, 0...1: the arcs' sweep, the dots' last leg, the centre ring's colour and the number.
    var glide: Double { Self.eased(seconds, Self.glideStart, Self.end) }

    /// Where a dot is: degrees clockwise from the top and the radius. It flies in to its orbit's start and turns
    /// `turnDegrees` along the orbit; the glide then takes it from there to the head of its arc (`sweep`, 0 for a
    /// missing score, which glides back to the start), so it is at the head exactly when the glide ends.
    func dot(_ orbit: OrbitGaugeGeometry.Orbit, sweep: Double, orbitRadius: CGFloat, farRadius: CGFloat)
        -> (degrees: Double, radius: CGFloat) {
        let f = flight(orbit)
        let direction: Double = orbit.trackSweep < 0 ? -1 : 1
        let turned = direction * Self.turnDegrees * f
        let g = glide
        return (orbit.startDegrees + turned * (1 - g) + sweep * g, farRadius + (orbitRadius - farRadius) * CGFloat(f))
    }
}

/// The entrance drawn at one moment. `elapsed` is its animatable clock: a view animates it linearly and the curves
/// above shape it; at its end (or in the fade, at `fadeDuration`) it draws what `settled` is, so the last frame is the
/// static drawing and nothing swaps. `reduced`: a cross-fade of `settled` instead of the choreography.
struct OrbitEntranceStage<Settled: View, Centre: View>: View, Animatable {
    var elapsed: Double
    let reduced: Bool
    /// The entrance has finished (its completion ran): the settled drawing, whatever `reduced` has become since
    /// (Reduce Motion turned off after a fade ended must not land on a frame of the choreography).
    var done = false
    let mode: OrbitGaugeMode
    let size: OrbitGaugeSize
    let palette: OrbitGaugePalette
    let settled: Settled
    let centre: Centre

    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    var body: some View {
        if done {
            settled.transition(.identity)
        } else if reduced {
            settled
                .opacity(min(max(elapsed / OrbitEntranceFrame.fadeDuration, 0), 1))
                .transition(.identity)
        } else if elapsed >= OrbitEntranceFrame.end {
            settled.transition(.identity)
        } else {
            choreography.transition(.identity)
        }
    }

    // MARK: the choreography

    private var choreography: some View {
        let frame = OrbitEntranceFrame(seconds: elapsed)
        let m = OrbitGaugeGeometry.metrics(forDial: size.dial)
        let values = mode.drawnValues
        let calibration = mode.calibratingValue
        let glide = frame.glide
        // Outside the bounds at every angle.
        let far = size.frame * 0.62
        let hasRing = values != nil
        let positions = Dictionary(uniqueKeysWithValues: OrbitGaugeGeometry.Orbit.allCases.map { orbit -> (OrbitGaugeGeometry.Orbit, (degrees: Double, radius: CGFloat)) in
            let sweep = orbit.sweep(for: values.flatMap { orbit.fraction(of: $0) } ?? 0)
            return (orbit, frame.dot(orbit, sweep: sweep, orbitRadius: m.radius(of: orbit), farRadius: far))
        })
        let centreD = m.centreRadius * 2 + m.centreStroke
        return ZStack {
            // Tracks: the air around a dot is cut from its own orbit only, so a dot on its way in leaves no gap in
            // the rings it crosses.
            tracks(frame, m, calibration, positions)
            // Under the readiness ring only where the static drawing has one too: never a ring that is not there.
            if hasRing {
                Circle().trim(from: 0, to: frame.trim(.centre)).rotation(.degrees(-90))
                    .stroke(palette.band(forReadiness: values?.readiness),
                            style: StrokeStyle(lineWidth: m.centreStroke, lineCap: .round))
                    .frame(width: centreD - m.centreStroke, height: centreD - m.centreStroke)
                    .opacity(glide * (mode.isPending ? OrbitGaugeMarks.pendingOpacity : 1))
            }
            marks(frame, m, values, positions, glide)
            centre
                .frame(width: max(m.centreSlotWidth, 0))
                .opacity(glide)
        }
        .frame(width: size.frame, height: size.frame)
    }

    @ViewBuilder
    private func tracks(_ frame: OrbitEntranceFrame, _ m: OrbitGaugeGeometry.Metrics,
                        _ calibration: OrbitGaugeCalibration?,
                        _ positions: [OrbitGaugeGeometry.Orbit: (degrees: Double, radius: CGFloat)]) -> some View {
        let cut = { (orbit: OrbitGaugeGeometry.Orbit) in
            OrbitDot(radius: positions[orbit]?.radius ?? 0, start: positions[orbit]?.degrees ?? 0, sweep: 0,
                     dotRadius: m.dotRadius + m.dotAir)
        }
        // Strain: the ring, or the calibrating segments, trimmed together.
        ZStack {
            if let calibration {
                ForEach(Array(OrbitGaugeGeometry.segments(required: calibration.required, dial: size.dial).enumerated()),
                        id: \.offset) { _, segment in
                    OrbitArc(radius: m.outerRadius, start: segment.start, sweep: segment.sweep * frame.trim(.strain))
                        .stroke(palette.track, style: StrokeStyle(lineWidth: m.outerStroke, lineCap: .round))
                }
            } else {
                OrbitArc(radius: m.outerRadius, start: 0,
                         sweep: OrbitGaugeGeometry.Orbit.strain.trackSweep * frame.trim(.strain))
                    .stroke(palette.track, style: StrokeStyle(lineWidth: m.outerStroke, lineCap: .round))
            }
            cutting(cut(.strain))
        }
        .compositingGroup()
        ZStack {
            ForEach([OrbitGaugeGeometry.Orbit.recovery, .sleep], id: \.self) { orbit in
                OrbitArc(radius: m.innerRadius, start: orbit.startDegrees, sweep: orbit.trackSweep * frame.trim(.inner))
                    .stroke(palette.track, style: StrokeStyle(lineWidth: m.innerStroke, lineCap: .round))
            }
            cutting(cut(.recovery))
            cutting(cut(.sleep))
        }
        .compositingGroup()
        // The centre ring draws last. Its track stays under it where the static drawing has one (no readiness, or
        // pending) and hands over to the band-coloured ring during the glide where it has none.
        let d = m.centreRadius * 2
        let staysUnder = mode.drawnValues == nil || mode.isPending
        Circle().trim(from: 0, to: frame.trim(.centre)).rotation(.degrees(-90))
            .stroke(palette.track, style: StrokeStyle(lineWidth: m.centreStroke, lineCap: .round))
            .frame(width: d, height: d)
            .opacity(staysUnder ? 1 : 1 - frame.glide)
    }

    private func cutting(_ shape: OrbitDot) -> some View {
        shape.fill(.black).blendMode(.destinationOut)
    }

    /// Per orbit: the arc filling behind its dot, and the dot, filled for a score, hollow for a missing one.
    private func marks(_ frame: OrbitEntranceFrame, _ m: OrbitGaugeGeometry.Metrics, _ values: OrbitGaugeValues?,
                       _ positions: [OrbitGaugeGeometry.Orbit: (degrees: Double, radius: CGFloat)],
                       _ glide: Double) -> some View {
        ZStack {
            ForEach(OrbitGaugeGeometry.Orbit.allCases, id: \.self) { orbit in
                let fraction = values.flatMap { orbit.fraction(of: $0) }
                let colour = palette.colour(of: orbit)
                let position = positions[orbit] ?? (degrees: 0, radius: 0)
                if let fraction {
                    OrbitArc(radius: m.radius(of: orbit), start: orbit.startDegrees,
                             sweep: orbit.sweep(for: fraction) * glide)
                        .stroke(colour, style: StrokeStyle(lineWidth: m.stroke(of: orbit), lineCap: .round))
                    dotShape(position, m).fill(colour)
                        .opacity(min(frame.flight(orbit) * 4, 1))
                } else {
                    dotShape(position, m).stroke(colour, lineWidth: m.hollowStroke)
                        .opacity(min(frame.flight(orbit) * 4, 1))
                }
            }
        }
        .compositingGroup()
        .opacity(mode.isPending ? OrbitGaugeMarks.pendingOpacity : 1)
    }

    private func dotShape(_ position: (degrees: Double, radius: CGFloat), _ m: OrbitGaugeGeometry.Metrics) -> OrbitDot {
        OrbitDot(radius: position.radius, start: position.degrees, sweep: 0, dotRadius: m.dotRadius)
    }
}

extension EnvironmentValues {
    /// Previews: draw as under Reduce Motion.
    @Entry var orbitForcesReducedMotion = false
}

// MARK: previews (synthetic values only)

/// Plays the entrance of one mode; Replay builds the gauge again (a new view instance plays once more).
private struct EntranceReplay: View {
    let mode: OrbitGaugeMode
    var size: OrbitGaugeSize = .large
    @State private var run = 0

    var body: some View {
        VStack(spacing: 8) {
            OrbitGauge(mode: mode, size: size, entrance: .assemble)
                .id(run)
                .padding(24)
            Button("Replay") { run += 1 }
                .font(.ryft(.caption))
        }
    }
}

#Preview("OrbitGauge · entrance, replay") {
    SchemePair {
        HStack(alignment: .top, spacing: 8) {
            EntranceReplay(mode: .scored(.previewScored), size: .medium)
            EntranceReplay(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .medium)
            EntranceReplay(mode: .pending(previous: .previewScored), size: .medium)
        }
    }
}

#Preview("OrbitGauge · entrance, Reduce Motion") {
    SchemePair {
        HStack(alignment: .top, spacing: 8) {
            EntranceReplay(mode: .scored(.previewScored), size: .medium)
            EntranceReplay(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .medium)
            EntranceReplay(mode: .pending(previous: .previewScored), size: .medium)
        }
    }
    .environment(\.orbitForcesReducedMotion, true)
}

#Preview("OrbitGauge · entrance frames", traits: .sizeThatFitsLayout) {
    // Frozen at t = 0, 0.25, 0.6 s and the end: nothing in it depends on time.
    SchemePair {
        VStack(spacing: 4) {
            ForEach([0.0, 0.25, 0.6, OrbitEntranceFrame.end], id: \.self) { t in
                HStack(spacing: 4) {
                    OrbitGauge(mode: .scored(.previewScored), size: .small, entrance: .assemble, frozenAt: t)
                    OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .small, animatesFill: false,
                               entrance: .assemble, frozenAt: t)
                    OrbitGauge(mode: .pending(previous: .previewScored), size: .small, breathes: false,
                               entrance: .assemble, frozenAt: t)
                }
            }
        }
    }
}
