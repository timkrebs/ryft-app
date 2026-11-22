import Foundation
import Testing
@testable import Ryft

// The demo's history is built around the day it is read, and read again on the next one: a process alive at midnight
// must still have a today. (CI, 2026-11-23 00:00:15: `MockData.todayDetail.workouts[0]` trapped with "Index out of range"
// because the nights were built once, at the first read before midnight, and the new day had none.)

@Suite("Demo data across midnight")
struct MockDataMidnightTests {
    private static func local(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour,
                                                                 minute: minute, second: second)))
    }

    @Test("Read at 23:59:50 and again 20 s later, each day has its own night with a workout to show")
    func theDayAfterHasItsOwnNight() throws {
        let before = try Self.local(22, 23, 59, 50)
        let after = before.addingTimeInterval(20)
        #expect(DayFormat.string(from: after) != DayFormat.string(from: before), "the second read is on the next day")

        let evening = MockData.todayDetail(asOf: before)
        #expect(evening.score.day == DayFormat.string(from: before))
        #expect(!evening.workouts.isEmpty)

        // What the preview and the tests index: the first workout of today.
        let morning = MockData.todayDetail(asOf: after)
        #expect(morning.score.day == DayFormat.string(from: after), "today moved on with the clock")
        let first = try #require(morning.workouts.first)
        #expect(first.start >= Calendar.current.startOfDay(for: after), "a workout of the new day")
        #expect(morning.sleep != nil)
    }

    @Test("Yesterday is still in the history after midnight")
    func theHistoryFollowsTheClock() throws {
        let before = try Self.local(22, 23, 59, 50)
        let after = before.addingTimeInterval(20)
        let first = MockData.detail(for: before, asOf: before)
        let second = MockData.detail(for: before, asOf: after)

        #expect(first.score.day == DayFormat.string(from: before))
        #expect(second.score.day == first.score.day, "yesterday is still there after midnight")
        #expect(second.sleep != nil)
    }
}
