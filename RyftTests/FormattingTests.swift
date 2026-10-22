import Foundation
import Testing
@testable import Ryft

@Suite("Date and day formatting")
struct FormattingTests {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func dayStringIsLocalYYYYMMDD() {
        #expect(DayFormat.string(from: date(2026, 1, 5)) == "2026-01-05")
        #expect(DayFormat.string(from: date(2026, 12, 31, 23, 59)) == "2026-12-31")
        #expect(APIClient.dayString(date(2026, 10, 18, 0, 1)) == "2026-10-18")
    }

    @Test func dayRoundTrip() throws {
        let d = try #require(DayFormat.date(from: "2026-03-29")) // DST change in Europe
        #expect(DayFormat.string(from: d) == "2026-03-29")
        #expect(DayFormat.date(from: "2026-13-40") == nil)
    }

    @Test func dayRanges() {
        let days = DayFormat.days(endingAt: date(2026, 3, 2), count: 3)
        #expect(days == ["2026-02-28", "2026-03-01", "2026-03-02"])
        #expect(DayFormat.days(endingAt: .now, count: 0).isEmpty)
    }

    @Test func rfc3339WithAndWithoutFractions() {
        #expect(DateParsing.rfc3339("2026-10-18T07:22:41.123456789+02:00") != nil)
        #expect(DateParsing.rfc3339("2026-10-18T07:22:41Z") != nil)
        #expect(DateParsing.rfc3339("18.10.2026") == nil)
    }

    @Test(arguments: [
        (468, "7h 48m"), (10, "10m"), (0, "0m"), (60, "1h 00m"), (605, "10h 05m"), (-25, "−25m"),
    ])
    func durations(minutes: Int, expected: String) {
        #expect(Fmt.duration(minutes: minutes) == expected)
    }

    @Test func placeholders() {
        #expect(Fmt.duration(minutes: nil) == "–")
        #expect(Fmt.percent(Int?.none) == "–")
        #expect(Fmt.time(nil) == "–")
        #expect(Fmt.distance(meters: 0) == "–")
        #expect(Fmt.percent(82) == "82%")
    }

    /// The raw night's "11:17 PM — 6:52 AM" under German (review T2): a time follows the locale it's given.
    @Test func timesFollowTheLocale() throws {
        let day = Date(timeIntervalSince1970: 1_792_600_000)
        let evening = try #require(Calendar.current.date(bySettingHour: 23, minute: 17, second: 0, of: day))
        let morning = try #require(Calendar.current.date(bySettingHour: 6, minute: 52, second: 0, of: day))
        #expect(Fmt.time(evening, locale: Locale(identifier: "de")) == "23:17")
        #expect(Fmt.time(evening, locale: Locale(identifier: "de_DE")) == "23:17")
        let early = Fmt.time(morning, locale: Locale(identifier: "de_DE"))
        #expect(early.hasSuffix("6:52") && !early.contains("AM"))
        let us = Fmt.time(evening, locale: Locale(identifier: "en_US"))
        #expect(us.hasPrefix("11:17") && us.hasSuffix("PM"))
        #expect(Fmt.time(evening, locale: Locale(identifier: "en_GB")) == "23:17")
    }
}
