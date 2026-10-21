import SwiftUI
import WidgetKit

/// RYFT's widget extension: readiness on the home and lock screen, and the rest timer
/// Live Activity.
@main
struct RyftWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ReadinessWidget()
        RestTimerLiveActivity()
        #if canImport(AlarmKit)
        if #available(iOSApplicationExtension 26.0, *) {
            WakeAlarmLiveActivity()
        }
        #endif
    }
}
