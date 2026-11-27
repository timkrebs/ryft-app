import Foundation
import Observation

/// One workout (`GET /v1/workouts/{id}`): its strain, zones, stats, heart-rate curve and source (design.md §P5-4). The
/// list's fields show at once; the curve, the zones and TRIMP when the detail arrives.
@MainActor
@Observable
final class WorkoutDetailViewModel {
    let workout: Workout
    let sessionRPE: SessionRPEModel
    private let state: AppState
    private(set) var loaded = false
    /// Why the last load brought no detail; nil after an answer.
    private var loadFailure: SleepLoadFailure?

    init(workout: Workout, state: AppState) {
        self.workout = workout
        self.state = state
        sessionRPE = SessionRPEModel(env: state.env, workoutID: workout.id,
                                     workout: state.cachedWorkoutDetail(workout)?.workout ?? workout, repository: state.repository)
    }

    /// Cached curve and zones (SwiftData), once fetched.
    var detail: WorkoutDetail? { state.cachedWorkoutDetail(workout) }
    var isLoading: Bool { detail == nil && !loaded }
    /// Loaded and still no detail: it couldn't load (outlines and the app's calm sentence with its button, as Strain's
    /// failed day), never "no zones" or "no series". Signed out without demo data, nothing was asked: Sign in.
    var failure: SleepLoadFailure? {
        guard loaded, detail == nil else { return nil }
        return loadFailure ?? SleepLoadFailure(reason: state.hasDataSource ? .unexpected : .signedOut, isDemo: state.isDemo)
    }
    /// Offline (not demo): the status line under the header; the cached detail stays in full ink.
    var isOffline: Bool { !state.isDemo && !state.env.connectivity.isOnline }
    var numeralStyle: DotNumeral.Style { state.env.settings.heroNumerals.style }

    var board: WorkoutBoard { WorkoutBoard(workout: workout, detail: detail, isLoading: isLoading, failure: failure) }

    /// Fetches the curve and zones (none when cached and fresh). Until they arrive the list's fields stand in; a retry
    /// shows the outlines again until it answers.
    func load() async {
        loaded = false
        loadFailure = nil
        do {
            try await state.repository.refreshWorkout(workout.id)
        } catch where error.isCancellation {
            // The page went away: nothing to show.
            return
        } catch {
            loadFailure = SleepLoadFailure(error, isOnline: state.isDemo || state.env.connectivity.isOnline,
                                           isDemo: state.isDemo, at: state.env.clock.now())
        }
        if let detail { sessionRPE.seed(from: detail.workout) }
        loaded = true
    }

    func signIn() async {
        await state.signInAgain()
    }
}

/// What the workout detail shows, as values (§P5-4; §P5-12 test 27).
struct WorkoutBoard: Equatable {
    let workout: Workout
    let detail: WorkoutDetail?
    /// The detail hasn't answered and nothing is cached: the zones tile and the chart are outlines.
    let isLoading: Bool
    /// The detail couldn't load and nothing is cached: the outlines, and this in the zones tile's place.
    var failure: SleepLoadFailure?

    /// No detail (loading or failed): the zones tile and the chart card are outlines.
    var isOutline: Bool { detail == nil && (isLoading || failure != nil) }

    /// "Run".
    var title: String { ActivityStyle.name(for: workout.activity) }

    /// "Wed, Nov 18 · 6:40 AM–7:32 AM".
    func when(locale: Locale) -> String {
        let day = workout.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(locale))
        return "\(day) · \(Fmt.time(workout.start, locale: locale))–\(Fmt.time(workout.end, locale: locale))"
    }

    /// "Wednesday, November 18, 6:40 AM to 7:32 AM".
    func spokenWhen(locale: Locale) -> String {
        let day = workout.start.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(locale))
        let range = String(localized: "\(Fmt.time(workout.start, locale: locale)) to \(Fmt.time(workout.end, locale: locale))",
                           comment: "VoiceOver: a time range.")
        return "\(day), \(range)"
    }

    /// The numeral, its caption ("Strain · of 21 · moderate") and the ruler, for this workout's strain.
    var hero: StrainHero {
        StrainHero(strain: workout.strain, namesStrain: true, missingCaption: StrainHero.named(TodayStrainBand.scaleOnly))
    }

    /// The workout's zone minutes (its TRIMP is a tile, not in the head row).
    var zones: StrainZones { StrainZones(minutes: detail?.zoneMin) }

    /// The detail answered without zones: the short tile and its sentence (never for a detail that didn't load).
    var lacksZones: Bool { detail != nil && zones.minutes == nil }

    /// The detail answered without a curve of two points: the card's sentence.
    var lacksSeries: Bool { detail != nil && plot == nil }

    static var noZonesSentence: String {
        String(localized: "No heart-rate zones for this workout.", comment: "A workout's zones tile without zone data.")
    }

    /// Two columns of neutral tiles: Duration, TRIMP, Average and Max heart rate, Energy, and Distance with one.
    var stats: [WorkoutStat] {
        let minutes = StrainFormat.minutes(workout.duration)
        let duration = StrainFormat.duration(minutes: minutes)
        var out = [
            WorkoutStat(id: "duration", label: String(localized: "Duration"), value: duration.value, unit: duration.unit,
                        spoken: Fmt.spokenDuration(minutes: minutes)),
            WorkoutStat(id: "trimp", label: String(localized: "TRIMP"), value: Fmt.integer(detail?.trimp)),
            WorkoutStat(id: "averageHR",
                        label: String(localized: "Average heart rate", comment: "A workout's tile: the mean heart rate."),
                        value: Fmt.integer(workout.avgHr), unit: workout.avgHr == nil ? nil : StrainFormat.bpmUnit),
            WorkoutStat(id: "maxHR", label: String(localized: "Max heart rate", comment: "A workout's tile: the highest heart rate."),
                        value: Fmt.integer(workout.maxHr), unit: workout.maxHr == nil ? nil : StrainFormat.bpmUnit),
            WorkoutStat(id: "energy", label: String(localized: "Energy", comment: "A workout's tile: the active energy it burned."),
                        value: Fmt.integer(workout.energyKcal), unit: workout.energyKcal == nil ? nil : StrainFormat.kcalUnit),
        ]
        if let meters = workout.distanceM, meters > 0 {
            out.append(WorkoutStat(id: "distance", label: String(localized: "Distance"), value: Fmt.distance(meters: meters)))
        }
        return out
    }

    /// The logged Train session's row (only with `sessionId`): "Logged session", "Load 84.6", a chevron.
    var sessionRow: ActivityListRow.Content? {
        guard workout.sessionId != nil else { return nil }
        let title = String(localized: "Logged session")
        var spoken = [title]
        if let load = workout.muscularLoad { spoken.append(String(localized: "Muscular load \(Fmt.load(load))")) }
        return ActivityListRow.Content(systemImage: "dumbbell", title: title,
                                       meta: workout.muscularLoad.map { StrainRows.loadText($0) }, value: nil,
                                       spoken: spoken.joined(separator: ", "), showsValue: false)
    }

    /// The curve, with two points at least.
    var plot: HeartRatePlot? { detail.flatMap { HeartRatePlot(points: $0.hr, average: workout.avgHr) } }

    /// "avg 148 bpm" at the card's head.
    var averageText: String? { workout.avgHr.map { String(localized: "avg \(Int($0.rounded()))\u{00A0}bpm") } }

    /// "Recorded by Garmin Connect".
    var sourceText: String {
        String(localized: "Recorded by \(workout.source)", comment: "Under a workout's heart-rate chart: the app or device that recorded it.")
    }
}

/// One neutral tile of the workout: "Average heart rate", "148", "bpm".
struct WorkoutStat: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    var unit: String?
    /// VoiceOver's value when the shown one reads badly ("52 minutes" for "52 min"); nil reads value and unit.
    var spoken: String?
}

/// The heart-rate chart's scales (§P5-4 row 6): three y ticks on a round step that cover the curve, gridlines at them, the
/// domain a little past the data; x ticks from the first point every 15 minutes (30, 60 or 120 for a long workout, at most
/// five); the peak.
struct HeartRatePlot: Equatable {
    let points: [HRPoint]
    let average: Double?
    let domain: ClosedRange<Double>
    let yTicks: [Double]
    let xTicks: [Date]
    let peak: HRPoint

    nonisolated static let ySteps: [Double] = [10, 20, 30, 40, 50, 60, 100]
    nonisolated static let xStepsMinutes: [Double] = [15, 30, 60, 120]
    /// The data's margin, of its range (as `ChartStyle.niceScale`).
    nonisolated static let padding = 0.12

    init?(points: [HRPoint], average: Double?) {
        guard points.count > 1, let first = points.first, let last = points.last,
              let peak = points.max(by: { $0.bpm < $1.bpm }) else { return nil }
        self.points = points
        self.average = average
        self.peak = peak
        let values = points.map(\.bpm) + [average].compactMap { $0 }
        let (domain, ticks) = Self.yScale(lo: values.min() ?? 0, hi: values.max() ?? 1)
        self.domain = domain
        yTicks = ticks
        xTicks = Self.xTicks(from: first.t, to: last.t)
    }

    /// Three ticks a round step apart, the lowest the first above the padded floor, the highest at or above the data's top;
    /// the domain from the padded floor to the padded top (or the top tick) plus a little, so the top label has room.
    static func yScale(lo: Double, hi: Double) -> (domain: ClosedRange<Double>, ticks: [Double]) {
        let pad = max((hi - lo) * padding, 1)
        let floor = max(lo - pad, 0)
        for step in ySteps {
            let first = (floor / step).rounded(.up) * step
            let top = first + 2 * step
            if top >= hi {
                let upper = max(hi + pad, top) + step * 0.15
                return (floor...upper, [first, first + step, top])
            }
        }
        return (floor...(hi + pad), [lo, hi])
    }

    /// From the first point (to the minute) every 15 minutes, or the smallest of 30, 60, 120 that gives five ticks at most.
    static func xTicks(from start: Date, to end: Date) -> [Date] {
        let minutes = end.timeIntervalSince(start) / 60
        guard minutes > 0 else { return [start] }
        let step = xStepsMinutes.first { minutes / $0 < 5 } ?? xStepsMinutes[xStepsMinutes.count - 1]
        let origin = (start.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        return stride(from: origin, through: end.timeIntervalSinceReferenceDate, by: step * 60)
            .map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    /// From AX1: every other clock tick ("6:40", "7:10"), so the large labels don't run into each other.
    var largeTextXTicks: [Date] {
        xTicks.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
    }

    /// "peak 159": over the peak's dot, or (from AX1) after the average in the card's head.
    var peakText: String { String(localized: "peak \(Int(peak.bpm.rounded()))") }

    /// "Average 148 beats per minute, peak 159"; "Peak 159 bpm" without an average.
    var spokenValue: String {
        let peak = Int(peak.bpm.rounded())
        guard let average else { return String(localized: "Peak \(peak)\u{00A0}bpm") }
        let format = String(localized: "Average %1$lld beats per minute, peak %2$lld",
                            comment: "VoiceOver value of a workout's heart-rate chart: the mean and the highest heart rate.")
        return String(format: format, Int(average.rounded()), peak)
    }
}
