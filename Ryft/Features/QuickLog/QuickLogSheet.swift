import SwiftUI

@MainActor
struct QuickLogSheet: View {
    static let titleResource = LocalizedStringResource(
        "Quick log", comment: "Today: opens a sheet to log a meal or activity, or to start a workout."
    )

    let actions: [QuickLogAction]
    let workoutInProgress: Bool
    let select: (QuickLogAction) -> Void

    var body: some View {
        SheetFrame(Text(Self.titleResource)) {
            if actions.isEmpty {
                InlineMessage(message: String(localized: "Nothing is available to log yet.",
                                              comment: "Empty state of the Quick log sheet."),
                              systemImage: "plus.circle", announces: false)
            } else {
                GroupedCard {
                    ForEach(actions) { action in
                        GroupedRow.push(title(action), icon: icon(action), identifier: "quickLog.\(action.id)") { select(action) }
                    }
                }
                .frame(maxWidth: SubpageSpec.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .presentationDetents([.medium])
    }

    private func title(_ action: QuickLogAction) -> Text {
        switch action {
        case .meal: Text("Log meal", comment: "Action that opens the meal editor.")
        case .barcode: Text("Scan barcode", comment: "Action that opens barcode entry in the food picker.")
        case .workout:
            workoutInProgress
                ? Text("Resume workout", comment: "Action that resumes the current workout.")
                : Text("Start workout", comment: "Button label.")
        case .activity: Text("Add activity", comment: "My Day and the sheet's title: type in an activity.")
        // The app's own words for both (Profile → Journal, My Day's Add sleep), so German reads the same everywhere.
        case .journal: Text("Journal")
        case .sleep: Text("Add sleep")
        }
    }

    private func icon(_ action: QuickLogAction) -> String {
        switch action {
        case .meal: "fork.knife"
        case .barcode: "barcode.viewfinder"
        case .workout: "dumbbell"
        case .activity: "figure.walk"
        case .journal: "book.closed"
        case .sleep: "bed.double"
        }
    }
}

#Preview("Quick log") {
    DarkPreview {
        QuickLogSheet(actions: QuickLogAction.allCases, workoutInProgress: false) { _ in }
    }
}
