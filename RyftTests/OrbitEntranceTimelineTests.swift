import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The entrance's timeline as numbers (PR 3, design.md section 10) and its Reduce Motion path. Pure: no clock, no animation.
@MainActor
@Suite struct OrbitEntranceTimelineTests {
    typealias Frame = OrbitEntranceFrame
    private static let samples: [Double] = (0...200).map { Double($0) * 0.0045 }  // 0 ... 0.9 s

    private static let tracks: [Frame.Track] = [.strain, .inner, .centre]

    private func png<V: View>(_ view: V, scheme: ColorScheme = .dark) -> Data? {
        let r = ImageRenderer(content: view.padding(20).background(Theme.background).environment(\.colorScheme, scheme))
        r.scale = 2
        return r.uiImage?.pngData()
    }

    // MARK: tracks

    @Test("tracks draw in their windows", arguments: [
        (Frame.Track.strain, 0.0, 0.15), (.inner, 0.05, 0.20), (.centre, 0.10, 0.25),
    ])
    func trackWindows(track: Frame.Track, from: Double, to: Double) {
        #expect(Frame(seconds: 0).trim(track) == 0)
        #expect(Frame(seconds: from).trim(track) == 0)
        #expect(Frame(seconds: (from + to) / 2).trim(track) > 0)
        #expect(Frame(seconds: (from + to) / 2).trim(track) < 1)
        #expect(Frame(seconds: to).trim(track) == 1)
        #expect(Frame(seconds: Frame.end).trim(track) == 1)
    }

    // MARK: dots

    @Test func dotsStartOutsideAndLandOnTheirOrbitsTurned() {
        let far: CGFloat = 100, orbit: CGFloat = 60
        for o in OrbitGaugeGeometry.Orbit.allCases {
            let start = Frame(seconds: 0).dot(o, sweep: 120, orbitRadius: orbit, farRadius: far)
            #expect(start.radius == far && start.degrees == o.startDegrees, "\(o)")
            let landed = Frame(seconds: Frame.flightEnd).dot(o, sweep: 120, orbitRadius: orbit, farRadius: far)
            #expect(landed.radius == orbit, "\(o)")
            let direction: Double = o.trackSweep < 0 ? -1 : 1
            #expect(abs(landed.degrees - (o.startDegrees + direction * Frame.turnDegrees)) < 1e-9, "\(o)")
            #expect(Frame.turnDegrees == 40)
        }
    }

    @Test func dotsFlyInStaggeredAndAreDoneBy600Milliseconds() {
        let t = Frame(seconds: 0.2)
        #expect(t.flight(.strain) > t.flight(.recovery) && t.flight(.recovery) > t.flight(.sleep))
        for o in OrbitGaugeGeometry.Orbit.allCases {
            #expect(Frame(seconds: 0.15).flight(o) == 0)
            #expect(Frame(seconds: 0.6).flight(o) == 1)
        }
    }

    @Test("the far radius is outside the frame", arguments: [OrbitGaugeSize.small, .medium, .large])
    func farRadiusIsOutside(size: OrbitGaugeSize) {
        #expect(size.frame * 0.62 > size.frame / 2 * 1.2)
    }

    // MARK: glide

    @Test func theGlideRuns600To850() {
        #expect(Frame.glideStart == 0.6 && Frame.end == 0.85)
        #expect(Frame(seconds: 0.6).glide == 0)
        #expect(Frame(seconds: 0.725).glide > 0 && Frame(seconds: 0.725).glide < 1)
        #expect(Frame(seconds: 0.85).glide == 1)
    }

    @Test func theDotIsAtTheHeadOfItsArcWhenTheGlideEnds() {
        for o in OrbitGaugeGeometry.Orbit.allCases {
            for sweep in [0.0, 90, o.trackSweep] {
                let end = Frame(seconds: Frame.end).dot(o, sweep: sweep, orbitRadius: 60, farRadius: 100)
                #expect(abs(end.degrees - (o.startDegrees + sweep)) < 1e-9 && end.radius == 60, "\(o) \(sweep)")
            }
        }
    }

    // MARK: whole timeline

    @Test func everythingIsMonotoneClampedAndFinalAtTheEnd() {
        #expect(Frame.end <= 0.9)
        var last = [Double](repeating: 0, count: 7)
        for s in Self.samples {
            let f = Frame(seconds: s)
            let now = Self.tracks.map { f.trim($0) } + OrbitGaugeGeometry.Orbit.allCases.map { f.flight($0) } + [f.glide]
            for (a, b) in zip(last, now) { #expect(b >= a - 1e-12, "at \(s)") }
            for v in now { #expect((0...1).contains(v), "at \(s)") }
            last = now
            if s >= Frame.end { #expect(now.allSatisfy { $0 == 1 }, "final at \(s)") }
        }
        // Before the start and long after the end: clamped.
        let before = Frame(seconds: -1), after = Frame(seconds: 10)
        #expect((Self.tracks.map { before.trim($0) } + [before.glide]).allSatisfy { $0 == 0 })
        #expect((Self.tracks.map { after.trim($0) } + [after.glide]).allSatisfy { $0 == 1 })
    }

    // MARK: frames

    @Test("the first frame is empty for every mode", arguments: [0, 1, 2])
    func firstFrameIsEmpty(index: Int) {
        let modes: [OrbitGaugeMode] = [.scored(.previewScored), .calibrating(OrbitGaugeCalibration(nights: 3)),
                                       .pending(previous: .previewScored)]
        let empty = png(Color.clear.frame(width: 172, height: 172))
        for scheme in [ColorScheme.dark, .light] {
            let first = png(OrbitGauge(mode: modes[index], size: .large, animatesFill: false, breathes: false,
                                       entrance: .assemble, frozenAt: 0), scheme: scheme)
            #expect(first != nil && first == png(Color.clear.frame(width: 172, height: 172), scheme: scheme), "\(index) \(scheme)")
        }
        #expect(empty != nil)
    }

    @Test func aMiddleFrameIsNeitherEmptyNorFinal() {
        let mode = OrbitGaugeMode.scored(.previewScored)
        let still = png(OrbitGauge(mode: mode, size: .large, animatesFill: false, breathes: false))
        let mid = png(OrbitGauge(mode: mode, size: .large, animatesFill: false, breathes: false, entrance: .assemble, frozenAt: 0.4))
        #expect(mid != nil && mid != still)
        #expect(mid != png(Color.clear.frame(width: 172, height: 172)))
    }

    @Test("none is the static render, with or without a frozen clock", arguments: [0, 1, 2])
    func noneIsStatic(index: Int) {
        let modes: [OrbitGaugeMode] = [.scored(.previewScored), .calibrating(OrbitGaugeCalibration(nights: 3)),
                                       .pending(previous: .previewScored)]
        let a = png(OrbitGauge(mode: modes[index], size: .large, animatesFill: false, breathes: false))
        for t in [0.0, 0.3, Frame.end] {
            let b = png(OrbitGauge(mode: modes[index], size: .large, animatesFill: false, breathes: false,
                                   entrance: .none, frozenAt: t))
            #expect(a != nil && a == b, "\(index) \(t)")
        }
    }

    // MARK: Reduce Motion

    @Test func underReduceMotionTheEntranceIsOnlyAnOpacityFade() {
        let mode = OrbitGaugeMode.scored(.previewScored)
        func gauge(_ t: Double, reduced: Bool) -> Data? {
            png(OrbitGauge(mode: mode, size: .large, animatesFill: false, breathes: false, entrance: .assemble, frozenAt: t)
                .environment(\.orbitForcesReducedMotion, reduced))
        }
        let still = png(OrbitGauge(mode: mode, size: .large, animatesFill: false, breathes: false))
        // Past the 250 ms fade the settled drawing is complete, while the choreography is still flying at 300 ms.
        #expect(gauge(0.3, reduced: true) == still)
        #expect(gauge(0.3, reduced: false) != still)
        // Nothing at the start, something faint half way: the settled drawing at partial opacity, no trim or flight.
        #expect(gauge(0, reduced: true) == png(Color.clear.frame(width: 172, height: 172)))
        let half = gauge(0.125, reduced: true)
        #expect(half != still && half != gauge(0, reduced: true))
        #expect(half != gauge(0.125, reduced: false))
    }
}
