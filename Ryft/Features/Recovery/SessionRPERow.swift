import SwiftUI

struct SessionRPERow: View {
    let model: SessionRPEModel
    var promptsForLoad = false

    private var pick: Binding<Int?> {
        Binding(get: {
            guard let rating = model.rating, rating == rating.rounded() else { return nil }
            return Int(rating)
        }, set: { value in
            Task {
                if let value { await model.save(value) } else { await model.clear() }
            }
        })
    }

    var body: some View {
        let question = Text("How hard was it?", comment: "Question for the perceived effort of a whole workout.")
        if model.isVisible {
            Card {
                VStack(alignment: .leading, spacing: Theme.Metrics.itemSpacing) {
                    question
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityHidden(true)
                    if promptsForLoad, model.showsPrompt {
                        Text("Rate it so RYFT can count this workout's load.",
                             comment: "Workout effort prompt on a workout without heart rate.")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    EffortScale(value: pick, label: question,
                                identifier: "rpe.scale", fractionalValue: model.rating)
                        .disabled(model.saving)
                    if model.rating != nil {
                        Button {
                            Task { await model.clear() }
                        } label: {
                            Text("Clear")
                                .font(.ryft(.button))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(minHeight: Theme.Metrics.minHitTarget)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.saving)
                    }
                    if let error = model.error {
                        InlineMessage(message: error.message, systemImage: "exclamationmark.circle", details: error.details,
                                      identifier: "rpe.error")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview("Session effort · AX3") {
    let workout = MockData.allWorkouts[0]
    DarkPreview {
        SessionRPERow(model: SessionRPEModel(env: .preview(flags: [.recoveryCheckin: true]), workoutID: workout.id,
                                            workout: workout))
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
