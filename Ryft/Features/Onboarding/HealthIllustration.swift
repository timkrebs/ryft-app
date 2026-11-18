import SwiftUI

/// The mark's numbers (PR 6 A §A-10, D6A-7), at its 72 pt side; a larger or smaller mark scales them.
enum HealthIllustrationSpec {
    static let side: CGFloat = 72
    /// The heart: `heart`, 34 pt ultra-light, `textPrimary`.
    static let heartSize: CGFloat = 34
    /// The pulse line across it: 44 × 14, 1.5 pt.
    static let pulse = CGSize(width: 44, height: 14)
    static let pulseWidth: CGFloat = 1.5
    /// The pulse draws in once (`Theme.Motion.slow`, 0.6 s) and then holds; never a loop.
    static let drawIn = Theme.Motion.slow
}

/// "Connect Apple Health": a heart, and the pulse line that RYFT reads from it. Nocturne: a neutral outline (a 1 pt ink
/// circle at 16 %, the circle button's border), no teal; the pulse draws in once when the mark appears and holds (no
/// looping motion), and under Reduce Motion it is drawn at rest. Decoration, hidden from VoiceOver.
struct HealthIllustration: View {
    var size: CGFloat = HealthIllustrationSpec.side

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The launch's mark still covers the screen (ADR 0017): the line draws once it has handed over, where it can be seen.
    @Environment(\.launchCoversRoot) private var launchCovers
    @State private var drawn = false

    private var scale: CGFloat { size / HealthIllustrationSpec.side }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.textPrimary.opacity(CircleButton.borderOpacity), lineWidth: Theme.Metrics.hairline)
            Image(systemName: "heart")
                .font(.system(size: HealthIllustrationSpec.heartSize * scale, weight: .ultraLight))
                .foregroundStyle(Theme.textPrimary)
            PulseShape(progress: Self.progress(drawn: drawn, reduceMotion: reduceMotion))
                .stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: HealthIllustrationSpec.pulseWidth,
                                                              lineCap: .round, lineJoin: .round))
                .frame(width: HealthIllustrationSpec.pulse.width * scale, height: HealthIllustrationSpec.pulse.height * scale)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear(perform: drawIn)
        .onChange(of: launchCovers) { drawIn() }
    }

    private func drawIn() {
        guard !drawn, !launchCovers else { return }
        withAnimation(Theme.Motion.respecting(reduceMotion, HealthIllustrationSpec.drawIn)) { drawn = true }
    }

    /// How much of the pulse is drawn: all of it once it has drawn in, and from the start under Reduce Motion.
    static func progress(drawn: Bool, reduceMotion: Bool) -> Double {
        drawn || reduceMotion ? 1 : 0
    }
}

/// An ECG-like beat across the width, drawn up to `progress`.
private struct PulseShape: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, mid = rect.midY
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: mid))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.30, y: mid))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.38, y: mid - h * 0.30))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.46, y: mid + h * 0.50))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.54, y: mid - h * 0.50))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.62, y: mid + h * 0.20))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.68, y: mid))
        p.addLine(to: CGPoint(x: rect.maxX, y: mid))
        return p.trimmedPath(from: 0, to: progress)
    }
}

// Dark only (NOCTURNE_STYLE §1).
#Preview("Health illustration", traits: .sizeThatFitsLayout) {
    DarkPreview {
        HStack(spacing: 24) {
            HealthIllustration()
            HealthIllustration(size: 56)
        }
    }
}
