import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Level by shape: `BandStyle` at the 67 and 34 boundaries, the ring's geometry, and the ring as rendered in both appearances.
/// Static renders read at the places the geometry gives. Synthetic values only.
@MainActor
@Suite("BandStyle")
struct BandStyleTests {
    typealias G = OrbitGaugeGeometry

    @Test(arguments: [
        (100, BandStyle.solid), (67, .solid), (66, .half), (34, .half), (33, .outlined), (0, .outlined),
    ] as [(Int, BandStyle)])
    func aScoreHasItsLevel(_ score: Int, _ style: BandStyle) {
        #expect(BandStyle(score: score) == style)
        // The colour side reads the same thresholds, so the band word, the colour and the shape can't drift apart.
        let palette = OrbitGaugePalette.assets
        let colour = style == .solid ? palette.high : style == .half ? palette.moderate : palette.low
        #expect(palette.band(forReadiness: score) == colour)
        #expect(Theme.band(forScore: score) == colour)
    }

    @Test func noScoreIsNoLevel() {
        #expect(BandStyle(score: nil) == .none)
        #expect(OrbitGaugePalette.assets.band(forReadiness: nil) == OrbitGaugePalette.assets.noReadiness)
    }

    @Test(arguments: [160, 112, 72] as [CGFloat])
    func theDashesAreSixteenWithAGapAtTheSeam(_ dial: CGFloat) {
        let radius = G.metrics(forDial: dial).centreRadius
        let pattern = G.ringDash(radius: radius)
        #expect(G.ringDashCount == 16)
        #expect(pattern.dash.count == 2 && abs(pattern.dash[0] - pattern.dash[1]) < 1e-9, "dashes as long as gaps")
        let turn = 2 * CGFloat.pi * radius
        #expect(abs(pattern.dash.reduce(0, +) * 16 - turn) < 1e-9, "the pattern closes on the circle")
        #expect(abs(pattern.phase - 1.5 * pattern.dash[0]) < 1e-9, "the path starts in the middle of a gap")
    }

    @Test func theOutlineIsTwoEdgesInsideTheStrokeWhereTheyFit() {
        let radii = G.outlinedRingRadii(forDial: 160)
        #expect(radii.count == 2)
        #expect(abs(radii[0] - 30.25) < 1e-9 && abs(radii[1] - 33.75) < 1e-9)
        #expect(abs((radii[1] - radii[0] - G.ringEdge) - 2.5) < 1e-9, "2.5 pt clear between the edges")
        #expect(G.outlinedRingRadii(forDial: 125).count == 2)
        #expect(G.outlinedRingRadii(forDial: 124) == [G.metrics(forDial: 124).centreRadius])
        #expect(G.outlinedRingRadii(forDial: 112) == [G.metrics(forDial: 112).centreRadius])
    }

    // MARK: rendered, in both appearances

    private struct RGB { var r, g, b: Double }

    private struct Shot {
        let width: Int, scale: CGFloat, frame: CGFloat, dial: CGFloat
        let bytes: [UInt8]

        func pixel(radius: CGFloat, degrees: Double) -> RGB {
            let p = G.point(centre: CGPoint(x: frame / 2, y: frame / 2), radius: radius, degrees: degrees)
            let i = (Int((p.y * scale).rounded()) * width + Int((p.x * scale).rounded())) * 4
            return RGB(r: Double(bytes[i]) / 255, g: Double(bytes[i + 1]) / 255, b: Double(bytes[i + 2]) / 255)
        }
    }

    private static let schemes: [(String, ColorScheme, UIUserInterfaceStyle)] = [("dark", .dark, .dark), ("light", .light, .light)]
    private static let sizes: [(String, OrbitGauge.Size)] = [("small", .small), ("medium", .medium), ("large", .large)]

    private func render(_ readiness: Int?, _ size: OrbitGauge.Size, _ scheme: ColorScheme) -> Shot? {
        let values = OrbitGaugeValues(readiness: readiness, recovery: 0.71, sleep: 0.88, strain: 9.6)
        let renderer = ImageRenderer(content: OrbitGauge(mode: .scored(values), size: size, animatesFill: false, breathes: false)
            .background(Theme.background)
            .environment(\.colorScheme, scheme))
        renderer.scale = 3
        guard let cg = renderer.uiImage?.cgImage else { return nil }
        let (w, h) = (cg.width, cg.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Shot(width: w, scale: 3, frame: size.frame, dial: size.dial, bytes: bytes)
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

    /// Middle of a dash and of a gap, round the ring.
    private static let dashDegrees = [11.25, 101.25, 191.25, 281.25], gapDegrees = [22.5, 112.5, 202.5, 292.5]

    /// The 67 and 34 boundaries and readiness 82, 50, 20, both appearances. Solid is the band's colour all round; moderate the
    /// colour at a dash and **the background at a gap**, never a track: light's `Warning` is 2.90:1 on the track and 3.45:1 here;
    /// low is the background on the centreline with ink at its edges, or one circle on the centreline where two won't fit.
    @Test(arguments: [82, 67, 66, 50, 34, 33, 20])
    func theRingIsDrawnByItsLevel(_ readiness: Int) throws {
        for (schemeName, scheme, uiStyle) in Self.schemes {
            let ink = rgb(OrbitGaugePalette.assets.band(forReadiness: readiness), uiStyle)
            let background = rgb(Theme.background, uiStyle)
            for (sizeName, size) in Self.sizes {
                let shot = try #require(render(readiness, size, scheme))
                let m = G.metrics(forDial: size.dial)
                let label = "\(readiness), \(sizeName), \(schemeName)"
                func at(_ r: CGFloat, _ d: Double) -> RGB { shot.pixel(radius: r, degrees: d) }
                func isInk(_ r: CGFloat, _ d: Double) -> Bool { distance(at(r, d), ink) < 0.2 }
                func isGround(_ r: CGFloat, _ d: Double) -> Bool { distance(at(r, d), background) < 0.03 }
                switch BandStyle(score: readiness) {
                case .solid:
                    for d in Self.dashDegrees + Self.gapDegrees { #expect(isInk(m.centreRadius, d), "solid at \(d): \(label)") }
                case .half:
                    for d in Self.dashDegrees { #expect(isInk(m.centreRadius, d), "dash at \(d): \(label)") }
                    for d in Self.gapDegrees {
                        #expect(isGround(m.centreRadius, d), "gap at \(d): \(label): \(at(m.centreRadius, d)) vs \(background)")
                    }
                case .outlined:
                    let radii = G.outlinedRingRadii(forDial: size.dial)
                    for d in Self.dashDegrees + Self.gapDegrees {
                        // A 1 pt line is 3 device pixels: within a pixel of its centreline, whichever way it rounds.
                        for r in radii {
                            #expect([r - 0.34, r, r + 0.34].contains { isInk($0, d) }, "edge \(r) at \(d): \(label)")
                        }
                        if radii.count == 2 {
                            #expect(isGround(m.centreRadius, d), "the background between the edges at \(d): \(label)")
                        } else {
                            #expect(isGround(m.centreRadius + 1.5, d), "one thin circle at \(d): \(label)")
                        }
                    }
                case .none:
                    Issue.record("these readiness values have a level: \(label)")
                }
            }
        }
    }

    /// No level is today's solid ring in `noReadiness`, until `design.md` 4.1 drops it in PR 3.
    @Test func withoutAReadinessTheRingStaysSolidAndTertiary() throws {
        for (schemeName, scheme, uiStyle) in Self.schemes {
            let ui = UIColor(Theme.textTertiary).resolvedColor(with: UITraitCollection(userInterfaceStyle: uiStyle))
            var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
            let ground = rgb(Theme.background, uiStyle)
            let ink = RGB(r: Double(r * a) + ground.r * Double(1 - a), g: Double(g * a) + ground.g * Double(1 - a),
                          b: Double(b * a) + ground.b * Double(1 - a))
            let shot = try #require(render(nil, .large, scheme))
            for d in Self.dashDegrees + Self.gapDegrees {
                #expect(distance(shot.pixel(radius: 32, degrees: d), ink) < 0.06, "\(d), \(schemeName)")
            }
        }
    }
}
