import Charts
import SwiftUI

/// The night as stage blocks over time (`SleepDetail.segments`): Awake on
/// top, Deep at the bottom. `asleep` (stage unknown) sits on the Light row in
/// a neutral colour.
struct Hypnogram: View {
    let segments: [SleepInterval]
    var height: CGFloat = 140

    private static let rows: [SleepStageKind] = [.awake, .rem, .light, .deep]

    private func row(_ s: SleepIntervalStage) -> SleepStageKind {
        switch s {
        case .deep: return .deep
        case .light, .asleep: return .light
        case .rem: return .rem
        case .awake: return .awake
        }
    }

    private func color(_ s: SleepIntervalStage) -> Color {
        s == .asleep ? Theme.accentSecondary : Theme.color(for: row(s))
    }

    /// Row index, Deep = 0 at the bottom.
    private func index(_ s: SleepIntervalStage) -> Double {
        Double(Self.rows.count - 1 - (Self.rows.firstIndex(of: row(s)) ?? 0))
    }

    var body: some View {
        Chart {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                let y = index(seg.stage)
                RectangleMark(xStart: .value("Start", seg.start), xEnd: .value("End", seg.end),
                              yStart: .value("Row", y - 0.32), yEnd: .value("Row", y + 0.32))
                    .foregroundStyle(color(seg.stage))
                    .cornerRadius(1)
            }
        }
        .chartYScale(domain: -0.5...Double(Self.rows.count) - 0.5)
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(0..<Self.rows.count).map(Double.init)) { value in
                AxisValueLabel {
                    if let i = value.as(Double.self) {
                        Text(Self.rows[Self.rows.count - 1 - Int(i)].title)
                            .font(ChartStyle.axisFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { value in
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
        .frame(height: height)
        .chartAppear()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Hypnogram"))
        .accessibilityValue(Text(summary))
    }

    /// "Deep 1h 52m, Light 4h 21m, …" for VoiceOver.
    private var summary: String {
        var minutes: [SleepStageKind: Int] = [:]
        for seg in segments {
            minutes[row(seg.stage), default: 0] += Int(seg.end.timeIntervalSince(seg.start) / 60)
        }
        return SleepStageKind.allCases.compactMap { s in
            minutes[s].map { "\(s.title) \(Fmt.duration(minutes: $0))" }
        }.joined(separator: ", ")
    }
}

#Preview("Hypnogram", traits: .sizeThatFitsLayout) {
    SchemePair {
        Card {
            Hypnogram(segments: MockData.todayDetail.sleep?.segments ?? [])
        }
    }
}
