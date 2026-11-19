// What an Insights trend card shows (docs/work/2026-11-16-nocturne/design.md §P5-5.2, §P5-5.3), as values: the latest value,
// the change against the days before it (Today's rule), the series per day for the line, the usual range behind it, the note,
// and what VoiceOver reads. Pure, so the data tests (§P5-12 tests 29, 30) assert it without a view.
import SwiftUI

extension TrendMetric {
    var title: String { spec.title }
    var color: Color { spec.color }
    func format(_ v: Double) -> String { spec.text(v) }

    /// The four cards with the usual range behind their line (§P5-5.2): readiness, HRV, time asleep and resting HR. Their
    /// 30-day series, which the range comes from, is fetched whatever the range.
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

/// A trend card's colours (§P5-5.2's table): the line, the usual range behind it, and the change's colour. "The rings are the
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

    /// The change's ink: `DeltaLabel.color` (`textSecondary` when flat or when the metric has no good direction, `alert` for
    /// the bad direction), except that the good direction takes the card's legend colour, `good`, where DeltaLabel takes the
    /// metric's (readiness' teal is the same; steps and resting HR are ink here).
    @MainActor func deltaColor(_ delta: MetricDelta, spec: MetricSpec) -> Color {
        let shared = DeltaLabel.color(delta, spec: spec)
        return shared == Theme.textSecondary || shared == Theme.alert ? shared : good
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
    /// "vs 7 d" (`MetricDelta.vsSevenDayMean`, Today's rule): the newest value against the mean of the others in the 7 days
    /// that end on its day.
    let delta: MetricDelta?
    /// The usual range behind the line: mean ± 1 SD of the 30-day series before its newest value (banded metrics only).
    let band: ClosedRange<Double>?
    /// This page's read of the series hasn't answered yet and nothing is cached: "–", the flat line, no note.
    let isPending: Bool
    /// The range's series is cached (it may hold no value); `false` with `isPending` false reads "Not loaded".
    let isLoaded: Bool
    /// "Band: your usual range", "SDNN", "Avg 7:31 h", "Band needs 7 days of data", "No data in this range", "Not loaded",
    /// "As of Nov 15".
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

    /// The usual range needs this many values before the newest one in the 30-day series.
    static let minimumBandValues = 7

    /// The usual range behind a banded card's line, or why there is none.
    enum UsualRange: Equatable {
        case range(ClosedRange<Double>)
        /// The 30-day series is loaded, with fewer than 7 values before its newest one: "Band needs 7 days of data".
        case tooShort
        /// No band: the metric has none, or its 30-day series isn't loaded (yet).
        case unavailable

        var band: ClosedRange<Double>? {
            if case .range(let r) = self { return r }
            return nil
        }
    }

    /// - Parameters:
    ///   - series: the range's series as cached; `nil` when there is none.
    ///   - monthly: the 30-day series behind the range (the same series when the range is 30 D); only banded metrics use it.
    ///   - isLoading: this page's read hasn't answered: a missing series is pending, not "Not loaded".
    ///   - isStale: the page has a refresh issue: the note gives the data's last day instead.
    ///   - today: the window's last day when the series names none.
    static func make(_ metric: TrendMetric, range: TrendRange, series: TrendSeries?, monthly: TrendSeries?,
                     isLoading: Bool, isStale: Bool = false, today: Date) -> TrendCardContent {
        let end = series?.to.flatMap(DayFormat.date(from:)) ?? today
        let byDay = Dictionary((series?.points ?? []).compactMap { p in p.value.map { (p.day, $0) } },
                               uniquingKeysWith: { _, new in new })
        let values: [Double?] = DayFormat.days(endingAt: end, count: range.days).map { byDay[$0] }
        let latest = (series?.points ?? []).filter { $0.value != nil }.max { $0.day < $1.day }
        let usual = metric.hasBand ? Self.usualRange(monthly) : .unavailable
        let isPending = series == nil && isLoading
        return TrendCardContent(
            metric: metric, style: TrendCardStyle(metric), days: range.days, values: values, latest: latest?.value,
            delta: .vsSevenDayMean(series?.points ?? []), band: usual.band, isPending: isPending, isLoaded: series != nil,
            note: Self.note(metric, series: series, latest: latest, usual: usual, isPending: isPending, isStale: isStale),
            points: series?.points ?? [], end: end, baseline: metric.hasBaseline ? series?.baseline : nil,
            avg: series?.avg, min: series?.min, max: series?.max)
    }

    /// Mean ± 1 SD (the window's own spread) of the 30-day series' values before its newest one, with at least 7 of them;
    /// the newest value stays out, so it can read above or below its usual range.
    static func usualRange(_ monthly: TrendSeries?) -> UsualRange {
        guard let monthly else { return .unavailable }
        let valued = monthly.points.filter { $0.value != nil }.sorted { $0.day < $1.day }
        let before = valued.dropLast().compactMap(\.value)
        guard before.count >= minimumBandValues else { return .tooShort }
        let mean = before.reduce(0, +) / Double(before.count)
        let sd = (before.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(before.count)).squareRoot()
        return .range((mean - sd)...(mean + sd))
    }

    private static func note(_ metric: TrendMetric, series: TrendSeries?, latest: TrendPoint?, usual: UsualRange,
                             isPending: Bool, isStale: Bool) -> String? {
        if isPending { return nil }
        guard let series else {
            return String(localized: "Not loaded", comment: "A trend card's note: the series couldn't be read (offline, or the read failed) and none is saved.")
        }
        guard let latest else { return String(localized: "No data in this range", comment: "A trend card's note: the range has no value.") }
        if isStale {
            let day = series.to.flatMap(DayFormat.date(from:)) ?? latest.date
            // The key Sleep's planner uses too ("As of %@"): no comment of its own here.
            return String(localized: "As of \(day.formatted(.dateTime.month(.abbreviated).day()))")
        }
        if usual == .tooShort {
            return String(localized: "Usual range needs 7 days of data",
                          comment: "A trend card's note: the usual range behind the line needs 7 days of data before the newest value. The 7 is fixed.")
        }
        switch metric {
        case .readiness where usual.band != nil:
            return String(localized: "Shaded: your usual range", comment: "The readiness trend card's note: the shaded area behind the line is the usual range.")
        case .hrv: return String(localized: "SDNN", comment: "The HRV trend card's note: the kind of HRV the number is.")
        default:
            return series.avg.map { avg in
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

    /// The card read as one element after its name: the value, the change, the note, the chart's sentence. Not loaded: the
    /// note says so, with no "No data" before it.
    @MainActor var spokenValue: String {
        if isPending { return String(localized: "Loading…") }
        var parts: [String] = []
        if let latest { parts.append(spec.text(latest)) } else if isLoaded { parts.append(String(localized: "No data")) }
        if let delta {
            parts.append(DeltaLabel.spoken(delta, spec: spec, reference: Self.deltaReference))
        }
        if let note { parts.append(note) }
        parts.append([chartLabel, chartEnding].compactMap { $0 }.joined(separator: ", "))
        return parts.joined(separator: ". ")
    }

    /// After the change: "vs 7 d" (`DeltaLabel.sevenDayReference`).
    @MainActor static var deltaReference: String { DeltaLabel.sevenDayReference }
}
