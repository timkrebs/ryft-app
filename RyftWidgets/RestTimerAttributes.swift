import ActivityKit
import Foundation

/// Keep identical to `Ryft/Train/RestActivity.swift`: ActivityKit matches the
/// app's and the extension's type by name and Codable shape.
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

    init(sessionTitle: String, startedAt: Date) {
        self.sessionTitle = sessionTitle
        self.startedAt = startedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionTitle = try c.decode(String.self, forKey: .sessionTitle)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? .now
    }
}
