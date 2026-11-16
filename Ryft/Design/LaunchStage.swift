import SwiftUI

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

    var body: some View {
        GeometryReader { proxy in
            let rect = markRect ?? Self.markRect(in: proxy.size)
            let ink = Color(frame.ink)
            ZStack(alignment: .top) {
                Canvas { context, _ in Self.drawMark(frame, in: rect, context: &context) }
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(rect.maxY + Self.wordmarkGap, 0))
                    Wordmark(size: Self.wordmarkSize, tracking: frame.wordmarkTracking)
                        .foregroundStyle(ink)
                        .opacity(frame.wordmarkOpacity)
                    Spacer(minLength: Self.taglineMinGap)
                    Text("Engineered for peak.", comment: "The tagline under the wordmark on the launch screen.")
                        .font(.ryft(.label))
                        .foregroundStyle(ink.opacity(LaunchFrame.taglineInk))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Metrics.screenPadding)
                        .opacity(frame.taglineOpacity)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    Color.clear.frame(height: Self.taglineBottomInset(safeAreaBottom: safeAreaBottom))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
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
