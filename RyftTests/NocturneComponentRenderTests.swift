import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The Nocturne components drawn by `ImageRenderer` and read pixel by pixel (docs/work/2026-11-16-nocturne/design.md §P2-7,
/// tests 16–22, plus the render half of DotRow, TickRow and the buttons). There are no golden images in this repo, so each
/// assertion names the colour that must be at a point. Static: nothing here depends on time.
///
/// Tolerance, once: a pixel is 8-bit sRGB after `ImageRenderer`'s colour conversion, so a colour is right to within 2/255 per
/// channel (`design.md` test 18 and 20); 1/255 where the colour is flat and unblended (test 19). Anti-aliased pixels are
/// never sampled: edges are skipped, or the sample sits at a pixel centre well inside the shape.
@MainActor
@Suite struct NocturneComponentRenderTests {
    private typealias Tokens = NocturneTokenTests
    private typealias RGBA = NocturneTokenTests.RGBA

    // MARK: reading pixels

    private struct Shot {
        let width: Int, height: Int, scale: CGFloat
        let bytes: [UInt8]

        /// The image's size in points.
        var size: CGSize { CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale) }

        func px(_ ix: Int, _ iy: Int) -> RGBA {
            let i = (iy * width + ix) * 4
            let a = Double(bytes[i + 3]) / 255
            guard a > 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
            return RGBA(r: Double(bytes[i]) / 255 / a, g: Double(bytes[i + 1]) / 255 / a, b: Double(bytes[i + 2]) / 255 / a, a: a)
        }

        /// The pixel that covers the point (points from the image's top-left).
        func at(_ x: Double, _ y: Double) -> RGBA {
            px(min(max(Int((x * Double(scale)).rounded(.down)), 0), width - 1),
               min(max(Int((y * Double(scale)).rounded(.down)), 0), height - 1))
        }

        /// The box (in points) around the pixels in `xs` × `ys` (pixel centres) for which `match` holds.
        func bounds(xs: ClosedRange<Double>, ys: ClosedRange<Double>, where match: (RGBA) -> Bool) -> CGRect? {
            var (minX, minY, maxX, maxY) = (Int.max, Int.max, Int.min, Int.min)
            for iy in 0..<height {
                let y = (Double(iy) + 0.5) / Double(scale)
                guard ys.contains(y) else { continue }
                for ix in 0..<width {
                    let x = (Double(ix) + 0.5) / Double(scale)
                    guard xs.contains(x), match(px(ix, iy)) else { continue }
                    minX = min(minX, ix); maxX = max(maxX, ix); minY = min(minY, iy); maxY = max(maxY, iy)
                }
            }
            guard minX <= maxX else { return nil }
            return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                          width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        }
    }

    /// `view` drawn at `scale`, with that `displayScale` in the environment so the ruler snaps its ticks to the same pixels.
    private func render<V: View>(_ view: V, scale: CGFloat = 4) -> Shot? {
        let renderer = ImageRenderer(content: view.environment(\.displayScale, scale))
        renderer.scale = scale
        guard let cg = renderer.uiImage?.cgImage else { return nil }
        let (w, h) = (cg.width, cg.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Shot(width: w, height: h, scale: scale, bytes: bytes)
    }

    // MARK: colours

    private var ink: RGBA { Tokens.resolve(Theme.textPrimary) }
    private var screen: RGBA { Tokens.resolve(Theme.background) }
    private var surface: RGBA { Tokens.resolve(Theme.surface) }
    private var volt: RGBA { Tokens.resolve(Theme.signal) }

    private func with(_ c: RGBA, alpha: Double) -> RGBA { RGBA(r: c.r, g: c.g, b: c.b, a: alpha) }
    private func opaque(_ c: RGBA) -> RGBA { RGBA(r: c.r, g: c.g, b: c.b, a: 1) }

    /// `fraction` of the ink over the screen: how an unlit mark or a dimmed fill looks.
    private func inkOverScreen(_ fraction: Double) -> RGBA { Tokens.over(with(ink, alpha: fraction), screen) }

    /// Every channel within `steps`/255 of `expected`; alpha ignored (the shots are drawn on an opaque ground).
    private func near(_ actual: RGBA, _ expected: RGBA, _ steps: Double = 2) -> Bool {
        let t = steps / 255 + 1e-9
        return abs(actual.r - expected.r) <= t && abs(actual.g - expected.g) <= t && abs(actual.b - expected.b) <= t
    }

    private func describe(_ c: RGBA) -> String { Tokens.describe(c) }

    private func distance(_ a: RGBA, _ b: RGBA) -> Double {
        ((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b)).squareRoot()
    }

    /// Anything visibly different from the screen colour.
    private func isInk(_ p: RGBA) -> Bool { distance(p, screen) > 0.06 }

    // MARK: the glow tile

    enum Metric: CaseIterable, Sendable, CustomTestStringConvertible {
        case recovery, sleep, strain
        var colour: Color {
            switch self {
            case .recovery: return Theme.recovery
            case .sleep: return Theme.metricSleep
            case .strain: return Theme.metricStrain
            }
        }
        var testDescription: String { "\(self)" }
    }

    /// A tile drawn alone on a transparent ground, `pad` points of it around, so the shadow test has somewhere to look.
    private struct GlowShot {
        let shot: Shot
        let pad: Double, width: Double, height: Double, radius: Double
        func at(_ x: Double, _ y: Double) -> RGBA { shot.at(x + pad, y + pad) }
    }

    private func glow(_ metric: Color, width: CGFloat, height: CGFloat, radius: GlowTileSpec.Radius = .tile,
                      flat: Bool = false, scale: CGFloat = 2) -> GlowShot? {
        let pad: CGFloat = 8
        let view = GlowTile(metric, radius: radius, reduceTransparency: flat) { Color.clear }
            .frame(width: width, height: height)
            .padding(pad)
        guard let shot = render(view, scale: scale) else { return nil }
        return GlowShot(shot: shot, pad: pad, width: width, height: height, radius: radius.points)
    }

    /// The tile's ellipse (design.md §P2-3): 0 at its centre (0.5·W, 0.55·H), 1 on the ellipse of radii 0.90·W and 1.10·H.
    private func radiusFraction(_ x: Double, _ y: Double, width w: Double, height h: Double) -> Double {
        let dx = (x - 0.5 * w) / (0.90 * w), dy = (y - 0.55 * h) / (1.10 * h)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Whether the point is at least `inset` inside the rounded rectangle: clear of the edges and of the corners' anti-aliasing.
    private func inside(_ x: Double, _ y: Double, width w: Double, height h: Double, radius r: Double, inset: Double) -> Bool {
        let dx = max(r - x, 0, x - (w - r)), dy = max(r - y, 0, y - (h - r))
        return (dx * dx + dy * dy).squareRoot() <= r - inset
    }

    /// The contrast of `textPrimary` (or at 78 %, a glow label) over the pixel.
    private func contrast(over pixel: RGBA, label: Bool) -> Double {
        Tokens.ratio(with(ink, alpha: label ? 0.78 : 1), on: opaque(pixel))
    }

    /// Spec 16. The core is where text sits. Floors: the spec table's worst core pixels are 7.55 / 5.33 (recovery), and its
    /// test asks for 7.0 and 5.0, a margin for the 8-bit pixels.
    @Test("Spec 16: in the core (t ≤ 0.60) textPrimary reaches 7.0 and the 78 % label 5.0, for all three metric colours",
          arguments: Metric.allCases)
    func coreContrast(_ metric: Metric) throws {
        let tile = try #require(glow(metric.colour, width: 169, height: 124))
        let w = 169.0, h = 124.0
        var (worstPrimary, worstLabel, samples) = (Double.infinity, Double.infinity, 0)
        for iy in stride(from: 0, to: Int(h) * 2, by: 4) {
            for ix in stride(from: 0, to: Int(w) * 2, by: 4) {
                let x = (Double(ix) + 0.5) / 2, y = (Double(iy) + 0.5) / 2
                guard radiusFraction(x, y, width: w, height: h) <= 0.60,
                      inside(x, y, width: w, height: h, radius: tile.radius, inset: 2) else { continue }
                let p = tile.at(x, y)
                worstPrimary = min(worstPrimary, contrast(over: p, label: false))
                worstLabel = min(worstLabel, contrast(over: p, label: true))
                samples += 1
            }
        }
        #expect(samples > 1000, "sampled \(samples) pixels")
        #expect(worstPrimary >= 7.0, "textPrimary, worst core pixel: \(worstPrimary)")
        #expect(worstLabel >= 5.0, "78 % label, worst core pixel: \(worstLabel)")
    }

    struct PaddedCase: Sendable, CustomTestStringConvertible {
        let width: CGFloat, height: CGFloat
        var testDescription: String { "\(Int(width)) × \(Int(height))" }
    }

    /// Spec 17. The rect inside the 14/16 padding is where content lives. Floor 4.5 for both (the table's minimum is 4.53,
    /// recovery at 350 × 176: asserted as a floor, not as the table's value).
    @Test("Spec 17: over the padded content rect the worst pixel reaches 4.5:1 for textPrimary and the 78 % label",
          arguments: Metric.allCases, [PaddedCase(width: 169, height: 124), PaddedCase(width: 350, height: 120),
                                       PaddedCase(width: 350, height: 168), PaddedCase(width: 350, height: 176)])
    func paddedRectContrast(_ metric: Metric, _ size: PaddedCase) throws {
        let tile = try #require(glow(metric.colour, width: size.width, height: size.height))
        // The padding is 14 above and below, 16 at the sides (written here, not read from `GlowTileSpec.padding`).
        let (left, top) = (16.0, 14.0)
        let (right, bottom) = (Double(size.width) - 16, Double(size.height) - 14)
        // Every second pixel, and the last row and column: the worst pixel is at a corner of the rect.
        func positions(_ from: Double, _ to: Double) -> [Double] {
            var out = stride(from: from, to: to, by: 1.0).map { $0 + 0.25 }
            out.append(to - 0.25)
            return out
        }
        var (worstPrimary, worstLabel) = (Double.infinity, Double.infinity)
        for y in positions(top, bottom) {
            for x in positions(left, right) {
                let p = tile.at(x, y)
                worstPrimary = min(worstPrimary, contrast(over: p, label: false))
                worstLabel = min(worstLabel, contrast(over: p, label: true))
            }
        }
        #expect(worstPrimary >= 4.5, "textPrimary, worst pixel of the padded rect: \(worstPrimary)")
        #expect(worstLabel >= 4.5, "78 % label, worst pixel of the padded rect: \(worstLabel)")
    }

    /// Spec 18, with the implementer's correction: the sample is at the ellipse centre (0.5·W, 0.55·H), where the overlay
    /// is 0.97; at the geometric centre it is 2.1/255 away from the formula, over the ±2 tolerance.
    @Test("Spec 18: the ellipse centre is background·0.97 + metric·0.03 (±2/255), the edge is lighter, nothing beats the metric",
          arguments: Metric.allCases)
    func gradientPixels(_ metric: Metric) throws {
        let (w, h) = (169.0, 124.0)
        let tile = try #require(glow(metric.colour, width: 169, height: 124))
        let m = Tokens.resolve(metric.colour)
        let expected = RGBA(r: screen.r * 0.97 + m.r * 0.03, g: screen.g * 0.97 + m.g * 0.03,
                            b: screen.b * 0.97 + m.b * 0.03, a: 1)
        let centre = tile.at(0.5 * w, 0.55 * h)
        #expect(near(centre, expected, 2), "ellipse centre \(describe(centre)), expected \(describe(expected))")

        // 1 pt inside the left edge, at mid height: lighter than the centre, darker than the pure metric colour.
        let edge = tile.at(1.25, h / 2)
        let lum = Tokens.luminance
        #expect(lum(edge) > lum(centre), "edge \(describe(edge)) is lighter than the centre \(describe(centre))")
        #expect(lum(edge) < lum(m), "edge \(describe(edge)) is darker than the metric \(describe(m))")

        // The overlay only darkens: no opaque interior pixel is brighter than the metric colour (1/255 of rounding).
        var brightest = 0.0
        for iy in stride(from: 0, to: Int(h) * 2, by: 2) {
            for ix in stride(from: 0, to: Int(w) * 2, by: 2) {
                let x = (Double(ix) + 0.5) / 2, y = (Double(iy) + 0.5) / 2
                guard inside(x, y, width: w, height: h, radius: tile.radius, inset: 2) else { continue }
                let p = tile.at(x, y)
                brightest = max(brightest, p.r - m.r, p.g - m.g, p.b - m.b)
            }
        }
        #expect(brightest <= 1.0 / 255 + 1e-9, "a pixel is \(brightest * 255)/255 brighter than the metric colour")
    }

    @Test("The overlay is lighter the farther from the ellipse centre, along the horizontal")
    func gradientRisesTowardTheEdge() throws {
        let (w, h) = (169.0, 124.0)
        let tile = try #require(glow(Theme.recovery, width: 169, height: 124))
        let lum = Tokens.luminance
        // x = 0.5·W − t·0.9·W for t = 0, 0.2, 0.4, 0.5: the last is 1.25 pt from the left edge.
        let values = [0.0, 0.2, 0.4, 0.5].map { lum(tile.at(max(0.5 * w - $0 * 0.9 * w, 1.25), 0.55 * h)) }
        for (a, b) in zip(values, values.dropFirst()) { #expect(a < b, "luminance should rise toward the edge: \(values)") }
    }

    /// Spec 19. Reduce Transparency: flat `surface` with a 2 pt border in the metric colour, inside the shape.
    @Test("Spec 19: flat — the interior is surface, the 2 pt border is the metric colour, nothing is drawn outside",
          arguments: Metric.allCases)
    func reduceTransparency(_ metric: Metric) throws {
        let (w, h) = (169.0, 124.0)
        let tile = try #require(glow(metric.colour, width: 169, height: 124, flat: true))
        let m = Tokens.resolve(metric.colour)

        var interior = 0
        for iy in stride(from: 0, to: Int(h) * 2, by: 4) {
            for ix in stride(from: 0, to: Int(w) * 2, by: 4) {
                let x = (Double(ix) + 0.5) / 2, y = (Double(iy) + 0.5) / 2
                guard inside(x, y, width: w, height: h, radius: tile.radius, inset: 3) else { continue }
                let p = tile.at(x, y)
                interior += 1
                #expect(near(p, surface, 1), "interior (\(x), \(y)): \(describe(p)), expected surface \(describe(surface))")
            }
        }
        #expect(interior > 1000)
        #expect(near(tile.at(0.5 * w, 0.5 * h), surface, 1), "the centre is surface")

        // Mid-sides, 1 pt inside the edge (the middle of the 2 pt border): the metric colour; 3 pt inside: surface.
        let onBorder = [(1.25, h / 2), (w - 1.25, h / 2), (w / 2, 1.25), (w / 2, h - 1.25)]
        for (x, y) in onBorder { #expect(near(tile.at(x, y), m, 2), "border (\(x), \(y)): \(describe(tile.at(x, y)))") }
        let beyond = [(3.25, h / 2), (w - 3.25, h / 2), (w / 2, 3.25), (w / 2, h - 3.25)]
        for (x, y) in beyond { #expect(near(tile.at(x, y), surface, 1), "inside the border (\(x), \(y))") }

        // No shadow, no halo: outside the shape the image is transparent, and the rounded corners are cut.
        for (x, y) in [(-1.0, h / 2), (-6.0, h / 2), (w + 1, h / 2), (w + 6, h / 2), (w / 2, -1.0), (w / 2, h + 6),
                       (0.3, 0.3), (w - 0.3, 0.3), (0.3, h - 0.3), (w - 0.3, h - 0.3)] {
            #expect(tile.at(x, y).a == 0, "(\(x), \(y)) is outside the shape but drawn: \(describe(tile.at(x, y)))")
        }
    }

    @Test("Spec 19: without Reduce Transparency the 1 pt pixel is the glowing metric colour, not surface",
          arguments: Metric.allCases)
    func transparencyOnIsNotFlat(_ metric: Metric) throws {
        let (w, h) = (169.0, 124.0)
        let tile = try #require(glow(metric.colour, width: 169, height: 124, flat: false))
        for (x, y) in [(1.25, h / 2), (w / 2, 1.25)] {
            #expect(!near(tile.at(x, y), surface, 6), "(\(x), \(y)) is \(describe(tile.at(x, y)))")
        }
        for (x, y) in [(-1.0, h / 2), (w + 6, h / 2), (w / 2, -4.0), (0.3, 0.3)] {
            #expect(tile.at(x, y).a == 0, "no shadow at (\(x), \(y))")
        }
    }

    @Test("The hero radius cuts a larger corner than the tile radius")
    func heroCornerIsLarger() throws {
        let tile = try #require(glow(Theme.metricSleep, width: 169, height: 172, radius: .tile))
        let hero = try #require(glow(Theme.metricSleep, width: 169, height: 172, radius: .hero))
        // The point (x, x) is inside a corner of radius r when (r − x)·√2 < r. At x = 7.75 (the middle of a pixel):
        // r = 24 gives 23.0 (inside), r = 28 gives 28.6 (outside).
        #expect(tile.at(7.75, 7.75).a == 1, "inside the 24 pt corner")
        #expect(hero.at(7.75, 7.75).a == 0, "outside the 28 pt corner")
    }

    // MARK: 20–21. DotNumeral

    /// Every dot centre of `text`, as (centre, lit) pairs, from the table itself.
    private func dotCentres(_ text: String, gap: CGFloat) throws -> (lit: [CGPoint], unlit: [CGPoint]) {
        let cells = try #require(DotNumeral.cells(text, glyphGap: gap))
        return (cells.lit, cells.unlit)
    }

    @Test("Spec 20: \"8\" — lit dots are textPrimary, unlit ones 10 % over the screen, the gaps are the screen")
    func dotNumeralPixels() throws {
        let view = DotNumeral("8", accessibilityLabel: Text(verbatim: "8")).background(Theme.background)
        let shot = try #require(render(view))
        #expect(shot.size == CGSize(width: 33, height: 47))
        let (lit, unlit) = try dotCentres("8", gap: 8)
        #expect(lit.count == 17 && unlit.count == 18)
        let off = inkOverScreen(0.10)
        for c in lit { #expect(near(shot.at(c.x, c.y), ink), "lit (\(c.x), \(c.y)): \(describe(shot.at(c.x, c.y)))") }
        for c in unlit { #expect(near(shot.at(c.x, c.y), off), "unlit (\(c.x), \(c.y)): \(describe(shot.at(c.x, c.y)))") }
        // Between dots: 2 pt gaps, horizontally, vertically and on the diagonal.
        for r in 0..<7 {
            for c in 0..<5 {
                let (cx, cy) = (2.5 + Double(c) * 7, 2.5 + Double(r) * 7)
                var gaps = [(cx + 3.5, cy), (cx, cy + 3.5), (cx + 3.5, cy + 3.5)]
                gaps = gaps.filter { $0.0 < 33 && $0.1 < 47 }
                for (x, y) in gaps { #expect(near(shot.at(x, y), screen), "gap (\(x), \(y)): \(describe(shot.at(x, y)))") }
            }
        }
    }

    @Test("Spec 20: pending draws every cell at 10 % and nothing lit")
    func pendingPixels() throws {
        let view = DotNumeral(nil, accessibilityLabel: Text(verbatim: "no value")).background(Theme.background)
        let shot = try #require(render(view))
        #expect(shot.size == CGSize(width: 74, height: 47))
        let cells = try #require(DotNumeral.cells(nil, glyphGap: 8))
        let off = inkOverScreen(0.10)
        for c in cells.unlit { #expect(near(shot.at(c.x, c.y), off), "(\(c.x), \(c.y)): \(describe(shot.at(c.x, c.y)))") }
    }

    /// P2-D10. The pending Sleep numeral: the cells of "0:00", every one at 10 %, the colon column among them.
    @Test("A pending \"0:00\" is 125 × 47 with every cell unlit, the colon column included, and no dot lit anywhere")
    func pendingTemplatePixels() throws {
        let view = DotNumeral(nil, glyphGap: 7, placeholder: "0:00", accessibilityLabel: Text(verbatim: "no value"))
            .background(Theme.background)
        let shot = try #require(render(view))
        #expect(shot.size == CGSize(width: 125, height: 47))
        let cells = try #require(DotNumeral.cells(nil, placeholder: "0:00", glyphGap: 7))
        #expect(cells.lit.isEmpty && cells.unlit.count == 35 * 3 + 7)
        let off = inkOverScreen(0.10)
        for c in cells.unlit { #expect(near(shot.at(c.x, c.y), off), "(\(c.x), \(c.y)): \(describe(shot.at(c.x, c.y)))") }
        // The colon is the second glyph: x₀ = 33 + 7 = 40, so its one column is centred at x 42.5, on all seven rows.
        for row in 0..<7 {
            let y = Double(row) * 7 + 2.5
            #expect(near(shot.at(42.5, y), off), "colon cell, row \(row): \(describe(shot.at(42.5, y)))")
        }
        // Where a value lights its colon (rows 3 and 5), the pending one is as dim as every other cell.
        for y in [16.5, 30.5] { #expect(!near(shot.at(42.5, y), ink, 8), "the colon's dots are lit at y \(y)") }
        // Nothing brighter than the unlit dots anywhere in the image.
        var brightest = 0.0
        for iy in 0..<shot.height { for ix in 0..<shot.width { brightest = max(brightest, shot.px(ix, iy).r) } }
        #expect(brightest <= off.r + 2.0 / 255, "the brightest pixel is \(brightest), an unlit dot is \(off.r)")
    }

    @Test("A pending \"0:00\" and \"7:48\" are the same size, and the value only lights dots the template left unlit")
    func pendingAndValueShareTheirCells() throws {
        let pending = try #require(DotNumeral.cells(nil, placeholder: "0:00", glyphGap: 7))
        let value = try #require(DotNumeral.cells("7:48", glyphGap: 7))
        #expect(pending.size == value.size)
        // Every dot of the value, lit or not, is a cell of the template, and the other way round.
        let valueCells = value.lit + value.unlit
        #expect(valueCells.count == pending.unlit.count)
        for c in pending.unlit { #expect(valueCells.contains(c), "(\(c.x), \(c.y)) is not a cell of 7:48") }
    }

    @Test("Pending in the Light fallback (AX3, \"0:00\") draws the dashes: no grid, and ink on the screen colour")
    func pendingLightIsDrawn() throws {
        let view = DotNumeral(nil, glyphGap: 7, placeholder: "0:00", accessibilityLabel: Text(verbatim: "no value"))
            .background(Theme.background)
            .environment(\.dynamicTypeSize, .accessibility3)
        let shot = try #require(render(view))
        #expect(shot.size != CGSize(width: 125, height: 47), "\(shot.size)")
        #expect(shot.bounds(xs: 0...Double(shot.size.width), ys: 0...Double(shot.size.height)) { self.distance($0, self.screen) > 0.1 } != nil)
    }

    @Test("Spec 20: from AX1 the dot grid is gone — the Light text is drawn instead", arguments: [
        DynamicTypeSize.accessibility1, .accessibility3,
    ])
    func lightFallbackIsDrawn(_ size: DynamicTypeSize) throws {
        let view = DotNumeral("8", accessibilityLabel: Text(verbatim: "8")).background(Theme.background)
            .environment(\.dynamicTypeSize, size)
        let shot = try #require(render(view))
        #expect(shot.size != CGSize(width: 33, height: 47), "the image is not the grid's size: \(shot.size)")
        // The grid's signature is its 10 % unlit dots; Light text has none of that colour at a dot centre.
        let (_, unlit) = try dotCentres("8", gap: 8)
        let off = inkOverScreen(0.10)
        let matching = unlit.filter { near(shot.at($0.x, $0.y), off, 2) }.count
        #expect(matching < unlit.count / 2, "\(matching) of \(unlit.count) unlit centres still read as dots")
        // Text is drawn: some pixel is bright ink.
        #expect(shot.bounds(xs: 0...Double(shot.size.width), ys: 0...Double(shot.size.height)) { near($0, ink, 8) } != nil)
    }

    @Test("Spec 20: .light draws text even at the default size")
    func lightStyleIsText() throws {
        let view = DotNumeral("84", style: .light, accessibilityLabel: Text(verbatim: "84")).background(Theme.background)
        let shot = try #require(render(view))
        #expect(shot.size != CGSize(width: 74, height: 47), "\(shot.size)")
        #expect(shot.bounds(xs: 0...Double(shot.size.width), ys: 0...Double(shot.size.height)) { near($0, ink, 8) } != nil)
    }

    @Test("Spec 21: \"7:48\" at gap 7 is 125 × 47 and its lit dots touch both edges (±0.5 pt)")
    func timeFillsItsFrame() throws {
        let view = DotNumeral("7:48", glyphGap: 7, accessibilityLabel: Text(verbatim: "7:48"))
            .background(Theme.background)
        let shot = try #require(render(view))
        #expect(shot.size == CGSize(width: 125, height: 47))
        let lit = try #require(shot.bounds(xs: 0...125, ys: 0...47) { $0.r > 0.5 })   // lit 0.95; unlit 0.12; screen 0.04
        #expect(lit.minX <= 0.5, "leftmost lit dot at \(lit.minX)")
        #expect(lit.maxX >= 124.5, "rightmost lit dot at \(lit.maxX)")
        #expect(lit.minY <= 0.5 && lit.maxY >= 46.5, "the lit dots reach the top and bottom rows: \(lit)")
    }

    // MARK: 22. RulerScale

    private func ruler(value: Double?, zone: ClosedRange<Double>? = 67...100, range: ClosedRange<Double> = 0...100,
                       ticks: Int = RulerScale.Ticks.today, style: RulerScale.ZoneStyle = .standard,
                       size: RulerScale.Size = .regular, width: CGFloat = 300) -> some View {
        RulerScale(range: range, value: value, zone: zone, zoneStyle: style, tickCount: ticks, size: size,
                   accessibilityLabel: Text(verbatim: "Scale"), accessibilityValue: Text(verbatim: "value"), reduceMotion: true)
            .frame(width: width)
            .background(Theme.background)
    }

    @Test("Spec 9: the ruler renders 36 high (regular) and 32 (compact), as wide as it is given",
          arguments: [(RulerScale.Size.regular, 36.0), (RulerScale.Size.compact, 32.0)])
    func rulerHeight(_ size: RulerScale.Size, _ height: Double) throws {
        let shot = try #require(render(ruler(value: 50, size: size)))
        #expect(shot.size == CGSize(width: 300, height: height))
        let wide = try #require(render(ruler(value: 50, size: size, width: 500)))
        #expect(wide.size == CGSize(width: 500, height: height))
    }

    @Test("Spec 22: the Volt needle is at the value's x; without a value the pixel is not Volt")
    func needlePixel() throws {
        let withValue = try #require(render(ruler(value: 84)))
        let p = withValue.at(252, 20)
        #expect(near(p, volt), "pixel at the needle: \(describe(p)), expected \(describe(volt))")
        let without = try #require(render(ruler(value: nil)))
        #expect(!near(without.at(252, 20), volt, 8), "no value, no needle: \(describe(without.at(252, 20)))")
        // The needle follows the value: at 20 it is at 60, not at 252.
        let moved = try #require(render(ruler(value: 20)))
        #expect(near(moved.at(60, 20), volt) && !near(moved.at(252, 20), volt, 8))
    }

    @Test("The needle is clamped: a value beyond the range sits on the end", arguments: [(150.0, 300.0), (-20.0, 0.0)])
    func needleIsClamped(_ value: Double, _ x: Double) throws {
        let shot = try #require(render(ruler(value: value)))
        // The line is 1.5 wide, centred on the end: the half inside the image is the pixel next to the edge.
        let probe = x == 0 ? 0.4 : 299.6
        #expect(near(shot.at(probe, 20), volt), "pixel at \(probe): \(describe(shot.at(probe, 20)))")
    }

    /// The extent of the ink along the column through `x`, in points, over the tick row only (the needle is absent).
    private func tickHeight(_ shot: Shot, at x: Double) -> (minY: Double, height: Double)? {
        guard let box = shot.bounds(xs: x...x + 0.2, ys: 0...Double(shot.size.height), where: { distance($0, screen) > 0.1 }) else {
            return nil
        }
        return (Double(box.minY), Double(box.height))
    }

    @Test("Spec 22: a zone tick (index 50) is 14 pt tall, an outside tick (index 10) 8 pt, both centred in the 8…30 row")
    func tickHeights() throws {
        let shot = try #require(render(ruler(value: nil)))
        let zone = try #require(tickHeight(shot, at: 250))
        let outside = try #require(tickHeight(shot, at: 50))
        #expect(abs(zone.height - 14) <= 0.5, "zone tick \(zone.height) tall")
        #expect(abs(outside.height - 8) <= 0.5, "outside tick \(outside.height) tall")
        #expect(abs(zone.minY - 12) <= 0.5, "zone tick starts at \(zone.minY)")
        #expect(abs(outside.minY - 15) <= 0.5, "outside tick starts at \(outside.minY)")
        // Index 40 is the last outside tick, index 41 the first zone tick: 6.67-point steps.
        let c = RulerScale.tickCentres(count: 61, width: 300)
        let before = try #require(tickHeight(shot, at: Double(c[40])))
        let after = try #require(tickHeight(shot, at: Double(c[41])))
        #expect(abs(before.height - 8) <= 0.5 && abs(after.height - 14) <= 0.5,
                "the zone starts at tick 41: \(before.height) then \(after.height)")
    }

    @Test("Spec 22: the compact ruler's ticks are 7 and 12 tall, the needle line ends at y 24")
    func compactTicks() throws {
        // 43 ticks over 0…21; the zone 10…14 is ticks 20…28, centres at i·300/42.
        let c = RulerScale.tickCentres(count: 43, width: 300)
        let shot = try #require(render(ruler(value: nil, zone: 10...14, range: 0...21, ticks: 43, size: .compact)))
        let zone = try #require(tickHeight(shot, at: Double(c[24])))
        let outside = try #require(tickHeight(shot, at: Double(c[5])))
        #expect(abs(zone.height - 12) <= 0.5 && abs(outside.height - 7) <= 0.5, "\(zone.height), \(outside.height)")
        let needle = try #require(render(ruler(value: 12.6, zone: 10...14, range: 0...21, ticks: 43, size: .compact)))
        let x = 12.6 / 21 * 300
        let line = try #require(needle.bounds(xs: x...x + 0.2, ys: 9...32) { self.near($0, self.volt, 8) })
        #expect(abs(line.maxY - 24) <= 0.5, "the compact needle ends at \(line.maxY)")
        let regular = try #require(render(ruler(value: 84)))
        let regularLine = try #require(regular.bounds(xs: 252...252.2, ys: 9...36) { self.near($0, self.volt, 8) })
        #expect(abs(regularLine.maxY - 28) <= 0.5, "the regular needle ends at \(regularLine.maxY)")
    }

    @Test("The zone's tint and opacity: Sleep draws its ticks in the sleep colour at 85 %")
    func zoneTintAndOpacity() throws {
        let shot = try #require(render(ruler(value: nil, zone: 7.5...8.3, range: 0...10, ticks: 61, style: .sleep)))
        let c = RulerScale.tickCentres(count: 61, width: 300)
        let centre = shot.at(Double(c[47]), 19)
        let expected = Tokens.over(with(Tokens.resolve(Theme.metricSleep), alpha: 0.85), screen)
        #expect(near(centre, expected, 3), "zone tick \(describe(centre)), expected \(describe(expected))")
        // An outside tick is textPrimary at 22 %.
        let outside = shot.at(Double(c[10]), 19)
        #expect(near(outside, inkOverScreen(0.22), 3), "outside tick \(describe(outside))")
    }

    @Test("Without a zone every tick is an outside tick")
    func noZoneIsAllShort() throws {
        let shot = try #require(render(ruler(value: nil, zone: nil)))
        let c = RulerScale.tickCentres(count: 61, width: 300)
        for i in [0, 20, 41, 50, 60] where i > 0 && i < 60 {
            let t = try #require(tickHeight(shot, at: Double(c[i])))
            #expect(abs(t.height - 8) <= 0.5, "tick \(i) is \(t.height) tall")
        }
    }

    // MARK: Signal: Volt only in the needle and the today dot

    private func voltPixels(_ shot: Shot) -> (count: Int, box: CGRect?) {
        var count = 0
        let isVolt: (RGBA) -> Bool = { self.distance($0, self.volt) < 0.12 }
        for iy in 0..<shot.height {
            for ix in 0..<shot.width where isVolt(shot.px(ix, iy)) { count += 1 }
        }
        let box = shot.bounds(xs: 0...Double(shot.size.width), ys: 0...Double(shot.size.height), where: isVolt)
        return (count, box)
    }

    @Test("Signal: on the ruler, Volt is the needle and nothing else", arguments: [84.0, 20.0, 100.0])
    func voltIsOnlyTheNeedle(_ value: Double) throws {
        let shot = try #require(render(ruler(value: value)))
        let (count, box) = voltPixels(shot)
        let found = try #require(box, "no Volt pixel at all")
        let x = value / 100 * 300
        #expect(count > 0)
        // The triangle is 12 wide, apex y 8; the line runs to y 28. Nothing else is Volt.
        #expect(found.minX >= x - 6.5 && found.maxX <= x + 6.5, "Volt spans x \(found.minX)…\(found.maxX), the needle is at \(x)")
        #expect(found.minY >= -0.5 && found.maxY <= 28.5, "Volt spans y \(found.minY)…\(found.maxY)")
    }

    @Test("Signal: with no value, or any zone tint, the ruler has no Volt at all")
    func rulerWithoutNeedleHasNoVolt() throws {
        #expect(voltPixels(try #require(render(ruler(value: nil)))).count == 0)
        let strain = ruler(value: nil, zone: 10...14, range: 0...21, ticks: 64, style: .strain)
        #expect(voltPixels(try #require(render(strain))).count == 0)
        let sleep = ruler(value: nil, zone: 7.5...8.3, range: 0...10, ticks: 61, style: .sleep)
        #expect(voltPixels(try #require(render(sleep))).count == 0)
    }

    // MARK: DotRow

    private func dotRow(_ marks: [DotRow.Mark]) -> some View {
        DotRow(marks, accessibilityLabel: Text(verbatim: "summary")).background(Theme.background)
    }

    @Test("A dot row is 36 × 6 for four dots; full is textPrimary, missed a ring, today Volt")
    func dotRowPixels() throws {
        let shot = try #require(render(dotRow([.full, .missed, .today, .full])))
        #expect(shot.size == CGSize(width: 36, height: 6))
        func centre(_ i: Int) -> (Double, Double) { (Double(i) * 10 + 3, 3) }   // dot i spans 10i … 10i + 6
        // full: filled ink. missed: the middle is the screen (no fill) and the ring is ink at 50 %. today: Volt.
        #expect(near(shot.at(centre(0).0, 3), ink), "full: \(describe(shot.at(3, 3)))")
        #expect(near(shot.at(centre(1).0, 3), screen), "missed has no fill: \(describe(shot.at(13, 3)))")
        #expect(near(shot.at(10.5, 3), inkOverScreen(0.5), 3), "missed ring: \(describe(shot.at(10.5, 3)))")
        #expect(near(shot.at(centre(2).0, 3), volt), "today: \(describe(shot.at(23, 3)))")
        #expect(near(shot.at(centre(3).0, 3), ink))
        // The gaps between dots (4 pt) are the screen.
        for x in [8.0, 18.0, 28.0] { #expect(near(shot.at(x, 3), screen), "gap at \(x): \(describe(shot.at(x, 3)))") }
    }

    @Test("Signal: Volt in a dot row is the today dot alone")
    func voltIsOnlyToday() throws {
        let some = try #require(render(dotRow([.full, .missed, .full, .today])))
        let (count, box) = voltPixels(some)
        let found = try #require(box)
        #expect(count > 0)
        #expect(found.minX >= 30 - 0.5 && found.maxX <= 36.5 && found.minY >= -0.5 && found.maxY <= 6.5, "Volt at \(found)")
        let none = try #require(render(dotRow([.full, .missed, .full, .missed, .full])))
        #expect(voltPixels(none).count == 0)
    }

    @Test("An empty dot row draws nothing and has no size")
    func emptyDotRow() {
        let renderer = ImageRenderer(content: DotRow([], accessibilityLabel: Text(verbatim: "none")))
        renderer.scale = 2
        #expect(renderer.uiImage == nil || renderer.uiImage?.size == .zero)
    }

    // MARK: TickRow

    private func tickRow(minutes: Double? = 24, scaleMax: Double = 60, label: String = "Zone 3") -> some View {
        TickRow(label: Text(verbatim: label), minutes: minutes, scaleMax: scaleMax, value: Text(verbatim: "24"),
                accessibilityLabel: Text(verbatim: "Zone 3, 24 minutes"))
    }

    @Test("A tick row at its natural width is 315 × 12; 12 of 30 ticks are lit, the rest 12 %, 6 pt apart")
    func tickRowPixels() throws {
        let shot = try #require(render(tickRow().frame(width: 315).background(Theme.background)))
        #expect(shot.size == CGSize(width: 315, height: 12))
        // Ticks start after the 74 pt label and the 12 pt gap: tick i is at 86 + 6i, 3 wide.
        let unlit = inkOverScreen(0.12)
        for i in 0..<30 {
            let x = 86 + Double(i) * 6 + 1.5
            let p = shot.at(x, 6)
            #expect(near(p, i < 12 ? ink : unlit), "tick \(i): \(describe(p))")
            #expect(near(shot.at(x + 3, 6), screen), "the gap after tick \(i): \(describe(shot.at(x + 3, 6)))")
        }
    }

    @Test("Nothing is lit without minutes, or with a zero scale")
    func tickRowUnlit() throws {
        for (minutes, scaleMax) in [(nil as Double?, 60.0), (10, 0), (0, 60)] {
            let shot = try #require(render(tickRow(minutes: minutes, scaleMax: scaleMax).frame(width: 315).background(Theme.background)))
            let unlit = inkOverScreen(0.12)
            for i in [0, 14, 29] { #expect(near(shot.at(86 + Double(i) * 6 + 1.5, 6), unlit), "\(String(describing: minutes)) / \(scaleMax), tick \(i)") }
        }
    }

    @Test("A full row lights all 30 ticks and none of them is Volt")
    func tickRowFull() throws {
        let shot = try #require(render(tickRow(minutes: 60).frame(width: 315).background(Theme.background)))
        for i in [0, 15, 29] { #expect(near(shot.at(86 + Double(i) * 6 + 1.5, 6), ink)) }
        #expect(voltPixels(shot).count == 0)
    }

    @Test("The label is a 74 pt column on the left, the value is pushed to the trailing edge")
    func tickRowColumns() throws {
        let shot = try #require(render(tickRow().frame(width: 315).background(Theme.background)))
        let height = Double(shot.size.height)
        let label = try #require(shot.bounds(xs: 0...74, ys: 0...height, where: isInk), "label ink")
        #expect(label.minX <= 2 && label.maxX < 74, "label ink x \(label.minX)…\(label.maxX)")
        let value = try #require(shot.bounds(xs: 275...315, ys: 0...height, where: isInk), "value ink")
        #expect(value.maxX >= 312, "value ink ends at \(value.maxX), trailing is 315")
        // Between the label column and the first tick (74…86), and between the last tick and the value (263…275): empty.
        #expect(shot.bounds(xs: 74...85.9, ys: 0...height, where: isInk) == nil)
        #expect(shot.bounds(xs: 263.5...274.5, ys: 0...height, where: isInk) == nil)
        // The ticks run from 86 to 263 (177 wide).
        let ticks = try #require(shot.bounds(xs: 80...270, ys: 0...height, where: isInk))
        #expect(abs(ticks.minX - 86) <= 0.5 && abs(ticks.maxX - 263) <= 0.5, "ticks x \(ticks.minX)…\(ticks.maxX)")
    }

    /// Decided by the implementation: `ViewThatFits` takes the one-line row only when its ideal width fits. At the default
    /// size the row needs 315; at xxxLarge it needs 372 (design.md, the implementer's note), so it stacks in 350.
    struct StackCase: Sendable, CustomTestStringConvertible {
        let typeSize: DynamicTypeSize
        let width: CGFloat
        let stacked: Bool
        var testDescription: String { "\(typeSize) in \(Int(width)) pt -> \(stacked ? "stacked" : "one line")" }
    }

    @Test("The row stacks when the one-line row needs more than the container", arguments: [
        StackCase(typeSize: .large, width: 315, stacked: false), StackCase(typeSize: .large, width: 350, stacked: false),
        StackCase(typeSize: .large, width: 314, stacked: true),
        StackCase(typeSize: .xLarge, width: 350, stacked: false), StackCase(typeSize: .xxxLarge, width: 350, stacked: true),
        StackCase(typeSize: .accessibility1, width: 600, stacked: true),
        StackCase(typeSize: .accessibility3, width: 350, stacked: true),
    ])
    func stacking(_ c: StackCase) throws {
        let view = tickRow().environment(\.dynamicTypeSize, c.typeSize).frame(width: c.width).background(Theme.background)
        let shot = try #require(render(view))
        // One line is the ticks' 12 pt (scaled a little with the text); a stacked row adds a text line and 4 pt.
        let stackedHeight = shot.size.height >= 12 + 4 + 10
        #expect(stackedHeight == c.stacked, "height \(shot.size.height)")
        // Either way the ticks keep their fixed 177 width.
        let ticks = shot.bounds(xs: 0...Double(c.width), ys: Double(shot.size.height) - 12...Double(shot.size.height)) {
            self.near($0, self.ink, 2)
        }
        #expect(ticks != nil)
    }

    /// P2-D12 / review row 1. A long label stacks the row instead of truncating (its ideal width decides), and a short one keeps
    /// the column at exactly 74. The ticks are the first full-ink pixels after the label column, so the label's own (62 %)
    /// pixels never count: they cannot reach `textPrimary`.
    @Test("A label wider than its 74 pt column stacks the row: taller than 12, the ticks below the label, the label not cut")
    func longLabelStacks() throws {
        let view = tickRow(label: "Zone 5 · maximum effort").frame(width: 350).background(Theme.background)
        let shot = try #require(render(view))
        let height = Double(shot.size.height)
        #expect(height > 12, "the row is \(height) high")
        #expect(height >= 12 + 4 + 10, "a text line and the 4 pt gap sit above the ticks: \(height)")
        // Ticks: the last 12 pt, from the leading edge, 177 wide.
        let ticks = try #require(shot.bounds(xs: 0...350, ys: height - 12...height) { self.near($0, self.ink, 2) }, "the ticks")
        #expect(abs(ticks.minY - (height - 12)) <= 0.5, "ticks start at \(ticks.minY)")
        #expect(abs(ticks.minX - 0) <= 0.5 && ticks.width <= 177 + 0.5, "ticks \(ticks)")
        // The label is above them, on its own line, wider than the 74 pt column (not truncated to it).
        let label = try #require(shot.bounds(xs: 0...350, ys: 0...(height - 12 - 1)) { self.distance($0, self.screen) > 0.2 }, "label ink")
        #expect(label.maxY <= ticks.minY, "the label ends at \(label.maxY), the ticks start at \(ticks.minY)")
        #expect(label.minX <= 2 && label.maxX > 74 + 20, "the label spans \(label.minX)…\(label.maxX), not cut to 74")
        // The value is on that line too, at the trailing edge.
        let value = try #require(shot.bounds(xs: 300...350, ys: 0...(height - 12 - 1)) { self.distance($0, self.screen) > 0.2 }, "value ink")
        #expect(value.maxX >= 347, "value ends at \(value.maxX)")
    }

    /// Re-review row 17. A mid-length label (wider than 74, but the row still fits) stays on one line and widens its own
    /// column: the first tick starts 12 pt after the label's full width, so no label pixel sits over the ticks. Before the
    /// fix the flexible value column was sized first and the label overflowed its 74–80 pt column into the ticks.
    @Test("A mid-length label widens its column on one line: the ticks start 12 pt after the whole label")
    func midLengthLabelPushesTheTicks() throws {
        let label = "Zone 2 · Endurance"
        let ideal = try #require(render(Text(verbatim: label).font(.ryft(.caption)).fixedSize())).size.width
        // The case only means something while the label is wider than the column and the row (label + 241) fits 361.
        #expect(ideal > 80 && ideal < 118, "the label is \(ideal) pt wide: pick another one")
        let shot = try #require(render(tickRow(label: label).frame(width: 361).background(Theme.background)))
        #expect(shot.size == CGSize(width: 361, height: 12), "one line: \(shot.size)")
        let ticks = try #require(shot.bounds(xs: 0...300, ys: 0...12) { self.near($0, self.ink, 2) }, "the lit ticks")
        #expect(abs(ticks.minX - (ideal + 12)) <= 1, "ticks start at \(ticks.minX), the label ends at \(ideal)")
    }

    @Test("A short label (\"Zone 3\") stays on one line in 350 pt: 12 high, the first tick at x 86")
    func shortLabelStaysOnOneLine() throws {
        let shot = try #require(render(tickRow().frame(width: 350).background(Theme.background)))
        #expect(shot.size == CGSize(width: 350, height: 12))
        // The column is exactly 74: the first tick spans 86…89, with the screen colour just before it.
        #expect(near(shot.at(87.5, 6), ink), "first tick: \(describe(shot.at(87.5, 6)))")
        #expect(near(shot.at(85.5, 6), screen), "before the first tick: \(describe(shot.at(85.5, 6)))")
        let ticks = try #require(shot.bounds(xs: 80...300, ys: 0...12) { self.near($0, self.ink, 2) || self.near($0, self.inkOverScreen(0.12), 2) })
        #expect(abs(ticks.minX - 86) <= 0.5, "ticks start at \(ticks.minX)")
    }

    // MARK: Compact ruler labels in a glow tile (P2-D12, review row 1)

    /// A strain tile as Today draws it, `width` × 124, with the compact ruler at the bottom of the padded area. `ruler: false`
    /// is the same tile empty: the background under the labels, since the glow depends only on the tile's size.
    private func labelTile(_ metric: Color, width: CGFloat, ruler: Bool) -> some View {
        GlowTile(metric) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                if ruler {
                    RulerScale(range: 0...21, value: 12.4, zone: 10...14, tickCount: RulerScale.Ticks.strainCompact,
                               labels: ["0", "21"], size: .compact, accessibilityLabel: Text(verbatim: "Strain scale"),
                               accessibilityValue: Text(verbatim: "12.4"), reduceMotion: true)
                }
            }
        }
        .frame(width: width, height: 124)
    }

    private struct EdgeLabel {
        /// The label's box in points and the lightest background pixel under it.
        let box: CGRect
        let lightestBackground: RGBA
        /// The label's opacity as drawn: the strongest `(drawn − background) / (ink − background)` in the box, which a fully
        /// covered pixel of a stem gives exactly.
        let opacity: Double
    }

    /// The box of the pixels in `xs` × `ys` that the labels changed, read against the empty tile.
    private func edgeLabel(_ full: Shot, _ empty: Shot, xs: ClosedRange<Double>, ys: ClosedRange<Double>) -> EdgeLabel? {
        var (minX, minY, maxX, maxY) = (Int.max, Int.max, Int.min, Int.min)
        for iy in 0..<full.height {
            let y = (Double(iy) + 0.5) / Double(full.scale)
            guard ys.contains(y) else { continue }
            for ix in 0..<full.width {
                let x = (Double(ix) + 0.5) / Double(full.scale)
                guard xs.contains(x), distance(full.px(ix, iy), empty.px(ix, iy)) > 0.02 else { continue }
                minX = min(minX, ix); maxX = max(maxX, ix); minY = min(minY, iy); maxY = max(maxY, iy)
            }
        }
        guard minX <= maxX else { return nil }
        var (lightest, lightestLuminance, opacity) = (empty.px(minX, minY), -1.0, 0.0)
        let channels: [(RGBA) -> Double] = [{ $0.r }, { $0.g }, { $0.b }]
        for iy in minY...maxY {
            for ix in minX...maxX {
                let bg = empty.px(ix, iy), drawn = full.px(ix, iy)
                if Tokens.luminance(bg) > lightestLuminance { (lightest, lightestLuminance) = (bg, Tokens.luminance(bg)) }
                // The channel where the ink is farthest from the background reads the opacity best.
                guard let read = channels.max(by: { $0(ink) - $0(bg) < $1(ink) - $1(bg) }), read(ink) - read(bg) > 0.3 else { continue }
                opacity = max(opacity, (read(drawn) - read(bg)) / (read(ink) - read(bg)))
            }
        }
        let scale = Double(full.scale)
        return EdgeLabel(box: CGRect(x: Double(minX) / scale, y: Double(minY) / scale,
                                     width: Double(maxX - minX + 1) / scale, height: Double(maxY - minY + 1) / scale),
                         lightestBackground: lightest, opacity: opacity)
    }

    /// The label colour is read from the drawn pixels, not from the component's constants: a regression to `textTertiary`
    /// (48 %) changes the drawn opacity, and the contrast follows. The expected numbers are written here: 4.5 (WCAG AA), the
    /// opacity 0.78 (± 0.04 for 8-bit pixels and a stem that may not cover a pixel fully).
    @Test("The compact ruler's edge labels read 4.5:1 or more against the lightest pixel under them, inside a glow tile at L",
          arguments: [Metric.recovery, .strain], [CGFloat(169), CGFloat(350)])
    func compactEdgeLabelContrast(_ metric: Metric, _ width: CGFloat) throws {
        let full = try #require(render(labelTile(metric.colour, width: width, ruler: true), scale: 4))
        let empty = try #require(render(labelTile(metric.colour, width: width, ruler: false), scale: 4))
        #expect(full.width == empty.width && full.height == empty.height)
        // The labels are the bottom line of the padded area (y up to 110); the ticks end 6 pt above them.
        let ys = 94.0...111.0
        let left = try #require(edgeLabel(full, empty, xs: 0...Double(width) / 2, ys: ys), "the \"0\" label")
        let right = try #require(edgeLabel(full, empty, xs: Double(width) / 2...Double(width), ys: ys), "the \"21\" label")
        // Each box is a label: a few points wide, a text line high, at the padding's edge.
        #expect(left.box.minX >= 15 && left.box.minX < 20 && left.box.width > 3 && left.box.width < 14, "\"0\" at \(left.box)")
        #expect(right.box.maxX <= Double(width) - 14 && right.box.maxX > Double(width) - 20 && right.box.width > 6 && right.box.width < 24,
                "\"21\" at \(right.box)")
        for label in [left, right] { #expect(label.box.height > 5 && label.box.height < 14 && label.box.maxY <= 111, "\(label.box)") }
        for (name, label) in [("0", left), ("21", right)] {
            #expect(abs(label.opacity - 0.78) <= 0.04, "\"\(name)\" is drawn at \(label.opacity), not 0.78")
            let contrast = Tokens.ratio(with(ink, alpha: label.opacity), on: label.lightestBackground)
            #expect(contrast >= 4.5, "\"\(name)\" on \(metric) at \(Int(width)) pt: \(contrast):1")
        }
    }

    // MARK: Ruler label gap (P2-D13, review row 10)

    private let todayLabels = ["0", "low", "moderate", "high", "100"]

    /// Today's ruler at AX3 in `width`, and the height of the label ink under the 36 pt graphic: one line, or the joined line wrapped.
    private func todayLabelInk(width: CGFloat) throws -> CGRect {
        let view = RulerScale(range: 0...100, value: nil, zone: 67...100, tickCount: RulerScale.Ticks.today, labels: todayLabels,
                              accessibilityLabel: Text(verbatim: "Scale"), accessibilityValue: Text(verbatim: "value"), reduceMotion: true)
            .frame(width: width).environment(\.dynamicTypeSize, .accessibility3).background(Theme.background)
        let shot = try #require(render(view))
        return try #require(shot.bounds(xs: 0...Double(width), ys: 36...Double(shot.size.height)) { self.distance($0, self.screen) > 0.1 },
                            "label ink at \(width) pt")
    }

    /// The five labels side by side at AX3 take `natural` points; with the 16 pt minimum between them, four gaps, the one-line row
    /// needs `natural + 64`. Under that the row falls back to the joined " · " line (407 pt at AX3, so it wraps in any of the widths
    /// here); at or over it, the labels sit on one line. The natural width is measured, so the bracket holds when the font moves.
    @Test("Today's five labels at AX3: one line from natural + 4 × 16 pt, the joined, wrapping line just below")
    func labelsFallBackWhenTheGapsGetUnderSixteen() throws {
        let natural = HStack(spacing: 0) {
            ForEach(Array(todayLabels.enumerated()), id: \.offset) { Text(verbatim: $1).lineLimit(1).fixedSize() }
        }
        .font(.ryft(.axis)).fixedSize().environment(\.dynamicTypeSize, .accessibility3)
        let t = Double(try #require(render(natural)).size.width)
        let oneLine = try todayLabelInk(width: CGFloat(t + 4 * 16 + 6))
        let fallback = try todayLabelInk(width: CGFloat(t + 4 * 16 - 6))
        // One line of AX3 11 pt text is about 29 pt of ink (a digit's box, not a line's); a wrapped joined line is two lines or more.
        #expect(oneLine.height < 40, "at natural + 70: \(oneLine)")
        #expect(fallback.height > 40, "at natural + 58 (gaps of 13 pt) the labels fall back and wrap: \(fallback)")
        // On one line the last label ends at the trailing edge; the joined line is leading-aligned and ragged.
        #expect(oneLine.maxX >= t + 4 * 16 + 6 - 4, "the last label is at the trailing edge: \(oneLine)")
    }

    /// The case review row 10 describes: Today at AX3 in a 350 pt column. With the old 8 pt gap (340 pt needed) the labels sat
    /// on one line and read as one run; with 16 (372 pt) they fall back. The window below is the measured width of the labels
    /// (308 pt now); if the font changes enough to leave it, the test says so instead of passing for the wrong reason.
    @Test("Today's five labels at AX3 in 350 pt fall back to the joined line (they would fit on one line at an 8 pt gap)")
    func todayLabelsAtAX3In350() throws {
        let natural = HStack(spacing: 0) {
            ForEach(Array(todayLabels.enumerated()), id: \.offset) { Text(verbatim: $1).lineLimit(1).fixedSize() }
        }
        .font(.ryft(.axis)).fixedSize().environment(\.dynamicTypeSize, .accessibility3)
        let t = Double(try #require(render(natural)).size.width)
        #expect(t + 4 * 8 <= 350 && 350 < t + 4 * 16, "the labels are \(t) pt wide: 350 no longer separates an 8 pt gap from a 16 pt one")
        let ink = try todayLabelInk(width: 350)
        #expect(ink.height > 40, "wrapped, not one line: \(ink)")
    }

    // MARK: CircleButton

    private func circle(enabled: Bool = true) -> some View {
        CircleButton(systemImage: "plus", accessibilityLabel: Text(verbatim: "Add"), action: {})
            .disabled(!enabled)
            .background(Theme.background)
    }

    @Test("Spec 24: the circle button is a 44 × 44 box around a 40 pt circle with a 1 pt border at 16 %")
    func circleButtonPixels() throws {
        let shot = try #require(render(circle()))
        #expect(shot.size == CGSize(width: 44, height: 44))
        // The ring is 1 pt, just inside the 40 pt circle: from 2 to 3 pt in from the box's edge.
        let border = inkOverScreen(0.16)
        for (x, y) in [(22.0, 2.5), (22.0, 41.5), (2.5, 22.0), (41.5, 22.0)] {
            #expect(near(shot.at(x, y), border, 3), "ring (\(x), \(y)): \(describe(shot.at(x, y)))")
        }
        // Outside the circle, in the 2 pt margin and the corners: the screen. Inside, off the symbol: the screen (no fill).
        for (x, y) in [(22.0, 1.0), (22.0, 43.0), (1.0, 22.0), (1.0, 1.0), (43.0, 43.0), (11.0, 11.0), (33.0, 33.0)] {
            #expect(near(shot.at(x, y), screen), "(\(x), \(y)): \(describe(shot.at(x, y)))")
        }
    }

    @Test("Disabled: the symbol drops to 35 % and the border does not change")
    func circleButtonDisabled() throws {
        let on = try #require(render(circle(enabled: true))), off = try #require(render(circle(enabled: false)))
        func brightest(_ s: Shot) -> Double {
            var best = 0.0
            for iy in 0..<s.height { for ix in 0..<s.width {
                let (x, y) = ((Double(ix) + 0.5) / 4, (Double(iy) + 0.5) / 4)
                if (15...29).contains(x), (15...29).contains(y) { best = max(best, s.px(ix, iy).r) }
            } }
            return best
        }
        #expect(abs(brightest(on) - ink.r) <= 3.0 / 255, "enabled symbol: \(brightest(on))")
        let dimmed = inkOverScreen(0.35).r
        #expect(abs(brightest(off) - dimmed) <= 3.0 / 255, "disabled symbol: \(brightest(off)), expected \(dimmed)")
        for (x, y) in [(22.0, 2.5), (2.5, 22.0)] {
            #expect(near(on.at(x, y), off.at(x, y), 1), "the border is the same enabled and disabled")
        }
    }

    // MARK: PillButton

    private func pill(_ style: PillButton.Style, title: String = "Continue", enabled: Bool = true, width: CGFloat = 300) -> some View {
        PillButton(Text(verbatim: title), style: style, action: {})
            .disabled(!enabled)
            .frame(width: width)
            .background(Theme.background)
    }

    @Test("Spec 25: the primary pill is 52 high with a textPrimary fill and a 40 pt circle 6 pt from the trailing edge")
    func primaryPillPixels() throws {
        let shot = try #require(render(pill(.primary)))
        #expect(shot.size == CGSize(width: 300, height: 52))
        #expect(near(shot.at(150, 2), ink), "fill at the top: \(describe(shot.at(150, 2)))")
        // Fully round ends: the corner pixels are the screen.
        #expect(near(shot.at(0.5, 0.5), screen) && near(shot.at(299.5, 51.5), screen))
        // The icon circle spans x 254…294, y 6…46: `background` inside, the fill 2 pt outside it.
        #expect(near(shot.at(274, 9), screen), "circle at the top: \(describe(shot.at(274, 9)))")
        #expect(near(shot.at(257, 26), screen), "circle at the left: \(describe(shot.at(257, 26)))")
        #expect(near(shot.at(291, 26), screen), "circle at the right: \(describe(shot.at(291, 26)))")
        #expect(near(shot.at(252, 26), ink), "fill left of the circle: \(describe(shot.at(252, 26)))")
        #expect(near(shot.at(296.5, 26), ink), "fill right of the circle: \(describe(shot.at(296.5, 26)))")
        // The title is `background` on the fill, leading, 20 pt in: dark pixels start at x ≥ 20.
        let title = try #require(shot.bounds(xs: 14...240, ys: 8...44) { self.near($0, self.screen, 40) })
        #expect(title.minX >= 19.5 && title.minX < 30, "title starts at \(title.minX)")
    }

    @Test("Spec 25: the secondary pill is an outline at 20 %, no fill, no icon, a centred title")
    func secondaryPillPixels() throws {
        let shot = try #require(render(pill(.secondary, title: "Skip")))
        #expect(shot.size == CGSize(width: 300, height: 52))
        #expect(near(shot.at(150, 0.5), inkOverScreen(0.20), 3), "outline: \(describe(shot.at(150, 0.5)))")
        #expect(near(shot.at(150, 51.5), inkOverScreen(0.20), 3))
        #expect(near(shot.at(150, 3), screen), "no fill: \(describe(shot.at(150, 3)))")
        #expect(near(shot.at(274, 26), screen), "no icon on the trailing side")
        let title = try #require(shot.bounds(xs: 10...290, ys: 8...44) { self.distance($0, self.screen) > 0.3 })
        #expect(abs(title.midX - 150) <= 2, "the title is centred, its box is \(title)")
    }

    @Test("Spec 25: disabled dims the whole pill to 35 %")
    func disabledPill() throws {
        let shot = try #require(render(pill(.primary, enabled: false)))
        let expected = inkOverScreen(0.35)
        #expect(near(shot.at(150, 2), expected, 3), "disabled fill: \(describe(shot.at(150, 2))), expected \(describe(expected))")
        let outline = try #require(render(pill(.secondary, title: "Skip", enabled: false)))
        let enabledOutline = try #require(render(pill(.secondary, title: "Skip")))
        #expect(distance(outline.at(150, 0.5), screen) < distance(enabledOutline.at(150, 0.5), screen), "the outline dims too")
    }

    /// Spec 25. A long title at AX3 wraps and the pill grows; no ink reaches the rim (the pill keeps its 26 pt corners rather
    /// than a capsule's, so the first and last lines are not cut). The title is `background` on the `textPrimary` fill: dark
    /// pixels inside the fill, clear of the icon circle (x < 254) and of the ends (x ≥ 18), are the text.
    @Test("Spec 25: at AX3 a 40-character title wraps, the pill grows past 52, and the text stays inside the fill")
    func accessibilityGrowth() throws {
        let title = "Start the guided breathing exercise now!"
        #expect(title.count == 40)
        let view = pill(.primary, title: title, width: 350).environment(\.dynamicTypeSize, .accessibility3)
        let shot = try #require(render(view))
        let height = Double(shot.size.height)
        #expect(height > 52 * 2, "the pill grew to \(height)")
        let text = try #require(shot.bounds(xs: 18...(350 - 46 - 2), ys: 4...(height - 4)) { self.near($0, self.screen, 60) },
                                "the title's ink")
        #expect(text.minY >= 8, "the text starts \(text.minY) pt from the top")
        #expect(text.maxY <= height - 8, "the text ends \(height - text.maxY) pt above the bottom")
        #expect(text.minX >= 19.5, "the text starts \(text.minX) from the left, leading is 20")
        #expect(text.maxX <= 350 - 46, "the text stays left of the icon circle: \(text.maxX)")
        // The icon circle stays 40 and centred, whatever the height.
        #expect(near(shot.at(350 - 26, height / 2 - 14), screen), "the circle: \(describe(shot.at(324, height / 2 - 14)))")
        #expect(near(shot.at(350 - 26, height / 2 - 22), ink), "above the circle's top (2 pt) is fill")
    }
}
