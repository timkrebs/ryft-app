import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// OrbitGauge PR 4 rendered: nil parity (byte-identical to a gauge with no band) and the pixels of the rail and of the
/// textured arc past the band. No golden images in this repo, so parity compares renders of the same build against each other:
/// a band that cannot be drawn (outside the scale, one point, non-finite), a band at a size and a state that draw
/// nothing of it, and the nil case itself. Static (`animatesFill: false`, `breathes: false`). Synthetic values only.
@MainActor
@Suite("OrbitGauge band: rendered")
struct OrbitGaugeBandRenderTests {
    typealias G = OrbitGaugeGeometry

    private struct RGB { var r, g, b: Double }

    private struct Shot {
        let width: Int, height: Int, scale: CGFloat, frame: CGFloat, dial: CGFloat
        let bytes: [UInt8]

        func pixel(_ p: CGPoint) -> RGB {
            let x = min(max(Int((p.x * scale).rounded()), 0), width - 1)
            let y = min(max(Int((p.y * scale).rounded()), 0), height - 1)
            let i = (y * width + x) * 4
            return RGB(r: Double(bytes[i]) / 255, g: Double(bytes[i + 1]) / 255, b: Double(bytes[i + 2]) / 255)
        }

        func onOrbit(_ referenceRadius: CGFloat, degrees: Double) -> CGPoint {
            let c = CGPoint(x: frame / 2, y: frame / 2)
            return G.point(centre: c, radius: referenceRadius * dial / G.referenceDial, degrees: degrees)
        }
    }

    private static let sizes: [(String, OrbitGauge.Size)] = [("small", .small), ("medium", .medium), ("large", .large)]
    private static let schemes: [(String, ColorScheme, UIUserInterfaceStyle)] = [("dark", .dark, .dark), ("light", .light, .light)]
    private static let band: ClosedRange<Double> = 8...13

    private func render(_ mode: OrbitGaugeMode, _ size: OrbitGauge.Size, _ scheme: ColorScheme,
                        entrance: OrbitGauge.Entrance = .none, frozenAt: Double? = nil) -> Shot? {
        shot(OrbitGauge(mode: mode, size: size, animatesFill: false, breathes: false, entrance: entrance, frozenAt: frozenAt),
             frame: size.frame, dial: size.dial, scheme)
    }

    /// Any view in a `frame` x `frame` box over the background, read as RGBA bytes at 3x.
    private func shot<V: View>(_ content: V, frame: CGFloat, dial: CGFloat, _ scheme: ColorScheme) -> Shot? {
        let view = content
            .background(Theme.background)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let cg = renderer.uiImage?.cgImage else { return nil }
        let (w, h) = (cg.width, cg.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Shot(width: w, height: h, scale: 3, frame: frame, dial: dial, bytes: bytes)
    }

    private func rgb(_ colour: Color, _ style: UIUserInterfaceStyle) -> RGB {
        let ui = UIColor(colour).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = ui.cgColor.converted(to: space, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0, 1]
        return RGB(r: Double(c[0]), g: Double(c[1]), b: Double(c[2]))
    }

    private func distance(_ a: RGB, _ b: RGB) -> Double {
        ((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b)).squareRoot()
    }

    private func blend(_ top: RGB, _ bottom: RGB, _ alpha: Double) -> RGB {
        RGB(r: top.r * alpha + bottom.r * (1 - alpha), g: top.g * alpha + bottom.g * (1 - alpha),
            b: top.b * alpha + bottom.b * (1 - alpha))
    }

    /// A pixel is the mark's rather than the ground's.
    private func isInk(_ p: RGB, ink: RGB, ground: RGB) -> Bool { distance(p, ink) < distance(p, ground) }

    /// Share of 3x pixels that are ink over `degrees` on an orbit, within `halfWidth` pt of its centreline: 1 pt by default, one
    /// hatch pitch across, so the figure holds where the arc runs along the hatch and leaves out the 1 pt edges.
    private func coverage(_ shot: Shot, degrees: ClosedRange<Double>, radius: CGFloat = 77, halfWidth: CGFloat = 1,
                          ink: RGB, ground: RGB) -> Double {
        var hits = 0, count = 0
        let scale = shot.dial / G.referenceDial
        let centre = CGPoint(x: shot.frame / 2, y: shot.frame / 2)
        let step = 1 / shot.scale
        for r in stride(from: radius * scale - halfWidth, through: radius * scale + halfWidth, by: step) {
            let angle = Double(step / r) * 180 / .pi
            for d in stride(from: degrees.lowerBound, through: degrees.upperBound, by: angle) {
                count += 1
                if isInk(shot.pixel(G.point(centre: centre, radius: r, degrees: d)), ink: ink, ground: ground) { hits += 1 }
            }
        }
        return count == 0 ? 0 : Double(hits) / Double(count)
    }

    /// Share of 3x pixels that are ink inside a disc.
    private func discCoverage(_ shot: Shot, at centre: CGPoint, radius: CGFloat, ink: RGB, ground: RGB) -> Double {
        var hits = 0, count = 0
        let step = 1 / shot.scale
        for dx in stride(from: -radius, through: radius, by: step) {
            for dy in stride(from: -radius, through: radius, by: step) where dx * dx + dy * dy <= radius * radius {
                count += 1
                if isInk(shot.pixel(CGPoint(x: centre.x + dx, y: centre.y + dy)), ink: ink, ground: ground) { hits += 1 }
            }
        }
        return count == 0 ? 0 : Double(hits) / Double(count)
    }

    /// The fine hatch is half ink (`RyftHatch`).
    private static let hatched = 0.35...0.65

    private func values(strain: Double?, band: ClosedRange<Double>?) -> OrbitGaugeValues {
        OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: strain, strainBand: band)
    }

    // MARK: 4. nil parity

    /// A mode over the given band: scored, strain missing, calibrating and pending (the previous day's values).
    private func modes(band: ClosedRange<Double>?) -> [(String, OrbitGaugeMode)] {
        [("scored", .scored(values(strain: 9.6, band: band))),
         ("scored, strain missing", .scored(values(strain: nil, band: band))),
         ("calibrating", .calibrating(OrbitGaugeCalibration(nights: 3))),
         ("pending", .pending(previous: values(strain: 9.6, band: band)))]
    }

    @Test func rendersAreDeterministicSoComparingThemMeansSomething() throws {
        let a = try #require(render(.scored(.previewScored), .large, .dark))
        let b = try #require(render(.scored(.previewScored), .large, .dark))
        #expect(a.bytes == b.bytes)
    }

    /// What this proves, and no more: an unusable band (outside the scale, one point, infinite) is treated as no band, in
    /// every mode, size and scheme. Both sides take the same branch, so it does not prove that nil is unchanged from before
    /// the band existed; that was checked once by hashing 84 renders on `main` and on the branch (design.md section 11),
    /// and the `.small` test below is the in-suite case that runs the band code and still must equal nil.
    @Test func anUnusableBandIsTreatedAsNoBand() throws {
        let undrawable: [(String, ClosedRange<Double>)] = [
            ("above the scale", 22...30), ("below the scale", -9 ... -1), ("one point", 10...10),
            ("infinite", -Double.infinity...Double.infinity), ("infinite upper", 8...Double.infinity),
        ]
        let reference = modes(band: nil)
        for (bandName, band) in undrawable {
            let candidate = modes(band: band)
            for (i, (modeName, _)) in reference.enumerated() {
                for (sizeName, size) in Self.sizes {
                    for (schemeName, scheme, _) in Self.schemes {
                        let nilShot = try #require(render(reference[i].1, size, scheme))
                        let shot = try #require(render(candidate[i].1, size, scheme))
                        #expect(shot.bytes == nilShot.bytes, "\(bandName): \(modeName), \(sizeName), \(schemeName)")
                    }
                }
            }
        }
    }

    /// At `.small` the rail is not drawn, and a strain inside or below the band does not shift: nothing differs from nil.
    @Test func smallWithStrainInOrBelowTheBandIsByteIdenticalToNoBand() throws {
        for strain in [4.0, 9.6, 13.0] as [Double] {
            for (schemeName, scheme, _) in Self.schemes {
                let nilShot = try #require(render(.scored(values(strain: strain, band: nil)), .small, scheme))
                let shot = try #require(render(.scored(values(strain: strain, band: Self.band)), .small, scheme))
                #expect(shot.bytes == nilShot.bytes, "strain \(strain), \(schemeName)")
            }
        }
    }

    /// The guard against a vacuous parity: where the band should show, the render does differ from nil.
    @Test func aDrawableBandDoesChangeThePicture() throws {
        for (schemeName, scheme, _) in Self.schemes {
            for (sizeName, size) in Self.sizes.dropFirst() {
                let nilShot = try #require(render(.scored(.previewScored), size, scheme))
                let shot = try #require(render(.scored(.previewBanded(strain: 9.6)), size, scheme))
                #expect(shot.bytes != nilShot.bytes, "rail at \(sizeName), \(schemeName)")
            }
            let nilSmall = try #require(render(.scored(values(strain: 16.5, band: nil)), .small, scheme))
            let small = try #require(render(.scored(values(strain: 16.5, band: Self.band)), .small, scheme))
            #expect(small.bytes != nilSmall.bytes, "the shift at small, \(schemeName)")
            let nilPending = try #require(render(.pending(previous: .previewScored), .medium, scheme))
            let pending = try #require(render(.pending(previous: .previewBanded(strain: 9.6)), .medium, scheme))
            #expect(pending.bytes != nilPending.bytes, "pending keeps the previous day's rail, \(schemeName)")
        }
    }

    // MARK: 5. pixels

    @Test func theRailShowsAtTheBandsMiddleOnlyWhenThereIsABand() throws {
        let mid = try #require(G.bandRail(for: Self.band)).start + (try #require(G.bandRail(for: Self.band)).sweep) / 2
        #expect(abs(mid - 180) < 0.01)
        for (schemeName, scheme, style) in Self.schemes {
            let banded = try #require(render(.scored(.previewBanded(strain: 9.6)), .large, scheme))
            let none = try #require(render(.scored(.previewScored), .large, scheme))
            let background = rgb(Theme.background, style)
            let rail = blend(rgb(Theme.metricStrain, style), background, G.bandRailOpacity)
            let at = banded.onOrbit(69.5, degrees: mid)
            #expect(distance(banded.pixel(at), rail) < 0.06, "rail colour, \(schemeName)")
            #expect(distance(none.pixel(at), background) < 0.03, "no rail without a band, \(schemeName)")
            // Along the rail, and not beyond its ends.
            for degrees in [mid - 40, mid + 40] {
                #expect(distance(banded.pixel(banded.onOrbit(69.5, degrees: degrees)), rail) < 0.06, "\(degrees), \(schemeName)")
            }
            for degrees in [120.0, 240.0] {
                #expect(distance(banded.pixel(banded.onOrbit(69.5, degrees: degrees)), background) < 0.03,
                        "outside the band at \(degrees), \(schemeName)")
            }
        }
    }

    /// 16.5 of 21 ends at 282.86 deg, the band at 222.86: the arc's colour behind the line, hatched past it with the dot
    /// hatched inside its rim. The same strain without a band is its colour all the way.
    @Test func theArcIsHatchedPastTheBandAndStrainColourInsideIt() throws {
        for (schemeName, scheme, style) in Self.schemes {
            let past = try #require(render(.scored(.previewBanded(strain: 16.5)), .large, scheme))
            let strain = rgb(Theme.metricStrain, style), alert = rgb(Theme.alert, style)
            let track = rgb(Theme.surfaceRaised, style), background = rgb(Theme.background, style)
            let hatch = coverage(past, degrees: 235...270, ink: alert, ground: track)
            #expect(Self.hatched.contains(hatch), "past, \(schemeName): \(hatch)")
            for degrees in [20.0, 100.0, 180.0, 215.0] {
                #expect(distance(past.pixel(past.onOrbit(77, degrees: degrees)), strain) < 0.06, "inside, \(degrees), \(schemeName)")
            }
            // The two 1 pt edges around the hatch.
            for radius in [74.75, 79.25] as [CGFloat] {
                let edge = coverage(past, degrees: 235...270, radius: radius, halfWidth: 0.2, ink: alert, ground: track)
                #expect(edge >= 0.85, "edge at \(radius), \(schemeName): \(edge)")
            }
            // The dot at the head is hatched too, inside its rim.
            let dot = discCoverage(past, at: past.onOrbit(77, degrees: 282.86), radius: 7, ink: alert, ground: background)
            #expect(Self.hatched.contains(dot), "dot, \(schemeName): \(dot)")
            // Without a band the same strain is strain-coloured all the way.
            let none = try #require(render(.scored(values(strain: 16.5, band: nil)), .large, scheme))
            #expect(distance(none.pixel(none.onOrbit(77, degrees: 250)), strain) < 0.06, "no band, \(schemeName)")
        }
    }

    @Test func atTheBandsUpperEndTheArcStaysStrainColour() throws {
        for (schemeName, scheme, style) in Self.schemes {
            let shot = try #require(render(.scored(.previewBanded(strain: 13)), .large, scheme))
            let strain = rgb(Theme.metricStrain, style)
            for degrees in [100.0, 180.0, 215.0] {
                #expect(distance(shot.pixel(shot.onOrbit(77, degrees: degrees)), strain) < 0.06, "\(degrees), \(schemeName)")
            }
        }
    }

    /// Too small for a hatch: past the band `.small` dashes the arc, 1.2 strokes on and 0.8 off, so a single point could land
    /// in a gap: several periods are measured. No rail at this size.
    @Test func theShiftShowsAtSmallWithoutARail() throws {
        for (schemeName, scheme, style) in Self.schemes {
            let shot = try #require(render(.scored(.previewBanded(strain: 16.5)), .small, scheme))
            let alert = rgb(Theme.alert, style), track = rgb(Theme.surfaceRaised, style)
            let dashed = coverage(shot, degrees: 235...270, halfWidth: 0.6, ink: alert, ground: track)
            #expect((0.45...0.75).contains(dashed), "arc, \(schemeName): \(dashed)")
            #expect(distance(shot.pixel(shot.onOrbit(69.5, degrees: 180)), rgb(Theme.background, style)) < 0.03,
                    "no rail, \(schemeName)")
        }
    }

    /// `.medium` is dashed too, and its dot stays solid with a ring of the ground in it.
    @Test func atMediumTheArcIsDashedAndTheDotKeepsARing() throws {
        for (schemeName, scheme, style) in Self.schemes {
            let shot = try #require(render(.scored(.previewBanded(strain: 16.5)), .medium, scheme))
            let alert = rgb(Theme.alert, style), background = rgb(Theme.background, style)
            let track = rgb(Theme.surfaceRaised, style)
            let dashed = coverage(shot, degrees: 235...270, ink: alert, ground: track)
            #expect((0.45...0.75).contains(dashed), "arc, \(schemeName): \(dashed)")
            let head = shot.onOrbit(77, degrees: 282.86), r = G.metrics(forDial: 112).dotRadius
            #expect(distance(shot.pixel(head), alert) < 0.1, "the dot's core, \(schemeName)")
            let ring = shot.pixel(G.point(centre: head, radius: r - 1.5, degrees: 45))
            #expect(isInk(ring, ink: background, ground: alert), "the ring in the dot, \(schemeName)")
        }
    }

    @Test func calibratingDrawsNoRailEvenWithABandInTheValues() throws {
        // `.calibrating` holds no values, so it has no band to carry; pixels on the rail's arc are background.
        for (schemeName, scheme, style) in Self.schemes {
            let shot = try #require(render(.calibrating(OrbitGaugeCalibration(nights: 3)), .large, scheme))
            let background = rgb(Theme.background, style)
            for degrees in [150.0, 180.0, 210.0] {
                #expect(distance(shot.pixel(shot.onOrbit(69.5, degrees: degrees)), background) < 0.03,
                        "\(degrees), \(schemeName)")
            }
        }
    }

    // MARK: the entrance with a band (the review's blocking bug)

    /// During the glide the arc grows from the top; wherever the head is, what is behind the split is its full colour and
    /// what is past it is hatched, whatever the final strain is. One ink in light, so the signal is coverage, not colour.
    @Test(arguments: [0.65, 0.72, 0.8])
    func midGlideTheArcInsideTheBandIsNeverHatched(_ t: Double) throws {
        let split = try #require(G.strainSplitDegrees(band: Self.band))
        let final = values(strain: 16.5, band: Self.band)
        let glide = OrbitEntranceFrame(seconds: t).glide
        let head = G.Orbit.strain.sweep(for: try #require(final.strainFraction)) * glide
        #expect(glide > 0 && glide < 1, "t \(t) is mid-glide")
        for (schemeName, scheme, style) in Self.schemes {
            let shot = try #require(render(.scored(final), .large, scheme, entrance: .assemble, frozenAt: t))
            let strain = rgb(Theme.metricStrain, style), alert = rgb(Theme.alert, style)
            let track = rgb(Theme.surfaceRaised, style)
            var sampled = 0, sampledPast = 0
            for degrees in stride(from: 12.0, to: head - 14, by: 6.0) {
                let window = degrees - 3...degrees + 3
                if degrees < split - 4 {
                    sampled += 1
                    let c = coverage(shot, degrees: window, ink: strain, ground: track)
                    #expect(c >= 0.95, "\(degrees) deg at t \(t) is whole, \(schemeName): \(c)")
                } else if degrees > split + 4 {
                    sampledPast += 1
                    let c = coverage(shot, degrees: window, ink: alert, ground: track)
                    #expect(Self.hatched.contains(c), "\(degrees) deg at t \(t) is hatched, \(schemeName): \(c)")
                }
            }
            #expect(sampled > 0, "t \(t) samples the arc inside the band (head \(head))")
            if head > split + 20 { #expect(sampledPast > 0) }
        }
    }

    /// The two trees (the static drawing and the entrance's settled state) are rasterised by SwiftUI separately, and the
    /// static one sometimes comes out slightly different for a while. Measured 2026-11-04: for tens of seconds in a
    /// process, `strain 4.0, dark` had 7 anti-aliased edge pixels off by one level, the same 7 every time; the entrance's
    /// frame was unchanged and a re-render of the static one matched itself. A probe saw it after an entrance render too,
    /// up to 19 pixels at one level, so the trigger may be render order; it isn't known. Byte equality failed on that.
    /// So: equal up to `tolerance` levels in a channel in at most `maxPixels` pixels. A different colour, position, size
    /// or opacity of anything moves far more pixels or far more levels; what this no longer sees is a difference of
    /// 2 levels or less in up to 64 of 266 256 pixels, which nobody can see.
    private static let tolerance = 2, maxPixels = 64

    static func nearlyEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var off = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            var worst = 0
            for k in 0..<4 { worst = max(worst, abs(Int(a[i + k]) - Int(b[i + k]))) }
            if worst > tolerance { return false }
            if worst > 0 { off += 1 }
        }
        return off <= maxPixels
    }

    /// The entrance is a second drawing of the ring and the past dot, and its last frame hands over to the static one, so
    /// parity at the end alone proves nothing about them. A moment before it, at every level, the choreography must already
    /// draw what the static gauge draws: a solid entrance ring or a filled dot fails here.
    @Test(arguments: [50, 20])
    func justBeforeItsEndTheEntranceDrawsTheStaticRingAndDot(_ readiness: Int) throws {
        let values = OrbitGaugeValues(readiness: readiness, recovery: 0.71, sleep: 0.88, strain: 16.5, strainBand: Self.band)
        for (schemeName, scheme, style) in Self.schemes {
            let still = try #require(render(.scored(values), .large, scheme))
            let entrance = try #require(render(.scored(values), .large, scheme, entrance: .assemble,
                                               frozenAt: OrbitEntranceFrame.end - 0.0005))
            for r in [30.25, 32, 33.75] as [CGFloat] {
                for degrees in stride(from: 0.0, to: 360, by: 2.8125) {
                    #expect(distance(entrance.pixel(entrance.onOrbit(r, degrees: degrees)), still.pixel(still.onOrbit(r, degrees: degrees))) < 0.1,
                            "ring r \(r) at \(degrees), readiness \(readiness), \(schemeName)")
                }
            }
            let alert = rgb(Theme.alert, style), background = rgb(Theme.background, style)
            let dot = discCoverage(entrance, at: entrance.onOrbit(77, degrees: 282.86), radius: 7, ink: alert, ground: background)
            #expect(Self.hatched.contains(dot), "the entrance's past dot, \(schemeName): \(dot)")
        }
    }

    @Test(arguments: [50, 20])
    func theEntrancesLastFrameEqualsTheStaticRenderAtEveryLevel(_ readiness: Int) throws {
        let values = OrbitGaugeValues(readiness: readiness, recovery: 0.71, sleep: 0.88, strain: 16.5, strainBand: Self.band)
        for (schemeName, scheme, _) in Self.schemes {
            let still = try #require(render(.scored(values), .large, scheme))
            let end = try #require(render(.scored(values), .large, scheme, entrance: .assemble, frozenAt: OrbitEntranceFrame.end))
            #expect(Self.nearlyEqual(end.bytes, still.bytes), "readiness \(readiness), \(schemeName)")
        }
    }

    @Test func theEntrancesLastFrameEqualsTheStaticRenderWithABand() throws {
        for strain in [4.0, 9.6, 16.5] as [Double] {
            for (schemeName, scheme, _) in Self.schemes {
                let still = try #require(render(.scored(values(strain: strain, band: Self.band)), .large, scheme))
                let end = try #require(render(.scored(values(strain: strain, band: Self.band)), .large, scheme,
                                              entrance: .assemble, frozenAt: OrbitEntranceFrame.end))
                #expect(Self.nearlyEqual(end.bytes, still.bytes), "strain \(strain), \(schemeName)")
            }
        }
    }

    /// The tolerance of the test above is narrow and not vacuous: the 7 one-level pixels it exists for pass, in any
    /// colour channel; one level past the tolerance doesn't, one pixel past the count doesn't, nor does a different size.
    @Test func theToleranceIsNarrow() {
        let base = [UInt8](repeating: 40, count: 4 * 1000)
        func changed(_ pixels: Int, by delta: Int, channel: Int = 1) -> [UInt8] {
            var b = base
            for p in 0..<pixels { b[p * 4 + channel] = UInt8(40 + delta) }
            return b
        }
        #expect(Self.nearlyEqual(base, base))
        #expect(Self.nearlyEqual(base, changed(7, by: 1)))
        #expect(Self.nearlyEqual(base, changed(64, by: 2)))
        #expect(!Self.nearlyEqual(base, changed(1, by: 3)))
        #expect(!Self.nearlyEqual(base, changed(1, by: 3, channel: 0)))
        #expect(!Self.nearlyEqual(base, changed(1, by: 3, channel: 2)))
        #expect(!Self.nearlyEqual(base, changed(65, by: 1)))
        #expect(!Self.nearlyEqual(base, Array(base.dropLast(4))))
    }

    // MARK: animatable sweep

    @Test func theStrainArcAnimatesItsSweepAndTheSplitStaysPut() throws {
        var arc = OrbitStrainArc(radius: 77, stroke: 11, sweep: 150, split: 222.86, plain: Theme.metricStrain, past: Theme.alert,
                                 texture: .hatch)
        #expect(arc.animatableData == 150)
        for (schemeName, scheme, style) in Self.schemes {
            let before = try #require(shot(ZStack { arc }.frame(width: 172, height: 172), frame: 172, dial: 160, scheme))
            arc.animatableData = 270
            #expect(arc.sweep == 270)
            let after = try #require(shot(ZStack { arc }.frame(width: 172, height: 172), frame: 172, dial: 160, scheme))
            arc.animatableData = 150
            let strain = rgb(Theme.metricStrain, style), alert = rgb(Theme.alert, style)
            let background = rgb(Theme.background, style)
            #expect(distance(before.pixel(before.onOrbit(77, degrees: 140)), strain) < 0.08, "\(schemeName)")
            #expect(distance(before.pixel(before.onOrbit(77, degrees: 250)), alert) > 0.15, "no past layer below the split")
            #expect(distance(after.pixel(after.onOrbit(77, degrees: 140)), strain) < 0.08)
            #expect(distance(after.pixel(after.onOrbit(77, degrees: 215)), strain) < 0.08, "behind the line")
            let hatch = coverage(after, degrees: 245...255, ink: alert, ground: background)
            #expect(Self.hatched.contains(hatch), "past the line once swept, \(schemeName): \(hatch)")
        }
    }

    @Test func theStrainDotTurnsHatchedExactlyWhenItsHeadPassesTheSplit() throws {
        let split = 222.86
        var dot = OrbitStrainDot(radius: 77, sweep: split - 0.5, dotRadius: 9, split: split,
                                 plain: Theme.metricStrain, past: Theme.alert, texture: .hatch)
        #expect(dot.animatableData == split - 0.5)
        for (schemeName, scheme, style) in Self.schemes {
            let strain = rgb(Theme.metricStrain, style), alert = rgb(Theme.alert, style)
            let background = rgb(Theme.background, style)
            /// Inside the dot's 1 pt rim. In a group, as the marks are: the dot clears what is under it from its own layer.
            func inside(_ dot: OrbitStrainDot, ink: RGB) throws -> Double {
                let s = try #require(shot(ZStack { dot }.compositingGroup().frame(width: 172, height: 172), frame: 172, dial: 160, scheme))
                return discCoverage(s, at: s.onOrbit(77, degrees: dot.sweep), radius: 7.5, ink: ink, ground: background)
            }
            dot.animatableData = split - 0.5
            #expect(try inside(dot, ink: strain) >= 0.95, "just before, \(schemeName)")
            dot.animatableData = split           // exactly at the line: not past
            #expect(try inside(dot, ink: strain) >= 0.95, "at the line, \(schemeName)")
            dot.animatableData = split + 0.5
            #expect(Self.hatched.contains(try inside(dot, ink: alert)), "just after, \(schemeName)")
        }
    }
}
