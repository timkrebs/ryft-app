import Foundation

enum SleepDialMath {
    static let dayMinutes = 24 * 60
    static let step = 5
    static let defaultBed = 23 * 60
    static let defaultWake = 7 * 60

    enum Validation: Error, Equatable {
        case tooShort, tooLong, futureWake

        var message: String {
            switch self {
            case .tooShort:
                return String(localized: "Bedtime and wake time need to be at least 1 hour apart.",
                              comment: "Morning check-in validation for a short sleep interval.")
            case .tooLong:
                return String(localized: "That's more than 16 hours.", comment: "Morning check-in validation for a long sleep interval.")
            case .futureWake:
                return String(localized: "Wake time can't be in the future.", comment: "Morning check-in validation for a future wake time.")
            }
        }
    }

    /// Degrees clockwise from midnight at the top.
    static func angle(for minutes: Int) -> Double {
        Double(wrapped(minutes)) * 360 / Double(dayMinutes)
    }

    static func minutes(for angle: Double) -> Int {
        let turn = angle.truncatingRemainder(dividingBy: 360)
        return wrapped(Int((turn * Double(dayMinutes) / 360).rounded()))
    }

    static func snap(_ minutes: Int) -> Int {
        wrapped(Int((Double(wrapped(minutes)) / Double(step)).rounded()) * step)
    }

    static func duration(bed: Int, wake: Int) -> Int {
        wake > bed ? wake - bed : dayMinutes - bed + wake
    }

    /// Takes a YYYY-MM-DD wake day. The sleep spans calendar days in the supplied time zone.
    /// A spring-forward gap resolves to the next valid local time. In a repeated hour,
    /// use the earlier occurrence for each endpoint.
    static func compose(wakeDay: String, bed: Int, wake: Int, timeZone: TimeZone) -> (bedtime: Date, wakeTime: Date)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = wakeDay.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              pathDate(day, tzOffsetSec: tzOffset(for: day, timeZone: timeZone)) == wakeDay,
              let bedDay = calendar.date(byAdding: .day, value: bed < wake ? 0 : -1, to: day),
              let bedtime = time(bed, on: bedDay, calendar: calendar),
              let wakeTime = time(wake, on: day, calendar: calendar) else { return nil }
        return (bedtime, wakeTime)
    }

    private static func time(_ minutes: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }

    static func tzOffset(for wakeTime: Date, timeZone: TimeZone) -> Int {
        timeZone.secondsFromGMT(for: wakeTime)
    }

    static func pathDate(_ wakeTime: Date, tzOffsetSec: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: wakeTime.addingTimeInterval(Double(tzOffsetSec)))
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func validate(bedtime: Date, wakeTime: Date, now: Date) -> Validation? {
        let elapsed = wakeTime.timeIntervalSince(bedtime)
        if elapsed < 60 * 60 { return .tooShort }
        if elapsed > 960 * 60 { return .tooLong }
        if wakeTime.timeIntervalSince(now) > 5 * 60 { return .futureWake }
        return nil
    }

    static func parse(_ time: String) -> Int? {
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ $0.utf8.count == 2 && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    static func minutes(of date: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// The clock a stored check-in is shown and edited on: this iPhone's zone when it had the check-in's offset at the wake
    /// time (so a DST night shows its bedtime on its own side of the change), else the check-in's fixed offset (another
    /// time zone since: the times stay where they were, never moved to this zone's clock).
    static func clock(ofCheckinOffset offset: Int, wakeTime: Date, current: TimeZone) -> TimeZone {
        if current.secondsFromGMT(for: wakeTime) == offset { return current }
        return TimeZone(secondsFromGMT: offset) ?? current
    }

    static func wrapped(_ minutes: Int) -> Int {
        (minutes % dayMinutes + dayMinutes) % dayMinutes
    }
}
