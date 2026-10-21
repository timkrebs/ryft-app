import Foundation
import HealthKit

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
    let source: String

    /// The source that recorded the most sleep: its asleep stages summed, from its first
    /// segment (in bed included) to its last. `nil` without any sleep.
    static func from(_ segments: [SleepSegment]) -> RawNight? {
        let asleep: Set<SleepStage> = [.asleep, .core, .deep, .rem]
        let nights = Dictionary(grouping: segments, by: \.source).compactMap { source, list -> RawNight? in
            let minutes = list.filter { asleep.contains($0.stage) }
                .reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) } / 60
            guard minutes >= 1, let bed = list.map(\.start).min(), let wake = list.map(\.end).max() else { return nil }
            return RawNight(asleepMin: Int(minutes.rounded()), bedtime: bed, wake: wake, source: source)
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
    /// As HealthKit names it ("Garmin Connect", "Tim's Apple Watch").
    let source: String
    /// `com.apple.health.…` for an Apple device; the writing app's otherwise.
    let bundleID: String?
    let newest: Date

    /// An app that syncs to Apple Health only while it runs, unlike Apple's own devices.
    var isApp: Bool { !(bundleID ?? "").hasPrefix("com.apple.health") }
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
    /// The newest heart-rate record per source since `since` (sleep when no source wrote
    /// heart rate): iPhones write no heart rate, so these are the watches and their apps.
    func newestRecords(since: Date) async throws -> [SourceFreshness]
    /// Asks to write workouts (and nothing else) to Apple Health; `true` when allowed.
    func requestWorkoutWriteAccess() async throws -> Bool
    /// Whether RYFT may write workouts (iOS says so for writing, never for reading).
    var canWriteWorkouts: Bool { get }
    /// A strength workout RYFT logged, as an `HKWorkout`: start, end, brand "RYFT" and the
    /// session's id as its external UUID. No heart-rate samples: the watch records those.
    func saveStrengthWorkout(sessionID: UUID, start: Date, end: Date) async throws
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
            Self.sleepStage(s.value).map { SleepSegment(start: s.startDate, end: s.endDate, stage: $0, source: Self.sourceName(s)) }
        })
    }

    func newestRecords(since: Date) async throws -> [SourceFreshness] {
        let heartRate = try await newestRecords(of: HKQuantityType(.heartRate), since: since)
        return heartRate.isEmpty ? try await newestRecords(of: sleepType, since: since) : heartRate
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
                newest.append(SourceFreshness(source: source.name, bundleID: source.bundleIdentifier, newest: latest.endDate))
            }
        }
        return newest
    }

    func requestWorkoutWriteAccess() async throws -> Bool {
        try await store.requestAuthorization(toShare: [workoutType], read: [])
        return canWriteWorkouts
    }

    var canWriteWorkouts: Bool { store.authorizationStatus(for: workoutType) == .sharingAuthorized }

    func saveStrengthWorkout(sessionID: UUID, start: Date, end: Date) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "RYFT",
                                       HKMetadataKeyExternalUUID: sessionID.uuidString])
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
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

    /// Workout writing: what iOS answers, and what was written.
    var allowsWorkoutWrites = true
    private(set) var writeRequests = 0
    private(set) var savedWorkouts: [(sessionID: UUID, start: Date, end: Date)] = []
    var canWriteWorkouts: Bool { writeRequests > 0 && allowsWorkoutWrites }

    func requestWorkoutWriteAccess() async throws -> Bool {
        writeRequests += 1
        return allowsWorkoutWrites
    }

    func saveStrengthWorkout(sessionID: UUID, start: Date, end: Date) async throws {
        savedWorkouts.append((sessionID, start, end))
    }
    func newestRecords(since: Date) async throws -> [SourceFreshness] { freshness.filter { $0.newest >= since } }

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
