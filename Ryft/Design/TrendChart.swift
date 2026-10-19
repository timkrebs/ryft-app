import SwiftUI
import Charts

/// Smooth line with a soft area fill. Optional axes, dashed baseline and
/// interactive scrubbing that shows the value of the touched day.
struct TrendChart: View {
    let points: [TrendPoint]
    /// VoiceOver name of the series, e.g. "Readiness".
    let title: String
    var color: Color = Theme.accent
    var baseline: Double? = nil
    var showsAxes = false
    var interactive = false
    var height: CGFloat = 120
    var valueText: (Double) -> String = Fmt.integer

    @State private var selection: Date?

    private struct Plotted: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private var data: [Plotted] {
        points.compactMap { p in p.value.map { Plotted(date: p.date, value: $0) } }
    }

    private var domain: ClosedRange<Double> {
        var values = data.map(\.value)
        if let baseline { values.append(baseline) }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.25, 1)
        return (lo - pad)...(hi + pad)
    }

    private var selected: Plotted? {
        guard let selection else { return nil }
        return data.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }

    var body: some View {
        Group {
            if data.count < 2 {
                Text("Not enough data yet")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: height)
            } else {
                chart
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilitySummary))
        .accessibilityChartDescriptor(SeriesChartDescriptor(title: title, valueName: title,
                                                            points: data.map { ($0.date, $0.value) },
                                                            valueText: valueText))
    }

    private var chart: some View {
        let domain = domain
        return Chart {
            ForEach(data) { p in
                AreaMark(x: .value("Day", p.date, unit: .day),
                         yStart: .value("Floor", domain.lowerBound),
                         yEnd: .value(title, p.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color.opacity(0.12))
                LineMark(x: .value("Day", p.date, unit: .day), y: .value(title, p.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let baseline {
                RuleMark(y: .value("Baseline", baseline))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("30-day baseline")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textTertiary)
                    }
            }
            if let s = selected {
                RuleMark(x: .value("Day", s.date, unit: .day))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(valueText(s.value))
                                .font(.ryft(.callout))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                            Text(s.date.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                PointMark(x: .value("Day", s.date, unit: .day), y: .value(title, s.value))
                    .foregroundStyle(color)
                    .symbolSize(70)
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis {
            if showsAxes {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .chartYAxis {
            if showsAxes {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(valueText(v)).font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
        }
        .chartXSelection(value: interactive ? $selection : .constant(nil))
        .frame(height: height)
    }

    private var accessibilitySummary: String {
        guard let last = data.last else { return String(localized: "No data") }
        let avg = data.map(\.value).reduce(0, +) / Double(data.count)
        return String(localized: "Latest \(valueText(last.value)), average \(valueText(avg)) over \(data.count) days")
    }
}

#Preview("TrendChart", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 24) {
            TrendChart(points: MockData.trend(.readiness, range: .week).points,
                       title: "Readiness", height: 90)
            let hrv = MockData.trend(.hrv, range: .month)
            TrendChart(points: hrv.points, title: "HRV", baseline: hrv.baseline, showsAxes: true,
                       interactive: true, height: 160)
        }
    }
}
