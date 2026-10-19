import Foundation
import Observation

enum SleepMode: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return String(localized: "Day")
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        }
    }

    var rangeKind: SleepRangeKind? {
        switch self {
        case .day: return nil
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

    init(state: AppState) {
        self.state = state
        date = Calendar.current.startOfDay(for: state.env.clock.now())
    }

    private var today: Date { Calendar.current.startOfDay(for: state.env.clock.now()) }

    var isToday: Bool { Calendar.current.isDate(date, inSameDayAs: today) }

    /// The night as cached (SwiftData); `load()` revalidates it.
    var detail: DayDetail? { state.cachedDayDetail(for: date) }
    var range: SleepRange? { mode.rangeKind.flatMap(state.cachedSleepRange) }
    var sleep: SleepDetail? { detail?.sleep }
    var score: DailyScore? { detail?.score }
    var hasNoHealthData: Bool { state.hasNoHealthData }

    /// "Last night", "Yesterday", "Mon, 13 Oct"; "Last 7 nights" / "Last 30 nights".
    var subtitle: String {
        switch mode {
        case .day: return isToday ? String(localized: "Last night") : Fmt.dayTitle(date, today: today)
        case .week: return String(localized: "Last 7 nights")
        case .month: return String(localized: "Last 30 nights")
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
        let deviation = SleepMath.bedtimeDeviation(range.days.compactMap(\.start))
        regularity = deviation.map { $0 < 30 ? .steady : $0 < 60 ? .fair : .irregular } ?? .unknown
        consistencyHint = SleepMath.consistencyHint(deviation: deviation)
        totals = range.days.map { TrendPoint(day: $0.day, value: $0.totalMin.map(Double.init)) }
    }
}
