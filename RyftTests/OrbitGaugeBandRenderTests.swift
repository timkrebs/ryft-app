import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// OrbitGauge PR 4 rendered: nil parity (byte-identical to a gauge with no band) and the pixels of the rail and of the
/// arc past the band. No golden images in this repo, so parity compares renders of the same build against each other:
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

    private func render(_ mode: OrbitGaugeMode, _ size: OrbitGauge.Size, _ scheme: ColorScheme) -> Shot? {
        let view = OrbitGauge(mode: mode, size: size, animatesFill: false, breathes: false)
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

    /// A band that cannot be drawn takes the same path as no band at all: byte-identical, in every mode, size and scheme.
    @Test func anUndrawableBandRendersByteIdenticalToNoBand() throws {
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

    @Test func theArcIsAlertPastTheBandAndStrainColourInsideIt() throws {
        for (schemeName, scheme, style) in Self.schemes {
            let past = try #require(render(.scored(.previewBanded(strain: 16.5)), .large, scheme))
            let strain = rgb(Theme.metricStrain, style), alert = rgb(Theme.alert, style)
            // 16.5 of 21 ends at 282.86 deg; the band ends at 222.86.
            for degrees in [235.0, 250.0, 270.0] {
                #expect(distance(past.pixel(past.onOrbit(77, degrees: degrees)), alert) < 0.06, "past, \(degrees), \(schemeName)")
            }
            for degrees in [20.0, 100.0, 180.0, 215.0] {
                #expect(distance(past.pixel(past.onOrbit(77, degrees: degrees)), strain) < 0.06, "inside, \(degrees), \(schemeName)")
            }
            // The dot at the head is alert too.
            #expect(distance(past.pixel(past.onOrbit(77, degrees: 282.86)), alert) < 0.06, "dot, \(schemeName)")
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

    @Test func theShiftShowsAtSmallWithoutARail() throws {
        for (schemeName, scheme, style) in Self.schemes {
            let shot = try #require(render(.scored(.previewBanded(strain: 16.5)), .small, scheme))
            #expect(distance(shot.pixel(shot.onOrbit(77, degrees: 260)), rgb(Theme.alert, style)) < 0.08, "arc, \(schemeName)")
            #expect(distance(shot.pixel(shot.onOrbit(69.5, degrees: 180)), rgb(Theme.background, style)) < 0.03,
                    "no rail, \(schemeName)")
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
}
