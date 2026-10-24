import Foundation

/// Wall-clock times from a file (which has no zone) as instants in the zone the flow captured (design §3, time zone
/// and DST). Pure. A time that doesn't exist (the spring change) moves forward by the gap; one that occurs twice
/// (autumn) takes the first. Ids never use the resolved instant (ADR 0007).
///
/// Resolution works on the zone's UTC offsets, not `Calendar.nextDate`, which jumps a whole day for a gap in a zone
/// with a 30-minute change (Australia/Lord_Howe). For each offset in force within a day of the time, `u − offset` is a
/// candidate (u: the wall clock read as UTC), kept when the zone really has that offset then. One candidate is the
/// normal case; two are a fold (the earlier wins); none is a gap (the offset before it applies).
struct ImportTimeResolver: Sendable {
    let zone: TimeZone

    struct Resolution: Equatable, Sendable {
        let instant: Date
        /// `.nonexistentLocalTime` or `.repeatedLocalTime` when a clock change touched the time; nil otherwise.
        let note: ImportWarning.Kind?
    }

    func resolve(_ time: LocalDateTime) -> Resolution {
        resolve(wall: Self.wallClockSeconds(date: time.date, hour: time.hour, minute: time.minute))
    }

    /// The first instant of a local day: midnight, or the end of the gap where midnight didn't exist.
    func startOfDay(_ date: LocalDate) -> Date {
        resolve(wall: Self.wallClockSeconds(date: date, hour: 0, minute: 0)).instant
    }

    /// Seconds since 1970-01-01T00:00 for a wall clock, as if it were UTC (days from the civil date, no calendar).
    static func wallClockSeconds(date: LocalDate, hour: Int, minute: Int) -> Int {
        daysFromCivil(year: date.year, month: date.month, day: date.day) * day + hour * 3_600 + minute * 60
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (H. Hinnant's `days_from_civil`).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    // MARK: Private

    private static let day = 86_400

    private func resolve(wall: Int) -> Resolution {
        var candidates: [Int] = []
        for offset in offsets(around: wall) {
            let instant = wall - offset
            if utcOffset(at: instant) == offset, !candidates.contains(instant) {
                candidates.append(instant)
            }
        }
        candidates.sort()
        if let first = candidates.first {
            return Resolution(instant: Date(timeIntervalSince1970: Double(first)),
                              note: candidates.count > 1 ? .repeatedLocalTime : nil)
        }
        // A gap: read the wall clock with the offset in force before it, which moves it forward by the gap's length.
        let before = utcOffset(at: wall - Self.day)
        return Resolution(instant: Date(timeIntervalSince1970: Double(wall - before)), note: .nonexistentLocalTime)
    }

    /// The zone's offsets from a day before to a day after the wall clock (read as UTC). Real zones change at most
    /// once in such a window, and a change is seen from both sides.
    private func offsets(around wall: Int) -> [Int] {
        var found: [Int] = []
        for shift in stride(from: -Self.day, through: Self.day, by: Self.day / 2) {
            let offset = utcOffset(at: wall + shift)
            if !found.contains(offset) { found.append(offset) }
        }
        return found
    }

    private func utcOffset(at seconds: Int) -> Int {
        zone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(seconds)))
    }
}
