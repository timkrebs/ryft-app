import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Gauge v3 rendered (docs/work/2026-11-16-nocturne/design.md §P3-8, cases 13, 14, 16 and 17; 15 is
/// `OrbitGaugeContrastTests`). `ImageRenderer` at 3x, dark, static (`animatesFill: false`, `breathes: false`), the
/// pixels read where the geometry says things are. The board's values at S = 260 unless a case says otherwise.
@MainActor
@Suite("OrbitGauge v3: rendered")
struct OrbitGaugeV3RenderTests {
    typealias G = OrbitGaugeGeometry

    /// 0...255 per channel, premultiplied (only opaque pixels are compared by colour).
    private struct RGBA: Equatable { var r, g, b, a: Int }

    /// Room around the gauge for what reaches past its frame (the strain halo, 3 pt at 260).
    private static let pad: CGFloat = 8
    nonisolated private static let scale: CGFloat = 3

    private struct Shot {
        let width: Int, height: Int, bytes: [UInt8]
        /// The gauge's centre in points of the image.
        let centre: CGPoint

        /// The pixel that contains a point (points of the image).
        func pixel(_ p: CGPoint) -> RGBA {
            let x = min(max(Int((p.x * OrbitGaugeV3RenderTests.scale).rounded(.down)), 0), width - 1)
            let y = min(max(Int((p.y * OrbitGaugeV3RenderTests.scale).rounded(.down)), 0), height - 1)
            let i = (y * width + x) * 4
            return RGBA(r: Int(bytes[i]), g: Int(bytes[i + 1]), b: Int(bytes[i + 2]), a: Int(bytes[i + 3]))
        }

        /// A point on a ring of the gauge.
        func at(radius: CGFloat, degrees: Double) -> CGPoint { G.point(centre: centre, radius: radius, degrees: degrees) }

        /// Every pixel with its centre in points of the image.
        func forEachPixel(_ body: (CGPoint, RGBA) -> Void) {
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    body(CGPoint(x: (CGFloat(x) + 0.5) / OrbitGaugeV3RenderTests.scale,
                                 y: (CGFloat(y) + 0.5) / OrbitGaugeV3RenderTests.scale),
                         RGBA(r: Int(bytes[i]), g: Int(bytes[i + 1]), b: Int(bytes[i + 2]), a: Int(bytes[i + 3])))
                }
            }
        }
    }

    /// A view of side `frame`, padded, over the background (or transparent), as RGBA bytes.
    private func shot<V: View>(_ content: V, frame: CGFloat, opaque: Bool = true) -> Shot? {
        let view = content
            .padding(Self.pad)
            .background(opaque ? Theme.background : Color.clear)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        guard let cg = renderer.cgImage else { return nil }
        let (w, h) = (cg.width, cg.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let c = Self.pad + frame / 2
        return Shot(width: w, height: h, bytes: bytes, centre: CGPoint(x: c, y: c))
    }

    private func render(_ mode: OrbitGaugeMode, _ size: OrbitGaugeSize = .previewBoard, opaque: Bool = true) -> Shot? {
        shot(OrbitGauge(mode: mode, size: size, animatesFill: false, breathes: false), frame: size.frame, opaque: opaque)
    }

    private func rgba(_ colour: Color) -> RGBA {
        let ui = UIColor(colour).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: Int((r * 255).rounded()), g: Int((g * 255).rounded()), b: Int((b * 255).rounded()),
                    a: Int((a * 255).rounded()))
    }

    /// `top` at `alpha` over an opaque `bottom`.
    private func over(_ top: RGBA, _ alpha: Double, _ bottom: RGBA) -> RGBA {
        func mix(_ t: Int, _ b: Int) -> Int { Int((Double(t) * alpha + Double(b) * (1 - alpha)).rounded()) }
        return RGBA(r: mix(top.r, bottom.r), g: mix(top.g, bottom.g), b: mix(top.b, bottom.b), a: 255)
    }

    private func close(_ a: RGBA, _ b: RGBA, _ tolerance: Int) -> Bool {
        max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b)) <= tolerance
    }

    private var background: RGBA { rgba(Theme.background) }

    /// The board's three dots: orbit, its colour, centre radius and angle (code) at S = 260.
    private var boardDots: [(G.Orbit, Color, CGFloat, Double)] {
        let v = OrbitGaugeValues.previewBoard
        return [(.strain, Theme.metricStrain, 118, G.Orbit.strain.headDegrees(for: v.strainFraction ?? 0)),
                (.recovery, Theme.recovery, 88, G.Orbit.recovery.headDegrees(for: v.recoveryFraction ?? 0)),
                (.sleep, Theme.metricSleep, 88, G.Orbit.sleep.headDegrees(for: v.sleepFraction ?? 0))]
    }

    // MARK: 13. colours in pixels

    @Test func arcsDotsAndLitTicksAreTheirColours() throws {
        let shot = try #require(render(.scored(.previewBoard)))
        for (orbit, colour, radius, degrees) in boardDots {
            let c = rgba(colour)
            #expect(close(shot.pixel(shot.at(radius: radius, degrees: degrees)), c, 2), "\(orbit) dot")
            // The arc behind the head, past the halo: 12 deg back along the orbit.
            let behind = orbit == .recovery ? degrees + 12 : degrees - 12
            #expect(close(shot.pixel(shot.at(radius: radius, degrees: behind)), c, 2), "\(orbit) arc")
        }
        // Lit readiness ticks are the ink: tick 15 (3 o'clock) and tick 0 (the top) of 50.
        let ink = rgba(Theme.textPrimary)
        #expect(close(shot.pixel(shot.at(radius: 58, degrees: 90)), ink, 2), "lit tick 15")
        #expect(close(shot.pixel(shot.at(radius: 58, degrees: 0)), ink, 2), "lit tick 0")
        // An unlit one (tick 55, 330 deg) is the ink at 13 %.
        let unlit = over(ink, OrbitGaugePalette.innerTrackOpacity, background)
        #expect(close(shot.pixel(shot.at(radius: 58, degrees: 330)), unlit, 2), "unlit tick 55")
    }

    /// Volt appears only at the Volt dot: its centre is `signal`, and no pixel outside r 7.5 around it is within 4/255 of
    /// it; without a readiness there is none at all.
    @Test func voltIsOnlyTheReadinessDot() throws {
        let signal = rgba(Theme.signal)
        let shot = try #require(render(.scored(.previewBoard)))
        let volt = shot.at(radius: 58, degrees: try #require(G.voltDegrees(readiness: 84)))
        #expect(close(shot.pixel(volt), signal, 2), "the Volt dot's centre")
        var stray = 0, found = 0
        shot.forEachPixel { p, c in
            guard c.a == 255, close(c, signal, 4) else { return }
            found += 1
            if hypot(p.x - volt.x, p.y - volt.y) > 7.5 { stray += 1 }
        }
        #expect(found > 0 && stray == 0, "\(stray) Volt pixels away from the dot")
        let none = try #require(render(.scored(OrbitGaugeValues(recovery: 0.82, sleep: 0.94, strain: 12.4))))
        var any = 0
        none.forEachPixel { _, c in if c.a == 255, close(c, signal, 4) { any += 1 } }
        #expect(any == 0, "no Volt without a readiness")
    }

    // MARK: 14. the cleared ring and the halo

    @Test func eachDotHasAClearedRingAndAHalo() throws {
        let opaque = try #require(render(.scored(.previewBoard)))
        let clear = try #require(render(.scored(.previewBoard), opaque: false))
        for (orbit, colour, radius, degrees) in boardDots {
            let dot = opaque.at(radius: radius, degrees: degrees)
            // r 7...10: the background, all the way round; nothing at all in a transparent render.
            for direction in stride(from: 0.0, to: 360, by: 22.5) {
                let p = G.point(centre: dot, radius: 8.5, degrees: direction)
                #expect(close(opaque.pixel(p), background, 2), "\(orbit) ring at \(direction) deg")
                #expect(clear.pixel(p).a <= 2, "\(orbit) ring at \(direction) deg is transparent")
            }
            // r 10...15, across the orbit (in and out): the colour at 16 % over the background.
            let halo = over(rgba(colour), OrbitGaugePalette.haloOpacity, background)
            for direction in [degrees, degrees + 180] {
                let p = G.point(centre: dot, radius: 12.5, degrees: direction)
                #expect(close(opaque.pixel(p), halo, 3), "\(orbit) halo at \(direction) deg")
            }
        }
        // The Volt dot's ring, r 5...7.5.
        let volt = opaque.at(radius: 58, degrees: try #require(G.voltDegrees(readiness: 84)))
        for direction in stride(from: 0.0, to: 360, by: 22.5) {
            let p = G.point(centre: volt, radius: 6.25, degrees: direction)
            #expect(close(opaque.pixel(p), background, 2), "Volt ring at \(direction) deg")
            #expect(clear.pixel(p).a <= 2, "Volt ring at \(direction) deg is transparent")
        }
    }

    /// The strain halo reaches 3 pt past the 260 frame (r 15 around a dot on the r 118 ring: 133 against 130), and the gauge
    /// does not clip it. The head sits on an axis, so the halo's outermost point is straight out of the frame's edge: 10.5 of
    /// 21 is the bottom (180 deg), 21 the top (the arc stops a hundredth of a degree short of the whole turn). The sample is
    /// 2 pt outside the frame's square on that axis, between the dot's cut (r 10) and the halo's edge (r 15) at 14 pt from
    /// the dot's centre, and must be the 16 % halo. A sample inside the square, as 212.6 deg was, would pass a `.clipped()`.
    @Test("The halo is not clipped to the frame", arguments: [(10.5, 180.0, "bottom"), (21.0, 360.0, "top")])
    func theHaloIsNotClippedToTheFrame(_ strain: Double, _ head: Double, _ edge: String) throws {
        let shot = try #require(render(.scored(OrbitGaugeValues(readiness: 84, recovery: 0.82, sleep: 0.94, strain: strain))))
        let (_, colour, radius, _) = boardDots[0]
        let degrees = G.Orbit.strain.headDegrees(for: strain / 21)
        // On the axis: the head is at the bottom (180) or, a hundredth short of a turn, at the top.
        #expect(abs(degrees - head) < 0.02 || abs(degrees - head + 360) < 0.02, "the head is on the \(edge) axis: \(degrees)")
        let frame = CGRect(x: shot.centre.x - 130, y: shot.centre.y - 130, width: 260, height: 260)
        let sample = shot.at(radius: radius + 14, degrees: degrees)
        #expect(!frame.contains(sample), "the sample \(sample) is outside the frame \(frame)")
        let outside = edge == "bottom" ? sample.y - frame.maxY : frame.minY - sample.y
        #expect(abs(outside - 2) < 0.05, "2 pt outside the \(edge) edge: \(outside)")
        #expect(abs(sample.x - frame.midX) < 0.05, "on the vertical axis")
        let halo = over(rgba(colour), OrbitGaugePalette.haloOpacity, background)
        #expect(close(shot.pixel(sample), halo, 3), "the halo at \(edge): \(shot.pixel(sample)) against \(halo)")
        // And a point beyond its reach is the background again: the halo ends at 133 (3 pt out), not at the edge of the image.
        let beyond = shot.at(radius: radius + 16, degrees: degrees)
        #expect(close(shot.pixel(beyond), background, 2), "past the halo")
    }

    @Test func noHaloBelowS110() throws {
        #expect(!G.metrics(forSide: 109.9).showsHalo && G.metrics(forSide: 110).showsHalo)
        func haloSample(_ size: OrbitGaugeSize) throws -> RGBA {
            let shot = try #require(render(.scored(.previewBoard), size))
            let m = G.metrics(forSide: size.frame)
            let degrees = G.Orbit.strain.headDegrees(for: 12.4 / 21)
            // Inward, between the cut and the halo's edge.
            let dot = shot.at(radius: m.outerRadius, degrees: degrees)
            return shot.pixel(G.point(centre: dot, radius: (m.dotCut + m.haloRadius) / 2, degrees: degrees + 180))
        }
        #expect(close(try haloSample(.custom(dial: 96)), background, 2), "S 108: no halo")
        #expect(!close(try haloSample(.custom(dial: 100)), background, 2), "S 112: a halo")
    }

    // MARK: 16. every state renders

    private static let states: [(String, OrbitGaugeMode)] = [
        ("scored", .scored(.previewBoard)),
        ("sleep missing", .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, strain: 6.2))),
        ("no readiness", .scored(OrbitGaugeValues(recovery: 0.82, sleep: 0.94, strain: 12.4))),
        ("zeros", .scored(OrbitGaugeValues(readiness: 0, recovery: 0, sleep: 0, strain: 0))),
        ("out of range", .scored(OrbitGaugeValues(readiness: 120, recovery: 1.4, sleep: -0.2, strain: 25))),
        ("band", .scored(.previewBanded(strain: 16.5))),
        ("no data", .scored(.empty)),
        ("calibrating", .calibrating(OrbitGaugeCalibration(nights: 3))),
        ("pending", .pending(previous: .previewBoard)),
        ("pending, none", .pending(previous: nil)),
    ]

    @Test(arguments: [248, 160, 112, 72, 44] as [CGFloat])
    func everyStateDrawsAtEverySize(_ dial: CGFloat) throws {
        let size = OrbitGaugeSize.custom(dial: dial)
        let bg = background
        for (name, mode) in Self.states {
            let s = try #require(render(mode, size), "\(name) at \(dial)")
            var ink = 0
            s.forEachPixel { _, c in if !close(c, bg, 1) { ink += 1 } }
            #expect(ink > 0, "\(name) at dial \(dial) draws something")
        }
        // The widget's unknown mode: the tracks only.
        let unknown = try #require(shot(OrbitGaugeDrawing(mode: nil, size: size), frame: size.frame))
        var ink = 0
        unknown.forEachPixel { _, c in if !close(c, bg, 1) { ink += 1 } }
        #expect(ink > 0, "unknown at dial \(dial)")
    }

    @Test func pendingDimsTheMarksAndNotTheTracks() throws {
        let scored = try #require(render(.scored(.previewBoard)))
        let pending = try #require(render(.pending(previous: .previewBoard)))
        // The sleep arc at 3 o'clock (94 % ends at 156.4) over the 7 % ring.
        let at = scored.at(radius: 88, degrees: 90)
        let track = over(rgba(Theme.textPrimary), OrbitGaugePalette.middleTrackOpacity, background)
        let s = scored.pixel(at), p = pending.pixel(at)
        for (sc, pc, tc) in [(s.r, p.r, track.r), (s.g, p.g, track.g), (s.b, p.b, track.b)] where abs(sc - tc) > 40 {
            let ratio = Double(pc - tc) / Double(sc - tc)
            #expect(abs(ratio - OrbitGaugeMarks.pendingOpacity) < 0.03, "marks at \(ratio)")
        }
        // The outer tick at 9 o'clock (tick 96, past strain's 212.6) is the 16 % track in both.
        let tick = scored.at(radius: 118, degrees: 270)
        let outer = rgba(Theme.surfaceRaised)
        #expect(close(scored.pixel(tick), outer, 2) && close(pending.pixel(tick), outer, 2), "tracks at full strength")
    }

    /// The pixels inside the strain arc's stroke at S, clear of its antialiased edges (0.5 pt in from each), from past the
    /// start cap to before the head's halo, and how many are not `colour` (±3).
    private func strainStroke(_ shot: Shot, side: CGFloat, colour: RGBA) -> (inside: Int, off: Int, first: String) {
        let m = G.metrics(forSide: side)
        let head = G.Orbit.strain.headDegrees(for: 12.4 / 21)
        // The halo (it reaches past the dot's cut) ends this far from the head along the ring, plus a degree.
        let haloClear = G.clearDegrees(cut: m.haloRadius, radius: m.outerRadius) + 1
        var inside = 0, off = 0, first = ""
        shot.forEachPixel { p, c in
            let (dx, dy) = (Double(p.x - shot.centre.x), Double(p.y - shot.centre.y))
            guard abs(hypot(dx, dy) - Double(m.outerRadius)) <= Double(m.outerStroke) / 2 - 0.5 else { return }
            // Code degrees: clockwise from the top.
            let degrees = (atan2(dx, -dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            guard degrees > 4, degrees < head - haloClear else { return }
            inside += 1
            if !close(c, colour, 3) {
                off += 1
                if first.isEmpty { first = "\(c) at \(String(format: "%.1f", degrees)) deg" }
            }
        }
        return (inside, off, first)
    }

    /// Pending dims the marks to 0.6 over full-strength 16 % ticks, so the strain arc showed them through as a ladder
    /// (review PR 3 row 20). While pending the outer ring is cut under the arc: every pixel inside its stroke is the dimmed
    /// arc over the background, as the scored arc there is its colour; the ticks' ends still show beside it in both.
    @Test("Pending shows no ticks through the strain arc, and reads as scored, only dimmer",
          arguments: [OrbitGaugeSize.previewBoard, .large])
    func pendingShowsNoTicksThroughTheStrainArc(_ size: OrbitGaugeSize) throws {
        let strain = rgba(Theme.metricStrain)
        let pending = try #require(render(.pending(previous: .previewBoard), size))
        let dimmed = strainStroke(pending, side: size.frame, colour: over(strain, OrbitGaugeMarks.pendingOpacity, background))
        #expect(dimmed.inside > 400, "pixels sampled: \(dimmed.inside)")
        #expect(dimmed.off == 0, "\(dimmed.off) of \(dimmed.inside) pixels in the pending strain stroke are not the dimmed arc, first \(dimmed.first)")
        let scored = try #require(render(.scored(.previewBoard), size))
        let opaque = strainStroke(scored, side: size.frame, colour: strain)
        #expect(opaque.inside == dimmed.inside && opaque.off == 0, "scored: \(opaque.off) of \(opaque.inside), first \(opaque.first)")
        // A tick's outer end beside the arc, at 3 o'clock (tick 32), at the board's 260: the 16 % track, pending or not.
        if size == .previewBoard {
            let m = G.metrics(forSide: size.frame)
            let end = (m.outerStroke / 2 + m.outerTick.height / 2) / 2
            for (name, shot) in [("pending", pending), ("scored", scored)] {
                for radius in [m.outerRadius + end, m.outerRadius - end] {
                    #expect(close(shot.pixel(shot.at(radius: radius, degrees: 90)), rgba(Theme.surfaceRaised), 2),
                            "\(name): tick 32's end at r \(radius)")
                }
            }
        }
    }

    /// The cut is pending's alone, follows the arc's sweep (the entrance's too) and needs a tick ring.
    @Test func onlyPendingCutsTheTicksUnderTheStrainArc() {
        let sweep = G.Orbit.strain.sweep(for: 12.4 / 21)
        #expect(OrbitGaugeScene(mode: .pending(previous: .previewBoard), size: .previewBoard).strainTickCut == sweep)
        #expect(OrbitGaugeScene(mode: .pending(previous: .previewBoard), size: .medium).strainTickCut == sweep, "64 ticks")
        #expect(OrbitGaugeScene(mode: .pending(previous: .previewBoard), size: .small).strainTickCut == nil, "solid ring")
        #expect(OrbitGaugeScene(mode: .pending(previous: nil), size: .previewBoard).strainTickCut == nil, "no arc")
        #expect(OrbitGaugeScene(mode: .pending(previous: OrbitGaugeValues(readiness: 60, recovery: 0.5)),
                                size: .previewBoard).strainTickCut == nil, "no strain")
        #expect(OrbitGaugeScene(mode: .scored(.previewBoard), size: .previewBoard).strainTickCut == nil, "scored")
        #expect(OrbitGaugeScene(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .previewBoard).strainTickCut == nil)
        var entering = OrbitGaugeScene(mode: .pending(previous: .previewBoard), size: .previewBoard)
        entering.progress = 0.5
        #expect(entering.strainTickCut == sweep * 0.5, "it grows with the arc")
    }

    @Test func aMissingScoreIsAHollowDot() throws {
        let shot = try #require(render(.scored(OrbitGaugeValues(readiness: 64))))
        for (orbit, radius) in [(G.Orbit.strain, 118.0), (.recovery, 88), (.sleep, 88)] as [(G.Orbit, CGFloat)] {
            let centre = shot.at(radius: radius, degrees: orbit.startDegrees)
            #expect(close(shot.pixel(centre), background, 2), "\(orbit): the hollow dot's middle")
            // Its outline is the metric colour (r 7, 1.5 wide: r 6.25...7.75 at 260).
            let colour = rgba(Theme.color(for: orbit))
            let edge = G.point(centre: centre, radius: 7, degrees: orbit.startDegrees + 180)
            #expect(close(shot.pixel(edge), colour, 3), "\(orbit): the outline")
        }
    }

    // MARK: 17. the entrance and the sentences

    private func png<V: View>(_ view: V) -> Data? {
        let r = ImageRenderer(content: view.padding(20).background(Theme.background).environment(\.colorScheme, .dark))
        r.scale = 2
        return r.uiImage?.pngData()
    }

    @Test(arguments: [OrbitGaugeSize.previewBoard, .large])
    func theEntrancesLastFrameIsTheStaticRender(_ size: OrbitGaugeSize) {
        for mode in [OrbitGaugeMode.scored(.previewBoard), .calibrating(OrbitGaugeCalibration(nights: 3)),
                     .pending(previous: .previewBoard)] {
            let still = png(OrbitGauge(mode: mode, size: size, animatesFill: false, breathes: false))
            let end = png(OrbitGauge(mode: mode, size: size, animatesFill: false, breathes: false,
                                     entrance: .assemble, frozenAt: OrbitEntranceFrame.end))
            #expect(still != nil && still == end, "\(mode) at \(size)")
        }
    }

    /// `end` takes the settled branch of `OrbitEntranceStage`, so the test above never draws the choreography. A hair
    /// earlier (0.1 ms, the glide's cubic 6e-11 short of done) the choreography's own drawing must already be the static one.
    @Test(arguments: [OrbitGaugeSize.previewBoard, .large])
    func theChoreographysLastFrameIsTheStaticRender(_ size: OrbitGaugeSize) {
        let justBefore = OrbitEntranceFrame.end - 1e-4
        #expect(justBefore < OrbitEntranceFrame.end, "this frame is the choreography's, not the settled branch")
        for mode in [OrbitGaugeMode.scored(.previewBoard), .calibrating(OrbitGaugeCalibration(nights: 3)),
                     .pending(previous: .previewBoard)] {
            let still = png(OrbitGauge(mode: mode, size: size, animatesFill: false, breathes: false))
            let late = png(OrbitGauge(mode: mode, size: size, animatesFill: false, breathes: false,
                                      entrance: .assemble, frozenAt: justBefore))
            #expect(still != nil && still == late, "\(mode) at \(size), end - 1e-4")
        }
    }

    // MARK: the entrance as numbers: the scene at one moment

    private func sameDot(_ a: OrbitGaugeScene.Dot, _ b: OrbitGaugeScene.Dot) -> Bool {
        abs(a.radius - b.radius) < 1e-9 && abs(a.start - b.start) < 1e-9 && abs(a.sweep - b.sweep) < 1e-9
            && a.opacity == b.opacity && a.halo == b.halo
    }

    /// At `end` the entrance's scene is the static scene, field by field (the drawing then is by construction).
    @Test(arguments: [OrbitGaugeSize.previewBoard, .large, .medium, .small])
    func theSceneAtTheEntrancesEndIsTheStaticScene(_ size: OrbitGaugeSize) {
        for mode in [OrbitGaugeMode.scored(.previewBoard), .scored(OrbitGaugeValues(recovery: 0.82, sleep: 0.94, strain: 12.4)),
                     .calibrating(OrbitGaugeCalibration(nights: 3)), .pending(previous: .previewBoard)] {
            let still = OrbitGaugeScene(mode: mode, size: size)
            let end = OrbitGaugeScene(mode: mode, size: size, entrance: OrbitEntranceFrame(seconds: OrbitEntranceFrame.end))
            #expect(end.mode == still.mode && end.dial == still.dial && end.metrics == still.metrics, "\(mode) at \(size)")
            #expect(end.outerTrack == still.outerTrack && end.middleTrack == still.middleTrack
                        && end.innerTrack == still.innerTrack, "tracks, \(mode) at \(size)")
            #expect(end.progress == still.progress, "progress, \(mode) at \(size)")
            #expect(end.voltOpacity == still.voltOpacity && end.railOpacity == still.railOpacity, "volt and rail, \(mode) at \(size)")
            for orbit in G.Orbit.allCases {
                #expect(sameDot(end.dot(orbit), still.dot(orbit)), "\(orbit) dot, \(mode) at \(size): \(end.dot(orbit)) against \(still.dot(orbit))")
            }
            #expect(end.showsVolt == still.showsVolt && end.readiness == still.readiness)
        }
    }

    /// At 0.4 s the dots are in flight: arcs unfilled, no Volt dot yet (it fades in with the glide, from 0.6 s), and each
    /// dot's halo is as far along as its flight.
    @Test func theSceneMidFlightHasNoVoltAndAHaloAsFarAsTheFlight() {
        let mode = OrbitGaugeMode.scored(.previewBoard)
        let frame = OrbitEntranceFrame(seconds: 0.4)
        let scene = OrbitGaugeScene(mode: mode, size: .previewBoard, entrance: frame)
        #expect(scene.voltOpacity == 0 && !scene.showsVolt, "no Volt dot before its value glides in")
        #expect(scene.progress == 0 && scene.readiness == 0, "nothing filled yet")
        for orbit in G.Orbit.allCases {
            let flight = frame.flight(orbit)
            #expect(flight > 0 && flight < 1, "\(orbit) is in flight at 0.4 s: \(flight)")
            #expect(scene.dot(orbit).halo == flight, "\(orbit) halo follows the flight")
            #expect(scene.dot(orbit).opacity == min(flight * 4, 1), "\(orbit) dot opacity")
            #expect(scene.dot(orbit).sweep == 0, "\(orbit) arc not drawn yet")
            #expect(scene.dot(orbit).radius > OrbitGaugeScene(mode: mode, size: .previewBoard).dot(orbit).radius,
                    "\(orbit) still outside its ring")
        }
        // The halos differ by the stagger: strain leads, then recovery, then sleep.
        #expect(scene.strainDot.halo > scene.recoveryDot.halo && scene.recoveryDot.halo > scene.sleepDot.halo)
        // The tracks are all drawn by 0.25 s.
        #expect(scene.outerTrack == 1 && scene.middleTrack == 1 && scene.innerTrack == 1 && scene.railOpacity == 1)
    }

    @Test func theVoltDotFadesInOverTheFirstQuarterOfTheGlide() {
        let mode = OrbitGaugeMode.scored(.previewBoard)
        func volt(_ seconds: Double) -> Double {
            OrbitGaugeScene(mode: mode, size: .previewBoard, entrance: OrbitEntranceFrame(seconds: seconds)).voltOpacity
        }
        #expect(volt(0.5) == 0 && volt(OrbitEntranceFrame.glideStart) == 0)
        #expect(volt(OrbitEntranceFrame.glideStart + 0.01) > 0 && volt(OrbitEntranceFrame.glideStart + 0.01) < 1)
        #expect(volt(OrbitEntranceFrame.end) == 1)
    }

    @Test func reduceMotionIsA250msCrossFade() {
        #expect(OrbitEntranceFrame.fadeDuration == 0.25)
        let mode = OrbitGaugeMode.scored(.previewBoard)
        let size = OrbitGaugeSize.previewBoard
        func stage(_ elapsed: Double) -> some View {
            OrbitEntranceStage(elapsed: elapsed, reduced: true, mode: mode, size: size, palette: .assets,
                               settled: OrbitGaugeDrawing(mode: mode, size: size), centre: EmptyView())
        }
        let still = png(OrbitGaugeDrawing(mode: mode, size: size))
        #expect(png(stage(0.125)) != still, "half way through the fade")
        #expect(png(stage(0.25)) == still, "at 250 ms")
    }

    @Test func theSpokenSentencesAreThePR2Strings() {
        let spoken = OrbitGauge.spokenValue(.previewScored).replacingOccurrences(of: "9,6", with: "9.6")
        #expect(spoken == "71, High. Recovery 71\u{00A0}percent, Sleep 88\u{00A0}percent, Strain 9.6 of 21")
        #expect(OrbitGauge.spokenPending(.previewScored).replacingOccurrences(of: "9,6", with: "9.6")
                == "Not scored yet. Last scored: 71. Recovery 71\u{00A0}percent, Sleep 88\u{00A0}percent, Strain 9.6 of 21")
        #expect(OrbitGauge.spokenValue(OrbitGaugeCalibration(nights: 3))
                == "3 of 7\u{00A0}nights. Readiness appears once the baselines are complete.")
    }
}

private extension Theme {
    static func color(for orbit: OrbitGaugeGeometry.Orbit) -> Color {
        switch orbit {
        case .recovery: return Theme.recovery
        case .sleep: return Theme.metricSleep
        case .strain: return Theme.metricStrain
        }
    }
}
