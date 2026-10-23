import Foundation
import Testing
@testable import Ryft

@Suite("Import time resolver")
struct ImportTimeResolverTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let zone: String
        let local: String // YYYY-MM-DD HH:mm, as written in a file
        let utc: String   // the instant, ISO 8601
        let note: ImportWarning.Kind?

        var testDescription: String { "\(zone) \(local)" }
    }

    static let cases: [Case] = [
        // Europe/Berlin, spring 2026-03-29 (02:00 → 03:00) and autumn 2026-10-25 (03:00 → 02:00).
        Case(zone: "Europe/Berlin", local: "2026-03-29 02:30", utc: "2026-03-29T01:30:00Z", note: .nonexistentLocalTime),
        Case(zone: "Europe/Berlin", local: "2026-03-29 02:00", utc: "2026-03-29T01:00:00Z", note: .nonexistentLocalTime),
        Case(zone: "Europe/Berlin", local: "2026-03-29 01:59", utc: "2026-03-29T00:59:00Z", note: nil),
        Case(zone: "Europe/Berlin", local: "2026-03-29 03:00", utc: "2026-03-29T01:00:00Z", note: nil),
        Case(zone: "Europe/Berlin", local: "2026-10-25 02:30", utc: "2026-10-25T00:30:00Z", note: .repeatedLocalTime),
        Case(zone: "Europe/Berlin", local: "2026-10-25 02:00", utc: "2026-10-25T00:00:00Z", note: .repeatedLocalTime),
        Case(zone: "Europe/Berlin", local: "2026-10-25 01:59", utc: "2026-10-24T23:59:00Z", note: nil),
        Case(zone: "Europe/Berlin", local: "2026-10-25 03:00", utc: "2026-10-25T02:00:00Z", note: nil),
        Case(zone: "Europe/Berlin", local: "2026-05-14 16:41", utc: "2026-05-14T14:41:00Z", note: nil),
        Case(zone: "Europe/Berlin", local: "2026-05-14 00:00", utc: "2026-05-13T22:00:00Z", note: nil),
        // America/New_York, spring 2026-03-08 (02:00 → 03:00) and autumn 2026-11-01 (02:00 → 01:00).
        Case(zone: "America/New_York", local: "2026-03-08 02:30", utc: "2026-03-08T07:30:00Z", note: .nonexistentLocalTime),
        Case(zone: "America/New_York", local: "2026-03-08 03:30", utc: "2026-03-08T07:30:00Z", note: nil),
        Case(zone: "America/New_York", local: "2026-11-01 01:30", utc: "2026-11-01T05:30:00Z", note: .repeatedLocalTime),
        Case(zone: "America/New_York", local: "2026-11-01 00:59", utc: "2026-11-01T04:59:00Z", note: nil),
        Case(zone: "America/New_York", local: "2026-11-01 02:00", utc: "2026-11-01T07:00:00Z", note: nil),
        // Australia/Lord_Howe changes by 30 minutes: spring 2026-10-04 (02:00 → 02:30), autumn 2026-04-05 (02:00 → 01:30).
        // A gap moves forward by its own length (here 30 minutes), never by a day.
        Case(zone: "Australia/Lord_Howe", local: "2026-10-04 02:15", utc: "2026-10-03T15:45:00Z", note: .nonexistentLocalTime),
        Case(zone: "Australia/Lord_Howe", local: "2026-10-04 02:30", utc: "2026-10-03T15:30:00Z", note: nil),
        Case(zone: "Australia/Lord_Howe", local: "2026-04-05 01:45", utc: "2026-04-04T14:45:00Z", note: .repeatedLocalTime),
        Case(zone: "Australia/Lord_Howe", local: "2026-04-05 01:29", utc: "2026-04-04T14:29:00Z", note: nil),
        Case(zone: "Australia/Lord_Howe", local: "2026-04-05 02:00", utc: "2026-04-04T15:30:00Z", note: nil),
        // A day whose midnight didn't exist (DST began at 00:00), and a fold across midnight (DST ended at 01:00).
        Case(zone: "America/Sao_Paulo", local: "2018-11-04 00:30", utc: "2018-11-04T03:30:00Z", note: .nonexistentLocalTime),
        Case(zone: "America/Havana", local: "2026-11-01 00:30", utc: "2026-11-01T04:30:00Z", note: .repeatedLocalTime),
        // A whole day skipped (Samoa crossed the date line): the time moves forward by the 24-hour gap.
        Case(zone: "Pacific/Apia", local: "2011-12-30 10:00", utc: "2011-12-30T20:00:00Z", note: .nonexistentLocalTime),
        Case(zone: "UTC", local: "2026-03-29 02:30", utc: "2026-03-29T02:30:00Z", note: nil),
    ]

    @Test(arguments: cases)
    func resolves(_ c: Case) throws {
        let zone = try #require(TimeZone(identifier: c.zone))
        let time = try Self.localTime(c.local)
        let expected = try #require(ISO8601DateFormatter().date(from: c.utc))
        let resolution = ImportTimeResolver(zone: zone).resolve(time)
        #expect(resolution.instant == expected)
        #expect(resolution.note == c.note)
    }

    @Test func startOfDay() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let saoPaulo = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let day = try #require(LocalDate(year: 2026, month: 3, day: 29))
        let skipped = try #require(LocalDate(year: 2018, month: 11, day: 4))
        let iso = ISO8601DateFormatter()
        #expect(ImportTimeResolver(zone: berlin).startOfDay(day) == iso.date(from: "2026-03-28T23:00:00Z"))
        #expect(ImportTimeResolver(zone: saoPaulo).startOfDay(skipped) == iso.date(from: "2018-11-04T03:00:00Z"))
    }

    @Test func theEdgeFixtureFallsOnBothBerlinClockChanges() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let resolver = ImportTimeResolver(zone: berlin)
        let sessions = try ImportFixture.parse("ap-workouts-edge").sessions
        #expect(sessions.prefix(2).map { resolver.resolve($0.start).note } == [.nonexistentLocalTime, .repeatedLocalTime])
        #expect(sessions.dropFirst(2).map { resolver.resolve($0.start).note } == [nil, nil])
    }

    @Test func daysFromTheCivilDate() {
        #expect(ImportTimeResolver.daysFromCivil(year: 1970, month: 1, day: 1) == 0)
        #expect(ImportTimeResolver.daysFromCivil(year: 2000, month: 3, day: 1) == 11_017)
        #expect(ImportTimeResolver.daysFromCivil(year: 1900, month: 1, day: 1) == -25_567)
        #expect(ImportTimeResolver.daysFromCivil(year: 2024, month: 2, day: 29) == 19_782)
    }

    @Test func keysStayWallClock() throws {
        // Ids use the wall-clock key, never the instant (ADR 0007): the same file in two zones keeps its keys.
        let time = try Self.localTime("2026-10-25 02:30")
        #expect(time.key == "2026-10-25T02:30")
        #expect(time.date.key == "2026-10-25")
        let padded = try Self.localTime("2026-01-05 07:05")
        #expect(padded.key == "2026-01-05T07:05")
        #expect(LocalDate(year: 1899, month: 12, day: 31) == nil)
        #expect(LocalDateTime(date: padded.date, hour: 24, minute: 0) == nil)
    }

    private static func localTime(_ text: String) throws -> LocalDateTime {
        let parts = text.split(separator: " ")
        let day = try #require(parts.first)
        let clock = try #require(parts.last?.split(separator: ":"))
        let dayParts = day.split(separator: "-").compactMap { Int($0) }
        let year = try #require(dayParts.first)
        let month = try #require(dayParts.dropFirst().first)
        let dayOfMonth = try #require(dayParts.last)
        let date = try #require(LocalDate(year: year, month: month, day: dayOfMonth))
        let hour = try #require(clock.first.flatMap { Int($0) })
        let minute = try #require(clock.last.flatMap { Int($0) })
        return try #require(LocalDateTime(date: date, hour: hour, minute: minute))
    }
}
