// What an Insights trend card shows (docs/work/2026-11-16-nocturne/design.md §P5-5.2, §P5-5.3), as values: the latest value,
// the change against the 7 days before it, the series per day for the line, the 30-day range behind it, the note, and what
// VoiceOver reads. Pure, so the data tests (§P5-12 tests 29, 30) assert it without a view.
import SwiftUI

extension TrendMetric {
    var title: String { spec.title }
    var color: Color { spec.color }
    func format(_ v: Double) -> String { spec.text(v) }

    /// The four cards with the 30-day range behind their line (§P5-5.2): readiness, HRV, time asleep and resting HR. Their
    /// 30-day series is fetched whatever the range.
    var hasBand: Bool { Self.banded.contains(self) }
    static let banded: [TrendMetric] = [.readiness, .hrv, .sleepMin, .rhr]

    /// The platform's personal baseline (HRV, resting HR): the expanded chart draws it as a dashed rule.
    var hasBaseline: Bool { self == .hrv || self == .rhr }

    /// A number of minutes, shown as a clock ("7:48 h").
    var isDuration: Bool { self == .sleepMin || self == .napMin || self == .strengthMin }

    /// The board's three first (readiness, HRV, time asleep), then the other eleven in the API's order (§P5-5.2, D5-19).
    static let boardOrder: [TrendMetric] = [.readiness, .hrv, .sleepMin]
    static var moreOrder: [TrendMetric] { allCases.filter { !boardOrder.contains($0) } }
}

/// A trend card's colours (§P5-5.2's table): the line, the 30-day range behind it, and the change's colour. "The rings are the
/// legend": recovery teal for readiness' change, recovery and HRV (D5-9); sleep violet for the sleep metrics; strain blue for
/// strain and training; ink for the rest. Amber and red mean attention only, so a bad change is `alert` and nothing is drawn
/// in a warning hue.
struct TrendCardStyle: Equatable {
    /// The line, and the range's fill at `bandOpacity`.
    let line: Color
    /// The fill's opacity: 6 % behind an ink line, 12 % behind a coloured one.
    let bandOpacity: Double
    /// A change in the good direction.
    let good: Color

    init(_ metric: TrendMetric) {
        switch metric {
        case .readiness:
            line = Theme.textPrimary
            good = Theme.recovery
        case .hrv, .recovery:
            line = Theme.recovery
            good = Theme.recovery
        case .sleepMin, .sleep, .sleepQuality, .sleepConsistency, .napMin:
            line = Theme.metricSleep
            good = Theme.metricSleep
        case .strain, .strengthMin, .volumeKg:
            line = Theme.metricStrain
            good = Theme.textSecondary
        case .rhr, .steps, .activeKcal:
            line = Theme.textPrimary
            good = Theme.textPrimary
        }
        bandOpacity = line == Theme.textPrimary ? InsightsLayout.inkBandOpacity : InsightsLayout.metricBandOpacity
    }

    /// The change's ink: `good` for the good direction, `alert` for the bad, `textSecondary` when flat or when the metric
    /// has no good direction (strain, naps, active energy).
    func deltaColor(_ delta: MetricDelta, polarity: MetricPolarity) -> Color {
        if delta.isFlat { return Theme.textSecondary }
        switch polarity {
        case .neutral: return Theme.textSecondary
        case .higherIsBetter: return delta.value > 0 ? good : Theme.alert
        case .lowerIsBetter: return delta.value < 0 ? good : Theme.alert
        }
    }
}

/// One trend card's facts for the selected range.
struct TrendCardContent: Identifiable, Equatable {
    let metric: TrendMetric
    var id: TrendMetric { metric }
    let style: TrendCardStyle
    /// The range's days (7, 30, 90).
    let days: Int
    /// One per day of the range, oldest first, `nil` where there is no value: the line breaks there.
    let values: [Double?]
    /// The newest value in the range.
    let latest: Double?
    /// The newest value against the mean of the 7 days before it; `nil` under 3 of them.
    let delta: MetricDelta?
    /// The 30-day min–max behind the line (banded metrics with a 30-day series only).
    let band: ClosedRange<Double>?
    /// Loading with nothing cached: "–", the flat line, no note.
    let isPending: Bool
    /// "Band: 30-day range", "SDNN", "Avg 7:31 h", "Band needs 30 days of data", "No data in this range", "As of Nov 15".
    let note: String?
    /// For the expanded card: the series, its end, the baseline and Avg · Min · Max.
    let points: [TrendPoint]
    let end: Date
    let baseline: Double?
    let avg: Double?
    let min: Double?
    let max: Double?

    var title: String { metric.title }
    var spec: MetricSpec { metric.spec }
    var hasData: Bool { latest != nil }

    /// Fewer than this many values in the 7 days before the newest one: no change is shown.
    static let minimumPriorDays = 3
    /// The window the change compares with.
    static let priorDays = 7

    /// - Parameters:
    ///   - series: the range's series as cached; `nil` when there is none.
    ///   - monthly: the 30-day series behind the range (the same series when the range is 30 D); only banded metrics use it.
    ///   - isLoading: a read is in flight: a missing series is pending, not empty.
    ///   - isStale: the page has a refresh issue: the note gives the data's last day instead.
    ///   - today: the window's last day when the series names none.
    static func make(_ metric: TrendMetric, range: TrendRange, series: TrendSeries?, monthly: TrendSeries?,
                     isLoading: Bool, isStale: Bool = false, today: Date) -> TrendCardContent {
        let end = series?.to.flatMap(DayFormat.date(from:)) ?? today
        let byDay = Dictionary((series?.points ?? []).compactMap { p in p.value.map { (p.day, $0) } },
                               uniquingKeysWith: { _, new in new })
        let values: [Double?] = DayFormat.days(endingAt: end, count: range.days).map { byDay[$0] }
        let valued = (series?.points ?? []).filter { $0.value != nil }.sorted { $0.day < $1.day }
        let latest = valued.last
        let delta = latest.flatMap { last in Self.delta(last, in: valued) }
        let band = metric.hasBand ? Self.band(monthly) : nil
        let isPending = series == nil && isLoading
        return TrendCardContent(
            metric: metric, style: TrendCardStyle(metric), days: range.days, values: values, latest: latest?.value,
            delta: delta, band: band, isPending: isPending,
            note: Self.note(metric, series: series, latest: latest, band: band, isPending: isPending, isStale: isStale),
            points: series?.points ?? [], end: end, baseline: metric.hasBaseline ? series?.baseline : nil,
            avg: series?.avg, min: series?.min, max: series?.max)
    }

    /// `last` against the mean of the values in the 7 days before its day, with at least 3 of them (Strain's rule).
    static func delta(_ last: TrendPoint, in valued: [TrendPoint]) -> MetricDelta? {
        guard let value = last.value else { return nil }
        let from = DayFormat.string(from: DayFormat.shift(last.date, days: -priorDays))
        let prior = valued.filter { $0.day >= from && $0.day < last.day }.compactMap(\.value)
        guard prior.count >= minimumPriorDays else { return nil }
        return .against(value, prior: prior)
    }

    /// The 30-day series' min–max; `nil` without a series or with a flat one.
    static func band(_ monthly: TrendSeries?) -> ClosedRange<Double>? {
        let values = monthly?.points.compactMap(\.value) ?? []
        guard let lo = monthly?.min ?? values.min(), let hi = monthly?.max ?? values.max(), lo < hi else { return nil }
        return lo...hi
    }

    private static func note(_ metric: TrendMetric, series: TrendSeries?, latest: TrendPoint?, band: ClosedRange<Double>?,
                             isPending: Bool, isStale: Bool) -> String? {
        if isPending { return nil }
        guard let latest else { return String(localized: "No data in this range", comment: "A trend card's note: the range has no value.") }
        if isStale {
            let day = series?.to.flatMap(DayFormat.date(from:)) ?? latest.date
            // The key Sleep's planner uses too ("As of %@"): no comment of its own here.
            return String(localized: "As of \(day.formatted(.dateTime.month(.abbreviated).day()))")
        }
        if metric.hasBand, band == nil {
            return String(localized: "Band needs 30 days of data", comment: "A trend card's note: the range behind the line needs a 30-day series.")
        }
        switch metric {
        case .readiness:
            return String(localized: "Band: 30-day range", comment: "The readiness trend card's note: the band behind the line is the last 30 days' range.")
        case .hrv: return String(localized: "SDNN", comment: "The HRV trend card's note: the kind of HRV the number is.")
        default:
            return series?.avg.map { avg in
                String(localized: "Avg \(Self.valueText(metric, avg))", comment: "A trend card's note: the range's average, e.g. \"Avg 7:31 h\".")
            }
        }
    }

    // MARK: value text

    /// The number and its unit as the card sets them: "7:48" "h", "66" "ms", "82" "%", "9,412" none.
    static func valueParts(_ metric: TrendMetric, _ v: Double) -> (number: String, unit: String?) {
        let spec = metric.spec
        if metric.isDuration { return (Fmt.clock(minutes: Int(v.rounded())), "h") }
        if spec.unit.isEmpty { return (spec.number(v), nil) }
        return (spec.number(v), spec.unit)
    }

    /// "7:31 h", "66 ms", "78 %", "12.4".
    static func valueText(_ metric: TrendMetric, _ v: Double) -> String {
        let parts = valueParts(metric, v)
        return parts.unit.map { "\(parts.number) \($0)" } ?? parts.number
    }

    // MARK: VoiceOver

    /// "Readiness over 30 days": the chart's name.
    var chartLabel: String {
        String(localized: "\(title) over \(days) days", comment: "VoiceOver: a trend line's name, e.g. \"Readiness over 30 days\".")
    }

    /// How the chart's sentence ends: "ending above its usual range", "ending at 78", or nothing.
    @MainActor var chartEnding: String? {
        if let ending = TrendLine.ending(values: values, band: band) { return TrendLine.spoken(ending) }
        guard let latest else { return nil }
        return String(localized: "ending at \(spec.text(latest))", comment: "VoiceOver: a trend line without a range ends at this value.")
    }

    /// The card read as one element after its name: the value, the change, the note, the chart's sentence.
    @MainActor var spokenValue: String {
        if isPending { return String(localized: "Loading…") }
        var parts: [String] = []
        parts.append(latest.map(spec.text) ?? String(localized: "No data"))
        if let delta { parts.append(DeltaLabel.spoken(delta, spec: spec, reference: Self.deltaReference)) }
        if let note { parts.append(note) }
        parts.append([chartLabel, chartEnding].compactMap { $0 }.joined(separator: ", "))
        return parts.joined(separator: ". ")
    }

    /// "▲ +7 ms · +12 %" with no line break inside a part: only after "·" may it wrap (no-break spaces elsewhere).
    nonisolated static func keepingUnitsTogether(_ text: String) -> String {
        text.components(separatedBy: " · ").map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · ")
    }

    /// After the change: "vs 7 d".
    static var deltaReference: String { String(localized: "vs 7 d") }
}
