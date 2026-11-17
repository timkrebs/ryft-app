import Foundation
import Testing
@testable import Ryft

/// Whether a launch plays the sequence (ADR 0017, launch-design.md §6.2 rows 1-6 and L9; plan.md L2, L9, L10, L12): the
/// ordered rules of `LaunchPolicy.decide`, one case per row, then the order itself (which row wins when two apply), L9's
/// boundary, and how `LaunchContext.current` reads what the app wrote. Pure values: nothing here touches the process.
///
/// The order, from the top: skip override, background launch, launch arguments (unless `play`), open workout, L9 recency
/// (unless `play`), reduced (Reduce Motion, VoiceOver, Low Power Mode), full.
@Suite("Launch: the play rules")
struct LaunchPolicyTests {
    private typealias C = LaunchContext

    private struct Row: CustomTestStringConvertible, Sendable {
        let name: String
        let context: LaunchContext
        let decision: LaunchDecision
        var testDescription: String { name }
        init(_ name: String, _ context: LaunchContext, _ decision: LaunchDecision) {
            self.name = name
            self.context = context
            self.decision = decision
        }
    }

    // MARK: every row, one case each

    private static let rows: [Row] = [
        Row("1 -RyftLaunchSequence skip", C(override: .skip), .skip(.harness)),
        Row("2 a background launch", C(launchedInBackground: true), .skip(.backgroundLaunch)),
        Row("3 any launch argument", C(hasLaunchArguments: true), .skip(.harness)),
        Row("3 play overrides the arguments", C(hasLaunchArguments: true, override: .play), .play(.full)),
        Row("4 a workout is open", C(workoutActive: true), .skip(.workoutActive)),
        Row("L9 back 60 s after the background", C(secondsSinceLastBackground: 60), .skip(.recentlyUsed)),
        Row("L9 never in the background", C(secondsSinceLastBackground: nil), .play(.full)),
        Row("5 Reduce Motion", C(reduceMotion: true), .play(.reduced)),
        Row("5 VoiceOver", C(voiceOver: true), .play(.reduced)),
        Row("5 Low Power Mode", C(lowPower: true), .play(.reduced)),
        Row("6 otherwise", C(), .play(.full)),
    ]

    @Test("Each row of the table", arguments: rows)
    private func eachRow(_ row: Row) {
        #expect(LaunchPolicy.decide(row.context) == row.decision)
    }

    /// Demo mode is not an input (L2: "Demo mode plays it, so the user can see it"): the policy has no such field, and
    /// a context read with demo mode on and every other input quiet is the full sequence.
    @MainActor
    @Test func demoModePlaysTheFullSequence() throws {
        let name = "LaunchPolicyTests.demo.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "demoMode")
        var context = LaunchContext.current(launchedInBackground: false, workoutActive: false, defaults: defaults)
        // What the host process reports (its arguments, its accessibility settings) isn't under test.
        context.hasLaunchArguments = false
        context.reduceMotion = false
        context.lowPower = false
        context.voiceOver = false
        #expect(LaunchPolicy.decide(context) == .play(.full))
        #expect(!Mirror(reflecting: context).children.contains { $0.label?.lowercased().contains("demo") == true },
                "demo mode must not become an input of the policy")
    }

    // MARK: the order: which row wins when two apply

    private static let order: [Row] = [
        Row("skip beats everything", C(launchedInBackground: true, hasLaunchArguments: true, override: .skip,
                                       reduceMotion: true, workoutActive: true, secondsSinceLastBackground: 5), .skip(.harness)),
        Row("background + play is still a skip", C(launchedInBackground: true, override: .play), .skip(.backgroundLaunch)),
        Row("background beats the arguments", C(launchedInBackground: true, hasLaunchArguments: true),
            .skip(.backgroundLaunch)),
        Row("background beats an open workout", C(launchedInBackground: true, workoutActive: true), .skip(.backgroundLaunch)),
        Row("arguments beat an open workout", C(hasLaunchArguments: true, workoutActive: true), .skip(.harness)),
        Row("arguments beat recency", C(hasLaunchArguments: true, secondsSinceLastBackground: 5), .skip(.harness)),
        Row("arguments beat the reduced variant", C(hasLaunchArguments: true, reduceMotion: true), .skip(.harness)),
        Row("workout + play is still a skip", C(override: .play, workoutActive: true), .skip(.workoutActive)),
        Row("workout beats recency", C(workoutActive: true, secondsSinceLastBackground: 5), .skip(.workoutActive)),
        Row("workout beats the reduced variant", C(voiceOver: true, workoutActive: true), .skip(.workoutActive)),
        Row("recency beats Reduce Motion", C(reduceMotion: true, secondsSinceLastBackground: 599), .skip(.recentlyUsed)),
        Row("recency beats VoiceOver", C(voiceOver: true, secondsSinceLastBackground: 599), .skip(.recentlyUsed)),
        Row("recency beats Low Power Mode", C(lowPower: true, secondsSinceLastBackground: 599), .skip(.recentlyUsed)),
        Row("play overrides recency", C(override: .play, secondsSinceLastBackground: 5), .play(.full)),
        Row("play overrides recency, then Reduce Motion applies", C(override: .play, reduceMotion: true,
                                                                   secondsSinceLastBackground: 5), .play(.reduced)),
        Row("play + arguments + recency still plays", C(hasLaunchArguments: true, override: .play,
                                                        secondsSinceLastBackground: 5), .play(.full)),
        Row("two reduced reasons are still reduced", C(reduceMotion: true, lowPower: true, voiceOver: true), .play(.reduced)),
    ]

    @Test("The order of the rules", arguments: order)
    private func theOrder(_ row: Row) {
        #expect(LaunchPolicy.decide(row.context) == row.decision)
    }

    // MARK: L9's boundary

    private struct Gap: CustomTestStringConvertible, Sendable {
        let seconds: TimeInterval?
        let decision: LaunchDecision
        var testDescription: String { seconds.map { "\($0) s" } ?? "never recorded" }
    }

    private static let gaps: [Gap] = [
        Gap(seconds: nil, decision: .play(.full)),
        Gap(seconds: 0, decision: .skip(.recentlyUsed)),
        Gap(seconds: 1, decision: .skip(.recentlyUsed)),
        Gap(seconds: 599, decision: .skip(.recentlyUsed)),
        Gap(seconds: 599.999, decision: .skip(.recentlyUsed)),
        Gap(seconds: 600, decision: .play(.full)),
        Gap(seconds: 601, decision: .play(.full)),
        Gap(seconds: 86_400, decision: .play(.full)),
        // A clock set back since the background write: not recent, whatever the size of the jump.
        Gap(seconds: -0.001, decision: .play(.full)),
        Gap(seconds: -5, decision: .play(.full)),
        Gap(seconds: -86_400, decision: .play(.full)),
    ]

    @Test("L9: under 10 minutes since the background skips, 10 minutes and more plays", arguments: gaps)
    private func theRecencyBoundary(_ gap: Gap) {
        #expect(LaunchPolicy.decide(C(secondsSinceLastBackground: gap.seconds)) == gap.decision)
    }

    @Test func theRecentWindowIsTenMinutes() {
        #expect(LaunchPolicy.recentWindow == 600)
    }

    @Test("play overrides recency at every gap", arguments: gaps)
    private func playOverridesTheRecencyAtEveryGap(_ gap: Gap) {
        #expect(LaunchPolicy.decide(C(override: .play, secondsSinceLastBackground: gap.seconds)) == .play(.full))
    }

    // MARK: the decision's names (the `launch-decision` signpost)

    @Test func theDecisionNamesTheSignpostCarries() {
        let names: [(LaunchDecision, String)] = [
            (.play(.full), "play-full"), (.play(.reduced), "play-reduced"),
            (.skip(.backgroundLaunch), "skip-backgroundLaunch"), (.skip(.harness), "skip-harness"),
            (.skip(.workoutActive), "skip-workoutActive"), (.skip(.recentlyUsed), "skip-recentlyUsed"),
            (.skip(.lateActivation), "skip-lateActivation"), (.skip(.backgrounded), "skip-backgrounded"),
            (.skip(.purposeLaunch), "skip-purposeLaunch"), (.skip(.presentation), "skip-presentation"),
        ]
        for (decision, name) in names { #expect(decision.signpostName == name) }
    }

    // MARK: what the app writes and `current` reads

    private static let day = Date(timeIntervalSince1970: 1_792_600_000)

    /// A fresh suite per call, so no test sees another's writes.
    @MainActor
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "LaunchPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @MainActor
    @Test func theKeysAreTheOnesTheDocsName() {
        #expect(LaunchContext.lastBackgroundKey == "launch.lastBackgroundAt")
        #expect(LaunchContext.overrideKey == "RyftLaunchSequence")
    }

    @MainActor
    @Test func nothingWrittenMeansNeverInTheBackgroundAndNoOverride() throws {
        try withDefaults { defaults in
            let context = LaunchContext.current(launchedInBackground: false, workoutActive: false, defaults: defaults)
            #expect(context.secondsSinceLastBackground == nil)
            #expect(context.override == nil)
            #expect(!context.launchedInBackground && !context.workoutActive)
        }
    }

    @MainActor
    @Test func theTwoStateArgumentsPassThrough() throws {
        try withDefaults { defaults in
            let context = LaunchContext.current(launchedInBackground: true, workoutActive: true, defaults: defaults)
            #expect(context.launchedInBackground && context.workoutActive)
        }
    }

    @MainActor
    @Test func aBackgroundWriteIsReadBackAsSecondsSince() throws {
        try withDefaults { defaults in
            LaunchContext.recordBackground(at: Self.day, in: defaults)
            #expect(defaults.object(forKey: LaunchContext.lastBackgroundKey) as? Date == Self.day)
            for seconds in [0.0, 90, 599, 600, 3_600] {
                let context = LaunchContext.current(launchedInBackground: false, workoutActive: false,
                                                    now: Self.day.addingTimeInterval(seconds), defaults: defaults)
                #expect(abs((context.secondsSinceLastBackground ?? .nan) - seconds) < 1e-3, "\(seconds) s")
            }
        }
    }

    @MainActor
    @Test func theLatestBackgroundWins() throws {
        try withDefaults { defaults in
            LaunchContext.recordBackground(at: Self.day, in: defaults)
            LaunchContext.recordBackground(at: Self.day.addingTimeInterval(1_000), in: defaults)
            let context = LaunchContext.current(launchedInBackground: false, workoutActive: false,
                                                now: Self.day.addingTimeInterval(1_060), defaults: defaults)
            #expect(abs((context.secondsSinceLastBackground ?? .nan) - 60) < 1e-3)
        }
    }

    /// A clock set back after the write gives a negative gap, which the policy reads as "not recent".
    @MainActor
    @Test func aClockSetBackReadsNegativeAndPlays() throws {
        try withDefaults { defaults in
            LaunchContext.recordBackground(at: Self.day, in: defaults)
            var context = LaunchContext.current(launchedInBackground: false, workoutActive: false,
                                                now: Self.day.addingTimeInterval(-30), defaults: defaults)
            #expect(abs((context.secondsSinceLastBackground ?? .nan) + 30) < 1e-3)
            quiet(&context)
            #expect(LaunchPolicy.decide(context) == .play(.full))
        }
    }

    /// The written date and the policy agree on the boundary end to end: what `RyftApp` writes at `.background` and
    /// reads in the next process's `init`.
    @MainActor
    @Test func theWrittenBackgroundDecidesAtTheBoundary() throws {
        try withDefaults { defaults in
            LaunchContext.recordBackground(at: Self.day, in: defaults)
            let expected: [(TimeInterval, LaunchDecision)] = [(599, .skip(.recentlyUsed)), (600, .play(.full)),
                                                              (601, .play(.full))]
            for (seconds, decision) in expected {
                var context = LaunchContext.current(launchedInBackground: false, workoutActive: false,
                                                    now: Self.day.addingTimeInterval(seconds), defaults: defaults)
                quiet(&context)
                #expect(LaunchPolicy.decide(context) == decision, "\(seconds) s")
            }
        }
    }

    private struct Argument: CustomTestStringConvertible, Sendable {
        let written: String?
        let override: LaunchContext.Override?
        var testDescription: String { written ?? "absent" }
    }

    @MainActor
    @Test("-RyftLaunchSequence is read from the defaults' argument domain", arguments: [
        Argument(written: "play", override: .play), Argument(written: "skip", override: .skip),
        Argument(written: "PLAY", override: nil), Argument(written: "maybe", override: nil),
        Argument(written: "", override: nil), Argument(written: nil, override: nil),
    ])
    private func theOverrideArgument(_ argument: Argument) throws {
        try withDefaults { defaults in
            if let written = argument.written { defaults.set(written, forKey: LaunchContext.overrideKey) }
            let context = LaunchContext.current(launchedInBackground: false, workoutActive: false, defaults: defaults)
            #expect(context.override == argument.override)
        }
    }

    /// The host process's own arguments and accessibility settings aren't under test: quiet them.
    private func quiet(_ context: inout LaunchContext) {
        context.hasLaunchArguments = false
        context.reduceMotion = false
        context.lowPower = false
        context.voiceOver = false
    }
}
