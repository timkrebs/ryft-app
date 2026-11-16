import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The launch screen drawn (docs/work/2026-11-16-nocturne/design.md §P3-4 "Layout", §P3-8 cases 31 and 32; plan.md L8):
/// where the mark, the wordmark and the tagline sit, and that the last frame is the static mark in pixels. The layout is
/// checked twice: the pure rule (`markRect(in:)`, `taglineBottomInset(safeAreaBottom:)`) and the pixels `LaunchStage`
/// really draws, because a rule nobody uses proves nothing. Dark, `ImageRenderer`, no fonts assumed: the text is found by
/// its ink, not by its glyphs.
@MainActor
@Suite("Launch: the stage")
struct LaunchStageTests {
    private typealias Frame = LaunchFrame
    private typealias Stage = LaunchStage
    private static let scale: CGFloat = 3

    // MARK: the rule

    @Test func theLayoutConstants() {
        #expect(Stage.markSide == 184 && Stage.markLift == 40)
        #expect(Stage.wordmarkSize == 22 && Stage.wordmarkGap == 28)
        #expect(Stage.taglineBottom == 64 && Stage.taglineAboveInset == 24 && Stage.taglineMinGap == 16)
    }

    private struct Screen: CustomTestStringConvertible, Sendable {
        let width: CGFloat
        let height: CGFloat
        var testDescription: String { "\(Int(width)) x \(Int(height))" }
        var size: CGSize { CGSize(width: width, height: height) }
    }

    nonisolated private static let screens = [Screen(width: 402, height: 874), Screen(width: 440, height: 956),
                                  Screen(width: 390, height: 844), Screen(width: 375, height: 667)]

    @Test("The mark's box is centred and 40 pt above the middle", arguments: screens)
    private func theMarkRectIsCentredAndFortyAboveTheMiddle(_ screen: Screen) {
        let rect = Stage.markRect(in: screen.size)
        #expect(rect.size == CGSize(width: 184, height: 184))
        #expect(rect.midX == screen.width / 2, "centred")
        #expect(rect.midY == screen.height / 2 - 40, "40 pt above the middle")
        // The wordmark's line box starts 28 pt under the 184 box.
        #expect(rect.maxY + Stage.wordmarkGap == screen.height / 2 - 40 + 92 + 28)
    }

    @Test func theDesignsOwnNumbers() {
        // 390 x 844: mark centre y 382, wordmark top 502, tagline bottom 780. 375 x 667: 293.5 / 413.5 / 603.
        let boards: [(CGSize, CGFloat, CGFloat, CGFloat)] = [(CGSize(width: 390, height: 844), 382, 502, 780),
                                                              (CGSize(width: 375, height: 667), 293.5, 413.5, 603)]
        for (size, centre, wordmark, tagline) in boards {
            let rect = Stage.markRect(in: size)
            #expect(rect.midY == centre && rect.maxY + Stage.wordmarkGap == wordmark, "\(size)")
            #expect(size.height - Stage.taglineBottomInset(safeAreaBottom: 34) == tagline, "\(size)")
        }
    }

    @Test("The tagline sits max(64, inset + 24) above the bottom", arguments: [
        (0.0, 64.0), (20, 64), (34, 64), (39.9, 64), (40, 64), (40.5, 64.5), (41, 65), (50, 74), (59, 83), (100, 124),
    ])
    private func theTaglineInset(_ safeAreaBottom: Double, _ expected: Double) {
        #expect(Stage.taglineBottomInset(safeAreaBottom: CGFloat(safeAreaBottom)) == CGFloat(expected))
    }

    // MARK: pixels

    private struct Raster {
        let width: Int, height: Int, scale: CGFloat, bytes: [UInt8]
        let background: (Int, Int, Int)

        init?(_ cg: CGImage, scale: CGFloat) {
            width = cg.width
            height = cg.height
            self.scale = scale
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                      bytesPerRow: cg.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            self.bytes = bytes
            background = (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
        }

        func rgb(x: Int, y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }

        /// The pixel under a point (points of the image).
        func rgb(at p: CGPoint) -> (Int, Int, Int) {
            rgb(x: min(max(Int((p.x * scale).rounded(.down)), 0), width - 1),
                y: min(max(Int((p.y * scale).rounded(.down)), 0), height - 1))
        }

        /// Visibly different from the background: more than a quarter of the way to the ink.
        func isInk(x: Int, y: Int) -> Bool {
            let (r, g, b) = rgb(x: x, y: y)
            return max(abs(r - background.0), abs(g - background.1), abs(b - background.2)) > 40
        }

        /// The ink's bounds in points inside `rect` (points), nil if there is none.
        func inkBounds(in rect: CGRect) -> CGRect? {
            let x0 = max(Int((rect.minX * scale).rounded(.down)), 0), x1 = min(Int((rect.maxX * scale).rounded(.up)), width)
            let y0 = max(Int((rect.minY * scale).rounded(.down)), 0), y1 = min(Int((rect.maxY * scale).rounded(.up)), height)
            var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
            for y in y0..<y1 {
                for x in x0..<x1 where isInk(x: x, y: y) {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= 0 else { return nil }
            return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale, width: CGFloat(maxX - minX + 1) / scale,
                          height: CGFloat(maxY - minY + 1) / scale)
        }

        /// Runs of rows, in points, that hold ink anywhere in `rect`; a gap of `gap` pt or more starts a new run.
        func inkRuns(in rect: CGRect, gap: CGFloat = 8) -> [ClosedRange<CGFloat>] {
            let x0 = max(Int((rect.minX * scale).rounded(.down)), 0), x1 = min(Int((rect.maxX * scale).rounded(.up)), width)
            let y0 = max(Int((rect.minY * scale).rounded(.down)), 0), y1 = min(Int((rect.maxY * scale).rounded(.up)), height)
            var runs: [ClosedRange<CGFloat>] = []
            for y in y0..<y1 where (x0..<x1).contains(where: { isInk(x: $0, y: y) }) {
                let top = CGFloat(y) / scale, bottom = CGFloat(y + 1) / scale
                if let last = runs.last, top - last.upperBound < gap {
                    runs[runs.count - 1] = last.lowerBound...bottom
                } else {
                    runs.append(top...bottom)
                }
            }
            return runs
        }
    }

    private func raster<V: View>(_ view: V, size: CGSize) -> Raster? {
        let content = ZStack { Theme.background; view }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = Self.scale
        return renderer.cgImage.flatMap { Raster($0, scale: Self.scale) }
    }

    private func stage(_ t: Double) -> LaunchStage {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        return LaunchStage(frame: Frame(t: t, palette: .resolved(in: environment)))
    }

    /// Where the last frame's three parts are in a raster: the inner ring's centre (the mark's, ±22 pt), the wordmark's and
    /// the tagline's ink, below the 184 box.
    private struct Layout {
        let ring: CGRect?
        let wordmark: CGRect?
        let tagline: CGRect?
        let runs: [ClosedRange<CGFloat>]
    }

    private func layout(_ raster: Raster, size: CGSize) -> Layout {
        let box = Stage.markRect(in: size)
        let ring = raster.inkBounds(in: CGRect(x: box.midX - 22, y: box.midY - 22, width: 44, height: 44))
        let below = CGRect(x: 0, y: box.maxY, width: size.width, height: size.height - box.maxY)
        let runs = raster.inkRuns(in: below)
        let wordmark = runs.first.flatMap { raster.inkBounds(in: CGRect(x: 0, y: $0.lowerBound, width: size.width, height: $0.upperBound - $0.lowerBound)) }
        let tagline = runs.last.flatMap { raster.inkBounds(in: CGRect(x: 0, y: $0.lowerBound, width: size.width, height: $0.upperBound - $0.lowerBound)) }
        return Layout(ring: ring, wordmark: wordmark, tagline: tagline, runs: runs)
    }

    @Test("The last frame is laid out as the rule says: mark centred, wordmark 28 pt under the box, tagline 64 pt up",
          arguments: screens)
    private func theLastFrameIsWhereTheRuleSays(_ screen: Screen) throws {
        let raster = try #require(raster(stage(1), size: screen.size))
        let layout = layout(raster, size: screen.size)
        let box = Stage.markRect(in: screen.size)

        // The mark: the inner ring is the only thing within 22 pt of its centre, and it is symmetric about it.
        let ring = try #require(layout.ring)
        #expect(abs(ring.midX - box.midX) <= 0.5 && abs(ring.midY - box.midY) <= 0.5,
                "the mark's centre: ring at \(ring), expected \(box.midX), \(box.midY)")
        #expect(abs(ring.midX - screen.width / 2) <= 0.5, "centred on the screen")
        #expect(abs(ring.midY - (screen.height / 2 - 40)) <= 0.5, "40 pt above the middle")

        // Two text runs below the box: "RYFT" and the tagline.
        #expect(layout.runs.count == 2, "runs below the box: \(layout.runs)")
        let wordmark = try #require(layout.wordmark), tagline = try #require(layout.tagline)

        // The wordmark's line box starts 28 pt under the 184 box; its ink starts inside the 22 pt line, not above it.
        let lineTop = box.maxY + 28
        #expect(wordmark.minY >= lineTop - 0.5, "ink above its line box: \(wordmark.minY) < \(lineTop)")
        #expect(wordmark.minY <= lineTop + 14, "ink far below its line box: \(wordmark.minY) > \(lineTop)")
        #expect(wordmark.height > 8 && wordmark.height < 24, "a 22 pt wordmark, not a placeholder: \(wordmark)")
        #expect(abs(wordmark.midX - screen.width / 2) <= 1.5, "the wordmark's ink is centred: \(wordmark.midX)")

        // The tagline's line box ends 64 pt above the bottom; its ink ends within a descender of that.
        let tagBottom = screen.height - 64
        #expect(tagline.maxY <= tagBottom + 0.5, "ink below its box: \(tagline.maxY) > \(tagBottom)")
        #expect(tagline.maxY >= tagBottom - 8, "ink far above its box: \(tagline.maxY) < \(tagBottom)")
        #expect(abs(tagline.midX - screen.width / 2) <= 1.5, "the tagline is centred: \(tagline.midX)")
        #expect(tagline.minY > wordmark.maxY + 16, "the tagline never closer than 16 pt to the wordmark")
    }

    /// Dark gaps are real: the wordmark and the tagline are not drawn before they arrive.
    @Test func theTextArrivesLast() throws {
        let size = CGSize(width: 402, height: 874)
        let before = try #require(raster(stage(0.7), size: size))
        #expect(layout(before, size: size).runs.isEmpty, "no text at t = 0.7")
        let wordmarkOnly = try #require(raster(stage(0.78), size: size))
        #expect(layout(wordmarkOnly, size: size).runs.count == 1, "the wordmark arrives before the tagline")
        let both = try #require(raster(stage(1), size: size))
        #expect(layout(both, size: size).runs.count == 2)
        let empty = try #require(raster(stage(0), size: size))
        #expect(empty.inkBounds(in: CGRect(origin: .zero, size: size)) == nil, "t = 0 draws nothing")
    }

    // MARK: the safe area

    /// The tagline's ink bottom with a home indicator of `inset` pt, drawn as `LaunchOverlay` draws its stage: on the
    /// background, in `LaunchFullScreen`, in a window whose bottom safe area is `inset`.
    private func taglineBottom(inset: Double) async throws -> CGFloat {
        let size = CGSize(width: 402, height: 874)
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let palette = Frame.Palette.resolved(in: environment)
        let content = LaunchFullScreen { safeAreaBottom in
            ZStack { Theme.background; LaunchStage(frame: Frame(t: 1, palette: palette), safeAreaBottom: safeAreaBottom) }
        }
        var found: Raster?
        try await HostedWindow.run(width: size.width, height: size.height, bottomInset: inset, content) { w in
            // A window the size of the screen brings the device's own inset (34 on a notched iPhone): make the total `inset`.
            w.window.layoutIfNeeded()
            let device = w.host.view.safeAreaInsets.bottom - w.host.additionalSafeAreaInsets.bottom
            w.host.additionalSafeAreaInsets.bottom = max(inset - device, 0)
            try await w.settle()
            let total = Double(w.host.view.safeAreaInsets.bottom)
            #expect(total == inset, "the window's bottom safe area: \(total), the device's \(device)")
            let format = UIGraphicsImageRendererFormat()
            format.scale = Self.scale
            format.opaque = true
            let image = UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
                w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
            }
            found = image.cgImage.flatMap { Raster($0, scale: Self.scale) }
        }
        let raster = try #require(found)
        return try #require(layout(raster, size: size).tagline).maxY
    }

    /// 34 pt is every notched iPhone: 34 + 24 = 58 is under 64, so the tagline is 64 up with or without the rule.
    @Test func theTaglineIsSixtyFourUpOverAHomeIndicator() async throws {
        let bottom = try await taglineBottom(inset: 34)
        #expect(bottom <= 874 - 64 + 0.5 && bottom >= 874 - 64 - 8, "ink ends at \(bottom), box ends at 810")
    }

    /// Above 40 pt the inset wins: 60 + 24 = 84 up. The stage once read its own geometry's inset under the overlay's
    /// `.ignoresSafeArea()`, which is 0, and stayed at 64 (T3.4); `LaunchFullScreen` reads it outside and passes it in.
    @Test func theTaglineClearsALargeInset() async throws {
        let bottom = try await taglineBottom(inset: 60)
        #expect(bottom <= 874 - 84 + 0.5 && bottom >= 874 - 84 - 8, "inset 60: ink ends at \(bottom), box ends at 790")
    }

    // MARK: t = 1 is the static mark in pixels (case 31)

    /// design.md asks for 2/255 per channel. Per pixel that holds in every flat area, but the two renderers (a `Canvas` fill
    /// and a `Shape` fill of one union path) antialias the curves' edges differently: 1.6 % of the pixels, all on an edge,
    /// by up to 59/255. So the guard is geometry to one device pixel: every pixel of the stage's render lies within 2/255 of
    /// the range its 3 x 3 neighbourhood spans in the reference. A mark moved by 0.4 pt, or a dot or arc end that is a degree
    /// off, fails it; an edge pixel shaded differently does not. (The angles themselves are `LaunchFrameTests`, to 1e-6.)
    @Test func theLastFrameIsTheStaticMarkToOneDevicePixel() throws {
        // 402 x 874 puts the 184 box on whole points, so the two renders share a pixel grid.
        let size = CGSize(width: 402, height: 874)
        let box = Stage.markRect(in: size)
        let launched = try #require(raster(stage(1), size: size))
        let reference = try #require(raster(RyftMark().frame(width: 184, height: 184).foregroundStyle(Theme.textPrimary),
                                            size: CGSize(width: 184, height: 184)))
        let (dx, dy) = (Int(box.minX * Self.scale), Int(box.minY * Self.scale))
        var inked = 0, outside = 0, exact = 0, firstBad = ""
        for y in 0..<reference.height {
            for x in 0..<reference.width {
                let got = launched.rgb(x: x + dx, y: y + dy)
                var low = (255, 255, 255), high = (0, 0, 0)
                for ny in max(y - 1, 0)...min(y + 1, reference.height - 1) {
                    for nx in max(x - 1, 0)...min(x + 1, reference.width - 1) {
                        let n = reference.rgb(x: nx, y: ny)
                        low = (min(low.0, n.0), min(low.1, n.1), min(low.2, n.2))
                        high = (max(high.0, n.0), max(high.1, n.1), max(high.2, n.2))
                    }
                }
                let inside = got.0 >= low.0 - 2 && got.0 <= high.0 + 2 && got.1 >= low.1 - 2 && got.1 <= high.1 + 2
                    && got.2 >= low.2 - 2 && got.2 <= high.2 + 2
                if !inside {
                    outside += 1
                    if firstBad.isEmpty { firstBad = "(\(x), \(y)) got \(got) outside \(low)...\(high)" }
                }
                let want = reference.rgb(x: x, y: y)
                if abs(want.0 - got.0) <= 2 && abs(want.1 - got.1) <= 2 && abs(want.2 - got.2) <= 2 { exact += 1 }
                if reference.isInk(x: x, y: y) { inked += 1 }
            }
        }
        let total = reference.width * reference.height
        #expect(inked > 2_000, "the reference draws a mark: \(inked) ink pixels")
        #expect(outside == 0, "\(outside) pixels off the mark's geometry, first \(firstBad)")
        #expect(Double(exact) / Double(total) > 0.97, "within 2/255 for \(exact) of \(total) pixels")
    }

    // MARK: t = 0.26: the hold, at the board's points

    @Test func theHoldDrawsThreeArcsThreeDotsAndTheTracks() throws {
        let size = CGSize(width: 402, height: 874)
        let box = Stage.markRect(in: size)
        let raster = try #require(raster(stage(0.26), size: size))
        let f = Frame(t: 0.26, palette: LaunchFrameTests.palette)
        let unit = Stage.markSide / 100
        func point(_ radius: Double, _ degrees: Double) -> CGPoint {
            let r = degrees * .pi / 180
            return CGPoint(x: box.midX + CGFloat(radius * cos(r)) * unit, y: box.midY + CGFloat(radius * sin(r)) * unit)
        }
        func within(_ got: (Int, Int, Int), _ colour: Frame.RGB, _ tolerance: Int = 2) -> Bool {
            let want = [colour.r, colour.g, colour.b].map { Int(($0 * 255).rounded()) }
            return abs(got.0 - want[0]) <= tolerance && abs(got.1 - want[1]) <= tolerance && abs(got.2 - want[2]) <= tolerance
        }
        let g = RyftMarkGeometry.self
        let p = LaunchFrameTests.palette
        // The centre pixel of each dot is its metric colour.
        #expect(within(raster.rgb(at: point(g.outer.radius, f.strain.dot)), p.strain), "strain dot")
        #expect(within(raster.rgb(at: point(g.middle.radius, f.sleep.dot)), p.sleep), "sleep dot")
        #expect(within(raster.rgb(at: point(g.middle.radius, f.recovery.dot)), p.recovery), "recovery dot")
        // The arcs are there too, between their ends: strain at 20 deg, sleep at 0 deg, recovery at 200 deg (stored 200 + 0).
        #expect(within(raster.rgb(at: point(g.outer.radius, 20)), p.strain), "strain arc")
        #expect(within(raster.rgb(at: point(g.middle.radius, 0)), p.sleep), "sleep arc")
        #expect(within(raster.rgb(at: point(g.middle.radius, 200)), p.recovery), "recovery arc")
        // Where no arc is (strain: 150 deg is past its dot, 108.55 + 24 + 14), the track is the ink at 10 %.
        let bg = raster.background
        let track = (0..<3).map { c -> Int in
            let ink = [p.ink.r, p.ink.g, p.ink.b][c] * 255
            let base = [bg.0, bg.1, bg.2][c]
            return Int((Double(base) * 0.9 + ink * 0.1).rounded())
        }
        let sample = raster.rgb(at: point(g.outer.radius, 150))
        #expect(abs(sample.0 - track[0]) <= 3 && abs(sample.1 - track[1]) <= 3 && abs(sample.2 - track[2]) <= 3,
                "strain track at 150 deg: \(sample), expected \(track)")
        // The inner ring is lit to 84 % in the ink: its start (12 o'clock, just clockwise) and 3 o'clock.
        #expect(within(raster.rgb(at: point(g.innerRadius, -80)), p.ink), "inner ring, lit")
        #expect(within(raster.rgb(at: point(g.innerRadius, 0)), p.ink), "inner ring, lit")
    }
}
