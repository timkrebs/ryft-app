// Control Center, the Lock Screen and the Action Button: one tap starts a strength workout
// (today's plan day, else an empty one), or resumes the one in progress.
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct StartWorkoutControl: ControlWidget {
    static let kind = "dev.timkrebs.ryft.workout"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenWorkoutIntent()) {
                Label("Workout", systemImage: "dumbbell.fill")
            }
        }
        .displayName("Start workout")
        .description("Starts a strength workout in RYFT, or resumes the one in progress.")
    }
}
