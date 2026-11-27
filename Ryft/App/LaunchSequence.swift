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
        /// From the first `.active`: the overlay covers the root and takes every tap; the timeline runs from the first
        /// frame it draws (`startedAt`).
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
        /// The overlay put the timeline on screen (`LaunchOverlay`'s `onAppear`): t = 0 is now, not at the scene's
        /// `.active`, which can come 0.15 s earlier in Debug (review PR 3 row 18).
        case firstFrame
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

        /// The hand-off at the natural end when the mark flies into Today's header (L25): the launch's brand-moment
        /// exception to the 250 ms motion rule. A tap keeps `quickHandOff`.
        static let moveHandOff: TimeInterval = 0.5
        /// During the move the background and the tagline fade over this long, so Today shows while the lock-up travels.
        static let moveFade: TimeInterval = 0.25

        /// The first `.active` must come within this long after init, or it is a background launch opened later.
        static let coldStartWindow: TimeInterval = 5
        /// The timeline waits this long after the first `.active` for the overlay's first frame, then starts anyway, so
        /// the overlay can never hold the root; a first frame after it changes nothing.
        static let firstFrameWindow: TimeInterval = 1
    }

    let decision: LaunchDecision
    let createdAt: Date
    private let tapTestWindow: TimeInterval?
    /// The first `.active`: `playing` starts here.
    private(set) var activatedAt: Date?
    /// The overlay's first frame, if it came within `firstFrameWindow` of `activatedAt`.
    private(set) var firstFrameAt: Date?
    /// An event's hand-off (tap, system UI, interruption): when it started, and its fade.
    private(set) var handOffAt: Date?
    private(set) var handOffFade: TimeInterval?
    /// Backgrounded while playing or handing off: over at once.
    private(set) var endedAt: Date?
    /// Set by an event; nil for the natural end.
    private(set) var recordedEnding: Ending?
    /// Armed and then skipped by an event.
    private(set) var skippedBy: LaunchSkip?
    /// Today's header has a `.mark` hand-off target on screen (`setMarkTarget`). Recorded only while armed or playing,
    /// so from the hand-off on it is fixed and `movesMark` is decided once.
    private(set) var hasMarkTarget = false

    init(decision: LaunchDecision, createdAt: Date, holdForTapTest: Bool = false) {
        self.decision = decision
        self.createdAt = createdAt
        tapTestWindow = holdForTapTest ? 60 : nil
    }

    var variant: Variant? {
        if case .play(let variant) = decision { return variant }
        return nil
    }

    var timing: Timing {
        var timing: Timing = variant == .reduced ? .reduced : .full
        if let tapTestWindow { timing.duration = tapTestWindow }
        return timing
    }

    /// The timeline's t = 0: the overlay's first frame, or the end of `firstFrameWindow` if none came by then; nil before
    /// the first `.active`. Until then every frame is t = 0, so the first one drawn fades in from nothing.
    var startedAt: Date? {
        firstFrameAt ?? activatedAt.map { $0.addingTimeInterval(Timing.firstFrameWindow) }
    }

    // MARK: events

    mutating func send(_ event: Event, at date: Date) {
        switch (phase(at: date), event) {
        case (.armed, .scene(.active)):
            if date.timeIntervalSince(createdAt) > (tapTestWindow ?? Timing.coldStartWindow) {
                skippedBy = .lateActivation
            } else {
                activatedAt = date
            }
        case (.playing, .firstFrame):
            // The first one only, and only while the timeline still waits for it.
            if firstFrameAt == nil, let activatedAt, date.timeIntervalSince(activatedAt) <= Timing.firstFrameWindow {
                firstFrameAt = max(date, activatedAt)
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
            // Armed: a cold launch passes through `.inactive`; taps do nothing yet. Handing off: taps reach the root, and
            // a first frame after a tap starts nothing. Done and skipped ignore everything.
            break
        }
    }

    /// Whether a `.mark` target (Today's header lock-up) is on screen; taken only while armed or playing.
    mutating func setMarkTarget(_ present: Bool, at date: Date) {
        let phase = phase(at: date)
        guard phase == .armed || phase == .playing else { return }
        hasMarkTarget = present
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
        return handOffStart.map { $0.addingTimeInterval(handOffDuration) }
    }

    /// The hand-off's length: an event's quick fade, else 0.5 s when the mark moves (L25), else the variant's fade.
    var handOffDuration: TimeInterval {
        handOffFade ?? (movesMark ? Timing.moveHandOff : timing.handOff)
    }

    // MARK: the matched move (design.md §P4-7, launch-design.md §7.5)

    /// The mark has formed by this share of the timeline (the wordmark and the colour are done): a hand-off from here on
    /// may move it.
    static let markFormed = LaunchFrame.Key.wordmarkTo

    /// The mark and "RYFT" fly into Today's header lock-up instead of fading: the full variant, a `.mark` target on
    /// screen, the mark formed when the hand-off starts, and a hand-off the person chose or the timeline's end (a tap or
    /// the natural end). Anything else (the reduced variant, a skip before 0.86, another root, system UI or an
    /// interruption, which take the screen) keeps the cross-fade. Fixed from the hand-off on (`setMarkTarget`).
    var movesMark: Bool {
        guard variant == .full, hasMarkTarget, Self.endingMovesMark(recordedEnding), let start = handOffStart else { return false }
        return progress(at: start) >= Self.markFormed
    }

    /// The natural end (no event, or `.finished` once backgrounded in its hand-off) and a tap may move the mark; system
    /// UI, an interruption and the background don't (CR6).
    static func endingMovesMark(_ ending: Ending?) -> Bool {
        switch ending {
        case nil, .finished, .tapped: return true
        case .systemUI, .backgrounded, .interrupted, .skipped: return false
        }
    }

    /// 0...1 of the hand-off's duration, linear; 0 before it, 1 after.
    func moveTime(at date: Date) -> Double {
        guard let start = handOffStart else { return 0 }
        if let endedAt, date >= endedAt { return 1 }
        let duration = handOffDuration
        guard duration > 0 else { return date >= start ? 1 : 0 }
        return min(max(date.timeIntervalSince(start) / duration, 0), 1)
    }

    /// The mark's progress through the move: E1 of `moveTime(at:)`.
    func moveProgress(at date: Date) -> Double {
        LaunchFrame.markMoveProgress(moveTime(at: date))
    }

    /// The background's and the tagline's opacity during the move: `1 − easeOut(elapsed / 0.25)`, so they are gone 0.25
    /// s in while the lock-up still travels; 1 before the hand-off.
    func moveFade(at date: Date) -> Double {
        guard let start = handOffStart else { return 1 }
        if let endedAt, date >= endedAt { return 0 }
        return 1 - LaunchFrame.Easing.easeOut(date.timeIntervalSince(start) / Timing.moveFade)
    }

    func phase(at date: Date) -> Phase {
        guard case .play = decision, skippedBy == nil else { return .skipped }
        guard let activatedAt, date >= activatedAt, let handOffStart, let doneAt else { return .armed }
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

    /// 0 until the hand-off, then 0...1 over its fade, eased out (`Theme.Motion`). The overlay's opacity is 1 minus this
    /// (with the matched move, the overlay fades its background and tagline by `moveFade(at:)` instead).
    func handOff(at date: Date) -> Double {
        guard let handOffStart else { return 0 }
        if let endedAt, date >= endedAt { return 1 }
        let fade = handOffDuration
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
