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
        for (label, t) in [("t03", 0.3), ("end", OrbitEntranceFrame.end)] {
            let view = OrbitGauge(mode: .scored(.previewScored), size: .large, caption: .preview, entrance: .assemble, frozenAt: t)
                .padding(40).frame(width: 390).background(Theme.background)
                .environment(\.dynamicTypeSize, .accessibility3).environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: view)
            r.scale = 2
            try r.uiImage?.pngData()?.write(to: URL(fileURLWithPath: "\(dir)/ax3-\(label).png"))
        }
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

    // MARK: layout at accessibility sizes

    /// The rows of a render (by 1 pt rows) that hold anything but the background: where the ring and the caption are.
    private func inkRows(_ gauge: OrbitGauge) -> [Bool] {
        let view = gauge.padding(40).frame(width: 390).background(Color.black)
            .environment(\.dynamicTypeSize, .accessibility3).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.uiImage?.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        let bpp = cg.bitsPerPixel / 8
        return (0..<cg.height).map { y in
            (0..<cg.width).contains { x in
                let o = y * cg.bytesPerRow + x * bpp
                return Int(bytes[o]) + Int(bytes[o + 1]) + Int(bytes[o + 2]) > 30
            }
        }
    }

    @Test func theCaptionIsWhereItIsAtTheEndFromTheFirstFrameAtAX3() {
        let mode = OrbitGaugeMode.scored(.previewScored)
        let still = OrbitGauge(mode: mode, size: .large, caption: .preview)
        let settledRows = inkRows(still)
        let endRows = inkRows(OrbitGauge(mode: mode, size: .large, caption: .preview, entrance: .assemble,
                                         frozenAt: OrbitEntranceFrame.end))
        #expect(!settledRows.isEmpty && settledRows == endRows)
        // Mid-entrance: the dots have landed (0.6 s), the caption is not in yet. Same height, and the ring starts on
        // the same row (the outer track's top), so the stage and the settled drawing share one frame and anchor.
        let landed = inkRows(OrbitGauge(mode: mode, size: .large, caption: .preview, entrance: .assemble, frozenAt: 0.6))
        #expect(landed.count == settledRows.count)
        #expect(landed.firstIndex(of: true) == settledRows.firstIndex(of: true))
        // Nearly done (0.84 s): the caption is on the rows it ends on.
        let late = inkRows(OrbitGauge(mode: mode, size: .large, caption: .preview, entrance: .assemble, frozenAt: 0.84))
        #expect(late.lastIndex(of: true) == settledRows.lastIndex(of: true))
        // The caption is not in before the glide.
        #expect((landed.lastIndex(of: true) ?? 0) < (settledRows.lastIndex(of: true) ?? 0) - 40)
    }
}
