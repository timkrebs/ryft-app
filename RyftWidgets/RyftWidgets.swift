// Rest timer Live Activity: lock screen and Dynamic Island. Started, updated
// and ended locally by the app (RestActivityController); no push.
import ActivityKit
import SwiftUI
import WidgetKit

/// The brand palette (the app's asset catalog isn't in this bundle).
enum Brand {
    static let graphite = Color(red: 0x0B / 255, green: 0x0F / 255, blue: 0x0E / 255)
    static let slate = Color(red: 0x1A / 255, green: 0x22 / 255, blue: 0x26 / 255)
    static let mist = Color(red: 0xE8 / 255, green: 0xE7 / 255, blue: 0xE3 / 255)
    static let teal = Color(red: 0x3F / 255, green: 0xD1 / 255, blue: 0xB4 / 255)
    static let deepLink = URL(string: "ryft://train/session")
}

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Brand.graphite)
                .activitySystemActionForegroundColor(Brand.mist)
                .widgetURL(Brand.deepLink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.resting ? "Rest" : "Workout")
                    } icon: {
                        Image(systemName: context.state.resting ? "timer" : "dumbbell.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.teal)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Clock(context: context)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        if context.state.resting { Progress(state: context.state) }
                        HStack {
                            NextLine(state: context.state)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            DoneLink()
                        }
                    }
                    .foregroundStyle(Brand.mist)
                }
            } compactLeading: {
                Image(systemName: context.state.resting ? "timer" : "dumbbell.fill")
                    .foregroundStyle(Brand.teal)
            } compactTrailing: {
                Clock(context: context)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.state.resting ? "timer" : "dumbbell.fill")
                    .foregroundStyle(Brand.teal)
            }
            .widgetURL(Brand.deepLink)
            .keylineTint(Brand.teal)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.resting ? "REST" : "WORKOUT")
                        .font(.caption2.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(Brand.teal)
                    Text(context.attributes.sessionTitle)
                        .font(.caption)
                        .foregroundStyle(Brand.mist.opacity(0.6))
                }
                Spacer()
                Clock(context: context)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.mist)
            }
            if context.state.resting { Progress(state: context.state) }
            HStack {
                NextLine(state: context.state)
                    .font(.callout)
                    .foregroundStyle(Brand.mist)
                    .lineLimit(1)
                Spacer()
                DoneLink()
            }
        }
        .padding(16)
        // Also painted here: the tint alone isn't applied in every presentation.
        .background(Brand.graphite)
    }
}

/// "Next: Bench press · set 3 of 4 · 5 × 80 kg".
private struct NextLine: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        Text("Next: \(state.next)")
    }
}

/// Resting: counts down to `endsAt`, "Go" once it's over. Otherwise the workout's elapsed time.
private struct Clock: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        let state = context.state
        if !state.resting {
            Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Brand.mist)
        } else if state.endsAt <= .now {
            Text("Go")
                .foregroundStyle(Brand.teal)
        } else {
            Text(timerInterval: Date.now...state.endsAt, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Brand.mist)
        }
    }
}

private struct Progress: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        let start = state.endsAt.addingTimeInterval(-state.totalSec)
        ProgressView(timerInterval: min(start, .now)...max(state.endsAt, .now), countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .tint(Brand.teal)
    }
}

/// "Open" goes to the live session in the app.
private struct DoneLink: View {
    var body: some View {
        if let url = Brand.deepLink {
            Link(destination: url) {
                Text("Open")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Brand.graphite)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Brand.teal, in: Capsule())
            }
        }
    }
}

private extension RestTimerAttributes {
    static let preview = RestTimerAttributes(sessionTitle: "Upper A", startedAt: .now.addingTimeInterval(-23 * 60))
}

private extension RestTimerAttributes.ContentState {
    static let resting = RestTimerAttributes.ContentState(endsAt: .now.addingTimeInterval(95), totalSec: 180,
                                                          exercise: "Bench press",
                                                          next: "Bench press · set 3 of 4 · 5 × 80 kg", resting: true)
    static let working = RestTimerAttributes.ContentState(endsAt: .now, totalSec: 0, exercise: "Upper A",
                                                          next: "Bench press · set 3 of 4 · 5 × 80 kg", resting: false)
}

#Preview("Lock screen", as: .content, using: RestTimerAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState.working
    RestTimerAttributes.ContentState.resting
}

#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: RestTimerAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState.working
    RestTimerAttributes.ContentState.resting
}

#Preview("Compact", as: .dynamicIsland(.compact), using: RestTimerAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState.working
    RestTimerAttributes.ContentState.resting
}
