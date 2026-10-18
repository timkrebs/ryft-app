import SwiftUI

/// Horizontal stacked bar of sleep stages, proportional to minutes.
struct StageBar: View {
    let stages: [StageShare]
    var height: CGFloat = 26
    var spacing: CGFloat = 2

    private var visible: [StageShare] { stages.filter { $0.min > 0 } }
    private var total: Int { visible.reduce(0) { $0 + $1.min } }

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width - spacing * CGFloat(max(0, visible.count - 1))
            HStack(spacing: spacing) {
                if total == 0 {
                    Rectangle().fill(Theme.surfaceRaised)
                } else {
                    ForEach(visible) { s in
                        Rectangle()
                            .fill(Theme.color(for: s.stage))
                            .frame(width: max(2, available * CGFloat(s.min) / CGFloat(total)))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height * 0.3, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep stages"))
        .accessibilityValue(Text(visible.map { "\($0.stage.title) \(Fmt.duration(minutes: $0.min))" }
            .joined(separator: ", ")))
    }
}

/// Legend row: coloured dot, stage name, duration, percentage.
struct StageRow: View {
    let share: StageShare

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.color(for: share.stage))
                .frame(width: 10, height: 10)
            Text(share.stage.title)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(Fmt.duration(minutes: share.min))
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(Fmt.percent(share.pct))
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("StageBar", traits: .sizeThatFitsLayout) {
    SchemePair {
        let stages = MockData.todayDetail.sleep?.displayStages ?? []
        VStack(spacing: 14) {
            StageBar(stages: stages)
            ForEach(stages) { StageRow(share: $0) }
            StageBar(stages: [])
        }
    }
}
