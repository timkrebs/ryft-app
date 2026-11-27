import Observation
import SwiftUI

/// The prompts Profile presents over its navigation stack, including those raised from a pushed page.
@MainActor
@Observable
final class ProfilePrompts {
    var showLogOutConfirm = false
    /// Activities and nights that haven't reached RYFT when Log out was tapped (design.md §8.4).
    var unsentAtLogOut = 0
    var sendsFirst = false
    var deleteConfirmation: AccountBinding?
    var showChangePassword = false
    var showWithdrawConfirm = false
    /// Demo data switched off while workouts logged in the demo exist: what the confirmation counts (ADR 0019).
    var confirmDemoExit: DemoWorkouts?
    var editing: BodySetting?

    func confirmLogOut(_ model: ProfileViewModel) {
        unsentAtLogOut = model.unconfirmedActivities
        showLogOutConfirm = true
    }

    func logOutHint(_ model: ProfileViewModel) -> Text {
        Text(verbatim: model.withdrawingConsent ? ProfileViewModel.withdrawalHoldReason : "")
    }
}
