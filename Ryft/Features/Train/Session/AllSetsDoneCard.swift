import SwiftUI

/// The end of the list once every set is checked off (ui.md §5): "All sets done", what was done, and Finish, which
/// opens the same confirmation as the header's Finish. Content, not a modal: it goes when a set is unchecked or an
/// exercise is added.
struct AllSetsDoneCard: View {
    let exercises: Int
    let sets: Int
    var onFinish: () -> Void

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("All sets done", comment: "Card at the end of a workout once every set is checked off.")
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(exercises) exercises · \(sets) sets",
                         comment: "Under All sets done: how many exercises and checked sets, e.g. 5 exercises · 17 sets.")
                        .font(.ryft(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                Button(action: onFinish) {
                    Text("Finish workout")
                }
                .buttonStyle(TealButtonStyle(prominent: true))
                .accessibilityIdentifier("session.allDone.finish")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.allDone")
    }
}

#Preview("All sets done", traits: .sizeThatFitsLayout) {
    SchemePair {
        AllSetsDoneCard(exercises: 5, sets: 17, onFinish: {})
    }
}

#Preview("All sets done · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        AllSetsDoneCard(exercises: 5, sets: 17, onFinish: {})
    }
    .dynamicTypeSize(.accessibility3)
}
