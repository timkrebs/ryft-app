import SwiftUI

/// The import's numbers (PR 6 C §4.14): a 3 pt bar, the track ink at 16 % (the step rule's upcoming segment), the fill ink.
enum ImportProgressBarSpec {
    static let height: CGFloat = 3
    static let trackOpacity = StepRuleSpec.upcomingOpacity
    /// The paused end cap: a hollow ring 2.5 × the bar's height, 1.5 pt.
    static let capScale: CGFloat = 2.5, capLineWidth: CGFloat = 1.5
}

/// A determinate progress bar (ui.md §8.2; PR 6 C §4.14): an ink fill on a 16 % ink track, 3 pt, rounded. No colour: the
/// count beside it carries the meaning. Paused shows the last progress frozen with a hollow end cap; `showsFill: false` is the
/// track alone (getting ready). Never a spinner. Moves with a 150 ms ease-out, not at all under Reduce Motion. The caller
/// gives it its VoiceOver label and value.
struct ImportProgressBar: View {
    /// 0…1.
    let fraction: Double
    var isPaused = false
    var showsFill = true
    var height: CGFloat = ImportProgressBarSpec.height

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * min(1, max(0, fraction))
            let cap = height * ImportProgressBarSpec.capScale
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.textPrimary.opacity(ImportProgressBarSpec.trackOpacity))
                if showsFill {
                    Capsule()
                        .fill(Theme.textPrimary)
                        .frame(width: max(width, fraction > 0 ? height : 0))
                }
            }
            .frame(height: height)
            // The cap is drawn over the bar, so the bar keeps its own height.
            .overlay(alignment: .leading) {
                if showsFill, isPaused, fraction > 0 {
                    Circle()
                        .strokeBorder(Theme.textPrimary, lineWidth: ImportProgressBarSpec.capLineWidth)
                        .background(Circle().fill(Theme.background))
                        .frame(width: cap, height: cap)
                        .offset(x: max(0, width - cap / 2))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: isPaused ? height * ImportProgressBarSpec.capScale : height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: fraction)
        .accessibilityHidden(true)
    }
}

#Preview("ImportProgressBar", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 20) {
            ImportProgressBar(fraction: 0, showsFill: false)
            ImportProgressBar(fraction: 40 / 120)
            ImportProgressBar(fraction: 8 / 12, isPaused: true)
            ImportProgressBar(fraction: 1)
            ImportProgressBar(fraction: 0.4, height: 2)
        }
    }
}
