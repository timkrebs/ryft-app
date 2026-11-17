import Foundation
import SwiftUI
import Testing
@testable import Ryft

// VN1 and CR8: Sleep → Day when a night couldn't load and nothing is cached. It said the system's error text
// ("The operation couldn't be completed. (NSURLErrorDomain error -1009.)") under an "Asleep" caption and an unlit 0:00.
// Now it says the app's calm sentences (Today's refresh issue, `RefreshIssue.Reason.message`; "No connection" offline),
// with the status and request ID behind Details, and the caption is empty.

private let unexpected = RefreshIssue.Reason.unexpected.message
private let noConnection = "No connection. Check your internet and try again."

@MainActor
struct SleepLoadFailureTests {
    private let at = Date(timeIntervalSince1970: 1_794_906_000)

    @Test func theSentencesAreTheAppsNeverTheSystems() {
        let offline = APIError.transport(URLError(.notConnectedToInternet))
        let cases: [(Error, Bool, String, String?)] = [
            (offline, true, noConnection, nil),
            (APIError.transport(URLError(.timedOut)), false, noConnection, nil),
            (APIError.transport(URLError(.timedOut)), true, RefreshIssue.Reason.unreachable.message, nil),
            (APIError.http(503, "", requestID: "r-503"), true, RefreshIssue.Reason.busy.message, "HTTP 503 · Request ID r-503"),
            (APIError.http(404, "not found", requestID: "r-404"), true, unexpected, "HTTP 404 · Request ID r-404"),
            (APIError.signedOut, true, RefreshIssue.Reason.signedOut.message, nil),
        ]
        for (error, online, message, details) in cases {
            let failure = SleepLoadFailure(error, isOnline: online, at: at)
            #expect(failure.message == message, "\(error)")
            #expect(failure.details == details, "\(error)")
            #expect(failure.message != error.localizedDescription)
        }
    }

    /// As on Today's card: Sign in when signed out, no button for an outdated app; trying again fixes neither.
    @Test func theButtonIsTodays() {
        #expect(RefreshIssue.Reason.signedOut.action == .signIn && RefreshIssue.Reason.appTooOld.action == .noButton)
        for reason in [RefreshIssue.Reason.busy, .unreachable, .unexpected] { #expect(reason.action == .retry, "\(reason)") }
        #expect(SleepLoadFailure(APIError.signedOut, isOnline: true, at: at).action == .signIn)
        #expect(SleepLoadFailure(APIError.http(401, "", requestID: "r-401"), isOnline: true, at: at).action == .signIn)
        #expect(SleepLoadFailure(reason: .appTooOld).action == .noButton)
        #expect(SleepLoadFailure(APIError.http(503, ""), isOnline: true, at: at).action == .retry)
        #expect(SleepLoadFailure(APIError.signedOut, isOnline: false, at: at).action == .retry, "offline: No connection, Try again")
    }

    /// N3: one wiring for Today's card and Sleep's failed night: the title and the action come from the reason's action.
    @Test func theButtonsWiringIsOne() async {
        typealias Action = RefreshIssue.Reason.Action
        #expect(Action.signIn.title == LocalizedStringKey("Sign in"))
        #expect(Action.retry.title == LocalizedStringKey("Try again"))
        final class Taps { var log: [String] = [] }
        let taps = Taps()
        let retry: () async -> Void = { taps.log.append("retry") }
        let signIn: () async -> Void = { taps.log.append("signIn") }
        await Action.retry.button(retry: retry, signIn: signIn)?()
        await Action.signIn.button(retry: retry, signIn: signIn)?()
        #expect(Action.noButton.button(retry: retry, signIn: signIn) == nil)
        #expect(taps.log == ["retry", "signIn"])
        #expect(Action.signIn.button(retry: retry, signIn: nil) == nil, "no sign-in action: no button")
    }

    /// With demo data on, a 401 (only fault injection makes one there) offers no Sign in, on Today's card and Sleep's
    /// failed night alike (`RefreshIssue.Reason.action(isDemo:)`): Sign in signs out, which demo data doesn't need.
    @Test func withDemoDataNeitherScreenSignsIn() {
        typealias Reason = RefreshIssue.Reason
        #expect(Reason.signedOut.action(isDemo: true) == .noButton)
        for reason in [Reason.busy, .unreachable, .unexpected, .signedOut, .appTooOld] {
            #expect(reason.action(isDemo: false) == reason.action, "\(reason): signed in, as before")
            if reason != .signedOut { #expect(reason.action(isDemo: true) == reason.action, "\(reason): only Sign in goes") }
        }
        let fault = APIError.http(401, "injected fault", requestID: "fault-day")
        #expect(SleepLoadFailure(fault, isOnline: true, isDemo: true, at: at).action == .noButton)
        #expect(SleepLoadFailure(fault, isOnline: true, isDemo: false, at: at).action == .signIn)
        #expect(SleepLoadFailure(reason: .signedOut, isDemo: true).action == .noButton)
    }

    /// The model passes demo mode on: a demo 401 leaves Sleep's failed night without Sign in, its Details kept.
    @Test func aDemo401LeavesSleepWithoutSignIn() async throws {
        let clock = TestClock(now: at)
        let api = MockPlatformAPI()
        api.now = { clock.now() }
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let env = AppEnvironment(
            settings: Settings(defaults: defaults), health: MockHealthStore(), liveAPI: MockPlatformAPI(), demoAPI: api,
            auth: .preview(), persistence: TrainStore(inMemory: true), clock: clock, notifier: MockNotifier(),
            flags: StaticFlags(), connectivity: .preview(online: true), defaults: defaults, demoOverride: true)
        env.reads.random = { $0.lowerBound }
        env.reads.budget = RequestBudget(clock: clock, maxStarts: .max)
        let state = AppState(env: env)
        try #require(state.isDemo && state.hasDataSource)
        api.failure = APIError.http(401, "injected fault", requestID: "fault-day")
        let vm = SleepViewModel(state: state)
        vm.mode = .day
        await vm.load()
        #expect(vm.error == RefreshIssue.Reason.signedOut.message)
        #expect(vm.failure?.action == .noButton && vm.failure?.details == "HTTP 401 · Request ID fault-day")
    }

    @Test func aFailedBoardHasAnEmptyCaption() {
        let board = SleepBoard(sleep: nil, score: nil, error: noConnection)
        #expect(board.look == .failed(noConnection) && board.caption.isEmpty && board.numeralLabel == nil)
        #expect(board.spokenCaption == nil, "the message in the hypnogram's place says it")
    }

    @Test func theModelKeepsTheSentenceAndTheDetails() async throws {
        let api = MockPlatformAPI()
        let state = AppState(env: .test(api: api, clock: TestClock(now: at)))
        try #require(state.hasDataSource, "the test environment is signed in and configured")
        api.failure = APIError.http(404, "not found", requestID: "r-404")
        let vm = SleepViewModel(state: state)
        vm.mode = .day
        await vm.load()
        #expect(vm.error == unexpected)
        #expect(vm.failure?.details == "HTTP 404 · Request ID r-404")
        #expect(vm.board.look == .failed(unexpected) && vm.board.caption.isEmpty)
        #expect(vm.stepAnnouncement == "\(vm.header.spokenValue). \(unexpected)", "\(vm.stepAnnouncement)")
    }
}

/// What a tap on the failed night's button did.
@MainActor
final class SleepFailureTaps {
    var names: [String] = []
}

/// The same in a window: the failed previews (`SleepPreviewScene.Night.failed`, `.failedBusy`).
@MainActor
@Suite(.serialized) struct SleepLoadFailureHostedTests {
    @Test func thePageSaysTheSentenceAndHidesTheDetails() async throws {
        for (night, message) in [(SleepPreviewScene.Night.failed, noConnection), (.failedBusy, RefreshIssue.Reason.busy.message)] {
            try await HostedWindow.run(width: 390, height: 1400, bottomInset: 0, SleepPreviewPage(night)) { w in
                try await w.wait("the message") { w.node(message, exactly: true) != nil }
                try await w.settle()
                let nodes = w.nodes()
                #expect(!nodes.contains { $0.label.contains("NSURLErrorDomain") || $0.label.contains("-1009") }, "\(night)")
                #expect(!nodes.contains { $0.label == "Asleep" }, "no caption under the unlit numeral")
                #expect(nodes.contains { $0.identifier == "sleep.failure.retry" }, "Try again")
                if night == .failedBusy {
                    // The inline toggle (`InlineMessage(details:)`) has no identifier of its own: its label.
                    let details = try #require(nodes.first { $0.label == "Details" && $0.traits.contains(.button) }, "Details")
                    details.activate()
                    try await w.wait("the details") { w.node("HTTP 503 · Request ID 01JD8K2V9Q7M3X", exactly: true) != nil }
                } else {
                    #expect(!nodes.contains { $0.label == "Details" }, "no Details without a response")
                }
            }
        }
    }

    /// Signed out: "Sign in", which signs in (Today's action), never a retry. An outdated app: no button.
    @Test func signedOutSignsInAndAnOutdatedAppHasNoButton() async throws {
        for (failure, title) in [(SleepLoadFailure(APIError.signedOut, isOnline: true, at: .now), "Sign in"),
                                 (SleepLoadFailure(reason: .appTooOld), nil)] {
            let taps = SleepFailureTaps()
            let board = SleepBoard(sleep: nil, score: nil, error: failure.message)
            let page = ScrollView {
                SleepDay(board: board, sleep: nil, score: nil, night: .now, failure: failure,
                         retry: { taps.names.append("retry") }, signIn: { taps.names.append("signIn") })
            }
            try await HostedWindow.run(width: 390, height: 1200, bottomInset: 0, page) { w in
                try await w.wait("the message") { w.node(failure.message, exactly: true) != nil }
                try await w.settle()
                let nodes = w.nodes()
                #expect(!nodes.contains { $0.label == "Try again" }, "\(failure.message)")
                guard let title else {
                    #expect(!nodes.contains { $0.identifier == "sleep.failure.retry" }, "no button for an outdated app")
                    return
                }
                let button = try #require(nodes.first { $0.identifier == "sleep.failure.retry" })
                #expect(button.label == title)
                _ = button.activate()
                try await w.wait("the tap") { !taps.names.isEmpty }
                #expect(taps.names == ["signIn"])
            }
        }
    }

    /// Demo data on, signed out (a 401 from fault injection): neither Today's card nor Sleep's failed night has Sign
    /// in, both keep Details; signed in, both have it.
    @Test(arguments: [true, false])
    func bothScreensDecideSignInAlike(isDemo: Bool) async throws {
        let failure = SleepLoadFailure(APIError.http(401, "", requestID: "fault-day"), isOnline: true, isDemo: isDemo,
                                       at: .now)
        let error = ResourceError(kind: .signedOut, status: 401, code: nil, requestID: "fault-day", transport: nil,
                                  attempts: 1, at: .now)
        let issue = RefreshIssue(reason: .signedOut, resource: .today, dataFrom: nil, failures: 1, error: error)
        let page = ScrollView {
            VStack(spacing: 24) {
                RefreshIssueCard(issue: issue, isDemo: isDemo)
                SleepDay(board: SleepBoard(sleep: nil, score: nil, error: failure.message), sleep: nil, score: nil,
                         night: .now, failure: failure, retry: {}, signIn: {})
            }
        }
        try await HostedWindow.run(width: 390, height: 1400, bottomInset: 0, page) { w in
            try await w.wait("both messages") { w.nodes().filter { $0.label == failure.message }.count == 2 }
            try await w.settle()
            let nodes = w.nodes()
            for prefix in ["refreshIssue", "sleep.failure"] {
                let button = nodes.first { $0.identifier == "\(prefix).retry" }
                #expect((button != nil) == !isDemo, "\(prefix), demo \(isDemo): \(button?.label ?? "no button")")
                if let button { #expect(button.label == "Sign in") }
            }
            #expect(nodes.contains { $0.identifier == "refreshIssue.details" }, "Today's Details")
            #expect(nodes.contains { $0.label == "Details" && $0.identifier != "refreshIssue.details" }, "Sleep's Details")
        }
    }
}
