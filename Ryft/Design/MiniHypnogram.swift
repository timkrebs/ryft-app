import Charts
import SwiftUI

/// Last night at a glance: a 20:00–12:00 axis, the stages as steps
/// (Awake on top, Deep at the bottom), the in-bed bounds and time asleep.
/// Tappable when `action` is set (Today → Sleep tab).
struct MiniHypnogram: View {
    let sleep: SleepDetail
    var height: CGFloat = 84
    var action: (() -> Void)? = nil

    private static let rows: [SleepStageKind] = [.awake, .rem, .light, .deep]

    private func row(_ s: SleepIntervalStage) -> SleepStageKind {
        switch s {
        case .deep: return .deep
        case .light, .asleep: return .light
        case .rem: return .rem
        case .awake: return .awake
        }
    }

    /// Deep = 0 at the bottom.
    private func level(_ s: SleepIntervalStage) -> Double {
        Double(Self.rows.count - 1 - (Self.rows.firstIndex(of: row(s)) ?? 0))
    }

    private func color(_ s: SleepIntervalStage) -> Color {
        s == .asleep ? Theme.accentSecondary : Theme.color(for: row(s))
    }

    private var segments: [SleepInterval] { sleep.segments.sorted { $0.start < $1.start } }

    /// 20:00 the evening before the wake day to 12:00 on it, widened if the night is longer.
    private var domain: ClosedRange<Date> {
        let cal = Calendar.current
        let wake = sleep.end ?? segments.last?.end ?? .now
        let day = cal.startOfDay(for: wake)
        let from = cal.date(byAdding: .hour, value: -4, to: day) ?? day
        let to = cal.date(byAdding: .hour, value: 12, to: day) ?? wake
        // 40 minutes of air after 12:00 so its label isn't clipped.
        return min(from, sleep.start ?? from)...max(to, wake).addingTimeInterval(2_400)
    }

    private var ticks: [Date] {
        stride(from: 0, through: 16, by: 4).compactMap {
            Calendar.current.date(byAdding: .hour, value: $0, to: domain.lowerBound)
        }
    }

    var body: some View {
        if let action {
            Button(action: action) { content(showsChevron: true) }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(Text("Opens Sleep"))
        } else {
            content(showsChevron: false)
        }
    }

    private func content(showsChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Sleep").ryftLabelStyle()
                Spacer(minLength: 4)
                Text("\(Fmt.duration(minutes: sleep.totalMin)) asleep")
                    .font(.ryft(.callout))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            chart
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last night"))
        .accessibilityValue(Text(spoken))
    }

    private var chart: some View {
        let segments = segments
        return Chart {
            if let start = sleep.start, let end = sleep.end {
                RectangleMark(xStart: .value("In bed", start), xEnd: .value("Out of bed", end),
                              yStart: .value("Row", -0.5), yEnd: .value("Row", 3.5))
                    .foregroundStyle(Theme.textPrimary.opacity(0.04))
                RuleMark(x: .value("In bed", start))
                    .foregroundStyle(ChartStyle.reference)
                    .lineStyle(ChartStyle.baseline)
                RuleMark(x: .value("Out of bed", end))
                    .foregroundStyle(ChartStyle.reference)
                    .lineStyle(ChartStyle.baseline)
            }
            // The step line: each segment's start and end at its level, joined vertically.
            ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                LineMark(x: .value("Time", seg.start), y: .value("Stage", level(seg.stage)),
                         series: .value("Night", "steps"))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .interpolationMethod(.linear)
                LineMark(x: .value("Time", seg.end), y: .value("Stage", level(seg.stage)),
                         series: .value("Night", "steps"))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .interpolationMethod(.linear)
            }
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                let y = level(seg.stage)
                RectangleMark(xStart: .value("Start", seg.start), xEnd: .value("End", seg.end),
                              yStart: .value("Row", y - 0.22), yEnd: .value("Row", y + 0.22))
                    .foregroundStyle(color(seg.stage))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: -0.5...3.5)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine(stroke: ChartStyle.grid).foregroundStyle(Theme.separator)
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(ChartStyle.hourLabel(d))
                            .font(ChartStyle.axisFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 1, 2, 3]) { value in
                AxisValueLabel {
                    if let i = value.as(Double.self) {
                        Text(Self.rows[Self.rows.count - 1 - Int(i)].title)
                            .font(ChartStyle.axisFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .frame(height: height)
        .chartAppear()
    }

    private var spoken: String {
        var parts = [String(localized: "\(Fmt.duration(minutes: sleep.totalMin)) asleep")]
        if let start = sleep.start, let end = sleep.end {
            parts.append(String(localized: "in bed \(Fmt.time(start)) to \(Fmt.time(end))"))
        }
        parts += sleep.displayStages.filter { $0.min > 0 }.map { "\($0.stage.title) \(Fmt.duration(minutes: $0.min))" }
        return parts.joined(separator: ", ")
    }
}

#Preview("MiniHypnogram", traits: .sizeThatFitsLayout) {
    SchemePair {
        if let sleep = MockData.todayDetail.sleep {
            Card { MiniHypnogram(sleep: sleep, action: {}) }
        }
    }
}
