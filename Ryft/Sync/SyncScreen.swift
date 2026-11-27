// The records of a sync page that `POST /v1/sync` would refuse, taken out before the page goes up.
import Foundation

/// Ingest's `validate()` (`plattform/backend/cmd/ingest/main.go`) answers a whole `POST /v1/sync` request with `422` for
/// one record it refuses, and stores nothing of it. An anchor can't move past a refused page, so one such record in Apple
/// Health (a workout without a duration, from another app or a manual entry) held its stream, and every stream drained
/// after it, for good. `screen(_:)` mirrors the rules on the values as they go over the wire and drops what they'd refuse;
/// the page's anchor then moves on with the rest (`SyncEngine.drain`).
///
/// The rules, as `validate()` has them:
/// - A sample: a `start` (Go's zero time is none), and `end` not before `start`.
/// - A sleep segment and a workout: `end` after `start`; a workout has an `id`.
/// - Any record: `source_bundle_id` at most 255 bytes. Only that field is wrong, so the record goes without it
///   (`trimmed`): its data still counts, and `User.sources` lists the source by its name.
/// - The request: `app_version` and `os_version` at most 64 bytes, else sent as nil (`version(_:)`); at most 5 000
///   workouts (`maxWorkouts`: `SyncEngine` pages workouts below it).
///
/// Not refused, so not screened: an empty `activity` (the platform stores `other`), unknown sample types and sleep
/// stages, and records outside the window (the platform drops and counts them in `ignored`).
///
/// **The wire's precision.** `APIClient.jsonEncoder` writes whole seconds, and the platform compares what it reads: a
/// workout from 10:00:00.2 to 10:00:00.7 arrives with `end == start`. Within two seconds of each other the encoder itself
/// decides (rare: everything else keeps its order when truncated). **Lengths** are Go's `len`: UTF-8 bytes, counted after
/// ingest removed every `\u0000` (`ReadJSONStripNUL`).
enum SyncScreen {
    struct Result {
        var delta: HealthDelta
        /// Records dropped: the platform would refuse the request for them.
        var invalid = 0
        /// Records sent without their `source_bundle_id`, which was too long.
        var trimmed = 0
    }

    /// `validate()`'s `maxBundleIDLen` and `maxVersionLen`, and `model.MaxWorkouts`.
    static let maxBundleIDBytes = 255
    static let maxVersionBytes = 64
    static let maxWorkouts = 5_000

    /// `delta` without the records `validate()` refuses, and with no field it refuses. A page with nothing to change
    /// (nearly every one) comes back as it is, uncopied.
    static func screen(_ delta: HealthDelta) -> Result {
        var invalid = 0
        var trimmed = 0
        var out = delta
        out.samples = screened(delta.samples, invalid: &invalid, trimmed: &trimmed)
        out.sleep = screened(delta.sleep, invalid: &invalid, trimmed: &trimmed)
        out.workouts = screened(delta.workouts, invalid: &invalid, trimmed: &trimmed)
        return Result(delta: out, invalid: invalid, trimmed: trimmed)
    }

    /// `app_version`, `os_version`: nil when the platform would refuse the request for it.
    static func version(_ value: String?) -> String? {
        tooLong(value, maxVersionBytes) ? nil : value
    }

    private static func screened<R: IngestRecord>(_ records: [R], invalid: inout Int, trimmed: inout Int) -> [R] {
        guard let first = records.firstIndex(where: { !$0.passesValidation || tooLong($0.sourceBundleId, maxBundleIDBytes) })
        else { return records }
        var kept = Array(records[..<first])
        kept.reserveCapacity(records.count)
        for var record in records[first...] {
            guard record.passesValidation else {
                invalid += 1
                continue
            }
            if tooLong(record.sourceBundleId, maxBundleIDBytes) {
                record.sourceBundleId = nil
                trimmed += 1
            }
            kept.append(record)
        }
        return kept
    }

    // MARK: the rules

    /// Longer than `limit` as `validate()` counts: UTF-8 bytes, without `\u0000`.
    static func tooLong(_ value: String?, _ limit: Int) -> Bool {
        guard let value, value.utf8.count > limit else { return false }
        return value.utf8.lazy.filter { $0 != 0 }.count > limit
    }

    /// `end` isn't before `start` on the wire (a sample's rule).
    static func endNotBeforeStart(_ start: Date, _ end: Date) -> Bool {
        if end >= start { return true }
        if start.timeIntervalSince(end) >= 2 { return false }
        return wire(start) == wire(end)
    }

    /// `end` is after `start` on the wire (a sleep segment's and a workout's rule).
    static func endAfterStart(_ start: Date, _ end: Date) -> Bool {
        if end <= start { return false }
        if end.timeIntervalSince(start) >= 2 { return true }
        return wire(start) != wire(end)
    }

    /// The sample has no `start` for the platform: it goes up as `0001-01-01T00:00:00Z`, which Go reads as its zero
    /// time. The encoder writes `Date.distantPast` that way (Foundation counts Julian days before 1582, Go proleptic
    /// Gregorian ones).
    static func lacksStart(_ start: Date) -> Bool {
        guard abs(start.timeIntervalSince(.distantPast)) < 2 else { return false }
        return wire(start) == goZeroTime
    }

    static let goZeroTime = Data(#""0001-01-01T00:00:00Z""#.utf8)

    /// The date as it goes up (`APIClient.jsonEncoder`: whole seconds, `Z`).
    static func wire(_ date: Date) -> Data? {
        try? APIClient.jsonEncoder.encode(date)
    }

    /// `uuid.Nil`, which `validate()` refuses as a workout's `id`.
    static let nilID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

/// A record of a sync page, as `validate()` checks it.
protocol IngestRecord {
    var sourceBundleId: String? { get set }
    /// Everything but `source_bundle_id` passes (`SyncScreen`).
    var passesValidation: Bool { get }
}

extension Sample: IngestRecord {
    var passesValidation: Bool {
        if type == .bodyMass, unit != "kg" || !(25...350).contains(value) { return false }
        return !SyncScreen.lacksStart(start) && SyncScreen.endNotBeforeStart(start, end)
    }
}

extension SleepSegment: IngestRecord {
    var passesValidation: Bool { SyncScreen.endAfterStart(start, end) }
}

extension Workout: IngestRecord {
    var passesValidation: Bool { id != SyncScreen.nilID && SyncScreen.endAfterStart(start, end) }
}
