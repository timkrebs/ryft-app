import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// VB1: the launch's matched move lands on Today's header lock-up in a real window. The pure tests (`LaunchMoveTests`)
/// take the conversion as given; this one takes the spaces from the layout the app has: `LaunchHost` over a `TabView`
/// with the real Today. The overlay is held at its landing (`launchOverlayMoment`, 1 ms before done) while the model
/// hides the header's lock-up, and the window is drawn; then the launch is done, the lock-up shows, and it is drawn
/// again. The ink of the mark and of "RYFT" in the header's row must sit where the lock-up's own does, to half a point,
/// at 402 and 390 wide. Before the fix the overlay's mark landed a top inset low, on the greeting, and the row was empty.
@MainActor
@Suite(.serialized) struct LaunchLandingHostedTests {
    private let created = Date(timeIntervalSince1970: 1_792_600_000)

    private func root(_ model: LaunchSequenceModel, landing: Date) -> some View {
        LaunchHost(model: model) {
            TabView {
                TodayView()
                    .tabItem { Label("Today", systemImage: "house.fill") }
            }
        }
        .environment(\.launchOverlayMoment, landing)
        // A hosted window's scene is active, but its phase is not ours to assume: the launch starts on `.active`.
        .environment(\.scenePhase, .active)
    }

    @Test("The mark and the wordmark land on the header's lock-up", arguments: [(402.0, 874.0), (390.0, 844.0)])
    func theLandingIsTheHeadersLockUp(_ size: (width: CGFloat, height: CGFloat)) async throws {
        let clock = TestClock(now: created)
        let model = LaunchSequenceModel(decision: .play(.full), clock: clock, signposts: false)
        // The natural end with a move: the hand-off at 5.2 s, done 0.5 s later; drawn 1 ms before done.
        let landing = created.addingTimeInterval(LaunchFrame.duration + LaunchSequence.Timing.moveHandOff - 0.001)
        try await HostedWindow.run(width: size.width, height: size.height, bottomInset: 0, root(model, landing: landing)) { w in
            try await w.wait("the launch playing with Today's header registered") {
                model.phase == .playing && model.targets[.mark] != nil && model.targets[.wordmark] != nil
                    && model.sequence.startedAt == created
            }
            #expect(w.window.safeAreaInsets.top > 20, "a top inset to get wrong: \(w.window.safeAreaInsets)")
            // Into the hand-off: the model hides the lock-up and the overlay draws it.
            clock.advance(by: .seconds(LaunchFrame.duration + 0.3))
            try await w.wait("handing off with the move") { model.phase == .handingOff && model.hidesHandOffTargets }
            try await w.settle()
            let lockUp = try #require(w.nodes().first { $0.label == "RYFT" && $0.traits.contains(.header) }, "the lock-up").frame
            let row = lockUp.insetBy(dx: -8, dy: -12)
            let inFlight = try ink(w, in: row, name: "in-flight")

            clock.advance(by: .seconds(1))
            try await w.wait("done") { model.phase == .done && !model.hidesHandOffTargets }
            try await w.settle()
            let landed = try ink(w, in: row, name: "landed")

            let markAtLanding = try #require(inFlight.mark, "the overlay drew no mark in the header's row \(row)")
            let markInHeader = try #require(landed.mark, "the header's mark in \(row)")
            #expect(close(markAtLanding, markInHeader), "the mark lands at \(markAtLanding), the header's is \(markInHeader)")
            let wordmarkAtLanding = try #require(inFlight.wordmark, "the overlay drew no wordmark in \(row)")
            let wordmarkInHeader = try #require(landed.wordmark, "the header's wordmark in \(row)")
            #expect(close(wordmarkAtLanding, wordmarkInHeader),
                    "\"RYFT\" lands at \(wordmarkAtLanding), the header's is \(wordmarkInHeader)")
            if let dir = ProcessInfo.processInfo.environment["PR4_LANDING_DIR"] {
                let line = "\(Int(size.width)) wide: lock-up \(lockUp), mark at landing \(markAtLanding), header mark \(markInHeader), "
                    + "wordmark at landing \(wordmarkAtLanding), header wordmark \(wordmarkInHeader)\n"
                try line.write(toFile: "\(dir)/landing-\(Int(size.width)).txt", atomically: true, encoding: .utf8)
            }
            // And the lock-up's own frame: the mark is its leading 26 pt, centred on it.
            #expect(abs(markInHeader.midY - lockUp.midY) < 1 && abs(markInHeader.minX - lockUp.minX) < 1.5,
                    "the measured mark \(markInHeader) is the lock-up's \(lockUp)")
        }
    }

    /// Two ink boxes agree to half a point on every edge.
    private func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 0.5 && abs(a.maxX - b.maxX) <= 0.5 && abs(a.minY - b.minY) <= 0.5 && abs(a.maxY - b.maxY) <= 0.5
    }

    /// The ink in `rect` (window points), split at the first gap of 5 pt or more: the mark, then the wordmark. With
    /// `PR4_LANDING_DIR` set the drawn window goes there as `landing-<width>-<name>.png`.
    private func ink(_ w: HostedWindow, in rect: CGRect, name: String) throws -> (mark: CGRect?, wordmark: CGRect?) {
        let scale: CGFloat = 3
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
            w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
        }
        let cg = try #require(image.cgImage)
        if let dir = ProcessInfo.processInfo.environment["PR4_LANDING_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? image.pngData()?.write(to: URL(fileURLWithPath: "\(dir)/landing-\(Int(w.window.bounds.width))-\(name).png"))
        }
        let width = cg.width, height = cg.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        }
        let x0 = max(Int(rect.minX * scale), 0), x1 = min(Int(rect.maxX * scale), width - 1)
        let y0 = max(Int(rect.minY * scale), 0), y1 = min(Int(rect.maxY * scale), height - 1)
        // The screen's colour, from the row's empty right end (the lock-up is leading, the calendar far right).
        let ground = pixel(min(x1 + Int(40 * scale), width - 1), (y0 + y1) / 2)
        func inked(_ x: Int, _ y: Int) -> Bool {
            let p = pixel(x, y)
            return max(abs(p.0 - ground.0), abs(p.1 - ground.1), abs(p.2 - ground.2)) > 60
        }
        var columns: [Int: (Int, Int)] = [:]
        for x in x0...x1 {
            for y in y0...y1 where inked(x, y) {
                let span = columns[x] ?? (y, y)
                columns[x] = (min(span.0, y), max(span.1, y))
            }
        }
        let xs = columns.keys.sorted()
        guard !xs.isEmpty else { return (nil, nil) }
        // The mark's columns run without a break; the first gap of 5 pt is the 10 pt between the mark and "RYFT".
        var split = xs.count
        for i in 1..<max(xs.count, 1) where xs[i] - xs[i - 1] >= Int(5 * scale) {
            split = i
            break
        }
        func box(_ part: ArraySlice<Int>) -> CGRect? {
            guard let lo = part.first, let hi = part.last else { return nil }
            let top = part.compactMap { columns[$0]?.0 }.min() ?? 0, bottom = part.compactMap { columns[$0]?.1 }.max() ?? 0
            return CGRect(x: CGFloat(lo) / scale, y: CGFloat(top) / scale, width: CGFloat(hi - lo + 1) / scale,
                          height: CGFloat(bottom - top + 1) / scale)
        }
        return (box(xs[0..<split]), split < xs.count ? box(xs[split...]) : nil)
    }
}
