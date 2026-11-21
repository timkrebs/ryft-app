import Foundation
import SwiftUI
import Testing
@testable import Ryft

/// F2 part B: Train's three pages (History, the exercise page, the session detail) with a failed read and nothing cached say
/// "Try again when you're online" only when the iPhone is offline (nothing could be sent, or the connection was lost). Held
/// back online by a `Retry-After`, RYFT is busy; failed online (an error answer, no answer in time), the page's own "Try
/// again". Injected sources only (`SideTrainSource`), the test clock, the pipeline's own environment. Synthetic data only.
@MainActor
@Suite("F2: Train's failed reads say offline only when offline", .serialized)
struct TrainFailureWordsTests {
    enum Page: String, CaseIterable, Sendable { case history, exercise, session }

    /// Why the read failed, and how it got there.
    enum Condition: String, CaseIterable, Sendable {
        /// The pipeline says offline: nothing is sent.
        case offline
        /// No pipeline; the request failed for want of a connection.
        case lostConnection
        /// The pipeline holds automatic reads back, online (a 503's `Retry-After`).
        case heldBack
        /// No pipeline; the platform answered 500.
        case serverError
        /// No pipeline; no answer in time, online.
        case timedOut
        /// Through the pipeline, online; the platform answered 404 (not retried).
        case refusedThroughPipeline
    }

    private static func offlineText(_ page: Page) -> String {
        switch page {
        case .history: return TrainHistoryRows.offlineFailureText
        case .exercise: return ExerciseDetailPage.offlineFailureText
        case .session: return SessionDetailPage.offlineFailureText
        }
    }

    private static func onlineText(_ page: Page) -> String {
        switch page {
        case .history: return TrainHistoryRows.onlineFailureText
        case .exercise: return ExerciseDetailPage.onlineFailureText
        case .session: return SessionDetailPage.onlineFailureText
        }
    }

    private static func expected(_ page: Page, _ condition: Condition) -> String {
        switch condition {
        case .offline, .lostConnection: return offlineText(page)
        case .heldBack: return RefreshIssue.Reason.busy.message
        case .serverError, .timedOut, .refusedThroughPipeline: return onlineText(page)
        }
    }

    private static func call(_ page: Page) -> SideTrainSource.Call {
        switch page {
        case .history: return .sessions
        case .exercise: return .history
        case .session: return .session
        }
    }

    /// The environment whose pipeline the read goes through (nil: straight to the source), and what the source throws.
    private static func setUp(_ condition: Condition) -> (env: AppEnvironment, pipeline: Bool, error: Error?) {
        switch condition {
        case .offline:
            return (AppEnvironment.test(clock: TestClock(), online: false), true, nil)
        case .lostConnection:
            return (AppEnvironment.test(clock: TestClock()), false, APIError.transport(URLError(.notConnectedToInternet)))
        case .heldBack:
            let env = AppEnvironment.test(clock: TestClock())
            let failure = ResourceError(kind: .transient, status: 503, code: nil, requestID: "rid-f2-503", transport: nil,
                                        attempts: 3, at: env.clock.now())
            env.reads.seed([.train: ResourceState(lastError: failure, consecutiveFailures: 1,
                                                  retryNotBefore: env.clock.now().addingTimeInterval(300))])
            return (env, true, nil)
        case .serverError:
            return (AppEnvironment.test(clock: TestClock()), false, APIError.http(500, "", requestID: "rid-f2-500"))
        case .timedOut:
            return (AppEnvironment.test(clock: TestClock()), false, APIError.transport(URLError(.timedOut)))
        case .refusedThroughPipeline:
            return (AppEnvironment.test(clock: TestClock()), true, APIError.http(404, "", requestID: "rid-f2-404"))
        }
    }

    /// The page's model after one read that failed with nothing cached: whether it shows the failed state, its sentence
    /// and its offline flag.
    private static func read(_ page: Page, _ condition: Condition) async -> (failed: Bool, text: String, offline: Bool, sent: Int) {
        let (env, pipeline, error) = setUp(condition)
        defer { withExtendedLifetime(env) {} }
        let source = SideTrainSource(.demo)
        source.fail(call(page), with: error)
        let rig = TrainSides([SideSwitch.alex: source], reads: pipeline ? env.reads : nil)
        switch page {
        case .history:
            let vm = TrainHistoryViewModel(library: rig.library, clock: env.clock)
            await vm.load()
            return (vm.failed, vm.failureText, vm.offline, source.calls)
        case .exercise:
            let vm = ExerciseDetailViewModel(exerciseID: MockTrain.bench.id, library: rig.library, clock: env.clock)
            await vm.load()
            return (vm.failed, vm.failureText, vm.offline, source.calls)
        case .session:
            let vm = SessionDetailViewModel(sessionID: MockTrain.history[0].id, library: rig.library)
            await vm.load()
            return (vm.content().state == .failed, vm.failureText, vm.offline, source.calls)
        }
    }

    @Test("Each page's failed read with nothing cached: offline says go online, held back says busy, failed online says try again",
          arguments: Page.allCases, Condition.allCases)
    func theSentenceFollowsWhyItFailed(_ page: Page, _ condition: Condition) async {
        let result = await Self.read(page, condition)
        let which = "\(page) \(condition)"
        #expect(result.failed, "\(which): the failed state, not empty or loading")
        #expect(result.text == Self.expected(page, condition), "\(which): \(result.text)")
        let offline = condition == .offline || condition == .lostConnection
        #expect(result.offline == offline, "\(which): an online request that failed isn't offline")
        if !offline {
            #expect(!result.text.lowercased().contains("online"), "\(which): no \"when you're online\" while online: \(result.text)")
        }
        switch condition {
        case .offline, .heldBack: #expect(result.sent == 0, "\(which): nothing sent")
        default: #expect(result.sent == 1, "\(which): one request")
        }
    }

    @Test("The three online sentences: calm, no apology, each its page's own")
    func theOnlineSentences() {
        let texts = Page.allCases.map(Self.onlineText)
        #expect(texts == ["Your workouts couldn't be loaded. Try again.",
                          "This exercise's history couldn't be loaded. Try again.",
                          "This workout couldn't be loaded. Try again."])
        for (page, text) in zip(Page.allCases, texts) {
            #expect(text != Self.offlineText(page))
            #expect(!text.lowercased().contains("sorry") && !text.lowercased().contains("please"))
        }
    }

    /// Each page draws its model's sentence: online, the failure says try again, with Try again and Details under it.
    @Test("Hosted: each page draws the online failure's sentence", arguments: Page.allCases)
    func eachPageDrawsTheOnlineSentence(_ page: Page) async throws {
        let env = AppEnvironment.test(clock: TestClock())
        defer { withExtendedLifetime(env) {} }
        let source = SideTrainSource(.demo)
        source.fail(Self.call(page), with: APIError.http(500, "", requestID: "rid-f2-500"))
        let rig = TrainSides([SideSwitch.alex: source])
        let view: AnyView
        let prefix: String
        switch page {
        case .history:
            view = AnyView(NavigationStack { TrainHistoryView() })
            prefix = "history.failure"
        case .exercise:
            view = AnyView(NavigationStack { ExerciseDetailView(exerciseID: MockTrain.bench.id) })
            prefix = "exerciseDetail.failure"
        case .session:
            view = AnyView(NavigationStack { SessionDetailView(sessionID: MockTrain.history[0].id) })
            prefix = "sessionDetail.failure"
        }
        let text = Self.onlineText(page)
        try await HostedWindow.run(width: 390, height: 1_200, view.environment(rig.library).environment(\.appEnvironment, env)) { w in
            // Exactly: the online sentence is the start of the offline one.
            try await w.wait("\(page): the failure") { w.node(text, exactly: true) != nil }
            let ids = w.nodes().compactMap(\.identifier)
            #expect(ids.contains("\(prefix).retry"), "Try again: \(ids)")
            #expect(w.node(Self.offlineText(page), exactly: true) == nil)
        }
    }
}
