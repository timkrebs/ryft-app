import Foundation

/// RFC 3339 timestamps: the platform's (Go, up to nanoseconds) and the read-model cache's
/// (`APIClient.jsonEncoder`, `.iso8601`: whole seconds, `Z`).
enum DateParsing {
    /// RFC3339 with or without fractional seconds (Go emits nanoseconds).
    static func rfc3339(_ s: String) -> Date? {
        canonical(s) ?? formatters(s)
    }

    /// The source of truth: what `rfc3339` returned before the fast path, and still returns for anything
    /// `canonical` doesn't take.
    static func formatters(_ s: String) -> Date? {
        fractional.date(from: s) ?? plain.date(from: s)
    }

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Fast path

extension DateParsing {
    /// A fast path in front of the formatters for the one shape nearly every date has:
    /// `YYYY-MM-DDTHH:MM:SS[.fraction](Z|±HH:MM)`, as Go and `APIClient.jsonEncoder` write it.
    ///
    /// It exists because the cache stores dates without fractions, so each cached date first failed the
    /// fractional formatter and then parsed with the plain one (about 95 µs), and cached reads decode on the
    /// main actor inside view bodies (2 to 6 ms for a `DayDetail`).
    ///
    /// The formatters remain the source of truth. This returns `nil` for anything it doesn't fully validate
    /// (another separator, lowercase `t` or `z`, `+HHMM`, more than 9 fraction digits, a field out of range, a
    /// year before 1583, trailing bytes), and `rfc3339` then asks them, so odd input behaves as before. For what
    /// it takes it returns their exact value: the fraction truncated to milliseconds, converted as
    /// `Double(ms) / 1000 - 978_307_200` like `CFDateFormatter`. `DateParsingTests` hold the two equal.
    static func canonical(_ s: String) -> Date? {
        var utf8 = s
        return utf8.withUTF8(RFC3339Bytes.parse)
    }
}

/// The byte-level parser behind `DateParsing.canonical`.
private enum RFC3339Bytes {
    /// ICU's calendar is Julian before 1582-10-15 (the formatters read `1582-10-10` as `1582-10-20`):
    /// earlier years go to them.
    static let firstGregorianYear = 1583
    /// RFC 3339 allows any number of digits; past 9 the formatters' reading overflows (12 come out wrong).
    static let maxFractionDigits = 9
    static let maxOffsetSeconds = 18 * 3600

    static func parse(_ b: UnsafeBufferPointer<UInt8>) -> Date? {
        // 19 bytes of date and time, an optional fraction, then `Z` or `±HH:MM`.
        let n = b.count
        guard n >= 20, n <= 19 + 1 + maxFractionDigits + 6 else { return nil }
        guard b[4] == UInt8(ascii: "-"), b[7] == UInt8(ascii: "-"), b[10] == UInt8(ascii: "T"),
              b[13] == UInt8(ascii: ":"), b[16] == UInt8(ascii: ":"),
              let year = number(b, at: 0, digits: 4), let month = number(b, at: 5, digits: 2),
              let day = number(b, at: 8, digits: 2), let hour = number(b, at: 11, digits: 2),
              let minute = number(b, at: 14, digits: 2), let second = number(b, at: 17, digits: 2)
        else { return nil }
        guard year >= firstGregorianYear, (1...12).contains(month), day >= 1, day <= days(inMonth: month, of: year),
              hour < 24, minute < 60, second < 60 // 60 (a leap second): the formatters return nil
        else { return nil }

        var i = 19
        var millis = 0
        if b[i] == UInt8(ascii: ".") {
            i += 1
            var digits = 0
            while i < n, let d = digit(b[i]) {
                if digits < 3 { millis = millis * 10 + d } // truncated to milliseconds, like the formatters
                digits += 1
                i += 1
            }
            guard digits >= 1, digits <= maxFractionDigits else { return nil }
            while digits < 3 {
                millis *= 10
                digits += 1
            }
        }

        guard i < n else { return nil }
        let offset: Int
        switch b[i] {
        case UInt8(ascii: "Z"):
            guard i + 1 == n else { return nil }
            offset = 0
        case UInt8(ascii: "+"), UInt8(ascii: "-"):
            guard i + 6 == n, b[i + 3] == UInt8(ascii: ":"),
                  let hours = number(b, at: i + 1, digits: 2), let minutes = number(b, at: i + 4, digits: 2),
                  minutes < 60, hours * 3600 + minutes * 60 <= maxOffsetSeconds
            else { return nil }
            offset = (hours * 3600 + minutes * 60) * (b[i] == UInt8(ascii: "+") ? 1 : -1)
        default:
            return nil
        }

        let seconds = daysSince1970(year: year, month: month, day: day) * 86400
            + hour * 3600 + minute * 60 + second - offset
        let ms = seconds * 1000 + millis
        return Date(timeIntervalSinceReferenceDate: Double(ms) / 1000 - Date.timeIntervalBetween1970AndReferenceDate)
    }

    private static func digit(_ byte: UInt8) -> Int? {
        let d = byte &- UInt8(ascii: "0")
        return d < 10 ? Int(d) : nil
    }

    private static func number(_ b: UnsafeBufferPointer<UInt8>, at start: Int, digits: Int) -> Int? {
        var value = 0
        for i in start..<(start + digits) {
            guard let d = digit(b[i]) else { return nil }
            value = value * 10 + d
        }
        return value
    }

    private static func days(inMonth month: Int, of year: Int) -> Int {
        switch month {
        case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days from 1970-01-01 in the proleptic Gregorian calendar (H. Hinnant's `days_from_civil`; years ≥ 1583).
    private static func daysSince1970(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = y / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
