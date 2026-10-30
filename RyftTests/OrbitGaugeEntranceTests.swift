import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The entrance's frames (PR 3). Deterministic: `OrbitGauge(entrance: .assemble, frozenAt:)` draws one moment.
@MainActor
@Suite struct OrbitGaugeEntranceTests {
    private static let modes: [(String, OrbitGaugeMode)] = [
        ("scored", .scored(.previewScored)),
        ("calibrating", .calibrating(OrbitGaugeCalibration(nights: 3))),
        ("pending", .pending(previous: .previewScored)),
    ]

    private func png<V: View>(_ view: V, scheme: ColorScheme) -> Data? {
        let r = ImageRenderer(content: view.padding(20).background(Theme.background).environment(\.colorScheme, scheme))
        r.scale = 2
        return r.uiImage?.pngData()
    }

    @Test func theLastFrameIsTheStaticRender() {
        for (name, mode) in Self.modes {
            for scheme in [ColorScheme.dark, .light] {
                let still = png(OrbitGauge(mode: mode, size: .large, animatesFill: false, breathes: false), scheme: scheme)
                let end = png(OrbitGauge(mode: mode, size: .large, animatesFill: false, breathes: false,
                                         entrance: .assemble, frozenAt: OrbitEntranceFrame.end), scheme: scheme)
                #expect(still != nil && still == end, "\(name) \(scheme)")
            }
        }
    }

    @Test func theFirstFrameHasNoMarksAndNoTracks() {
        let first = png(OrbitGauge(mode: .scored(.previewScored), size: .large, entrance: .assemble, frozenAt: 0), scheme: .dark)
        let empty = png(Color.clear.frame(width: 172, height: 172), scheme: .dark)
        #expect(first == empty)
    }

    @Test func noneIgnoresAFrozenClock() {
        let a = png(OrbitGauge(mode: .scored(.previewScored), size: .large), scheme: .dark)
        let b = png(OrbitGauge(mode: .scored(.previewScored), size: .large, entrance: .none, frozenAt: 0.1), scheme: .dark)
        #expect(a == b)
    }

    @Test func theTimingsAddUpTo850Milliseconds() {
        #expect(OrbitEntranceFrame.end == 0.85)
        #expect(OrbitEntranceFrame(seconds: 0).glide == 0)
        #expect(OrbitEntranceFrame(seconds: OrbitEntranceFrame.end).glide == 1)
        for orbit in OrbitGaugeGeometry.Orbit.allCases {
            #expect(OrbitEntranceFrame(seconds: 0.15).flight(orbit) == 0)
            #expect(OrbitEntranceFrame(seconds: 0.60).flight(orbit) == 1)
        }
        #expect(OrbitEntranceFrame(seconds: 0.25).trim(.centre) == 1)
    }

    /// `ORBIT_SHOTS_DIR` set: the key frames for the design note.
    @Test func writeShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORBIT_SHOTS_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, mode) in Self.modes {
            for scheme in [ColorScheme.dark, .light] {
                let row = HStack(spacing: 8) {
                    ForEach([0.0, 0.25, 0.6, OrbitEntranceFrame.end], id: \.self) { t in
                        OrbitGauge(mode: mode, size: .medium, animatesFill: false, breathes: false, entrance: .assemble, frozenAt: t)
                    }
                }
                let r = ImageRenderer(content: row.padding(20).background(Theme.background).environment(\.colorScheme, scheme))
                r.scale = 3
                try r.uiImage?.pngData()?.write(to: URL(fileURLWithPath: "\(dir)/pr3-\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }

    // MARK: Reduce Motion changing while the entrance is under way or after it

    private func stage(elapsed: Double, reduced: Bool, done: Bool) -> some View {
        let mode = OrbitGaugeMode.scored(.previewScored)
        return OrbitEntranceStage(elapsed: elapsed, reduced: reduced, done: done, mode: mode, size: .large,
                                  palette: .assets, settled: OrbitGaugeDrawing(mode: mode, size: .large),
                                  centre: EmptyView())
    }

    @Test func afterTheFadeTurningReduceMotionOffSettlesOnTheStaticDrawing() {
        let still = png(OrbitGaugeDrawing(mode: .scored(.previewScored), size: .large), scheme: .dark)
        // The fade ended at 0.25 s and `reduced` is false again: done, so never a frame of the choreography.
        #expect(png(stage(elapsed: OrbitEntranceFrame.fadeDuration, reduced: false, done: true), scheme: .dark) == still)
        // The bug it guards: not done, the same inputs drew the choreography at 0.25 s.
        #expect(png(stage(elapsed: OrbitEntranceFrame.fadeDuration, reduced: false, done: false), scheme: .dark) != still)
    }

    @Test func reduceMotionTurnedOnMidChoreographyShowsTheSettledDrawing() {
        let still = png(OrbitGaugeDrawing(mode: .scored(.previewScored), size: .large), scheme: .dark)
        // Past the fade's length the opacity is already 1; the clock runs on to the end and `done` follows.
        #expect(png(stage(elapsed: 0.4, reduced: true, done: false), scheme: .dark) == still)
        #expect(png(stage(elapsed: OrbitEntranceFrame.end, reduced: true, done: true), scheme: .dark) == still)
    }
}
