import SwiftUI
import WidgetKit

/// RYFT's widget extension: readiness on the home and lock screen, the workout Live
/// Activity, and the start-workout control.
@main
struct RyftWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ReadinessWidget()
        RestTimerLiveActivity()
        StartWorkoutControl()
        #if canImport(AlarmKit)
        if #available(iOSApplicationExtension 26.0, *) {
            WakeAlarmLiveActivity()
        }
        #endif
    }
}
