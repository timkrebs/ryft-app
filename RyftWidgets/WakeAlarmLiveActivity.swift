// The wake alarm's snooze (Bedtime & wake, AlarmKit): a countdown on the lock screen and in
// the Dynamic Island. AlarmKit expects the widget extension to provide it once an alarm can
// count down; the alert itself is the system's.
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
import WidgetKit

@available(iOS 26.0, *)
struct WakeAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<WakeAlarmMetadata>.self) { context in
            SnoozeLockScreen(state: context.state)
                .activityBackgroundTint(Brand.graphite)
                .activitySystemActionForegroundColor(Brand.mist)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Snoozing", systemImage: "zzz")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.teal)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SnoozeClock(state: context.state)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                }
            } compactLeading: {
                Image(systemName: "zzz").foregroundStyle(Brand.teal)
            } compactTrailing: {
                SnoozeClock(state: context.state)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "zzz").foregroundStyle(Brand.teal)
            }
            .keylineTint(Brand.teal)
        }
    }
}

@available(iOS 26.0, *)
private struct SnoozeLockScreen: View {
    let state: AlarmPresentationState

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SNOOZING")
                    .font(.caption2.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(Brand.teal)
                Text("Your alarm rings again")
                    .font(.caption)
                    .foregroundStyle(Brand.mist.opacity(0.6))
            }
            Spacer()
            SnoozeClock(state: state)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.mist)
        }
        .padding(16)
        .background(Brand.graphite)
    }
}

/// Counts down to the next ring.
@available(iOS 26.0, *)
private struct SnoozeClock: View {
    let state: AlarmPresentationState

    var body: some View {
        if case .countdown(let countdown) = state.mode {
            Text(timerInterval: Date.now...max(countdown.fireDate, .now), countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Brand.mist)
        } else {
            Image(systemName: "alarm")
                .foregroundStyle(Brand.teal)
        }
    }
}
#endif
