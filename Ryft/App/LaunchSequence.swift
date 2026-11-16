// The launch sequence's rules and timing as plain values (ADR 0017; docs/work/2026-11-16-nocturne/launch-design.md
// §5 and §6): whether a launch plays it (`LaunchPolicy`), and where a playing sequence is at any moment
// (`LaunchSequence`). Pure: the phase, the progress and the hand-off are functions of a date, so every rule is a row in
// a test. `LaunchSequenceModel` keeps one for the process and refreshes on events and deadlines; `LaunchOverlay` draws
// it. Foundation, plus SwiftUI only for `ScenePhase`.
import Foundation
import SwiftUI
import UIKit

/// Why a launch shows no sequence: decided at init (`LaunchPolicy`), or an event while it was still armed.
enum LaunchSkip: String, Sendable {
    /// A HealthKit delivery, a background task, a silent push: nobody is looking.
    case backgroundLaunch
    /// A UI test, a screenshot run, `-RyftScreen`: any launch argument, or `-RyftLaunchSequence skip`.
    case harness
    /// A workout is open: its banner and cover come at once.
    case workoutActive
    /// The app went to the background less than 10 minutes ago (L9): an evicted app reopened feels like a return.
    case recentlyUsed
    /// The scene's first `.active` came more than `coldStartWindow` after init: a background launch opened later.
    case lateActivation
    /// Backgrounded before it played.
    case backgrounded
    /// A link, a notification, a quick action or Handoff opened the app (`UIScene.ConnectionOptions.carriesPurpose`).
    case purposeLaunch
    /// A root sheet or cover is presenting (`RootView.presentsSomething`).
    case presentation
}

/// What ends the sequence early from outside the scene's phase.
enum LaunchInterruption: String, Sendable {
    case purposeLaunch, presentation

    var skip: LaunchSkip {
        switch self {
        case .purposeLaunch: return .purposeLaunch
        case .presentation: return .presentation
        }
    }
}

enum LaunchDecision: Equatable, Sendable {
    case play(LaunchSequence.Variant)
    case skip(LaunchSkip)

    /// The `launch-decision` signpost's message: `play-full`, `play-reduced` or `skip-<reason>`.
    var signpostName: String {
        switch self {
        case .play(let variant): return "play-\(variant.rawValue)"
        case .skip(let reason): return "skip-\(reason.rawValue)"
        }
    }
}

/// What `LaunchPolicy` decides from: read once in `RyftApp.init`, plain values in tests.
struct LaunchContext: Equatable, Sendable {
    /// `-RyftLaunchSequence play | skip`.
    enum Override: String, Sendable { case play, skip }

    /// `UIApplication.shared.applicationState == .background` at init.
    var launchedInBackground: Bool
    /// `ProcessInfo.arguments.count > 1`: no launch from the Home Screen, the App Store or TestFlight carries one.
    var hasLaunchArguments: Bool
    var override: Override?
    var reduceMotion: Bool
    var lowPower: Bool
    var voiceOver: Bool
    /// A workout is open (`TrainCoordinator.shared.active != nil`).
    var workoutActive: Bool
    /// Since the scene last went to the background (`launch.lastBackgroundAt`), in seconds; nil if it never did.
    var secondsSinceLastBackground: TimeInterval?

    init(launchedInBackground: Bool = false, hasLaunchArguments: Bool = false, override: Override? = nil,
         reduceMotion: Bool = false, lowPower: Bool = false, voiceOver: Bool = false, workoutActive: Bool = false,
         secondsSinceLastBackground: TimeInterval? = nil) {
        self.launchedInBackground = launchedInBackground
        self.hasLaunchArguments = hasLaunchArguments
        self.override = override
        self.reduceMotion = reduceMotion
        self.lowPower = lowPower
        self.voiceOver = voiceOver
        self.workoutActive = workoutActive
        self.secondsSinceLastBackground = secondsSinceLastBackground
    }

    /// The `UserDefaults` key of the last time the scene went to the background (L9).
    static let lastBackgroundKey = "launch.lastBackgroundAt"
    /// The launch argument (`-RyftLaunchSequence play | skip`), read from the argument domain.
    static let overrideKey = "RyftLaunchSequence"

    /// The scene went to the background now (`RyftApp`'s `.background` branch).
    static func recordBackground(at date: Date, in defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastBackgroundKey)
    }

    /// The only reader of process state. `RyftApp.init` passes the two values it has already read.
    @MainActor
    static func current(launchedInBackground: Bool, workoutActive: Bool, now: Date = Date(),
                        defaults: UserDefaults = .standard) -> LaunchContext {
        let last = defaults.object(forKey: lastBackgroundKey) as? Date
        return LaunchContext(launchedInBackground: launchedInBackground,
                             hasLaunchArguments: ProcessInfo.processInfo.arguments.count > 1,
                             override: defaults.string(forKey: overrideKey).flatMap(Override.init(rawValue:)),
                             reduceMotion: UIAccessibility.isReduceMotionEnabled,
                             lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                             voiceOver: UIAccessibility.isVoiceOverRunning,
                             workoutActive: workoutActive,
                             secondsSinceLastBackground: last.map { now.timeIntervalSince($0) })
    }
}

/// Whether this launch plays the sequence (launch-design.md §6.2, rows 1–6, and L9), checked from the top.
enum LaunchPolicy {
    /// Back within this long after going to the background: no sequence (L9).
    static let recentWindow: TimeInterval = 10 * 60

    static func decide(_ context: LaunchContext) -> LaunchDecision {
        // 1. Forced.
        if context.override == .skip { return .skip(.harness) }
        // 2. Nobody is looking; `play` never overrides it.
        if context.launchedInBackground { return .skip(.backgroundLaunch) }
        // 3. UI tests, screenshot runs, `-RyftScreen`: any argument, unless `play` asks for it.
        if context.hasLaunchArguments, context.override != .play { return .skip(.harness) }
        // 4. An open workout comes first; `play` never overrides it either.
        if context.workoutActive { return .skip(.workoutActive) }
        // L9. A reopen that feels like a return. `play` overrides it, so a harness that plays it is deterministic.
        if context.override != .play, let since = context.secondsSinceLastBackground, since >= 0, since < recentWindow {
            return .skip(.recentlyUsed)
        }
        // 5. The static frame and a cross-fade.
        if context.reduceMotion || context.lowPower || context.voiceOver { return .play(.reduced) }
        // 6. Demo mode included.
        return .play(.full)
    }
}

/// One launch's sequence: the decision, when it was created and started, and how it ended. Phase, progress and hand-off
/// are functions of a date; `send` records an event at its date. `done` and `skipped` are terminal.
struct LaunchSequence: Equatable, Sendable {
    enum Variant: String, Sendable {
        /// The 5.2 s timeline (`LaunchFrame`).
        case full
        /// Reduce Motion, Low Power Mode, VoiceOver: the last frame (L11), faded in, held, cross-faded out.
        case reduced
    }

    enum Phase: String, CaseIterable, Sendable {
        /// Waiting for the scene's first `.active`; the overlay is only the launch screen's colour.
        case armed
        /// The timeline runs; the overlay covers the root and takes every tap.
        case playing
        /// The overlay fades out; the root is visible to VoiceOver and takes taps.
        case handingOff
        /// Over; the overlay is gone.
        case done
        /// It never played (or only the armed fill was ever drawn); the overlay is gone.
        case skipped
    }

    enum Event: Equatable, Sendable {
        case scene(ScenePhase)
        /// A tap anywhere, or VoiceOver's activate or "Skip" action.
        case tap
        case interrupted(LaunchInterruption)
    }

    enum Ending: Equatable, Sendable {
        case finished, tapped, systemUI, backgrounded
        case interrupted(LaunchInterruption)
        case skipped(LaunchSkip)

        /// The `launch-sequence` interval's end message.
        var signpostName: String {
            switch self {
            case .finished: return "finished"
            case .tapped: return "tapped"
            case .systemUI: return "system-ui"
            case .backgrounded: return "backgrounded"
            case .interrupted(let reason): return "interrupted-\(reason.rawValue)"
            case .skipped(let reason): return "skipped-\(reason.rawValue)"
            }
        }

        /// VoiceOver moves to the root once it is uncovered (`ScreenChanged`), unless what ended the sequence owns the
        /// focus: a sheet, system UI, the background.
        var movesFocusToRoot: Bool {
            switch self {
            case .finished, .tapped, .interrupted(.purposeLaunch), .skipped(.purposeLaunch), .skipped(.lateActivation):
                return true
            case .systemUI, .backgrounded, .interrupted(.presentation), .skipped:
                return false
            }
        }
    }

    struct Timing: Equatable, Sendable {
        /// How long `playing` lasts when nothing ends it.
        var duration: TimeInterval
        /// The fade into the root at the natural end.
        var handOff: TimeInterval
        /// The fade after a tap, system UI or an interruption.
        var quickHandOff: TimeInterval
        /// The frame's own fade-in at the start (the reduced variant; the full timeline fades its group itself).
        var fadeIn: TimeInterval

        /// 5.2 s (`LaunchFrame.duration`), then `Theme.Motion.standard`'s 0.4 s.
        static let full = Timing(duration: LaunchFrame.duration, handOff: 0.4, quickHandOff: 0.25, fadeIn: 0)
        /// The last frame fades in over `Theme.Motion.quick`'s 0.25 s and holds until 1.0 s, then 0.25 s out.
        static let reduced = Timing(duration: 1.0, handOff: 0.25, quickHandOff: 0.25, fadeIn: 0.25)

        /// The first `.active` must come within this long after init, or it is a background launch opened later.
        static let coldStartWindow: TimeInterval = 5
    }

    let decision: LaunchDecision
    let createdAt: Date
    /// The first `.active` (the clock's start).
    private(set) var startedAt: Date?
    /// An event's hand-off (tap, system UI, interruption): when it started, and its fade.
    private(set) var handOffAt: Date?
    private(set) var handOffFade: TimeInterval?
    /// Backgrounded while playing or handing off: over at once.
    private(set) var endedAt: Date?
    /// Set by an event; nil for the natural end.
    private(set) var recordedEnding: Ending?
    /// Armed and then skipped by an event.
    private(set) var skippedBy: LaunchSkip?

    init(decision: LaunchDecision, createdAt: Date) {
        self.decision = decision
        self.createdAt = createdAt
    }

    var variant: Variant? {
        if case .play(let variant) = decision { return variant }
        return nil
    }

    var timing: Timing { variant == .reduced ? .reduced : .full }

    // MARK: events

    mutating func send(_ event: Event, at date: Date) {
        switch (phase(at: date), event) {
        case (.armed, .scene(.active)):
            if date.timeIntervalSince(createdAt) > Timing.coldStartWindow {
                skippedBy = .lateActivation
            } else {
                startedAt = date
            }
        case (.armed, .scene(.background)):
            skippedBy = .backgrounded
        case (.armed, .interrupted(let reason)):
            skippedBy = reason.skip
        case (.playing, .scene(.inactive)):
            handOff(at: date, ending: .systemUI)
        case (.playing, .tap):
            handOff(at: date, ending: .tapped)
        case (.playing, .interrupted(let reason)):
            handOff(at: date, ending: .interrupted(reason))
        case (.playing, .scene(.background)):
            recordedEnding = .backgrounded
            endedAt = date
        case (.handingOff, .scene(.background)):
            // The ending stays what started the hand-off.
            if recordedEnding == nil { recordedEnding = .finished }
            endedAt = date
        default:
            // Armed: a cold launch passes through `.inactive`; taps do nothing yet. Handing off: taps reach the root.
            // Done and skipped ignore everything.
            break
        }
    }

    private mutating func handOff(at date: Date, ending: Ending) {
        handOffAt = date
        handOffFade = timing.quickHandOff
        recordedEnding = ending
    }

    // MARK: time

    /// When the fade into the root starts (an event's, or the timeline's end); nil before the start.
    var handOffStart: Date? {
        if let handOffAt { return handOffAt }
        return startedAt.map { $0.addingTimeInterval(timing.duration) }
    }

    /// When the overlay is gone; nil before the start.
    var doneAt: Date? {
        if let endedAt { return endedAt }
        return handOffStart.map { $0.addingTimeInterval(handOffFade ?? timing.handOff) }
    }

    func phase(at date: Date) -> Phase {
        guard case .play = decision, skippedBy == nil else { return .skipped }
        guard let startedAt, date >= startedAt, let handOffStart, let doneAt else { return .armed }
        if date >= doneAt { return .done }
        if date >= handOffStart { return .handingOff }
        return .playing
    }

    /// 0...1 of the variant's timeline; 0 before the start. It keeps running through the hand-off, so a tap never
    /// freezes a frame mid-motion.
    func progress(at date: Date) -> Double {
        guard let startedAt else { return 0 }
        return min(max(date.timeIntervalSince(startedAt) / timing.duration, 0), 1)
    }

    /// 0 until the hand-off, then 0...1 over its fade, eased out (`Theme.Motion`). The overlay's opacity is 1 minus this.
    func handOff(at date: Date) -> Double {
        guard let handOffStart else { return 0 }
        if let endedAt, date >= endedAt { return 1 }
        let fade = handOffFade ?? timing.handOff
        guard fade > 0 else { return date >= handOffStart ? 1 : 0 }
        return LaunchFrame.Easing.easeOut(date.timeIntervalSince(handOffStart) / fade)
    }

    /// The t `LaunchFrame` draws: the timeline's progress, or the last frame throughout in the reduced variant (L11).
    func frameProgress(at date: Date) -> Double {
        variant == .reduced ? 1 : progress(at: date)
    }

    /// The frame's own fade-in from the start (the reduced variant's 0.25 s); 1 when there is none.
    func contentOpacity(at date: Date) -> Double {
        guard let startedAt else { return 0 }
        guard timing.fadeIn > 0 else { return 1 }
        return LaunchFrame.Easing.easeOut(date.timeIntervalSince(startedAt) / timing.fadeIn)
    }

    /// Armed or playing: the root is hidden from VoiceOver, takes no taps, and counts as unseen.
    func covers(at date: Date) -> Bool {
        let phase = phase(at: date)
        return phase == .armed || phase == .playing
    }

    /// nil while armed or playing.
    func ending(at date: Date) -> Ending? {
        switch phase(at: date) {
        case .armed, .playing: return nil
        case .skipped:
            if let skippedBy { return .skipped(skippedBy) }
            if case .skip(let reason) = decision { return .skipped(reason) }
            return nil
        case .handingOff, .done: return recordedEnding ?? .finished
        }
    }

    /// When `phase(at:)` next changes by itself; nil if only an event can change it (armed) or it is terminal.
    func nextChange(after date: Date) -> Date? {
        switch phase(at: date) {
        case .playing: return handOffStart
        case .handingOff: return doneAt
        case .armed, .done, .skipped: return nil
        }
    }
}
