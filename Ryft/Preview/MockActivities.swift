// The platform's activities and manual sleep in memory (API.md → Activities, the draft): demo data, previews
// and tests. `MockPlatformAPI` forwards to it, so its `failure`, `failNext` and `-RyftFault` apply unchanged.
import Foundation

/// Behaves like the platform brief: `PUT` stores by id and answers `scoring_state: "pending"`; once
/// `scoreDelay` has passed on `now`, reads return a canned strain. List and `PUT` answers carry no route or
/// heart-rate samples (API request R16); `GET /v1/activities/{id}` does. A `PUT` that leaves out `route`,
/// `hr_samples` or `splits` keeps the stored ones; a `null` clears an editable field (R19).
final class MockActivitiesSource: ActivitiesAPI, @unchecked Sendable {
    private struct Stored {
        var activity: SportActivity
        var putAt: Date
    }

    private let lock = NSLock()
    private var storedByID: [UUID: Stored] = [:]
    private var sleeps: [String: ManualSleepPut] = [:]
    /// What the platform holds at the start and after `reset()`, for the clock's day (`demo(on:)`).
    private let initialSeed: (@Sendable (Date) -> [SportActivity])?
    /// Built on first use, not at launch: the live graph creates the demo platform whether or not demo data is on.
    private var seed: (@Sendable (Date) -> [SportActivity])?

    /// The platform's clock (tests: the `TestClock`).
    var now: @Sendable () -> Date
    /// False: a platform before the contract (`ActivitiesAPI.publishesActivities`).
    var publishesActivities = true
    /// Seconds from a `PUT` until reads report a strain (tests: 0; demo: 15).
    var scoreDelay: TimeInterval
    /// A platform that ignores R16 and sends route and samples in lists and `PUT` answers (tests).
    var answersWithTrack = false
    /// Every `PUT` body as the platform received it (the `SportActivityPut` encoding, decoded), oldest first.
    private(set) var puts: [SportActivity] = []
    private(set) var deletes: [UUID] = []
    private(set) var sleepPuts: [String: ManualSleepPut] = [:]

    /// `seed`: what the platform already holds, scored, for the day of `now` (`demo(on:)`). Tests start empty.
    init(now: @escaping @Sendable () -> Date = { .now }, scoreDelay: TimeInterval = 0,
         seed: (@Sendable (Date) -> [SportActivity])? = nil) {
        self.now = now
        self.scoreDelay = scoreDelay
        initialSeed = seed
        self.seed = seed
    }

    /// Demo data's platform (the live graph's demo and previews): `demo(on:)`, scored 15 s after a `PUT`.
    static func demoSource() -> MockActivitiesSource {
        MockActivitiesSource(scoreDelay: 15, seed: { MockActivitiesSource.demo(on: $0) })
    }

    /// Back to the seed: everything put, deleted or added since is gone (another account, demo switched).
    func reset() {
        lock.withLock {
            storedByID = [:]
            sleeps = [:]
            puts = []
            deletes = []
            sleepPuts = [:]
            seed = initialSeed
        }
    }

    /// The stored activities; call with the lock held.
    private var stored: [UUID: Stored] {
        get {
            if let make = seed {
                seed = nil
                for a in make(now()) { storedByID[a.id] = Stored(activity: a, putAt: .distantPast) }
            }
            return storedByID
        }
        set { storedByID = newValue }
    }

    // MARK: ActivitiesAPI

    func putActivity(_ a: SportActivity) async throws -> SportActivity {
        // Only what a real PUT carries reaches the platform.
        let body = try APIClient.jsonEncoder.encode(SportActivityPut(a))
        let received = try APIClient.jsonDecoder.decode(SportActivity.self, from: body)
        let sent = Set(((try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]).keys)
        try validate(received)
        var saved = received
        saved.scoringState = "pending"
        let answer = lock.withLock {
            puts.append(received)
            let previous = stored[a.id]?.activity
            // Kept on an update: what the platform merged it with, and what the body left out (R19).
            saved.mergedWith = previous?.mergedWith
            if !sent.contains("route") { saved.route = previous?.route }
            if !sent.contains("hr_samples") { saved.hrSamples = previous?.hrSamples }
            if !sent.contains("splits") { saved.splits = previous?.splits }
            stored[a.id] = Stored(activity: saved, putAt: now())
            return saved
        }
        return answersWithTrack ? answer : answer.withoutRouteOrHeartRate
    }

    func activities(from: Date, to: Date) async throws -> [SportActivity] {
        lock.withLock {
            stored.values.filter { $0.activity.start >= from && $0.activity.start < to }
                .map { answersWithTrack ? scored($0) : scored($0).withoutRouteOrHeartRate }
                .sorted { $0.start < $1.start }
        }
    }

    func activity(id: UUID) async throws -> SportActivity {
        try lock.withLock {
            guard let entry = stored[id] else { throw APIError.http(404, "not found", requestID: "mock-activity-404") }
            return scored(entry)
        }
    }

    func deleteActivity(id: UUID) async throws {
        try lock.withLock {
            guard stored.removeValue(forKey: id) != nil else {
                throw APIError.http(404, "not found", requestID: "mock-activity-404")
            }
            deletes.append(id)
        }
    }

    func putManualSleep(day: String, _ body: ManualSleepPut) async throws {
        guard body.wake > body.bed, body.wake <= now() else {
            throw APIError.http(422, "invalid sleep", requestID: "mock-sleep-422")
        }
        lock.withLock {
            sleeps[day] = body
            sleepPuts[day] = body
        }
    }

    func deleteManualSleep(day: String) async throws {
        try lock.withLock {
            guard sleeps.removeValue(forKey: day) != nil else {
                throw APIError.http(404, "not found", requestID: "mock-sleep-404")
            }
        }
    }

    /// The manual sleep the platform holds for `day` (tests).
    func manualSleep(day: String) -> ManualSleepPut? { lock.withLock { sleeps[day] } }

    // MARK: rules

    /// The brief's `422`s: end after start, at most 24 h, not in the future, effort 1–10, notes ≤ 500.
    private func validate(_ a: SportActivity) throws {
        let ok = a.end > a.start && a.end.timeIntervalSince(a.start) <= 24 * 3600 && a.end <= now()
            && (a.perceivedEffort.map { (1...10).contains($0) } ?? true) && (a.notes?.count ?? 0) <= 500
        if !ok { throw APIError.http(422, "invalid activity", requestID: "mock-activity-422") }
    }

    /// Scored once `scoreDelay` has passed since its `PUT`: a canned strain per family, from heart rate.
    private func scored(_ entry: Stored) -> SportActivity {
        var a = entry.activity
        guard a.scoringState == "pending", now().timeIntervalSince(entry.putAt) >= scoreDelay else { return a }
        a.scoringState = "scored"
        a.strain = Self.cannedStrain[a.sport.family] ?? 6
        a.strainSource = .heartRate
        a.hrSource = "Apple Health"
        return a
    }

    private static let cannedStrain: [Sport.Family: Double] = [
        .foot: 9.4, .cycle: 8.1, .water: 7.2, .gym: 6.0, .snow: 10.2, .ball: 8.8, .other: 5.5,
    ]

    // MARK: demo

    /// Demo data: today's mock tracker run (MockData, "Garmin Connect") was also recorded by RYFT, and the
    /// platform merged the two (`merged_with`), so My Day shows one row with both sources.
    static func demo(on date: Date = .now) -> [SportActivity] {
        guard let workout = MockData.detail(for: date).workouts.first(where: { $0.activity == "running" }) else {
            return []
        }
        let moving = workout.duration - 4 * 60
        let perKm = moving / 8.42
        // Eight kilometres, then the partial last split of 420 m.
        var splits = (0..<8).map { i in
            ActivitySplit(index: i + 1, distanceM: 1000, durationSec: perKm + Double(i % 3 - 1) * 6,
                          ascentM: Double([6, 11, 4, 9, 14, 3, 7, 5][i]))
        }
        splits.append(ActivitySplit(index: 9, distanceM: 420, durationSec: perKm * 0.42, ascentM: 5))
        let run = SportActivity(id: UUID(uuidString: "00000000-0000-4000-8000-0000000a0001") ?? UUID(),
                                sport: .running, origin: .recorded, start: workout.start, end: workout.end,
                                movingSec: moving, distanceM: 8_420, ascentM: 64, descentM: 61, perceivedEffort: 6,
                                splits: splits, clientUpdatedAt: workout.end.addingTimeInterval(120),
                                strain: workout.strain, strainSource: .heartRate, hrSource: workout.source,
                                mergedWith: workout.id, scoringState: "scored")
        return [run]
    }
}
