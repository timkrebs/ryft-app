import Foundation
import Testing
@testable import Ryft

/// The rule behind `HostedWindow.settle` and `wait`: quiet is a run of equal samples, a stalled runner is not a moving
/// layout, and a layout that never rests fails naming what moved. A scripted sampler stands in for the window, so none of
/// this needs the accessibility tree or the clock to cooperate.
@MainActor
@Suite("Hosted settling")
struct HostedSettlingTests {
    private typealias Entry = HostedSettling.Entry

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

    @Test("A quiet layout returns after the first sample and five equal ones")
    func quietReturns() async throws {
        var samples = 0
        try await HostedSettling.untilQuiet(movingSamples: 5, quietFor: .zero, sample: { samples += 1; return box(0) },
                                            pause: { await Task.yield() })
        #expect(samples == 6)
    }

    @Test("Quiet takes time as well as samples: 200 ms with nothing moving")
    func quietTakesTime() async throws {
        var samples = 0
        let start = ContinuousClock.now
        try await HostedSettling.untilQuiet(movingSamples: 5, quietFor: .milliseconds(200), sample: { samples += 1; return box(0) },
                                            pause: { try await Task.sleep(for: .milliseconds(20)) })
        #expect(ContinuousClock.now - start >= .milliseconds(200))
        #expect(samples >= 6)
    }

    @Test("A change starts the count of equal samples again")
    func aChangeResetsTheRun() async throws {
        var samples = 0
        try await HostedSettling.untilQuiet(movingSamples: 5, quietFor: .zero, sample: {
            samples += 1
            return box(samples <= 4 ? Double(samples) : 4)
        }, pause: { await Task.yield() })
        // Sample 1 is the start, 2 to 4 each differ from the one before, 5 to 9 equal sample 4.
        #expect(samples == 9)
    }

    @Test("A frame that keeps changing times out and the message names it")
    func movingForeverFails() async {
        var x = 0.0
        let message = await timeoutMessage {
            try await HostedSettling.untilQuiet(movingSamples: 8, quietFor: .zero, sample: { x += 1; return box(x) }, pause: { await Task.yield() })
        }
        let text = message ?? ""
        #expect(text.contains("the layout to settle"), "\(text)")
        #expect(text.contains("still moving, 9 changing samples"), "\(text)")
        #expect(text.contains("Box (") && text.contains("->"), "the box that moved, from and to: \(text)")
        #expect(!text.contains("Title"), "the title stood still: \(text)")
    }

    @Test("A runner that is slow, not a layout that moves, does not fail the wait")
    func aSlowRunnerStillSettles() async throws {
        // Every sample holds the main actor for 30 ms, as a render test does on CI. The budget for a layout that moves is
        // one sample (50 ms of a quiet runner), and seven samples take over 200 ms: a wall-clock deadline of that size fails.
        var samples = 0
        let start = ContinuousClock.now
        try await HostedSettling.untilQuiet(movingSamples: 1, quietFor: .zero, sample: {
            samples += 1
            let until = ContinuousClock.now + .milliseconds(30)
            while ContinuousClock.now < until {}
            return box(samples == 1 ? 0 : 1)
        }, pause: { await Task.yield() })
        #expect(ContinuousClock.now - start > .milliseconds(180))
        #expect(samples == 7)
    }

    @Test("A wedged runner fails at the wall-clock limit and says how far it got")
    func theWallLimit() async {
        var x = 0.0
        let message = await timeoutMessage {
            try await HostedSettling.untilQuiet(movingSamples: .max, quietFor: .zero, wallLimit: .milliseconds(150), sample: { x += 1; return box(x) },
                                                pause: { try await Task.sleep(for: .milliseconds(20)) })
        }
        let text = message ?? ""
        #expect(text.contains("ran out of time"), "\(text)")
        #expect(text.contains("the last 0 quiet"), "\(text)")
        #expect(text.contains("Box"), "\(text)")
    }

    @Test("The message says when the number of elements changed")
    func countChange() {
        let text = HostedSettling.describe(from: box(0), to: box(0) + [Entry(label: "New", frame: "(1.0, 1.0, 1.0, 1.0)")])
        #expect(text == "2 -> 3 elements")
    }

    // MARK: wait

    @Test("A condition that turns true on the third poll returns")
    func waitReturns() async throws {
        var polls = 0
        try await HostedSettling.until("the toast", polls: 10, condition: { polls += 1; return polls > 3 }, pause: { await Task.yield() })
        #expect(polls == 4)
    }

    @Test("A condition that stays false fails after its polls and names what was waited for")
    func waitFails() async {
        var polls = 0
        let message = await timeoutMessage {
            try await HostedSettling.until("the keypad", polls: 5, condition: { polls += 1; return false }, pause: { await Task.yield() })
        }
        #expect(message?.hasPrefix("the keypad (5 polls") == true, "\(message ?? "")")
        #expect(polls == 6)
    }

    @Test("A slow runner gets its polls: they are not counted in wall-clock time")
    func waitCountsPolls() async throws {
        var polls = 0
        let start = ContinuousClock.now
        try await HostedSettling.until("the sheet", polls: 4, condition: {
            polls += 1
            let until = ContinuousClock.now + .milliseconds(40)
            while ContinuousClock.now < until {}
            return polls > 4
        }, pause: { await Task.yield() })
        #expect(ContinuousClock.now - start > .milliseconds(160))
    }
}
