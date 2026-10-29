import SwiftUI

/// An exercise's notes in this workout ("pause on chest"); they go up with the session.
struct ExerciseNotesSheet: View {
    var controller: SessionController
    let exercise: LocalSessionExercise

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(controller: SessionController, exercise: LocalSessionExercise) {
        self.controller = controller
        self.exercise = exercise
        _text = State(initialValue: exercise.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $text, axis: .vertical) {
                        Text("Notes for this exercise", comment: "Placeholder of an exercise's notes in a workout.")
                    }
                    .font(.ryft(.body))
                    .lineLimit(3...8)
                    .focused($focused)
                } header: {
                    Text(exercise.name)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text("Notes", comment: "Title of an exercise's notes sheet in a workout."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        controller.setNotes(text, for: exercise)
                        dismiss()
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Exercise notes · dark") {
    let c = TrainPreview.liveController()
    return ExerciseNotesSheet(controller: c, exercise: c.exercises[0])
        .preferredColorScheme(.dark)
}

#Preview("Exercise notes · light") {
    let c = TrainPreview.liveController()
    return ExerciseNotesSheet(controller: c, exercise: c.exercises[0])
        .preferredColorScheme(.light)
}
