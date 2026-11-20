// The wake alarm's snooze (Bedtime & wake, AlarmKit): a countdown on the lock screen and in the Dynamic Island. AlarmKit
// expects the widget extension to provide it once an alarm can count down; the alert itself is the system's. Nocturne
// (c-27): the words in `textSecondary`, the countdown 40 Light in ink, no teal; the keyline as the workout's.
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
import WidgetKit

@available(iOS 26.0, *)
struct WakeAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<WakeAlarmMetadata>.self) { context in
            SnoozeLockScreen(fireDate: context.state.snoozeFireDate)
                .activityBackgroundTint(Brand.graphite)
                .activitySystemActionForegroundColor(Brand.mist)
        } dynamicIsland: { context in
            let fireDate = context.state.snoozeFireDate
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { SnoozeIslandLabel() }
                DynamicIslandExpandedRegion(.trailing) {
                    SnoozeClock(fireDate: fireDate)
                        .font(.system(size: 28, weight: .light))
                }
            } compactLeading: {
                SnoozeGlyph()
            } compactTrailing: {
                SnoozeClock(fireDate: fireDate)
                    .font(.system(size: 15, weight: .light))
                    .frame(maxWidth: 56)
            } minimal: {
                SnoozeGlyph()
            }
            .keylineTint(Brand.mist.opacity(WorkoutActivityLook.keylineOpacity))
        }
    }
}

@available(iOS 26.0, *)
private extension AlarmPresentationState {
    /// The next ring while the alarm counts down (snoozed); nil otherwise.
    var snoozeFireDate: Date? {
        if case .countdown(let countdown) = mode { return countdown.fireDate }
        return nil
    }
}

/// "Snoozing" and "Your alarm rings again" in `textSecondary`, the countdown 40 Light in ink. One element for VoiceOver.
struct SnoozeLockScreen: View {
    let fireDate: Date?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: WorkoutActivityLook.labelGap) {
                Text("Snoozing")
                    .font(.caption2.weight(.medium))
                Text("Your alarm rings again")
                    .font(.caption)
            }
            .foregroundStyle(WidgetInk.secondary.colour)
            .lineLimit(1)
            Spacer(minLength: 8)
            SnoozeClock(fireDate: fireDate)
                .font(.system(size: 40, weight: .light))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(WorkoutActivityLook.padding)
        .dynamicTypeSize(...WorkoutActivityLook.largestType)
        .background(Brand.graphite)
        .accessibilityElement(children: .combine)
    }
}

/// The island's leading region: `zzz` and "Snoozing" in `textSecondary`.
struct SnoozeIslandLabel: View {
    var body: some View {
        Label {
            Text("Snoozing").font(.caption.weight(.medium))
        } icon: {
            Image(systemName: "zzz").font(.caption)
        }
        .foregroundStyle(WidgetInk.secondary.colour)
        .padding(.leading, 4)
        .dynamicTypeSize(...WorkoutActivityLook.largestType)
    }
}

/// Compact and minimal: `zzz` in `textSecondary`, at the default size (the regions are fixed); VoiceOver says
/// "Snoozing".
struct SnoozeGlyph: View {
    var body: some View {
        Image(systemName: "zzz")
            .foregroundStyle(WidgetInk.secondary.colour)
            .dynamicTypeSize(...WorkoutActivityLook.glanceLargestType)
            .accessibilityLabel(Text("Snoozing"))
    }
}

/// Counts down to the next ring; the alarm glyph when there is none to count to.
struct SnoozeClock: View {
    let fireDate: Date?

    var body: some View {
        if let fireDate {
            Text(timerInterval: Date.now...max(fireDate, .now), countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(WidgetInk.primary.colour)
        } else {
            Image(systemName: "alarm")
                .foregroundStyle(WidgetInk.secondary.colour)
        }
    }
}

#Preview("Snooze · lock screen", traits: .sizeThatFitsLayout) {
    SnoozeLockScreen(fireDate: .now.addingTimeInterval(8 * 60 + 42))
        .frame(width: 358)
}
#endif
