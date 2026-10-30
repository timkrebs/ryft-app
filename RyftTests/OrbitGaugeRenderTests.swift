import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// PR 2 rendered: the app's `OrbitGauge` drawn by `ImageRenderer` in both appearances at the three sizes, and the
/// pixels read at the places the geometry says things are. There are no golden images in this repo (the shots in
/// `OrbitGaugeShotsTests` are written, not compared), so each assertion names the colour that must be at a point.
/// Static: `animatesFill: false`, `breathes: false`, nothing depends on time.
@MainActor
@Suite struct OrbitGaugeRenderTests {
    typealias G = OrbitGaugeGeometry

    private struct RGB { var r, g, b: Double }

    private struct Shot {
        let width: Int, height: Int, scale: CGFloat, frame: CGFloat, dial: CGFloat
        let bytes: [UInt8]

        /// The pixel at a point of the gauge's frame (points from its top-left).
        func pixel(_ p: CGPoint) -> RGB {
            let x = min(max(Int((p.x * scale).rounded()), 0), width - 1)
            let y = min(max(Int((p.y * scale).rounded()), 0), height - 1)
            let i = (y * width + x) * 4
            return RGB(r: Double(bytes[i]) / 255, g: Double(bytes[i + 1]) / 255, b: Double(bytes[i + 2]) / 255)
        }

        /// A point on an orbit of the reference drawing, scaled to this dial.
        func onOrbit(_ referenceRadius: CGFloat, degrees: Double) -> CGPoint {
            let c = CGPoint(x: frame / 2, y: frame / 2)
            return G.point(centre: c, radius: referenceRadius * dial / G.referenceDial, degrees: degrees)
        }
    }

    private static let sizes: [(String, OrbitGauge.Size)] = [("small", .small), ("medium", .medium), ("large", .large)]
    private static let schemes: [(String, ColorScheme, UIUserInterfaceStyle)] = [("dark", .dark, .dark), ("light", .light, .light)]

    private func render(_ mode: OrbitGaugeMode, _ size: OrbitGauge.Size, _ scheme: ColorScheme,
                        animatesFill: Bool = false) -> Shot? {
        let view = OrbitGauge(mode: mode, size: size, animatesFill: animatesFill, breathes: false)
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
        return Shot(width: w, height: h, scale: 3, frame: size.frame, dial: size.dial, bytes: bytes)
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

    private enum Ink { case filled, track, background }

    /// Which of the three colours the pixel is nearest to.
    private func ink(_ p: RGB, style: UIUserInterfaceStyle) -> Ink {
        let options: [(Ink, RGB)] = [(.filled, rgb(Theme.accent, style)), (.track, rgb(Theme.surfaceRaised, style)),
                                      (.background, rgb(Theme.background, style))]
        return options.min { distance($0.1, p) < distance($1.1, p) }!.0
    }

    /// The centre of segment `i` on the outer orbit's centreline.
    private func segmentMiddle(_ i: Int, required: Int = 7, dial: CGFloat) -> Double {
        let s = G.segments(required: required, dial: dial)[i]
        return s.start + s.sweep / 2
    }

    // MARK: calibrating

    @Test(arguments: [0, 3, 7])
    func calibratingFillsThatManySegmentsInEverySizeAndScheme(nights: Int) throws {
        for (sizeName, size) in Self.sizes {
            for (schemeName, scheme, style) in Self.schemes {
                let shot = try #require(render(.calibrating(OrbitGaugeCalibration(nights: nights)), size, scheme),
                                        "\(sizeName) \(schemeName) renders")
                let label = "\(nights) nights, \(sizeName), \(schemeName)"
                for i in 0..<7 {
                    let p = shot.pixel(shot.onOrbit(77, degrees: segmentMiddle(i, dial: size.dial)))
                    #expect(ink(p, style: style) == (i < nights ? .filled : .track), "segment \(i): \(label)")
                }
            }
        }
    }

    @Test(arguments: [0, 3, 7])
    func calibratingKeepsTheGapsAndTheSeamClear(nights: Int) throws {
        for (sizeName, size) in Self.sizes.dropFirst() {
            for (schemeName, scheme, style) in Self.schemes {
                let shot = try #require(render(.calibrating(OrbitGaugeCalibration(nights: nights)), size, scheme))
                let cap = Double(G.metrics(forDial: size.dial).outerStroke / 2 / G.metrics(forDial: size.dial).outerRadius) * 180 / .pi
                let segments = G.segments(required: 7, dial: size.dial)
                for i in 0..<6 {
                    let mid = ((segments[i].start + segments[i].sweep + cap) + (segments[i + 1].start - cap)) / 2
                    #expect(ink(shot.pixel(shot.onOrbit(77, degrees: mid)), style: style) == .background,
                            "gap \(i): \(nights) nights, \(sizeName), \(schemeName)")
                }
                // The hollow dot at the top is an outline: its middle is the background, never a segment.
                #expect(ink(shot.pixel(shot.onOrbit(77, degrees: 0)), style: style) == .background,
                        "seam: \(nights) nights, \(sizeName), \(schemeName)")
            }
        }
    }

    @Test func calibratingDrawsNoInnerArcsAndNoCentreRing() throws {
        for (schemeName, scheme, style) in Self.schemes {
            let shot = try #require(render(.calibrating(OrbitGaugeCalibration(nights: 3)), .large, scheme))
            // 3 and 9 o'clock on the inner orbit: where a Recovery or Sleep arc of 50 % would end. Track only.
            #expect(ink(shot.pixel(shot.onOrbit(54, degrees: 90)), style: style) == .track, "sleep side, \(schemeName)")
            #expect(ink(shot.pixel(shot.onOrbit(54, degrees: -90)), style: style) == .track, "recovery side, \(schemeName)")
            // The centre ring (r 32) at 3 o'clock is its track: no band colour without a readiness.
            #expect(ink(shot.pixel(shot.onOrbit(32, degrees: 90)), style: style) == .track, "centre ring, \(schemeName)")
        }
    }

    @Test func aHigherCountOnlyAddsFilledSegments() throws {
        for (_, scheme, style) in Self.schemes {
            var previous = 0
            for nights in 0...7 {
                let shot = try #require(render(.calibrating(OrbitGaugeCalibration(nights: nights)), .medium, scheme))
                let filled = (0..<7).filter {
                    ink(shot.pixel(shot.onOrbit(77, degrees: segmentMiddle($0, dial: 112))), style: style) == .filled
                }
                #expect(filled == Array(0..<nights))
                #expect(filled.count >= previous)
                previous = filled.count
            }
        }
    }

    @Test func aCountPastTheRequirementDrawsAllSevenAndNegativeDrawsNone() throws {
        for (_, scheme, style) in Self.schemes {
            let over = try #require(render(.calibrating(OrbitGaugeCalibration(nights: 12)), .large, scheme))
            let under = try #require(render(.calibrating(OrbitGaugeCalibration(nights: -4)), .large, scheme))
            for i in 0..<7 {
                let at = over.onOrbit(77, degrees: segmentMiddle(i, dial: 160))
                #expect(ink(over.pixel(at), style: style) == .filled)
                #expect(ink(under.pixel(at), style: style) == .track)
            }
        }
    }

    /// Reduce Motion cannot be injected (`accessibilityReduceMotion` is read-only), so the "no stepping" path is checked
    /// through its other switch, `animatesFill: false`: the very first frame already shows the final count.
    @Test func withoutTheFillAnimationTheFirstFrameShowsTheFinalCount() throws {
        for (_, scheme, style) in Self.schemes {
            let shot = try #require(render(.calibrating(OrbitGaugeCalibration(nights: 3)), .large, scheme, animatesFill: false))
            let filled = (0..<7).filter {
                ink(shot.pixel(shot.onOrbit(77, degrees: segmentMiddle($0, dial: 160))), style: style) == .filled
            }
            #expect(filled == [0, 1, 2])
        }
    }

    // MARK: pending

    /// Pending draws the previous day's Sleep arc (88 %, so 3 o'clock is on it) at 0.6 of its colour over the track.
    @Test func pendingDimsThePreviousDayAgainstTheScoredGauge() throws {
        for (schemeName, scheme, style) in Self.schemes {
            for (sizeName, size) in Self.sizes {
                let scored = try #require(render(.scored(.previewScored), size, scheme))
                let pending = try #require(render(.pending(previous: .previewScored), size, scheme))
                let at = scored.onOrbit(54, degrees: 90)
                let sleep = rgb(Theme.metricSleep, style), track = rgb(Theme.surfaceRaised, style)
                let label = "\(sizeName), \(schemeName)"
                #expect(distance(scored.pixel(at), sleep) < 0.06, "scored is the full colour: \(label)")
                #expect(distance(pending.pixel(at), blend(sleep, track, OrbitGaugeMarks.pendingOpacity)) < 0.06,
                        "pending is 0.6 of it over the track: \(label)")
                #expect(distance(pending.pixel(at), scored.pixel(at)) > 0.04, "and visibly dimmer: \(label)")
                // The recovery arc (71 %) at 9 o'clock is drawn too.
                let rAt = scored.onOrbit(54, degrees: -90)
                let recovery = rgb(Theme.accent, style)
                #expect(distance(pending.pixel(rAt), blend(recovery, track, OrbitGaugeMarks.pendingOpacity)) < 0.06,
                        "recovery: \(label)")
            }
        }
    }

    @Test func pendingWithoutADayBeforeDrawsTracksOnly() throws {
        for (schemeName, scheme, style) in Self.schemes {
            let shot = try #require(render(.pending(previous: nil), .large, scheme))
            for (name, radius, degrees) in [("sleep", 54.0, 90.0), ("recovery", 54.0, -90.0), ("strain", 77.0, 90.0)] {
                #expect(ink(shot.pixel(shot.onOrbit(radius, degrees: degrees)), style: style) == .track,
                        "\(name) side, \(schemeName)")
            }
        }
    }

    @Test func pendingKeepsTheTracksAtFullStrength() throws {
        // The unscored remainder of the outer orbit (strain 9.6 of 21 ends at 165 deg) is the plain track colour even
        // while the marks are dimmed.
        for (schemeName, scheme, style) in Self.schemes {
            let shot = try #require(render(.pending(previous: .previewScored), .large, scheme))
            #expect(distance(shot.pixel(shot.onOrbit(77, degrees: 270)), rgb(Theme.surfaceRaised, style)) < 0.04,
                    "track at 9 o'clock, \(schemeName)")
        }
    }

    // MARK: every PR 2 mode renders at every size (the shot matrix)

    @Test func everyPR2ModeRendersAtEverySizeInBothSchemes() throws {
        let modes: [(String, OrbitGaugeMode)] = [
            ("calibrating-0", .calibrating(OrbitGaugeCalibration(nights: 0))),
            ("calibrating-3", .calibrating(OrbitGaugeCalibration(nights: 3))),
            ("calibrating-7", .calibrating(OrbitGaugeCalibration(nights: 7))),
            ("pending-previous", .pending(previous: .previewScored)),
            ("pending-none", .pending(previous: nil)),
        ]
        let dir = ProcessInfo.processInfo.environment["ORBIT_SHOTS_DIR"]
        for (modeName, mode) in modes {
            for (sizeName, size) in Self.sizes {
                for (schemeName, scheme, _) in Self.schemes {
                    let shot = try #require(render(mode, size, scheme), "\(modeName) \(sizeName) \(schemeName)")
                    #expect(shot.width == Int(size.frame * 3) && shot.height == Int(size.frame * 3))
                    if let dir {
                        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                        let view = OrbitGauge(mode: mode, size: size, animatesFill: false, breathes: false)
                            .padding(20).background(Theme.background).environment(\.colorScheme, scheme)
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 3
                        try? renderer.uiImage?.pngData()?.write(
                            to: URL(fileURLWithPath: "\(dir)/pr2-\(modeName)-\(sizeName)-\(schemeName).png"))
                    }
                }
            }
        }
    }
}
