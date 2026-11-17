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
}
