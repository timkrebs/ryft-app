import Foundation
import Testing
@testable import Ryft

/// "Looks like a session you already logged" (design §6): same local day, `|I ∩ E| / max(|I|, |E|) ≥ 0.7`.
@Suite("Import duplicates")
struct DuplicateDetectorTests {
    private static func ids(_ range: Range<Int>) -> Set<UUID> { Set(range.map(ImportBuildFixture.id)) }
    private static let berlin = ImportBuildFixture.berlin
    /// 2026-03-10T17:00Z: 18:00 in Berlin.
    private static let evening = Date(timeIntervalSince1970: 1_773_162_000)

    private static func candidate(_ exercises: Set<UUID>, day: String = "2026-03-10") -> DuplicateDetector.Candidate {
        DuplicateDetector.Candidate(id: ImportBuildFixture.id(1_000), day: day, exerciseIDs: exercises)
    }

    private static func logged(_ exercises: Set<UUID>, at date: Date = evening, id: Int = 2_000) -> LoggedSession {
        LoggedSession(id: ImportBuildFixture.id(id), startedAt: date, exerciseIDs: exercises)
    }

    private static func isFlagged(_ candidate: DuplicateDetector.Candidate, _ logged: [LoggedSession]) -> Bool {
        DuplicateDetector.duplicates(of: [candidate], against: logged, zone: berlin)[candidate.id] != nil
    }

    /// 70 of 100 exercises in common is a duplicate; 69 isn't.
    @Test func theBoundaryIsSeventyPercent() {
        let mine = Self.ids(0..<100)
        #expect(Self.isFlagged(Self.candidate(mine), [Self.logged(Self.ids(30..<130))]))
        #expect(!Self.isFlagged(Self.candidate(mine), [Self.logged(Self.ids(31..<131))]))
        #expect(DuplicateDetector.overlap(Self.ids(0..<10), Self.ids(3..<13)) == 0.7)
        #expect(Self.isFlagged(Self.candidate(Self.ids(0..<10)), [Self.logged(Self.ids(3..<13))]))
        #expect(!Self.isFlagged(Self.candidate(Self.ids(0..<10)), [Self.logged(Self.ids(4..<14))]))
    }

    /// The larger side is the denominator: three exercises logged in RYFT can't hide a ten-exercise import, nor the
    /// other way round.
    @Test func theLargerSessionDecides() {
        #expect(DuplicateDetector.overlap(Self.ids(0..<3), Self.ids(0..<10)) == 0.3)
        #expect(!Self.isFlagged(Self.candidate(Self.ids(0..<10)), [Self.logged(Self.ids(0..<3))]))
        #expect(!Self.isFlagged(Self.candidate(Self.ids(0..<3)), [Self.logged(Self.ids(0..<10))]))
        #expect(Self.isFlagged(Self.candidate(Self.ids(0..<7)), [Self.logged(Self.ids(0..<10))]))
    }

    @Test func onlyTheSameLocalDay() {
        let same = Self.ids(0..<5)
        #expect(!Self.isFlagged(Self.candidate(same, day: "2026-03-11"), [Self.logged(same)]))
        // 23:30 UTC on the 10th is 00:30 on the 11th in Berlin.
        let lateNight = Date(timeIntervalSince1970: 1_773_185_400)
        #expect(Self.isFlagged(Self.candidate(same, day: "2026-03-11"), [Self.logged(same, at: lateNight)]))
        #expect(!Self.isFlagged(Self.candidate(same, day: "2026-03-10"), [Self.logged(same, at: lateNight)]))
    }

    @Test func nothingEmptyIsEverADuplicate() {
        #expect(DuplicateDetector.overlap([], []) == 0)
        #expect(!Self.isFlagged(Self.candidate([]), [Self.logged([])]))
        #expect(!DuplicateDetector.isDuplicate(Self.ids(0..<1), []))
        #expect(DuplicateDetector.duplicates(of: [], against: [Self.logged(Self.ids(0..<3))], zone: Self.berlin).isEmpty)
    }

    /// Two logged sessions that day: the better overlap wins; on a tie, the earlier one.
    @Test func theBestMatchIsNamed() {
        let mine = Self.ids(0..<10)
        let close = Self.logged(Self.ids(1..<11), id: 2_001)          // 0.9
        let closer = Self.logged(Self.ids(0..<10), id: 2_002)         // 1.0
        let found = DuplicateDetector.duplicates(of: [Self.candidate(mine)], against: [close, closer], zone: Self.berlin)
        #expect(found[ImportBuildFixture.id(1_000)] == ImportBuildFixture.id(2_002))
        let earlier = Self.logged(mine, at: Self.evening.addingTimeInterval(-3_600), id: 2_003)
        let tie = DuplicateDetector.duplicates(of: [Self.candidate(mine)], against: [closer, earlier], zone: Self.berlin)
        #expect(tie[ImportBuildFixture.id(1_000)] == ImportBuildFixture.id(2_003))
    }
}
