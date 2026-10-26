import SwiftUI

/// Where a multi-step flow is (ui.md §2): a thin line of `count` segments, accent up to `step`, and "Step 3 of 6".
/// One VoiceOver element.
struct StepRule: View {
    let step: Int
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(1...max(1, count), id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.accent : Theme.separator)
                        .frame(height: 3)
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
    SchemePair {
        VStack(spacing: 20) {
            StepRule(step: 1, count: 6)
            StepRule(step: 3, count: 6)
            StepRule(step: 6, count: 6)
        }
    }
}

#Preview("StepRule · AX3", traits: .sizeThatFitsLayout) {
    SchemePair { StepRule(step: 4, count: 6) }
        .environment(\.dynamicTypeSize, .accessibility3)
}
