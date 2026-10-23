// What the user recorded or typed, kept on this iPhone until the platform confirms it (ADR 0004, design.md §2.3).
// The rows live in the account's SwiftData store (`TrainStore`); only `ActivityStore` reads and writes them,
// filtered by `account`. Views and the uploader get value snapshots.
import Foundation
import SwiftData

/// One manual or recorded activity, until compaction (30 days after confirmation).
@Model
final class LocalActivity {
    @Attribute(.unique) var id: UUID
    /// The Supabase user id at creation; every fetch filters by it (design.md §8.4).
    var account: String
    /// Set when a session expiry kept the row (§8.4); deleted after 30 days.
    var parkedAt: Date?
    var sportRaw: String
    var originRaw: String
    /// `RecordingPhase` while recording; `LocalActivity.savedPhase` for a saved document.
    var phaseRaw: String
    var start: Date
    var end: Date?
    var movingSec: Double
    var distanceM: Double?
    var ascentM: Double?
    var descentM: Double?
    var perceivedEffort: Int?
    var notes: String
    var recordRoute: Bool
    /// Privacy zones active when recording started (§8.2, the withhold rule).
    var zoneCountAtRecording: Int
    /// The route isn't attached until the user decides (§8.2).
    var routeWithheld: Bool
    /// Unconfirmed for 30 days: the route went, the activity stayed (§8.6).
    var routeDroppedAt: Date?
    /// `[ActivitySplit]`, wire JSON.
    var splitsData: Data?
    /// `[DateInterval]` (manual and auto), for Apple Health's events and a resume.
    var pausesData: Data?
    /// `RecordingHeader` (§3.9) while recording or interrupted. No coordinates.
    var headerData: Data?
    /// Bumped by every save or edit. A recording keeps 0 until Save, so it isn't uploaded mid-run.
    var localRevision: Int
    /// The newest revision the platform answered 2xx to.
    var confirmedRevision: Int
    /// A tombstone until the `DELETE` is confirmed.
    var deletedAt: Date?
    /// `UploadAttempt`: the last failure's time, status, code, request ID. Never a body.
    var lastAttemptData: Data?
    /// nil · saved · alreadySaved · recordedElsewhere · failed (Apple Health, A6).
    var healthStateRaw: String?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), account: String, sport: Sport, origin: ActivityOrigin,
         phase: String = LocalActivity.savedPhase, start: Date, end: Date?, movingSec: Double,
         distanceM: Double? = nil, ascentM: Double? = nil, descentM: Double? = nil, perceivedEffort: Int? = nil,
         notes: String = "", recordRoute: Bool = false, zoneCountAtRecording: Int = 0, splits: [ActivitySplit]? = nil,
         localRevision: Int, confirmedRevision: Int = 0, createdAt: Date) {
        self.id = id
        self.account = account
        sportRaw = sport.rawValue
        originRaw = origin.rawValue
        phaseRaw = phase
        self.start = start
        self.end = end
        self.movingSec = movingSec
        self.distanceM = distanceM
        self.ascentM = ascentM
        self.descentM = descentM
        self.perceivedEffort = perceivedEffort
        self.notes = notes
        self.recordRoute = recordRoute
        self.zoneCountAtRecording = zoneCountAtRecording
        routeWithheld = false
        splitsData = splits.flatMap { WireCoding.encode($0) }
        self.localRevision = localRevision
        self.confirmedRevision = confirmedRevision
        self.createdAt = createdAt
        updatedAt = createdAt
    }
}

extension LocalActivity {
    /// `phaseRaw` of a document: typed in, or a recording that was saved.
    static let savedPhase = "saved"

    var sport: Sport { Sport(rawValue: sportRaw) ?? .other }
    var origin: ActivityOrigin { ActivityOrigin(rawValue: originRaw) ?? .manual }
    var splits: [ActivitySplit] { WireCoding.decode([ActivitySplit].self, splitsData) ?? [] }
    var lastAttempt: UploadAttempt? { WireCoding.decode(UploadAttempt.self, lastAttemptData) }

    var snapshot: LocalActivitySnapshot {
        LocalActivitySnapshot(id: id, account: account, sport: sport, origin: origin, phase: phaseRaw, start: start,
                              end: end, movingSec: movingSec, distanceM: distanceM, ascentM: ascentM,
                              descentM: descentM, perceivedEffort: perceivedEffort, notes: notes,
                              recordRoute: recordRoute, routeWithheld: routeWithheld, routeDroppedAt: routeDroppedAt,
                              splits: splits, localRevision: localRevision, confirmedRevision: confirmedRevision,
                              deletedAt: deletedAt, lastAttempt: lastAttempt, createdAt: createdAt,
                              updatedAt: updatedAt)
    }
}

/// One checkpoint's new samples of one kind, packed by `TrackCodec` (A3). Append-only, and no relationship:
/// `TrainStore.wipe()` uses batch deletes, which skip cascades, so chunks are deleted by `activityID`.
@Model
final class ActivityTrackChunk {
    var activityID: UUID
    var account: String
    var seq: Int
    /// `Kind`.
    var kindRaw: String
    /// ≤ ~1 KB. `route` and `heartRate` are sealed (AES-GCM, §8.6).
    var data: Data
    var count: Int
    var first: Date
    var last: Date

    init(activityID: UUID, account: String, seq: Int, kind: Kind, data: Data, count: Int, first: Date, last: Date) {
        self.activityID = activityID
        self.account = account
        self.seq = seq
        kindRaw = kind.rawValue
        self.data = data
        self.count = count
        self.first = first
        self.last = last
    }
}

extension ActivityTrackChunk {
    enum Kind: String, CaseIterable, Sendable {
        /// Time, cumulative distance, altitude, speed: no coordinates. Charts, splits and resume use it.
        case profile
        /// Time, latitude, longitude, accuracy, altitude: only with the route opt-in, trimmed by the zones
        /// active at recording, sealed.
        case route
        /// Time and bpm (Bluetooth sensor), sealed.
        case heartRate
    }

    var kind: Kind? { Kind(rawValue: kindRaw) }

    var snapshot: ChunkSnapshot {
        ChunkSnapshot(activityID: activityID, seq: seq, kind: kind, data: data, count: count, first: first, last: last)
    }
}

/// "Add sleep": a night the user typed in, until the platform confirms it.
@Model
final class LocalManualSleep {
    /// The wake day, `yyyy-MM-dd`.
    @Attribute(.unique) var day: String
    var account: String
    /// Set when a session expiry kept the row (§8.4), like `LocalActivity.parkedAt`.
    var parkedAt: Date?
    var bed: Date
    var wake: Date
    var localRevision: Int
    var confirmedRevision: Int
    var deletedAt: Date?
    var lastAttemptData: Data?

    init(day: String, account: String, bed: Date, wake: Date, localRevision: Int = 1, confirmedRevision: Int = 0) {
        self.day = day
        self.account = account
        self.bed = bed
        self.wake = wake
        self.localRevision = localRevision
        self.confirmedRevision = confirmedRevision
    }
}

extension LocalManualSleep {
    var snapshot: ManualSleepSnapshot {
        ManualSleepSnapshot(day: day, bed: bed, wake: wake, localRevision: localRevision,
                            confirmedRevision: confirmedRevision, deletedAt: deletedAt,
                            lastAttempt: WireCoding.decode(UploadAttempt.self, lastAttemptData))
    }
}

// MARK: - snapshots

/// A value copy of a `LocalActivity` row: what My Day, the uploader and the payload read. Never a coordinate.
struct LocalActivitySnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let account: String
    let sport: Sport
    let origin: ActivityOrigin
    let phase: String
    let start: Date
    let end: Date?
    let movingSec: Double
    let distanceM: Double?
    let ascentM: Double?
    let descentM: Double?
    let perceivedEffort: Int?
    let notes: String
    let recordRoute: Bool
    let routeWithheld: Bool
    let routeDroppedAt: Date?
    let splits: [ActivitySplit]
    let localRevision: Int
    let confirmedRevision: Int
    let deletedAt: Date?
    let lastAttempt: UploadAttempt?
    let createdAt: Date
    let updatedAt: Date

    /// Deleted by the user; the row stays until the platform confirms the `DELETE`.
    var isTombstone: Bool { deletedAt != nil }
    /// An edit the platform hasn't confirmed, or a delete.
    var needsUpload: Bool { localRevision > confirmedRevision || deletedAt != nil }
    /// A saved document (not a recording in progress or interrupted).
    var isSaved: Bool { phase == LocalActivity.savedPhase }

    /// What the row alone says. The uploader (A2) knows more: offline, in flight, retrying, gated, failed.
    /// `nil` while recording (nothing to upload yet).
    var storedUploadState: UploadState? {
        if localRevision == 0, deletedAt == nil { return nil }
        return needsUpload ? .pending(.queued) : .confirmed
    }

    /// The wire document as of this revision, without route or heart rate (those are `ActivityPayload`'s, A4/A5).
    var activity: SportActivity {
        SportActivity(id: id, sport: sport, origin: origin, start: start,
                      end: self.end ?? start.addingTimeInterval(movingSec), movingSec: movingSec,
                      distanceM: distanceM, ascentM: ascentM, descentM: descentM,
                      perceivedEffort: perceivedEffort, notes: notes.isEmpty ? nil : notes,
                      splits: splits.isEmpty ? nil : splits, clientUpdatedAt: updatedAt)
    }
}

/// A value copy of a `LocalManualSleep` row.
struct ManualSleepSnapshot: Equatable, Sendable {
    let day: String
    let bed: Date
    let wake: Date
    let localRevision: Int
    let confirmedRevision: Int
    let deletedAt: Date?
    let lastAttempt: UploadAttempt?

    var isTombstone: Bool { deletedAt != nil }
    var needsUpload: Bool { localRevision > confirmedRevision || deletedAt != nil }
}

/// A value copy of an `ActivityTrackChunk`, for the payload (A4) and charts. `route` and `heartRate` data
/// stay sealed until `ActivityVault` opens them.
struct ChunkSnapshot: Equatable, Sendable {
    let activityID: UUID
    let seq: Int
    /// nil: a kind this build doesn't know.
    let kind: ActivityTrackChunk.Kind?
    let data: Data
    let count: Int
    let first: Date
    let last: Date
}

/// What the user typed in Add activity, or changed in Edit (`ActivityStore.save(manual:)`, `update(_:_:)`).
/// Validation is the form's (`AddActivityModel`, A2).
struct ActivityDraft: Equatable, Sendable {
    var sport: Sport
    var start: Date
    var end: Date
    var distanceM: Double?
    /// 1–10.
    var perceivedEffort: Int?
    var notes: String

    init(sport: Sport, start: Date, end: Date, distanceM: Double? = nil, perceivedEffort: Int? = nil,
         notes: String = "") {
        self.sport = sport
        self.start = start
        self.end = end
        self.distanceM = distanceM
        self.perceivedEffort = perceivedEffort
        self.notes = notes
    }
}

extension TrainStore {
    /// The activity tables (design.md §2.3). Wiped with the rest of the store; A2 adds parking (§8.4).
    /// `LocalPrivacyZone` joins them in A5.
    static let activityModels: [any PersistentModel.Type] = [LocalActivity.self, ActivityTrackChunk.self,
                                                             LocalManualSleep.self]
}
