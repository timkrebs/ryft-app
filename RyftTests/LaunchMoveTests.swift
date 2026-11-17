import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The launch's matched move into Today's header (design.md §P4-7, tests 37–45; L15, L25): the mark and "RYFT" fly from
/// the launch layout into the header's lock-up instead of fading. Pure first: the rect interpolation, the safe-area
/// conversion, the move's timing and decision on `LaunchSequence`, the clearance in flight; then the model on a test clock
/// (the reveal, the hidden lock-up) and one render of the landing against `RyftMark()`.
@MainActor
@Suite("Launch: the matched move")
struct LaunchMoveTests {
    private let created = Date(timeIntervalSince1970: 1_792_600_000)
    private let e = 0.001
    private typealias G = RyftMarkGeometry

    private func at(_ seconds: TimeInterval) -> Date { created.addingTimeInterval(seconds) }

    private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-3) -> Bool { abs(a - b) <= tolerance }

    /// The board's launch layout on a 390 × 844 screen and the header mark under a 59 pt top inset.
    private let start = CGRect(x: 103, y: 290, width: 184, height: 184)
    private let target = CGRect(x: 20, y: 66, width: 26, height: 26)

    /// Active and drawing at 0.1 s; `target`: Today's header registered a mark while it played.
    private func playing(_ variant: LaunchSequence.Variant = .full, target: Bool = true) -> LaunchSequence {
        var sequence = LaunchSequence(decision: .play(variant), createdAt: created)
        sequence.send(.scene(.active), at: at(0.1))
        sequence.send(.firstFrame, at: at(0.1))
        if target { sequence.setMarkTarget(true, at: at(0.2)) }
        return sequence
    }

    // MARK: 37. the rect interpolation

    @Test func theRectIsLerpedComponentByComponent() {
        #expect(LaunchFrame.rect(from: start, to: target, progress: 0) == start)
        #expect(LaunchFrame.rect(from: start, to: target, progress: 1) == target)
        let mid = LaunchFrame.rect(from: start, to: target, progress: 0.5)
        #expect(close(mid.minX, 61.5) && close(mid.minY, 178) && close(mid.width, 105) && close(mid.height, 105))
        #expect(close(mid.midX, (start.midX + target.midX) / 2) && close(mid.midY, (start.midY + target.midY) / 2),
                "the centre moves on a straight line")
    }

    @Test func withE1TheBoardsNumbers() {
        let u25 = LaunchFrame.markMoveProgress(0.25), u50 = LaunchFrame.markMoveProgress(0.5)
        #expect(close(u25, 0.2068, 1e-4) && close(u50, 0.7912, 1e-4))
        let quarter = LaunchFrame.rect(from: start, to: target, progress: u25)
        #expect(close(quarter.width, 151.3, 0.05) && quarter.width == quarter.height)
        let half = LaunchFrame.rect(from: start, to: target, progress: u50)
        #expect(close(half.minX, 37.3, 0.05) && close(half.minY, 112.8, 0.05) && close(half.width, 59.0, 0.05))
    }

    // MARK: 38. the safe-area conversion

    @Test func aLaunchSpaceFrameMovesByTheLeadingAndTopInsets() {
        let header = CGRect(x: 20, y: 7, width: 26, height: 26)
        let insets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        #expect(LaunchStage.overlayRect(fromLaunch: header, safeArea: insets) == target)
        #expect(LaunchStage.overlayRect(fromLaunch: header, safeArea: EdgeInsets()) == header, "no insets: the identity")
        let landscape = EdgeInsets(top: 0, leading: 47, bottom: 21, trailing: 47)
        #expect(LaunchStage.overlayRect(fromLaunch: header, safeArea: landscape) == header.offsetBy(dx: 47, dy: 0))
    }

    @Test func theLayoutStartsAtTheLaunchAndLandsOnTheHeader() {
        let screen = CGSize(width: 390, height: 844)
        let insets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        let wordmark = CGRect(x: 56, y: 9.875, width: 52, height: 20.25)
        let palette = LaunchFrame.Palette(strain: .init(r: 0, g: 0, b: 1), sleep: .init(r: 1, g: 0, b: 1),
                                          recovery: .init(r: 0, g: 1, b: 0), ink: .init(r: 1, g: 1, b: 1))
        func layout(_ time: Double) -> LaunchStage.MoveLayout {
            LaunchStage.moveLayout(LaunchStage.Move(mark: CGRect(x: 20, y: 7, width: 26, height: 26), wordmark: wordmark,
                                                    time: time, taglineOpacity: 1, palette: palette),
                                   screen: screen, safeArea: insets)
        }
        #expect(layout(0).mark == LaunchStage.markRect(in: screen) && layout(0).mark == start)
        #expect(layout(0).wordmarkCentre == LaunchStage.wordmarkCentre(in: screen) && layout(0).wordmarkSize == 22)
        #expect(layout(1).mark == target)
        #expect(layout(1).wordmarkCentre == CGPoint(x: 82, y: 59 + 20) && layout(1).wordmarkSize == 15)
    }

    // MARK: 39. moveProgress

    @Test func theMoveRunsHalfASecondAtTheNaturalEnd() throws {
        let sequence = playing()
        #expect(sequence.movesMark)
        let handOff = try #require(sequence.handOffStart)
        #expect(close(handOff.timeIntervalSince(at(0.1)), 5.2, 1e-6))
        #expect(sequence.handOffDuration == LaunchSequence.Timing.moveHandOff && sequence.handOffDuration == 0.5)
        let done = try #require(sequence.doneAt)
        #expect(close(done.timeIntervalSince(handOff), 0.5, 1e-6))
        #expect(sequence.moveProgress(at: handOff.addingTimeInterval(-1)) == 0, "0 before the hand-off")
        #expect(sequence.moveTime(at: handOff) == 0 && sequence.moveProgress(at: handOff) == 0)
        for elapsed in stride(from: 0.0, through: 0.5, by: 0.05) {
            let date = handOff.addingTimeInterval(elapsed)
            #expect(close(sequence.moveTime(at: date), elapsed / 0.5, 1e-6), "linear time at \(elapsed)")
            // A `Date` at this epoch rounds to about 1e-7 s, so E1 is compared a little looser than the curve's own 1e-9.
            #expect(close(sequence.moveProgress(at: date), LaunchFrame.Easing.e1(elapsed / 0.5), 1e-5), "E1 at \(elapsed)")
        }
        #expect(sequence.moveProgress(at: done) == 1 && sequence.moveProgress(at: done.addingTimeInterval(1)) == 1, "1 after")
        #expect(sequence.phase(at: done.addingTimeInterval(-e)) == .handingOff && sequence.phase(at: done) == .done)
    }

    @Test func aTapAfterTheMarkHasFormedMovesItInAQuarterSecond() throws {
        var sequence = playing()
        sequence.send(.tap, at: at(0.1 + 5.2 * 0.9))
        #expect(sequence.movesMark, "the mark stands at 0.9")
        let handOff = try #require(sequence.handOffStart)
        #expect(sequence.handOffDuration == 0.25)
        let done = try #require(sequence.doneAt)
        #expect(close(done.timeIntervalSince(handOff), 0.25, 1e-6))
        #expect(close(sequence.moveTime(at: handOff.addingTimeInterval(0.125)), 0.5, 1e-6))
    }

    @Test func withoutAMoveTheHandOffKeepsPR3sFades() throws {
        let natural = playing(target: false)
        #expect(!natural.movesMark && natural.handOffDuration == 0.4)
        let reduced = playing(.reduced)
        #expect(!reduced.movesMark && reduced.handOffDuration == 0.25)
    }

    // MARK: 40. the wordmark

    @Test func theWordmarkStartsLaterAndLandsWithTheMark() {
        #expect(LaunchFrame.wordmarkMoveProgress(0) == 0)
        #expect(LaunchFrame.wordmarkMoveProgress(0.15) == 0, "it has not moved at τ 0.15")
        #expect(LaunchFrame.wordmarkMoveProgress(0.1) == 0)
        #expect(LaunchFrame.wordmarkMoveProgress(1) == 1 && LaunchFrame.markMoveProgress(1) == 1, "both land at τ 1")
        for tau in stride(from: 0.0, through: 1.0, by: 0.05) {
            let expected = LaunchFrame.Easing.e1(min(max((tau - 0.15) / 0.85, 0), 1))
            #expect(close(LaunchFrame.wordmarkMoveProgress(tau), expected, 1e-12), "τ \(tau)")
        }
        #expect(LaunchFrame.wordmarkMoveSize(0, from: 22) == 22 && LaunchFrame.wordmarkMoveSize(1, from: 22) == 15)
        // The tracking is the last frame's 0.32 em throughout; it is not animated in flight.
        #expect(LaunchFrame(t: 1, palette: Self.palette, side: 80).wordmarkTracking == Double(Wordmark.tracking))
        #expect(Wordmark.tracking == 0.32)
    }

    // MARK: 41. clearance in flight

    @Test func theWordmarkNeverComesWithin4ptOfTheMark() {
        let screen = CGSize(width: 390, height: 844)
        let insets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        let move = { (time: Double) in
            LaunchStage.Move(mark: CGRect(x: 20, y: 7, width: 26, height: 26), wordmark: nil, time: time,
                             taglineOpacity: 1, palette: Self.palette)
        }
        var least = Double.infinity
        for step in 0...50 {
            let time = Double(step) / 50
            let layout = LaunchStage.moveLayout(move(time), screen: screen, safeArea: insets)
            let side = Double(layout.mark.width)
            let metrics = G.metrics(forSide: side)
            // The mark's outer ink from its centre: the outer ring (44 % of the side) plus a dot's radius.
            let reach = 0.44 * side + metrics.dotRadius * side / G.box
            // The wordmark's ink: four 0.62 em advances and three 0.32 em trackings wide, its line box high.
            let size = layout.wordmarkSize
            let ink = CGRect(x: layout.wordmarkCentre.x - LaunchStage.wordmarkInkWidth(size) / 2,
                             y: layout.wordmarkCentre.y - LaunchStage.wordmarkLineHeight(size) / 2,
                             width: LaunchStage.wordmarkInkWidth(size), height: LaunchStage.wordmarkLineHeight(size))
            let centre = CGPoint(x: layout.mark.midX, y: layout.mark.midY)
            let dx = max(ink.minX - centre.x, 0, centre.x - ink.maxX)
            let dy = max(ink.minY - centre.y, 0, centre.y - ink.maxY)
            let clearance = Double(hypot(dx, dy)) - reach
            least = min(least, clearance)
            #expect(clearance >= 4, "τ \(time): \(clearance) pt")
        }
        #expect(least < 20, "the check bites: the two pass close (\(least) pt)")
    }

    // MARK: 42. the mark's metrics in flight

    @Test(arguments: [(184.0, 5.81, 11.04, 14.02), (80, 2.53, 4.80, 14.02), (40, 1.26, 2.40, 14.02), (26, 1.25, 1.92, 17.92)])
    func strokeAndDotsFollowTheSide(_ side: Double, _ stroke: Double, _ dot: Double, _ gap: Double) {
        let metrics = G.metrics(forSide: side)
        #expect(close(metrics.stroke * side / G.box, stroke, 0.006), "stroke at \(side)")
        #expect(close(metrics.dotRadius * side / G.box, dot, 0.006), "dot at \(side)")
        #expect(close(G.halfGap(ringRadius: G.outer.radius, metrics: metrics), gap, 0.006), "outer gap at \(side)")
    }

    @Test func theLandingFrameIsTheMarkAt26() {
        let frame = LaunchFrame(t: 1, palette: Self.palette, side: 26)
        #expect(frame.side == 26 && frame.groupOpacity == 1 && frame.trackOpacity == 0 && frame.innerSweep == 360)
        #expect(frame.strain.colour == Self.palette.ink && frame.sleep.colour == Self.palette.ink)
    }

    /// The overlay's last frame and the header's `RyftMark()` at 26 pt, rendered at 3x on the background. As in
    /// `LaunchStageTests` (case 31), a `Canvas` fill of the parts and a `Shape` fill of one union path antialias the curves'
    /// edges differently, so "within 2/255" is held per pixel against the reference's 3 × 3 neighbourhood (geometry to one
    /// device pixel), and most pixels match outright.
    @Test func theLandingRendersAsTheHeaderMark() throws {
        func pixels(_ view: some View) throws -> [UInt8] {
            let renderer = ImageRenderer(content: view.frame(width: 26, height: 26).background(Theme.background)
                .environment(\.colorScheme, .dark))
            renderer.scale = 3
            let image = try #require(renderer.cgImage)
            try #require(image.width == 78 && image.height == 78)
            var data = [UInt8](repeating: 0, count: 78 * 78 * 4)
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(data: &data, width: 78, height: 78, bitsPerComponent: 8, bytesPerRow: 78 * 4,
                                                 space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 78, height: 78))
            return data
        }
        let landing = try pixels(LandingMark())
        let header = try pixels(RyftMark().foregroundStyle(Theme.textPrimary))
        func channel(_ data: [UInt8], _ x: Int, _ y: Int, _ c: Int) -> Int { Int(data[(y * 78 + x) * 4 + c]) }
        var outside = 0, exact = 0, inked = 0, firstBad = ""
        for y in 0..<78 {
            for x in 0..<78 {
                var inside = true, same = true
                for c in 0..<3 {
                    let got = channel(landing, x, y, c)
                    var low = 255, high = 0
                    for ny in max(y - 1, 0)...min(y + 1, 77) {
                        for nx in max(x - 1, 0)...min(x + 1, 77) {
                            low = min(low, channel(header, nx, ny, c))
                            high = max(high, channel(header, nx, ny, c))
                        }
                    }
                    if got < low - 2 || got > high + 2 { inside = false }
                    if abs(got - channel(header, x, y, c)) > 2 { same = false }
                }
                if !inside {
                    outside += 1
                    if firstBad.isEmpty { firstBad = "(\(x), \(y))" }
                }
                if same { exact += 1 }
                if channel(header, x, y, 0) > 128 { inked += 1 }
            }
        }
        #expect(inked > 300, "the reference draws a mark: \(inked) ink pixels")
        #expect(outside == 0, "\(outside) pixels off the mark's geometry, first \(firstBad)")
        // At 26 pt the edges are about seven times the share of the pixels they are at 184 (1.6 % differ there): 86 % match.
        #expect(Double(exact) / Double(78 * 78) > 0.8, "within 2/255 for \(exact) of \(78 * 78) pixels")
    }

    /// The overlay's drawing of the last frame in a 26 pt box, as `LaunchStage` draws it in flight.
    private struct LandingMark: View {
        @Environment(\.self) private var environment

        var body: some View {
            Canvas { context, size in
                let frame = LaunchFrame(t: 1, palette: .resolved(in: environment), side: Double(size.width))
                LaunchStage.drawMark(frame, in: CGRect(origin: .zero, size: size), context: &context)
            }
        }
    }

    // MARK: 43. the decision

    @Test func itMovesOnlyForTheFullVariantAFormedMarkAndATarget() {
        #expect(playing().movesMark, "full, natural end, a target")
        #expect(!playing(.reduced).movesMark, "the reduced variant cross-fades")
        #expect(!playing(target: false).movesMark, "no target (another root): a cross-fade")
        var early = playing()
        early.send(.tap, at: at(0.1 + 5.2 * 0.5))
        #expect(!early.movesMark, "a skip at 0.5: the mark hasn't formed")
        var formed = playing()
        formed.send(.tap, at: at(0.1 + 5.2 * LaunchSequence.markFormed + e))
        #expect(formed.movesMark, "a tap once the mark has formed (≥ 0.86)")
        // Only a `.mark` target counts; it is the one `setMarkTarget` takes (the model passes the mark's).
        var gone = playing()
        gone.setMarkTarget(false, at: at(1))
        #expect(!gone.movesMark, "the target left before the hand-off")
    }

    @Test func theDecisionIsTakenOnceAtTheHandOff() throws {
        var sequence = playing()
        let handOff = try #require(sequence.handOffStart)
        // After the hand-off started, the target going (or coming) changes nothing.
        sequence.setMarkTarget(false, at: handOff.addingTimeInterval(0.1))
        #expect(sequence.movesMark && sequence.hasMarkTarget)
        var none = playing(target: false)
        none.setMarkTarget(true, at: handOff.addingTimeInterval(0.1))
        #expect(!none.movesMark)
        // Armed: a header that is already laid out before the first `.active` counts.
        var armed = LaunchSequence(decision: .play(.full), createdAt: created)
        armed.setMarkTarget(true, at: at(0.01))
        armed.send(.scene(.active), at: at(0.1))
        armed.send(.firstFrame, at: at(0.1))
        #expect(armed.movesMark)
    }

    // MARK: 44, 45. the model: reveal, layers, the hidden lock-up

    private let clock = TestClock()

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    private func advance(_ seconds: TimeInterval) async {
        clock.advance(by: .seconds(seconds))
        await settle()
    }

    private func started(_ variant: LaunchSequence.Variant = .full, target: Bool = true) async -> LaunchSequenceModel {
        let model = LaunchSequenceModel(decision: .play(variant), clock: clock, signposts: false)
        if target {
            model.register(.mark, CGRect(x: 20, y: 7, width: 26, height: 26))
            model.register(.wordmark, CGRect(x: 56, y: 9.875, width: 52, height: 20.25))
        }
        model.send(.scene(.active))
        model.send(.firstFrame)
        await settle()
        return model
    }

    @Test func revealsRootHoldsUntilTheLockUpLands() async {
        let model = await started()
        #expect(model.coversRoot && model.revealsRoot && !model.hidesHandOffTargets)
        await advance(5.2 + e)
        #expect(model.phase == .handingOff && model.movesMark)
        #expect(!model.coversRoot, "taps and VoiceOver reach Today from the hand-off's start")
        #expect(model.revealsRoot, "the gauge waits for the landing")
        #expect(model.hidesHandOffTargets, "the overlay draws the lock-up in flight")
        await advance(0.4)
        #expect(model.phase == .handingOff && model.revealsRoot, "0.5 s, not PR 3's 0.4")
        await advance(0.1)
        #expect(model.phase == .done && !model.revealsRoot && !model.hidesHandOffTargets && !model.isOnScreen)
    }

    @Test func withoutAMoveRevealsRootIsCoversRoot() async {
        for (variant, target) in [(LaunchSequence.Variant.full, false), (.reduced, true)] {
            let model = await started(variant, target: target)
            #expect(model.revealsRoot == model.coversRoot)
            await advance(variant == .full ? 5.2 + e : 1.0 + e)
            #expect(model.phase == .handingOff && !model.movesMark)
            #expect(model.revealsRoot == model.coversRoot && !model.revealsRoot && !model.hidesHandOffTargets)
            await advance(0.5)
            #expect(model.phase == .done && model.revealsRoot == model.coversRoot)
        }
    }

    @Test func theTargetsAreTakenOnlyWhileTheLaunchIsOnScreen() async {
        let model = await started()
        #expect(model.targets[.mark] == CGRect(x: 20, y: 7, width: 26, height: 26) && model.targets[.wordmark] != nil)
        await advance(5.2 + e)
        // In flight a target that goes keeps its last frame: the lock-up still lands.
        model.register(.mark, nil)
        #expect(model.targets[.mark] != nil && model.movesMark)
        await advance(0.6)
        model.register(.mark, CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(model.targets[.mark] == CGRect(x: 20, y: 7, width: 26, height: 26), "nothing after done")
    }

    @Test func theBackgroundAndTaglineFadeInAQuarterSecondTheLockUpStays() throws {
        let sequence = playing()
        let handOff = try #require(sequence.handOffStart)
        #expect(sequence.moveFade(at: handOff.addingTimeInterval(-0.1)) == 1)
        #expect(sequence.moveFade(at: handOff) == 1)
        #expect(close(sequence.moveFade(at: handOff.addingTimeInterval(0.125)),
                      1 - LaunchFrame.Easing.easeOut(0.5), 1e-9))
        #expect(sequence.moveFade(at: handOff.addingTimeInterval(0.25)) == 0, "gone 0.25 s in")
        #expect(sequence.moveFade(at: handOff.addingTimeInterval(0.4)) == 0)
        // The mark and the wordmark are drawn at full opacity until done: the overlay's move draws them from the last
        // frame, whose opacities are 1, and no overall fade applies.
        let frame = LaunchFrame(t: 1, palette: Self.palette)
        let move = try #require(LaunchOverlay.move(sequence, targets: [.mark: target], at: handOff.addingTimeInterval(0.3),
                                                   frame: frame, palette: Self.palette))
        #expect(move.taglineOpacity == 0 && frame.groupOpacity == 1 && frame.wordmarkOpacity == 1)
        #expect(LaunchOverlay.move(sequence, targets: [:], at: handOff.addingTimeInterval(0.3), frame: frame,
                                   palette: Self.palette) == nil, "no target: the cross-fade")
        #expect(LaunchOverlay.move(sequence, targets: [.mark: target], at: handOff.addingTimeInterval(-0.1), frame: frame,
                                   palette: Self.palette) == nil, "playing: the launch layout")
    }

    /// The gauge's slot during the move: empty only uncovered and not yet revealed.
    @Test func theGaugeSlotIsEmptyOnlyInFlight() {
        #expect(!TodayView.gaugeSlotIsEmpty(covers: true, reveals: true), "covered: the static gauge, unseen")
        #expect(TodayView.gaugeSlotIsEmpty(covers: false, reveals: true), "in flight: 260 × 260 and empty")
        #expect(!TodayView.gaugeSlotIsEmpty(covers: false, reveals: false), "landed: the gauge and its entrance")
        #expect(TodayLayout.heroFrame == 260)
    }

    private static let palette = LaunchFrame.Palette(strain: .init(r: 0.37, g: 0.55, b: 0.92),
                                                     sleep: .init(r: 0.61, g: 0.54, b: 0.94),
                                                     recovery: .init(r: 0.39, g: 0.82, b: 0.71),
                                                     ink: .init(r: 0.95, g: 0.95, b: 0.93))
}
