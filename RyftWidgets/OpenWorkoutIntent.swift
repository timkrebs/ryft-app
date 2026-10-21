import AppIntents

/// The control's action. Keep identical to `OpenWorkoutIntent` in
/// `Ryft/Features/Train/TrainCoordinator.swift` (its type name, title and `openAppWhenRun`):
/// with `openAppWhenRun` the system opens RYFT and performs the app's copy, which starts or
/// resumes the workout. This copy only exists so the control can name it.
struct OpenWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or resume workout"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        .result()
    }
}
