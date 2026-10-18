import SwiftUI

/// Progress ring with a thin track and a subtle glow inside. Animates in on
/// appear (0.8 s ease-out) unless Reduce Motion is on. The centre is free-form.
struct ScoreRing<Center: View>: View {
    /// 0…1, nil for "no data" (empty track).
    let progress: Double?
    var size: CGFloat = 120
    var lineWidth: CGFloat? = nil
    var color: Color = Theme.accent
    var glow = true
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
            if glow && progress != nil {
                Circle()
                    .fill(RadialGradient(colors: [color.opacity(0), color.opacity(0.13)],
                                         center: .center, startRadius: size * 0.22, endRadius: size * 0.5))
                    .padding(width / 2)
            }
            Circle()
                .stroke(color.opacity(0.14), lineWidth: width)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: glow ? color.opacity(0.45) : .clear, radius: width * 0.7)
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

/// A number that counts up from 0 on appear (instant under Reduce Motion).
struct CountingText: View {
    let value: Double?
    var format: (Double) -> String = { String(Int($0.rounded())) }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        Group {
            if let value {
                CountingLabel(value: shown, format: format)
                    .onAppear { animate(to: value) }
                    .onChange(of: value) { _, new in animate(to: new) }
            } else {
                Text(Fmt.placeholder)
            }
        }
        .monospacedDigit()
    }

    private func animate(to v: Double) {
        if reduceMotion {
            shown = v
        } else {
            shown = 0
            withAnimation(Theme.ringAnimation) { shown = v }
        }
    }
}

private struct CountingLabel: View, Animatable {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

#Preview("ScoreRing", traits: .sizeThatFitsLayout) {
    SchemePair {
        HStack(spacing: 24) {
            ScoreRing(progress: 0.84, size: 160,
                      accessibilityLabel: Text("Readiness"), accessibilityValue: Text("84 of 100")) {
                VStack(spacing: 4) {
                    RyftMark().frame(width: 18).foregroundStyle(Theme.textPrimary)
                    CountingText(value: 84).font(.ryftNumber(size: 40)).foregroundStyle(Theme.textPrimary)
                    Text("Overall readiness").ryftLabelStyle()
                        .font(.system(size: 7))
                }
            }
            VStack(spacing: 16) {
                ScoreRing(progress: 12.4 / 21, size: 64, color: Theme.accent,
                          accessibilityLabel: Text("Strain"), accessibilityValue: Text("12.4")) {
                    Text("12.4").font(.ryftNumber(size: 15)).foregroundStyle(Theme.textPrimary)
                }
                ScoreRing(progress: nil, size: 64,
                          accessibilityLabel: Text("Strain"), accessibilityValue: Text("No data")) {
                    Text(Fmt.placeholder).font(.ryftNumber(size: 15)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}
