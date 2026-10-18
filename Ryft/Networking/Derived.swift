// Client-side fallbacks built from `/v1/days`. Used when the platform doesn't
// serve `/v1/trends`, `/v1/sleep` or `/v1/insights` yet (404) or when offline,
// so every tab stays usable with the day scores alone.
import Foundation

extension TrendMetric {
    /// The value this metric reads from a day score. Sleep is in minutes.
    func value(in s: DailyScore) -> Double? {
        switch self {
        case .readiness: return s.readinessValue.map(Double.init)
        case .recovery: return s.recovery.map(Double.init)
        case .strain: return s.strain
        case .sleep: return s.sleepActualMin.map(Double.init)
        case .hrv: return s.hrvMs
        case .rhr: return s.rhr
        }
    }
}

extension TrendSeries {
    /// Series for the last `range.days` days ending `today`, one point per day
    /// (nil where there's no score). HRV gets a 30-day mean as its baseline.
    static func derived(from history: [DailyScore], metric: TrendMetric, range: TrendRange, today: Date = .now) -> TrendSeries {
        let byDay = Dictionary(history.map { ($0.day, $0) }, uniquingKeysWith: { _, new in new })
        let days = DayFormat.days(endingAt: today, count: range.days)
        let points = days.map { TrendPoint(day: $0, value: byDay[$0].flatMap(metric.value(in:))) }
        let values = points.compactMap(\.value)
        var baseline: Double?
        if metric == .hrv {
            let window = Set(DayFormat.days(endingAt: today, count: 30))
            let hrv = history.filter { window.contains($0.day) }.compactMap(\.hrvMs)
            baseline = hrv.isEmpty ? nil : hrv.reduce(0, +) / Double(hrv.count)
        }
        return TrendSeries(metric: metric.rawValue, range: range.rawValue, points: points,
                           avg: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
                           min: values.min(), max: values.max(), baseline: baseline)
    }
}

extension SleepRange {
    static func derived(from history: [DailyScore], kind: SleepRangeKind, today: Date = .now) -> SleepRange {
        let byDay = Dictionary(history.map { ($0.day, $0) }, uniquingKeysWith: { _, new in new })
        let nights = DayFormat.days(endingAt: today, count: kind.days).map { day -> SleepNight in
            guard let score = byDay[day] else { return SleepNight(day: day, totalMin: nil, stages: [], quality: nil) }
            let detail = SleepDetail(fallbackFrom: score)
            return SleepNight(day: day, totalMin: score.sleepActualMin ?? detail?.totalMin,
                              stages: detail?.stages ?? [], quality: score.sleepPerformance,
                              start: score.sleepStart, end: score.sleepEnd)
        }
        let totals = nights.compactMap(\.totalMin)
        let qualities = nights.compactMap(\.quality)
        return SleepRange(range: kind.rawValue, days: nights,
                          avgTotalMin: totals.isEmpty ? nil : Double(totals.reduce(0, +)) / Double(totals.count),
                          avgQuality: qualities.isEmpty ? nil : Double(qualities.reduce(0, +)) / Double(qualities.count))
    }
}

extension Insight {
    /// A few plain observations computed on-device from the day scores.
    static func derived(from history: [DailyScore]) -> [Insight] {
        guard let today = history.last else { return [] }
        var out: [Insight] = []
        let prior = history.dropLast().suffix(30)

        if today.calibrating {
            out.append(Insight(id: "local-calibrating-\(today.day)", severity: .info,
                               title: String(localized: "Building your baseline"),
                               body: String(localized: "Scores firm up after \(DailyScore.baselineNightsRequired) nights of sleep data. Wear your watch to bed."),
                               metric: "readiness", day: today.day))
        }
        let hrvs = prior.compactMap(\.hrvMs)
        if let hrv = today.hrvMs, hrvs.count >= 7 {
            let base = hrvs.reduce(0, +) / Double(hrvs.count)
            let delta = (hrv - base) / base
            if delta >= 0.10 {
                out.append(Insight(id: "local-hrv-high-\(today.day)", severity: .info,
                                   title: String(localized: "HRV above your baseline"),
                                   body: String(localized: "HRV is \(Int((delta * 100).rounded()))% above your 30-day average — a good day to push."),
                                   metric: "hrv", day: today.day))
            } else if delta <= -0.15 {
                out.append(Insight(id: "local-hrv-low-\(today.day)", severity: .warn,
                                   title: String(localized: "HRV below your baseline"),
                                   body: String(localized: "HRV is \(Int((-delta * 100).rounded()))% under your 30-day average. Keep today light."),
                                   metric: "hrv", day: today.day))
            }
        }
        if let debt = today.sleepDebtMin, debt >= 60 {
            out.append(Insight(id: "local-debt-\(today.day)", severity: .notice,
                               title: String(localized: "Sleep debt building"),
                               body: String(localized: "You're \(Fmt.duration(minutes: debt)) behind your sleep need. An earlier night helps."),
                               metric: "sleep", day: today.day))
        }
        let rhrs = prior.compactMap(\.rhr)
        if let rhr = today.rhr, rhrs.count >= 7 {
            let base = rhrs.reduce(0, +) / Double(rhrs.count)
            if rhr - base >= 4 {
                out.append(Insight(id: "local-rhr-\(today.day)", severity: .notice,
                                   title: String(localized: "Resting heart rate elevated"),
                                   body: String(localized: "Resting HR is \(Int((rhr - base).rounded())) bpm above normal — watch for illness or accumulated fatigue."),
                                   metric: "rhr", day: today.day))
            }
        }
        return out
    }
}
