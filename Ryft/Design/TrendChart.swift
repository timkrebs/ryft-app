import SwiftUI
import Charts

/// A daily series as an instrument (`ChartStyle`): header readout, 1.5 pt linear
/// line broken at missing days, dated axes with nice bounds, threshold rules for
/// scores, dashed baseline, optional personal-range band, markers only at today
/// and the window's min / max, and scrubbing with a haptic per day.
struct TrendChart: View {
    let points: [TrendPoint]
    let spec: MetricSpec
    /// Defaults to the span of the points.
    var window: ChartWindow? = nil
    /// Last day of the window (`TrendSeries.to`); defaults to the newest point.
    var end: Date? = nil
    var baseline: Double? = nil
    /// Personal range, e.g. the 30-day min–max.
    var band: ClosedRange<Double>? = nil
    var showsHeader = true
    var interactive = true
    var height: CGFloat = 150

    @State private var selection: Date?

    private struct Plotted: Identifiable {
        let date: Date
        let value: Double
        /// Consecutive days share a segment; a missing day starts a new one.
        let segment: Int
        var id: Date { date }
    }

    private var data: [Plotted] {
        var out: [Plotted] = []
        var segment = 0
        for p in points {
            guard let v = p.value else { continue }
            let d = p.date
            if let prev = out.last, d.timeIntervalSince(prev.date) > 1.5 * 86_400 { segment += 1 }
            out.append(Plotted(date: d, value: v, segment: segment))
        }
        return out
    }

    private var resolvedWindow: ChartWindow {
        if let window { return window }
        guard let first = points.first?.date, let last = points.last?.date else { return .week }
        return ChartWindow(days: Int(last.timeIntervalSince(first) / 86_400) + 1)
    }

    private var endDate: Date { end ?? data.last?.date ?? .now }

    private func nearest(to date: Date?, in data: [Plotted]) -> Plotted? {
        guard let date else { return nil }
        return data.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    var body: some View {
        let data = data
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                ChartHeader(spec: spec, value: data.last?.value, delta: .vsSevenDayMean(points),
                            window: resolvedWindow.title)
            }
            Group {
                if data.count < 2 {
                    Text("Not enough data yet")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: height)
                } else {
                    chart(data)
                        .chartAppear()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spec.title))
            .accessibilityValue(Text(accessibilitySummary(data)))
            .accessibilityChartDescriptor(SeriesChartDescriptor(title: spec.title, valueName: spec.title,
                                                                points: data.map { ($0.date, $0.value) },
                                                                valueText: spec.text))
        }
    }

    private func chart(_ data: [Plotted]) -> some View {
        let window = resolvedWindow
        let xDomain = window.domain(endingAt: endDate)
        var values = data.map(\.value)
        if let baseline { values.append(baseline) }
        if let band { values += [band.lowerBound, band.upperBound] }
        let scale = ChartStyle.scale(for: values, spec: spec)
        let selected = nearest(to: selection, in: data)
        let last = data.last
        // Min / max markers, unless they are today's point.
        let extremes = data.count < 3 ? [] : [data.min { $0.value < $1.value }, data.max { $0.value < $1.value }]
            .compactMap { $0 }
            .filter { $0.date != last?.date }

        return Chart {
            if let band {
                RangeBand(x: xDomain, y: band, color: spec.color)
            }
            ThresholdRules(values: spec.thresholds)
            if let baseline {
                BaselineRule(value: baseline, label: String(localized: "baseline \(spec.text(baseline))"))
            }
            ForEach(data) { p in
                LineMark(x: .value("Day", p.date), y: .value(spec.title, p.value),
                         series: .value("Segment", p.segment))
                    .interpolationMethod(.linear)
                    .foregroundStyle(spec.color)
                    .lineStyle(ChartStyle.line)
            }
            ForEach(extremes) { p in
                PointMark(x: .value("Day", p.date), y: .value(spec.title, p.value))
                    .symbol {
                        Circle()
                            .strokeBorder(spec.color, lineWidth: 1)
                            .background(Circle().fill(Theme.surface))
                            .frame(width: ChartStyle.marker.width, height: ChartStyle.marker.height)
                    }
            }
            if let s = selected {
                RuleMark(x: .value("Day", s.date))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ScrubReadout(value: spec.text(s.value),
                                     date: s.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                                     delta: scrubDelta(s.value, data: data))
                    }
                PointMark(x: .value("Day", s.date), y: .value(spec.title, s.value))
                    .foregroundStyle(spec.color)
                    .symbolSize(ChartStyle.marker)
            } else if let last {
                PointMark(x: .value("Day", last.date), y: .value(spec.title, last.value))
                    .foregroundStyle(spec.color)
                    .symbolSize(ChartStyle.marker)
                    .annotation(position: .top, spacing: 3) {
                        Text(spec.number(last.value))
                            .font(ChartStyle.axisFont)
                            .foregroundStyle(Theme.textPrimary)
                    }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: scale.domain)
        .chartXAxis { ChartStyle.xAxis(window.ticks(endingAt: endDate), format: window.format) }
        .chartYAxis { ChartStyle.yAxis(scale.ticks, unit: spec.yAxisUnit, label: spec.axis) }
        .chartXSelection(value: interactive ? $selection : .constant(nil))
        .sensoryFeedback(.selection, trigger: selected?.date)
        .frame(height: height)
    }

    /// "+3 ms vs baseline", or against the window's mean without a baseline.
    private func scrubDelta(_ value: Double, data: [Plotted]) -> String {
        let reference = baseline ?? data.map(\.value).reduce(0, +) / Double(max(data.count, 1))
        let d = value - reference
        let signed = "\(d >= 0 ? "+" : "−")\(spec.deltaMagnitude(abs(d)))"
        return baseline != nil ? String(localized: "\(signed) vs baseline") : String(localized: "\(signed) vs average")
    }

    private func accessibilitySummary(_ data: [Plotted]) -> String {
        guard let last = data.last else { return String(localized: "No data") }
        let avg = data.map(\.value).reduce(0, +) / Double(data.count)
        return String(localized: "Latest \(spec.text(last.value)), average \(spec.text(avg)) over \(data.count) days")
    }
}

#Preview("TrendChart", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 28) {
            TrendChart(points: MockData.trend(.readiness, range: .week).points, spec: .readiness,
                       window: .week, height: 110)
            let hrv = MockData.trend(.hrv, range: .month)
            TrendChart(points: hrv.points, spec: .hrv, window: .month, baseline: hrv.baseline,
                       band: hrv.min.flatMap { lo in hrv.max.map { lo...$0 } })
            TrendChart(points: MockData.trend(.strain, range: .quarter).points, spec: .strain, window: .quarter)
        }
    }
}
