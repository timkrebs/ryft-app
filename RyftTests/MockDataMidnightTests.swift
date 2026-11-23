import Foundation
import Testing
@testable import Ryft

// The demo's today is the day its nights were built for, whatever the wall clock says. (CI, 2026-11-23 00:00:15:
// `MockData.todayDetail.workouts[0]` trapped with "Index out of range": the nights were built before midnight, and
// `todayDetail` read `.now`, a day they didn't have.) The window here is built at an instant far from any real date, so
// a read at `.now` can't find its day, on whatever date CI runs.

@Suite("Demo data across midnight")
struct MockDataMidnightTests {
    private static func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour,
                                                                 minute: minute, second: second)))
    }

    @Test("A window built at 23:59:50 on 2020-02-29 has its last day as today, with a workout and a night, whatever `.now` is")
    func todayIsTheWindowsLastDay() throws {
        let built = try Self.local(2020, 2, 29, 23, 59, 50)
        let window = MockData.Window(endingOn: built)
        let today = window.today

        #expect(today.score.day == "2020-02-29")
        let first = try #require(today.workouts.first, "workouts[0] must exist")
        #expect(first.start >= Calendar.current.startOfDay(for: built))
        #expect(today.sleep != nil)
        // The moment after midnight is another day: the window has no night for it, as the process would find at `.now`.
        let after = try Self.local(2020, 3, 1, 0, 0, 10)
        #expect(window.detail(for: after).workouts.isEmpty, "the next day isn't in the window; today never reads it")
    }

    @Test("The process's own today is its history's last day, and its workouts index")
    func theFrozenTodayIsTheHistorysLast() throws {
        let last = try #require(MockData.history.last)
        #expect(MockData.todayDetail.score.day == last.day)
        #expect(MockData.todayScore.day == last.day)
        #expect(!MockData.todayDetail.workouts.isEmpty)
        #expect(MockData.sleepRange(.week).to == last.day)
        #expect(MockData.trend(.readiness, range: .week).points.last?.day == last.day)
    }
}
