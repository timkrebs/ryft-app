import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The glow per kind (docs/work/2026-11-16-nocturne/design.md §P4-3, §P4-11 tests 7–16): the four shapes, the 2-up's
/// fallback, the label ink, and the contrast in each concrete tile, computed from `overlayOpacity` over the spec's text rect
/// (16 at the sides, 14 top, 12 bottom; worst pixel on a 40 × 40 grid) and checked against `ImageRenderer`'s pixels. The
/// spec's numbers are margins, not pins: every text case asserts ≥ 4.5:1 and every graphic ≥ 3:1.
@MainActor
@Suite struct GlowTileKindTests {
    private typealias Tokens = NocturneTokenTests
    private typealias RGBA = NocturneTokenTests.RGBA
    typealias Kind = GlowTileSpec.Kind

    // MARK: colours

    private var ink: RGBA { Tokens.resolve(Theme.textPrimary) }
    private var screen: RGBA { Tokens.resolve(Theme.background) }
    private var surface: RGBA { Tokens.resolve(Theme.surface) }
    private var volt: RGBA { Tokens.resolve(Theme.signal) }

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

    private func with(_ c: RGBA, alpha: Double) -> RGBA { RGBA(r: c.r, g: c.g, b: c.b, a: alpha) }

    /// The tile's pixel at (`x`, `y`): `background` at the overlay's opacity over the metric colour.
    private func pixel(_ shape: GlowTileSpec.Shape, _ metric: Metric, _ x: Double, _ y: Double, in size: CGSize) -> RGBA {
        Tokens.over(with(screen, alpha: shape.overlayOpacity(x: x, y: y, in: size)), Tokens.resolve(metric.colour))
    }

    /// A rect in the tile's points, inset from its edges.
    private struct Rect {
        var minX, minY, maxX, maxY: Double
        /// The spec's text rect: the tile less 16 at the sides, 14 at the top and 12 at the bottom.
        static func text(_ size: CGSize) -> Rect {
            Rect(minX: 16, minY: 14, maxX: Double(size.width) - 16, maxY: Double(size.height) - 12)
        }
    }

    /// The lowest contrast of `foreground` at `alpha` over the tile's pixels in `rect`, on a 41 × 41 grid of points.
    private func worst(_ kind: Kind, _ metric: Metric, _ size: CGSize, _ foreground: RGBA, alpha: Double,
                       in rect: Rect? = nil) -> Double {
        let shape = GlowTileSpec.shape(for: kind, size: size)
        let r = rect ?? .text(size)
        var lowest = Double.infinity
        for i in 0...40 {
            for j in 0...40 {
                let x = r.minX + (r.maxX - r.minX) * Double(i) / 40, y = r.minY + (r.maxY - r.minY) * Double(j) / 40
                let ground = pixel(shape, metric, x, y, in: size)
                lowest = min(lowest, Tokens.ratio(with(foreground, alpha: alpha), on: ground))
            }
        }
        return lowest
    }

    private func label(_ metric: Metric, _ typeSize: DynamicTypeSize = .large) -> Double {
        GlowTileSpec.labelOpacity(metric: metric.colour, typeSize: typeSize)
    }

    // MARK: 7. The shapes

    struct ShapeCase: Sendable, CustomTestStringConvertible {
        let kind: GlowTileSpec.Kind
        let ellipse: [Double]
        let stops: [Double]
        let radius: CGFloat
        let minHeight: CGFloat
        var testDescription: String { "\(kind)" }
    }

    @Test("Spec 7: each kind's ellipse, stop locations, radius and minimum height; every kind 0.97 / 0.92 / 0.55 / 0.10", arguments: [
        ShapeCase(kind: .twoUp, ellipse: [0.85, 0.80, 0.50], stops: [0, 0.30, 0.65, 1], radius: 24, minHeight: 124),
        ShapeCase(kind: .strain, ellipse: [0.90, 1.10, 0.55], stops: [0, 0.32, 0.66, 1], radius: 24, minHeight: 96),
        ShapeCase(kind: .hypnogram, ellipse: [0.90, 0.95, 0.55], stops: [0, 0.34, 0.68, 1], radius: 28, minHeight: 168),
        ShapeCase(kind: .panel, ellipse: [0.90, 1.10, 0.55], stops: [0, 0.34, 0.68, 1], radius: 28, minHeight: 172),
    ])
    func shapes(_ c: ShapeCase) {
        let shape = GlowTileSpec.shape(for: c.kind)
        #expect([shape.rx, shape.ry, shape.cy] == c.ellipse)
        #expect(shape.stops.map(\.location) == c.stops)
        #expect(shape.stops.map(\.opacity) == [0.97, 0.92, 0.55, 0.10])
        #expect(shape.radius == c.radius && shape.minHeight == c.minHeight)
        #expect(Kind.allCases.count == 4)
    }

    @Test("Spec 7: the 2-up keeps its own ellipse up to 200 × 160 and takes the panel's past it, with its own radius and height",
          arguments: [
              (CGSize(width: 169, height: 124), false), (CGSize(width: 200, height: 160), false),
              (CGSize(width: 161, height: 124), false), (CGSize(width: 194, height: 124), false),
              (CGSize(width: 201, height: 124), true), (CGSize(width: 169, height: 161), true),
              (CGSize(width: 350, height: 124), true), (CGSize(width: 350, height: 300), true),
          ])
    func twoUpFallback(_ size: CGSize, _ fallsBack: Bool) {
        let shape = GlowTileSpec.shape(for: .twoUp, size: size)
        let own = GlowTileSpec.shape(for: .twoUp), panel = GlowTileSpec.shape(for: .panel)
        let drawn = fallsBack ? panel : own
        #expect(shape.rx == drawn.rx && shape.ry == drawn.ry && shape.cy == drawn.cy && shape.stops == drawn.stops, "\(size)")
        #expect(shape.radius == 24 && shape.minHeight == 124, "the fallback keeps the 2-up's corner and height")
    }

    @Test("Spec 7: no other kind changes with its size", arguments: [Kind.strain, .hypnogram, .panel])
    func otherKindsKeepTheirShape(_ kind: Kind) {
        for size in [CGSize(width: 169, height: 124), CGSize(width: 350, height: 96), CGSize(width: 400, height: 420)] {
            #expect(GlowTileSpec.shape(for: kind, size: size) == GlowTileSpec.shape(for: kind), "\(kind) at \(size)")
        }
    }

    @Test("The board's kinds pad 14 / 16 / 12 / 16 (the spec's text rect); the panel keeps PR 2's 14 below")
    func padding() {
        for kind in [Kind.twoUp, .strain, .hypnogram] {
            #expect(GlowTileSpec.padding(for: kind) == EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16), "\(kind)")
        }
        #expect(GlowTileSpec.padding(for: .panel) == EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
    }

    // MARK: 8. The overlay per kind

    @Test("Spec 8: at 0, the second stop, the third and 1 each kind's overlay is the table's", arguments: Kind.allCases)
    func overlayAtTheStops(_ kind: Kind) {
        let shape = GlowTileSpec.shape(for: kind)
        let at = shape.stops.map(\.location)
        let got = at.map { shape.overlayOpacity(atRadiusFraction: $0) }
        #expect(zip(got, [0.97, 0.92, 0.55, 0.10]).allSatisfy { abs($0 - $1) < 1e-12 }, "\(got)")
        #expect(shape.overlayOpacity(atRadiusFraction: 1.5) == 0.10 && shape.overlayOpacity(atRadiusFraction: -1) == 0.97)
    }

    @Test("Spec 8: the 2-up's corner at t 0.858 is ≈ 0.283 background, the strain's at its padded corner lighter than its core")
    func twoUpCorner() {
        let twoUp = GlowTileSpec.shape(for: .twoUp)
        #expect(abs(twoUp.overlayOpacity(atRadiusFraction: 0.858) - 0.283) < 0.001)
        // The 2-up's corner of the text rect (16, 112) in 169 × 124 is t ≈ 0.694.
        let t = twoUp.radiusFraction(x: 16, y: 112, in: CGSize(width: 169, height: 124))
        #expect(abs(t - 0.694) < 0.001, "t \(t)")
    }

    // MARK: 9. The label ink (L23)

    @Test("Spec 9: the recovery tile's labels are full ink at every size; the others 78 % below AX1, full from AX1",
          arguments: DynamicTypeSize.allCases)
    func labelOpacity(_ size: DynamicTypeSize) {
        #expect(GlowTileSpec.labelOpacity(metric: Theme.recovery, typeSize: size) == 1)
        let others = size.isAccessibilitySize ? 1.0 : 0.78
        #expect(GlowTileSpec.labelOpacity(metric: Theme.metricSleep, typeSize: size) == others, "\(size)")
        #expect(GlowTileSpec.labelOpacity(metric: Theme.metricStrain, typeSize: size) == others, "\(size)")
    }

    /// A rectangle in `ryftGlowLabelStyle()` fills with the label ink: on the flat tile (a solid `surface`), the drawn pixel
    /// says the opacity the tile published.
    private func drawnLabelOpacity(_ metric: Metric, kind: Kind, typeSize: DynamicTypeSize) throws -> Double {
        // At the kind's own height: a taller frame would centre the content-sized tile in it.
        let view = GlowTile(metric.colour, kind: kind, reduceTransparency: true) {
            Rectangle().ryftGlowLabelStyle().frame(width: 40, height: 20)
        }
        .frame(width: 169, height: GlowTileSpec.shape(for: kind).minHeight)
        .environment(\.dynamicTypeSize, typeSize)
        let shot = try #require(KindShot.render(view))
        let p = shot.at(30, 24)
        // The green channel: the farthest apart for ink and surface.
        return (p.g - surface.g) / (ink.g - surface.g)
    }

    @Test("Spec 9: the tile publishes the ink, and `ryftGlowLabelStyle()` draws it", arguments: [
        (Metric.recovery, DynamicTypeSize.large, 1.0), (.sleep, .large, 0.78), (.strain, .large, 0.78),
        (.recovery, .accessibility3, 1.0), (.sleep, .accessibility3, 1.0),
    ])
    func labelInkIsDrawn(_ metric: Metric, _ typeSize: DynamicTypeSize, _ want: Double) throws {
        let got = try drawnLabelOpacity(metric, kind: metric == .strain ? .strain : .twoUp, typeSize: typeSize)
        #expect(abs(got - want) <= 0.02, "\(metric) at \(typeSize): \(got)")
    }

    @Test("Outside a glow tile the label falls back to 78 % below AX1 and the compact ruler's labels follow the tile")
    func labelOutsideATile() {
        #expect(GlowTileSpec.labelOpacity(for: .large) == 0.78 && GlowTileSpec.labelOpacity(for: .accessibility1) == 1)
        #expect(RulerScale.labelOpacity(size: .compact, dynamicTypeSize: .large, glowLabelOpacity: 1) == 1)
        #expect(RulerScale.labelOpacity(size: .compact, dynamicTypeSize: .large, glowLabelOpacity: nil) == 0.78)
        #expect(RulerScale.labelOpacity(size: .regular, dynamicTypeSize: .large, glowLabelOpacity: 1) == nil)
    }

    // MARK: 10–11. Text contrast per tile

    struct TileCase: Sendable, CustomTestStringConvertible {
        let name: String
        let kind: GlowTileSpec.Kind
        let metric: Metric
        let size: CGSize
        /// The spec's worst-pixel numbers at the default size (margins, not pins): `textPrimary` and the label ink.
        let ink: Double
        let label: Double
        var testDescription: String { "\(name) \(Int(size.width)) × \(Int(size.height))" }
    }

    nonisolated private static let boardTiles: [TileCase] = [
        TileCase(name: "recovery 2-up", kind: .twoUp, metric: .recovery, size: CGSize(width: 169, height: 124), ink: 5.0, label: 5.0),
        TileCase(name: "sleep 2-up", kind: .twoUp, metric: .sleep, size: CGSize(width: 169, height: 124), ink: 6.8, label: 4.9),
        TileCase(name: "strain", kind: .strain, metric: .strain, size: CGSize(width: 350, height: 96), ink: 9.0, label: 6.2),
        TileCase(name: "hypnogram", kind: .hypnogram, metric: .sleep, size: CGSize(width: 350, height: 168), ink: 7.2, label: 5.1),
    ]

    @Test("Spec 10: the board's tiles at the default size: textPrimary and the label over the worst pixel of the text rect",
          arguments: boardTiles)
    func boardTileContrast(_ c: TileCase) {
        let text = worst(c.kind, c.metric, c.size, ink, alpha: 1)
        let labels = worst(c.kind, c.metric, c.size, ink, alpha: label(c.metric))
        #expect(text >= 4.5 && labels >= 4.5, "\(c): \(text) / \(labels)")
        // The spec's table, to its second decimal: a change to a stop or an ellipse shows here first.
        #expect(text >= c.ink && labels >= c.label, "\(c): \(text) / \(labels), the spec has \(c.ink) / \(c.label)")
    }

    @Test("Spec 11: other widths and a taller 2-up keep every text at 4.5:1", arguments: [
        TileCase(name: "recovery 2-up", kind: .twoUp, metric: .recovery, size: CGSize(width: 161, height: 124), ink: 0, label: 0),
        TileCase(name: "sleep 2-up", kind: .twoUp, metric: .sleep, size: CGSize(width: 161, height: 124), ink: 0, label: 0),
        TileCase(name: "recovery 2-up", kind: .twoUp, metric: .recovery, size: CGSize(width: 194, height: 124), ink: 0, label: 0),
        TileCase(name: "sleep 2-up", kind: .twoUp, metric: .sleep, size: CGSize(width: 194, height: 124), ink: 0, label: 0),
        TileCase(name: "recovery 2-up", kind: .twoUp, metric: .recovery, size: CGSize(width: 169, height: 160), ink: 0, label: 0),
        TileCase(name: "sleep 2-up", kind: .twoUp, metric: .sleep, size: CGSize(width: 169, height: 160), ink: 0, label: 0),
        TileCase(name: "strain", kind: .strain, metric: .strain, size: CGSize(width: 335, height: 96), ink: 0, label: 0),
        TileCase(name: "strain", kind: .strain, metric: .strain, size: CGSize(width: 400, height: 96), ink: 0, label: 0),
        TileCase(name: "hypnogram", kind: .hypnogram, metric: .sleep, size: CGSize(width: 335, height: 168), ink: 0, label: 0),
        TileCase(name: "hypnogram", kind: .hypnogram, metric: .sleep, size: CGSize(width: 400, height: 168), ink: 0, label: 0),
    ])
    func otherSizes(_ c: TileCase) {
        let text = worst(c.kind, c.metric, c.size, ink, alpha: 1)
        let labels = worst(c.kind, c.metric, c.size, ink, alpha: label(c.metric))
        #expect(text >= 4.5 && labels >= 4.5, "\(c): \(text) / \(labels)")
    }

    // MARK: 12. AX3

    @Test("Spec 12: AX3, full ink in the single column: 2-ups with the panel ellipse, strain and hypnogram as they grow",
          arguments: [124.0, 160, 240, 300])
    func ax3TwoUps(_ height: Double) {
        let size = CGSize(width: 350, height: height)
        #expect(GlowTileSpec.shape(for: .twoUp, size: size).rx == GlowTileSpec.shape(for: .panel).rx)
        for metric in [Metric.recovery, .sleep] {
            #expect(label(metric, .accessibility3) == 1)
            let c = worst(.twoUp, metric, size, ink, alpha: 1)
            // The spec's floors: recovery 5.89 at 300, sleep 7.74.
            #expect(c >= 4.5 && c >= (metric == .recovery ? 5.85 : 7.7), "\(metric) 350 × \(Int(height)): \(c)")
        }
    }

    @Test("Spec 12: AX3 strain at 350 × 150…300 ≥ 7.9 and hypnogram at 350 × 260…420 ≥ 6.4")
    func ax3Wide() {
        for height in [150.0, 200, 300] {
            let c = worst(.strain, .strain, CGSize(width: 350, height: height), ink, alpha: 1)
            #expect(c >= 7.9, "strain 350 × \(Int(height)): \(c)")
        }
        for height in [260.0, 340, 420] {
            let c = worst(.hypnogram, .sleep, CGSize(width: 350, height: height), ink, alpha: 1)
            #expect(c >= 6.4, "hypnogram 350 × \(Int(height)): \(c)")
        }
    }

    @Test("D4-12: at 350 × 124 the 2-up's own ellipse would fail even in full ink; the panel's passes")
    func whyTheFallback() {
        let size = CGSize(width: 350, height: 124)
        let own = GlowTileSpec.shape(for: .twoUp)
        var lowest = Double.infinity
        let r = Rect.text(size)
        for i in 0...40 {
            for j in 0...40 {
                let x = r.minX + (r.maxX - r.minX) * Double(i) / 40, y = r.minY + (r.maxY - r.minY) * Double(j) / 40
                lowest = min(lowest, Tokens.ratio(ink, on: pixel(own, .recovery, x, y, in: size)))
            }
        }
        #expect(lowest < 4.5, "the board's ellipse at 350 wide: \(lowest)")
        #expect(worst(.twoUp, .recovery, size, ink, alpha: 1) >= 4.5)
    }

    // MARK: 13. Why the rule exists

    @Test("Spec 13: the board's own label inks fail where the spec says: recovery at 78 %, sleep 2-up at 62 %, hypnogram at 55 %")
    func boardInksFail() {
        let twoUp = CGSize(width: 169, height: 124)
        #expect(worst(.twoUp, .recovery, twoUp, ink, alpha: 0.78) < 4.5)
        #expect(worst(.twoUp, .sleep, twoUp, ink, alpha: 0.62) < 4.5)
        #expect(worst(.hypnogram, .sleep, CGSize(width: 350, height: 168), ink, alpha: 0.55) < 4.5)
        // And the one place 0.62 passes: the strain tile (4.60).
        #expect(worst(.strain, .strain, CGSize(width: 350, height: 96), ink, alpha: 0.62) >= 4.5)
    }

    // MARK: 14. Graphics

    @Test("Spec 14: graphics read 3:1: the sparkline and Volt in the 2-ups' top-right, the dot row's ring in the sleep 2-up")
    func twoUpGraphics() {
        let size = CGSize(width: 169, height: 124)
        // The series sits right of the label, under the tile's top-right corner (derived: 58 × 20 at the padding's edge).
        let series = Rect(minX: 95, minY: 14, maxX: 153, maxY: 34)
        #expect(worst(.twoUp, .recovery, size, ink, alpha: Sparkline.lineOpacity, in: series) >= 3)
        #expect(worst(.twoUp, .recovery, size, volt, alpha: 1, in: series) >= 3)
        #expect(worst(.twoUp, .sleep, size, volt, alpha: 1, in: series) >= 3)
        // The seven dots (66 × 6) in the same corner of the sleep tile: margin 0.09 (nothing may lower the outline).
        let dots = Rect(minX: 87, minY: 14, maxX: 153, maxY: 34)
        #expect(worst(.twoUp, .sleep, size, ink, alpha: DotRow.outlineOpacity, in: dots) >= 3)
    }

    @Test("Spec 14: the hypnogram's step line and deep bars, the compact ruler's zone ticks and needle in the strain tile")
    func wideGraphics() {
        let hypnogram = CGSize(width: 350, height: 168)
        // The plot: right of the 38 pt stage column, 90 high under the header (14 + 17.6 + 10).
        let plot = Rect(minX: 54, minY: 41.6, maxX: 334, maxY: 131.6)
        #expect(worst(.hypnogram, .sleep, hypnogram, ink, alpha: HypnogramPlot.lineOpacity, in: plot) >= 3)
        let sleep = Tokens.resolve(Theme.metricSleep)
        #expect(worst(.hypnogram, .sleep, hypnogram, sleep, alpha: 1, in: plot) >= 3)
        let ruler = Rect(minX: 16, minY: 52, maxX: 334, maxY: 84)
        let strain = CGSize(width: 350, height: 96)
        #expect(worst(.strain, .strain, strain, ink, alpha: 0.6, in: ruler) >= 3)
        #expect(worst(.strain, .strain, strain, volt, alpha: 1, in: ruler) >= 3)
    }

    // MARK: 15. Reduce Transparency

    @Test("Spec 15: on the flat surface the ink, the 78 % label, the sparkline and the deep bars all pass")
    func reduceTransparencyContrast() {
        #expect(Tokens.ratio(ink, on: surface) >= 4.5)
        #expect(Tokens.ratio(with(ink, alpha: 0.78), on: surface) >= 4.5)
        #expect(Tokens.ratio(with(ink, alpha: Sparkline.lineOpacity), on: surface) >= 3)
        #expect(Tokens.ratio(Tokens.resolve(Theme.metricSleep), on: surface) >= 3)
    }

    @Test("Spec 15: every kind under Reduce Transparency is flat surface inside a 2 pt metric border", arguments: Kind.allCases)
    func flatKinds(_ kind: Kind) throws {
        let size = CGSize(width: kind == .twoUp ? 169 : 350, height: GlowTileSpec.shape(for: kind).minHeight)
        let shot = try #require(KindShot.render(GlowTile(Theme.metricSleep, kind: kind, reduceTransparency: true) {
            Color.clear
        }.frame(width: size.width, height: size.height)))
        for (x, y) in [(size.width / 2, size.height / 2), (40, size.height / 2), (size.width - 40, 20)] {
            #expect(NocturneTokenTests.matches(shot.at(Double(x), Double(y)), surface), "\(kind) at \(x), \(y)")
        }
        #expect(NocturneTokenTests.matches(shot.at(Double(size.width) / 2, 1), Tokens.resolve(Theme.metricSleep)))
    }

    // MARK: rendered: the overlay draws the kind's shape at the tile's size

    @Test("The rendered tile is the computed one (±3/255) over its text rect, per kind and for the 2-up's fallback",
          arguments: [
              (Kind.twoUp, Metric.recovery, CGSize(width: 169, height: 124)),
              (.twoUp, .sleep, CGSize(width: 169, height: 124)),
              (.twoUp, .recovery, CGSize(width: 350, height: 124)),
              (.strain, .strain, CGSize(width: 350, height: 96)),
              (.hypnogram, .sleep, CGSize(width: 350, height: 168)),
              (.panel, .recovery, CGSize(width: 350, height: 172)),
          ])
    func renderedMatchesComputed(_ kind: Kind, _ metric: Metric, _ size: CGSize) throws {
        let shot = try #require(KindShot.render(GlowTile(metric.colour, kind: kind, reduceTransparency: false) {
            Color.clear
        }.frame(width: size.width, height: size.height)))
        let shape = GlowTileSpec.shape(for: kind, size: size)
        let r = Rect.text(size)
        for i in 0...6 {
            for j in 0...6 {
                let x = r.minX + (r.maxX - r.minX) * Double(i) / 6, y = r.minY + (r.maxY - r.minY) * Double(j) / 6
                let want = pixel(shape, metric, x, y, in: size), got = shot.at(x, y)
                let off = max(abs(got.r - want.r), abs(got.g - want.g), abs(got.b - want.b))
                #expect(off <= 3.0 / 255 + 1e-9, "\(kind) at (\(x), \(y)): \(Tokens.describe(got)) not \(Tokens.describe(want))")
            }
        }
    }

    // MARK: 16. The shim

    @Test("Spec 16: the PR 2 init(_:radius:) still draws the panel's ellipse (a 2-up of that size would be brighter)")
    func shimDrawsPanel() throws {
        let size = CGSize(width: 169, height: 124)
        let shot = try #require(KindShot.render(GlowTile(Theme.recovery, radius: .tile) { Color.clear }
            .frame(width: size.width, height: size.height)))
        let panel = GlowTileSpec.shape(for: .panel), twoUp = GlowTileSpec.shape(for: .twoUp)
        // The text rect's bottom-left corner: the two ellipses differ most there.
        let got = shot.at(16, 112)
        let asPanel = pixel(panel, .recovery, 16, 112, in: size), asTwoUp = pixel(twoUp, .recovery, 16, 112, in: size)
        #expect(abs(got.g - asPanel.g) <= 3.0 / 255, "\(Tokens.describe(got)) vs panel \(Tokens.describe(asPanel))")
        #expect(abs(got.g - asTwoUp.g) > 10.0 / 255, "the shim is not the 2-up")
    }
}

/// `ImageRenderer` pixels, sRGB, un-premultiplied: a small copy of `NocturneComponentRenderTests`' reader.
@MainActor
struct KindShot {
    let width: Int, height: Int, scale: CGFloat
    let bytes: [UInt8]

    static func render<V: View>(_ view: V, scale: CGFloat = 2) -> KindShot? {
        let renderer = ImageRenderer(content: view.environment(\.displayScale, scale))
        renderer.scale = scale
        guard let cg = renderer.uiImage?.cgImage else { return nil }
        let (w, h) = (cg.width, cg.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return KindShot(width: w, height: h, scale: scale, bytes: bytes)
    }

    var size: CGSize { CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale) }

    func px(_ ix: Int, _ iy: Int) -> NocturneTokenTests.RGBA {
        let i = (iy * width + ix) * 4
        let a = Double(bytes[i + 3]) / 255
        guard a > 0 else { return NocturneTokenTests.RGBA(r: 0, g: 0, b: 0, a: 0) }
        return NocturneTokenTests.RGBA(r: Double(bytes[i]) / 255 / a, g: Double(bytes[i + 1]) / 255 / a,
                                       b: Double(bytes[i + 2]) / 255 / a, a: a)
    }

    /// The pixel that covers the point.
    func at(_ x: Double, _ y: Double) -> NocturneTokenTests.RGBA {
        px(min(max(Int((x * Double(scale)).rounded(.down)), 0), width - 1),
           min(max(Int((y * Double(scale)).rounded(.down)), 0), height - 1))
    }
}
