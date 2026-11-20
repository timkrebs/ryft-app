import SwiftUI
import UIKit

/// Account, body settings, data/sync and about. Replaces the scaffold's SettingsView.
struct ProfileView: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(Settings.self) private var settings
    @Environment(\.openURL) private var openURL
    private var apiStatus = APIStatus.shared

    @State private var showResyncConfirm = false
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

    private var model: ProfileViewModel { screens.profile }

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                Text("Profile")
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                account
                bodySection
                sleepSection
                privacy
                data
                if model.showsTraining { training }
                if model.showsNotifications { notifications }
                if screens.journal.isLive { journal }
                display
                about
                #if DEBUG
                developer
                #endif
            }
        }
        .safariSheet($legal)
        // The export file goes as soon as the share sheet is done with it (or closed by a swipe).
        .sheet(item: Bindable(model).exported, onDismiss: { model.removeExportFiles() }) {
            ShareSheet(items: [$0.url], completion: { model.removeExportFiles() }).presentationDetents([.medium, .large])
        }
        .bodySettingSheet($editing, editor: model.bodySettings)
        .task { await model.refreshHealthStatus() }
        .confirmationDialog("Re-upload the last 90 days of Health data?", isPresented: $showResyncConfirm,
                            titleVisibility: .visible) {
            Button("Re-sync", role: .destructive) {
                Task { await model.fullResync() }
            }
        } message: {
            Text("This uploads everything again. It can take a few minutes on the first run.")
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
                            if case .unsent(let left) = outcome {
                                unsentAtLogOut = left
                                showLogOutConfirm = true
                            }
                        }
                    } label: {
                        Text("Send first", comment: "Log out: upload the activities and nights not at RYFT yet, then log out.")
                    }
                    .accessibilityIdentifier("profile.logOut.sendFirst")
                }
                Button(role: .destructive) {
                    Task { await model.logOut() }
                } label: {
                    Text("Log out anyway", comment: "Log out: delete the activities and nights not at RYFT yet.")
                }
                .accessibilityIdentifier("profile.logOut.anyway")
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
            SetNewPasswordView(mode: .change)
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
            .accessibilityIdentifier("profile.demo.discard")
            Button(role: .cancel) {} label: {
                Text("Keep Demo data", comment: "Demo data stays on; nothing is deleted")
            }
            .accessibilityIdentifier("profile.demo.keep")
        } message: { workouts in
            Text("The \(workouts.count) workouts you logged with Demo data will be discarded. This can't be undone.",
                 comment: "The count includes one in progress. They're deleted from this iPhone; they only ever reached the demo's sample platform.")
        }
    }

    // MARK: account

    private var account: some View {
        ProfileSection(title: "Account") {
            if model.isSignedIn {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.accountTitle)
                            .font(.ryft(.headline))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let email = model.accountSubtitle {
                            Text(email)
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 8)
                    if let badge = model.providerBadge {
                        ProviderBadge(title: badge.title, systemImage: badge.systemImage)
                    }
                }
                .accessibilityElement(children: .combine)
                if let tz = model.timezone {
                    StatRow(title: "Timezone", value: tz, detail: model.timezoneDetail)
                }
                NavigationLink {
                    SignInMethodsView()
                } label: {
                    HStack {
                        Text("Sign-in methods").font(.ryft(.callout)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.signInMethods")
                Divider().overlay(Theme.separator)
                if model.canChangePassword {
                    PrimaryButton(title: "Change password", style: .secondary) { showChangePassword = true }
                }
                PrimaryButton(title: "Log out", style: .secondary, busy: sendsFirst) {
                    unsentAtLogOut = model.unconfirmedActivities
                    showLogOutConfirm = true
                }
                .accessibilityIdentifier("profile.logOut")
                PrimaryButton(title: "Delete account", style: .destructive, busy: model.isWorking) {
                    showDeleteConfirm = true
                }
                if let error = model.accountError {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle", details: model.accountErrorDetails)
                }
            } else {
                StatRow(title: "Signed in", value: String(localized: "No"), valueColor: Theme.textSecondary)
                Text("Turn off Demo data to log in or create an account.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: developer (Debug builds only)

    #if DEBUG
    /// Platform overrides for a compose stack, API key mode (`AUTH_MODE=apikey`),
    /// request IDs of recent failures and a connection test. Not in Release.
    private var developer: some View {
        ProfileSection(title: "Developer") {
            Text("Debug builds only.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
            NavigationLink {
                DebugComponentCatalog()
            } label: {
                Label("Component catalog", systemImage: "square.grid.2x2")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("dev.catalog")
            NavigationLink {
                FeatureFlagsDebugView()
            } label: {
                Label("Feature flags", systemImage: "flag")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("dev.flags")
            HStack {
                Text(verbatim: "Push registration").font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(verbatim: screens.push.lastResult ?? "—").font(.ryft(.caption)).foregroundStyle(Theme.textPrimary)
            }
            FieldLabel("API URL override")
            TextField(Bundle.configValue("RyftAPIURL") ?? "https://api.ryftlab.de", text: Bindable(settings).devAPIURLOverride)
                .ryftField()
                .keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            FieldLabel("Ingest URL override (compose: :8081, needed with an API override)")
            TextField(Bundle.configValue("RyftIngestURL") ?? "https://ingest.ryftlab.de",
                      text: Bindable(settings).devIngestURLOverride)
                .ryftField()
                .keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()

            Toggle(isOn: Bindable(settings).apiKeyMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("API key mode")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Sends a static bearer instead of your session, for a platform started with AUTH_MODE=apikey.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .tint(Theme.accent)
            if settings.apiKeyMode {
                FieldLabel("API key")
                SecureField("Bearer token", text: Bindable(settings).devAPIKey)
                    .ryftField()
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }

            Toggle(isOn: Bindable(settings).showRequestIDs) {
                Text("Show request IDs")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)
            if settings.showRequestIDs {
                if apiStatus.failures.isEmpty {
                    Text("No failed requests since launch.")
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

            PrimaryButton(title: "Test connection", style: .secondary, busy: model.testingConnection) {
                await model.testConnection()
            }
            switch model.connection {
            case .ok(let text):
                Label(text, systemImage: "checkmark.circle.fill")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.accent)
            case .failed(let text):
                InlineMessage(message: text, systemImage: "exclamationmark.circle")
            case nil:
                EmptyView()
            }
        }
    }

    #endif

    // MARK: body

    private var bodySection: some View {
        let editor = model.bodySettings
        return ProfileSection(title: "Body") {
            SettingRow(title: "Maximum heart rate", value: editor.maxHRText, detail: editor.maxHRSourceText) {
                editing = .maxHR
            }
            HStack {
                Text("Birth year").font(.ryft(.body)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker("Birth year", selection: Binding(get: { editor.birthYear },
                                                        set: { y in if let y { Task { await editor.setBirthYear(y) } } })) {
                    if editor.birthYear == nil { Text("Not set").tag(Int?.none) }
                    ForEach(editor.birthYears, id: \.self) { Text(verbatim: "\($0)").tag(Int?.some($0)) }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
                .disabled(editor.isBusy)
            }
            .frame(minHeight: 44)
            if let error = editor.birthYearError {
                InlineMessage(message: error, systemImage: "exclamationmark.circle", details: editor.birthYearErrorDetails)
            }
            Text("Changing a setting doesn't rescore past days on its own.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Rescore the last 90 days", style: .secondary, busy: editor.rescoring) {
                await editor.rescore()
            }
            .disabled(!editor.canSave || editor.saving)
            RescoreStatus(editor: editor)
        }
    }

    // MARK: sleep

    private var sleepSection: some View {
        let editor = model.bodySettings
        return ProfileSection(title: "Sleep") {
            SettingRow(title: "Baseline sleep need", value: editor.sleepBaseText, detail: editor.sleepBaseSourceText) {
                editing = .sleepBase
            }
            .accessibilityIdentifier("profile.sleepBase")
            Text("Each night's sleep need starts from this baseline, plus top-ups for strain and sleep debt, minus naps.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if screens.bedtime.isEnabled {
                Divider().overlay(Theme.separator)
                NavigationLink {
                    SleepScheduleView(planner: screens.bedtime)
                } label: {
                    SettingRowLabel(title: "Bedtime & wake", value: screens.bedtime.summary,
                                    detail: screens.bedtime.summaryDetail)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.bedtime")
            }
        }
    }

    // MARK: privacy

    /// Consent to health-data processing: when, for which policy, withdraw or agree.
    private var privacy: some View {
        ProfileSection(title: "Privacy") {
            StatRow(title: "Health-data consent", value: model.consentText,
                    valueColor: model.consentIsCurrent ? Theme.textPrimary : Theme.warning)
            if let detail = model.consentDetail {
                Text(detail)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.consentIsCurrent {
                PrimaryButton(title: "Withdraw consent", style: .destructive, busy: model.withdrawingConsent) {
                    showWithdrawConfirm = true
                }
            } else {
                PrimaryButton(title: "Review and agree") { model.reviewConsent() }
            }
            if let error = model.consentError {
                InlineMessage(message: error, systemImage: "exclamationmark.circle")
            }
            AnalyticsOptInRow()
            Button {
                legal = model.policyPage
            } label: {
                Text("Privacy Policy").font(.ryft(.callout)).foregroundStyle(Theme.accent).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: data

    private var data: some View {
        ProfileSection(title: "Data") {
            // `devices.setup`: what you wear, each tracker's setup and what Apple Health has seen.
            if model.devices.isEnabled {
                NavigationLink {
                    DevicesAndSyncView(model: model.devices)
                } label: {
                    DevicesRowLabel(summary: model.devices.summary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.devices")
                Divider().overlay(Theme.separator)
            }
            StatRow(title: "Apple Health", value: model.healthStatusText,
                    valueColor: model.healthNeedsAttention ? Theme.warning : Theme.textPrimary)
            HStack(spacing: 10) {
                if model.canAskForHealth {
                    PrimaryButton(title: "Allow access", style: .secondary) { await model.requestHealthAccess() }
                }
                if model.devices.isEnabled {
                    PrimaryButton(title: "Open Health", style: .secondary) { HealthLinks.open(with: openURL) }
                } else {
                    PrimaryButton(title: "Open Health permissions", style: .secondary) { HealthLinks.open(with: openURL) }
                }
            }
            // With `devices.setup` the path to RYFT's permission comes from the catalog, and Devices & sync has each
            // tracker's own steps.
            if model.devices.isEnabled {
                if !model.devices.healthAccessSteps.isEmpty {
                    Text(verbatim: model.devices.healthAccessSteps.joined(separator: " "))
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Garmin Connect must write to Apple Health (Garmin Connect → More → Settings → Apple Health), and RYFT must be allowed to read it (Health → Sharing → Apps → RYFT).")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // On only while iOS still allows it; otherwise where to allow it.
            Toggle(isOn: Binding(get: { WorkoutHealthExport.shared.isWriting },
                                 set: { on in
                                     if on { Task { await WorkoutHealthExport.shared.turnOn() } } else { WorkoutHealthExport.shared.turnOff() }
                                 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save strength workouts to Apple Health")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Each workout you log appears in Fitness and Health. Only the workout: no heart rate.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("profile.saveWorkouts")
            if WorkoutHealthExport.shared.needsAccess { HealthWriteAccessHint() }

            Divider().overlay(Theme.separator)
            StatRow(title: "Last sync", value: model.lastSyncText)
            StatRow(title: "Device ID", value: model.deviceIDText)
            if model.isSyncing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                    Text(model.syncProgress)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            switch model.syncNotice {
            case .retrying(let notice):
                InlineMessage(message: notice, systemImage: "clock.arrow.circlepath")
            case .failed(let message, let details):
                InlineMessage(message: message, systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                              details: details)
            case nil:
                EmptyView()
            }
            HStack(spacing: 10) {
                PrimaryButton(title: "Sync now", style: .secondary, busy: model.isSyncing) { await model.syncNow() }
                PrimaryButton(title: "Full re-sync", style: .destructive) { showResyncConfirm = true }
            }
            .disabled(!model.canSync)
            NavigationLink {
                SyncDetailsView(model: model.syncDetails)
            } label: {
                Label("Sync details", systemImage: "list.bullet.rectangle")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("profile.syncDetails")

            // The training import: in, then Export: out (ui.md §3.2).
            ImportProfileRows()
            if model.canExport {
                PrimaryButton(title: "Export my data", style: .secondary, busy: model.exporting) { await model.export() }
                    .accessibilityHint(Text("Creates a JSON file of your scores, workouts and sessions to share or save"))
                if let error = model.exportError {
                    InlineMessage(message: error, systemImage: "square.and.arrow.up")
                }
            }

            Divider().overlay(Theme.separator)
            // Off with workouts logged in the demo asks first; the switch reads on until the exit has run.
            Toggle(isOn: Binding(get: { model.demoMode }, set: { on in
                guard !on else {
                    Task { await model.setDemoMode(true) }
                    return
                }
                switch model.switchingDemoOff() {
                case .confirm(let workouts): confirmDemoExit = workouts
                case .exit: Task { await model.endDemo() }
                case .refused: break // the switch stays on, and the message under it says why
                }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Demo data")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Show a realistic sample history instead of your server.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("profile.demoMode")
            .accessibilityHint(!model.showsDemoExitHint ? Text(verbatim: "")
                : Text("Turning it off discards the workouts logged with Demo data.",
                       comment: "Only while such workouts exist"))
            if let error = model.demoExitError {
                InlineMessage(message: error, systemImage: "exclamationmark.circle")
            }
        }
    }

    // MARK: notifications

    private var notifications: some View {
        ProfileSection(title: "Notifications") {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                HStack {
                    Text("Categories and quiet hours").font(.ryft(.callout)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.notifications")
        }
    }

    // MARK: training

    private var training: some View {
        ProfileSection(title: "Training") {
            Toggle(isOn: Bindable(settings).jumpToNextExercise) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advance to the next exercise",
                         comment: "Profile → Training toggle: after the last set of an exercise, the workout moves on to the next one.")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Jumps to the next set when you finish an exercise.",
                         comment: "Footer under the Profile → Training toggle \"Advance to the next exercise\".")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("profile.jumpToNext")
            if model.showsSessionLayout { sessionLayout }
        }
    }

    private var sessionLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session layout", comment: "Profile → Training: how a workout shows its exercises, one per page or all in one list.")
                .font(.ryft(.body))
                .foregroundStyle(Theme.textPrimary)
            SegmentedPicker(selection: Bindable(settings).sessionLayout, options: SessionLayout.allCases, title: \.title)
                .accessibilityIdentifier("profile.sessionLayout")
            Text("Focused: one exercise at a time. List: all exercises on one screen. Applies the next time you open a workout.",
                 comment: "Footer under Profile → Training → Session layout.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: journal

    private var journal: some View {
        ProfileSection(title: "Journal") {
            NavigationLink {
                JournalSettingsView(store: screens.journal)
            } label: {
                HStack {
                    Text("Behaviors to track").font(.ryft(.callout)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.journal")
        }
    }

    // MARK: display

    /// The hero numbers' look (L19, design.md §P4-6): it applies at once, the screens read the observable `Settings`.
    private var display: some View {
        ProfileSection(title: "Display") {
            HeroNumeralsRow(selection: Bindable(settings).heroNumerals)
            Text("Large numbers on Today, Sleep and Strain.",
                 comment: "Footer under Profile → Display → Hero numbers: where the dots or thin digits show.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: about

    private var about: some View {
        ProfileSection(title: "About") {
            BrandLockup()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            StatRow(title: "Version", value: Self.version)
            Text("RYFT is a wellness tool, not a medical device. Talk to a doctor about health concerns.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Theme.separator)
            NavigationLink {
                ReportProblemView(model: model.report)
            } label: {
                ReportProblemRow(waiting: model.report.waiting)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.reportProblem")
            .task { model.report.reloadWaiting() }
            LinkRow(title: "Privacy Policy", url: LegalPage.privacy.url)
            LinkRow(title: "Terms of Use", url: LegalPage.terms.url)
            NavigationLink {
                LicensesView()
            } label: {
                HStack {
                    Text("Licences").font(.ryft(.callout)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider().overlay(Theme.separator)
            if !model.devices.isEnabled {
                LinkRow(title: "Garmin Connect and Apple Health", url: URL(string: "https://support.garmin.com/?q=apple%20health"))
            }
            LinkRow(title: "Apple Health privacy", url: URL(string: "https://www.apple.com/legal/privacy/data/en/health-app/"))
        }
    }

    static var version: String { AppInfo.version }
}

// MARK: - building blocks

private struct FieldLabel: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .padding(.bottom, -6)
    }
}

private struct ProviderBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.surfaceRaised, in: Capsule())
    }
}

private extension View {
    func ryftField() -> some View {
        font(.ryft(.body))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview("Profile · dark") {
    ProfileView().previewEnvironment()
}

/// Profile → Data's first row while `devices.setup` is on: "Devices & sync", and what's chosen.
private struct DevicesRowLabel: View {
    let summary: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            SettingRowLabel(title: "Devices & sync", value: summary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Profile · Data row · dark") {
    ProfileView().previewEnvironment(AppState.preview(flags: [.devicesSetup: true]))
}
