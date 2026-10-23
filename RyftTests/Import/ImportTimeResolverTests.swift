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
        // A day whose midnight didn't exist (DST began at 00:00).
        Case(zone: "America/Sao_Paulo", local: "2018-11-04 00:30", utc: "2018-11-04T03:30:00Z", note: .nonexistentLocalTime),
        Case(zone: "UTC", local: "2026-03-29 02:30", utc: "2026-03-29T02:30:00Z", note: nil),
    ]

    @Test(arguments: cases)
    func resolves(_ c: Case) throws {
        let zone = try #require(TimeZone(identifier: c.zone))
        let time = try Self.localTime(c.local)
        let expected = try #require(ISO8601DateFormatter().date(from: c.utc))
        let resolution = try #require(ImportTimeResolver(zone: zone).resolve(time))
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
        #expect(sessions.prefix(2).map { resolver.resolve($0.start)?.note } == [.nonexistentLocalTime, .repeatedLocalTime])
        #expect(sessions.dropFirst(2).map { resolver.resolve($0.start)?.note } == [nil, nil])
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
