import Testing
@testable import Ryft

@Suite struct OrbitGaugeGeometryTests {
    typealias G = OrbitGaugeGeometry

    @Test func recoveryRunsCounterClockwiseAndSleepClockwiseFromTheTop() {
        #expect(G.Orbit.recovery.headDegrees(for: 0.5) == -90)
        #expect(G.Orbit.sleep.headDegrees(for: 0.5) == 90)
        #expect(G.Orbit.recovery.sweep(for: 0.2) < 0)
        #expect(G.Orbit.sleep.sweep(for: 0.2) > 0)
    }

    @Test func innerHalvesStopShortOfEachOtherByTheInset() {
        let r = G.Orbit.recovery.headDegrees(for: 1), s = G.Orbit.sleep.headDegrees(for: 1)
        #expect(s == 180 - G.innerInset)
        #expect(r == -(180 - G.innerInset))
        // On the 54 pt orbit the two dots at 100 % keep a dot's diameter and 4 pt of air between them.
        let m = G.metrics(forDial: 160)
        let a = G.point(centre: .zero, radius: m.innerRadius, degrees: r)
        let b = G.point(centre: .zero, radius: m.innerRadius, degrees: s)
        #expect(abs(a.x - b.x) >= 2 * m.dotRadius + 4)
    }

    @Test func startDotsOfTheInnerOrbitDoNotOverlap() {
        let m = G.metrics(forDial: 160)
        let a = G.point(centre: .zero, radius: m.innerRadius, degrees: G.Orbit.recovery.startDegrees)
        let b = G.point(centre: .zero, radius: m.innerRadius, degrees: G.Orbit.sleep.startDegrees)
        #expect(abs(a.x - b.x) >= 2 * m.dotRadius + 4)
    }

    @Test func strainTwentyOneIsAWholeTurn() {
        #expect(abs(G.Orbit.strain.sweep(for: 1) - 360) < 0.02)
        #expect(G.Orbit.strain.sweep(for: 0) == 0)
        #expect(abs(G.Orbit.strain.headDegrees(for: 0.25) - 90) < 0.01)
    }

    @Test func valuesClampAndStrainScalesTo21() {
        let v = OrbitGaugeValues(readiness: 71, recovery: 1.4, sleep: -0.2, strain: 10.5)
        #expect(v.recoveryFraction == 1)
        #expect(v.sleepFraction == 0)
        #expect(v.strainFraction == 0.5)
        #expect(OrbitGaugeValues().isEmpty)
    }

    @Test func dotIsAtTheArcHead() {
        let m = G.metrics(forDial: 160)
        // Strain 5.25 of 21 = a quarter turn: the head is at 3 o'clock.
        let head = G.point(centre: .zero, radius: m.outerRadius, degrees: G.Orbit.strain.headDegrees(for: 0.25))
        #expect(abs(head.x - m.outerRadius) < 0.01 && abs(head.y) < 0.01)
    }

    @Test func opticalFloorKeepsThreeRingsAt44() {
        let m = G.metrics(forDial: 44)
        #expect(m.outerStroke >= G.minStroke)
        #expect(m.dotRadius >= m.outerStroke * 1.15)
        // Rings stay apart: outer dot edge to inner dot edge.
        #expect(m.outerRadius - m.dotRadius > m.innerRadius + m.dotRadius)
    }

    @Test func sizesKeepMetricGaugeFrames() {
        #expect(OrbitGauge.Size.small.frame == 84)
        #expect(OrbitGauge.Size.medium.frame == 124)
        #expect(OrbitGauge.Size.large.frame == 172)
    }

    @Test func readinessZeroIsZeroNotOne() {
        let v = OrbitGaugeValues(readiness: 0, recovery: 0, sleep: 0, strain: 0)
        #expect(v.readiness == 0)
        #expect(String(v.readiness ?? -1) == "0")
        let s = OrbitGauge.spokenValue(v)
        #expect(s.hasPrefix("0, "))
        #expect(!s.hasPrefix("1, "))
    }

    @Test func spokenValueNamesEveryScore() {
        let s = OrbitGauge.spokenValue(.previewScored)
        // The simulator's region decides the decimal separator: 9.6 or 9,6.
        #expect(s.hasPrefix("71, High. Recovery 71 percent, Sleep 88 percent, Strain 9"))
        #expect(s.hasSuffix(" of 21"))
        let missing = OrbitGauge.spokenValue(OrbitGaugeValues(readiness: 71, recovery: 0.71, strain: 9.6))
        #expect(missing.contains("Sleep, no data"))
        #expect(OrbitGauge.spokenValue(OrbitGaugeValues()) == "No data")
    }
}
