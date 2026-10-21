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
                        Text("Rest")
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.teal)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Progress(state: context.state)
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
                Image(systemName: context.state.finished ? "bell.fill" : "timer")
                    .foregroundStyle(Brand.teal)
            } compactTrailing: {
                Countdown(state: context.state)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.state.finished ? "bell.fill" : "timer")
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
                    Text(context.state.finished ? "REST OVER" : "REST")
                        .font(.caption2.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(Brand.teal)
                    Text(context.attributes.sessionTitle)
                        .font(.caption)
                        .foregroundStyle(Brand.mist.opacity(0.6))
                }
                Spacer()
                Countdown(state: context.state)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.mist)
            }
            Progress(state: context.state)
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

/// "Next: Bench press · set 3 of 4", or just the set once the rest is over.
private struct NextLine: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        if state.finished { Text(verbatim: state.next) } else { Text("Next: \(state.next)") }
    }
}

/// Counts down to `endsAt` on its own; "Go" once it's over.
private struct Countdown: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        if state.finished || state.endsAt <= .now {
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
        if state.finished {
            Capsule().fill(Brand.teal).frame(height: 6)
        } else {
            let start = state.endsAt.addingTimeInterval(-state.totalSec)
            ProgressView(timerInterval: min(start, .now)...state.endsAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(Brand.teal)
        }
    }
}

/// "Done" opens the live session in the app.
private struct DoneLink: View {
    var body: some View {
        if let url = Brand.deepLink {
            Link(destination: url) {
                Text("Done")
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
    static let preview = RestTimerAttributes(sessionTitle: "Upper A")
}

private extension RestTimerAttributes.ContentState {
    static let resting = RestTimerAttributes.ContentState(endsAt: .now.addingTimeInterval(95), totalSec: 180,
                                                          exercise: "Bench press", next: "Bench press · set 3 of 4",
                                                          finished: false)
    static let over = RestTimerAttributes.ContentState(endsAt: .now, totalSec: 180, exercise: "Bench press",
                                                       next: "Bench press · set 3 of 4", finished: true)
}

#Preview("Lock screen", as: .content, using: RestTimerAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState.resting
    RestTimerAttributes.ContentState.over
}

#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: RestTimerAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState.resting
}

#Preview("Compact", as: .dynamicIsland(.compact), using: RestTimerAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState.resting
}
