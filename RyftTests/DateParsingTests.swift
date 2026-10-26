import Foundation
import Testing
@testable import Ryft

/// `DateParsing.rfc3339`: the fast path (`canonical`) and the formatters behind it, which stay the source of truth.
/// Equality here is `Date ==`, so the fast path's values are bit for bit the formatters'.
@Suite("RFC 3339 parsing")
struct DateParsingTests {
    /// An input the fast path takes, and its instant in whole milliseconds since 1970 (worked out independently).
    struct Taken: CustomTestStringConvertible, Sendable {
        let input: String
        let millis: Int64

        init(_ input: String, _ millis: Int64) {
            self.input = input
            self.millis = millis
        }

        var testDescription: String { input }
    }

    static let taken: [Taken] = [
        // The cache's shape (`.iso8601`) and the shortest input.
        Taken("2026-10-18T07:22:41Z", 1_792_308_161_000),
        // Fractions: 1 to 9 digits, truncated to milliseconds like the formatters (never rounded up).
        Taken("2026-10-18T07:22:41.1Z", 1_792_308_161_100),
        Taken("2026-10-18T07:22:41.12Z", 1_792_308_161_120),
        Taken("2026-10-18T07:22:41.123Z", 1_792_308_161_123),
        Taken("2026-10-18T07:22:41.9999Z", 1_792_308_161_999),
        Taken("2026-10-18T07:22:41.000000001Z", 1_792_308_161_000),
        Taken("2026-10-18T07:22:41.999999999Z", 1_792_308_161_999),
        // The longest input: 9 digits and an offset.
        Taken("2026-10-18T07:22:41.123456789+02:00", 1_792_300_961_123),
        // Offsets, both signs, quarter and half hours, the ±18:00 bounds, and -00:00 (UTC, as the formatters read it).
        Taken("2026-10-18T07:22:41+02:00", 1_792_300_961_000),
        Taken("2026-10-18T07:22:41+05:45", 1_792_287_461_000),
        Taken("2026-10-18T07:22:41-03:30", 1_792_320_761_000),
        Taken("2026-10-18T07:22:41+18:00", 1_792_243_361_000),
        Taken("2026-10-18T07:22:41-18:00", 1_792_372_961_000),
        Taken("2026-10-18T07:22:41-00:00", 1_792_308_161_000),
        // Leap days (every 4th year, and 2000 by the 400-year rule).
        Taken("2024-02-29T12:00:00Z", 1_709_208_000_000),
        Taken("2000-02-29T00:00:00Z", 951_782_400_000),
        // Year boundaries, also crossed by the offset alone.
        Taken("2026-12-31T23:59:59Z", 1_798_761_599_000),
        Taken("2027-01-01T00:00:00Z", 1_798_761_600_000),
        Taken("2026-12-31T23:30:00-01:00", 1_798_763_400_000),
        Taken("2027-01-01T00:15:00+01:00", 1_798_758_900_000),
        // The epoch, just before it (a negative instant with a fraction), and the range's ends.
        Taken("1970-01-01T00:00:00Z", 0),
        Taken("1969-12-31T23:59:59.999Z", -1),
        Taken("1583-01-01T00:00:00Z", -12_212_553_600_000),
        Taken("9999-12-31T23:59:59.999Z", 253_402_300_799_999),
    ]

    @Test(arguments: taken)
    func theFastPathTakesTheCanonicalShape(_ c: Taken) throws {
        let fast = try #require(DateParsing.canonical(c.input))
        #expect(fast == DateParsing.formatters(c.input))
        #expect(DateParsing.rfc3339(c.input) == fast)
        #expect(Int64((fast.timeIntervalSince1970 * 1000).rounded()) == c.millis)
    }

    /// Declined by the fast path, so the formatters decide exactly as before. The comments say what they answer
    /// (iOS 27 simulator): they are lenient in places, which is why the fast path doesn't guess.
    static let declined: [String] = [
        "", // nil
        "2026-10-18T07:22:41", // no zone: nil
        "2026-10-18T07:22:41.Z", // no fraction digits: nil
        "2026-10-18T07:22:41,5Z", // comma: nil
        "2026-10-18t07:22:41Z", // lowercase t: nil
        "2026-10-18T07:22:41z", // lowercase z: 07:22:41Z
        "2026-10-18 07:22:41Z", // space for T: nil
        "2026-10-18T07:22:41+0200", // no colon: 05:22:41Z
        "2026-10-18T07:22:41+02", // hours only: 05:22:41Z
        "2026-10-18T07:22:41.1234567891Z", // 10 digits: .123
        "2026-10-18T07:22:41.123456789123Z", // 12 digits: 07:22:40.999 (their fraction overflows)
        "2026-10-18T07:22:41.123+02:00junk", // trailing bytes: 05:22:41.123Z
        "2026-10-18T07:22:41Zjunk", // trailing bytes: 07:22:41Z
        "2026-10-18T07:22:41+02:00Z", // trailing Z: 05:22:41Z
        "2026-10-18T07:22:41Z ", // trailing space: 07:22:41Z
        " 2026-10-18T07:22:41Z", // leading space: 07:22:41Z
        "2026-00-18T07:22:41Z", // month 0: nil
        "2026-13-18T07:22:41Z", // month 13: nil
        "2026-10-00T07:22:41Z", // day 0: nil
        "2026-10-32T07:22:41Z", // day 32: nil
        "2026-02-29T07:22:41Z", // not a leap year: 2026-03-01
        "2026-02-30T07:22:41Z", // Feb 30: 2026-03-02
        "2026-04-31T07:22:41Z", // April 31: 2026-05-01
        "1900-02-29T00:00:00Z", // a century, not a leap year: 1900-03-01
        "2100-02-29T00:00:00Z", // the same: 2100-03-01
        "2026-10-18T24:00:00Z", // hour 24: the next midnight
        "2026-10-18T23:60:00Z", // minute 60: nil
        "2016-12-31T23:59:60Z", // a real leap second: nil
        "2026-10-18T07:22:41+18:01", // past ±18:00: read as an offset
        "2026-10-18T07:22:41+24:00", // the same as +02:00
        "2026-10-18T07:22:41+00:60", // offset minute 60: as Z
        "1582-10-14T00:00:00Z", // Julian before 1582-10-15: 1582-10-24
        "0000-01-01T00:00:00Z", // year 0: Julian
        "10000-01-01T00:00:00Z", // five-digit year: read
        "-2026-10-18T07:22:41Z", // negative year: read
        "2026/10-18T07:22:41Z", // one separator off at a time: 07:22:41Z
        "2026-10/18T07:22:41Z", // 07:22:41Z
        "2026-10-18T07.22:41Z", // 07:22:41Z
        "2026-10-18T07:22.41Z", // 07:22:41Z
        "2026-10-18T07:22:41+02.00", // 05:22:41Z
        "2026-1-18T07:22:41Z", // one-digit month: 2026-01-18
        "2026-10-18T07:22:41.-5Z", // a signed fraction: 07:22:40.5
        "２026-10-18T07:22:41Z", // a fullwidth digit: 07:22:41Z
        "18.10.2026", // nil
    ]

    @Test(arguments: declined)
    func everythingElseGoesToTheFormatters(_ input: String) {
        #expect(DateParsing.canonical(input) == nil)
        #expect(DateParsing.rfc3339(input) == DateParsing.formatters(input))
    }

    /// 10 000 seeded strings, half canonical and half one edit away: the fast path takes every canonical one,
    /// and on all of them `rfc3339` equals the formatters, both `nil` included.
    @Test func agreesWithTheFormattersOnASeededSweep() {
        var strings = RFC3339Strings(seed: 0x5EED_3339)
        var mismatches: [String] = []
        var declinedCanonical: [String] = []
        for _ in 0..<5000 {
            let s = strings.canonical()
            let fast = DateParsing.canonical(s)
            if fast == nil { declinedCanonical.append(s) }
            if fast != DateParsing.formatters(s) || DateParsing.rfc3339(s) != fast { mismatches.append(s) }
        }
        var readByTheFormattersOnly = 0
        var nearMissesTaken = 0
        for _ in 0..<5000 {
            let s = strings.nearMiss()
            let fast = DateParsing.canonical(s)
            let truth = DateParsing.formatters(s)
            if let fast {
                nearMissesTaken += 1
                if fast != truth { mismatches.append(s) }
            } else if truth != nil {
                readByTheFormattersOnly += 1
            }
            if DateParsing.rfc3339(s) != truth { mismatches.append(s) }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(10))")
        #expect(declinedCanonical.isEmpty, "\(declinedCanonical.prefix(10))")
        // Both paths are exercised: near misses only the formatters read (their leniency), and edits that left the
        // string canonical (a digit for a digit).
        #expect(readByTheFormattersOnly > 1000)
        #expect(nearMissesTaken > 50)
    }
}

/// Canonical RFC 3339 strings and near misses (one field out of range, or one character replaced, removed, inserted
/// or appended), from a seed so a failure names a string that reproduces.
private struct RFC3339Strings {
    private var rng: SeededGenerator

    init(seed: UInt64) {
        rng = SeededGenerator(seed: seed)
    }

    private struct Fields {
        var year = 2026
        var month = 10
        var day = 18
        var hour = 7
        var minute = 22
        var second = 41
        var fraction = ""
        var zone = "Z"

        var text: String {
            let date = "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
            let time = "\(pad(hour, 2)):\(pad(minute, 2)):\(pad(second, 2))"
            return date + "T" + time + (fraction.isEmpty ? "" : "." + fraction) + zone
        }
    }

    private static let alphabet = Array("0123456789-:T.tZz +,/x٣")

    mutating func canonical() -> String {
        fields().text
    }

    mutating func nearMiss() -> String {
        var f = fields()
        switch int(0...9) {
        case 0: f.month = [0, 13, 19, 99][int(0...3)]
        case 1: f.day = [0, days(inMonth: f.month, of: f.year) + 1, 32, 99][int(0...3)]
        case 2: f.hour = int(24...29)
        case 3: f.minute = int(60...69)
        case 4: f.second = int(60...69)
        case 5: f.fraction = digits(int(10...12))
        case 6: f.year = int(0...1582)
        case 7:
            let hours = int(18...24)
            f.zone = sign() + pad(hours, 2) + ":" + pad(int(hours == 18 ? 1...99 : 0...99), 2)
        default:
            var chars = Array(f.text)
            let at = int(0...(chars.count - 1))
            let c = Self.alphabet[int(0...(Self.alphabet.count - 1))]
            switch int(0...3) {
            case 0: chars[at] = c
            case 1: chars.remove(at: at)
            case 2: chars.insert(c, at: at)
            default: chars.append(c)
            }
            return String(chars)
        }
        return f.text
    }

    private mutating func fields() -> Fields {
        var f = Fields()
        f.year = int(0...1) == 0 ? int(1970...2100) : int(1583...9999)
        f.month = int(1...12)
        f.day = int(1...days(inMonth: f.month, of: f.year))
        f.hour = int(0...23)
        f.minute = int(0...59)
        f.second = int(0...59)
        let fractionDigits = int(-3...9)
        f.fraction = fractionDigits > 0 ? digits(fractionDigits) : ""
        if int(0...3) > 0 {
            let hours = int(0...18)
            f.zone = sign() + pad(hours, 2) + ":" + pad(hours == 18 ? 0 : int(0...59), 2)
        }
        return f
    }

    private mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &rng)
    }

    private mutating func sign() -> String {
        int(0...1) == 0 ? "+" : "-"
    }

    private mutating func digits(_ count: Int) -> String {
        (0..<count).map { _ in String(int(0...9)) }.joined()
    }
}

private func pad(_ value: Int, _ width: Int) -> String {
    let digits = String(value)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
}

private func days(inMonth month: Int, of year: Int) -> Int {
    switch month {
    case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
}
