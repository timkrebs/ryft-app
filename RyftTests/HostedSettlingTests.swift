import Foundation
import Testing
@testable import Ryft

/// The rule behind `HostedWindow.settle` and `wait`: quiet is a run of equal samples that has also lasted long enough, a
/// stalled runner is not a moving layout, and a layout that never rests fails naming what moved. A scripted sampler stands in
/// for the window and a clock moved by hand for time, so none of this depends on the accessibility tree or on how busy the
/// runner is.
@MainActor
@Suite("Hosted settling")
struct HostedSettlingTests {
    private typealias Entry = HostedSettling.Entry

    /// Time that only moves when a script's pause says so.
    private final class FakeClock {
        let base = ContinuousClock.now
        var elapsed = Duration.zero
        var now: ContinuousClock.Instant { base + elapsed }
        func advance(_ step: Duration) { elapsed += step }
    }

    private func box(_ x: Double) -> [Entry] {
        [Entry(label: "Box", frame: "(\(x), 0.0, 10.0, 10.0)"), Entry(label: "Title", frame: "(0.0, 0.0, 50.0, 20.0)")]
    }

    /// The message of the timeout `body` throws, nil when it returns.
    private func timeoutMessage(_ body: () async throws -> Void) async -> String? {
        do {
            try await body()
            return nil
        } catch let HostedWindow.HostError.timeout(message) {
            return message
        } catch {
            return "not a timeout: \(error)"
        }
    }

    /// Runs `untilQuiet` on a fake clock that moves `step` per pause. `layout` gives the sample at its 1-based number and the
    /// time it is taken at. Returns how many samples it took and when it returned.
    private func quiet(step: Duration = .milliseconds(50), movingSamples: Int = 100, quietFor: Duration = .zero,
                       wallLimit: Duration = HostedSettling.wallLimit,
                       layout: (_ sample: Int, _ at: Duration) -> Double) async throws -> (samples: Int, at: Duration) {
        let clock = FakeClock()
        var samples = 0
        try await HostedSettling.untilQuiet(movingSamples: movingSamples, quietFor: quietFor, wallLimit: wallLimit, now: { clock.now },
                                            sample: { samples += 1; return box(layout(samples, clock.elapsed)) },
                                            pause: { clock.advance(step) })
        return (samples, clock.elapsed)
    }

    @Test("A quiet layout returns after the first sample and five equal ones")
    func quietReturns() async throws {
        let done = try await quiet { _, _ in 0 }
        #expect(done.samples == 6)
    }

    @Test("A change after equal samples starts the run again: 0 0 0 0 1 1 1 ... returns at sample 10, not 7")
    func aChangeResetsTheRun() async throws {
        let done = try await quiet { sample, _ in sample <= 4 ? 0 : 1 }
        // Sample 5 is the change; samples 6 to 10 are the five that equal it. Without the reset the four equal samples
        // before the change would count, and it would return at sample 7.
        #expect(done.samples == 10)
    }

    @Test("A run of changes then equal samples returns five equal samples after the last change")
    func equalSamplesAfterTheLastChange() async throws {
        let done = try await quiet { sample, _ in Double(min(sample, 4)) }
        #expect(done.samples == 9)
    }

    @Test("The quiet time counts from the last change, not from the start: a change at 300 ms returns at 800 ms")
    func quietTimeRunsFromTheLastChange() async throws {
        // The first sample is at t = 0, then one per 50 ms; the layout moves at t = 300 ms (sample 7). Counted from the start,
        // 500 ms is over at sample 11 and five equal samples are there by t = 550 ms; counted from the change it is t = 800 ms.
        let done = try await quiet(quietFor: .milliseconds(500)) { _, at in at >= .milliseconds(300) ? 1 : 0 }
        #expect(done.samples == 17)
        #expect(done.at == .milliseconds(800))
    }

    @Test("Quiet takes time as well as samples: 200 ms with nothing moving")
    func quietTakesTime() async throws {
        let done = try await quiet(step: .milliseconds(20), quietFor: .milliseconds(200)) { _, _ in 0 }
        #expect(done.at == .milliseconds(200))
        #expect(done.samples == 11)
    }

    @Test("A frame that keeps changing times out and the message names it")
    func movingForeverFails() async {
        let message = await timeoutMessage { _ = try await quiet(movingSamples: 8) { sample, _ in Double(sample) } }
        let text = message ?? ""
        #expect(text.contains("the layout to settle"), "\(text)")
        #expect(text.contains("still moving, 9 changing samples"), "\(text)")
        #expect(text.contains("Box (") && text.contains("->"), "the box that moved, from and to: \(text)")
        #expect(!text.contains("Title"), "the title stood still: \(text)")
    }

    @Test("A runner that is slow, not a layout that moves, does not fail the wait")
    func aSlowRunnerStillSettles() async throws {
        // Every pause takes 1.2 s, as on a CI main actor held by render tests. The budget for a layout that moves is one
        // sample (50 ms of a quiet runner); seven samples take 7.2 s, and a wall-clock deadline of 6 s fails them.
        let done = try await quiet(step: .milliseconds(1200), movingSamples: 1, quietFor: HostedSettling.quietFor) { sample, _ in
            sample == 1 ? 0 : 1
        }
        #expect(done.samples == 7)
        #expect(done.at == .milliseconds(7200))
    }

    @Test("A wedged runner fails at the wall-clock limit and says how far it got")
    func theWallLimit() async {
        let message = await timeoutMessage {
            _ = try await quiet(step: .milliseconds(20), movingSamples: .max, wallLimit: .milliseconds(150)) { sample, _ in Double(sample) }
        }
        let text = message ?? ""
        #expect(text.contains("ran out of time"), "\(text)")
        #expect(text.contains("8 samples in 0.2 s and the last 0 quiet"), "\(text)")
        #expect(text.contains("Box"), "\(text)")
    }

    @Test("A quiet layout that outlasts the wall limit is told apart from a moving one")
    func quietButOutOfTime() async {
        let message = await timeoutMessage {
            _ = try await quiet(step: .seconds(1), quietFor: .seconds(60), wallLimit: .seconds(30)) { _, _ in 0 }
        }
        let text = message ?? ""
        #expect(text.contains("ran out of time, 30 samples in 30.0 s and the last 30 quiet"), "\(text)")
        #expect(text.contains("last change: none"), "\(text)")
    }

    @Test("The message says when the number of elements changed")
    func countChange() {
        let text = HostedSettling.describe(from: box(0), to: box(0) + [Entry(label: "New", frame: "(1.0, 1.0, 1.0, 1.0)")])
        #expect(text == "2 -> 3 elements")
    }

    // MARK: wait

    /// Runs `until` on a fake clock that moves `step` per pause, with a condition that holds from check `holdsAt` (1-based).
    private func poll(polls: Int, step: Duration = .milliseconds(25), wallLimit: Duration = HostedSettling.wallLimit,
                      holdsAt: Int) async throws -> (checks: Int, at: Duration) {
        let clock = FakeClock()
        var checks = 0
        try await HostedSettling.until("the toast", polls: polls, wallLimit: wallLimit, now: { clock.now },
                                       condition: { checks += 1; return checks >= holdsAt }, pause: { clock.advance(step) })
        return (checks, clock.elapsed)
    }

    @Test("A condition that turns true on the fourth check returns")
    func waitReturns() async throws {
        let done = try await poll(polls: 10, holdsAt: 4)
        #expect(done.checks == 4)
        #expect(done.at == .milliseconds(75))
    }

    @Test("A condition that stays false fails after its polls and names what was waited for")
    func waitFails() async {
        var checks = 0
        let clock = FakeClock()
        let message = await timeoutMessage {
            try await HostedSettling.until("the keypad", polls: 5, now: { clock.now }, condition: { checks += 1; return false },
                                           pause: { clock.advance(.milliseconds(20)) })
        }
        #expect(message == "the keypad (5 polls in 0.1 s)", "\(message ?? "")")
        #expect(checks == 6, "the first check and one after each of the 5 pauses")
    }

    @Test("A slow runner gets its polls: they are not counted in wall-clock time")
    func waitCountsPolls() async throws {
        // 4 polls are 100 ms of a quiet runner. Here each pause takes 1 s, and the fifth check still gets its chance.
        let done = try await poll(polls: 4, step: .seconds(1), holdsAt: 5)
        #expect(done.checks == 5)
        #expect(done.at == .seconds(4))
    }

    @Test("A wait that outlasts the wall limit fails there, however many polls it has left")
    func waitWallLimit() async {
        var checks = 0
        let clock = FakeClock()
        let message = await timeoutMessage {
            try await HostedSettling.until("the sheet", polls: .max, wallLimit: .milliseconds(150), now: { clock.now },
                                           condition: { checks += 1; return false }, pause: { clock.advance(.milliseconds(20)) })
        }
        #expect(message == "the sheet (8 polls in 0.2 s)", "\(message ?? "")")
    }
}
