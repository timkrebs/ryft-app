// The platform's activities and manual sleep in memory (API.md → Activities, the draft): demo data, previews
// and tests. `MockPlatformAPI` forwards to it, so its `failure`, `failNext` and `-RyftFault` apply unchanged.
import Foundation

/// Behaves like the platform brief: `PUT` stores by id and answers `scoring_state: "pending"`; once
/// `scoreDelay` has passed on `now`, reads return a canned strain. List and `PUT` answers carry no route or
/// heart-rate samples (API request R16); `GET /v1/activities/{id}` does.
final class MockActivitiesSource: ActivitiesAPI, @unchecked Sendable {
    private struct Stored {
        var activity: SportActivity
        var putAt: Date
    }

    private let lock = NSLock()
    private var storedByID: [UUID: Stored] = [:]
    private var sleeps: [String: ManualSleepPut] = [:]
    /// Built on first use, not at launch: the live graph creates the demo platform whether or not demo data is on.
    private var seed: (@Sendable () -> [SportActivity])?

    /// The platform's clock (tests: the `TestClock`).
    var now: @Sendable () -> Date
    /// Seconds from a `PUT` until reads report a strain (tests: 0; demo: 15).
    var scoreDelay: TimeInterval
    /// A platform that ignores R16 and sends route and samples in lists and `PUT` answers (tests).
    var answersWithTrack = false
    /// Every `PUT` body as the platform received it (the `SportActivityPut` encoding, decoded), oldest first.
    private(set) var puts: [SportActivity] = []
    private(set) var deletes: [UUID] = []
    private(set) var sleepPuts: [String: ManualSleepPut] = [:]

    /// `seed`: activities the platform already holds, scored (`demo`).
    init(now: @escaping @Sendable () -> Date = { .now }, scoreDelay: TimeInterval = 0,
         seed: (@Sendable () -> [SportActivity])? = nil) {
        self.now = now
        self.scoreDelay = scoreDelay
        self.seed = seed
    }

    /// The stored activities; call with the lock held.
    private var stored: [UUID: Stored] {
        get {
            if let make = seed {
                seed = nil
                // A seed the platform is still scoring stays pending (demo's "strain pending" row).
                for a in make() {
                    storedByID[a.id] = Stored(activity: a, putAt: a.scoringState == "pending" ? .distantFuture : .distantPast)
                }
            }
            return storedByID
        }
        set { storedByID = newValue }
    }

    // MARK: ActivitiesAPI

    func putActivity(_ a: SportActivity) async throws -> SportActivity {
        // Only what a real PUT carries reaches the platform.
        let received = try APIClient.jsonDecoder.decode(SportActivity.self,
                                                        from: APIClient.jsonEncoder.encode(SportActivityPut(a)))
        try validate(received)
        var saved = received
        saved.scoringState = "pending"
        let answer = lock.withLock {
            puts.append(received)
            // Kept on an update: what the platform merged it with.
            saved.mergedWith = stored[a.id]?.activity.mergedWith
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

    /// Demo data, one of each row My Day shows from the platform (ui.md §1):
    /// - today's mock tracker run (MockData, "Garmin Connect") was also recorded by RYFT, and the platform merged
    ///   the two (`merged_with`), so My Day shows one row with both sources (R6, scored);
    /// - today before the run, mobility typed in, scored without heart rate (R5);
    /// - today after lunch, yoga typed in, its heart rate still pending (R2);
    /// - yesterday evening, padel typed in, scored from perceived effort;
    /// - two days ago at noon, a ride RYFT recorded, not merged, scored from Apple Health's heart rate.
    /// Times sit beside MockData's workouts, never over them.
    static func demo(on date: Date = .now) -> [SportActivity] {
        var out: [SportActivity] = []
        if let run = mergedRun(on: date) { out.append(run) }
        func at(_ day: Date, _ hour: Int, _ minute: Int) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-0000000a%04d", n)) ?? UUID() }
        let yesterday = DayFormat.shift(date, days: -1)
        let twoDaysAgo = DayFormat.shift(date, days: -2)
        let mobility = at(date, 6, 0)
        out.append(SportActivity(id: id(2), sport: .mobility, origin: .manual, start: mobility,
                                 end: mobility.addingTimeInterval(20 * 60), movingSec: 20 * 60, perceivedEffort: 3,
                                 clientUpdatedAt: mobility.addingTimeInterval(25 * 60), strainSource: .noSource,
                                 scoringState: "scored"))
        let yoga = at(date, 13, 5)
        out.append(SportActivity(id: id(3), sport: .yoga, origin: .manual, start: yoga,
                                 end: yoga.addingTimeInterval(30 * 60), movingSec: 30 * 60, perceivedEffort: 4,
                                 clientUpdatedAt: yoga.addingTimeInterval(35 * 60), scoringState: "pending"))
        let padel = at(yesterday, 19, 30)
        out.append(SportActivity(id: id(4), sport: .padel, origin: .manual, start: padel,
                                 end: padel.addingTimeInterval(90 * 60), movingSec: 90 * 60, perceivedEffort: 7,
                                 clientUpdatedAt: padel.addingTimeInterval(100 * 60), strain: 9.1,
                                 strainSource: .perceivedEffort, scoringState: "scored"))
        let ride = at(twoDaysAgo, 12, 0)
        out.append(SportActivity(id: id(5), sport: .cycling, origin: .recorded, start: ride,
                                 end: ride.addingTimeInterval(65 * 60), movingSec: 61 * 60, distanceM: 24_300,
                                 ascentM: 180, descentM: 176, perceivedEffort: 6,
                                 clientUpdatedAt: ride.addingTimeInterval(70 * 60), strain: 11.2,
                                 strainSource: .heartRate, hrSource: "Apple Health", scoringState: "scored"))
        return out
    }

    /// Today's mock tracker run, also recorded by RYFT, merged by the platform.
    private static func mergedRun(on date: Date) -> SportActivity? {
        guard let workout = MockData.detail(for: date).workouts.first(where: { $0.activity == "running" }) else {
            return nil
        }
        let moving = workout.duration - 4 * 60
        let perKm = moving / 8.42
        // Eight kilometres, then the partial last split of 420 m.
        var splits = (0..<8).map { i in
            ActivitySplit(index: i + 1, distanceM: 1000, durationSec: perKm + Double(i % 3 - 1) * 6,
                          ascentM: Double([6, 11, 4, 9, 14, 3, 7, 5][i]))
        }
        splits.append(ActivitySplit(index: 9, distanceM: 420, durationSec: perKm * 0.42, ascentM: 5))
        return SportActivity(id: UUID(uuidString: "00000000-0000-4000-8000-0000000a0001") ?? UUID(),
                             sport: .running, origin: .recorded, start: workout.start, end: workout.end,
                             movingSec: moving, distanceM: 8_420, ascentM: 64, descentM: 61, perceivedEffort: 6,
                             splits: splits, clientUpdatedAt: workout.end.addingTimeInterval(120),
                             strain: workout.strain, strainSource: .heartRate, hrSource: workout.source,
                             mergedWith: workout.id, scoringState: "scored")
    }
}

// MARK: - My Day (previews)

/// My Day's rows and day contents on mock data, built by the assembler from MockData's day, the demo platform's
/// activities and a few local rows (an upload pending, one failed), so every row state of ui.md §1 has a preview.
@MainActor
enum MockMyDay {
    static var today: Date { Calendar.current.startOfDay(for: .now) }

    /// The demo account's local rows today: an indoor run recorded at 08:30, not uploaded yet (R1), and a
    /// HIIT session typed in at 17:00 whose upload the platform refused (R4).
    static let pendingRunID = UUID(uuidString: "00000000-0000-4000-8000-0000000b0001") ?? UUID()
    static let failedID = UUID(uuidString: "00000000-0000-4000-8000-0000000b0002") ?? UUID()

    static func at(_ hour: Int, _ minute: Int, daysBack: Int = 0) -> Date {
        let day = DayFormat.shift(today, days: -daysBack)
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func local(_ id: UUID, sport: Sport, origin: ActivityOrigin, start: Date, minutes: Double,
                      distanceM: Double? = nil, revision: Int = 1, confirmed: Int = 0) -> LocalActivitySnapshot {
        LocalActivitySnapshot(id: id, account: ActivityStore.demoAccount, sport: sport, origin: origin,
                              phase: LocalActivity.savedPhase, start: start, end: start.addingTimeInterval(minutes * 60),
                              movingSec: minutes * 60, distanceM: distanceM, ascentM: nil, descentM: nil,
                              perceivedEffort: 6, notes: "", recordRoute: false, routeWithheld: false, routeDroppedAt: nil,
                              splits: [], localRevision: revision, confirmedRevision: confirmed, deletedAt: nil,
                              lastAttempt: nil, createdAt: start, updatedAt: start)
    }

    static var failedAttempt: UploadAttempt {
        UploadAttempt(at: at(17, 50), request: .put, status: 422, code: "invalid_activity", requestID: "preview-422",
                      kind: .other)
    }

    /// Today as the assembler builds it; `locals` adds the pending and the failed row.
    static func items(daysBack: Int = 0, locals: Bool = false, sleep: Bool = true, nightGap: Bool = false) -> [MyDayItem] {
        let day = DayFormat.shift(today, days: -daysBack)
        var detail = MockData.detail(for: day)
        if !sleep { detail.sleep = nil }
        let key = DayFormat.string(from: day)
        let server = MockActivitiesSource.demo().filter { DayFormat.string(from: $0.start) == key }
        var input = MyDayInput(day: key, server: .dayDetail(detail, activities: server), nightGap: nightGap)
        if locals {
            input.local = [local(pendingRunID, sport: .indoorRunning, origin: .recorded, start: at(8, 30, daysBack: daysBack),
                                 minutes: 32, distanceM: 5_200),
                           local(failedID, sport: .hiit, origin: .manual, start: at(17, 0, daysBack: daysBack), minutes: 25)]
            input.uploads = [failedID: .failed(failedAttempt)]
        }
        return MyDayAssembler.items(input, catalog: .bundled, now: .now)
    }

    /// One of each row: sleep, merged, scored workout, Train session, pending upload, strain pending, failed,
    /// no heart rate, manual, and the missing night.
    static var gallery: [MyDayItem] {
        var rows = items(locals: true)
        if let session = MockTrain.history.last.map(SessionSummary.init) {
            let input = MyDayInput(day: DayFormat.string(from: session.startedAt),
                                   server: .dayDetail(nil, activities: []), localSessions: [session])
            rows += MyDayAssembler.items(input, catalog: .bundled, now: .now)
        }
        rows += items(daysBack: 1).filter { if case .activity = $0.kind { return true } else { return false } }
        rows += items(sleep: false).filter(\.kind.isMissingSleep)
        return rows
    }

    static func failed(_ item: MyDayItem) -> Bool {
        if case .failed? = item.upload { return true }
        return false
    }

    enum Case {
        /// Today's demo day: the night, mobility, the merged run, the walk, yoga (five rows).
        case populated
        /// Over the cap: the pending and the failed rows too ("Show all 7").
        case full
        /// Early: the night and nothing else.
        case nothing
        /// No night and nothing else.
        case noSleepNothing
        /// No night, some rows.
        case noSleepRows
        case loading, failed
        /// The list from three hours ago, the platform unreachable.
        case stale
        /// Three days ago, nothing at all.
        case pastEmpty
    }

    static func content(_ c: Case) -> MyDayContent {
        let all = items()
        switch c {
        case .populated:
            return MyDayContent(day: today, isToday: true, phase: .ready, items: all)
        case .full:
            return MyDayContent(day: today, isToday: true, phase: .ready, items: items(locals: true),
                                dayStrain: MockData.todayScore.strain)
        case .nothing:
            return MyDayContent(day: today, isToday: true, phase: .ready, items: all.filter(\.kind.isSleep))
        case .noSleepNothing:
            return MyDayContent(day: today, isToday: true, phase: .ready,
                                items: items(sleep: false).filter(\.kind.isMissingSleep))
        case .noSleepRows:
            return MyDayContent(day: today, isToday: true, phase: .ready, items: Array(items(sleep: false).prefix(3)))
        case .loading:
            return MyDayContent(day: today, isToday: true, phase: .loading, items: [])
        case .failed:
            return MyDayContent(day: today, isToday: true, phase: .failed, items: [])
        case .stale:
            return MyDayContent(day: today, isToday: true, phase: .ready, items: all,
                                staleSince: Date.now.addingTimeInterval(-3 * 3_600), offersRetry: true)
        case .pastEmpty:
            let day = DayFormat.shift(today, days: -3)
            let missing = MyDayItem(id: "nosleep.\(DayFormat.string(from: day))",
                                    kind: .missingSleep(day: DayFormat.string(from: day)), symbol: "bed.double",
                                    title: String(localized: "No sleep recorded"), start: day, end: day, duration: 0,
                                    distanceM: nil, strain: .notApplicable, sources: [], upload: nil, editable: false)
            return MyDayContent(day: day, isToday: false, phase: .ready, items: [missing])
        }
    }

    /// The week strip on MockData's scores, `daysBack` selected.
    static func week(daysBack: Int) -> [DateStrip.Day] {
        let scores = Dictionary(MockData.history.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        return DateStrip.week(endingAt: today, selected: DayFormat.shift(today, days: -daysBack)) {
            scores[DayFormat.string(from: $0)]
        }
    }
}
