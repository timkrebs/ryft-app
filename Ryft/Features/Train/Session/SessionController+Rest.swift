import Foundation

/// What the Focused layout's rest pill shows (design.md §2.7). Derived, so a page change, the keypad or a check can't leave
/// it stale.
enum RestPillState: Equatable {
    /// Nothing to rest for, or the keypad needs the room.
    case hidden
    /// The exercise's rest, ready to start.
    case idle
    case running
    /// "Rest over", for a moment.
    case finished

    /// No exercises or all sets done: no pill (architecture.md §7). A running rest and its end show over the keypad; only
    /// the idle pill gives way to it.
    static func resolve(_ phase: RestTimer.Phase, keypadOpen: Bool, hasExercises: Bool, isAllDone: Bool) -> RestPillState {
        guard hasExercises, !isAllDone else { return .hidden }
        switch phase {
        case .idle: return keypadOpen ? .hidden : .idle
        case .running: return .running
        case .finished: return .finished
        }
    }
}

/// The length the rest sheet's Start begins (design.md §4c): it starts at the exercise's rest and changes nothing else.
struct RestDraft: Equatable {
    static let step = 15
    /// The sheet's floor. `SessionTargets.rest` starts at 0, which is no rest; the ceiling is the same.
    static let range = 15...SessionTargets.rest.upperBound

    private(set) var seconds: Int

    init(seconds: Int) { self.seconds = seconds }

    var canDecrease: Bool { seconds > Self.range.lowerBound }
    var canIncrease: Bool { seconds < Self.range.upperBound }
    /// An exercise can rest 0:00, which starts nothing (`RestTimer.start`).
    var canStart: Bool { seconds > 0 }

    mutating func adjust(by delta: Int) {
        seconds = min(max(seconds + delta, Self.range.lowerBound), Self.range.upperBound)
    }
}

extension SessionController {
    var restPillState: RestPillState {
        RestPillState.resolve(rest.phase, keypadOpen: focus != nil, hasExercises: !exercises.isEmpty, isAllDone: isAllDone)
    }

    /// The pill's VoiceOver value. A rest in steps of 5 s, as `train.rest.value`, so it doesn't chatter.
    func restPillValue(at date: Date) -> String {
        switch restPillState {
        case .running:
            let left = Int((rest.remaining(at: date) / 5).rounded(.up)) * 5
            return RestSpeech.value(seconds: left, next: spokenNext)
        case .finished:
            return String(localized: "Rest over")
        case .idle, .hidden:
            return RestSpeech.idle(seconds: pageExercise?.restSec ?? 0)
        }
    }

    /// "next Bench press set 2 of 4": the row the user will see. `nextLabel()`'s text is for the eye: it adds the target.
    private var spokenNext: String? {
        guard let next = nextUp else { return nil }
        let at = position(of: next.set, in: next.exercise)
        return at.isWarmup
            ? String(localized: "next \(next.exercise.name) warm-up \(at.number) of \(at.count)",
                     comment: "VoiceOver, the rest pill: the next set when it is a warm-up, e.g. next Bench press warm-up 1 of 2.")
            : String(localized: "next \(next.exercise.name) set \(at.number) of \(at.count)",
                     comment: "VoiceOver, the rest pill: the next set, e.g. next Bench press set 2 of 4.")
    }
}

/// The pill's spoken parts, each localised on its own: German orders them differently.
enum RestSpeech {
    /// "1 minute 54 seconds left, next Bench press set 2 of 4". Exact: the caller decides the step.
    static func value(seconds: Int, next: String?) -> String {
        let left = String(localized: "\(duration(seconds)) left",
                          comment: "VoiceOver, the rest pill: the time left, e.g. 1 minute 54 seconds left.")
        return [left, next].compactMap(\.self).joined(separator: ", ")
    }

    /// "Not running. Starts at 1 minute 15 seconds".
    static func idle(seconds: Int) -> String {
        String(localized: "Not running. Starts at \(duration(seconds))",
               comment: "VoiceOver, the idle rest pill. 1: the exercise's rest, e.g. 1 minute 15 seconds.")
    }

    /// "1 minute 54 seconds", "2 minutes", "45 seconds": one unit at a time, so it has no comma to pause on.
    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60, rest = seconds % 60
        let parts = [minutes > 0 ? Duration.seconds(minutes * 60).formatted(.units(allowed: [.minutes], width: .wide)) : nil,
                     rest > 0 || minutes == 0 ? Duration.seconds(rest).formatted(.units(allowed: [.seconds], width: .wide)) : nil]
        return parts.compactMap(\.self).joined(separator: " ")
    }
}
