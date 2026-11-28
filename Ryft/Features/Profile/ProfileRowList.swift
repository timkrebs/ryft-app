import StoreKit
import SwiftUI

/// Draws the rows of one card, with their actions and identifiers shared between Profile's pages.
struct ProfileRowList: View {
    let rows: [ProfileRow]

    @Environment(ScreenModels.self) private var screens
    @Environment(Settings.self) private var settings
    @Environment(ProfilePrompts.self) private var prompts
    @Environment(\.appEnvironment) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: ProfileViewModel { screens.profile }
    private typealias L = ProfileLayout

    var body: some View {
        ForEach(rows) { row($0) }
    }

    // MARK: - rows

    // The rows shared by Profile's groups and pages. Each row's
    // identifier is on its control (`GroupedRow`'s `identifier:`).
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    @ViewBuilder private func row(_ row: ProfileRow) -> some View {
        let editor = model.bodySettings
        let id = row.identifier
        switch row {
        // You and body settings
        case .bodyAndBaselines:
            GroupedRow.push(ProfilePage.body.title, identifier: id, route: ProfileRoute.body)
        case .birthYear:
            BirthYearMenuRow(editor: editor)
        case .maxHR:
            // The saved value, or "Saving…" while a change is out (the value on its way is the editor page's alone).
            GroupedRow.push(Text("Maximum heart rate"), value: Text(verbatim: editor.rowValue(.maxHR, saved: editor.maxHRText)),
                            detail: editor.rowDetail(.maxHR).map { Text(verbatim: $0) }, hint: Text("Opens the editor"),
                            identifier: id) {
                prompts.editing = .maxHR
            }
            .detailParts(editor.rowDetailParts(.maxHR))
        case .sleepBase:
            GroupedRow.push(Text("Baseline sleep need"),
                            value: Text(verbatim: editor.rowValue(.sleepBase, saved: editor.sleepBaseText)),
                            detail: editor.rowDetail(.sleepBase).map { Text(verbatim: $0) }, hint: Text("Opens the editor"),
                            identifier: id) {
                prompts.editing = .sleepBase
            }
            .detailParts(editor.rowDetailParts(.sleepBase))
        case .rescore:
            GroupedRow.action(Text("Rescore the last 90\u{00A0}days"), systemImage: "arrow.clockwise", busy: editor.rescoring,
                              identifier: id) {
                Task { await editor.rescore() }
            }
            .disabled(!editor.canSave || (editor.saving && !editor.rescoring))
        // Devices and sync
        case .devices:
            let value = model.devices.isEnabled ? Text(verbatim: model.devices.summary)
                : Text(verbatim: model.healthStatusText).foregroundStyle(model.healthNeedsAttention ? Theme.warning : Theme.textTertiary)
            GroupedRow.push(ProfilePage.devicesAndSync.title, value: value, identifier: id, route: ProfileRoute.devices)
        case .appleHealth:
            GroupedRow.value(Text("Apple Health"), value: Text(verbatim: model.healthStatusText)
                .foregroundStyle(model.healthNeedsAttention ? Theme.warning : Theme.textTertiary), identifier: id)
        case .allowHealth:
            GroupedRow.action(Text("Allow access"), systemImage: "heart", identifier: id) {
                Task { await model.requestHealthAccess() }
            }
        case .openHealth:
            GroupedRow.action(model.devices.isEnabled ? Text("Open Health") : Text("Open Health permissions"),
                              systemImage: "arrow.up.right", hint: ProfileView.healthAppHint, identifier: id) {
                HealthLinks.open(with: openURL)
            }
        case .lastSync:
            GroupedRow.value(Text("Last sync"), value: Text(verbatim: model.lastSyncText), identifier: id)
        case .deviceID:
            GroupedRow.value(Text("Device ID"), value: Text(verbatim: model.deviceIDText), identifier: id)
        case .syncNow:
            GroupedRow.action(Text("Sync now"), detail: model.isSyncing ? Text(verbatim: model.syncProgress) : nil,
                              systemImage: "arrow.triangle.2.circlepath", busy: model.isSyncing, identifier: id) {
                Task { await model.syncNowFromProfile() }
            }
            .disabled(!model.canSync && !model.isSyncing)
        case .syncDetails:
            GroupedRow.push(Text("Sync details"), identifier: id, route: ProfileRoute.syncDetails)
        case .importTraining:
            // Area B's rows (`ImportProfileRows`, their own identifiers), each laid out as a grouped row.
            ImportProfileRows()
                .frame(maxWidth: .infinity, minHeight: L.rowMinHeight, alignment: .leading)
                .padding(.horizontal, GroupedListSpec.rowInset)
                .groupedRowHairline()
        case .demoMode:
            // Off with workouts logged in the demo asks first; the switch reads on until the exit has run. Held (no tap) while a
            // consent withdrawal is on its way, the reason as its detail, which is part of its label (D6): the switch alone
            // dims, the title and the reason stay at full ink so the sentence stays readable.
            let held = model.withdrawingConsent
            GroupedRow.toggle(Text("Demo data"),
                              detail: held ? Text(verbatim: ProfileViewModel.withdrawalHoldReason)
                                  : Text("Show a realistic sample history instead of your server."),
                              identifier: id, isOn: demoSwitch)
                .accessibilityHint(!model.showsDemoExitHint ? Text(verbatim: "")
                    : Text("Turning it off discards the workouts logged with Demo data.",
                           comment: "Only while such workouts exist"))
                .toggleStyle(RyftToggleStyle(dimsLabel: !held))
                .disabled(held)
                .animation(Theme.Motion.respecting(reduceMotion), value: held)
        // Training
        case .training:
            GroupedRow.push(ProfilePage.training.title, identifier: id, route: ProfileRoute.training)
        case .jumpToNext:
            GroupedRow.toggle(Text("Advance to the next exercise",
                                   comment: "Profile → Training toggle: after the last set of an exercise, the workout moves on to the next one."),
                              detail: Text("Jumps to the next set when you finish an exercise.",
                                           comment: "Footer under the Profile → Training toggle \"Advance to the next exercise\"."),
                              identifier: id, isOn: Bindable(settings).jumpToNextExercise)
        case .sessionLayout:
            SessionLayoutMenuRow(selection: Bindable(settings).sessionLayout)
        case .saveWorkouts:
            // On only while iOS still allows it; otherwise where to allow it (under the card).
            GroupedRow.toggle(Text("Save strength workouts to Apple Health"),
                              detail: Text("Each workout you log appears in Fitness and Health. Only the workout: no heart rate."),
                              identifier: id,
                              isOn: Binding(get: { WorkoutHealthExport.shared.isWriting }, set: { on in
                                  if on { Task { await WorkoutHealthExport.shared.turnOn() } } else { WorkoutHealthExport.shared.turnOff() }
                              }))
        // General
        case .display:
            GroupedRow.push(ProfilePage.display.title, identifier: id, route: ProfileRoute.display)
        case .notifications:
            GroupedRow.push(Text("Notifications"), identifier: id, route: ProfileRoute.notifications)
        case .journal:
            GroupedRow.push(Text("Journal"), identifier: id, route: ProfileRoute.journal)
        case .heroNumerals:
            HeroNumbersMenuRow(selection: Bindable(settings).heroNumerals)
        case .bedtime:
            GroupedRow.push(Text("Bedtime and wake", comment: "Profile row that opens the bedtime and wake schedule."),
                            value: Text(verbatim: screens.bedtime.summary),
                            detail: screens.bedtime.summaryDetail.map { Text(verbatim: $0) }, identifier: id,
                            route: ProfileRoute.bedtime)
                .detailParts(screens.bedtime.summaryDetailParts)
        // Privacy and data
        case .privacyAndData:
            let value = model.isSignedIn && !model.demoMode ? consentValue : nil
            GroupedRow.push(ProfilePage.privacyAndData.title, value: value, identifier: id, route: ProfileRoute.privacyAndData)
        case .consent:
            GroupedRow.value(Text("Health-data consent"), value: consentValue, identifier: id)
        case .reviewConsent:
            GroupedRow.action(Text("Review and agree"), systemImage: PillButton.Icon.forward, identifier: id) {
                model.reviewConsent()
            }
        case .checkConsent:
            // Sync now's glyph: it asks RYFT again. Busy, the row ignores taps itself and its spinner stays bright (UI
            // validation round 3, 1); offline it can't ask: dimmed, the hint says why, and the footer when it asks again.
            GroupedRow.action(Text("Check with RYFT",
                                   comment: "Profile → Privacy: asks RYFT again whether it has the consent given on this iPhone."),
                              systemImage: "arrow.triangle.2.circlepath", busy: model.checkingConsent,
                              hint: model.checkConsentHint.map { Text(verbatim: $0) }, identifier: id) {
                Task { await model.checkConsent() }
            }
            .disabled(!model.canCheckConsent && !model.checkingConsent)
        case .withdrawConsent:
            GroupedRow.destructive(Text("Withdraw consent"), busy: model.withdrawingConsent, identifier: id) {
                prompts.showWithdrawConfirm = true
            }
            // Not while Log out runs: its sign-out would end the withdrawal unsent; nor while Check with RYFT asks (the model
            // refuses both too).
            .disabled(model.loggingOut || model.checkingConsent)
        case .nutritionPrivacy:
            GroupedRow.push(Text("Nutrition privacy"), identifier: id, route: ProfileRoute.nutritionPrivacy)
        case .analytics:
            AnalyticsOptInRow()
        case .export:
            GroupedRow.action(Text("Export data", comment: "Privacy and data action that creates a file to share or save."),
                              systemImage: PillButton.Icon.download, busy: model.exporting,
                              hint: Text("Creates a JSON file of your scores, workouts and sessions to share or save",
                                         comment: "VoiceOver hint for Export data on the Privacy and data page."),
                              identifier: id) {
                Task { await model.export() }
            }
        // Account
        case .account:
            GroupedRow.push(ProfilePage.account.title, value: model.providerBadge.map { Text(verbatim: $0.title) },
                            identifier: id, route: ProfileRoute.account)
        case .email:
            GroupedRow.value(Text("Email"), value: Text(verbatim: model.accountEmail ?? ""), identifier: id)
        case .timezone:
            GroupedRow.value(Text("Timezone"), value: Text(verbatim: model.timezone ?? ""),
                             detail: model.timezoneDetail.map { Text(verbatim: $0) }, identifier: id)
        case .signInMethods:
            // The provider was the account card's badge ("Apple", "Email").
            GroupedRow.push(Text("Sign-in methods"), value: model.providerBadge.map { Text(verbatim: $0.title) },
                            identifier: id, route: ProfileRoute.signInMethods)
        case .changePassword:
            // A sheet over the page, not a page of its own: an action, no chevron.
            GroupedRow.action(Text("Change password"), identifier: id) { prompts.showChangePassword = true }
        case .logOutRow:
            GroupedRow.action(Text("Log out", comment: "Account action that opens the log-out confirmation."),
                              busy: prompts.sendsFirst || model.loggingOut, hint: prompts.logOutHint(model), identifier: id) {
                prompts.confirmLogOut(model)
            }
            .disabled(model.withdrawingConsent)
            .animation(Theme.Motion.respecting(reduceMotion), value: model.withdrawingConsent)
        case .deleteAccount:
            GroupedRow.destructive(Text("Delete account"), busy: model.isWorking, identifier: id) {
                prompts.deleteConfirmation = AccountBinding(env)
            }
        case .signedIn:
            GroupedRow.value(Text("Signed in"), value: Text("No"), identifier: id)
        // Resources
        case .whatsNew:
            GroupedRow.push(ProfilePage.whatsNew.title, value: Text(verbatim: ProfileView.version), identifier: id,
                            route: ProfileRoute.whatsNew)
        case .version:
            GroupedRow.value(Text("Version"), value: Text(verbatim: ProfileView.version), identifier: id)
        case .reportProblem:
            let waiting = model.report.waiting
            let value = waiting > 0
                ? Text("\(waiting) waiting to send", comment: "Help and feedback row value for queued reports.") : nil
            GroupedRow.push(Text("Help and feedback", comment: "Profile row that opens the problem report form."),
                            value: value, identifier: id, route: ProfileRoute.reportProblem)
                .task { model.report.reloadWaiting() }
        case .rateApp:
            GroupedRow.action(Text("Rate RYFT", comment: "Profile action to request an App Store rating."),
                              // `requestReview` is iOS's to show or not (a few times a year): the hint promises no more.
                              hint: Text("Asks iOS to show the App Store rating prompt",
                                         comment: "VoiceOver hint for Rate RYFT in Profile; iOS may not show the prompt."),
                              identifier: id) {
                requestReview()
            }
        // Legal
        case .privacyPolicy:
            // The policy in force (`GET /v1/config`), in the in-app Safari sheet (`safariSheet` catches `LegalPage` URLs).
            GroupedRow.linkOut(Text("Privacy Policy"), hint: Self.inAppHint, identifier: id, url: model.policyPage.url)
        case .terms:
            GroupedRow.linkOut(Text("Terms of Use"), hint: Self.inAppHint, identifier: id, url: LegalPage.terms.url)
        case .appleHealthPrivacy:
            if let url = URL(string: "https://www.apple.com/legal/privacy/data/en/health-app/") {
                GroupedRow.linkOut(Text("Apple Health privacy"), hint: Self.browserHint, identifier: id, url: url)
            }
        case .garminHealth:
            if let url = URL(string: "https://support.garmin.com/?q=apple%20health") {
                GroupedRow.linkOut(Text("Garmin Connect and Apple Health"), hint: Self.browserHint, identifier: id, url: url)
            }
        case .licences:
            GroupedRow.push(Text("Licences"), identifier: id, route: ProfileRoute.licences)
        }
    }

    /// The Demo data switch: on at once; off asks first when the demo logged workouts, and stays on when refused.
    private var demoSwitch: Binding<Bool> {
        Binding(get: { model.demoMode }, set: { on in
            guard !on else {
                Task { await model.setDemoMode(true) }
                return
            }
            switch model.switchingDemoOff() {
            case .confirm(let workouts): prompts.confirmDemoExit = workouts
            case .exit: Task { await model.endDemo() }
            case .refused: break // the switch stays on, and the message under the card says why
            }
        })
    }

    /// The legal links' hints for the browser and RYFT's own sheet.
    private static let browserHint = GroupedRow.webLinkHint
    private static let inAppHint = Text("Opens the page in RYFT",
                                comment: "VoiceOver hint of Profile's Privacy Policy and Terms of Use: they open in RYFT's own browser sheet.")

    private var consentValue: Text {
        Text(verbatim: model.consentText)
            .foregroundStyle(model.consentNeedsAttention ? Theme.warning : Theme.textTertiary)
    }
}
