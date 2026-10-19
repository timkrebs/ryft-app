import Charts
import SwiftUI

/// The one chart language every chart adopts. Thin linear lines; axes always
/// visible, with nice bounds and dated ticks; dashed baselines, flat range bands
/// and threshold rules as reference layers; a numeric header; scrubbing with a
/// haptic; a 250 ms fade-in. No glow, no shadow, no gradient, no smoothing.
enum ChartStyle {
    static let line = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
    static let grid = StrokeStyle(lineWidth: 0.5)
    static let baseline = StrokeStyle(lineWidth: 1, dash: [3, 3])
    static let threshold = StrokeStyle(lineWidth: 0.5, dash: [2, 2])
    /// Point markers: today / selected / min / max only.
    static let marker = CGSize(width: 6, height: 6)
    /// The most an area may be filled.
    static let areaOpacity = 0.06
    static let bandOpacity = 0.10
    static let appear = Animation.easeOut(duration: 0.25)

    /// Baselines and bounds: Mist at 40 % in dark, Graphite at 40 % in light.
    static var reference: Color { Theme.textPrimary.opacity(0.4) }
    static var axisFont: Font { .ryft(.axis).monospacedDigit() }

    // MARK: y scale

    struct Scale: Equatable {
        let domain: ClosedRange<Double>
        let ticks: [Double]
    }

    /// Scores keep their fixed scale, with the band thresholds as ticks; anything
    /// else gets nice bounds around the data.
    static func scale(for values: [Double], spec: MetricSpec) -> Scale {
        if let fixed = spec.scale {
            let ticks = spec.thresholds.isEmpty
                ? niceTicks(in: fixed)
                : [fixed.lowerBound] + spec.thresholds + [fixed.upperBound]
            return Scale(domain: fixed, ticks: ticks)
        }
        let u = spec.tickUnit
        let s = niceScale(values.map { $0 / u }, steps: spec.tickSteps)
        return Scale(domain: (s.domain.lowerBound * u)...(s.domain.upperBound * u), ticks: s.ticks.map { $0 * u })
    }

    /// Data ± 12 %, rounded out to the smallest 1/2/2.5/5 × 10ⁿ step that gives at
    /// most five ticks. Non-negative data never gets a negative floor.
    static func niceScale(_ values: [Double], steps allowed: [Double]? = nil) -> Scale {
        guard var lo = values.min(), var hi = values.max() else { return Scale(domain: 0...1, ticks: [0, 1]) }
        let nonNegative = lo >= 0
        if lo == hi {
            let pad = max(abs(lo) * 0.1, 1)
            lo -= pad
            hi += pad
        }
        let pad = (hi - lo) * 0.12
        for step in allowed ?? steps {
            var a = ((lo - pad) / step).rounded(.down) * step
            if nonNegative { a = max(a, 0) }
            let b = ((hi + pad) / step).rounded(.up) * step
            if Int(((b - a) / step).rounded()) + 1 <= 5 {
                return Scale(domain: a...b, ticks: Array(stride(from: a, through: b + step / 2, by: step)))
            }
        }
        return Scale(domain: lo...hi, ticks: [lo, hi])
    }

    /// Whole-hour steps for time axes (no 2.5 h ticks).
    static let hourSteps: [Double] = [1, 2, 3, 4, 6, 12, 24]

    private static let steps: [Double] = (-2...6).flatMap { e in
        [1.0, 2, 2.5, 5].map { $0 * pow(10, Double(e)) }
    }

    /// Even ticks across a fixed scale, at most five (0…100 → 0, 25, 50, 75, 100).
    private static func niceTicks(in r: ClosedRange<Double>) -> [Double] {
        let span = r.upperBound - r.lowerBound
        for step in steps where span / step <= 4 {
            let n = span / step
            if abs(n - n.rounded()) < 0.001 {
                return Array(stride(from: r.lowerBound, through: r.upperBound + step / 2, by: step))
            }
        }
        return [r.lowerBound, r.upperBound]
    }

    // MARK: axes

    /// Dated x ticks, labels in caption2 with monospaced digits. `centered` puts
    /// labels in the middle of day bins (bar charts).
    static func xAxis(_ ticks: [Date], format: Date.FormatStyle, centered: Bool = false) -> some AxisContent {
        AxisMarks(values: ticks) { _ in
            AxisValueLabel(format: format, centered: centered)
                .font(axisFont)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    /// "20", "00", "04": 24-hour clock in every locale, so a night axis reads the same
    /// everywhere (`.hour(.twoDigits(amPM: .omitted))` gives "08" for 20:00 in 12-hour locales).
    static func hourLabel(_ date: Date) -> String {
        String(format: "%02d", Calendar.current.component(.hour, from: date))
    }

    /// Trailing y ticks with 0.5 pt gridlines. The top tick carries the unit
    /// ("80 ms"), so the axis is labelled without a separate title colliding with it.
    static func yAxis(_ ticks: [Double], unit: String = "",
                      label: @escaping (Double) -> String) -> some AxisContent {
        let top = ticks.max()
        return AxisMarks(position: .trailing, values: ticks) { value in
            AxisGridLine(stroke: grid)
                .foregroundStyle(Theme.separator)
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(v == top && !unit.isEmpty ? "\(label(v)) \(unit)" : label(v))
                        .font(axisFont)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}

/// A day window on the x axis: every day for 7 d (weekday initials), weekly for
/// 30 d, monthly for 90 d.
enum ChartWindow: Equatable {
    case week, month, quarter

    init(_ range: TrendRange) {
        switch range {
        case .week: self = .week
        case .month: self = .month
        case .quarter: self = .quarter
        }
    }

    init(days: Int) {
        self = days <= 8 ? .week : days <= 31 ? .month : .quarter
    }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        }
    }

    /// "30 d" in the chart header.
    var title: String {
        switch self {
        case .week: return String(localized: "7 d")
        case .month: return String(localized: "30 d")
        case .quarter: return String(localized: "90 d")
        }
    }

    var format: Date.FormatStyle {
        switch self {
        case .week: return .dateTime.weekday(.narrow)
        case .month: return .dateTime.day().month(.abbreviated)
        case .quarter: return .dateTime.month(.abbreviated)
        }
    }

    private static var calendar: Calendar { .current }

    func start(endingAt end: Date) -> Date {
        DayFormat.shift(Self.calendar.startOfDay(for: end), days: -(days - 1))
    }

    /// The window's days, half a day of air on both sides so end markers aren't clipped.
    func domain(endingAt end: Date) -> ClosedRange<Date> {
        let last = Self.calendar.startOfDay(for: end)
        return start(endingAt: end).addingTimeInterval(-43_200)...last.addingTimeInterval(43_200)
    }

    func ticks(endingAt end: Date) -> [Date] {
        let last = Self.calendar.startOfDay(for: end)
        switch self {
        case .week:
            return (0..<7).reversed().map { DayFormat.shift(last, days: -$0) }
        case .month:
            // Weekly, counted back from the last day so it is always labelled.
            return stride(from: 28, through: 0, by: -7).map { DayFormat.shift(last, days: -$0) }
        case .quarter:
            let first = start(endingAt: end)
            var month = Self.calendar.dateInterval(of: .month, for: first)?.start ?? first
            if month < first { month = Self.calendar.date(byAdding: .month, value: 1, to: month) ?? last }
            var ticks: [Date] = []
            while month <= last {
                ticks.append(month)
                month = Self.calendar.date(byAdding: .month, value: 1, to: month) ?? last.addingTimeInterval(1)
            }
            return ticks
        }
    }
}

// MARK: reference layers

/// Dashed baseline with its label, e.g. "baseline 52 ms". The label sits at the
/// leading end: today's point and its value are always at the trailing one.
struct BaselineRule: ChartContent {
    let value: Double
    let label: String
    var alignment: Alignment = .leading

    var body: some ChartContent {
        RuleMark(y: .value("Baseline", value))
            .foregroundStyle(ChartStyle.reference)
            .lineStyle(ChartStyle.baseline)
            .annotation(position: .top, alignment: alignment, spacing: 1) {
                // Backed with the card surface so it stays legible over bars and lines.
                Text(label)
                    .font(ChartStyle.axisFont)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 3)
                    .background(Theme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
    }
}

/// A personal range (min–max, later ±σ) as a flat 10 % band across the window.
struct RangeBand: ChartContent {
    let x: ClosedRange<Date>
    let y: ClosedRange<Double>
    let color: Color

    var body: some ChartContent {
        RectangleMark(xStart: .value("From", x.lowerBound), xEnd: .value("To", x.upperBound),
                      yStart: .value("Low", y.lowerBound), yEnd: .value("High", y.upperBound))
            .foregroundStyle(color.opacity(ChartStyle.bandOpacity))
    }
}

/// Band thresholds (33 / 67, 10 / 14 / 18) as thin rules. Their labels are the
/// y-axis ticks in the margin.
struct ThresholdRules: ChartContent {
    let values: [Double]

    var body: some ChartContent {
        ForEach(values, id: \.self) { v in
            RuleMark(y: .value("Threshold", v))
                .foregroundStyle(Theme.textTertiary)
                .lineStyle(ChartStyle.threshold)
        }
    }
}

// MARK: readouts

/// The header row every chart carries: name in small caps, current value with
/// its unit, the delta against the 7-day mean, and the window.
struct ChartHeader: View {
    let spec: MetricSpec
    let value: Double?
    var delta: MetricDelta? = nil
    var deltaReference: String? = String(localized: "vs 7 d")
    var window: String? = nil
    /// Replaces the value, e.g. "avg 142 bpm".
    var valueOverride: String? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(spec.title).ryftLabelStyle()
                Spacer(minLength: 8)
                if let window {
                    Text(window)
                        .font(ChartStyle.axisFont)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                MetricValueText(spec: spec, value: value, override: valueOverride)
                DeltaLabel(spec: spec, delta: delta, reference: deltaReference)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "58" in the metric font with "ms" after it, or the custom text ("7h 48m").
struct MetricValueText: View {
    let spec: MetricSpec
    let value: Double?
    var override: String? = nil
    var font: Font = .ryft(.metric)

    var body: some View {
        if let override {
            Text(override).font(font).monospacedDigit().foregroundStyle(Theme.textPrimary)
        } else if let value {
            if spec.custom != nil || spec.unit.isEmpty || spec.unit == "%" {
                Text(spec.text(value)).font(font).monospacedDigit().foregroundStyle(Theme.textPrimary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(spec.number(value)).font(font).monospacedDigit().foregroundStyle(Theme.textPrimary)
                    Text(spec.unit).font(.ryft(.caption)).foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        } else {
            Text(Fmt.placeholder).font(font).foregroundStyle(Theme.textTertiary)
                .accessibilityLabel(Text("No data"))
        }
    }
}

/// The scrub bubble: value, date, delta to the baseline.
struct ScrubReadout: View {
    let value: String
    let date: String
    var delta: String? = nil

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(date)
                .font(ChartStyle.axisFont)
                .foregroundStyle(Theme.textSecondary)
            if let delta {
                Text(delta)
                    .font(ChartStyle.axisFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: motion

/// 250 ms ease-out fade on appear; instant under Reduce Motion.
private struct ChartAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(ChartStyle.appear) { shown = true }
                }
            }
    }
}

extension View {
    func chartAppear() -> some View { modifier(ChartAppear()) }
}
