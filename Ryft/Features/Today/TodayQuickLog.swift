import SwiftUI

enum TodayQuickLogAction: String, Identifiable {
    case meal, activity, workout

    var id: String { rawValue }

    func title(workoutInProgress: Bool) -> Text {
        switch self {
        case .meal: Text("Log meal")
        case .activity: Text("Add activity")
        case .workout: workoutInProgress ? Text("Resume workout") : Text("Start workout")
        }
    }

    var icon: String {
        switch self {
        case .meal: "fork.knife"
        case .activity: "figure.walk"
        case .workout: "dumbbell"
        }
    }
}

struct TodayQuickLogButton: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.background)
                .frame(width: Theme.Metrics.pillHeight, height: Theme.Metrics.pillHeight)
                .background(Theme.textPrimary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Quick log"))
        .accessibilityIdentifier("today.quickLog")
    }
}

struct TodayQuickLogSheet: View {
    let actions: [TodayQuickLogAction]
    let workoutInProgress: Bool
    let select: (TodayQuickLogAction) -> Void

    private var compactHeight: CGFloat {
        let rowHeight = IconDisc.regularDiameter + 2 * GroupedListSpec.textPadding
        return SheetHeaderSpec.topInset + SheetHeaderSpec.height + SheetFrameSpec.bodyGap
            + CGFloat(actions.count) * rowHeight + SubpageSpec.bottomPadding
    }

    var body: some View {
        SheetFrame(Text("Quick log")) {
            GroupedCard {
                ForEach(actions) { action in
                    GroupedRow.push(action.title(workoutInProgress: workoutInProgress), icon: action.icon,
                                    identifier: "today.quickLog.\(action.id)") { select(action) }
                }
            }
            .frame(maxWidth: SubpageSpec.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .sheetDetents(compact: [.height(compactHeight), .large])
    }
}
