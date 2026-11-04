import Testing
import SwiftUI
@testable import Ryft

@Suite("RyftMarkGeometry")
struct RyftMarkGeometryTests {
    typealias G = RyftMarkGeometry

    /// Clear-air rule at nominal size: chord = dotR + stroke/2 + airFactor * stroke.
    private func expectedHalfGap(radius: Double) -> Double {
        let chord = G.dotRadius + G.stroke / 2 + G.airFactor * G.stroke
        return 2 * asin(chord / (2 * radius)) * 180 / .pi
    }

    @Test("nominal metrics equal the constants", arguments: [44.0, 1024.0])
    func nominalMetrics(side: Double) {
        let m = G.metrics(forSide: side)
        #expect(m.stroke == G.stroke)
        #expect(m.dotRadius == G.dotRadius)
        #expect(m.showsInnerRing)
    }

    @Test("nominal half gaps follow the clear-air rule", arguments: [44.0, 1024.0])
    func nominalHalfGaps(side: Double) {
        let m = G.metrics(forSide: side)
        let outer = G.halfGap(ringRadius: G.outer.radius, metrics: m)
        let middle = G.halfGap(ringRadius: G.middle.radius, metrics: m)
        #expect(abs(outer - expectedHalfGap(radius: G.outer.radius)) < 1e-9)
        #expect(abs(middle - expectedHalfGap(radius: G.middle.radius)) < 1e-9)
        #expect(abs(outer - 14.02) < 0.01)
        #expect(abs(middle - 24.22) < 0.01)
    }

    @Test("nominal arcs")
    func nominalArcs() {
        let m = G.metrics(forSide: 44)
        let outer = G.arcs(of: G.outer, metrics: m)
        #expect(outer.count == 1)
        #expect(abs(outer[0].start - 79.02) < 0.01)
        #expect(abs(outer[0].end - 410.98) < 0.01)

        let middle = G.arcs(of: G.middle, metrics: m)
        #expect(middle.count == 2)
        #expect(abs(middle[0].start - -51.78) < 0.01)
        #expect(abs(middle[0].end - 155.78) < 0.01)
        #expect(abs(middle[1].start - 204.22) < 0.01)
        #expect(abs(middle[1].end - 259.78) < 0.01)
    }

    static let sides: [Double] = [18, 20, 22, 24, 34, 44, 48, 120, 1024]

    @Test("every arc stays at least 15 degrees long", arguments: sides)
    func arcsNeverCollapse(side: Double) {
        let m = G.metrics(forSide: side)
        for ring in [G.outer, G.middle] {
            let arcs = G.arcs(of: ring, metrics: m)
            // `arcs` drops a collapsed arc; one arc per dot means none was dropped.
            #expect(arcs.count == ring.dots.count, "ring \(ring.radius) at \(side) pt lost an arc")
            for a in arcs {
                #expect(a.end - a.start >= 15, "ring \(ring.radius) at \(side) pt: \(a)")
            }
        }
    }

    @Test("effective stroke is not below the minimum", arguments: sides)
    func strokeFloor(side: Double) {
        let m = G.metrics(forSide: side)
        #expect(m.stroke * side / G.box >= G.minStrokePt - 1e-9)
    }

    @Test("dots are never thinner than the ring", arguments: sides)
    func dotsNotThinnerThanRing(side: Double) {
        let m = G.metrics(forSide: side)
        #expect(m.dotRadius >= m.stroke / 2)
    }

    @Test("degenerate sides do not crash and stay finite", arguments: [0.0, -10.0])
    func degenerateSides(side: Double) {
        let m = G.metrics(forSide: side)
        #expect(m.stroke.isFinite)
        #expect(m.dotRadius.isFinite)
        for ring in [G.outer, G.middle] {
            #expect(G.halfGap(ringRadius: ring.radius, metrics: m).isFinite)
            for a in G.arcs(of: ring, metrics: m) {
                #expect(a.start.isFinite && a.end.isFinite)
            }
        }
    }

    @Test("shape path is non-empty and inside its rect", arguments: [18.0, 24.0, 100.0])
    func shapePathBounds(side: Double) {
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let path = RyftMarkShape().path(in: rect)
        #expect(!path.isEmpty)
        #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(path.boundingRect))
    }
}
