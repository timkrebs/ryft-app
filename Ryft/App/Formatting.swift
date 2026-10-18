// Shared formatting: API day strings and the display strings every screen uses.
// Anything nil renders as the placeholder "–".
import Foundation

/// `YYYY-MM-DD` day strings in the device's current time zone.
enum DayFormat {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// Start of the given day (local), or nil for malformed input.
    static func date(from day: String) -> Date? {
        formatter.date(from: day)
    }

    /// `count` consecutive day strings ending with (and including) `end`, oldest first.
    static func days(endingAt end: Date, count: Int, calendar: Calendar = .current) -> [String] {
        (0..<max(0, count)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end).map(string(from:))
        }
    }

    static func shift(_ date: Date, days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}

enum Fmt {
    static let placeholder = "–"

    /// 468 → "7h 48m", 10 → "10m", nil → "–".
    static func duration(minutes: Int?) -> String {
        guard let minutes else { return placeholder }
        let m = abs(minutes)
        let sign = minutes < 0 ? "−" : ""
        if m < 60 { return "\(sign)\(m)m" }
        return "\(sign)\(m / 60)h \(String(format: "%02d", m % 60))m"
    }

    static func duration(seconds: TimeInterval) -> String {
        duration(minutes: Int((seconds / 60).rounded()))
    }

    /// Strain: one decimal ("12.4").
    static func strain(_ v: Double?) -> String {
        guard let v else { return placeholder }
        return v.formatted(.number.precision(.fractionLength(1)))
    }

    static func percent(_ v: Int?) -> String {
        guard let v else { return placeholder }
        return "\(v)%"
    }

    static func percent(_ v: Double?) -> String {
        percent(v.map { Int($0.rounded()) })
    }

    static func integer(_ v: Double?) -> String {
        guard let v else { return placeholder }
        return v.formatted(.number.precision(.fractionLength(0)))
    }

    static func decimal(_ v: Double?, digits: Int = 1) -> String {
        guard let v else { return placeholder }
        return v.formatted(.number.precision(.fractionLength(digits)))
    }

    static func time(_ d: Date?) -> String {
        guard let d else { return placeholder }
        return d.formatted(date: .omitted, time: .shortened)
    }

    static func distance(meters: Double?) -> String {
        guard let meters, meters > 0 else { return placeholder }
        let m = Measurement(value: meters, unit: UnitLength.meters)
        return m.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    static func kcal(_ v: Double?) -> String {
        guard let v else { return placeholder }
        return "\(Int(v.rounded())) kcal"
    }

    /// "Fri, 17 Oct"-style day title; "Today" / "Yesterday" where it applies.
    static func dayTitle(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

extension Int {
    var asHoursMinutes: String { Fmt.duration(minutes: self) }
}
