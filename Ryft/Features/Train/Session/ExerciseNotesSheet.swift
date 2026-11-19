import SwiftUI

/// An exercise's notes in this workout ("pause on chest"); they go up with the session (PR 6 B §4.8): `SheetHeader("Notes")`
/// with a compact "Save", then a grouped card titled with the exercise holding one multi-line field. The close circle
/// ("Cancel") or a drag down keeps the notes as they were.
struct ExerciseNotesSheet: View {
    var controller: SessionController
    let exercise: LocalSessionExercise

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    /// The field: 3 to 8 lines.
    static let lines = 3...8

    init(controller: SessionController, exercise: LocalSessionExercise) {
        self.controller = controller
        self.exercise = exercise
        _text = State(initialValue: exercise.notes)
    }

    var body: some View {
        SessionSheetFrame(Text("Notes", comment: "Title of an exercise's notes sheet in a workout."), closeLabel: Text("Cancel")) {
            PillButton(Text("Save"), size: .compact) {
                controller.setNotes(text, for: exercise)
                dismiss()
            }
            .accessibilityIdentifier("notes.save")
        } content: {
            GroupedCard(Text(verbatim: exercise.name)) {
                FormField(Text("Notes", comment: "Title of an exercise's notes sheet in a workout."), isFocused: focused) {
                    TextField(text: $text,
                              prompt: Text("Notes for this exercise", comment: "Placeholder of an exercise's notes in a workout.")
                                  .fieldPrompt(),
                              axis: .vertical) {
                        Text("Notes for this exercise", comment: "Placeholder of an exercise's notes in a workout.")
                    }
                    .lineLimit(Self.lines)
                    .focused($focused)
                    .accessibilityIdentifier("notes.field")
                }
            }
        }
        .onAppear { focused = true }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - previews (dark only)

#Preview("Exercise notes") {
    let c = SessionSheetsPreview.listDraft()
    c.exercises[0].notes = "Pause on the chest, elbows in"
    return Color.clear
        .sheet(isPresented: .constant(true)) { ExerciseNotesSheet(controller: c, exercise: c.exercises[0]) }
        .previewEnvironment()
}

#Preview("Exercise notes · empty, AX3") {
    let c = SessionSheetsPreview.listDraft()
    return ExerciseNotesSheet(controller: c, exercise: c.exercises[0])
        .previewEnvironment()
        .dynamicTypeSize(.accessibility3)
}
