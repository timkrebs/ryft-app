import SwiftUI

/// The step rule's numbers (Nocturne, PR 6 C #5): six segments 3 high and 4 apart; done `textPrimary` at 55 %, the current
/// one in full, the ones to come at 16 % (the track). No teal and no Volt: the words say the step.
enum StepRuleSpec {
    static let height: CGFloat = 3
    static let spacing: CGFloat = 4
    static let doneOpacity = 0.55
    static let currentOpacity = 1.0
    static let upcomingOpacity = 0.16

    /// The ink of segment `index` (1-based) when the flow is at `step`.
    static func opacity(index: Int, step: Int) -> Double {
        if index < step { return doneOpacity }
        if index == step { return currentOpacity }
        return upcomingOpacity
    }
}

/// Where a multi-step flow is (ui.md §2): a thin line of `count` segments, the done ones dimmed, the current one bright, and
/// "Step 3 of 6". One VoiceOver element.
struct StepRule: View {
    let step: Int
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: StepRuleSpec.spacing) {
                ForEach(1...max(1, count), id: \.self) { index in
                    Capsule()
                        .fill(Theme.textPrimary.opacity(StepRuleSpec.opacity(index: index, step: step)))
                        .frame(height: StepRuleSpec.height)
                }
            }
            Text("Step \(step) of \(count)")
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(step) of \(count)"))
    }
}

#Preview("StepRule", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 20) {
            StepRule(step: 1, count: 6)
            StepRule(step: 3, count: 6)
            StepRule(step: 6, count: 6)
        }
    }
}

#Preview("StepRule · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { StepRule(step: 4, count: 6) }
        .environment(\.dynamicTypeSize, .accessibility3)
}
