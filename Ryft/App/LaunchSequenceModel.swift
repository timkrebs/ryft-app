// The process's one launch sequence (ADR 0017): `RyftApp` owns it for the life of the process, so a re-created scene
// or a second one reads the same, already terminal, sequence and nothing plays twice. It stores the pure
// `LaunchSequence`, records events at the clock's time, and refreshes `phase` on each event and at each deadline; it
// never writes per frame (the overlay renders `sequence` inside a `TimelineView`).
import Foundation
import Observation
import os
import SwiftUI
import UIKit
import UserNotifications

@MainActor
@Observable
final class LaunchSequenceModel {
    private(set) var sequence: LaunchSequence
    /// `sequence.phase(at: clock.now())`, refreshed on each event and at each `nextChange`. Nothing else sets it.
    private(set) var phase: LaunchSequence.Phase
    /// `sequence.ending(at:)`, refreshed with `phase`: nil while armed or playing.
    private(set) var ending: LaunchSequence.Ending?

    /// Armed or playing: the root is hidden from VoiceOver, takes no taps, and counts as unseen (`launchCoversRoot`).
    var coversRoot: Bool { phase == .armed || phase == .playing }
    /// The overlay is in the hierarchy.
    var isOnScreen: Bool { coversRoot || phase == .handingOff }
    /// The overlay's timeline runs.
    var isAnimating: Bool { phase == .playing || phase == .handingOff }

    /// What the model marks for performance-profiler (launch-design §9.2), as values: each goes to `Signposts.launch`
    /// when `signposts` is on, and to `marks` either way.
    enum Mark: Equatable, Sendable {
        /// `launch-decision`, with `LaunchDecision.signpostName`.
        case decision(String)
        /// The `launch-sequence` interval begins: the first `.active`, `armed -> playing`. It covers what the user waits
        /// through, the wait for the overlay's first frame included.
        case began
        /// `launch-first-frame`: the overlay's first frame, the timeline's t = 0 (a natural end hands off 5.2 s later).
        case firstFrame
        /// `launch-handoff`: the root is interactive again, M2's end. Once per run, when `playing` ends: into the fade,
        /// or straight to done when the natural end's wake-up came after the fade too; never when the background ended it.
        case handOff
        /// The `launch-sequence` interval ends, with `Ending.signpostName`.
        case ended(String)
    }

    @ObservationIgnored private let clock: AppClock
    @ObservationIgnored private let signposts: Bool
    /// Every mark, whether or not `signposts` sends it to the system: the tests' window on the signposts.
    @ObservationIgnored private let marks: ((Mark) -> Void)?
    /// The one wait for the next deadline; a new event replaces it, a terminal phase leaves none.
    @ObservationIgnored private var deadline: Task<Void, Never>?
    /// `began` was marked and `ended` not yet.
    @ObservationIgnored private var intervalOpen = false
    @ObservationIgnored private var interval: OSSignpostIntervalState?

    init(decision: LaunchDecision, clock: AppClock, signposts: Bool = true, marks: ((Mark) -> Void)? = nil) {
        self.clock = clock
        self.signposts = signposts
        self.marks = marks
        let now = clock.now()
        let sequence = LaunchSequence(decision: decision, createdAt: now)
        self.sequence = sequence
        phase = sequence.phase(at: now)
        ending = sequence.ending(at: now)
        mark(.decision(decision.signpostName))
        Self.log.debug("launch: \(decision.signpostName, privacy: .public)")
    }

    func send(_ event: LaunchSequence.Event) {
        let now = clock.now()
        let waitedForFirstFrame = sequence.firstFrameAt == nil
        sequence.send(event, at: now)
        if waitedForFirstFrame, sequence.firstFrameAt != nil { mark(.firstFrame) }
        refresh(at: now)
    }

    /// Whether VoiceOver should move to the root now that it was uncovered (`LaunchHost` posts `ScreenChanged`): not
    /// when a sheet, system UI or the background ended the sequence, because that owns the focus.
    var movesFocusToRoot: Bool { !coversRoot && ending?.movesFocusToRoot == true }

    /// Takes the phase at `now`, marks the transitions, and waits for the next deadline (only one wait at a time).
    private func refresh(at now: Date) {
        let new = sequence.phase(at: now)
        let newEnding = sequence.ending(at: now)
        if newEnding != ending { ending = newEnding }
        if new != phase {
            let old = phase
            phase = new
            transition(from: old, to: new)
        }
        deadline?.cancel()
        deadline = nil
        guard let next = sequence.nextChange(after: now) else { return }
        deadline = Task { [weak self, clock] in
            // Measured here, not when scheduled: a clock that moved on meanwhile ends the wait at once.
            let wait = next.timeIntervalSince(clock.now())
            if wait > 0 {
                do { try await clock.sleep(for: .seconds(wait)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            self?.refresh(at: clock.now())
        }
    }

    private func transition(from old: LaunchSequence.Phase, to new: LaunchSequence.Phase) {
        let what = "\(old.rawValue) -> \(new.rawValue)"
        Self.log.debug("launch: \(what, privacy: .public)")
        if new == .playing {
            intervalOpen = true
            mark(.began)
        }
        // A natural end whose wake-up runs 0.4 s late jumps `playing -> done`: the root was still handed over (review PR 3
        // row 15). Leaving `playing` happens once per run, so this marks once.
        if old == .playing, new == .handingOff || (new == .done && ending != .backgrounded) { mark(.handOff) }
        if new == .done || new == .skipped, intervalOpen {
            intervalOpen = false
            mark(.ended(ending?.signpostName ?? "none"))
        }
    }

    private func mark(_ mark: Mark) {
        if signposts {
            switch mark {
            case .decision(let name):
                Signposts.launch.emitEvent("launch-decision", "\(name, privacy: .public)")
            case .began:
                interval = Signposts.launch.beginInterval("launch-sequence", id: Signposts.launch.makeSignpostID())
            case .firstFrame:
                Signposts.launch.emitEvent("launch-first-frame")
            case .handOff:
                Signposts.launch.emitEvent("launch-handoff")
            case .ended(let name):
                if let interval { Signposts.launch.endInterval("launch-sequence", interval, "\(name, privacy: .public)") }
                interval = nil
            }
        }
        marks?(mark)
    }

    private static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "launch")
}

/// UIKit's way in (`QuickActionSceneDelegate`, which SwiftUI's environment never reaches). `RyftApp.init` points it at
/// the process's model; in the unit-test host it stays a no-op.
@MainActor
enum LaunchInterruptions {
    static var post: (LaunchInterruption) -> Void = { _ in }
}

extension UIScene.ConnectionOptions {
    /// The scene connects to show something specific: a URL or universal link, a user activity or Handoff, a quick
    /// action or a notification's response. The launch sequence yields to it (`.purposeLaunch`).
    var carriesPurpose: Bool {
        !urlContexts.isEmpty || !userActivities.isEmpty || handoffUserActivityType != nil
            || shortcutItem != nil || notificationResponse != nil
    }
}

/// Ends the launch sequence for a reason (`RootView`'s presentations). Wraps the closure because `@Entry` refuses a
/// bare one.
struct LaunchInterruptAction: Sendable {
    let action: @MainActor @Sendable (LaunchInterruption) -> Void

    init(_ action: @escaping @MainActor @Sendable (LaunchInterruption) -> Void = { _ in }) {
        self.action = action
    }

    @MainActor func callAsFunction(_ reason: LaunchInterruption) { action(reason) }
}

extension EnvironmentValues {
    /// The launch sequence covers the root (armed or playing): anything that plays once when first seen treats it like
    /// the background and plays at the hand-off (ADR 0017, 7; Today's gauge entrance).
    @Entry var launchCoversRoot = false
    /// Ends the launch sequence early: a root sheet or cover is presenting.
    @Entry var launchInterrupt = LaunchInterruptAction()
}
