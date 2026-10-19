import SwiftUI

/// Small progress ring with a flat track (Strain's week strip). Settles in 250 ms
/// ease-out unless Reduce Motion is on. No glow, no gradient. Scores with a scale
/// and bands use `MetricGauge`. The centre is free-form.
struct ScoreRing<Center: View>: View {
    /// 0…1, nil for "no data" (empty track).
    let progress: Double?
    var size: CGFloat = 120
    var lineWidth: CGFloat? = nil
    var color: Color = Theme.accent
    /// VoiceOver, e.g. "Readiness" / "84 of 100".
    let accessibilityLabel: Text
    let accessibilityValue: Text
    @ViewBuilder var center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var width: CGFloat { lineWidth ?? max(2.5, size * 0.048) }
    private var target: Double { min(max(progress ?? 0, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.surfaceRaised, lineWidth: width)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            center()
        }
        .frame(width: size, height: size)
        .onAppear(perform: animate)
        .onChange(of: progress) { animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private func animate() {
        if reduceMotion {
            shown = target
        } else {
            shown = 0
            withAnimation(Theme.ringAnimation) { shown = target }
        }
    }
}

#Preview("ScoreRing", traits: .sizeThatFitsLayout) {
    SchemePair {
        HStack(spacing: 16) {
            ScoreRing(progress: 12.4 / 21, size: 36, lineWidth: 3, color: Theme.metricStrain,
                      accessibilityLabel: Text("Strain"), accessibilityValue: Text("12.4")) {
                Text("12").font(.ryftNumber(size: 11)).foregroundStyle(Theme.textPrimary)
            }
            ScoreRing(progress: nil, size: 36, lineWidth: 3,
                      accessibilityLabel: Text("Strain"), accessibilityValue: Text("No data")) {
                Text(Fmt.placeholder).font(.ryftNumber(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
