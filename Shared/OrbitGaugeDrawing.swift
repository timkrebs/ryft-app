// The orbit gauge's static drawing, shared by the app and the widget (ADR 0010): tracks, arcs, dots and the centre
// ring, deterministic, from a mode, a size and a palette. No strings, no fonts, no accessibility, no timers: the
// wrappers add those (`Ryft/Design/OrbitGauge.swift` in the app, `RyftWidgets/WidgetOrbitGauge.swift` in the widget).
//
// Geometry and mapping: `OrbitGaugeGeometry`, docs/work/2026-10-29-orbit-gauge/design.md. `.calibrating` draws the
// outer orbit as segments, `.pending` the previous day's marks dimmed. The launch entrance is not a mode: the
// app's wrapper plays it (`Ryft/Design/OrbitGaugeEntrance.swift`).
import SwiftUI

/// The gauge's sizes: `MetricGauge`'s dials, so nothing around the gauge moves.
enum OrbitGaugeSize: Hashable, Sendable {
    case small, medium, large
    /// An exact dial, for the widget's other families and for checks. Screens use the three above.
    case custom(dial: CGFloat)

    /// The drawing's diameter.
    var dial: CGFloat {
        switch self {
        case .small: return 72
        case .medium: return 112
        case .large: return 160
        case .custom(let dial): return dial
        }
    }

    /// The frame: the dial plus the 6 pt `MetricGauge` keeps free on every side for its ticks. Here the outer dot's
    /// overshoot and the Today padding use it.
    var frame: CGFloat { dial + 12 }
}

/// The whole drawing: tracks, then the marks (arcs, dots, the centre ring), then the caller's centre content
/// (the number) framed inside the centre ring. `mode == nil` is "unknown" (a widget snapshot written before the
/// orbit): tracks only, never hollow dots that would say "missing".
///
/// `marks` lets a caller style the marks layer alone: the widget makes it `widgetAccentable()` for tinted and clear
/// home screens while the tracks stay in the default group.
struct OrbitGaugeDrawing<Marks: View, Centre: View>: View {
    let mode: OrbitGaugeMode?
    var size: OrbitGaugeSize
    var palette: OrbitGaugePalette
    private let styleMarks: (OrbitGaugeMarks) -> Marks
    private let centre: Centre

    init(mode: OrbitGaugeMode?, size: OrbitGaugeSize = .large, palette: OrbitGaugePalette = .assets,
         @ViewBuilder marks: @escaping (OrbitGaugeMarks) -> Marks, @ViewBuilder centre: () -> Centre) {
        self.mode = mode
        self.size = size
        self.palette = palette
        self.styleMarks = marks
        self.centre = centre()
    }

    var body: some View {
        let m = OrbitGaugeGeometry.metrics(forDial: size.dial)
        ZStack {
            OrbitGaugeTracks(mode: mode, dial: size.dial, palette: palette)
            if let mode {
                styleMarks(OrbitGaugeMarks(mode: mode, dial: size.dial, palette: palette))
            }
            centre
                .frame(width: max(m.centreSlotWidth, 0))
        }
        .frame(width: size.frame, height: size.frame)
    }
}

extension OrbitGaugeDrawing where Marks == OrbitGaugeMarks {
    init(mode: OrbitGaugeMode?, size: OrbitGaugeSize = .large, palette: OrbitGaugePalette = .assets,
         @ViewBuilder centre: () -> Centre) {
        self.init(mode: mode, size: size, palette: palette, marks: { $0 }, centre: centre)
    }
}

extension OrbitGaugeDrawing where Marks == OrbitGaugeMarks, Centre == EmptyView {
    init(mode: OrbitGaugeMode?, size: OrbitGaugeSize = .large, palette: OrbitGaugePalette = .assets) {
        self.init(mode: mode, size: size, palette: palette, marks: { $0 }, centre: { EmptyView() })
    }
}

/// Tracks in the palette's track colour, with the air around every dot cut out of them, as the mark cuts its rings.
/// The centre ring's track only where no readiness ring is drawn over it (the stubs, an unknown mode).
struct OrbitGaugeTracks: View {
    let mode: OrbitGaugeMode?
    let dial: CGFloat
    let palette: OrbitGaugePalette

    var body: some View {
        let m = OrbitGaugeGeometry.metrics(forDial: dial)
        let values = mode?.drawnValues
        let calibration = mode?.calibratingValue
        ZStack {
            ForEach(OrbitGaugeGeometry.Orbit.allCases, id: \.self) { orbit in
                if orbit == .strain, let calibration {
                    // Seven segments instead of the one ring.
                    ForEach(Array(OrbitGaugeGeometry.segments(required: calibration.required, dial: dial).enumerated()),
                            id: \.offset) { _, segment in
                        OrbitArc(radius: m.radius(of: orbit), start: segment.start, sweep: segment.sweep)
                            .stroke(palette.track, style: StrokeStyle(lineWidth: m.stroke(of: orbit), lineCap: .round))
                    }
                } else {
                    OrbitArc(radius: m.radius(of: orbit), start: orbit.startDegrees, sweep: orbit.trackSweep)
                        .stroke(palette.track, style: StrokeStyle(lineWidth: m.stroke(of: orbit), lineCap: .round))
                }
            }
            if mode != nil {
                ForEach(OrbitGaugeGeometry.Orbit.allCases, id: \.self) { orbit in
                    OrbitDot(radius: m.radius(of: orbit), start: orbit.startDegrees,
                             sweep: orbit.sweep(for: values.flatMap { orbit.fraction(of: $0) } ?? 0),
                             dotRadius: m.dotRadius + m.dotAir)
                        .fill(.black)
                        .blendMode(.destinationOut)
                }
            }
            // Under the readiness ring only while it is dimmed (pending), so the dimmed ring sits on its track.
            if values == nil || mode?.isPending == true {
                let d = m.centreRadius * 2 + m.centreStroke
                Circle()
                    .inset(by: m.centreStroke / 2)
                    .stroke(palette.track, lineWidth: m.centreStroke)
                    .frame(width: d, height: d)
            }
        }
        .compositingGroup()
    }
}

/// The marks of a mode: per orbit the arc and the filled dot of a present score, or the hollow dot of a missing
/// one; the centre ring in the readiness band's colour when scored. Calibrating adds the filled segments; pending
/// draws the previous day's marks at `pendingOpacity`. The other modes draw three hollow dots.
struct OrbitGaugeMarks: View {
    let mode: OrbitGaugeMode
    let dial: CGFloat
    let palette: OrbitGaugePalette

    /// How much of its colour a pending gauge keeps. Intentionally secondary (design.md, PR 2): the numbers say what
    /// it is, this says "not today's".
    static let pendingOpacity = 0.6

    var body: some View {
        let m = OrbitGaugeGeometry.metrics(forDial: dial)
        let values = mode.drawnValues
        ZStack {
            // The strain band's rail under the outer orbit's marks; nothing without a band, a dial with room, or values.
            if let values, OrbitGaugeGeometry.drawsBandRail(values.strainBand, dial: dial) {
                OrbitGaugeBandRail(band: values.strainBand, dial: dial, colour: palette.strain,
                                   cut: (start: 0, sweep: OrbitGaugeGeometry.Orbit.strain.sweep(for: values.strainFraction ?? 0),
                                         radius: m.outerRadius))
            }
            ForEach(OrbitGaugeGeometry.Orbit.allCases, id: \.self) { orbit in
                if orbit == .strain, let calibration = mode.calibratingValue {
                    segments(calibration, m)
                }
                marks(orbit, fraction: values.flatMap { orbit.fraction(of: $0) },
                      split: orbit == .strain ? values.flatMap { OrbitGaugeGeometry.strainSplitDegrees(band: $0.strainBand) } : nil,
                      m)
            }
            if let values {
                let d = m.centreRadius * 2 + m.centreStroke
                Circle()
                    .inset(by: m.centreStroke / 2)
                    .stroke(palette.band(forReadiness: values.readiness), lineWidth: m.centreStroke)
                    .frame(width: d, height: d)
            }
        }
        // One group, so a dot over its arc does not darken twice.
        .compositingGroup()
        .opacity(mode.isPending ? Self.pendingOpacity : 1)
    }

    /// The nights counted, clockwise from the seam, in the accent. An unfilled segment has no sweep, so a segment
    /// that fills grows from its start (the app steps `nights` one at a time).
    private func segments(_ calibration: OrbitGaugeCalibration, _ m: OrbitGaugeGeometry.Metrics) -> some View {
        let counted = calibration.counted
        return ForEach(Array(OrbitGaugeGeometry.segments(required: calibration.required, dial: dial).enumerated()),
                       id: \.offset) { i, segment in
            OrbitArc(radius: m.outerRadius, start: segment.start, sweep: i < counted ? segment.sweep : 0)
                .stroke(palette.calibration, style: StrokeStyle(lineWidth: m.outerStroke, lineCap: .round))
        }
    }

    @ViewBuilder
    private func marks(_ orbit: OrbitGaugeGeometry.Orbit, fraction: Double?, split: Double?,
                       _ m: OrbitGaugeGeometry.Metrics) -> some View {
        let colour = palette.colour(of: orbit)
        if let fraction {
            if let split {
                // A usable band: one structure whatever the strain is, so a change that crosses the band's end moves
                // the arc and the dot's colour with it (`OrbitStrainArc`, `OrbitStrainDot`).
                OrbitStrainArc(radius: m.radius(of: orbit), stroke: m.stroke(of: orbit),
                               sweep: orbit.sweep(for: fraction), split: split, plain: colour, past: palette.strainPastBand)
                OrbitStrainDot(radius: m.radius(of: orbit), sweep: orbit.sweep(for: fraction), dotRadius: m.dotRadius,
                               split: split, plain: colour, past: palette.strainPastBand)
            } else {
                OrbitArc(radius: m.radius(of: orbit), start: orbit.startDegrees, sweep: orbit.sweep(for: fraction))
                    .stroke(colour, style: StrokeStyle(lineWidth: m.stroke(of: orbit), lineCap: .round))
                OrbitDot(radius: m.radius(of: orbit), start: orbit.startDegrees, sweep: orbit.sweep(for: fraction),
                         dotRadius: m.dotRadius)
                    .fill(colour)
            }
        } else {
            OrbitDot(radius: m.radius(of: orbit), start: orbit.startDegrees, sweep: 0, dotRadius: m.dotRadius)
                .stroke(colour, lineWidth: m.hollowStroke)
        }
    }
}

extension OrbitGaugeMode {
    /// The count of a calibrating gauge, only for `.calibrating`. The app's `OrbitGaugeMode.calibration`
    /// (`OrbitGaugeMode+Today.swift`) also returns S2's `learning`, which is never drawn (plan.md decision 3).
    var calibratingValue: OrbitGaugeCalibration? {
        if case .calibrating(let calibration) = self { return calibration }
        return nil
    }
}

extension OrbitGaugeGeometry.Orbit {
    /// This orbit's fraction of `values`, nil when its score is missing.
    func fraction(of values: OrbitGaugeValues) -> Double? {
        switch self {
        case .recovery: return values.recoveryFraction
        case .sleep: return values.sleepFraction
        case .strain: return values.strainFraction
        }
    }
}

// MARK: strain band (PR 4)

/// The band's rail: a thin butt-capped arc inside the outer orbit, `metricStrain` at `bandRailOpacity`, with the air around
/// the strain dot cut out of it the way the tracks are (`cut`: the dot's start and sweep on its orbit, like the tracks').
/// Draws nothing for an empty band.
struct OrbitGaugeBandRail: View {
    let band: ClosedRange<Double>?
    let dial: CGFloat
    let colour: Color
    var opacity = OrbitGaugeGeometry.bandRailOpacity
    let cut: (start: Double, sweep: Double, radius: CGFloat)

    var body: some View {
        let m = OrbitGaugeGeometry.metrics(forDial: dial)
        ZStack {
            if let rail = OrbitGaugeGeometry.bandRail(for: band) {
                OrbitArc(radius: m.bandRadius, start: rail.start, sweep: rail.sweep)
                    .stroke(colour.opacity(opacity), style: StrokeStyle(lineWidth: m.bandStroke, lineCap: .butt))
                OrbitDot(radius: cut.radius, start: cut.start, sweep: cut.sweep, dotRadius: m.dotRadius + m.dotAir)
                    .fill(.black)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }
}

/// The strain arc with a band: one stroked arc drawn twice, `plain` up to `split` (the band's upper end, degrees from the
/// top) and `past` beyond it, each clipped to its side of a radial line, so the join is straight, the caps stay round at
/// both ends and there is no fringe of one colour under the edge of the other. Always this structure for a usable band,
/// whatever the strain: it is `Animatable` in the sweep, so the past layer grows and shrinks with the arc and nothing swaps
/// when a change crosses the band's end. Below the split the past layer is empty.
struct OrbitStrainArc: View, Animatable {
    var radius: CGFloat
    var stroke: CGFloat
    var sweep: Double
    var split: Double
    var plain: Color
    var past: Color

    var animatableData: Double {
        get { sweep }
        set { sweep = newValue }
    }

    var body: some View {
        let arc = OrbitArc(radius: radius, start: 0, sweep: sweep)
            .stroke(style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        ZStack {
            // The start cap reaches a few degrees before the top (it stays `plain`); the far end is under the dot.
            arc.foregroundStyle(plain).clipShape(OrbitWedge(from: -8, to: split))
            if sweep > split {
                arc.foregroundStyle(past).clipShape(OrbitWedge(from: split, to: min(sweep + 4, 357)))
            }
        }
    }
}

/// The strain dot with a band: `past` once its head is beyond `split`, `plain` before, decided from the animated sweep
/// (it switches at the moment the head crosses the line, not at the end of the animation).
struct OrbitStrainDot: View, Animatable {
    var radius: CGFloat
    var sweep: Double
    var dotRadius: CGFloat
    var split: Double
    var plain: Color
    var past: Color

    var animatableData: Double {
        get { sweep }
        set { sweep = newValue }
    }

    var body: some View {
        OrbitDot(radius: radius, start: 0, sweep: sweep, dotRadius: dotRadius)
            .fill(sweep > split ? past : plain)
    }
}

/// A pie slice from the centre, `from` to `to` degrees clockwise from the top, larger than the rect. Empty when `to` does
/// not pass `from` (it would otherwise wrap the long way round).
struct OrbitWedge: Shape {
    var from: Double
    var to: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard to > from else { return p }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: centre)
        p.addArc(center: centre, radius: hypot(rect.width, rect.height),
                 startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
        p.closeSubpath()
        return p
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
