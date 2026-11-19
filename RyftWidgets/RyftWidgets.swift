// The workout's Live Activity: lock screen and Dynamic Island. Started, updated and ended locally by the app
// (RestActivityController); no push. Nocturne (b-16, c-26): the system face with Light numbers, ink and its ladder, Volt
// for the running rest's dot and bar and nothing else in the activity (D6B-11), the light "Open" pill (F24). The decisions
// are `WorkoutActivityLook`'s (`Shared/WidgetLook.swift`).
import ActivityKit
import SwiftUI
import WidgetKit

/// The brand palette (the app's asset catalog isn't in this bundle; only the orbit's colorsets are copied in). The
/// same values as the app's Nocturne tokens (ADR 0016); `scripts/check-shared-types.py` compares each with the app colorset
/// of its name. The widget, like the app, is dark-only.
enum Brand {
    /// `Theme.graphite`, the screen.
    static let graphite = Color(red: 0x0A / 255, green: 0x0C / 255, blue: 0x0B / 255)
    /// `Theme.slate`, the neutral tile.
    static let slate = Color(red: 0x12 / 255, green: 0x15 / 255, blue: 0x14 / 255)
    /// `Theme.mist`, the ink.
    static let mist = Color(red: 0xF2 / 255, green: 0xF1 / 255, blue: 0xEC / 255)
    /// `Theme.signal`, Volt, as the extension draws it itself: the running rest's dot and bar only (D6B-11, L27;
    /// `WidgetNocturneTests` scans for it). The orbit's readiness marker is Volt too, from the shared palette's `Signal`.
    static let signal = Color(red: 0xD8 / 255, green: 0xFF / 255, blue: 0x4F / 255)
    static let deepLink = URL(string: "ryft://train/session")

    /// Text on the widget's background.
    static let ink = mist
    /// The widget's background.
    static let background = graphite
}

extension WidgetInk {
    /// `Brand.mist` at the ladder's strength.
    var colour: Color { Brand.mist.opacity(opacity) }
}

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            WorkoutLockScreen(workout: WorkoutShown(context))
                .activityBackgroundTint(Brand.graphite)
                .activitySystemActionForegroundColor(Brand.mist)
                .widgetURL(Brand.deepLink)
        } dynamicIsland: { context in
            let workout = WorkoutShown(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { WorkoutIslandLabel(workout: workout) }
                DynamicIslandExpandedRegion(.trailing) { WorkoutIslandClock(workout: workout) }
                DynamicIslandExpandedRegion(.bottom) { WorkoutIslandBottom(workout: workout) }
            } compactLeading: {
                WorkoutGlyph(workout: workout)
            } compactTrailing: {
                WorkoutCompactClock(workout: workout)
            } minimal: {
                WorkoutGlyph(workout: workout)
            }
            .widgetURL(Brand.deepLink)
            .keylineTint(Brand.mist.opacity(WorkoutActivityLook.keylineOpacity))
        }
    }
}

/// What the activity shows, out of its context, so the views take plain values (previews, the comparison shots).
struct WorkoutShown {
    var title: String
    var startedAt: Date
    var state: RestTimerAttributes.ContentState
    var isStale: Bool

    init(title: String, startedAt: Date, state: RestTimerAttributes.ContentState, isStale: Bool) {
        self.title = title
        self.startedAt = startedAt
        self.state = state
        self.isStale = isStale
    }

    init(_ context: ActivityViewContext<RestTimerAttributes>) {
        self.init(title: context.attributes.sessionTitle, startedAt: context.attributes.startedAt, state: context.state,
                  isStale: context.isStale)
    }

    /// A rest is counting down now: the clock counts down, the dot and the bar show.
    var restRunning: Bool {
        WorkoutActivityLook.restRunning(resting: state.resting, isStale: isStale, endsAt: state.endsAt, now: .now)
    }

    var inks: WorkoutActivityLook.Inks { WorkoutActivityLook.inks(restRunning: restRunning) }

    /// "Rest" or "Workout", as built (a rest that ran out with the app not running still says "Rest").
    var label: LocalizedStringKey { state.resting ? "Rest" : "Workout" }
    var glyph: String { state.resting ? "timer" : "dumbbell.fill" }
}

/// The lock screen (b-16 with F24's pill): the label with the rest's Volt dot and the session title, the clock 40 Light;
/// the rest's bar; the next set (two lines) and "Open". To stay within the lock screen's 160 pt the next set keeps one line
/// above the default size, and from the accessibility sizes the session title goes (`WorkoutActivityLook.condenses`); the
/// next set is cut at its end, so the exercise's name stays. One element for VoiceOver, which still hears the title.
struct WorkoutLockScreen: View {
    let workout: WorkoutShown
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.redactionReasons) private var redaction

    var body: some View {
        let inks = workout.inks
        let condensed = WorkoutActivityLook.condenses(typeSize)
        VStack(alignment: .leading, spacing: WorkoutActivityLook.rowGap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: WorkoutActivityLook.labelGap) {
                    HStack(spacing: 6) {
                        if inks.restMarks { RestTimerDot() }
                        Text(workout.label)
                            .font(.caption2.weight(.medium))
                            .accessibilityLabel(spokenLabel)
                    }
                    if !condensed {
                        Text(workout.title)
                            .font(.caption)
                            .privacySensitive()
                    }
                }
                .foregroundStyle(inks.label.colour)
                .lineLimit(1)
                Spacer(minLength: 8)
                WorkoutClock(workout: workout)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(inks.clock.colour)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if inks.restMarks { RestTimerBar(state: workout.state) }
            HStack(alignment: .center, spacing: 12) {
                NextLine(state: workout.state)
                    .font(.subheadline)
                    .foregroundStyle(inks.clock.colour)
                    .lineLimit(WorkoutActivityLook.nextLineLimit(typeSize))
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                OpenPill()
            }
        }
        .padding(WorkoutActivityLook.padding)
        .dynamicTypeSize(...WorkoutActivityLook.largestType)
        // Also painted here: the tint alone isn't applied in every presentation.
        .background(Brand.graphite)
        .accessibilityElement(children: .combine)
    }

    /// "Rest" or "Workout", and the session title after it where the card doesn't draw it (not while a redaction hides
    /// the values, as it hides the drawn title).
    private var spokenLabel: Text {
        let title = WorkoutActivityLook.spokenTitle(workout.title, size: typeSize, concealment: WidgetConcealment(redaction))
        return title.map { Text(workout.label) + Text(verbatim: ", \($0)") } ?? Text(workout.label)
    }
}

/// The island's leading region: the glyph and "Rest" or "Workout" in ink (b-16).
struct WorkoutIslandLabel: View {
    let workout: WorkoutShown

    var body: some View {
        Label {
            Text(workout.label).font(.caption.weight(.medium))
        } icon: {
            Image(systemName: workout.glyph).font(.caption)
        }
        .foregroundStyle(workout.inks.islandLabel.colour)
        .padding(.leading, 4)
        .dynamicTypeSize(...WorkoutActivityLook.largestType)
    }
}

/// The island's trailing region: the clock, 28 Light.
struct WorkoutIslandClock: View {
    let workout: WorkoutShown

    var body: some View {
        WorkoutClock(workout: workout)
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(workout.inks.clock.colour)
            .frame(maxWidth: 110, alignment: .trailing)
    }
}

/// The island's bottom region: the rest's bar while it runs, then the next set (one line) and "Open".
struct WorkoutIslandBottom: View {
    let workout: WorkoutShown

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if workout.inks.restMarks { RestTimerBar(state: workout.state) }
            HStack(spacing: 12) {
                NextLine(state: workout.state)
                    .font(.system(size: 14))
                    .lineLimit(WorkoutActivityLook.islandNextLines)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                OpenPill()
            }
            .foregroundStyle(workout.inks.clock.colour)
        }
        .dynamicTypeSize(...WorkoutActivityLook.largestType)
    }
}

/// Compact and minimal: the glyph in ink, at the default size (the regions are fixed); VoiceOver says "Rest" or
/// "Workout".
struct WorkoutGlyph: View {
    let workout: WorkoutShown

    var body: some View {
        Image(systemName: workout.glyph)
            .foregroundStyle(workout.inks.islandLabel.colour)
            .dynamicTypeSize(...WorkoutActivityLook.glanceLargestType)
            .accessibilityLabel(Text(workout.label))
    }
}

/// Compact's trailing clock, 15 Light.
struct WorkoutCompactClock: View {
    let workout: WorkoutShown

    var body: some View {
        WorkoutClock(workout: workout)
            .font(.system(size: 15, weight: .light))
            .foregroundStyle(workout.inks.clock.colour)
            .frame(maxWidth: 56)
    }
}

/// "Next: Bench press · set 3 of 4 · 5 × 80 kg" (hidden on a locked screen when the user asks iOS to hide sensitive
/// content).
private struct NextLine: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        Text("Next: \(state.next)")
            .privacySensitive()
    }
}

/// While a rest runs: counts down to `endsAt`. Otherwise (and once a rest has run out, even with the app not running to
/// say so) the workout's elapsed time. Tabular digits.
struct WorkoutClock: View {
    let workout: WorkoutShown

    var body: some View {
        Group {
            if workout.restRunning {
                Text(timerInterval: Date.now...workout.state.endsAt, countsDown: true)
            } else {
                Text(timerInterval: min(workout.startedAt, .now)...Date.distantFuture, countsDown: false)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

/// The 6 pt dot before "Rest" while a rest runs: Volt (`Brand.signal`), with `RestTimerBar` the only Volt the extension
/// draws itself. Decoration: the word says the state.
struct RestTimerDot: View {
    var body: some View {
        Circle()
            .fill(Brand.signal)
            .frame(width: WorkoutActivityLook.dot, height: WorkoutActivityLook.dot)
            .accessibilityHidden(true)
    }
}

/// The rest's bar while it runs: Volt on the system's track (`ProgressView(timerInterval:)` is the only progress the
/// system animates without updates; its track isn't ours to colour). The clock says the time, so VoiceOver skips it.
struct RestTimerBar: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        let start = state.endsAt.addingTimeInterval(-state.totalSec)
        ProgressView(timerInterval: min(start, .now)...max(state.endsAt, .now), countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(Brand.signal)
        .accessibilityHidden(true)
    }
}

/// "Open" goes to the live session in the app: the light pill (F24, D6C-10), the widget's `PillButton(.primary)` at the
/// activity's scale: 32 high, ink fill, graphite 14 Medium.
struct OpenPill: View {
    var body: some View {
        if let url = Brand.deepLink {
            Link(destination: url) {
                Text("Open")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Brand.graphite)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(height: WorkoutActivityLook.openPill)
                    .background(WidgetInk.primary.colour, in: Capsule())
            }
        }
    }
}

// MARK: - previews (synthetic: "Upper A", bench press)

private extension RestTimerAttributes {
    static let preview = RestTimerAttributes(sessionTitle: "Upper A", startedAt: .now.addingTimeInterval(-23 * 60),
                                             sessionID: UUID())
}

private extension RestTimerAttributes.ContentState {
    static let resting = RestTimerAttributes.ContentState(endsAt: .now.addingTimeInterval(114), totalSec: 180,
                                                          exercise: "Bench press",
                                                          next: "Bench press · set 2 of 4 · 5 × 80 kg", resting: true)
    static let working = RestTimerAttributes.ContentState(endsAt: .now, totalSec: 0, exercise: "Upper A",
                                                          next: "Bench press · set 2 of 4 · 5 × 80 kg", resting: false)
}

#Preview("Lock screen", as: .content, using: RestTimerAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState.resting
    RestTimerAttributes.ContentState.working
}

#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: RestTimerAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState.resting
    RestTimerAttributes.ContentState.working
}

#Preview("Compact", as: .dynamicIsland(.compact), using: RestTimerAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState.resting
    RestTimerAttributes.ContentState.working
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: RestTimerAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState.resting
    RestTimerAttributes.ContentState.working
}
