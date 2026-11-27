import SwiftUI

struct CheckinCard: View {
    let state: RecoveryCheckinStore.CardState
    let open: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Metrics.itemSpacing) {
                switch state {
                case .due:
                    title(Text("How did you sleep?", comment: "Today's morning check-in prompt."))
                    openButton
                case .skipped:
                    openButton
                case .done(let checkin):
                    title(Text("Checked in", comment: "Today's completed morning check-in."))
                        .accessibilityIdentifier("checkin.done")
                    summary(checkin)
                    PillButton(Text("Edit"), style: .secondary, size: .compact, action: open)
                        .accessibilityIdentifier("checkin.open")
                case .waiting:
                    detail(Text("Saved on this iPhone. It will be sent when you're online.",
                                comment: "Today's morning check-in is waiting to send."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("checkin.card")
    }

    private var openButton: some View {
        PillButton(Text("Check in", comment: "Action to open the morning check-in."), size: .compact, action: open)
            .accessibilityIdentifier("checkin.open")
    }

    private func summary(_ checkin: RecoveryCheckin) -> some View {
        let offset = TimeZone(secondsFromGMT: checkin.tzOffsetSec) ?? .current
        let bed = clock(checkin.bedtime, offset: offset)
        let wake = clock(checkin.wakeTime, offset: offset)
        return VStack(alignment: .leading, spacing: Theme.Metrics.hairline) {
            detail(Text(verbatim: "\(bed) – \(wake)"))
            detail(Text("Estimated recovery \(checkin.recoveryScore)", comment: "Today's estimated recovery score from the check-in."))
            if checkin.confidence == .medium {
                detail(Text("Based on your check-in and daytime heart rate", comment: "Medium confidence in estimated recovery."))
            } else {
                detail(Text("Based on your check-in", comment: "Low confidence in estimated recovery."))
            }
        }
    }

    private func clock(_ time: Date, offset: TimeZone) -> String {
        let minutes = SleepDialMath.minutes(of: time, timeZone: offset)
        return Fmt.time(hour: minutes / 60, minute: minutes % 60, locale: locale)
    }

    private func title(_ text: Text) -> some View {
        text.font(.ryft(.headline))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func detail(_ text: Text) -> some View {
        text.font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Morning check-in · due") {
    DarkPreview { CheckinCard(state: .due) {} }
}

#Preview("Morning check-in · waiting · AX3") {
    DarkPreview { CheckinCard(state: .waiting) {} }
        .environment(\.dynamicTypeSize, .accessibility3)
}
