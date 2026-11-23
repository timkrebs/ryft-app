import SwiftUI

/// The first run's step indicator's numbers (docs/work/2026-11-23-first-run/ui.md §3). The segments are `StepRule`'s
/// (`StepRuleSpec`: 3 high, 4 apart, done 55 %, current 100 %, to come 16 %); only the arrangement differs.
enum FirstRunStepRuleSpec {
    /// The lock-up row → the rule 12, the rule → the title 20 (4 less than the lock-up → title 24 of a screen without it, so
    /// the rule costs the page its own height and 8), and the segments → the caption beside them 12.
    static let topGap: CGFloat = 12, titleGap: CGFloat = 20, captionGap: CGFloat = 12
    /// At accessibility sizes the caption goes under the segments, 6 below them (`StepRule`'s own gap).
    static let stackedGap: CGFloat = 6
    /// Under this many steps there is nothing to count and the rule is not drawn.
    static let minimumCount = 2

    /// The step shown: held inside 1...count, so a stale index never draws a segment out of range.
    static func clamped(step: Int, count: Int) -> Int { min(max(step, 1), max(count, 1)) }
}

/// "Step 3 of 7" for the first run: `count` thin segments (done dimmed, the current one in full, the rest at the track's 16 %)
/// and the caption on one line beside them (stacked from the accessibility sizes, where the caption would crowd the
/// segments). Quiet on purpose: `textPrimary` at three opacities and `textTertiary` for the words, no teal and no Volt (the
/// words say the step, colour says nothing), no motion of its own (the screen it sits on cross-fades with `Theme.Motion.quick`,
/// at once under Reduce Motion). One VoiceOver element, "Step 3 of 7".
///
/// Fewer than `FirstRunStepRuleSpec.minimumCount` steps draws nothing: a flow of one has no progress. Placed by the screen
/// under its lock-up row (`topGap`); never in a sheet (the caller passes no progress there). The same caption text as
/// `StepRule`, so it shares its catalog string.
struct FirstRunStepRule: View {
    let step: Int
    let count: Int

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if count >= FirstRunStepRuleSpec.minimumCount {
            let current = FirstRunStepRuleSpec.clamped(step: step, count: count)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: FirstRunStepRuleSpec.stackedGap))
                : AnyLayout(HStackLayout(alignment: .center, spacing: FirstRunStepRuleSpec.captionGap))
            layout {
                HStack(spacing: StepRuleSpec.spacing) {
                    ForEach(1...count, id: \.self) { index in
                        Capsule()
                            .fill(Theme.textPrimary.opacity(StepRuleSpec.opacity(index: index, step: current)))
                            .frame(height: StepRuleSpec.height)
                    }
                }
                Text("Step \(current) of \(count)")
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Step \(current) of \(count)"))
        }
    }
}

// Dark only (ADR 0016): every colour here is a one-value asset, so a light preview would be the same pixels.
#Preview("FirstRunStepRule · 3 of 7, 1 of 6, 8 of 8, one step", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(alignment: .leading, spacing: 20) {
            FirstRunStepRule(step: 3, count: 7)
            FirstRunStepRule(step: 1, count: 6)
            FirstRunStepRule(step: 8, count: 8)
            // One step: nothing is drawn.
            FirstRunStepRule(step: 1, count: 1)
        }
    }
}

#Preview("FirstRunStepRule · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { FirstRunStepRule(step: 4, count: 7) }
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("FirstRunStepRule · AX5", traits: .sizeThatFitsLayout) {
    DarkPreview { FirstRunStepRule(step: 4, count: 8) }
        .environment(\.dynamicTypeSize, .accessibility5)
}
