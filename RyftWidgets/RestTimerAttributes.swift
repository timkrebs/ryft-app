import ActivityKit
import Foundation

/// Keep identical to `Ryft/Train/RestActivity.swift`: ActivityKit matches the
/// app's and the extension's type by name and Codable shape.
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
