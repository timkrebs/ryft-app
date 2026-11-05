import SwiftUI

/// The exercise's `…` menu and context menu, in one order for both layouts (ui.md §1): Replace · Edit targets · Notes ·
/// Plate calculator (barbell) · History · Rest ▸ · Superset ─ Remove. What an item opens is the caller's: `ExerciseCard`
/// keeps its sheets, Focused holds them above the pages.
struct ExerciseMenuItems: View {
    var controller: SessionController
    let exercise: LocalSessionExercise
    var onReplace: () -> Void
    var onTargets: () -> Void
    var onNotes: () -> Void
    var onPlates: () -> Void
    var onHistory: () -> Void
    var onRemove: () -> Void
    /// Focused, for an exercise without a warm-up: once the pill is hidden, the group has no other way in (design.md §2.4).
    var onAddWarmup: (() -> Void)?

    var body: some View {
        Section {
            Button {
                controller.beginReplace()
                onReplace()
            } label: {
                Label(String(localized: "Replace exercise…", comment: "Exercise menu in a workout: pick another exercise for this one."),
                      systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!controller.canReplace(exercise))
            .accessibilityIdentifier("session.replace")
            Button {
                controller.focus = nil
                onTargets()
            } label: {
                Label(String(localized: "Edit targets…", comment: "Exercise menu in a workout: sets, reps, weight and rest for this workout."),
                      systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("session.editTargets")
            Button {
                controller.focus = nil
                onNotes()
            } label: {
                Label(String(localized: "Notes", comment: "Exercise menu in a workout: this exercise's notes."),
                      systemImage: "note.text")
            }
            if exercise.kind == .barbell {
                Button("Plate calculator", systemImage: "circle.grid.cross") { onPlates() }
            }
            Button("History", systemImage: "chart.xyaxis.line") { onHistory() }
            Menu {
                RestChoices(controller: controller, exercise: exercise)
            } label: {
                Label("Rest \(Fmt.clock(TimeInterval(exercise.restSec)))", systemImage: "timer")
            }
            if let onAddWarmup {
                Button(action: onAddWarmup) {
                    Label(String(localized: "Add warm-up set", comment: "Exercise menu in a workout: adds a warm-up set to this exercise."),
                          systemImage: "flame")
                }
            }
            if exercise.supersetGroup != nil {
                Button("Remove from superset", systemImage: "link.badge.plus") { controller.toggleSuperset(exercise) }
            } else if controller.canLinkBelow(exercise) {
                Button("Superset with next", systemImage: "link") { controller.toggleSuperset(exercise) }
            }
        }
        Section {
            Button("Remove exercise", systemImage: "trash", role: .destructive) { onRemove() }
        }
    }
}

/// The rest presets of the `…` menu's Rest item; the Focused page's Rest chip shows them in `RestChoicesSheet`.
struct RestChoices: View {
    var controller: SessionController
    let exercise: LocalSessionExercise

    static let presets = [60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        ForEach(Self.presets, id: \.self) { sec in
            Button(Fmt.clock(TimeInterval(sec))) { controller.setRest(sec, for: exercise) }
        }
    }
}

#Preview("Exercise menu · dark and light", traits: .sizeThatFitsLayout) {
    let c = TrainPreview.liveController()
    return SchemePair {
        // Every item without opening the menu: a menu's items exist only while it's open.
        VStack(alignment: .leading, spacing: 12) {
            ExerciseMenuItems(controller: c, exercise: c.exercises[0], onReplace: {}, onTargets: {}, onNotes: {}, onPlates: {},
                              onHistory: {}, onRemove: {}, onAddWarmup: {})
        }
        .font(.ryft(.callout))
    }
}
