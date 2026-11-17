import SwiftUI
import UIKit

/// The launch sequence's picture at one moment (`LaunchFrame`): the mark, drawn in one `Canvas` with
/// `RyftMarkGeometry`'s own path builders, "RYFT" under it and the tagline at the bottom, laid out on the full screen
/// (design.md §P3-4, "Layout"; portrait only). No background and no accessibility of its own: `LaunchOverlay` puts it
/// on `Theme.background` and is the one VoiceOver element.
struct LaunchStage: View {
    let frame: LaunchFrame
    /// The mark's 100 box in the stage's own space; nil is the launch layout's (`markRect(in:)`). PR 4 passes Today's
    /// header mark here to move the mark into it.
    var markRect: CGRect?
    /// The screen's bottom safe-area inset (the home indicator's), which the tagline clears. The overlay passes it from
    /// `LaunchFullScreen`: the stage's own geometry is laid out ignoring the safe areas, where it reads 0.
    var safeAreaBottom: CGFloat = 0
    /// The matched move into Today's header (design.md §P4-7): the mark and "RYFT" leave the launch layout for the
    /// lock-up's frames; nil draws the launch layout.
    var move: Move?

    /// One moment of the matched move: where the lock-up is, how far the move is, and what the mark is drawn in.
    struct Move: Equatable {
        /// The header's mark and wordmark in the window's space, as their targets report them. Without a wordmark target
        /// the wordmark lands beside the mark, as `WordmarkLockup` lays it out.
        var mark: CGRect
        var wordmark: CGRect?
        /// 0...1 of the hand-off's duration, linear (`LaunchSequence.moveTime(at:)`).
        var time: Double
        /// The tagline's opacity at this moment (it fades with the background).
        var taglineOpacity: Double
        /// The mark is drawn as the last frame at each moment's side: its stroke and dots follow the size.
        var palette: LaunchFrame.Palette
    }

    /// Where the lock-up is drawn at one moment of the move, in the stage's (the screen's) space.
    struct MoveLayout: Equatable {
        var mark: CGRect
        var wordmarkCentre: CGPoint
        var wordmarkSize: CGFloat
    }

    /// The 100 box's side: stroke 5.81, dot r 11.04, radii 80.96 / 47.10 / 13.98 pt.
    static let markSide: CGFloat = 184
    /// The box's centre sits this far above the screen's middle.
    static let markLift: CGFloat = 40
    /// "RYFT": fixed, a brand mark (ADR 0016 §3).
    static let wordmarkSize: CGFloat = 22
    /// From the box's bottom to the wordmark's line box (Q9: below the box, not below the ring's edge).
    static let wordmarkGap: CGFloat = 28
    /// The tagline's bottom edge above the screen's bottom: at least this, and 24 pt above the home indicator's inset.
    static let taglineBottom: CGFloat = 64
    static let taglineAboveInset: CGFloat = 24
    /// The tagline grows upwards at large text sizes, never closer than this to the wordmark.
    static let taglineMinGap: CGFloat = 16

    /// The launch layout's mark box on a screen of `size`: centred, 40 pt above the middle (390 x 844: centre y 382).
    static func markRect(in size: CGSize) -> CGRect {
        CGRect(x: size.width / 2 - markSide / 2, y: size.height / 2 - markLift - markSide / 2,
               width: markSide, height: markSide)
    }

    /// The tagline's bottom inset for a home-indicator inset (64 on every notched iPhone).
    static func taglineBottomInset(safeAreaBottom: CGFloat) -> CGFloat {
        max(taglineBottom, safeAreaBottom + taglineAboveInset)
    }

    // MARK: the matched move (design.md §P4-7)

    /// A frame in the window's space (`.global`) in the stage's own: moved by the stage's origin in the window, which
    /// the stage measures (`body`). Target and drawing are measured in the one space every view of the window shares,
    /// and nothing assumes where a root or its safe area starts. A named space would not do: Today sits in the
    /// `TabView`'s own hosting view, where `LaunchHost`'s name is not found and SwiftUI falls back to the window's space,
    /// while the overlay found the name 62 pt lower (VB1). The stage ignores the safe areas, so it sits at (0, 0) and the
    /// header's (20.9, 69.9) is drawn at (20.9, 69.9).
    static func overlayRect(fromWindow rect: CGRect, stageOrigin: CGPoint) -> CGRect {
        rect.offsetBy(dx: -stageOrigin.x, dy: -stageOrigin.y)
    }

    /// The wordmark's line box at `size` (Satoshi Light: 29.7 at 22, 20.25 at 15), which its centre is placed by.
    static func wordmarkLineHeight(_ size: CGFloat) -> CGFloat {
        UIFont(name: RyftFonts.postScriptName(for: .light), size: size)?.lineHeight ?? size * 1.35
    }

    /// The wordmark's ink width at `size` (the clearance model): four letters at 0.62 em and three trackings of 0.32 em;
    /// the tracking after the last letter is pulled back (`Wordmark`).
    static func wordmarkInkWidth(_ size: CGFloat) -> CGFloat {
        size * (4 * 0.62 + 3 * Wordmark.tracking)
    }

    /// The launch layout's wordmark centre: the screen's middle, its line box 28 below the mark's box.
    static func wordmarkCentre(in screen: CGSize) -> CGPoint {
        let box = markRect(in: screen)
        return CGPoint(x: screen.width / 2, y: box.maxY + wordmarkGap + wordmarkLineHeight(wordmarkSize) / 2)
    }

    /// The lock-up at one moment: the mark's box lerped from the launch layout's to the header's by E1 of the move's time,
    /// the wordmark's centre and size by the delayed E1 (`LaunchFrame.wordmarkMoveProgress`).
    static func moveLayout(_ move: Move, screen: CGSize, stageOrigin: CGPoint) -> MoveLayout {
        let start = markRect(in: screen)
        let target = overlayRect(fromWindow: move.mark, stageOrigin: stageOrigin)
        let mark = LaunchFrame.rect(from: start, to: target, progress: LaunchFrame.markMoveProgress(move.time))
        let landing: CGPoint
        if let wordmark = move.wordmark.map({ overlayRect(fromWindow: $0, stageOrigin: stageOrigin) }) {
            landing = CGPoint(x: wordmark.midX, y: wordmark.midY)
        } else {
            // `WordmarkLockup`: 10 pt of air per 26 pt of mark, the wordmark centred on the mark's middle.
            let size = CGFloat(LaunchFrame.wordmarkMoveTargetSize)
            landing = CGPoint(x: target.maxX + target.width * 10 / 26 + wordmarkInkWidth(size) / 2, y: target.midY)
        }
        let progress = LaunchFrame.wordmarkMoveProgress(move.time)
        return MoveLayout(mark: mark, wordmarkCentre: LaunchFrame.point(from: wordmarkCentre(in: screen), to: landing,
                                                                        progress: progress),
                          wordmarkSize: CGFloat(LaunchFrame.wordmarkMoveSize(move.time, from: Double(wordmarkSize))))
    }

    var body: some View {
        GeometryReader { proxy in
            // Where the stage is in the window, the space the header's frames come in: one space for target and drawing.
            let layout = move.map { Self.moveLayout($0, screen: proxy.size, stageOrigin: proxy.frame(in: .global).origin) }
            // In flight the mark is the last frame at its current side (stroke and dots follow it), never interpolated.
            let drawn = move.map { LaunchFrame(t: 1, palette: $0.palette, side: Double(layout?.mark.width ?? Self.markSide)) }
                ?? frame
            let rect = layout?.mark ?? markRect ?? Self.markRect(in: proxy.size)
            // The tagline keeps the launch layout's place while the lock-up moves.
            let layoutRect = move == nil ? rect : Self.markRect(in: proxy.size)
            let ink = Color(drawn.ink)
            ZStack(alignment: .top) {
                Canvas { context, _ in Self.drawMark(drawn, in: rect, context: &context) }
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(layoutRect.maxY + Self.wordmarkGap, 0))
                    Wordmark(size: Self.wordmarkSize, tracking: frame.wordmarkTracking)
                        .foregroundStyle(ink)
                        .opacity(layout == nil ? frame.wordmarkOpacity : 0)
                    Spacer(minLength: Self.taglineMinGap)
                    Text("Engineered for peak.", comment: "RYFT's tagline: under the wordmark on the launch screen and in the brand lock-up.")
                        .font(.ryft(.label))
                        .foregroundStyle(ink.opacity(LaunchFrame.taglineInk))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Metrics.screenPadding)
                        .opacity(move?.taglineOpacity ?? frame.taglineOpacity)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    Color.clear.frame(height: Self.taglineBottomInset(safeAreaBottom: safeAreaBottom))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                if let layout {
                    // In flight: at its own size each frame (so it lands as the header's 15 pt text), 0.32 em throughout.
                    Wordmark(size: layout.wordmarkSize)
                        .foregroundStyle(ink)
                        .fixedSize()
                        .position(layout.wordmarkCentre)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Tracks, arcs, the inner ring, then the dots, each part from `RyftMarkGeometry` (no second geometry), in the
    /// frame's colours and at its group opacity. At t = 1 these are `RyftMarkShape`'s paths, so the pixels are the mark's.
    static func drawMark(_ frame: LaunchFrame, in rect: CGRect, context: inout GraphicsContext) {
        guard frame.groupOpacity > 0 else { return }
        let g = RyftMarkGeometry.self
        let placement = RyftMarkGeometry.Placement(in: rect)
        context.opacity = frame.groupOpacity
        if frame.trackOpacity > 0 {
            let track = GraphicsContext.Shading.color(Color(frame.ink).opacity(LaunchFrame.trackInk * frame.trackOpacity))
            for radius in [g.outer.radius, g.middle.radius, g.innerRadius] {
                context.fill(g.ringPath(radius: radius, in: placement), with: track)
            }
        }
        let orbits: [(LaunchFrame.Orbit, Double)] = [(frame.strain, g.outer.radius), (frame.sleep, g.middle.radius),
                                                     (frame.recovery, g.middle.radius)]
        for (orbit, radius) in orbits where !orbit.arc.isEmpty {
            context.fill(g.arcPath(radius: radius, start: orbit.arc.start, end: orbit.arc.end, in: placement),
                         with: .color(Color(orbit.colour)))
        }
        context.fill(g.innerRingArcPath(start: -90, sweep: frame.innerSweep, in: placement), with: .color(Color(frame.ink)))
        for (orbit, radius) in orbits {
            context.fill(g.dotPath(radius: radius, degrees: orbit.dot, in: placement), with: .color(Color(orbit.colour)))
        }
    }
}

extension LaunchFrame.Palette {
    /// The asset catalog's colours (`Theme`) as sRGB components, the space the frame mixes in.
    static func resolved(in environment: EnvironmentValues) -> LaunchFrame.Palette {
        func rgb(_ colour: Color) -> LaunchFrame.RGB {
            let resolved = colour.resolve(in: environment)
            return LaunchFrame.RGB(r: Double(resolved.red), g: Double(resolved.green), b: Double(resolved.blue))
        }
        return LaunchFrame.Palette(strain: rgb(Theme.metricStrain), sleep: rgb(Theme.metricSleep),
                                   recovery: rgb(Theme.recovery), ink: rgb(Theme.textPrimary))
    }
}

extension Color {
    /// A launch frame's mixed colour.
    init(_ rgb: LaunchFrame.RGB) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

// MARK: previews (the board's demo reading; synthetic, never the user's)

#if DEBUG
/// The stage at one t on the 390 x 844 launch layout, on the background, as the overlay draws it.
struct LaunchStagePreview: View {
    var t: Double
    /// The reduced variant's fade-in, or the hand-off's fade.
    var opacity: Double = 1
    @Environment(\.self) private var environment

    var body: some View {
        ZStack {
            Theme.background
            LaunchStage(frame: LaunchFrame(t: t, palette: .resolved(in: environment)))
                .opacity(opacity)
        }
        .frame(width: 390, height: 844)
        .environment(\.colorScheme, .dark)
    }
}

/// The default size beside AX3 (only the tagline scales).
private struct LaunchPreviewPair: View {
    var t: Double

    var body: some View {
        HStack(spacing: 12) {
            LaunchStagePreview(t: t)
            LaunchStagePreview(t: t).environment(\.dynamicTypeSize, .accessibility3)
        }
        .padding(12)
        .background(Theme.surface)
    }
}

#Preview("Launch · t 0.26 (hold), default and AX3", traits: .sizeThatFitsLayout) {
    LaunchPreviewPair(t: 0.26)
}

#Preview("Launch · t 0.5 (end of the hold), default and AX3", traits: .sizeThatFitsLayout) {
    LaunchPreviewPair(t: 0.5)
}

#Preview("Launch · t 0.76 (the mark's geometry), default and AX3", traits: .sizeThatFitsLayout) {
    LaunchPreviewPair(t: 0.76)
}

#Preview("Launch · t 1 (the static lock-up), default and AX3", traits: .sizeThatFitsLayout) {
    LaunchPreviewPair(t: 1)
}

#Preview("Launch · Reduce Motion, default and AX3", traits: .sizeThatFitsLayout) {
    // The reduced variant shows the t = 1 frame (L11), fading in over 0.25 s: half-way, then held.
    HStack(spacing: 12) {
        LaunchStagePreview(t: 1, opacity: LaunchFrame.Easing.easeOut(0.5))
        LaunchStagePreview(t: 1)
        LaunchStagePreview(t: 1).environment(\.dynamicTypeSize, .accessibility3)
    }
    .padding(12)
    .background(Theme.surface)
}

#Preview("Launch · keyframes 0, 0.13, 0.63, 0.86", traits: .sizeThatFitsLayout) {
    HStack(spacing: 12) {
        ForEach([0, 0.13, 0.63, 0.86], id: \.self) { LaunchStagePreview(t: $0) }
    }
    .padding(12)
    .background(Theme.surface)
}
#endif
