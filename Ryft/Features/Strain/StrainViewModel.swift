import Foundation
import Observation

/// Strain for the selected day: the week strip, the gauge with its 7-day
/// comparison, movement, zones and the day's activities (workouts merged with
/// logged sessions). "Today" comes from the environment's clock.
@MainActor
@Observable
final class StrainViewModel {
    private let state: AppState
    private let store: TrainStore

    var date: Date
    /// A deep link's Train screen; the view pushes it and clears it.
    var requestedRoute: TrainRoute?
    private(set) var isLoading = false
    private(set) var error: String?

    /// One day of the week strip (`DateStrip`, shared with My Day).
    typealias StripDay = DateStrip.Day

    init(state: AppState, store: TrainStore) {
        self.state = state
        self.store = store
        date = Calendar.current.startOfDay(for: state.env.clock.now())
    }

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: state.env.clock.now()) }

    /// The selected day as cached (SwiftData); `load()` revalidates it.
    var detail: DayDetail? { state.cachedDayDetail(for: date) }

    var isToday: Bool { calendar.isDate(date, inSameDayAs: today) }
    /// Strength training behind `train.enabled`.
    var showsTrain: Bool { state.env.flags.isOn(.trainEnabled) }
    var title: String { Fmt.dayTitle(date, today: today) }
    var hasNoHealthData: Bool { state.hasNoHealthData }

    private var score: DailyScore? { detail?.score ?? state.score(for: date) }
    var strain: Double? { score?.strain }

    /// Against the mean of the seven days before the selected one.
    var strainDelta: MetricDelta? {
        let prior = (1...7).compactMap { state.score(for: DayFormat.shift(date, days: -$0))?.strain }
        return .against(strain, prior: prior)
    }

    var week: [StripDay] {
        DateStrip.week(endingAt: today, selected: date) { state.score(for: $0) }
    }

    /// `DayDetail.strain`, else the score.
    var stepsText: String { Fmt.integer((detail?.strain?.steps ?? score?.steps).map(Double.init)) }
    var activeKcalText: String { Fmt.integer((detail?.strain?.activeKcal ?? score?.activeKcal).map(Double.init)) }
    var zoneMinutes: [Double]? { detail?.strain?.zoneMin.map(Double.init) }
    var trimpText: String? { detail?.strain.map { "TRIMP \($0.trimp)" } }

    /// "Cardio 9.2 · Strength 4.1": the day's strain split in proportion to the
    /// heart-rate TRIMP and the strength sessions' muscular TRIMP (the platform
    /// compresses their sum into one strain, so the split is by load). Nil
    /// without a strength session.
    var strainSplit: (cardio: Double, strength: Double)? {
        guard let strain, let d = detail?.strain, let muscular = d.muscularTrimp, muscular > 0 else { return nil }
        let total = Double(d.trimp + muscular)
        guard total > 0 else { return nil }
        let strength = (strain * Double(muscular) / total * 10).rounded() / 10
        // The two parts add up to the shown strain (one decimal).
        return (((strain - strength) * 10).rounded() / 10, strength)
    }

    var strainSplitText: String? {
        strainSplit.map {
            String(localized: "Cardio \(Fmt.strain($0.cardio)) · Strength \(Fmt.strain($0.strength))")
        }
    }

    /// The list is My Day's rows without the night (`today.myDay`, ADR 0006): RYFT's activities show too.
    var showsMyDayList: Bool { state.env.flags.isOn(.todayMyDay) }

    /// The day's rows as My Day builds them, without the sleep rows (behind `today.myDay`).
    var dayItems: [MyDayItem] {
        MyDayAssembler.items(.cached(day: date, state: state, store: store), catalog: state.env.trackerCatalog,
                             now: state.env.clock.now(), includingSleep: false)
    }

    /// The workout behind one of `dayItems`.
    func workout(_ id: UUID) -> Workout? { detail?.workouts.first { $0.id == id } }

    /// The day's workouts, each merged with its logged session (`session_id`),
    /// then sessions without a workout yet (e.g. still syncing). The list without `today.myDay`.
    var activities: [ActivityItem] {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let local = store.completedSessions(from: start, to: end).map(\.summary)
        let sessions = TrainLibrary.merged(local: local, remote: detail?.strain?.sessions ?? [])
        var linked = Set<UUID>()
        var items: [ActivityItem] = (detail?.workouts ?? []).map { w in
            let s = sessions.first { $0.id == w.sessionId || $0.workoutId == w.id }
            if let s { linked.insert(s.id) }
            return .workout(w, s)
        }
        items += sessions.filter { !linked.contains($0.id) }.map(ActivityItem.session)
        return items.sorted { $0.start < $1.start }
    }

    func select(_ day: Date) {
        date = calendar.startOfDay(for: day)
    }

    private func refreshActivities() async {
        guard showsMyDayList else { return }
        _ = try? await state.repository.refreshActivities(DayFormat.string(from: date))
    }

    /// Revalidates the selected day (no request when it's cached and fresh).
    func load() async {
        error = nil
        guard state.hasDataSource else { return }
        isLoading = detail == nil
        defer { isLoading = false }
        // My Day's list needs the day's activities as well, side by side (cached and fresh: nothing is sent).
        async let activities: Void = refreshActivities()
        do {
            _ = try await state.dayDetail(for: date)
            await activities
        } catch where error.isCancellation {
            // `.task(id:)` restarted (another day, new data): the next load says what's true.
            return
        } catch {
            if detail == nil { self.error = error.localizedDescription }
        }
    }
}

/// One workout: its stats, heart-rate curve and zones (`GET /v1/workouts/{id}`).
@MainActor
@Observable
final class WorkoutDetailViewModel {
    let workout: Workout
    private let state: AppState
    private(set) var loaded = false

    struct Stat: Identifiable, Equatable {
        let title: String
        let value: String
        var id: String { title }
    }

    init(workout: Workout, state: AppState) {
        self.workout = workout
        self.state = state
    }

    var title: String { ActivityStyle.name(for: workout.activity) }
    var icon: String { ActivityStyle.icon(for: workout.activity) }
    /// "Monday, 19 Oct · 06:40–07:32".
    var when: String {
        "\(workout.start.formatted(.dateTime.weekday(.wide).day().month())) · \(Fmt.time(workout.start))–\(Fmt.time(workout.end))"
    }

    var stats: [Stat] {
        var out = [
            Stat(title: String(localized: "Strain"), value: Fmt.strain(workout.strain)),
            Stat(title: String(localized: "Duration"), value: Fmt.duration(seconds: workout.duration)),
            Stat(title: String(localized: "TRIMP"), value: Fmt.integer(detail?.trimp)),
            Stat(title: String(localized: "Avg HR"), value: Fmt.integer(workout.avgHr)),
            Stat(title: String(localized: "Max HR"), value: Fmt.integer(workout.maxHr)),
            Stat(title: String(localized: "Calories"), value: Fmt.integer(workout.energyKcal)),
        ]
        if workout.distanceM != nil {
            out.append(Stat(title: String(localized: "Distance"), value: Fmt.distance(meters: workout.distanceM)))
        }
        return out
    }

    var averageText: String? { workout.avgHr.map { String(localized: "avg \(Int($0.rounded())) bpm") } }
    var durationText: String { Fmt.duration(seconds: workout.duration) }
    var heartRate: [HRPoint]? {
        guard let hr = detail?.hr, hr.count > 1 else { return nil }
        return hr
    }
    /// Cached curve and zones (SwiftData), once fetched.
    var detail: WorkoutDetail? { state.cachedWorkoutDetail(workout) }
    var isLoading: Bool { detail == nil && !loaded }
    var zones: [Double]? {
        guard let z = detail?.zoneMin, z.count == 5 else { return nil }
        return z
    }

    /// Without a detail endpoint answer, the list's fields stand in.
    func load() async {
        _ = await state.workoutDetail(workout)
        loaded = true
    }
}
