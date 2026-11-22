import SwiftUI

// The Focused table's fourth column in each mode, on a page with every row state and last time; the plain header of a page
// with no estimates is "Page · time and distance". In its own file: `ExercisePage.swift` holds the page's other states.

@MainActor
private func page(_ scenario: FocusedPreview.Scenario, _ column: SetColumn?) -> some View {
    let c = FocusedPreview.controller(scenario, column: column)
    return ExercisePage(controller: c, exercise: c.pageExercise ?? c.exercises[0], columns: .regular, onSheet: { _ in }, onRemove: {},
                        onPlates: {}, onHistory: {}, onFinish: {})
        .background(Theme.background)
}

#Preview("Column · E1RM") {
    page(.estimates, .e1rm).previewEnvironment()
}

#Preview("Column · 10RM") {
    page(.estimates, .tenRM).previewEnvironment()
}

#Preview("Column · RPE") {
    page(.estimates, .rpe).previewEnvironment()
}

#Preview("Column · bodyweight") {
    page(.bodyweightEstimates, .e1rm).previewEnvironment()
}
