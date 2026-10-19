import SwiftUI
import WidgetKit

/// RYFT's widget extension. v1 carries only the rest timer Live Activity.
@main
struct RyftWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}
