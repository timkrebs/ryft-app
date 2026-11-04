import SwiftUI

/// A determinate hairline progress bar (ui.md §8.2): an accent fill on a separator track, 4 pt, rounded. Paused shows
/// the last progress frozen with a hollow end cap; `showsFill: false` is the track alone (getting ready). Never a
/// spinner. Moves with a 150 ms ease-out, not at all under Reduce Motion. The caller gives it its VoiceOver value.
struct ImportProgressBar: View {
    /// 0…1.
    let fraction: Double
    var isPaused = false
    var showsFill = true
    var height: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.separator)
                if showsFill {
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(width, fraction > 0 ? height : 0))
                    if isPaused, fraction > 0 {
                        Circle()
                            .strokeBorder(Theme.accent, lineWidth: 1.5)
                            .background(Circle().fill(Theme.background))
                            .frame(width: height * 2.5, height: height * 2.5)
                            .offset(x: max(0, width - height * 1.25))
                    }
                }
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
        }
        .frame(height: max(height, isPaused ? height * 2.5 : height))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: fraction)
        .accessibilityHidden(true)
    }
}

#Preview("ImportProgressBar", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 20) {
            ImportProgressBar(fraction: 0, showsFill: false)
            ImportProgressBar(fraction: 8 / 12)
            ImportProgressBar(fraction: 8 / 12, isPaused: true)
            ImportProgressBar(fraction: 1)
            ImportProgressBar(fraction: 0.4, height: 2)
        }
    }
}
