import SwiftUI

/// Which direction of a metric is the good one. Colours deltas and range status.
enum MetricPolarity {
    case higherIsBetter, lowerIsBetter, neutral
}

/// Everything a chart, gauge, range bar or delta needs to know about one metric:
/// its colour, unit, polarity, scale and band thresholds.
struct MetricSpec {
    let title: String
    /// Unit after the number ("ms", "bpm", "%"). Empty for scores.
    var unit: String = ""
    let color: Color
    var polarity: MetricPolarity = .neutral
    /// Fixed scale for scores, so their band thresholds are always on screen.
    var scale: ClosedRange<Double>? = nil
    /// Band thresholds, drawn as rules on charts and ticks on gauges.
    var thresholds: [Double] = []
    /// Under a gauge's value: "/ 21", "/ 100", "%".
    var scaleLabel: String = ""
    var fractionDigits = 0
    /// Axis ticks are "nice" multiples of this (60 for minutes, so ticks fall on hours).
    var tickUnit: Double = 1
    /// Allowed tick steps (in `tickUnit`s) instead of 1/2/2.5/5 × 10ⁿ, e.g. whole hours.
    var tickSteps: [Double]? = nil
    /// Unit at the top of the y axis; defaults to `unit`.
    var axisUnit: String? = nil
    /// Whole value when number + unit doesn't fit, e.g. "7h 48m".
    var custom: ((Double) -> String)? = nil
    /// Tick labels; default is the number with up to one decimal.
    var axisLabel: ((Double) -> String)? = nil
    /// The band a value falls in, in words, with its colour (scores only).
    var band: ((Double) -> (label: String, color: Color))? = nil

    /// The number alone, localised ("12,4" in German).
    func number(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// Number and unit, e.g. "58 ms", "82%", "7h 48m".
    func text(_ v: Double) -> String {
        if let custom { return custom(v) }
        if unit.isEmpty { return number(v) }
        return unit == "%" ? "\(number(v))%" : "\(number(v)) \(unit)"
    }

    func axis(_ v: Double) -> String {
        axisLabel?(v) ?? v.formatted(.number.precision(.fractionLength(0...1)))
    }

    var yAxisUnit: String { axisUnit ?? unit }

    /// Deltas of raw physiology also show a percentage; scores and percentages
    /// change in points, so they don't.
    var deltaShowsPercent: Bool { scale == nil && unit != "%" }

    /// The value as it would end a delta, e.g. "4 ms", "25m", "6".
    func deltaMagnitude(_ v: Double) -> String {
        if let custom { return custom(v) }
        return unit.isEmpty || unit == "%" ? number(v) : "\(number(v)) \(unit)"
    }
}

extension MetricSpec {
    /// Recovery / readiness bands: ≥ 67 high, 34–66 moderate, < 34 low.
    static func scoreBand(_ v: Double) -> (label: String, color: Color) {
        let score = Int(v.rounded())
        let label: String
        switch score {
        case 67...: label = String(localized: "High")
        case 34...: label = String(localized: "Moderate")
        default: label = String(localized: "Low")
        }
        return (label, Theme.band(forScore: score))
    }

    /// Strain bands at 10 / 14 / 18. Strain isn't good or bad, so one colour.
    static func strainBand(_ v: Double) -> (label: String, color: Color) {
        let label: String
        switch v {
        case 18...: label = String(localized: "All out")
        case 14...: label = String(localized: "High strain")
        case 10...: label = String(localized: "Moderate strain")
        default: label = String(localized: "Light strain")
        }
        return (label, Theme.metricStrain)
    }

    static let readiness = MetricSpec(title: String(localized: "Readiness"), color: Theme.accent,
                                      polarity: .higherIsBetter, scale: 0...100, thresholds: [33, 67],
                                      scaleLabel: "/ 100", band: scoreBand)
    static let recovery = MetricSpec(title: String(localized: "Recovery"), unit: "%", color: Theme.accent,
                                     polarity: .higherIsBetter, scale: 0...100, thresholds: [33, 67],
                                     scaleLabel: "%", band: scoreBand)
    static let strain = MetricSpec(title: String(localized: "Strain"), color: Theme.metricStrain,
                                   scale: 0...21, thresholds: [10, 14, 18], scaleLabel: "/ 21",
                                   fractionDigits: 1, band: strainBand)
    static let sleepPerformance = MetricSpec(title: String(localized: "Sleep performance"), unit: "%",
                                             color: Theme.metricSleep, polarity: .higherIsBetter,
                                             scale: 0...100, scaleLabel: "%")
    static let sleepMin = MetricSpec(title: String(localized: "Time asleep"), color: Theme.metricSleep,
                                     polarity: .higherIsBetter, tickUnit: 60, tickSteps: ChartStyle.hourSteps,
                                     axisUnit: "h",
                                     custom: { Fmt.duration(minutes: Int($0.rounded())) },
                                     axisLabel: { ($0 / 60).formatted(.number.precision(.fractionLength(0...1))) })
    static let hrv = MetricSpec(title: String(localized: "HRV"), unit: "ms", color: Theme.accent,
                                polarity: .higherIsBetter)
    static let rhr = MetricSpec(title: String(localized: "Resting HR"), unit: "bpm", color: Theme.alert,
                                polarity: .lowerIsBetter)
    static let respRate = MetricSpec(title: String(localized: "Respiratory rate"), unit: "rpm",
                                     color: Theme.accentSecondary, fractionDigits: 1)
    /// SpO₂ in Mist; in light mode Mist would vanish, so the secondary ink stands in.
    static let spo2 = MetricSpec(title: String(localized: "Blood oxygen"), unit: "%", color: Theme.textSecondary,
                                 polarity: .higherIsBetter, fractionDigits: 1)
    static let steps = MetricSpec(title: String(localized: "Steps"), color: Theme.accentSecondary,
                                  polarity: .higherIsBetter)
    static let activeKcal = MetricSpec(title: String(localized: "Active energy"), unit: "kcal",
                                       color: Theme.warning)
    /// Sleep quality: good ≥ 80, fair 60–79, poor < 60 (`quality_label`).
    static let sleepQuality = MetricSpec(title: String(localized: "Sleep quality"), color: Theme.metricSleep,
                                         polarity: .higherIsBetter, scale: 0...100, thresholds: [60, 80],
                                         scaleLabel: "/ 100",
                                         band: { v in (SleepQualityLabel(quality: Int(v.rounded())).title, Theme.metricSleep) })
    static let sleepConsistency = MetricSpec(title: String(localized: "Sleep consistency"), color: Theme.metricSleep,
                                             polarity: .higherIsBetter, scale: 0...100, thresholds: [60],
                                             scaleLabel: "/ 100")
    static let napMin = MetricSpec(title: String(localized: "Naps"), color: Theme.metricSleep,
                                   tickUnit: 15, custom: { Fmt.duration(minutes: Int($0.rounded())) })
    static let strengthMin = MetricSpec(title: String(localized: "Strength training"), color: Theme.metricStrain,
                                        tickUnit: 15, custom: { Fmt.duration(minutes: Int($0.rounded())) })
    static let volumeKg = MetricSpec(title: String(localized: "Training volume"), unit: "kg",
                                     color: Theme.metricStrain)
    static let e1rm = MetricSpec(title: String(localized: "Estimated 1RM"), unit: "kg", color: Theme.accent,
                                 polarity: .higherIsBetter, fractionDigits: 1,
                                 custom: { Fmt.kg($0) })
    static let heartRate = MetricSpec(title: String(localized: "Heart rate"), unit: "bpm", color: Theme.alert)
}

extension TrendMetric {
    var spec: MetricSpec {
        switch self {
        case .readiness: return .readiness
        case .recovery: return .recovery
        case .strain: return .strain
        case .sleep: return .sleepPerformance
        case .sleepMin: return .sleepMin
        case .hrv: return .hrv
        case .rhr: return .rhr
        case .steps: return .steps
        case .activeKcal: return .activeKcal
        case .strengthMin: return .strengthMin
        case .volumeKg: return .volumeKg
        case .sleepQuality: return .sleepQuality
        case .sleepConsistency: return .sleepConsistency
        case .napMin: return .napMin
        }
    }
}

/// A change against a reference (the 7-day mean, a baseline).
struct MetricDelta: Equatable {
    let value: Double
    /// Relative change in percent; nil when the reference is 0.
    let percent: Double?

    init(current: Double, reference: Double) {
        value = current - reference
        percent = reference == 0 ? nil : (current - reference) / abs(reference) * 100
    }

    /// Under 2 % (or exactly 0 without a reference) reads as no change.
    var isFlat: Bool {
        if let percent { return abs(percent) < 2 }
        return value == 0
    }

    /// The newest point against the mean of the seven days before it.
    static func vsSevenDayMean(_ points: [TrendPoint]) -> MetricDelta? {
        let valued = points.compactMap { p in p.value.map { (date: p.date, value: $0) } }
        guard let last = valued.last else { return nil }
        let from = DayFormat.shift(last.date, days: -7)
        let prior = valued.filter { $0.date >= from && $0.date < last.date }.map(\.value)
        guard !prior.isEmpty else { return nil }
        return MetricDelta(current: last.value, reference: prior.reduce(0, +) / Double(prior.count))
    }

    /// `current` against the mean of `prior`; nil when either is missing.
    static func against(_ current: Double?, prior: [Double]) -> MetricDelta? {
        guard let current, !prior.isEmpty else { return nil }
        return MetricDelta(current: current, reference: prior.reduce(0, +) / Double(prior.count))
    }
}
