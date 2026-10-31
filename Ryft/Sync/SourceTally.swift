import Foundation

/// How many records each source sent RYFT, per stream and local day: counted when an anchored page commits, so it is
/// what RYFT read and the platform accepted (architecture.md §D4.1 (d)). It gives the Sources screen its "5,312
/// samples" without reading every record of the week from HealthKit, and it is the same fact `samples_7d` will report
/// from the platform's side.
///
/// Rules the engine keeps when it counts (the hook in `SyncEngine`):
/// - only anchored pages, at their commit: a page read again after a `413` or a crash is counted once, and the recent
///   window and "Sync last 3 days again" are not counted, because the backfill sends their records again;
/// - `prune` on every save, `reset` with the anchors (a full re-sync reads everything again).
///
/// Records deleted in Apple Health stay counted: a deletion carries neither its source nor its day.
struct SourceTally: Codable, Equatable, Sendable {
    /// Source key (`key(source:bundleID:)`) → `HealthStream.anchorID` → local day (`yyyy-MM-dd`) → records.
    private(set) var counts: [String: [String: [String: Int]]] = [:]
    /// When counting began: the first counted page, or the last reset.
    private(set) var since: Date?
    /// A backfill that started from no anchors finished while the tally was on: every record of the window was
    /// counted, whenever counting began.
    private(set) var backfilled = false

    /// Local days kept: the 7-day window touches 8 of them.
    static let keptDays = 8
    static let window: TimeInterval = 7 * 86_400

    init() {}

    /// Every field optional on disk, like `SyncEngineState`'s: a later field never loses the counts.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        counts = try c.decodeIfPresent([String: [String: [String: Int]]].self, forKey: .counts) ?? [:]
        since = try c.decodeIfPresent(Date.self, forKey: .since)
        backfilled = try c.decodeIfPresent(Bool.self, forKey: .backfilled) ?? false
    }

    /// A source as `SourceFreshness.newestPerSource` keys it: its bundle id, else its name.
    static func key(source: String, bundleID: String?) -> String {
        if let bundleID, !bundleID.isEmpty { return bundleID }
        return "name:" + source
    }

    static func key(_ ref: SourceRef) -> String { key(source: ref.name, bundleID: ref.bundleID) }

    /// Counts a committed anchored page of `stream`. A record's day is the one the engine gives it (a night by its
    /// wake). Runs off the main actor with the commit: a page holds up to 20,000 records, and a day is formatted once
    /// per run of records on it, not per record.
    mutating func add(_ delta: HealthDelta, stream: HealthStream, at now: Date, calendar: Calendar = .current) {
        guard !delta.isEmpty else { return }
        if since == nil { since = now }
        var days = DayKeys(calendar: calendar)
        var page: [String: [String: Int]] = [:]
        func count(_ key: String, _ date: Date) { page[key, default: [:]][days.key(date), default: 0] += 1 }
        for s in delta.samples { count(Self.key(source: s.source, bundleID: s.sourceBundleId), s.start) }
        for s in delta.sleep { count(Self.key(source: s.source, bundleID: s.sourceBundleId), s.end) }
        for w in delta.workouts { count(Self.key(source: w.source, bundleID: w.sourceBundleId), w.start) }
        for (key, perDay) in page {
            for (day, n) in perDay { counts[key, default: [:]][stream.anchorID, default: [:]][day, default: 0] += n }
        }
    }

    /// Keeps the last `keptDays` local days up to `now`; sources and streams left empty go.
    mutating func prune(now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -(Self.keptDays - 1), to: today) ?? today
        var days = DayKeys(calendar: calendar)
        let oldest = days.key(first)
        for (key, streams) in counts {
            var kept: [String: [String: Int]] = [:]
            for (stream, perDay) in streams {
                let recent = perDay.filter { $0.key >= oldest }
                if !recent.isEmpty { kept[stream] = recent }
            }
            counts[key] = kept.isEmpty ? nil : kept
        }
    }

    /// With the anchors: everything is read again, and counted from `now`.
    mutating func reset(at now: Date) {
        counts = [:]
        since = now
        backfilled = false
    }

    /// A backfill that began from no anchors at `started` has finished. It covers the window only if the tally was
    /// already counting then; a backfill that began before this build counted nothing of its first pages.
    mutating func backfillFinished(startedAt started: Date) {
        guard let since, since <= started else { return }
        backfilled = true
    }

    /// Whether every record RYFT accepted in `window` was counted: counting began before it, or a backfill from
    /// scratch ran with the tally on. Until then a count would be too low, so there is none.
    func covers(_ window: DateInterval) -> Bool {
        if backfilled { return true }
        guard let since else { return false }
        return since <= window.start
    }

    /// Records of source `key` on the local days `window` touches, over `streams` (anchor ids).
    func records(_ key: String, streams: Set<String>, in window: DateInterval, calendar: Calendar = .current) -> Int {
        guard let perStream = counts[key] else { return 0 }
        let days = Self.days(touching: window, calendar: calendar)
        return perStream.filter { streams.contains($0.key) }.values
            .reduce(0) { total, perDay in total + perDay.reduce(0) { days.contains($1.key) ? $0 + $1.value : $0 } }
    }

    /// The local days `window` touches, first to last.
    static func days(touching window: DateInterval, calendar: Calendar = .current) -> Set<String> {
        var keys = DayKeys(calendar: calendar)
        var found = Set<String>()
        var day = calendar.startOfDay(for: window.start)
        while day <= window.end {
            found.insert(keys.key(day))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return found
    }
}

/// `yyyy-MM-dd` in the calendar's time zone, formatted once per day: records mostly come in runs on the same day.
private struct DayKeys {
    let calendar: Calendar
    private var current: (interval: DateInterval, key: String)?

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    mutating func key(_ date: Date) -> String {
        if let current, date >= current.interval.start, date < current.interval.end { return current.key }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        if let interval = calendar.dateInterval(of: .day, for: date) { current = (interval, key) }
        return key
    }
}
