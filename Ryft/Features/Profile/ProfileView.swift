import SwiftUI
import UIKit

/// Profile's main list in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-6): the header, the identity row, the app's
/// real rows in seven grouped cards (`ProfileRows`), the buttons row, and the Developer group in Debug builds. The subpages
/// are pushed (`ProfileRoute`) and keep their code (PR 6 C restyles them); every sheet and dialog is as before.
struct ProfileView: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(Settings.self) private var settings
    @Environment(\.appEnvironment) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showLogOutConfirm = false
    /// Activities and nights that haven't reached RYFT when Log out was tapped (design.md §8.4).
    @State private var unsentAtLogOut = 0
    @State private var sendsFirst = false
    @State private var showDeleteConfirm = false
    @State private var showChangePassword = false
    @State private var showWithdrawConfirm = false
    /// Demo data switched off while workouts logged in the demo exist: what the confirmation counts (ADR 0019).
    @State private var confirmDemoExit: DemoWorkouts?
    @State private var legal: LegalPage?
    @State private var editing: BodySetting?
    /// The identity row's tap: Sync details, pushed.
    @State private var showsSyncDetails = false

    private var model: ProfileViewModel { screens.profile }

    private typealias L = ProfileLayout

    var body: some View {
        NavigationStack {
            ScreenScaffold(showsHeader: false) {
                page
            }
            .navigationDestination(for: ProfileRoute.self) { destination($0) }
            .navigationDestination(isPresented: $showsSyncDetails) { SyncDetailsView(model: model.syncDetails) }
        }
        .safariSheet($legal)
        // The export file goes as soon as the share sheet is done with it (or closed by a swipe).
        .sheet(item: Bindable(model).exported, onDismiss: { model.removeExportFiles() }) {
            ShareSheet(items: [$0.url], completion: { model.removeExportFiles() }).presentationDetents([.medium, .large])
                .presentedRoot()
        }
        .bodySettingSheet($editing, editor: model.bodySettings)
        .task { await model.refreshHealthStatus() }
        // The Journal row is there while the journal is live: after the Demo data switch forgot the other side's, this
        // side's is asked for here too (as Today and Insights ask), so the row doesn't wait for them.
        .task(id: model.demoMode) {
            if screens.journal.availability == .unknown { await screens.journal.load() }
        }
        .confirmationDialog("Log out of RYFT?", isPresented: $showLogOutConfirm, titleVisibility: .visible) {
            if unsentAtLogOut > 0 {
                // Send first (10 s at most), then log out if nothing is left and it's still the same account;
                // otherwise ask again with what's left. Not offered when nothing can be sent now.
                if model.sendFirst == .available {
                    Button {
                        Task {
                            sendsFirst = true
                            let outcome = await model.sendFirstThenLogOut()
                            sendsFirst = false
                            // Asked again with what's left; never under a held Log out (D6: `.held`, or a withdrawal
                            // that began as the wait ended).
                            if case .unsent(let left) = outcome, !model.withdrawingConsent {
                                unsentAtLogOut = left
                                showLogOutConfirm = true
                            }
                        }
                    } label: {
                        Text("Send first", comment: "Log out: upload the activities and nights not at RYFT yet, then log out.")
                    }
                    .accessibilityIdentifier(ProfileRows.logOutSendFirst)
                }
                Button(role: .destructive) {
                    Task { await model.logOut() }
                } label: {
                    Text("Log out anyway", comment: "Log out: delete the activities and nights not at RYFT yet.")
                }
                .accessibilityIdentifier(ProfileRows.logOutAnyway)
            } else {
                Button("Log out", role: .destructive) {
                    Task { await model.logOut() }
                }
            }
        } message: {
            if unsentAtLogOut > 0, model.sendFirst == .offline {
                Text("\(unsentAtLogOut) activities or nights haven't reached RYFT yet, and you're offline. Logging out deletes them from this iPhone.",
                     comment: "Log out offline with uploads pending (Send first isn't offered); the number of activities and nights.")
            } else if unsentAtLogOut > 0 {
                Text("\(unsentAtLogOut) activities or nights haven't reached RYFT yet. Logging out deletes them from this iPhone.",
                     comment: "Log out with uploads pending; the number of activities and nights.")
            } else {
                Text("Cached scores and Health sync progress are removed from this iPhone. Your account and data stay on the RYFT platform.")
            }
        }
        .alert("Delete your RYFT account?", isPresented: $showDeleteConfirm) {
            Button("Delete account", role: .destructive) {
                Task { await model.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and everything RYFT stores for you: all synced Health samples, sleep, workouts, scores, devices and your profile. It can't be undone. Apple Health on this iPhone isn't touched.")
        }
        .sheet(isPresented: $showChangePassword) {
            SetNewPasswordView(mode: .change).presentedRoot()
        }
        .confirmationDialog("Withdraw your consent?", isPresented: $showWithdrawConfirm, titleVisibility: .visible) {
            Button("Withdraw consent", role: .destructive) {
                Task { await model.withdrawConsent() }
            }
            if model.canExport {
                Button("Export my data first") { Task { await model.export() } }
            }
            Button("Delete account instead", role: .destructive) { showDeleteConfirm = true }
        } message: {
            Text("RYFT stops syncing and scoring your health data. Nothing is deleted: your scores stay readable, and you can export your data or delete your account at any time.")
        }
        // Cancel keeps the demo running: nothing is called. Confirm works out again what goes (`endDemo`).
        .confirmationDialog(Text("Turn off Demo data?",
                                 comment: "Profile → Demo data switched off while workouts logged in the demo exist"),
                            isPresented: Binding(get: { confirmDemoExit != nil },
                                                 set: { if !$0 { confirmDemoExit = nil } }),
                            titleVisibility: .visible, presenting: confirmDemoExit) { _ in
            Button(role: .destructive) {
                Task { await model.endDemo() }
            } label: {
                Text("Discard and turn off", comment: "Deletes them and turns Demo data off")
            }
            .accessibilityIdentifier(ProfileRows.demoDiscard)
            Button(role: .cancel) {} label: {
                Text("Keep Demo data", comment: "Demo data stays on; nothing is deleted")
            }
            .accessibilityIdentifier(ProfileRows.demoKeep)
        } message: { workouts in
            Text("The \(workouts.count) workouts you logged with Demo data will be discarded. This can't be undone.",
                 comment: "The count includes one in progress. They're deleted from this iPhone; they only ever reached the demo's sample platform.")
        }
    }

    // MARK: the page (§P5-6.1)

    private var page: some View {
        let facts = ProfileRowFacts(model, journalLive: screens.journal.isLive, bedtimeEnabled: screens.bedtime.isEnabled,
                                    showsAnalytics: env.analytics.showsToggle)
        let groups = ProfileRows.groups(facts)
        return VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: Text("Profile"))
            ProfileIdentitySection(showsSyncDetails: $showsSyncDetails)
                .padding(.top, L.headerToIdentity)
            ForEach(groups) { entry in
                if entry.group == .about {
                    // The brand lock-up above the About group (as before), a group's gap above and under it.
                    BrandLockup()
                        .frame(maxWidth: .infinity)
                        .padding(.top, L.groupGap)
                }
                group(entry.group, rows: entry.rows)
                    .padding(.top, entry.group == .about ? L.lockUpToGroup
                        : entry.id == groups.first?.id ? L.identityToFirstGroup : L.groupGap)
            }
            buttons(ProfileRows.buttons(facts))
            #if DEBUG
            ProfileDeveloperGroup(model: model)
                .padding(.top, L.buttonsToDeveloper)
            #endif
        }
    }

    /// A group's card; its footer only when there is one, so an empty footer adds no gap.
    @ViewBuilder private func group(_ group: ProfileGroup, rows: [ProfileRow]) -> some View {
        if hasFooter(group) {
            GroupedCard(GroupTitle(group.title)) { self.rows(rows) } footer: { footer(group) }
        } else {
            GroupedCard(group.title) { self.rows(rows) }
        }
    }

    private func rows(_ rows: [ProfileRow]) -> some View {
        ForEach(rows) { self.row($0) }
    }

    // MARK: rows (§P5-6.2)

    // One switch over every row: the rows are the app's own, each with its behaviour from before Nocturne. Each row's
    // identifier is on its control (`GroupedRow`'s `identifier:`), one element per identifier.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    @ViewBuilder private func row(_ row: ProfileRow) -> some View {
        let editor = model.bodySettings
        let id = row.identifier
        switch row {
        // About you
        case .birthYear:
            BirthYearMenuRow(editor: editor)
        case .maxHR:
            // The saved value, or "Saving…" while a change is out (the value on its way is the editor page's alone).
            GroupedRow.push(Text("Maximum heart rate"), value: Text(verbatim: editor.rowValue(.maxHR, saved: editor.maxHRText)),
                            detail: editor.rowDetail(.maxHR).map { Text(verbatim: $0) }, hint: Text("Opens the editor"),
                            identifier: id) {
                editing = .maxHR
            }
            .detailParts(editor.rowDetailParts(.maxHR))
        case .sleepBase:
            GroupedRow.push(Text("Baseline sleep need"),
                            value: Text(verbatim: editor.rowValue(.sleepBase, saved: editor.sleepBaseText)),
                            detail: editor.rowDetail(.sleepBase).map { Text(verbatim: $0) }, hint: Text("Opens the editor"),
                            identifier: id) {
                editing = .sleepBase
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
            GroupedRow.push(Text("Devices & sync"), value: Text(verbatim: model.devices.summary), identifier: id,
                            route: ProfileRoute.devices)
        case .appleHealth:
            GroupedRow.value(Text("Apple Health"), value: Text(verbatim: model.healthStatusText)
                .foregroundStyle(model.healthNeedsAttention ? Theme.warning : Theme.textTertiary), identifier: id)
        case .allowHealth:
            GroupedRow.action(Text("Allow access"), systemImage: "heart", identifier: id) {
                Task { await model.requestHealthAccess() }
            }
        case .openHealth:
            GroupedRow.action(model.devices.isEnabled ? Text("Open Health") : Text("Open Health permissions"),
                              systemImage: "arrow.up.right", hint: Self.healthAppHint, identifier: id) {
                HealthLinks.open(with: openURL)
            }
        case .lastSync:
            GroupedRow.value(Text("Last sync"), value: Text(verbatim: model.lastSyncText), identifier: id)
        case .deviceID:
            GroupedRow.value(Text("Device ID"), value: Text(verbatim: model.deviceIDText), identifier: id)
        case .syncNow:
            GroupedRow.action(Text("Sync now"), detail: model.isSyncing ? Text(verbatim: model.syncProgress) : nil,
                              systemImage: "arrow.triangle.2.circlepath", busy: model.isSyncing, identifier: id) {
                Task { await model.syncNow() }
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
        // Settings
        case .notifications:
            GroupedRow.push(Text("Notifications"), identifier: id, route: ProfileRoute.notifications)
        case .journal:
            GroupedRow.push(Text("Journal"), identifier: id, route: ProfileRoute.journal)
        case .heroNumerals:
            HeroNumbersMenuRow(selection: Bindable(settings).heroNumerals)
        case .bedtime:
            GroupedRow.push(Text("Bedtime & wake"), value: Text(verbatim: screens.bedtime.summary),
                            detail: screens.bedtime.summaryDetail.map { Text(verbatim: $0) }, identifier: id,
                            route: ProfileRoute.bedtime)
                .detailParts(screens.bedtime.summaryDetailParts)
        // Privacy
        case .consent:
            GroupedRow.value(Text("Health-data consent"), value: Text(verbatim: model.consentText)
                .foregroundStyle(model.consentNeedsAttention ? Theme.warning : Theme.textTertiary), identifier: id)
        case .reviewConsent:
            GroupedRow.action(Text("Review and agree"), systemImage: PillButton.Icon.forward, identifier: id) {
                model.reviewConsent()
            }
        case .withdrawConsent:
            GroupedRow.destructive(Text("Withdraw consent"), busy: model.withdrawingConsent, identifier: id) {
                showWithdrawConfirm = true
            }
            // Not while Log out runs: its sign-out would end the withdrawal unsent (the model refuses it too).
            .disabled(model.loggingOut)
        case .analytics:
            AnalyticsOptInRow()
        // Account
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
            GroupedRow.action(Text("Change password"), identifier: id) { showChangePassword = true }
        case .deleteAccount:
            GroupedRow.destructive(Text("Delete account"), busy: model.isWorking, identifier: id) { showDeleteConfirm = true }
        case .signedIn:
            GroupedRow.value(Text("Signed in"), value: Text("No"), identifier: id)
        // About
        case .version:
            GroupedRow.value(Text("Version"), value: Text(verbatim: Self.version), identifier: id)
        case .reportProblem:
            let waiting = model.report.waiting
            GroupedRow.push(Text("Report a problem"), value: waiting > 0 ? Text("\(waiting) waiting to send") : nil,
                            identifier: id, route: ProfileRoute.reportProblem)
                .task { model.report.reloadWaiting() }
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
            case .confirm(let workouts): confirmDemoExit = workouts
            case .exit: Task { await model.endDemo() }
            case .refused: break // the switch stays on, and the message under the card says why
            }
        })
    }

    /// The link-outs' hints: a web page outside RYFT, a page in RYFT's own sheet, the Health app.
    static let browserHint = GroupedRow.webLinkHint
    static let inAppHint = Text("Opens the page in RYFT",
                                comment: "VoiceOver hint of Profile's Privacy Policy and Terms of Use: they open in RYFT's own browser sheet.")
    static let healthAppHint = Text("Opens the Health app", comment: "VoiceOver hint of Profile's Open Health row.")

    // MARK: footers: notices and sentences under each card, 8 below it

    private func hasFooter(_ group: ProfileGroup) -> Bool {
        switch group {
        case .aboutYou, .settings, .about: return true
        case .devicesAndSync:
            return model.syncNotice != nil || model.demoExitError != nil || !model.devices.isEnabled
                || !model.devices.healthAccessSteps.isEmpty
        case .training: return WorkoutHealthExport.shared.needsAccess || model.showsSessionLayout
        case .privacy: return model.consentError != nil || model.consentDetail != nil
        case .account: return !model.isSignedIn || model.accountError != nil
        }
    }

    @ViewBuilder private func footer(_ group: ProfileGroup) -> some View {
        switch group {
        case .aboutYou:
            let editor = model.bodySettings
            FooterStack {
                if let error = editor.birthYearError {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle", details: editor.birthYearErrorDetails)
                }
                // A save whose answer came after its editor page went: said here, where the user is.
                if editor.errorMissed, let error = editor.error {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle", details: editor.errorDetails)
                        .accessibilityIdentifier("profile.bodySettingsError")
                }
                RescoreStatus(editor: editor)
                GroupFooter(Text("Changing a setting doesn't rescore past days on its own."))
            }
        case .devicesAndSync:
            FooterStack {
                switch model.syncNotice {
                case .retrying(let notice):
                    InlineMessage(message: notice, systemImage: "clock.arrow.circlepath")
                case .failed(let message, let details):
                    InlineMessage(message: message, systemImage: "exclamationmark.arrow.triangle.2.circlepath", details: details)
                case nil:
                    EmptyView()
                }
                if let error = model.demoExitError {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle")
                }
                // With `devices.setup` the path to RYFT's permission comes from the catalog, and Devices & sync has each
                // tracker's own steps.
                if model.devices.isEnabled {
                    if !model.devices.healthAccessSteps.isEmpty {
                        GroupFooter(Text(verbatim: model.devices.healthAccessSteps.joined(separator: " ")))
                    }
                } else {
                    GroupFooter(Text("Garmin Connect must write to Apple Health (Garmin Connect → More → Settings → Apple Health), and RYFT must be allowed to read it (Health → Sharing → Apps → RYFT)."))
                }
            }
        case .training:
            FooterStack {
                if WorkoutHealthExport.shared.needsAccess { HealthWriteAccessHint() }
                if model.showsSessionLayout {
                    GroupFooter(Text("Focused: one exercise at a time. List: all exercises on one screen. Applies the next time you open a workout.",
                                     comment: "Footer under Profile → Training → Session layout."))
                }
            }
        case .settings:
            GroupFooter(Text("Large numbers on Today, Sleep and Strain.",
                             comment: "Footer under Profile → Display → Hero numbers: where the dots or thin digits show."))
        case .privacy:
            FooterStack {
                if let error = model.consentError {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle", details: model.consentErrorDetails)
                }
                if let detail = model.consentDetail {
                    GroupFooter(consentFooter(detail))
                }
            }
        case .account:
            if model.isSignedIn {
                if let error = model.accountError {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle", details: model.accountErrorDetails)
                }
            } else {
                GroupFooter(Text("Turn off Demo data to log in or create an account."))
            }
        case .about:
            GroupFooter(Text("RYFT is a wellness tool, not a medical device. Talk to a doctor about health concerns."))
        }
    }

    /// "Agreed on 3 Nov 2026 · policy 2026-11. Read the policy": the policy in force beside Withdraw consent, in the in-app
    /// sheet (`safariSheet` catches its `LegalPage` URL); the link in the link ink, underlined (`InlineLink`).
    private func consentFooter(_ detail: String) -> Text {
        var link = AttributedString(localized: "Read the policy",
                                    comment: "Link at the end of Profile → Privacy's footer: opens the privacy policy in force in RYFT.")
        link.link = model.policyPage.url
        return Text(InlineLink.styled(AttributedString(detail + " ") + link))
    }

    // MARK: the buttons row (§P5-6.1 row 4)

    /// Log out is held while a consent withdrawal is on its way (D6): dimmed, no tap, the reason under the row (8 below it)
    /// and as its VoiceOver hint; the line itself is hidden from VoiceOver, so the reason is read once.
    @ViewBuilder private func buttons(_ buttons: [ProfileButton]) -> some View {
        if !buttons.isEmpty {
            let stacked = typeSize.isAccessibilitySize
            let held = model.withdrawingConsent && buttons.contains(.logOut)
            VStack(alignment: .leading, spacing: L.buttonsToMessage) {
                let layout = stacked ? AnyLayout(VStackLayout(spacing: L.buttonsGap)) : AnyLayout(HStackLayout(spacing: L.buttonsGap))
                layout {
                    ForEach(buttons) { button in
                        switch button {
                        case .export:
                            PillButton(Text("Export data", comment: "Profile: the button that creates a file of your data to share or save."),
                                       systemImage: PillButton.Icon.download, busy: model.exporting) {
                                await model.export()
                            }
                            .accessibilityHint(Text("Creates a JSON file of your scores, workouts and sessions to share or save"))
                            .accessibilityIdentifier(button.identifier)
                        case .logOut:
                            // Busy while Send first waits, and while the sign-out deletes the push registration.
                            PillButton(Text("Log out"), style: .secondary, busy: sendsFirst || model.loggingOut) {
                                unsentAtLogOut = model.unconfirmedActivities
                                showLogOutConfirm = true
                            }
                            // As wide as its title plus 22 a side beside Export; full width when the row stacks.
                            .fixedSize(horizontal: !stacked && buttons.count > 1, vertical: false)
                            .disabled(held)
                            .accessibilityHint(held ? Text(verbatim: ProfileViewModel.withdrawalHoldReason) : Text(verbatim: ""))
                            .accessibilityIdentifier(button.identifier)
                        }
                    }
                }
                if held {
                    Text(verbatim: ProfileViewModel.withdrawalHoldReason)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                }
                if let error = model.exportError {
                    InlineMessage(message: error, systemImage: "square.and.arrow.up")
                }
            }
            .animation(Theme.Motion.respecting(reduceMotion), value: held)
            .padding(.top, L.buttonsTop)
        }
    }

    // MARK: subpages (PR 6 C restyles them)

    @ViewBuilder private func destination(_ route: ProfileRoute) -> some View {
        switch route {
        case .devices: DevicesAndSyncView(model: model.devices)
        case .syncDetails: SyncDetailsView(model: model.syncDetails)
        case .notifications: NotificationSettingsView()
        case .journal: JournalSettingsView(store: screens.journal)
        case .bedtime: SleepScheduleView(planner: screens.bedtime)
        case .signInMethods: SignInMethodsView()
        case .reportProblem: ReportProblemView(model: model.report)
        case .licences: LicensesView()
        #if DEBUG
        case .catalog: DebugComponentCatalog()
        case .flags: FeatureFlagsDebugView()
        #endif
        }
    }

    static var version: String { AppInfo.version }
}

/// A card's footer parts, 8 apart (`GroupedListSpec.footerGap`); nothing when there are none.
private struct FooterStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.footerGap) { content() }
    }
}

extension ProfileRowFacts {
    /// The page's facts: the model's account, flags and switches, and the two shared stores'.
    @MainActor
    init(_ model: ProfileViewModel, journalLive: Bool, bedtimeEnabled: Bool, showsAnalytics: Bool = false) {
        self.init(isSignedIn: model.isSignedIn, devicesEnabled: model.devices.isEnabled, canAskForHealth: model.canAskForHealth,
                  showsTraining: model.showsTraining, showsSessionLayout: model.showsSessionLayout,
                  showsNotifications: model.showsNotifications, journalLive: journalLive, bedtimeEnabled: bedtimeEnabled,
                  consentIsCurrent: model.consentIsCurrent, showsAnalytics: showsAnalytics, isDemo: model.demoMode, canChangePassword: model.canChangePassword,
                  hasTimezone: model.timezone != nil, showsEmail: model.showsEmailRow, canExport: model.canExport)
    }
}

// MARK: - the identity row's models

/// The identity row, reading the sync's line in its own body: the line changes with every sync step, and only this row
/// shows it, so the page's groups don't re-render for it.
private struct ProfileIdentitySection: View {
    @Binding var showsSyncDetails: Bool
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        let model = screens.profile
        let status = model.status(line: screens.today.syncLine)
        ProfileIdentityRow(identity: model.identity, status: status) {
            if model.tapStatus(status.tap) { showsSyncDetails = true }
        }
    }
}

// MARK: - developer (Debug builds only)

#if DEBUG
/// Platform overrides for a compose stack, API key mode (`AUTH_MODE=apikey`), request IDs of recent failures and a connection
/// test, in the page's grouped card (§P5-6.2: the same rows). Not in Release; English only, never in the catalog.
private struct ProfileDeveloperGroup: View {
    let model: ProfileViewModel
    @Environment(ScreenModels.self) private var screens
    @Environment(Settings.self) private var settings
    private let apiStatus = APIStatus.shared

    var body: some View {
        // Held as Demo data is (D6, security review N-1): another platform or another credential mid-way would end the
        // withdrawal unsent, or send it somewhere else.
        let held = model.withdrawingConsent
        GroupedCard(GroupTitle(Text(verbatim: "Developer"))) {
            GroupedRow.push(Text(verbatim: "Component catalog"), identifier: ProfileRows.devCatalog, route: ProfileRoute.catalog)
            GroupedRow.push(Text(verbatim: "Feature flags"), identifier: ProfileRows.devFlags, route: ProfileRoute.flags)
            GroupedRow.value(Text(verbatim: "Push registration"), value: Text(verbatim: screens.push.lastResult ?? "—"))
            field("API URL override") {
                TextField(Bundle.configValue("RyftAPIURL") ?? "https://api.ryftlab.de", text: Bindable(settings).devAPIURLOverride)
                    .keyboardType(.URL)
                    .accessibilityIdentifier(ProfileRows.devAPIURL)
            }
            .disabled(held)
            field("Ingest URL override (compose: :8081, needed with an API override)") {
                TextField(Bundle.configValue("RyftIngestURL") ?? "https://ingest.ryftlab.de",
                          text: Bindable(settings).devIngestURLOverride)
                    .keyboardType(.URL)
                    .accessibilityIdentifier(ProfileRows.devIngestURL)
            }
            .disabled(held)
            GroupedRow.toggle(Text(verbatim: "API key mode"),
                              detail: Text(verbatim: held ? "Held while your consent withdrawal is on its way."
                                                          : "Sends a static bearer instead of your session, for a platform started with AUTH_MODE=apikey."),
                              identifier: ProfileRows.devAPIKeyMode, isOn: Bindable(settings).apiKeyMode)
                // Held, the switch alone dims, so "Held while…" stays readable (as Demo data's).
                .toggleStyle(RyftToggleStyle(dimsLabel: !held))
                .disabled(held)
            if settings.apiKeyMode {
                field("API key") {
                    SecureField("Bearer token", text: Bindable(settings).devAPIKey)
                }
                .disabled(held)
            }
            GroupedRow.toggle(Text(verbatim: "Show request IDs"), isOn: Bindable(settings).showRequestIDs)
            if settings.showRequestIDs {
                requestIDs
            }
            GroupedRow.action(Text(verbatim: "Test connection"), systemImage: "network", busy: model.testingConnection) {
                Task { await model.testConnection() }
            }
        } footer: {
            FooterStack {
                switch model.connection {
                case .ok(let text):
                    InlineMessage(message: text, systemImage: "checkmark.circle", announces: false)
                case .failed(let text):
                    InlineMessage(message: text, systemImage: "exclamationmark.circle")
                case nil:
                    EmptyView()
                }
                GroupFooter(Text(verbatim: "Debug builds only."))
            }
        }
    }

    /// A text field under its label, in the card's row padding.
    private func field<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: label)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
            field()
                .font(.ryft(.body))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, GroupedListSpec.textPadding)
        .groupedRowHairline()
    }

    @ViewBuilder private var requestIDs: some View {
        VStack(alignment: .leading, spacing: 8) {
            if apiStatus.failures.isEmpty {
                Text(verbatim: "No failed requests since launch.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(apiStatus.failures) { f in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(f.status) \(f.method) \(redactedPath(f.path))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: "\(f.requestID ?? "–") · \(f.date.formatted(date: .omitted, time: .standard))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, GroupedListSpec.textPadding)
        .groupedRowHairline()
    }
}
#endif

// MARK: - previews (dark; default and AX3; design.md §P5-11)

#if DEBUG
/// Profile on a graph of its own: signed in or not, Demo data on or off, the account and today's strain as the state needs.
/// Syncing is the identity row's preview (`ProfileIdentity.swift`): the line comes from the sync's own state.
@MainActor
private enum ProfilePreview {
    enum Case {
        case signedIn, noName, noStrain, signedOutDemo, signedInDemo, offline, consentOutdated
        /// A consent withdrawal on its way that never answers: Demo data, Log out and the overrides held (D6).
        case withdrawing
    }

    static func page(_ kind: Case, ax3: Bool = false) -> some View {
        let demo = kind == .signedOutDemo || kind == .signedInDemo
        let defaults = UserDefaults(suiteName: "ryft.preview.profile") ?? .standard
        let settings = Settings(defaults: defaults)
        // Apple Health uploaded a minute ago: "up to date" needs it.
        settings.lastSync = demo ? nil : .now.addingTimeInterval(-60)
        let api = MockPlatformAPI(activities: .demoSource())
        let withdrawing = kind == .withdrawing
        // Never answered while the preview is open; on a clock that stands still, so `SettingsWrite.deadline` never ends it.
        if withdrawing { api.beforeRevokeConsent = { try? await Task.sleep(for: .seconds(86_400)) } }
        // Demo data on over a signed-in Apple account: the account's rows are the session's, never the demo's person.
        let env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: api, demoAPI: api,
                                 auth: .preview(signedIn: kind != .signedOutDemo, provider: kind == .signedInDemo ? "apple" : "email"),
                                 persistence: TrainStore(inMemory: true),
                                 clock: withdrawing ? TestClock(now: .now) : SystemClock(), notifier: MockNotifier(),
                                 flags: StaticFlags([.devicesSetup: true]), connectivity: .preview(online: kind != .offline),
                                 defaults: defaults, demoOverride: demo)
        env.uploader.gate = { _ in nil }
        let state = AppState(env: env)
        state.history = MockData.history
        state.user = user(kind)
        var today = MockData.todayDetail
        if kind == .noStrain { today.score.strain = nil }
        state.today = today
        let sync = SyncService(env: env)
        let screens = ScreenModels(state: state, sync: sync,
                                   coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock),
                                   store: TrainPreview.store, library: TrainPreview.library)
        return ProfileView()
            // The confirmation's Withdraw consent, tapped.
            .task { if withdrawing { await screens.profile.withdrawConsent() } }
            .environment(\.appEnvironment, env)
            .environment(screens)
            .environment(settings)
            .environment(env.auth)
            .environment(sync)
            .environment(state)
            .environment(TrainPreview.library)
            .environment(TrainPreview.sync)
            .environment(TrainPreview.coordinator)
            .environment(env.connectivityMonitor)
            .toggleStyle(.ryft)
            .preferredColorScheme(.dark)
            .tint(Theme.textPrimary)
            .environment(\.dynamicTypeSize, ax3 ? .accessibility3 : .large)
    }

    private static func user(_ kind: Case) -> User {
        let u = MockData.user
        switch kind {
        case .noName:
            return User(id: u.id, name: "", email: u.email, provider: u.provider, tz: u.tz, maxHr: u.maxHr,
                        sleepBaseMin: u.sleepBaseMin, consent: u.consent, birthYear: u.birthYear)
        case .consentOutdated:
            return User(id: u.id, name: u.name, email: u.email, provider: u.provider, tz: u.tz, maxHr: u.maxHr,
                        sleepBaseMin: u.sleepBaseMin, birthYear: u.birthYear)
        default:
            return u
        }
    }
}

/// The buttons row on its own: exporting (the Export pill busy) beside Log out.
private struct ProfileButtonsPreview: View {
    var body: some View {
        HStack(spacing: ProfileLayout.buttonsGap) {
            PillButton(Text(verbatim: "Export data"), systemImage: PillButton.Icon.download, busy: true) {}
            PillButton(Text(verbatim: "Log out"), style: .secondary) {}.fixedSize(horizontal: true, vertical: false)
        }
    }
}

#Preview("Profile · signed in") { ProfilePreview.page(.signedIn) }
#Preview("Profile · signed in · AX3") { ProfilePreview.page(.signedIn, ax3: true) }
#Preview("Profile · no name (email)") { ProfilePreview.page(.noName) }
#Preview("Profile · no name (email) · AX3") { ProfilePreview.page(.noName, ax3: true) }
#Preview("Profile · no strain today") { ProfilePreview.page(.noStrain) }
#Preview("Profile · no strain today · AX3") { ProfilePreview.page(.noStrain, ax3: true) }
#Preview("Profile · signed out / demo") { ProfilePreview.page(.signedOutDemo) }
#Preview("Profile · signed out / demo · AX3") { ProfilePreview.page(.signedOutDemo, ax3: true) }
#Preview("Profile · signed in / demo") { ProfilePreview.page(.signedInDemo) }
#Preview("Profile · signed in / demo · AX3") { ProfilePreview.page(.signedInDemo, ax3: true) }
#Preview("Profile · offline") { ProfilePreview.page(.offline) }
#Preview("Profile · offline · AX3") { ProfilePreview.page(.offline, ax3: true) }
#Preview("Profile · consent outdated") { ProfilePreview.page(.consentOutdated) }
#Preview("Profile · consent outdated · AX3") { ProfilePreview.page(.consentOutdated, ax3: true) }
#Preview("Profile · withdrawing consent") { ProfilePreview.page(.withdrawing) }
#Preview("Profile · withdrawing consent · AX3") { ProfilePreview.page(.withdrawing, ax3: true) }
#Preview("Profile · exporting", traits: .sizeThatFitsLayout) { DarkPreview { ProfileButtonsPreview() } }
#Preview("Profile · exporting · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { ProfileButtonsPreview() }.environment(\.dynamicTypeSize, .accessibility3)
}
#endif
