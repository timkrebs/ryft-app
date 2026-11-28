import Foundation

enum QuickLogAction: String, CaseIterable, Identifiable {
    case meal, barcode, workout, activity, journal, sleep

    var id: String { rawValue }

    static func available(nutrition: Bool, train: Bool, myDay: Bool, canAddActivity: Bool,
                          journal: Bool, offersAddSleep: Bool) -> [Self] {
        allCases.filter { action in
            switch action {
            case .meal, .barcode: nutrition
            case .workout: train
            case .activity: myDay && canAddActivity
            case .journal: journal
            case .sleep: myDay && offersAddSleep
            }
        }
    }

    static func activityDay(selectedTab: AppTab, fitnessDay: Date, today: Date) -> Date {
        selectedTab == .strain ? fitnessDay : today
    }

    var analytics: AnalyticsQuickLogAction {
        switch self {
        case .meal: .logMeal
        case .barcode: .scanBarcode
        case .workout: .startWorkout
        case .activity: .addActivity
        case .journal: .journal
        case .sleep: .addSleep
        }
    }
}

enum QuickLogDestination: Identifiable {
    case activity(AddActivityModel)
    case journal(JournalSheetModel)
    case sleep(AddSleepModel)

    var id: QuickLogAction {
        switch self {
        case .activity: .activity
        case .journal: .journal
        case .sleep: .sleep
        }
    }
}
