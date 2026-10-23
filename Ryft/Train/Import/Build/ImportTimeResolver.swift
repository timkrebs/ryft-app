import Foundation

/// Wall-clock times from a file (which has no zone) as instants in the zone the flow captured (design §3, time zone
/// and DST). Pure. A time that doesn't exist (the spring change) moves to the next valid time, minutes kept; one that
/// occurs twice (autumn) takes the first. Ids never use the resolved instant (ADR 0007).
struct ImportTimeResolver: Sendable {
    let zone: TimeZone
    private let calendar: Calendar

    init(zone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        self.zone = zone
        self.calendar = calendar
    }

    struct Resolution: Equatable, Sendable {
        let instant: Date
        /// `.nonexistentLocalTime` or `.repeatedLocalTime` when a clock change touched the time; nil otherwise.
        let note: ImportWarning.Kind?
    }

    /// Via `Calendar.nextDate` from local midnight, with the policies spelled out (not `date(from:)`'s defaults).
    func resolve(_ time: LocalDateTime) -> Resolution? {
        guard let midnight = startOfDay(time.date) else { return nil }
        let wanted = DateComponents(hour: time.hour, minute: time.minute, second: 0)
        let from = midnight.addingTimeInterval(-1)
        guard let first = calendar.nextDate(after: from, matching: wanted, matchingPolicy: .nextTimePreservingSmallerComponents,
                                            repeatedTimePolicy: .first, direction: .forward) else { return nil }
        let found = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: first)
        let sameDay = found.year == time.date.year && found.month == time.date.month && found.day == time.date.day
        if !sameDay || found.hour != time.hour || found.minute != time.minute {
            return Resolution(instant: first, note: .nonexistentLocalTime)
        }
        if let last = calendar.nextDate(after: from, matching: wanted, matchingPolicy: .nextTimePreservingSmallerComponents,
                                        repeatedTimePolicy: .last, direction: .forward), last != first {
            return Resolution(instant: first, note: .repeatedLocalTime)
        }
        return Resolution(instant: first, note: nil)
    }

    /// The first instant of a local day (midnight, or later where midnight itself doesn't exist).
    func startOfDay(_ date: LocalDate) -> Date? {
        guard let noon = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12)) else {
            return nil
        }
        return calendar.startOfDay(for: noon)
    }
}
