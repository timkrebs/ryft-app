// Rest timer Live Activity (lock screen + Dynamic Island). Local only: started,
// updated and ended from the app, no push.
import ActivityKit
import Foundation

/// Keep identical to `RyftWidgets/RestTimerAttributes.swift`: ActivityKit
/// matches the app's and the extension's type by name and Codable shape.
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the rest is over; the activity counts down to it while `resting`.
        var endsAt: Date
        var totalSec: Double
        /// The exercise just done.
        var exercise: String
        /// "Bench press · set 3 of 4 · 5 × 80 kg".
        var next: String
        /// Resting: the countdown. Otherwise the workout's elapsed time and the next set.
        var resting: Bool

        init(endsAt: Date, totalSec: Double, exercise: String, next: String, resting: Bool) {
            self.endsAt = endsAt
            self.totalSec = totalSec
            self.exercise = exercise
            self.next = next
            self.resting = resting
        }

        // An activity an older version started has no `resting`: it was a rest.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            endsAt = try c.decode(Date.self, forKey: .endsAt)
            totalSec = try c.decode(Double.self, forKey: .totalSec)
            exercise = try c.decode(String.self, forKey: .exercise)
            next = try c.decode(String.self, forKey: .next)
            resting = try c.decodeIfPresent(Bool.self, forKey: .resting) ?? true
        }
    }

    var sessionTitle: String
    /// When the workout started: the elapsed time counts from it.
    var startedAt: Date
    /// The workout it shows; `nil` for one an older version started (never reused).
    var sessionID: UUID?

    init(sessionTitle: String, startedAt: Date, sessionID: UUID?) {
        self.sessionTitle = sessionTitle
        self.startedAt = startedAt
        self.sessionID = sessionID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionTitle = try c.decode(String.self, forKey: .sessionTitle)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? .distantPast
        sessionID = try c.decodeIfPresent(UUID.self, forKey: .sessionID)
    }
}

/// The workout on the lock screen and in the Dynamic Island, from the session's start to its
/// end: elapsed time and the next set, and the countdown while resting. Local only: started,
/// updated and ended from the app, no push.
@MainActor
final class RestActivityController {
    static let shared = RestActivityController()

    /// Opens the live session (`RyftApp.onOpenURL`).
    static let deepLink = URL(string: "ryft://train/session")

    private var activity: Activity<RestTimerAttributes>?

    /// The one showing `session`, also when an earlier launch started it. Another workout's (or
    /// an older version's) is ended rather than reused.
    private func current(for session: UUID) -> Activity<RestTimerAttributes>? {
        if let activity, activity.activityState == .active, activity.attributes.sessionID == session { return activity }
        activity = nil
        for a in Activity<RestTimerAttributes>.activities where a.activityState == .active {
            if a.attributes.sessionID == session {
                activity = a
            } else {
                Task { await a.end(nil, dismissalPolicy: .immediate) }
            }
        }
        return activity
    }

    /// The workout without a rest: elapsed time and the next set (starts the activity).
    func workout(session: UUID, title: String, startedAt: Date, next: String) {
        let state = RestTimerAttributes.ContentState(endsAt: .now, totalSec: 0, exercise: title, next: next,
                                                     resting: false)
        put(state, session: session, title: title, startedAt: startedAt, staleDate: nil)
    }

    /// Resting until `endsAt`; it goes stale then, and the lock screen shows the workout again
    /// even if the app isn't running to say so.
    func show(session: UUID, title: String, startedAt: Date, endsAt: Date, total: TimeInterval, exercise: String,
              next: String) {
        let state = RestTimerAttributes.ContentState(endsAt: endsAt, totalSec: total, exercise: exercise, next: next,
                                                     resting: true)
        put(state, session: session, title: title, startedAt: startedAt, staleDate: endsAt)
    }

    /// The rest is over: back to the workout and its next set.
    func finish(session: UUID, next: String) {
        guard let activity = current(for: session) else { return }
        var state = activity.content.state
        state.resting = false
        state.next = next
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func put(_ state: RestTimerAttributes.ContentState, session: UUID, title: String, startedAt: Date,
                     staleDate: Date?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: staleDate)
        if let activity = current(for: session) {
            Task { await activity.update(content) }
            return
        }
        do {
            activity = try Activity.request(attributes: RestTimerAttributes(sessionTitle: title, startedAt: startedAt,
                                                                            sessionID: session),
                                            content: content, pushType: nil)
        } catch {
            TrainStore.log.notice("Workout Live Activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The workout ended (finished, discarded, signed out).
    func end() {
        endAll(except: nil)
    }

    /// At launch: every activity but the running workout's goes.
    func endAll(except session: UUID?) {
        let stale = Activity<RestTimerAttributes>.activities.filter { session == nil || $0.attributes.sessionID != session }
        if activity.map({ a in stale.contains { $0.id == a.id } }) ?? false { activity = nil }
        Task {
            for a in stale { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
