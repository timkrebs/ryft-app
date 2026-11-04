import Foundation
import Testing
@testable import Ryft

/// U2: a refused item's words come from the platform's `code`, and Details carry the request ID and the message.
struct ImportRejectionTextTests {
    private func item(code: String?, reason: String? = nil, requestID: String? = nil, blocked: Bool = false) -> ImportItemSummary {
        ImportItemSummary(id: UUID(), kind: .session, title: "Upper", date: nil, reason: reason, requestID: requestID,
                          blocked: blocked, code: code)
    }

    @Test func codesMap() {
        #expect(ImportRejectionCode("invalid") == .invalid)
        #expect(ImportRejectionCode("unknown_exercise") == .unknownExercise)
        #expect(ImportRejectionCode("unknown_plan_reference") == .unknownPlanReference)
        #expect(ImportRejectionCode("id_taken") == .idTaken)
        #expect(ImportRejectionCode("newer_on_server") == .newerOnServer)
        #expect(ImportRejectionCode("something_new") == .unknown)
        #expect(ImportRejectionCode(nil) == .unknown)
    }

    @Test func eachCodeHasItsOwnReasonAndNeverTheServersWords() {
        let codes: [String?] = ["invalid", "unknown_exercise", "unknown_plan_reference", "id_taken", "newer_on_server", "x", nil]
        let reasons = codes.map { ImportRejectionText.reason(item(code: $0, reason: "SERVER WORDS")) }
        #expect(reasons.allSatisfy { !$0.contains("SERVER WORDS") })
        #expect(reasons[5] == reasons[6])
        #expect(Set(reasons).count == 6)
    }

    @Test func newerOnServerReadsAsLeftAsIs() {
        #expect(ImportRejectionText.reason(item(code: "newer_on_server")) == ImportRejectionText.leftAsIs)
    }

    @Test func blockedKeepsItsOwnReason() {
        let blocked = item(code: nil, blocked: true)
        #expect(ImportRejectionText.reason(blocked) != ImportRejectionText.reason(item(code: nil)))
        // A blocked item has no answer of its own: no message in Details.
        #expect(ImportRejectionText.details(item(code: nil, reason: "x", blocked: true)) == nil)
    }

    @Test func detailsHoldRequestIDCodeAndMessage() throws {
        let details = try #require(ImportRejectionText.details(item(code: "invalid", reason: "reps out of range", requestID: " 01JB7Z ")))
        #expect(details.contains("01JB7Z") && details.contains("invalid") && details.contains("reps out of range"))
        #expect(details.split(separator: "\n").count == 3)
        #expect(ImportRejectionText.details(item(code: nil)) == nil)
    }

    @Test func longMessageIsCut() throws {
        let long = String(repeating: "a", count: 500)
        let details = try #require(ImportRejectionText.details(item(code: nil, reason: long)))
        #expect(details.count < 300)
        #expect(details.hasSuffix("…"))
    }

    @Test func leftAsIsIsNotCountedAsImported() {
        let status = MockTrainImport.leftAsIsDone
        #expect(status.leftAsIs == 3 && status.sessionsImported == 9 && status.plansImported == 1)
        #expect(!status.hasRejected)
        #expect(ImportResultText.sentence(status).contains("9"))
        #expect(!ImportResultText.sentence(status).contains("12"))
    }

    @Test func onlyLeftAsIsIsNothingNew() {
        var status = MockTrainImport.leftAsIsDone
        status.sessions = ImportItemCounts(total: 3, done: 3)
        status.plans = ImportItemCounts()
        status.leftAsIs = 3
        status.leftAsIsSessions = 3
        #expect(ImportResultText.sentence(status).hasPrefix("Nothing new"))
    }
}
