import SwiftUI

// The launch entrance of `OrbitGauge` (PR 3): the gauge assembles once, then is the real mode. Presentation only:
// the mode is data and never says "assembling". View state and one linear animation of a clock; the curves are
// applied inside `OrbitEntranceFrame`, so a test can ask for any moment (docs/work/2026-10-29-orbit-gauge/design.md §10;
// what each stage draws on gauge v3: docs/work/2026-11-16-nocturne/design.md §P3-1).

extension OrbitGauge {
    /// Whether the gauge plays its launch entrance. The view latches the value when it first appears: later changes
    /// are ignored by that instance, and it plays at most once per instance.
    enum Entrance: Hashable, Sendable {
        case none
        case assemble
        /// The same entrance over tracks already on screen: Today replaces a placeholder (the empty orbit, drawn while
        /// its data is on its way) with the gauge that has it. Tracks and the centre ring are there from the first
        /// frame, never trimmed in again; the dots fly in, then the glide. Under Reduce Motion or Low Power Mode the
        /// marks and the number fade in over the tracks.
        case assembleOverTracks

        /// This instance plays an entrance.
        var plays: Bool { self != .none }
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
    /// `Entrance.assembleOverTracks`: the tracks are drawn from the start (no trim).
    var overTracks = false

    /// How much of its track an orbit has drawn, 0...1: strain first, the inner orbit next, the centre ring last. All
    /// of it from the start over tracks already on screen.
    func trim(_ track: Track) -> Double {
        if overTracks { return 1 }
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
struct OrbitEntranceStage<Settled: View, Centre: View>: View {
    var elapsed: Double
    let reduced: Bool
    /// `Entrance.assembleOverTracks`: the choreography's tracks are whole from the start; under `reduced` the caller
    /// fades the marks inside `settled` and the stage leaves its opacity alone (the tracks never fade).
    var overTracks = false
    /// The entrance has finished (its completion ran): the settled drawing, whatever `reduced` has become since
    /// (Reduce Motion turned off after a fade ended must not land on a frame of the choreography).
    var done = false
    let mode: OrbitGaugeMode
    let size: OrbitGaugeSize
    let palette: OrbitGaugePalette
    let settled: Settled
    let centre: Centre

    /// One identity for `settled` in the fade, at the end and after it, so the drawing and its breathing are never
    /// rebuilt on the way.
    var body: some View {
        if done || reduced || elapsed >= OrbitEntranceFrame.end {
            let fades = reduced && !done && !overTracks
            settled
                .opacity(fades ? OrbitEntranceFrame.eased(elapsed, 0, OrbitEntranceFrame.fadeDuration) : 1)
                .transition(.identity)
        } else {
            choreography.transition(.identity)
        }
    }

    // MARK: the choreography

    /// The shared drawing at this moment's scene: the same tracks, marks and centre as the static gauge, so the last
    /// frame is that gauge by construction.
    private var choreography: some View {
        let frame = OrbitEntranceFrame(seconds: elapsed, overTracks: overTracks)
        let scene = OrbitGaugeScene(mode: mode, size: size, entrance: frame)
        return ZStack {
            OrbitGaugeTracks(scene: scene, palette: palette)
            OrbitGaugeMarks(scene: scene, palette: palette)
            centre
                .frame(width: max(scene.metrics.centreSlotWidth, 0))
                .opacity(frame.glide)
        }
        .frame(width: size.frame, height: size.frame)
    }
}

extension OrbitGaugeScene {
    /// The gauge at one moment of the entrance (design.md §P3-1, "Entrance on v3"). Tracks: the outer ticks (or ring, or
    /// segments) clockwise with `trim(.strain)`, the middle ring from the top both ways with `trim(.inner)`, the unlit
    /// inner ticks clockwise with `trim(.centre)`. Flight: the orbit dots fly in, their halos growing with them; no Volt
    /// dot yet. Glide: the arcs fill behind the dots, the Volt dot fades in at the top and travels to the value with the
    /// lit ticks behind it. The band's rail fades in with the tracks. At the end every value is the static scene's.
    init(mode: OrbitGaugeMode, size: OrbitGaugeSize, entrance frame: OrbitEntranceFrame) {
        self.init(mode: mode, size: size)
        outerTrack = frame.trim(.strain)
        middleTrack = frame.trim(.inner)
        innerTrack = frame.trim(.centre)
        progress = frame.glide
        // Outside the bounds at every angle.
        let far = size.frame * 0.62
        for orbit in OrbitGaugeGeometry.Orbit.allCases {
            let settled = dot(orbit)
            let at = frame.dot(orbit, sweep: settled.sweep, orbitRadius: settled.radius, farRadius: far)
            // The dot is at `at`; its sweep is the arc's so far, so the strain dot turns alert when the arc's head passes
            // the band (not at the dot's flight angle, which includes the 40 deg turn).
            let sweep = settled.sweep * frame.glide
            let flight = frame.flight(orbit)
            setDot(orbit, Dot(radius: at.radius, start: at.degrees - sweep, sweep: sweep,
                              opacity: min(flight * 4, 1), halo: flight))
        }
        voltOpacity = min(frame.glide * 4, 1)
        railOpacity = OrbitEntranceFrame.eased(frame.seconds, 0, OrbitEntranceFrame.tracksEnd)
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
            Button { run += 1 } label: { Text(verbatim: "Replay") }
                .font(.ryft(.caption))
        }
    }
}

#Preview("OrbitGauge · entrance, replay") {
    DarkPreview {
        HStack(alignment: .top, spacing: 8) {
            EntranceReplay(mode: .scored(.previewScored), size: .medium)
            EntranceReplay(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .medium)
            EntranceReplay(mode: .pending(previous: .previewScored), size: .medium)
        }
    }
}

#Preview("OrbitGauge · entrance, Reduce Motion") {
    DarkPreview {
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
    DarkPreview {
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

#Preview("OrbitGauge · entrance over tracks", traits: .sizeThatFitsLayout) {
    // Today's placeholder (the empty orbit) first, then the gauge that replaces it frozen at t = 0, 0.25, 0.6 s and
    // the end: the tracks are whole from the first frame, the dots fly in over them.
    DarkPreview {
        HStack(spacing: 4) {
            OrbitGauge(mode: .scored(.empty), size: .small)
            ForEach([0.0, 0.25, 0.6, OrbitEntranceFrame.end], id: \.self) { t in
                OrbitGauge(mode: .scored(.previewScored), size: .small, entrance: .assembleOverTracks, frozenAt: t)
            }
        }
    }
}
