import Foundation

/// How `HostedWindow.settle` and `wait` tell "still moving" from "the runner is slow". The window is not needed for that, so the
/// rule lives here and `HostedSettlingTests` drive it with a scripted sampler.
///
/// The hosted tests share one main actor with every other `@MainActor` test, and on CI that actor is held for hundreds of
/// milliseconds at a time (the render tests): a 50 ms pause came back after about 1.2 s there, and 5 samples took the whole
/// 6 s that a wall-clock deadline allowed, with the layout quiet since the first. So time is not what a layout gets to
/// move for. A budget counts samples that found something moving (a stalled runner takes fewer samples, never more changing
/// ones), quiet needs time as well as samples, and only a generous wall-clock limit bounds the rest, for a runner that is
/// wedged rather than slow.
enum HostedSettling {
    /// One element as the accessibility tree reports it: its label and its frame (or the page's scroll offset), as text.
    struct Entry: Equatable {
        let label: String
        let frame: String
    }

    /// The time between two samples when nothing stalls.
    static let interval = Duration.milliseconds(50)
    /// Samples in a row that must agree. Each one came after the main actor had run its turn, so a stall in the middle of an
    /// animation shows as a change, not as a quiet layout.
    static let quietSamples = 5
    /// How long the layout must have stood still: twice a scroll's 250 ms animation. When nothing stalls this is what
    /// decides (about 10 samples), on a stalled runner the samples do.
    static let quietFor = Duration.milliseconds(500)
    /// The most a wait may take whatever the runner does: half a unit test's 60 s limit, so the failure names its cause
    /// instead of the test timing out without a word.
    static let wallLimit = Duration.seconds(30)

    /// Samples until `quietSamples` in a row are equal and `quietFor` has passed since the last change. Throws
    /// `HostedWindow.HostError.timeout` naming what moved when more than `movingSamples` samples differed from the one before,
    /// or when `wallLimit` passed first.
    @MainActor
    static func untilQuiet(movingSamples: Int, quietFor: Duration = HostedSettling.quietFor, wallLimit: Duration = HostedSettling.wallLimit,
                           sample: () -> [Entry],
                           pause: () async throws -> Void = { try await Task.sleep(for: HostedSettling.interval) }) async throws {
        let start = ContinuousClock.now
        var last = sample(), quiet = 0, moving = 0, taken = 0, lastMove = "", lastChange = start
        while quiet < quietSamples || ContinuousClock.now - lastChange < quietFor {
            if moving > movingSamples || ContinuousClock.now - start >= wallLimit {
                let seconds = seconds(ContinuousClock.now - start)
                let why = moving > movingSamples
                    ? "still moving, \(moving) changing samples of \(taken)"
                    : "ran out of time, \(taken) samples in \(seconds) s and the last \(quiet) quiet"
                throw HostedWindow.HostError.timeout("the layout to settle (\(why); last change: \(lastMove.isEmpty ? "none" : lastMove))")
            }
            try await pause()
            let now = sample()
            taken += 1
            if now == last {
                quiet += 1
            } else {
                quiet = 0
                moving += 1
                lastChange = ContinuousClock.now
                lastMove = describe(from: last, to: now)
            }
            last = now
        }
    }

    /// Polls `condition` until it holds. Gives up after `polls` checks that found it false, or when `wallLimit` passed first:
    /// a slow runner makes fewer polls in the same time, and the condition may need every one of them.
    @MainActor
    static func until(_ what: String, polls: Int, wallLimit: Duration = HostedSettling.wallLimit, condition: () -> Bool,
                      pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(25)) }) async throws {
        let start = ContinuousClock.now
        var taken = 0
        while !condition() {
            if taken >= polls || ContinuousClock.now - start >= wallLimit {
                throw HostedWindow.HostError.timeout("\(what) (\(taken) polls in \(seconds(ContinuousClock.now - start)) s)")
            }
            try await pause()
            taken += 1
        }
    }

    /// What differs between two samples, for a failure message: the first three elements that moved, then a changed count.
    static func describe(from old: [Entry], to new: [Entry]) -> String {
        func short(_ label: String) -> String { label.count > 40 ? String(label.prefix(40)) + "..." : label }
        var moved: [String] = []
        for (a, b) in zip(old, new) where a != b && moved.count < 3 {
            moved.append(a.label == b.label ? "\(short(b.label)) \(a.frame) -> \(b.frame)" : "\(short(a.label)) -> \(short(b.label))")
        }
        if old.count != new.count { moved.append("\(old.count) -> \(new.count) elements") }
        return moved.joined(separator: "; ")
    }

    private static func seconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.1f", value)
    }
}
