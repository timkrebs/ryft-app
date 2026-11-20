import Foundation
import Testing
@testable import Ryft

// T5.2 review: Strain's loads that overlap (S1), its pending day (S2), a deep link older than the strip (deviation 3), and
// the workout detail that couldn't load (S3); the demo workout's curve reaching its max heart rate (N3).

/// `AppEnvironment.test()`'s clock: the day the view models see as today.
private let testNow = TestClock().now()

/// The day's detail answers, scripted per day and in turn: each may wait on its hold, then answer or fail (404, which the
/// read pipeline doesn't retry). Everything else comes from the demo source.
private final class ScriptedDays: RyftDataSource {
    enum Answer {
        case detail(strain: Double)
        case failure
    }

    struct Step {
        var hold: RequestHold?
        var answer: Answer
    }

    private let lock = NSLock()
    private var steps: [String: [Step]] = [:]

    func script(_ day: Date, _ list: [Step]) {
        lock.withLock { steps[DayFormat.string(from: day)] = list }
    }

    func day(_ date: Date) async throws -> DayDetail {
        let key = DayFormat.string(from: date)
        let step = lock.withLock { () -> Step? in
            guard var list = steps[key], !list.isEmpty else { return nil }
            let first = list.removeFirst()
            steps[key] = list
            return first
        }
        await step?.hold?.wait()
        switch step?.answer ?? .failure {
        case .failure:
            throw APIError.http(404, "not found")
        case .detail(let strain):
            var detail = MockData.todayDetail
            detail.score = DailyScore(day: key, strain: strain)
            detail.workouts = []
            return detail
        }
    }

    func days(from: Date, to: Date) async throws -> [DailyScore] { [] }
    func me() async throws -> User { try await MockDataSource.shared.me() }
    func patchMe(_ p: UserPatch) async throws -> User { try await MockDataSource.shared.patchMe(p) }
    func sleep(range: SleepRangeKind) async throws -> SleepRange { try await MockDataSource.shared.sleep(range: range) }
    func workouts(from: Date, to: Date) async throws -> [Workout] { [] }
    func workout(id: UUID) async throws -> WorkoutDetail { try await MockDataSource.shared.workout(id: id) }
    func trends(metric: TrendMetric, range: TrendRange) async throws -> TrendSeries {
        try await MockDataSource.shared.trends(metric: metric, range: range)
    }
    func insights() async throws -> [Insight] { [] }
    func recompute(from: Date, to: Date) async throws {}
    func deleteMe() async throws -> AccountDeleted { try await MockDataSource.shared.deleteMe() }
}

/// Lets the main actor run until `condition` holds (a few thousand turns at most; no clock time passes).
@MainActor
private func yield(until condition: () -> Bool) async {
    var turns = 0
    while !condition(), turns < 5_000 {
        await Task.yield()
        turns += 1
    }
}

@Suite("Strain: overlapping day loads (T5.2 review S1)")
@MainActor
struct StrainOverlappingLoadTests {
    /// A failed, then B, then back to A: B's late failure neither ends A's reload nor shows on A, and A says nothing
    /// final ("No strain recorded…") until its own answer is in.
    @Test func anOlderDaysLateAnswerChangesNothing() async throws {
        let a = Calendar.current.startOfDay(for: testNow)
        let b = DayFormat.shift(a, days: -1)
        let holdA = RequestHold()
        let holdB = RequestHold()
        let source = ScriptedDays()
        source.script(a, [.init(answer: .failure), .init(hold: holdA, answer: .detail(strain: 12.4))])
        source.script(b, [.init(hold: holdB, answer: .failure)])
        let state = AppState(env: .test(api: MockPlatformAPI(screens: source)))
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))

        await vm.load()
        #expect(vm.board.failure != nil, "A couldn't load")

        vm.step(to: b)
        let loadB = Task { await vm.load() }
        await yield { holdB.waiting == 1 }
        #expect(holdB.waiting == 1)
        vm.step(to: a)
        let loadA = Task { await vm.load() }
        await yield { holdA.waiting == 1 }
        #expect(holdA.waiting == 1)
        #expect(vm.board.failure == nil, "A's old failure is gone while it reloads")

        holdB.release()
        await loadB.value
        #expect(vm.date == a)
        #expect(vm.isLoading, "B's end doesn't end A's load")
        #expect(vm.board.look == .loading)
        #expect(vm.board.failure == nil, "B's failure isn't A's")
        #expect(vm.board.hero.caption.isEmpty, "no absence sentence while A loads")

        holdA.release()
        await loadA.value
        #expect(!vm.isLoading)
        #expect(vm.board.look == .loaded)
        #expect(vm.board.hero.numeral == Fmt.strain(12.4))
    }
}

@Suite("Strain: a day being scored (T5.2 review S2)")
@MainActor
struct StrainPendingDayTests {
    /// API.md's placeholder (`GET /v1/days/{day}` before the day is scored), decoded as the client does.
    private func placeholder(_ date: Date, scoringState: String = "pending") throws -> DayDetail {
        let day = DayFormat.string(from: date)
        let json = #"{"score":{"day":"\#(day)","state":"calibrating","baseline_days":0,"calibrating":false,"#
            + #""computed_at":"0001-01-01T00:00:00Z","scoring_state":"\#(scoringState)","coverage":null},"#
            + #""sleep":null,"strain":null,"workouts":[]}"#
        return try APIClient.jsonDecoder.decode(DayDetail.self, from: Data(json.utf8))
    }

    private func model(seeding details: [DayDetail]) -> StrainViewModel {
        let state = AppState(env: .test())
        for detail in details { state.repository.seed(.detail(detail)) }
        return StrainViewModel(state: state, store: TrainStore(inMemory: true))
    }

    @Test func todayPendingSaysItIsScoringNotThatNothingIsThere() throws {
        let vm = model(seeding: [try placeholder(testNow)])
        #expect(vm.scoringState == .pending)
        let board = vm.board
        #expect(board.scoring == .pending)
        #expect(board.look == .loaded)
        #expect(board.hero.numeral == nil)
        #expect(board.hero.caption == String(localized: "Scoring your latest data"))
        #expect(!board.lacksZones, "the rows with \"–\"")
        #expect(board.zonesMissing.isPending)
    }

    @Test func anEarlierPendingDayToo() throws {
        let day = DayFormat.shift(Calendar.current.startOfDay(for: testNow), days: -2)
        let vm = model(seeding: [try placeholder(day)])
        vm.step(to: day)
        #expect(vm.board.scoring == .pending)
        #expect(vm.board.hero.caption != StrainBoard.noStrainSentence)
        #expect(!vm.board.lacksZones)
    }

    @Test func todayScoredWithoutStrainIsNotFinal() throws {
        let vm = model(seeding: [try placeholder(testNow, scoringState: "scored")])
        #expect(vm.board.scoring == .today)
        #expect(vm.board.hero.caption == StrainBoard.noStrainTodaySentence)
        #expect(vm.board.zonesMissing == .sentence(StrainBoard.noZonesTodaySentence))
    }

    @Test func anEarlierScoredDayIsFinal() throws {
        let day = DayFormat.shift(Calendar.current.startOfDay(for: testNow), days: -3)
        let vm = model(seeding: [try placeholder(day, scoringState: "scored")])
        vm.step(to: day)
        #expect(vm.board.scoring == .final)
        #expect(vm.board.hero.caption == StrainBoard.noStrainSentence)
        #expect(vm.board.zonesMissing == .sentence(StrainBoard.noZonesSentence))
    }
}

@Suite("Workout detail: couldn't load (T5.2 review S3)")
@MainActor
struct WorkoutDetailLoadTests {
    @Test func aFailedLoadIsCouldntLoadThenTryAgainLoadsIt() async throws {
        let api = MockPlatformAPI()
        api.failure = APIError.transport(URLError(.timedOut))
        let state = AppState(env: .test(api: api))
        let workout = MockData.todayDetail.workouts[0]
        let vm = WorkoutDetailViewModel(workout: workout, state: state)
        #expect(vm.board.isOutline && vm.failure == nil, "loading: outlines, nothing said yet")

        await vm.load()

        let failure = try #require(vm.board.failure)
        #expect(failure.message == RefreshIssue.Reason.unreachable.message)
        #expect(failure.action == .retry)
        #expect(vm.board.isOutline)
        #expect(!vm.board.lacksZones, "not \"no zones\"")
        #expect(!vm.board.lacksSeries, "not \"no series\"")

        api.failure = nil
        await vm.load()

        #expect(vm.board.failure == nil)
        #expect(!vm.board.isOutline)
        #expect(vm.board.zones.minutes != nil)
        #expect(vm.board.plot != nil)
    }
}

@Suite("Strain: a deep link older than the strip (T5.2 review, deviation 3)")
@MainActor
struct StrainOlderDayLinkTests {
    @Test func tenDaysAgoOpensThatDayWithNoCellSelected() async {
        let state = AppState(env: .test(auth: .preview(signedIn: true)))
        let strain = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        let router = DeepLinkRouter(state: state, sleep: SleepViewModel(state: state), strain: strain,
                                    insights: InsightsViewModel(state: state))
        state.selectedTab = .profile
        let today = Calendar.current.startOfDay(for: state.env.clock.now())
        let old = DayFormat.shift(today, days: -10)

        await router.open(.day(old))

        #expect(state.selectedTab == .strain)
        #expect(strain.date == old)
        #expect(!strain.week.contains { $0.isSelected }, "no strip cell selected")
        #expect(strain.dateLine == StrainPageContent.dateLine(old, today: today))
        #expect(strain.dateLine != nil)
        #expect(strain.takeStepAnnouncement()?.hasPrefix(Fmt.dayTitle(old, today: today)) == true, "the day is announced")
    }
}

@Suite("Demo workouts (T5.2 review N3)")
struct DemoWorkoutCurveTests {
    @Test func theCurvePeaksAtTheWorkoutsMaxHeartRate() throws {
        let workouts = MockData.allWorkouts.filter { $0.maxHr != nil }
        #expect(!workouts.isEmpty)
        for w in workouts {
            let peak = try #require(MockData.workoutDetail(w).hr.map(\.bpm).max())
            #expect(peak == w.maxHr?.rounded(), "\(w.activity) \(w.start)")
        }
    }
}
