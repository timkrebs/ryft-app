import Foundation
import Observation

enum SleepMode: String, CaseIterable, Identifiable {
    case day, week, month, plan
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return String(localized: "Day")
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        case .plan: return String(localized: "Planner")
        }
    }

    var rangeKind: SleepRangeKind? {
        switch self {
        case .day, .plan: return nil
        case .week: return .week
        case .month: return .month
        }
    }
}

@MainActor
@Observable
final class SleepViewModel {
    private let state: AppState

    /// `-RyftSleepMode week` preselects a mode (screenshots).
    var mode: SleepMode = UserDefaults.standard.string(forKey: "RyftSleepMode")
        .flatMap(SleepMode.init(rawValue:)) ?? .day
    /// The night shown in Day mode, identified by the morning it ended.
    private(set) var date: Date
    private(set) var isLoading = false
    private(set) var error: String?

    /// Sleep → Planner, behind `sleep.planner`.
    let planner: SleepPlannerViewModel

    init(state: AppState) {
        self.state = state
        date = Calendar.current.startOfDay(for: state.env.clock.now())
        planner = SleepPlannerViewModel(state: state)
    }

    /// The picker's modes: the planner only with `sleep.planner`.
    var modes: [SleepMode] {
        state.env.flags.isOn(.sleepPlanner) ? SleepMode.allCases : SleepMode.allCases.filter { $0 != .plan }
    }

    /// A deep link to the planner (or the picker).
    func showPlanner() {
        guard modes.contains(.plan) else { return }
        mode = .plan
    }

    private var today: Date { Calendar.current.startOfDay(for: state.env.clock.now()) }

    var isToday: Bool { Calendar.current.isDate(date, inSameDayAs: today) }

    /// The night as cached (SwiftData); `load()` revalidates it.
    var detail: DayDetail? { state.cachedDayDetail(for: date) }
    var range: SleepRange? { mode.rangeKind.flatMap(state.cachedSleepRange) }
    var sleep: SleepDetail? { detail?.sleep }
    var score: DailyScore? { detail?.score }
    /// The night's scoring state beside its title (`DayMarker`); the cached 90 days when the
    /// detail isn't loaded.
    var marker: DayMarker.Kind? { DayMarker.kind(for: score ?? state.score(for: date)) }
    var hasNoHealthData: Bool { state.hasNoHealthData }

    /// "Last night", "Yesterday", "Mon, 13 Oct"; "Last 7 nights" / "Last 30 nights".
    var subtitle: String {
        switch mode {
        case .day: return isToday ? String(localized: "Last night") : Fmt.dayTitle(date, today: today)
        case .week: return String(localized: "Last 7 nights")
        case .month: return String(localized: "Last 30 nights")
        case .plan: return String(localized: "Tonight")
        }
    }

    var canStepBack: Bool { mode == .day }
    var canStepForward: Bool { mode == .day && !isToday }

    /// A deep link: Day mode on that night (never past today).
    func show(night: Date) {
        mode = .day
        date = min(Calendar.current.startOfDay(for: night), today)
    }

    func step(by days: Int) async {
        let next = DayFormat.shift(date, days: days)
        guard next <= today else { return }
        date = next
        await load()
    }

    /// Revalidates what the mode shows (no request when cached and fresh).
    func load() async {
        error = nil
        guard state.hasDataSource else { return }
        if mode == .plan {
            await planner.load()
            return
        }
        if let kind = mode.rangeKind {
            isLoading = range == nil
            _ = await state.sleepRange(kind)
            isLoading = false
            return
        }
        isLoading = detail == nil
        defer { isLoading = false }
        do {
            _ = try await state.dayDetail(for: date)
        } catch {
            if detail == nil { self.error = error.localizedDescription }
        }
    }
}

/// What the Day section shows about one night, computed once (testable without a view).
struct SleepNightSummary: Equatable {
    let total: String
    let qualityLabel: String
    let quality: String
    let qualityFraction: Double?
    let bedtime: String
    let wake: String
    let timeInBed: String
    let efficiency: String
    let need: String
    let actual: String
    /// "87% of need".
    let actualOfNeed: String?
    let debt: String
    /// More than 45 minutes of debt is worth a warning colour.
    let debtIsHigh: Bool
    let performance: String
    let restorative: String
    /// That day's consistency (7 nights); nil until there are 5.
    let consistency: String?
    /// "Nap · 35m" when there was one that day.
    let nap: String?
    let needBreakdown: SleepNeedBreakdown?

    init(sleep: SleepDetail, score: DailyScore?) {
        let need = score?.sleepNeedMin
        let actual = score?.sleepActualMin ?? sleep.totalMin
        let debt = score?.sleepDebtMin
        total = Fmt.duration(minutes: sleep.totalMin)
        qualityLabel = sleep.resolvedQualityLabel ?? Fmt.placeholder
        quality = Fmt.percent(sleep.quality)
        qualityFraction = sleep.quality.map { Double($0) / 100 }
        bedtime = Fmt.time(sleep.start)
        wake = Fmt.time(sleep.end)
        timeInBed = Fmt.duration(minutes: sleep.timeInBedMin)
        efficiency = Fmt.percent(sleep.efficiencyPercent)
        self.need = Fmt.duration(minutes: need)
        self.actual = Fmt.duration(minutes: actual)
        actualOfNeed = need.flatMap { n in actual.map { a in
            String(localized: "\(Int((Double(a) / Double(max(n, 1)) * 100).rounded()))% of need")
        } }
        self.debt = debt == 0 ? String(localized: "None") : Fmt.duration(minutes: debt)
        debtIsHigh = (debt ?? 0) > 45
        performance = Fmt.percent(score?.sleepPerformance)
        restorative = Fmt.percent(sleep.restorative)
        consistency = score?.sleepConsistency.map(String.init)
        nap = score?.napMin.flatMap { $0 > 0 ? String(localized: "Nap · \(Fmt.duration(minutes: $0))") : nil }
        needBreakdown = sleep.need.map(SleepNeedBreakdown.init)
    }
}

/// Week / Month: the stacked nightly bars, averages and bedtime consistency.
struct SleepRangeSummary {
    struct Bar: Identifiable, Equatable {
        let date: Date
        let stage: String
        let hours: Double
        var id: String { "\(date.timeIntervalSince1970)-\(stage)" }
    }

    /// How regular bedtimes were: < 30 min steady, < 60 fair, else irregular.
    enum Regularity: Equatable { case steady, fair, irregular, unknown }

    static let asleep = String(localized: "Asleep")
    static let stageOrder = [SleepStageKind.deep, .light, .rem]

    let bars: [Bar]
    /// A stage without per-night stages ("Asleep") is in the legend only when it occurs.
    let hasUnstaged: Bool
    let averageSleep: String
    let averageQuality: String
    let nights: String
    let averageHours: Double?
    let window: ChartWindow
    let end: Date
    /// Tallest night, for the y scale.
    let tallestNight: Double
    let regularity: Regularity
    let consistencyHint: String
    /// Time asleep per night, for the header's value and delta.
    let totals: [TrendPoint]
    /// The platform's mean consistency over the nights (0–100).
    let averageConsistency: String
    let bedtimes: [SleepBedtime]
    /// Per night, newest first: date, total, quality, consistency, nap.
    let nightRows: [NightRow]

    struct NightRow: Identifiable, Equatable {
        let day: String
        let title: String
        let total: String
        let quality: String
        let consistency: String?
        let nap: String?
        var id: String { day }
    }

    init(range: SleepRange) {
        bars = range.days.flatMap { night -> [Bar] in
            let staged = Self.stageOrder.compactMap { s -> Bar? in
                let m = night.minutes(for: s)
                return m > 0 ? Bar(date: night.date, stage: s.title, hours: Double(m) / 60) : nil
            }
            if !staged.isEmpty { return staged }
            guard let total = night.totalMin, total > 0 else { return [] }
            return [Bar(date: night.date, stage: Self.asleep, hours: Double(total) / 60)]
        }
        hasUnstaged = bars.contains { $0.stage == Self.asleep }
        averageSleep = Fmt.duration(minutes: range.avgTotalMin)
        averageQuality = Fmt.percent(range.avgQuality)
        nights = "\(range.nights)"
        averageHours = range.avgTotalMin.map { Double($0) / 60 }
        window = range.range == SleepRangeKind.month.rawValue ? .month : .week
        end = range.to.flatMap(DayFormat.date(from:)) ?? range.days.last?.date ?? .now
        tallestNight = Dictionary(grouping: bars, by: \.date).values.map { $0.reduce(0) { $0 + $1.hours } }.max() ?? 0
        // The platform's consistency (bedtime and wake σ), else the local bedtime spread.
        if let c = range.avgConsistency {
            regularity = c >= 80 ? .steady : c >= 60 ? .fair : .irregular
            consistencyHint = Self.hint(consistency: c)
        } else {
            let deviation = SleepMath.bedtimeDeviation(range.days.compactMap(\.start))
            regularity = deviation.map { $0 < 30 ? .steady : $0 < 60 ? .fair : .irregular } ?? .unknown
            consistencyHint = SleepMath.consistencyHint(deviation: deviation)
        }
        totals = range.days.map { TrendPoint(day: $0.day, value: $0.totalMin.map(Double.init)) }
        averageConsistency = range.avgConsistency.map(String.init) ?? Fmt.placeholder
        bedtimes = range.bedtimes
        nightRows = range.days.reversed().map { n in
            NightRow(day: n.day, title: n.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                     total: Fmt.duration(minutes: n.totalMin), quality: n.quality.map(String.init) ?? Fmt.placeholder,
                     consistency: n.consistency.map(String.init),
                     nap: n.napMin.flatMap { $0 > 0 ? Fmt.duration(minutes: $0) : nil })
        }
    }

    /// Bands of the platform's 0–100 consistency: ≥ 80 steady, ≥ 60 fair (the
    /// `sleep-consistency-low` insight fires below 60).
    static func hint(consistency c: Int) -> String {
        switch c {
        case 80...: return String(localized: "Very regular — bedtime and wake time hardly move.")
        case 60...: return String(localized: "Fairly regular. Keeping bed and wake times within half an hour helps recovery.")
        default: return String(localized: "Irregular bed and wake times. A steadier rhythm helps recovery.")
        }
    }
}
