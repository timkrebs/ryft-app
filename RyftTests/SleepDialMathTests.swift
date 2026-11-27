import Foundation
import Testing
@testable import Ryft

@Suite("Sleep dial math")
struct SleepDialMathTests {
    @Test func clockAnglesAndRoundTrips() {
        #expect(SleepDialMath.angle(for: 0) == 0)
        #expect(SleepDialMath.angle(for: 360) == 90)
        #expect(SleepDialMath.angle(for: 720) == 180)
        #expect(SleepDialMath.angle(for: 1080) == 270)
        #expect(SleepDialMath.minutes(for: -90) == 1080)
        #expect(SleepDialMath.minutes(for: 360) == 0)
        for minutes in 0..<1440 {
            #expect(SleepDialMath.minutes(for: SleepDialMath.angle(for: minutes)) == minutes)
        }
    }

    @Test func fiveMinuteDetentsWrap() {
        #expect(SleepDialMath.snap(2) == 0)
        #expect(SleepDialMath.snap(3) == 5)
        #expect(SleepDialMath.snap(1438) == 0)
        #expect(SleepDialMath.snap(-5) == 1435)
    }

    @Test func clockDurations() {
        #expect(SleepDialMath.duration(bed: 22 * 60 + 10, wake: 5 * 60 + 40) == 450)
        #expect(SleepDialMath.duration(bed: 120, wake: 180) == 60)
        #expect(SleepDialMath.duration(bed: 420, wake: 420) == 1440)
    }

    @Test func compositionUsesTheWakeDay() throws {
        let day = "2026-11-26"
        let times = try #require(SleepDialMath.compose(wakeDay: day, bed: 23 * 60, wake: 7 * 60, timeZone: .gmt))
        #expect(times.wakeTime.timeIntervalSince(times.bedtime) == 8 * 3600)
        #expect(SleepDialMath.pathDate(times.bedtime, tzOffsetSec: 0) == "2026-11-25")
        #expect(SleepDialMath.pathDate(times.wakeTime, tzOffsetSec: 0) == day)
        let sameDay = try #require(SleepDialMath.compose(wakeDay: day, bed: 60, wake: 420, timeZone: .gmt))
        #expect(SleepDialMath.pathDate(sameDay.bedtime, tzOffsetSec: 0) == day)
        #expect(SleepDialMath.compose(wakeDay: "2026-02-30", bed: 1380, wake: 420, timeZone: .gmt) == nil)
    }

    @Test(arguments: ["2026-03-29", "2026-10-25"])
    func berlinDaylightSaving(_ day: String) throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let times = try #require(SleepDialMath.compose(wakeDay: day, bed: 1380, wake: 420, timeZone: zone))
        let spring = day == "2026-03-29"
        #expect(times.wakeTime.timeIntervalSince(times.bedtime) == Double(spring ? 7 : 9) * 3600)
        #expect(SleepDialMath.tzOffset(for: times.wakeTime, timeZone: zone) == (spring ? 7200 : 3600))
        #expect(SleepDialMath.validate(bedtime: times.bedtime, wakeTime: times.wakeTime, now: times.wakeTime) == nil)
    }

    @Test func nonexistentWallTimeAdvancesToTheNextValidTime() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let times = try #require(SleepDialMath.compose(wakeDay: "2026-03-29", bed: 1380, wake: 150, timeZone: zone))
        #expect(SleepDialMath.minutes(of: times.wakeTime, timeZone: zone) == 180)
    }

    @Test(arguments: ["America/Los_Angeles", "Asia/Kolkata"])
    func pathDateUsesOffsetInsteadOfTheUTCDate(_ identifier: String) throws {
        let zone = try #require(TimeZone(identifier: identifier))
        let day = "2026-11-26"
        // Put the instant on the other side of midnight in UTC in both cases.
        let isKolkata = identifier == "Asia/Kolkata"
        let times = try #require(SleepDialMath.compose(wakeDay: day, bed: isKolkata ? 1380 : 1020,
                                                       wake: isKolkata ? 60 : 1380, timeZone: zone))
        let offset = SleepDialMath.tzOffset(for: times.wakeTime, timeZone: zone)
        #expect(offset == (isKolkata ? 19_800 : -28_800))
        #expect(SleepDialMath.pathDate(times.wakeTime, tzOffsetSec: offset) == day)
        #expect(SleepDialMath.pathDate(times.wakeTime, tzOffsetSec: 0) != day)
    }

    @Test func validationUsesElapsedTimeAndIncludesBothLimits() {
        let now = Date(timeIntervalSince1970: 200_000)
        func validate(minutes: Int, minutesInFuture: Int = 0) -> SleepDialMath.Validation? {
            let wake = now.addingTimeInterval(Double(minutesInFuture * 60))
            return SleepDialMath.validate(bedtime: wake.addingTimeInterval(Double(-minutes * 60)), wakeTime: wake, now: now)
        }
        #expect(validate(minutes: 59) == .tooShort)
        #expect(validate(minutes: 60) == nil)
        #expect(validate(minutes: 960) == nil)
        #expect(validate(minutes: 961) == .tooLong)
        #expect(validate(minutes: 450, minutesInFuture: 5) == nil)
        #expect(validate(minutes: 450, minutesInFuture: 6) == .futureWake)
    }

    @Test func parsesOnlyLocalHHMM() {
        #expect(SleepDialMath.parse("00:00") == 0)
        #expect(SleepDialMath.parse("06:45") == 405)
        #expect(SleepDialMath.parse("23:59") == 1439)
        for invalid in ["", "7:00", "07:0", "07::00", "24:00", "23:60", "07:00Z", " 07:00", "٠٧:٠٠"] {
            #expect(SleepDialMath.parse(invalid) == nil)
        }
    }

    /// A suggested wake time still ahead of the clock starts at now (rounded down to 5 min), so the sheet doesn't open
    /// refused; one already past, or a wake day that isn't today on this clock, stays as suggested.
    @MainActor @Test func prefilledWakeNeverStartsInTheFuture() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let day = "2026-11-26"
        // 06:22 in Berlin (UTC+1).
        let early = try #require(ISO8601DateFormatter().date(from: "2026-11-26T05:22:00Z"))
        #expect(CheckinSheetModel.prefilledWake(7 * 60, wakeDay: day, now: early, timeZone: berlin) == 6 * 60 + 20)
        #expect(CheckinSheetModel.prefilledWake(6 * 60 + 25, wakeDay: day, now: early, timeZone: berlin) == 6 * 60 + 25)
        #expect(CheckinSheetModel.prefilledWake(6 * 60, wakeDay: day, now: early, timeZone: berlin) == 6 * 60)
        // 08:00: the suggestion is in the past.
        let late = try #require(ISO8601DateFormatter().date(from: "2026-11-26T07:00:00Z"))
        #expect(CheckinSheetModel.prefilledWake(7 * 60, wakeDay: day, now: late, timeZone: berlin) == 7 * 60)
        // The wake day is tomorrow on this clock (another time zone than the account's): left alone.
        #expect(CheckinSheetModel.prefilledWake(7 * 60, wakeDay: "2026-11-27", now: early, timeZone: berlin) == 7 * 60)
    }
}
