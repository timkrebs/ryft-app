// Rest timer Live Activity (lock screen + Dynamic Island). Local only: started,
// updated and ended from the app, no push.
import ActivityKit
import Foundation

/// Keep identical to `RyftWidgets/RestTimerAttributes.swift`: ActivityKit
/// matches the app's and the extension's type by name and Codable shape.
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the rest is over; the activity counts down to it.
        var endsAt: Date
        var totalSec: Double
        /// The exercise just done.
        var exercise: String
        /// "Bench press · set 3 of 4".
        var next: String
        var finished: Bool
    }

    var sessionTitle: String
}

@MainActor
final class RestActivityController {
    static let shared = RestActivityController()

    /// Opens the live session (`RyftApp.onOpenURL`).
    static let deepLink = URL(string: "ryft://train/session")

    private var activity: Activity<RestTimerAttributes>?

    func show(session: String, endsAt: Date, total: TimeInterval, exercise: String, next: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RestTimerAttributes.ContentState(endsAt: endsAt, totalSec: total, exercise: exercise,
                                                     next: next, finished: false)
        let content = ActivityContent(state: state, staleDate: endsAt.addingTimeInterval(60))
        if let activity, activity.activityState == .active {
            Task { await activity.update(content) }
            return
        }
        do {
            activity = try Activity.request(attributes: RestTimerAttributes(sessionTitle: session),
                                            content: content, pushType: nil)
        } catch {
            TrainStore.log.notice("Rest Live Activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Rest is over: "Time for the next set", then gone after two minutes.
    func finish(next: String) {
        guard let activity else { return }
        var state = activity.content.state
        state.finished = true
        state.next = next
        let content = ActivityContent(state: state, staleDate: nil)
        self.activity = nil
        Task { await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(120))) }
    }

    /// Skipped, or the workout ended.
    func end() {
        let all = Activity<RestTimerAttributes>.activities
        activity = nil
        Task {
            for a in all { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
