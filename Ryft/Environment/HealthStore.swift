import Foundation
import HealthKit
import os

/// One anchored stream HealthKit is drained by: a quantity type, sleep or workouts.
enum HealthStream: Hashable, Sendable {
    case quantity(SampleType)
    case sleep
    case workouts

    /// Key of its persisted anchor (unchanged from before the seam).
    var anchorID: String {
        switch self {
        case .quantity(let t): return t.rawValue
        case .sleep: return "sleep"
        case .workouts: return "workouts"
        }
    }

    /// Lower case, for "Syncing · heart rate" and Sync details.
    var displayName: String {
        switch self {
        case .sleep: return String(localized: "sleep")
        case .workouts: return String(localized: "workouts")
        case .quantity(let t):
            switch t {
            case .heartRate: return String(localized: "heart rate")
            case .hrvSDNN: return String(localized: "HRV")
            case .restingHR: return String(localized: "resting heart rate")
            case .respiratoryRate: return String(localized: "respiratory rate")
            case .spo2: return String(localized: "blood oxygen")
            case .vo2max: return String(localized: "VO₂ max")
            case .activeEnergy: return String(localized: "active energy")
            case .steps: return String(localized: "steps")
            }
        }
    }
}

/// Last night as Apple Health has it, before RYFT scored it: raw totals from one source,
/// not a score (the phone computes no scores).
struct RawNight: Equatable, Sendable {
    let asleepMin: Int
    let bedtime: Date
    let wake: Date
    /// As HealthKit names the source ("Connect"); Today shows its display name (`TodayContent.rawNightSource`).
    let source: String
    /// Its first segment's `sourceBundleId`, for the display name.
    let bundleID: String?

    init(asleepMin: Int, bedtime: Date, wake: Date, source: String, bundleID: String? = nil) {
        self.asleepMin = asleepMin
        self.bedtime = bedtime
        self.wake = wake
        self.source = source
        self.bundleID = bundleID
    }

    /// The source as the tracker catalog matches it (a night carries no device model).
    var ref: SourceRef { SourceRef(name: source, bundleID: bundleID, deviceModel: nil) }

    /// The source that recorded the most sleep: its asleep stages summed, from its first
    /// segment (in bed included) to its last. `nil` without any sleep.
    static func from(_ segments: [SleepSegment]) -> RawNight? {
        let asleep: Set<SleepStage> = [.asleep, .core, .deep, .rem]
        let nights = Dictionary(grouping: segments, by: \.source).compactMap { source, list -> RawNight? in
            let minutes = list.filter { asleep.contains($0.stage) }
                .reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) } / 60
            guard minutes >= 1, let bed = list.map(\.start).min(), let wake = list.map(\.end).max() else { return nil }
            return RawNight(asleepMin: Int(minutes.rounded()), bedtime: bed, wake: wake, source: source,
                            bundleID: list.min { $0.start < $1.start }?.sourceBundleId)
        }
        return nights.max { ($0.asleepMin, $0.source) < ($1.asleepMin, $1.source) }
    }

    /// Since 18:00 the evening before `now`.
    static func window(before now: Date, calendar: Calendar = .current) -> Date {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday) ?? yesterday
    }
}

/// The newest record one source wrote to Apple Health, for "your watch hasn't synced".
struct SourceFreshness: Equatable, Sendable {
    /// As HealthKit names it ("Connect", "Tim's Apple Watch"); Today shows the display name.
    let source: String
    /// `com.apple.health.…` for an Apple device; the writing app's otherwise.
    let bundleID: String?
    let newest: Date
    /// The newest sample's device ("Watch", "iPhone"; `SourceRef.deviceModel(model:productType:)`).
    let deviceModel: String?

    init(source: String, bundleID: String?, newest: Date, deviceModel: String? = nil) {
        self.source = source
        self.bundleID = bundleID
        self.newest = newest
        self.deviceModel = deviceModel
    }

    var ref: SourceRef { SourceRef(name: source, bundleID: bundleID, deviceModel: deviceModel) }

    /// An app that syncs to Apple Health only while it runs, unlike Apple's own devices.
    var isApp: Bool { !(bundleID ?? "").hasPrefix("com.apple.health") }

    /// This iPhone itself (its sleep schedule writes in-bed time): never the night's evidence.
    var isPhone: Bool {
        (bundleID ?? "").lowercased().hasPrefix("com.apple.health.") && deviceModel?.lowercased() == "iphone"
    }

    /// One entry per source from heart rate's and sleep's: the newer record, and a device model from
    /// either (the iPhone writes no heart rate, an app may write sleep only).
    static func newestPerSource(_ lists: [[SourceFreshness]]) -> [SourceFreshness] {
        var newest: [String: SourceFreshness] = [:]
        var order: [String] = []
        for entry in lists.joined() {
            let key = entry.bundleID ?? "name:" + entry.source
            guard let current = newest[key] else {
                newest[key] = entry
                order.append(key)
                continue
            }
            let later = entry.newest > current.newest ? entry : current
            newest[key] = SourceFreshness(source: later.source, bundleID: later.bundleID, newest: later.newest,
                                          deviceModel: later.deviceModel ?? current.deviceModel ?? entry.deviceModel)
        }
        return order.compactMap { newest[$0] }
    }
}

/// The newest record of one type from one source, for Check sync (design.md §4.1). Never persisted.
struct SourceSample: Equatable, Sendable {
    let stream: HealthStream
    let source: SourceRef
    /// Its end date.
    let newest: Date
    /// Sleep only: that source's newest night holds core, deep or REM (`HealthProbe.newestNightHasStages`).
    var hasStages: Bool?
}

/// One page of new records, with the opaque anchor that marks its end. The caller
/// uploads the delta, then `commit`s the page; that ordering makes sync crash-safe.
/// The next page can be read before this one is committed (`nextPage(_:after:)`), so
/// reading overlaps the upload.
struct HealthPage {
    let delta: HealthDelta
    let anchor: Data?
    let more: Bool
    /// HealthKit UUIDs deleted in Apple Health since the previous anchor.
    var deleted: [UUID] = []
}

/// HealthKit is unreadable while the phone is locked (protected data): a delivery or a
/// background task that fires then gets `errorDatabaseInaccessible`. Not a failure: the
/// sync waits for the unlock.
enum ProtectedData {
    static func isLocked(_ error: Error) -> Bool {
        (error as? HKError)?.code == .errorDatabaseInaccessible
    }
}

/// What HealthKit grants is never visible for reads, only whether the prompt still has to show.
enum HealthAccess: Equatable, Sendable {
    case unavailable, notAsked, asked, unknown
}

/// HealthKit, behind a seam. `HealthKitManager` is the live store; `MockHealthStore`
/// scripts pages for tests and previews. Reads are called off the main actor
/// (`SyncEngine`): mapping thousands of samples must not cost a frame.
protocol HealthStore: AnyObject {
    var isAvailable: Bool { get }
    /// Streams in the order a sync drains them: what scoring waits for first.
    var streams: [HealthStream] { get }
    /// The most records one page may hold; the engine sizes pages below it by bytes.
    var pageSize: Int { get set }
    /// Some stream has a committed anchor for this account (not its first sync).
    var hasAnchors: Bool { get }
    func requestAuthorization() async throws
    func accessStatus() async -> HealthAccess
    /// `.immediate` delivery for the observed types; idempotent, called on every launch.
    func enableBackgroundDelivery() async
    /// Registers the observers once (during launch). `onChange` gets the delivery's
    /// completion and calls it as soon as the upload is done.
    func startObserving(onChange: @escaping @Sendable (_ done: @escaping @Sendable () -> Void) -> Void)
    /// The page after `anchor` (an uncommitted page's), or after the committed anchor when
    /// `nil`; at most `limit` records. Without any anchor: the backfill window.
    func nextPage(_ stream: HealthStream, after anchor: Data?, limit: Int) async throws -> HealthPage
    /// The recent window (`since` up to now) page by page, for the first score; its anchors
    /// are never committed (`after`: the previous recent page's).
    func recentPage(_ stream: HealthStream, since: Date, after anchor: Data?, limit: Int) async throws -> HealthPage
    func commit(_ page: HealthPage, for stream: HealthStream)
    func migrateLegacyAnchors()
    func resetAnchors()
    /// Last night's sleep as Apple Health has it (`RawNight.from`), since 18:00 the evening
    /// before `now`; `nil` without any.
    func lastNight(before now: Date) async throws -> RawNight?
    /// The newest heart-rate or sleep record per source since `since`, whichever is newer, with its
    /// device: the watches, their apps, and the iPhone's in-bed sleep (`SourceFreshness.isPhone`).
    func newestRecords(since: Date) async throws -> [SourceFreshness]
    /// Check sync: the newest record per type and source since `since`, RYFT's own records left out. Types RYFT
    /// may not read come back empty, exactly like types nobody wrote. Called from `HealthProbe`, off the main actor.
    func newestSamples(of streams: [HealthStream], since: Date) async throws -> [SourceSample]
    /// The types RYFT sees at least one record of, from any source but RYFT, ever: proof that reading is
    /// allowed. Absence proves nothing (iOS never says a read is denied).
    func visibleTypes(_ streams: [HealthStream]) async throws -> Set<HealthStream>
    /// Asks to write workouts (and nothing else) to Apple Health; `true` when allowed.
    func requestWorkoutWriteAccess() async throws -> Bool
    /// Whether RYFT may write workouts (iOS says so for writing, never for reading).
    var canWriteWorkouts: Bool { get }
    /// A strength workout RYFT logged, as an `HKWorkout`: start, end, brand "RYFT" and the
    /// session's id as its external UUID. No heart-rate samples: the watch records those.
    /// Once per session, and not when the watch (or another app) recorded it.
    func saveStrengthWorkout(sessionID: UUID, start: Date, end: Date) async throws -> WorkoutSaveResult
    /// RYFT's workouts since `since` that another app or the watch recorded too (the watch's
    /// ended after the session): deleted, so Fitness lists each once. How many.
    func removeOwnWorkoutsRecordedElsewhere(since: Date) async throws -> Int
}

enum WorkoutSaveResult: Equatable, Sendable {
    case saved
    /// This session's workout is in Apple Health already (a second tap, a retry).
    case alreadySaved
    /// A strength workout from the watch or another app covers at least half of the session
    /// (the platform's rule for attaching the session's load).
    case recordedElsewhere
}

/// The overlap rule for a session and another app's workout: at least half of the session.
enum StrengthOverlap {
    static func covers(_ other: DateInterval, session: DateInterval) -> Bool {
        guard let overlap = other.intersection(with: session) else { return false }
        return overlap.duration >= session.duration / 2
    }
}

extension HealthKitManager: HealthStore {
    var isAvailable: Bool { Self.isAvailable }

    /// The night and the overnight vitals first (what the morning's score waits for),
    /// then workouts, then the high-volume day streams.
    var streams: [HealthStream] {
        [.sleep, .quantity(.hrvSDNN), .quantity(.restingHR), .quantity(.respiratoryRate), .quantity(.spo2),
         .workouts, .quantity(.heartRate), .quantity(.steps), .quantity(.activeEnergy), .quantity(.vo2max)]
    }

    var hasAnchors: Bool {
        streams.contains { anchor(for: $0.anchorID) != nil }
    }

    func nextPage(_ stream: HealthStream, after anchor: Data?, limit: Int) async throws -> HealthPage {
        let from = anchor.flatMap(Self.unarchive) ?? self.anchor(for: stream.anchorID)
        // Only the very first query of a stream is bounded to the backfill window.
        return try await page(stream, anchor: from, predicate: from == nil ? backfillPredicate : nil, limit: limit)
    }

    func recentPage(_ stream: HealthStream, since: Date, after anchor: Data?, limit: Int) async throws -> HealthPage {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        return try await page(stream, anchor: anchor.flatMap(Self.unarchive), predicate: predicate, limit: limit)
    }

    private func page(_ stream: HealthStream, anchor: HKQueryAnchor?, predicate: NSPredicate?,
                      limit: Int) async throws -> HealthPage {
        switch stream {
        case .quantity(let type):
            guard let spec = quantities.first(where: { $0.type == type }) else {
                return HealthPage(delta: HealthDelta(), anchor: nil, more: false)
            }
            let p = try await quantityPage(spec, anchor: anchor, predicate: predicate, limit: limit)
            return HealthPage(delta: HealthDelta(samples: p.items), anchor: Self.archive(p.anchor), more: p.more,
                              deleted: p.deleted)
        case .sleep:
            let p = try await sleepPage(anchor: anchor, predicate: predicate, limit: limit)
            return HealthPage(delta: HealthDelta(sleep: p.items), anchor: Self.archive(p.anchor), more: p.more,
                              deleted: p.deleted)
        case .workouts:
            let p = try await workoutPage(anchor: anchor, predicate: predicate, limit: limit)
            return HealthPage(delta: HealthDelta(workouts: p.items), anchor: Self.archive(p.anchor), more: p.more,
                              deleted: p.deleted)
        }
    }

    func commit(_ page: HealthPage, for stream: HealthStream) {
        guard let anchor = page.anchor.flatMap(Self.unarchive) else { return }
        save(anchor: anchor, for: stream.anchorID)
    }

    func lastNight(before now: Date) async throws -> RawNight? {
        let predicate = HKQuery.predicateForSamples(withStart: RawNight.window(before: now), end: now, options: [])
        let query = HKSampleQueryDescriptor(predicates: [.categorySample(type: sleepType, predicate: predicate)],
                                            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await query.result(for: store)
        return RawNight.from(samples.compactMap { s in
            Self.sleepStage(s.value).map {
                SleepSegment(start: s.startDate, end: s.endDate, stage: $0, source: Self.sourceName(s), sourceBundleId: Self.sourceBundleID(s))
            }
        })
    }

    /// Heart rate and sleep per source, the newer of the two: an app that wrote last night's sleep but
    /// no heart rate since (or the other way round) still counts.
    func newestRecords(since: Date) async throws -> [SourceFreshness] {
        let heartRate = try await newestRecords(of: HKQuantityType(.heartRate), since: since)
        let sleep = try await newestRecords(of: sleepType, since: since)
        return SourceFreshness.newestPerSource([heartRate, sleep])
    }

    /// One query for the type's sources, then the newest record of each (a handful).
    private func newestRecords(of type: HKSampleType, since: Date) async throws -> [SourceFreshness] {
        let window = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        let sources: Set<HKSource> = try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSourceQuery(sampleType: type, samplePredicate: window) { _, sources, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: sources ?? []) }
            })
        }
        var newest: [SourceFreshness] = []
        for source in sources {
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [window, HKQuery.predicateForObjects(from: source)])
            let latest: HKSample? = try await withCheckedThrowingContinuation { continuation in
                store.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                                            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples?.first) }
                })
            }
            if let latest {
                let model = SourceRef.deviceModel(model: latest.device?.model, productType: latest.sourceRevision.productType)
                newest.append(SourceFreshness(source: source.name, bundleID: source.bundleIdentifier, newest: latest.endDate,
                                              deviceModel: model))
            }
        }
        return newest
    }

    // MARK: check sync (design.md §4.1, §10: a handful of small queries, never in the background)

    /// Per type (concurrently): one source query, then per source (one after the other) its newest record,
    /// whose device names an Apple device. For sleep the newest 200 segments, whose newest night says whether
    /// there are stages. RYFT's own source is skipped: its strength workouts say nothing about a tracker. (By bundle
    /// ID: `HKSource.default()` raises an exception in an unsigned build.)
    func newestSamples(of streams: [HealthStream], since: Date) async throws -> [SourceSample] {
        let store = store
        let types = streams.compactMap { stream in sampleType(stream).map { (stream, $0) } }
        return try await withThrowingTaskGroup(of: [SourceSample].self) { group in
            for (stream, type) in types {
                group.addTask {
                    try await Self.newestSamples(store: store, stream: stream, type: type, since: since)
                }
            }
            var all: [SourceSample] = []
            for try await found in group { all += found }
            return all
        }
    }

    /// One limit-1 query per type, unsorted, any time. RYFT can always read what it wrote, so a record of RYFT's
    /// own (a strength workout) proves nothing: then the type's sources decide.
    func visibleTypes(_ streams: [HealthStream]) async throws -> Set<HealthStream> {
        let store = store
        let types = streams.compactMap { stream in sampleType(stream).map { (stream, $0) } }
        return try await withThrowingTaskGroup(of: HealthStream?.self) { group in
            for (stream, type) in types {
                group.addTask {
                    let first = try await Self.samples(store: store, type: type, predicate: nil, limit: 1,
                                                       newestFirst: false).first
                    let readable = try await HealthProbe.readable(firstRecordFrom: first?.sourceRevision.source.bundleIdentifier) {
                        try await Self.sources(store: store, type: type, predicate: nil).map(\.bundleIdentifier)
                    }
                    return readable ? stream : nil
                }
            }
            var visible = Set<HealthStream>()
            for try await stream in group { if let stream { visible.insert(stream) } }
            return visible
        }
    }

    private func sampleType(_ stream: HealthStream) -> HKSampleType? {
        switch stream {
        case .quantity(let type): return quantities.first { $0.type == type }?.hkType
        case .sleep: return sleepType
        case .workouts: return workoutType
        }
    }

    private static func newestSamples(store: HKHealthStore, stream: HealthStream, type: HKSampleType,
                                      since: Date) async throws -> [SourceSample] {
        let window = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        var found: [SourceSample] = []
        for source in try await sources(store: store, type: type, predicate: window)
        where !HealthProbe.isRYFT(bundleID: source.bundleIdentifier) {
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [window, HKQuery.predicateForObjects(from: source)])
            let records = try await samples(store: store, type: type, predicate: predicate, limit: stream == .sleep ? 200 : 1)
            guard let latest = records.first else { continue }
            MainThread.assertOff("Check sync")
            let model = SourceRef.deviceModel(model: latest.device?.model, productType: latest.sourceRevision.productType)
            let ref = SourceRef(name: source.name, bundleID: source.bundleIdentifier.isEmpty ? nil : source.bundleIdentifier,
                                deviceModel: model)
            var sample = SourceSample(stream: stream, source: ref, newest: latest.endDate)
            if stream == .sleep {
                sample.hasStages = HealthProbe.newestNightHasStages(records.compactMap { record in
                    guard let segment = record as? HKCategorySample, let stage = sleepStage(segment.value) else { return nil }
                    return SleepSegment(start: segment.startDate, end: segment.endDate, stage: stage, source: source.name)
                })
            }
            found.append(sample)
        }
        return found
    }

    private static func sources(store: HKHealthStore, type: HKSampleType, predicate: NSPredicate?) async throws -> Set<HKSource> {
        try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSourceQuery(sampleType: type, samplePredicate: predicate) { _, sources, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: sources ?? []) }
            })
        }
    }

    private static func samples(store: HKHealthStore, type: HKSampleType, predicate: NSPredicate?, limit: Int,
                                newestFirst: Bool = true) async throws -> [HKSample] {
        let sort = newestFirst ? [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)] : nil
        return try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sort) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            })
        }
    }

    func requestWorkoutWriteAccess() async throws -> Bool {
        try await store.requestAuthorization(toShare: [workoutType], read: [])
        return canWriteWorkouts
    }

    var canWriteWorkouts: Bool { store.authorizationStatus(for: workoutType) == .sharingAuthorized }

    func saveStrengthWorkout(sessionID: UUID, start: Date, end: Date) async throws -> WorkoutSaveResult {
        let session = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [sessionID.uuidString])
        let ours = NSCompoundPredicate(andPredicateWithSubpredicates: [session, HKQuery.predicateForObjects(from: .default())])
        if try await !workouts(ours, limit: 1).isEmpty { return .alreadySaved }
        if try await recordedElsewhere(DateInterval(start: start, end: end)) { return .recordedElsewhere }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "RYFT",
                                           HKMetadataKeyExternalUUID: sessionID.uuidString])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            builder.discardWorkout()
            throw error
        }
        return .saved
    }

    func removeOwnWorkoutsRecordedElsewhere(since: Date) async throws -> Int {
        let ours = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: .default()),
            HKQuery.predicateForSamples(withStart: since, end: nil, options: []),
        ])
        var duplicates: [HKWorkout] = []
        for workout in try await workouts(ours) where try await recordedElsewhere(DateInterval(start: workout.startDate, end: workout.endDate)) {
            duplicates.append(workout)
        }
        if !duplicates.isEmpty { try await store.delete(duplicates) }
        return duplicates.count
    }

    /// Strength, functional strength or cross training from another source over `session`.
    private func recordedElsewhere(_ session: DateInterval) async throws -> Bool {
        let types: [HKWorkoutActivityType] = [.traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining]
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: session.start, end: session.end, options: []),
            NSCompoundPredicate(orPredicateWithSubpredicates: types.map { HKQuery.predicateForWorkouts(with: $0) }),
        ])
        let own = Bundle.main.bundleIdentifier
        return try await workouts(predicate).contains {
            $0.sourceRevision.source.bundleIdentifier != own
                && StrengthOverlap.covers(DateInterval(start: $0.startDate, end: $0.endDate), session: session)
        }
    }

    private func workouts(_ predicate: NSPredicate, limit: Int = HKObjectQueryNoLimit) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: limit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples as? [HKWorkout] ?? []) }
            })
        }
    }

    private static func archive(_ anchor: HKQueryAnchor?) -> Data? {
        anchor.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
    }

    private static func unarchive(_ data: Data) -> HKQueryAnchor? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
}

/// Scripted HealthKit for tests and previews: pages per stream, handed out in order.
/// Like HealthKit, a page comes back until its anchor is committed, and the page after an
/// uncommitted one can be read with that page's anchor. Reads may run concurrently with a
/// commit (the engine reads ahead), so its state sits behind a lock.
final class MockHealthStore: HealthStore, @unchecked Sendable {
    private let lock = NSLock()
    var isAvailable = true
    var access: HealthAccess = .asked
    var pageSize = 20_000
    let streams: [HealthStream]
    /// The pages per stream, oldest first; an empty list means "nothing new".
    var pages: [HealthStream: [HealthDelta]] {
        get { locked { _pages } }
        set { locked { _pages = newValue } }
    }
    /// The recent window per stream (the first sync's phase 1).
    var recent: [HealthStream: [HealthDelta]] {
        get { locked { _recent } }
        set { locked { _recent = newValue } }
    }
    /// Thrown by the next read, then cleared.
    var nextError: Error? {
        get { locked { _nextError } }
        set { locked { _nextError = newValue } }
    }
    /// Called on every commit, before the anchor moves (tests check what's stored by then).
    var onCommit: ((HealthStream) -> Void)?

    private(set) var authorizationRequests = 0
    private(set) var backgroundDeliveryEnabled = false
    private(set) var observing = false
    private(set) var observerRegistrations = 0
    private(set) var resets = 0
    /// UUIDs deleted per stream, handed out with the stream's next page.
    var deletions: [HealthStream: [UUID]] {
        get { locked { _deletions } }
        set { locked { _deletions = newValue } }
    }
    private var _deletions: [HealthStream: [UUID]] = [:]
    var committed: [HealthStream] { locked { _committed } }
    var pageReads: Int { locked { _pageReads } }
    var recentReads: Int { locked { _recentReads } }
    /// The `limit` of every read, in order.
    var limits: [Int] { locked { _limits } }
    /// Reads that ran on the main thread (mapping belongs off it).
    var readsOnMainThread: Int { locked { _readsOnMainThread } }

    private var _pages: [HealthStream: [HealthDelta]]
    private var _recent: [HealthStream: [HealthDelta]]
    private var _nextError: Error?
    private var _committed: [HealthStream] = []
    private var _pageReads = 0
    private var _recentReads = 0
    private var _limits: [Int] = []
    private var _readsOnMainThread = 0
    private var position: [HealthStream: Int] = [:]
    private var onChange: (@Sendable (_ done: @escaping @Sendable () -> Void) -> Void)?

    init(streams: [HealthStream] = [.quantity(.heartRate), .sleep, .workouts],
         pages: [HealthStream: [HealthDelta]] = [:], recent: [HealthStream: [HealthDelta]] = [:]) {
        self.streams = streams
        _pages = pages
        _recent = recent
    }

    var hasAnchors: Bool { locked { !position.isEmpty } }

    func requestAuthorization() async throws { authorizationRequests += 1; access = .asked }
    func accessStatus() async -> HealthAccess { access }
    func enableBackgroundDelivery() async { backgroundDeliveryEnabled = true }

    func startObserving(onChange: @escaping @Sendable (_ done: @escaping @Sendable () -> Void) -> Void) {
        // Once, like the live store: launch and bootstrap both call it.
        guard !observing else { return }
        observing = true
        observerRegistrations += 1
        self.onChange = onChange
    }

    /// Simulates HealthKit background delivery; `done` is the delivery's completion.
    func deliverChange(done: @escaping @Sendable () -> Void = {}) { onChange?(done) }

    func nextPage(_ stream: HealthStream, after anchor: Data?, limit: Int) async throws -> HealthPage {
        let onMain = MainThread.isCurrent
        return try locked {
            try read(limit, onMain: onMain)
            let index = anchor.flatMap(Self.index).map { $0 + 1 } ?? position[stream, default: 0]
            let queue = _pages[stream] ?? []
            guard index < queue.count else {
                return HealthPage(delta: HealthDelta(), anchor: nil, more: false, deleted: _deletions[stream] ?? [])
            }
            _pageReads += 1
            return HealthPage(delta: queue[index], anchor: Self.anchor(index), more: index + 1 < queue.count,
                              deleted: index == 0 ? _deletions[stream] ?? [] : [])
        }
    }

    func recentPage(_ stream: HealthStream, since: Date, after anchor: Data?, limit: Int) async throws -> HealthPage {
        let onMain = MainThread.isCurrent
        return try locked {
            try read(limit, onMain: onMain)
            let index = anchor.flatMap(Self.index).map { $0 + 1 } ?? 0
            let queue = _recent[stream] ?? []
            guard index < queue.count else { return HealthPage(delta: HealthDelta(), anchor: nil, more: false) }
            _recentReads += 1
            return HealthPage(delta: queue[index], anchor: Self.anchor(index), more: index + 1 < queue.count)
        }
    }

    func commit(_ page: HealthPage, for stream: HealthStream) {
        onCommit?(stream)
        locked {
            _committed.append(stream)
            if !page.deleted.isEmpty { _deletions[stream] = nil }
            let current = position[stream, default: 0]
            position[stream] = page.anchor.flatMap(Self.index).map { $0 + 1 } ?? current
        }
    }

    func migrateLegacyAnchors() {}
    func resetAnchors() { locked { resets += 1; position = [:] } }

    /// What `lastNight` and `newestRecords` answer.
    var night: RawNight?
    var freshness: [SourceFreshness] = []
    func lastNight(before now: Date) async throws -> RawNight? { night }

    /// Workout writing: what iOS answers, what was written, and what the watch recorded.
    var allowsWorkoutWrites: Bool {
        get { locked { _allowsWorkoutWrites } }
        set { locked { _allowsWorkoutWrites = newValue } }
    }
    var writeRequests: Int { locked { _writeRequests } }
    var savedWorkouts: [(sessionID: UUID, start: Date, end: Date)] { locked { _savedWorkouts } }
    /// Other sources' strength workouts.
    var otherWorkouts: [DateInterval] {
        get { locked { _otherWorkouts } }
        set { locked { _otherWorkouts = newValue } }
    }
    private var _allowsWorkoutWrites = true
    private var _writeRequests = 0
    private var _savedWorkouts: [(sessionID: UUID, start: Date, end: Date)] = []
    private var _otherWorkouts: [DateInterval] = []
    var canWriteWorkouts: Bool { locked { _writeRequests > 0 && _allowsWorkoutWrites } }

    func requestWorkoutWriteAccess() async throws -> Bool {
        locked {
            _writeRequests += 1
            return _allowsWorkoutWrites
        }
    }

    func saveStrengthWorkout(sessionID: UUID, start: Date, end: Date) async throws -> WorkoutSaveResult {
        locked {
            if _savedWorkouts.contains(where: { $0.sessionID == sessionID }) { return .alreadySaved }
            let session = DateInterval(start: start, end: end)
            if _otherWorkouts.contains(where: { StrengthOverlap.covers($0, session: session) }) { return .recordedElsewhere }
            _savedWorkouts.append((sessionID, start, end))
            return .saved
        }
    }

    func removeOwnWorkoutsRecordedElsewhere(since: Date) async throws -> Int {
        locked {
            let before = _savedWorkouts.count
            _savedWorkouts.removeAll { saved in
                saved.start >= since && _otherWorkouts.contains {
                    StrengthOverlap.covers($0, session: DateInterval(start: saved.start, end: saved.end))
                }
            }
            return before - _savedWorkouts.count
        }
    }
    func newestRecords(since: Date) async throws -> [SourceFreshness] { freshness.filter { $0.newest >= since } }

    /// Check sync: every source's newest record per type as HealthKit would hand them out (RYFT's own
    /// included: `HealthProbe` drops them), and the types readable at all (`garminLike`).
    var samples: [SourceSample] {
        get { locked { _samples } }
        set { locked { _samples = newValue } }
    }
    var visible: Set<HealthStream> {
        get { locked { _visible } }
        set { locked { _visible = newValue } }
    }
    /// Check sync's reads (`newestSamples`, `visibleTypes`); those on the main thread count in `readsOnMainThread`.
    var probeReads: Int { locked { _probeReads } }
    private var _samples: [SourceSample] = []
    private var _visible: Set<HealthStream> = []
    private var _probeReads = 0

    func newestSamples(of streams: [HealthStream], since: Date) async throws -> [SourceSample] {
        let onMain = MainThread.isCurrent
        return try locked {
            try probe(onMain: onMain)
            return _samples.filter { streams.contains($0.stream) && $0.newest >= since }
        }
    }

    func visibleTypes(_ streams: [HealthStream]) async throws -> Set<HealthStream> {
        let onMain = MainThread.isCurrent
        return try locked {
            try probe(onMain: onMain)
            return _visible.intersection(streams)
        }
    }

    private func probe(onMain: Bool) throws {
        _probeReads += 1
        if onMain { _readsOnMainThread += 1 }
        if let e = _nextError { _nextError = nil; throw e }
    }

    private func read(_ limit: Int, onMain: Bool) throws {
        if onMain { _readsOnMainThread += 1 }
        _limits.append(limit)
        if let e = _nextError { _nextError = nil; throw e }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private static func anchor(_ index: Int) -> Data { Data("\(index)".utf8) }
    private static func index(_ anchor: Data) -> Int? { Int(String(decoding: anchor, as: UTF8.self)) }
}

/// Check sync's reads, off the main actor the way `SyncEngine` runs page reads (design.md §4.1). Only the user
/// starts it, in the foreground: never at launch, in the background or from a BG task.
actor HealthProbe {
    private let health: HealthStore

    init(health: HealthStore) {
        self.health = health
    }

    /// The newest record per type and source since `since`, and the types readable at all. RYFT's own records
    /// are dropped here too, whatever the store returned: they'd pass for an unknown tracker.
    func run(_ streams: [HealthStream], since: Date) async throws -> (samples: [SourceSample], visible: Set<HealthStream>) {
        let signposter = Signposts.sync
        let check = signposter.beginInterval("check", id: signposter.makeSignpostID(), "\(streams.count) types")
        defer { signposter.endInterval("check", check) }
        MainThread.assertOff("Check sync")
        let newest = signposter.beginInterval("check-newest", id: signposter.makeSignpostID())
        let samples = try await health.newestSamples(of: streams, since: since)
        signposter.endInterval("check-newest", newest, "\(samples.count) sources")
        let readable = signposter.beginInterval("check-visible", id: signposter.makeSignpostID())
        let visible = try await health.visibleTypes(streams)
        signposter.endInterval("check-visible", readable, "\(visible.count) visible")
        return (samples.filter { !Self.isRYFT($0.source) }, visible)
    }

    /// A signal arrived that the catalog says the tracker doesn't share: the catalog is out of date. Ids only.
    nonisolated static func logDrift(tracker: String, signals: [TrackerSignal]) {
        guard !signals.isEmpty else { return }
        log.notice("catalog drift: \(tracker, privacy: .private) shares \(signals.map(\.rawValue).joined(separator: ","), privacy: .public)")
    }

    /// Whether a type proves that RYFT may read it (design.md §4.5): no record, no; another source's record, yes. RYFT
    /// can always read what it wrote, so when the first record is RYFT's own, the type's sources decide (asked only
    /// then).
    nonisolated static func readable(firstRecordFrom source: String?,
                                     sources: () async throws -> [String]) async rethrows -> Bool {
        guard let source else { return false }
        if !isRYFT(bundleID: source) { return true }
        return try await sources().contains { !isRYFT(bundleID: $0) }
    }

    /// Whether one source's newest night holds core, deep or REM: from the segment that ends last, back through every
    /// segment that ends within 3 h of the night's start so far. An older night with stages doesn't count.
    nonisolated static func newestNightHasStages(_ segments: [SleepSegment]) -> Bool {
        let latestFirst = segments.sorted { $0.end > $1.end }
        guard var start = latestFirst.first?.start else { return false }
        let staged: Set<SleepStage> = [.core, .deep, .rem]
        var found = false
        for segment in latestFirst {
            guard segment.end >= start.addingTimeInterval(-3 * 3_600) else { break }
            start = min(start, segment.start)
            found = found || staged.contains(segment.stage)
        }
        return found
    }

    private static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "check")

    /// RYFT itself (or one of its extensions), by bundle ID.
    nonisolated static func isRYFT(_ source: SourceRef) -> Bool { isRYFT(bundleID: source.bundleID) }

    nonisolated static func isRYFT(bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased(), let own = Bundle.main.bundleIdentifier?.lowercased() else { return false }
        return id == own || id.hasPrefix(own + ".")
    }
}

/// Whether the caller runs on the main thread, from async code too (`Thread.isMainThread`
/// is unavailable there). For the Debug checks that keep sync work off the main actor.
enum MainThread {
    static var isCurrent: Bool { Thread.isMainThread }

    /// Debug builds stop here when heavy sync work (mapping, encoding) runs on the main thread.
    static func assertOff(_ what: @autoclosure () -> String) {
        #if DEBUG
        if isCurrent { assertionFailure("\(what()) ran on the main thread") }
        #endif
    }
}
