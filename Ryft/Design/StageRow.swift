import SwiftUI

/// One stage of a night (Sleep → Day's stage card): coloured dot, stage name, duration, percentage.
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

#Preview("StageRow", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 14) {
            ForEach(MockData.todayDetail.sleep?.displayStages ?? []) { StageRow(share: $0) }
        }
    }
}
