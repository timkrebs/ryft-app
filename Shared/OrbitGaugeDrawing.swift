// The orbit gauge's drawing, shared by the app and the widget (ADR 0010): tracks, ticks, arcs, dots, halos and the
// readiness marker, deterministic, from a mode, a size and a palette. No strings, no fonts, no accessibility, no timers:
// the wrappers add those (`Ryft/Design/OrbitGauge.swift` in the app, `RyftWidgets/WidgetOrbitGauge.swift` in the widget).
//
// Gauge v3 (Nocturne PR 3): docs/work/2026-11-16-nocturne/design.md §P3-1 and §P3-2; geometry and mapping in
// `OrbitGaugeGeometry`. `.calibrating` draws the outer orbit as segments, `.pending` the previous day's marks dimmed.
// One drawing serves every moment: `OrbitGaugeScene` says where everything is and how much of it is drawn. The static
// gauge is the scene of a mode; the app's launch entrance (`Ryft/Design/OrbitGaugeEntrance.swift`) is the same drawing
// at the entrance's values, so its last frame is the static gauge by construction.
//
// LAYERS, back to front. Tracks (one group): the outer solid ring or the calibrating segments, the middle ring, the inner
// solid ring, each cut around the dots of its own ring; then the tick rings, which are never cut (a tick is whole or
// absent: `OrbitGaugeGeometry.drawnTicks` leaves out the ones too close to a dot). Marks (one group, dimmed while
// pending): the band rail, the arcs, the solid tier's lit readiness arc, the halos, the cuts (each dot clears its ring
// through everything under it, so the gauge reads the same on any ground and in the widget's tinted modes), the lit
// readiness ticks, the dots, the Volt dot last. Dots come after every cut, so two close dots never cut each other.
import SwiftUI

/// The gauge's sizes: `MetricGauge`'s dials, so nothing around the gauge moves.
enum OrbitGaugeSize: Hashable, Sendable {
    case small, medium, large
    /// An exact dial, for the widget's other families, the Today board's 260 (`.custom(dial: 248)`) and checks.
    /// Screens use the three above.
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

    /// The frame, S in the geometry: the dial plus the 6 pt `MetricGauge` keeps free on every side for its ticks. The
    /// outer ticks and the strain dot's ring stay inside it; only a halo can reach 3 pt past it (at 260), so nothing
    /// around the gauge may clip it.
    var frame: CGFloat { dial + 12 }
}

/// The whole drawing: tracks, then the marks, then the caller's centre content framed inside the readiness ring.
/// `mode == nil` is "unknown" (a widget snapshot written before the orbit): tracks only, never hollow dots that would
/// say "missing".
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
        let scene = OrbitGaugeScene(mode: mode, size: size)
        ZStack {
            OrbitGaugeTracks(scene: scene, palette: palette)
            if mode != nil {
                styleMarks(OrbitGaugeMarks(scene: scene, palette: palette))
            }
            centre
                .frame(width: max(scene.metrics.centreSlotWidth, 0))
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

// MARK: the scene

/// One moment of the drawing, as numbers: where each dot is, how much of each track is drawn, how far the values have
/// come. `init(mode:size:)` is the static gauge; the app's entrance changes the rest.
struct OrbitGaugeScene {
    /// A dot at `start + sweep` degrees (clockwise from the top) at `radius`. The static gauge keeps `start` at the
    /// orbit's start and `sweep` at the arc's, so the dot rides the arc's animation; the entrance flies it in.
    struct Dot: Equatable {
        var radius: CGFloat
        var start: Double
        var sweep: Double
        /// The dot's own opacity (the entrance fades it in as it flies).
        var opacity = 1.0
        /// The share of the halo's 16 % shown (the entrance grows it with the flight).
        var halo = 1.0

        var degrees: Double { start + sweep }
    }

    let mode: OrbitGaugeMode?
    let dial: CGFloat
    let metrics: OrbitGaugeGeometry.Metrics
    /// How much of each track is drawn, 0...1: the outer ring (ticks, solid ring or segments) and the inner ring
    /// clockwise from the top, the middle ring both ways from the top.
    var outerTrack = 1.0
    var middleTrack = 1.0
    var innerTrack = 1.0
    /// How much of its value the arcs, the counted segments, the lit ticks and the Volt dot show (0...1).
    var progress = 1.0
    var strainDot: Dot
    var recoveryDot: Dot
    var sleepDot: Dot
    var voltOpacity = 1.0
    var railOpacity = 1.0

    init(mode: OrbitGaugeMode?, size: OrbitGaugeSize) {
        self.mode = mode
        dial = size.dial
        let m = OrbitGaugeGeometry.metrics(forSide: size.frame)
        metrics = m
        let values = mode?.drawnValues
        func settled(_ orbit: OrbitGaugeGeometry.Orbit) -> Dot {
            Dot(radius: m.radius(of: orbit), start: orbit.startDegrees,
                sweep: orbit.sweep(for: values.flatMap { orbit.fraction(of: $0) } ?? 0))
        }
        strainDot = settled(.strain)
        recoveryDot = settled(.recovery)
        sleepDot = settled(.sleep)
    }

    func dot(_ orbit: OrbitGaugeGeometry.Orbit) -> Dot {
        switch orbit {
        case .strain: return strainDot
        case .recovery: return recoveryDot
        case .sleep: return sleepDot
        }
    }

    mutating func setDot(_ orbit: OrbitGaugeGeometry.Orbit, _ dot: Dot) {
        switch orbit {
        case .strain: strainDot = dot
        case .recovery: recoveryDot = dot
        case .sleep: sleepDot = dot
        }
    }

    var values: OrbitGaugeValues? { mode?.drawnValues }
    var calibration: OrbitGaugeCalibration? { mode?.calibratingValue }
    /// Any mode draws three dots (filled or hollow); unknown draws none.
    var drawsDots: Bool { mode != nil }

    /// The outer tick ring: not while calibrating (the segments take the orbit) and not in the solid tier (a ring).
    var drawsOuterTicks: Bool { calibration == nil && metrics.tier != .solid }

    /// An orbit's fraction, nil when its score is missing (a hollow dot).
    func fraction(_ orbit: OrbitGaugeGeometry.Orbit) -> Double? {
        values.flatMap { orbit.fraction(of: $0) }
    }

    /// The radial line where the strain arc may turn toward alert, for a usable band.
    var strainSplit: Double? {
        values.flatMap { OrbitGaugeGeometry.strainSplitDegrees(band: $0.strainBand) }
    }

    /// The readiness as drawn, 0...1 of the inner ring; nil without one (no lit tick, no Volt dot).
    var readiness: Double? {
        guard drawsDots else { return nil }
        return OrbitGaugeGeometry.readinessFraction(values?.readiness).map { $0 * progress }
    }

    /// The Volt dot is on the gauge (it marks a value) and visible.
    var showsVolt: Bool { readiness != nil && voltOpacity > 0 }

    /// Volt on the inner ring at the drawn readiness: at the value, not at a tick.
    var voltDot: Dot { Dot(radius: metrics.centreRadius, start: 0, sweep: (readiness ?? 0) * 360) }
}

// MARK: tracks

/// The tracks: `ink` at 16 % (the outer ticks, ring or segments), 7 % (the middle ring) and 13 % (the inner ticks or
/// ring). Each ring is cut around the dots of its own ring only, so a dot on its way in leaves no gap in the rings it
/// crosses; the tick rings leave out their ticks instead.
struct OrbitGaugeTracks: View {
    let scene: OrbitGaugeScene
    let palette: OrbitGaugePalette

    init(scene: OrbitGaugeScene, palette: OrbitGaugePalette) {
        self.scene = scene
        self.palette = palette
    }

    init(mode: OrbitGaugeMode?, size: OrbitGaugeSize, palette: OrbitGaugePalette) {
        self.init(scene: OrbitGaugeScene(mode: mode, size: size), palette: palette)
    }

    var body: some View {
        let m = scene.metrics
        ZStack {
            outerRing(m)
            ZStack {
                OrbitRing(radius: m.innerRadius, fraction: scene.middleTrack)
                    .stroke(palette.middleTrack, style: StrokeStyle(lineWidth: m.innerStroke, lineCap: .round))
                cut(scene.recoveryDot, m.dotCut)
                cut(scene.sleepDot, m.dotCut)
            }
            .compositingGroup()
            if m.tier == .solid {
                ZStack {
                    OrbitArc(radius: m.centreRadius, start: 0, sweep: OrbitGaugeGeometry.strainTrackSweep * scene.innerTrack)
                        .stroke(palette.innerTrack, style: StrokeStyle(lineWidth: m.centreStroke, lineCap: .round))
                    if scene.showsVolt { cutting(scene.voltDot, m.voltCut) }
                }
                .compositingGroup()
            } else {
                if scene.drawsOuterTicks {
                    OrbitTicks(count: m.outerTickCount, radius: m.outerRadius, tick: m.outerTick, fraction: scene.outerTrack,
                               lit: false, dot: scene.drawsDots ? scene.strainDot : nil, cut: m.dotCut)
                        .fill(palette.outerTrack)
                }
                OrbitTicks(count: m.innerTickCount, radius: m.centreRadius, tick: m.innerTick, fraction: scene.innerTrack,
                           lit: false, dot: scene.showsVolt ? scene.voltDot : nil, cut: m.voltCut)
                    .fill(palette.innerTrack)
            }
        }
        .compositingGroup()
    }

    /// Calibrating: the segments (no tick ring); the solid tier: one ring; else nothing (the ticks are drawn above).
    @ViewBuilder
    private func outerRing(_ m: OrbitGaugeGeometry.Metrics) -> some View {
        if let calibration = scene.calibration {
            ZStack {
                ForEach(Array(OrbitGaugeGeometry.segments(required: calibration.required, dial: scene.dial).enumerated()),
                        id: \.offset) { _, segment in
                    OrbitArc(radius: m.outerRadius, start: segment.start, sweep: segment.sweep * scene.outerTrack)
                        .stroke(palette.outerTrack, style: StrokeStyle(lineWidth: m.outerStroke, lineCap: .round))
                }
                cut(scene.strainDot, m.dotCut)
            }
            .compositingGroup()
        } else if m.tier == .solid {
            ZStack {
                OrbitArc(radius: m.outerRadius, start: 0, sweep: OrbitGaugeGeometry.strainTrackSweep * scene.outerTrack)
                    .stroke(palette.outerTrack, style: StrokeStyle(lineWidth: m.outerStroke, lineCap: .round))
                cut(scene.strainDot, m.dotCut)
            }
            .compositingGroup()
        }
    }

    @ViewBuilder
    private func cut(_ dot: OrbitGaugeScene.Dot, _ radius: CGFloat) -> some View {
        if scene.drawsDots { cutting(dot, radius) }
    }

    private func cutting(_ dot: OrbitGaugeScene.Dot, _ radius: CGFloat) -> some View {
        OrbitDot(radius: dot.radius, start: dot.start, sweep: dot.sweep, dotRadius: radius)
            .fill(.black)
            .blendMode(.destinationOut)
    }
}

// MARK: marks

/// The marks of a mode: per orbit the arc, halo and filled dot of a present score or the hollow dot of a missing one;
/// the lit readiness ticks (a solid arc below S 100) and the Volt dot at the value; the strain band's rail. Calibrating
/// adds the counted segments; pending draws the previous day's marks at `pendingOpacity`, lit ticks and Volt included.
struct OrbitGaugeMarks: View {
    let scene: OrbitGaugeScene
    let palette: OrbitGaugePalette

    /// How much of its colour a pending gauge keeps. Intentionally secondary (design.md, PR 2 of the orbit gauge): the
    /// numbers say what it is, this says "not today's".
    static let pendingOpacity = 0.6

    init(scene: OrbitGaugeScene, palette: OrbitGaugePalette) {
        self.scene = scene
        self.palette = palette
    }

    init(mode: OrbitGaugeMode, size: OrbitGaugeSize, palette: OrbitGaugePalette) {
        self.init(scene: OrbitGaugeScene(mode: mode, size: size), palette: palette)
    }

    var body: some View {
        let m = scene.metrics
        let split = scene.strainSplit
        ZStack {
            rail(m)
            if let calibration = scene.calibration { segments(calibration, m) }
            ForEach(OrbitGaugeGeometry.Orbit.allCases, id: \.self) { orbit in
                if let fraction = scene.fraction(orbit) { arc(orbit, fraction: fraction, split: split, m) }
            }
            if m.tier == .solid, let readiness = scene.readiness {
                OrbitArc(radius: m.centreRadius, start: 0, sweep: min(readiness * 360, OrbitGaugeGeometry.strainTrackSweep))
                    .stroke(palette.ink, style: StrokeStyle(lineWidth: m.centreStroke, lineCap: .round))
            }
            if m.showsHalo {
                ForEach(OrbitGaugeGeometry.Orbit.allCases, id: \.self) { orbit in
                    if scene.fraction(orbit) != nil { halo(orbit, split: split, m) }
                }
            }
            if scene.drawsDots {
                ForEach(OrbitGaugeGeometry.Orbit.allCases, id: \.self) { orbit in cutting(scene.dot(orbit), m.dotCut) }
            }
            if scene.showsVolt { cutting(scene.voltDot, m.voltCut) }
            if m.tier != .solid, let readiness = scene.readiness {
                OrbitTicks(count: m.innerTickCount, radius: m.centreRadius, tick: m.innerTick, fraction: readiness, lit: true,
                           dot: scene.showsVolt ? scene.voltDot : nil, cut: m.voltCut)
                    .fill(palette.ink)
            }
            if scene.drawsDots {
                ForEach(OrbitGaugeGeometry.Orbit.allCases, id: \.self) { orbit in dot(orbit, split: split, m) }
            }
            if scene.showsVolt {
                let volt = scene.voltDot
                OrbitDot(radius: volt.radius, start: volt.start, sweep: volt.sweep, dotRadius: m.voltRadius)
                    .fill(palette.signal)
                    .opacity(scene.voltOpacity)
            }
        }
        // One group, so a dot over its arc does not darken twice and the cuts reach only the marks.
        .compositingGroup()
        .opacity(scene.mode?.isPending == true ? Self.pendingOpacity : 1)
    }

    /// The band's rail: a thin butt-capped arc inside the outer ticks, `metricStrain` at `bandRailOpacity`; the strain
    /// dot's cut clears it around the dot. Nothing without a usable band, a dial with room, or values.
    @ViewBuilder
    private func rail(_ m: OrbitGaugeGeometry.Metrics) -> some View {
        if let band = scene.values?.strainBand, OrbitGaugeGeometry.drawsBandRail(band, dial: scene.dial),
           let rail = OrbitGaugeGeometry.bandRail(for: band) {
            OrbitArc(radius: m.bandRadius, start: rail.start, sweep: rail.sweep)
                .stroke(palette.strain.opacity(OrbitGaugeGeometry.bandRailOpacity),
                        style: StrokeStyle(lineWidth: m.bandStroke, lineCap: .butt))
                .opacity(scene.railOpacity)
        }
    }

    /// The nights counted, clockwise from the seam, in the calibration teal. An unfilled segment has no sweep, so a
    /// segment that fills grows from its start (the app steps `nights` one at a time).
    private func segments(_ calibration: OrbitGaugeCalibration, _ m: OrbitGaugeGeometry.Metrics) -> some View {
        let counted = calibration.counted
        return ForEach(Array(OrbitGaugeGeometry.segments(required: calibration.required, dial: scene.dial).enumerated()),
                       id: \.offset) { i, segment in
            OrbitArc(radius: m.outerRadius, start: segment.start, sweep: i < counted ? segment.sweep * scene.progress : 0)
                .stroke(palette.calibration, style: StrokeStyle(lineWidth: m.outerStroke, lineCap: .round))
        }
    }

    @ViewBuilder
    private func arc(_ orbit: OrbitGaugeGeometry.Orbit, fraction: Double, split: Double?,
                     _ m: OrbitGaugeGeometry.Metrics) -> some View {
        let sweep = orbit.sweep(for: fraction) * scene.progress
        if orbit == .strain, let split {
            // A usable band: one structure whatever the strain is, so a change that crosses the band's end moves the
            // arc's colour with it (`OrbitStrainArc`).
            OrbitStrainArc(radius: m.outerRadius, stroke: m.outerStroke, sweep: sweep, split: split,
                           plain: palette.strain, past: palette.strainPastBand)
        } else {
            OrbitArc(radius: m.radius(of: orbit), start: orbit.startDegrees, sweep: sweep)
                .stroke(palette.colour(of: orbit), style: StrokeStyle(lineWidth: m.stroke(of: orbit), lineCap: .round))
        }
    }

    /// The halo of a present score: its colour at 16 %, behind the ring (the cut leaves r 10...15 of it at 260).
    @ViewBuilder
    private func halo(_ orbit: OrbitGaugeGeometry.Orbit, split: Double?, _ m: OrbitGaugeGeometry.Metrics) -> some View {
        let d = scene.dot(orbit)
        let alpha = OrbitGaugePalette.haloOpacity * d.halo
        if orbit == .strain, let split {
            OrbitStrainDot(radius: d.radius, start: d.start, sweep: d.sweep, dotRadius: m.haloRadius, split: split,
                           plain: palette.strain.opacity(alpha), past: palette.strainPastBand.opacity(alpha))
        } else {
            OrbitDot(radius: d.radius, start: d.start, sweep: d.sweep, dotRadius: m.haloRadius)
                .fill(palette.colour(of: orbit).opacity(alpha))
        }
    }

    /// Filled for a score (a zero is a filled dot at the start), hollow for a missing one: an outline with its inside
    /// cleared, no halo.
    @ViewBuilder
    private func dot(_ orbit: OrbitGaugeGeometry.Orbit, split: Double?, _ m: OrbitGaugeGeometry.Metrics) -> some View {
        let d = scene.dot(orbit)
        let colour = palette.colour(of: orbit)
        if scene.fraction(orbit) != nil {
            if orbit == .strain, let split {
                OrbitStrainDot(radius: d.radius, start: d.start, sweep: d.sweep, dotRadius: m.dotRadius, split: split,
                               plain: colour, past: palette.strainPastBand)
                    .opacity(d.opacity)
            } else {
                OrbitDot(radius: d.radius, start: d.start, sweep: d.sweep, dotRadius: m.dotRadius)
                    .fill(colour)
                    .opacity(d.opacity)
            }
        } else {
            OrbitDot(radius: d.radius, start: d.start, sweep: d.sweep, dotRadius: m.dotRadius)
                .stroke(colour, lineWidth: m.hollowStroke)
                .opacity(d.opacity)
        }
    }

    private func cutting(_ dot: OrbitGaugeScene.Dot, _ radius: CGFloat) -> some View {
        OrbitDot(radius: dot.radius, start: dot.start, sweep: dot.sweep, dotRadius: radius)
            .fill(.black)
            .blendMode(.destinationOut)
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

/// The strain dot (or its halo) with a band: `past` once the arc's head is beyond `split`, `plain` before, decided from
/// the animated sweep (it switches at the moment the head crosses the line, not at the end of the animation). It sits at
/// `start + sweep`: the static gauge passes the arc's sweep from the top; the entrance passes the arc's sweep so far and
/// a `start` that puts the flying dot where it is.
struct OrbitStrainDot: View, Animatable {
    var radius: CGFloat
    var start: Double = 0
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
        OrbitDot(radius: radius, start: start, sweep: sweep, dotRadius: dotRadius)
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

/// The middle orbit's track: the whole ring, or (the entrance) the part of it within `fraction` x 180 deg of the top on
/// either side, one path so its round ends never overlap themselves.
struct OrbitRing: Shape {
    var radius: CGFloat
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        if fraction >= 1 {
            p.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))
            return p
        }
        let half = 180 * fraction
        guard half > 0.025 else { return p }
        p.addArc(center: c, radius: radius, startAngle: .degrees(-half - 90), endAngle: .degrees(half - 90),
                 clockwise: false)
        return p
    }
}

/// A tick ring: rectangles `tick.width` across and `tick.height` along the radius, centred on the ring, tick 0 at the
/// top. Which are drawn is `OrbitGaugeGeometry.drawnTicks`: the lit ones or the ones drawn in so far, less those too
/// close to the ring's dot. Animatable in the fraction and the dot, so the lit count follows an animated readiness by
/// threshold and the gap travels with the dot; a tick itself never moves or shrinks.
struct OrbitTicks: Shape {
    var count: Int
    var radius: CGFloat
    var tick: CGSize
    var fraction: Double
    var lit: Bool
    var dotStart: Double
    var dotSweep: Double
    var dotRadius: CGFloat
    /// 0: no dot.
    var cut: CGFloat

    init(count: Int, radius: CGFloat, tick: CGSize, fraction: Double, lit: Bool, dot: OrbitGaugeScene.Dot?, cut: CGFloat) {
        self.count = count
        self.radius = radius
        self.tick = tick
        self.fraction = fraction
        self.lit = lit
        dotStart = dot?.start ?? 0
        dotSweep = dot?.sweep ?? 0
        dotRadius = dot?.radius ?? 0
        self.cut = dot == nil ? 0 : cut
    }

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, CGFloat>> {
        get { AnimatablePair(fraction, AnimatablePair(dotSweep, dotRadius)) }
        set {
            fraction = newValue.first
            dotSweep = newValue.second.first
            dotRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let dot = cut > 0 ? (degrees: dotStart + dotSweep, radius: dotRadius, cut: cut) : nil
        let box = CGRect(x: -tick.width / 2, y: -radius - tick.height / 2, width: tick.width, height: tick.height)
        for i in OrbitGaugeGeometry.drawnTicks(count: count, ringRadius: radius, tick: tick, fraction: fraction, lit: lit,
                                               dot: dot) {
            // Rotating the top tick clockwise in y-down space: positive radians.
            let angle = OrbitGaugeGeometry.tickDegrees(i, count: count) * .pi / 180
            p.addRect(box, transform: CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(angle)))
        }
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
