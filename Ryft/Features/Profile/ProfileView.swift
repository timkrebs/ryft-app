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
    @State private var showDeleteConfirm = false
    @State private var showChangePassword = false
    @State private var showWithdrawConfirm = false
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
                if model.showsNotifications { notifications }
                if screens.journal.isLive { journal }
                appearance
                about
                #if DEBUG
                developer
                #endif
            }
        }
        .safariSheet($legal)
        .sheet(item: Bindable(model).exported) { ShareSheet(items: [$0.url]).presentationDetents([.medium, .large]) }
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
            Button("Log out", role: .destructive) {
                Task { await model.logOut() }
            }
        } message: {
            Text("Cached scores and Health sync progress are removed from this iPhone. Your account and data stay on the RYFT platform.")
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
                PrimaryButton(title: "Log out", style: .secondary) { showLogOutConfirm = true }
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
            TextField(Bundle.configValue("RyftAPIURL") ?? "https://api.ryftapp.de", text: Bindable(settings).devAPIURLOverride)
                .ryftField()
                .keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            FieldLabel("Ingest URL override (compose: :8081)")
            TextField("Same host as the API", text: Bindable(settings).devIngestURLOverride)
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

            if model.canExport {
                PrimaryButton(title: "Export my data", style: .secondary, busy: model.exporting) { await model.export() }
                    .accessibilityHint(Text("Creates a JSON file of your scores, workouts and sessions to share or save"))
                if let error = model.exportError {
                    InlineMessage(message: error, systemImage: "square.and.arrow.up")
                }
            }

            Divider().overlay(Theme.separator)
            Toggle(isOn: Binding(get: { model.demoMode }, set: { on in Task { await model.setDemoMode(on) } })) {
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

    // MARK: appearance & about

    private var appearance: some View {
        ProfileSection(title: "Appearance") {
            SegmentedPicker(selection: Bindable(settings).appearance, options: Settings.Appearance.allCases) { a in
                switch a {
                case .dark: return String(localized: "Dark")
                case .light: return String(localized: "Light")
                case .system: return String(localized: "System")
                }
            }
        }
    }

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

/// Profile → Data → Sync details: what the sync knows, stream by stream, the last requests
/// with their IDs, and "Sync last 3 days again", "Full resync", "Copy diagnostics".
struct SyncDetailsView: View {
    let model: SyncDetailsModel
    @State private var showResyncConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                engine
                loadedData
                streams
                requests
                actions
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("Sync details"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadQueue() }
        .confirmationDialog("Re-upload the last 90 days of Health data?", isPresented: $showResyncConfirm,
                            titleVisibility: .visible) {
            Button("Re-sync", role: .destructive) {
                Task { await model.fullResync() }
            }
        } message: {
            Text("This uploads everything again. It can take a few minutes on the first run.")
        }
    }

    private var engine: some View {
        ProfileSection(title: "Engine") {
            StatRow(title: "State", value: model.phaseText)
            StatRow(title: "Scoring", value: model.scoringText, detail: model.scoringIsSlow ? String(localized: "Taking longer than usual") : nil)
            StatRow(title: "Queue", value: model.queueText)
            StatRow(title: "Backlog", value: model.backlogText)
            StatRow(title: "Uploaded", value: model.uploadedText)
            if model.engine.pendingDeletions > 0 {
                StatRow(title: "Deletions kept", value: model.engine.pendingDeletions.formatted())
            }
            if let error = model.lastErrorText {
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.warning)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the app reads (uploads are Streams): when each loaded, and how its last fetches went.
    private var loadedData: some View {
        ProfileSection(title: "Loaded data") {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.resources) { row in
                        LoadedDataRow(row: row, now: context.date)
                    }
                }
            }
        }
    }

    private var streams: some View {
        ProfileSection(title: "Streams") {
            ForEach(model.streams) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text((row.progress?.sent ?? 0).formatted())
                            .font(.ryft(.callout))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(row.newestText)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                    if let last = row.lastPageText {
                        Text(last)
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var requests: some View {
        ProfileSection(title: "Last requests") {
            if model.requests.isEmpty {
                Text("No requests since launch.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(model.requests) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(r.transport ?? String(r.status))\(r.code.map { " \($0)" } ?? "") \(r.method) \(redactedPath(r.path))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle((200..<300).contains(r.status) ? Theme.textSecondary : Theme.warning)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: "\(r.requestID ?? "–") · \(r.date.formatted(date: .omitted, time: .standard))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Sync last 3 days again", style: .secondary) { await model.resendRecent() }
                .disabled(!model.canSync)
            PrimaryButton(title: "Full resync", style: .destructive) { showResyncConfirm = true }
                .disabled(!model.canSync)
            PrimaryButton(title: model.copied ? "Copied" : "Copy diagnostics", style: .secondary) {
                model.copyDiagnostics()
            }
            .accessibilityHint(Text("Counts, dates and request IDs for support; no health data"))
        }
    }
}

/// Sync details as a sheet (Today's status line): its own stack and "Done".
struct SyncDetailsSheet: View {
    let model: SyncDetailsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SyncDetailsView(model: model)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// One resource in Sync details → Loaded data: name and load time, then its last error or "No errors".
private struct LoadedDataRow: View {
    let row: SyncDetailsModel.ResourceRow
    let now: Date
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            layout {
                Text(row.name)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                if !typeSize.isAccessibilitySize { Spacer() }
                Text(row.fetchedText(now: now))
                    .font(.ryft(.callout))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(row.statusText(now: now))
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(row.isWarning ? Theme.warning
                                 : row.state.consecutiveFailures > 0 ? Theme.textSecondary : Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.spoken(now: now)))
        .accessibilityIdentifier("syncDetails.loaded.\(row.id)")
    }
}

// MARK: - body settings (shared by onboarding, Sleep and Profile)

/// Which setting's editor is open.
enum BodySetting: String, Identifiable {
    case sleepBase, maxHR
    var id: String { rawValue }
}

extension View {
    /// The editor for `item` as a sheet.
    func bodySettingSheet(_ item: Binding<BodySetting?>, editor: BodySettingsEditor) -> some View {
        sheet(item: item) { setting in
            NavigationStack {
                switch setting {
                case .sleepBase: BaselineSleepNeedForm(editor: editor, showsClose: true)
                case .maxHR: MaxHeartRateForm(editor: editor, showsClose: true)
                }
            }
            .presentationDetents([.large])
        }
    }
}

/// A setting you can tap: title and value, where the value comes from underneath, a chevron.
struct SettingRow: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingRowLabel(title: title, value: value, detail: detail)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the editor"))
    }
}

/// `SettingRow`'s look, for a `NavigationLink` too. At accessibility sizes the value goes
/// under the title instead of fighting it for the line.
struct SettingRowLabel: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.ryft(.body))
                                .foregroundStyle(Theme.textPrimary)
                            Text(value)
                                .font(.ryft(.body))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Spacer(minLength: 8)
                    } else {
                        Text(title)
                            .font(.ryft(.body))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 8)
                        Text(value)
                            .font(.ryft(.body))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
                if let detail {
                    Text(detail)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }
}

/// A big value between − and +; VoiceOver adjusts it by swiping up and down.
struct SettingStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let label: LocalizedStringKey
    let text: (Int) -> String
    /// The − and + grow with the text.
    @ScaledMetric(relativeTo: .title) private var buttonSize: CGFloat = 48
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func change(by delta: Int) {
        withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick)) {
            value = min(range.upperBound, max(range.lowerBound, value + delta))
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            button("minus", enabled: value > range.lowerBound) { change(by: -step) }
            Text(text(value))
                .font(.ryft(.numberLarge))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: Double(value)))
                .frame(minWidth: 150)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            button("plus", enabled: value < range.upperBound) { change(by: step) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(text(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(by: step)
            case .decrement: change(by: -step)
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(.title3, weight: .semibold))
                .frame(width: buttonSize, height: buttonSize)
                .background(Theme.surfaceRaised, in: Circle())
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Baseline sleep need: 15-minute steps, 4–12 h. In a sheet (`showsClose`) or pushed from
/// Sleep's need breakdown.
struct BaselineSleepNeedForm: View {
    let editor: BodySettingsEditor
    var showsClose = false
    @Environment(\.dismiss) private var dismiss
    @State private var draft = BodySettingsEditor.defaultSleepBase
    /// Edited by hand: no longer follows the saved value.
    @State private var touched = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingStepper(value: drafted, range: BodySettingsEditor.sleepBaseRange, step: BodySettingsEditor.sleepBaseStep,
                             label: "Baseline sleep need") { Fmt.duration(minutes: $0) }
                    .padding(.vertical, 8)
                if let source = editor.sleepBaseSourceText {
                    Label(source, systemImage: "info.circle")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("Each night's sleep need starts from this baseline, plus top-ups for strain and sleep debt, minus naps. RYFT adjusts it from your nights unless you set it.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if editor.canUseLearnedBase {
                    Button(editor.usesLearnedTitle) {
                        Task {
                            await editor.useLearnedSleepBase()
                            reset()
                        }
                    }
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                    .disabled(editor.isBusy)
                }
                SettingSaveFooter(editor: editor)
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("Baseline sleep need"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { SheetTitle(text: "Baseline sleep need") }
            if showsClose {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await editor.setSleepBase(draft)
                        reset()
                    }
                }
                .disabled(draft == editor.sleepBase || editor.isBusy || !editor.canSave)
                    .accessibilityIdentifier("sleepBase.save")
            }
        }
        .onAppear {
            editor.begin()
            reset()
        }
        // The account arrived (or changed) while the form was open: follow it until edited.
        .onChange(of: editor.sleepBase) { if !touched { draft = editor.sleepBase } }
    }

    /// Back to what's saved: after a save (taken or refused) or going back to learned.
    private func reset() {
        draft = editor.sleepBase
        touched = false
    }

    private var drafted: Binding<Int> {
        Binding(get: { draft }, set: { draft = $0; touched = true })
    }
}

/// Maximum heart rate: 100–230 bpm.
struct MaxHeartRateForm: View {
    let editor: BodySettingsEditor
    var showsClose = false
    @Environment(\.dismiss) private var dismiss
    @State private var draft = BodySettingsEditor.defaultMaxHR
    @State private var touched = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingStepper(value: drafted, range: BodySettingsEditor.maxHRRange, step: 1,
                             label: "Maximum heart rate") { "\($0) bpm" }
                    .padding(.vertical, 8)
                if let source = editor.maxHRSourceText {
                    Label(source, systemImage: "info.circle")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("Strain and heart-rate zones are measured against it. If you know yours from a test, set it here.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if editor.canUseMaxHREstimate {
                    Button("Use the estimate") {
                        Task {
                            await editor.useMaxHREstimate()
                            reset()
                        }
                    }
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                    .disabled(editor.isBusy)
                }
                SettingSaveFooter(editor: editor)
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("Maximum heart rate"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { SheetTitle(text: "Maximum heart rate") }
            if showsClose {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await editor.setMaxHR(draft)
                        reset()
                    }
                }
                .disabled(draft == editor.maxHR || editor.isBusy || !editor.canSave)
            }
        }
        .onAppear {
            editor.begin()
            reset()
        }
        .onChange(of: editor.maxHR) { if !touched { draft = editor.maxHR } }
    }

    private func reset() {
        draft = editor.maxHR
        touched = false
    }

    private var drafted: Binding<Int> {
        Binding(get: { draft }, set: { draft = $0; touched = true })
    }
}

/// A sheet's title between its two buttons: smaller rather than cut off (German runs long).
struct SheetTitle: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Under an editor: a refusal, or after a save that past days keep their scores, with the
/// offer to rescore them.
private struct SettingSaveFooter: View {
    let editor: BodySettingsEditor

    var body: some View {
        if editor.saving {
            ProgressView().tint(Theme.accent)
        }
        if let error = editor.error {
            InlineMessage(message: error, systemImage: "exclamationmark.circle", details: editor.errorDetails)
                .accessibilityIdentifier("bodySettings.error")
        }
        if editor.savedChange || editor.rescoreStatus != nil {
            VStack(alignment: .leading, spacing: 10) {
                if editor.savedChange {
                    Label("Saved. Past days keep their scores until you rescore them.", systemImage: "checkmark.circle")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PrimaryButton(title: "Rescore the last 90 days", style: .secondary, busy: editor.rescoring) {
                    await editor.rescore()
                }
                .disabled(editor.saving)
                RescoreStatus(editor: editor)
            }
        }
    }
}

/// How the rescore went; a failure with its request ID.
private struct RescoreStatus: View {
    let editor: BodySettingsEditor

    var body: some View {
        if let details = editor.rescoreDetails, let status = editor.rescoreStatus {
            InlineMessage(message: status, systemImage: "exclamationmark.circle", details: details)
        } else if let status = editor.rescoreStatus {
            Text(status)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct ProfileSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).ryftLabelStyle()
                // A label, not a headline: past AX3 it would crowd out the content.
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            Card {
                VStack(alignment: .leading, spacing: 14) { content() }
            }
        }
    }
}

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

private struct LinkRow: View {
    let title: LocalizedStringKey
    let url: URL?

    var body: some View {
        if let url {
            Link(destination: url) {
                HStack {
                    Text(title)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
    }
}

struct PrimaryButton: View {
    enum Style { case primary, secondary, destructive }

    let title: Text
    var style: Style = .primary
    var busy = false
    let action: () async -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(title: LocalizedStringKey, style: Style = .primary, busy: Bool = false, action: @escaping () async -> Void) {
        self.init(text: Text(title), style: style, busy: busy, action: action)
    }

    /// A title that holds outside text (a tracker's app name from the catalog): never parsed as a key or Markdown.
    init(verbatim title: String, style: Style = .primary, busy: Bool = false, action: @escaping () async -> Void) {
        self.init(text: Text(verbatim: title), style: style, busy: busy, action: action)
    }

    private init(text: Text, style: Style, busy: Bool, action: @escaping () async -> Void) {
        title = text
        self.style = style
        self.busy = busy
        self.action = action
    }

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            ZStack {
                if busy {
                    ProgressView().controlSize(.small).tint(foreground)
                } else {
                    title
                        .font(.ryft(.callout))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(background, in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(busy)
    }

    private var foreground: Color {
        switch style {
        case .primary: return Theme.onAccent
        case .secondary: return Theme.textPrimary
        case .destructive: return Theme.alert
        }
    }

    private var background: Color {
        switch style {
        case .primary: return Theme.accent
        case .secondary: return Theme.surfaceRaised
        case .destructive: return Theme.alert.opacity(0.14)
        }
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

#Preview("Baseline sleep need · dark") {
    let state = AppState.preview()
    NavigationStack { BaselineSleepNeedForm(editor: BodySettingsEditor(state: state), showsClose: true) }
        .previewEnvironment(state)
}

#Preview("Baseline sleep need · light · de") {
    let state = AppState.preview()
    NavigationStack { BaselineSleepNeedForm(editor: BodySettingsEditor(state: state), showsClose: true) }
        .previewEnvironment(state, scheme: .light)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Maximum heart rate · dark") {
    let state = AppState.preview()
    NavigationStack { MaxHeartRateForm(editor: BodySettingsEditor(state: state), showsClose: true) }
        .previewEnvironment(state)
}

#Preview("Maximum heart rate · light") {
    let state = AppState.preview()
    NavigationStack { MaxHeartRateForm(editor: BodySettingsEditor(state: state), showsClose: true) }
        .previewEnvironment(state, scheme: .light)
}

#Preview("Sync details · dark") {
    let state = AppState.preview()
    let sync = SyncService(env: state.env)
    NavigationStack {
        SyncDetailsView(model: SyncDetailsModel(state: state, sync: sync,
                                                coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                             clock: state.env.clock)))
    }
    .previewEnvironment(state)
}

#Preview("Sync details · light · de") {
    let state = AppState.preview()
    let sync = SyncService(env: state.env)
    NavigationStack {
        SyncDetailsView(model: SyncDetailsModel(state: state, sync: sync,
                                                coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                             clock: state.env.clock)))
    }
    .previewEnvironment(state, scheme: .light)
    .environment(\.locale, Locale(identifier: "de"))
}

/// Loaded data in every row state: fine, one failure, three in a row, never loaded.
private enum SyncDetailsPreview {
    @MainActor
    static func seed(_ reads: ReadScheduler) {
        let now = Date.now
        func error(_ status: Int?, _ minutesAgo: Double) -> ResourceError {
            ResourceError(kind: .transient, status: status, code: nil, requestID: "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c",
                          transport: status == nil ? "timedOut" : nil, attempts: 3, at: now.addingTimeInterval(-minutesAgo * 60))
        }
        reads.seed([
            .history: ResourceState(fetchedAt: now.addingTimeInterval(-600)),
            .me: ResourceState(fetchedAt: now.addingTimeInterval(-7_200), lastError: error(503, 0.2), consecutiveFailures: 3),
            .syncStatus: ResourceState(fetchedAt: now.addingTimeInterval(-60)),
            .trends: ResourceState(fetchedAt: now.addingTimeInterval(-900), lastError: error(nil, 2), consecutiveFailures: 1),
            .insights: ResourceState(fetchedAt: now.addingTimeInterval(-900)),
            .config: ResourceState(fetchedAt: now.addingTimeInterval(-3_600)),
        ])
    }
}

#Preview("Sync details · loaded data · dark") {
    let state = AppState.preview()
    let sync = SyncService(env: state.env)
    SyncDetailsPreview.seed(state.env.reads)
    return NavigationStack {
        SyncDetailsView(model: SyncDetailsModel(state: state, sync: sync,
                                                coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                             clock: state.env.clock)))
    }
    .previewEnvironment(state)
}

#Preview("Sync details · loaded data · light · de · AX3") {
    let state = AppState.preview()
    let sync = SyncService(env: state.env)
    SyncDetailsPreview.seed(state.env.reads)
    return NavigationStack {
        SyncDetailsView(model: SyncDetailsModel(state: state, sync: sync,
                                                coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                             clock: state.env.clock)))
    }
    .previewEnvironment(state, scheme: .light)
    .environment(\.locale, Locale(identifier: "de"))
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Profile · dark") {
    ProfileView().previewEnvironment()
}

#Preview("Profile · light") {
    ProfileView().previewEnvironment(scheme: .light)
}

// MARK: - check sync

/// Check sync (ui.md §5): per selected tracker, what reached Apple Health in the last 48 hours, the expected gaps
/// as plain facts, and the fix for an unexpected one. Pushed from Devices & sync, or inline in onboarding's setup
/// step (`embedded`: no scroll view of its own, Check again under the cards). Runs on appearance.
struct TrackerCheckView: View {
    @State private var model: TrackerCheckModel
    private let embedded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    init(model: TrackerCheckModel, embedded: Bool = false) {
        _model = State(initialValue: model)
        self.embedded = embedded
    }

    private var text: TrackerCheckText { TrackerCheckText(locale: locale) }

    var body: some View {
        Group {
            if embedded {
                VStack(alignment: .leading, spacing: 16) {
                    content
                    checkAgain
                }
            } else {
                ScrollView {
                    content
                        .padding(.horizontal, Theme.Metrics.screenPadding)
                        .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
                // Pinned, so it's reachable at every text size.
                .safeAreaInset(edge: .bottom) {
                    checkAgain
                        .padding(.horizontal, Theme.Metrics.screenPadding)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .background(Theme.background)
                }
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle(Text("Check sync"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await model.start(stagger: !reduceMotion) }
        .onChange(of: model.phase) { _, phase in
            // One announcement when it's done; the rows stay silent while they resolve.
            guard phase == .done else { return }
            AccessibilityNotification.Announcement(text.announcement(model.checks)).post()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Looks at the last 48 hours in Apple Health. The check uploads nothing.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            switch model.phase {
            case .notAsked:
                notAsked
            case .unavailable:
                note("Apple Health isn't available on this device.", systemImage: "heart.slash")
            case .locked:
                note("Unlock your iPhone to check: Apple Health can't be read while it's locked.", systemImage: "lock")
            case .failed:
                note("Apple Health couldn't be read this time. Tap Check again.", systemImage: "exclamationmark.triangle")
            case .idle, .running, .done:
                ForEach(model.checks) { check in
                    if let tracker = model.trackers.first(where: { $0.id == check.trackerID }) {
                        TrackerCheckCard(check: check, tracker: tracker, healthAccess: model.catalog.healthAccess.value(for: locale.identifier),
                                         now: model.checkedAt ?? model.now, text: text)
                    }
                }
                if model.showsPermissionCard { permissionCard }
            }
        }
    }

    private var checkAgain: some View {
        PrimaryButton(title: model.isRunning ? "Checking…" : "Check again") { await model.run(stagger: !reduceMotion) }
            .disabled(model.isRunning || model.phase == .unavailable)
            .accessibilityLabel(model.isRunning ? Text("Checking") : Text("Check again"))
            .accessibilityIdentifier("check.run")
    }

    /// D2 K9: not an error, one action.
    private var notAsked: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RYFT hasn't asked for Health access yet.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Allow access", style: .secondary) { await model.requestAccess() }
                .accessibilityIdentifier("check.allow")
        }
        .checkPanel()
    }

    private func note(_ text: LocalizedStringKey, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .checkPanel()
        .accessibilityIdentifier("check.note")
    }

    /// D2 K7, last: iOS tells RYFT nothing about read access, so both possibilities and where to look; never
    /// "denied" (ui.md errata 5). The Health app opens at its start screen: the catalog's path goes with it.
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    if model.mayNotRead {
                        Text("Even your iPhone's steps aren't arriving, so RYFT may not be allowed to read Health.")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("check.mayNotRead")
                    }
                    // swiftlint:disable:next line_length
                    Text("iOS doesn't tell apps whether they may read Health data: RYFT only sees what it's allowed to read. So “nothing yet” can mean no data, or that RYFT isn't allowed to read it.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    CheckSteps(steps: model.catalog.healthAccess.value(for: locale.identifier))
                }
            }
            PrimaryButton(title: "Open Health", style: .secondary) { HealthLinks.open(with: openURL) }
                .accessibilityIdentifier("check.openHealth")
        }
        .checkPanel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("check.permission")
    }
}

/// One tracker in Check sync: header, summary, rows, and the fix under the last gap; silent, can't-read, Other and an
/// Apple device RYFT can't tell apart say so instead of a list.
private struct TrackerCheckCard: View {
    let check: TrackerCheck
    let tracker: Tracker
    /// The catalog's steps for RYFT's own read permission.
    let healthAccess: [String]
    let now: Date
    let text: TrackerCheckText

    @State private var showsDetails = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .headline) private var headerGlyph: CGFloat = 17
    @ScaledMetric(relativeTo: .headline) private var headerGlyphWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .callout) private var trayGlyph: CGFloat = 28
    /// "That's normal." lines up with the row names: CheckRow's glyph column (scaled like there) plus its 10 pt.
    @ScaledMetric(relativeTo: .callout) private var rowGlyphWidth: CGFloat = 24

    private var app: String { check.app ?? tracker.name }
    /// Only a vendor's app has a store page to send people to.
    private var storeURL: URL? { tracker.integration == .vendorApp ? tracker.appStoreURL : nil }
    private var steps: [String] { tracker.setup.value(for: locale.identifier) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header
                switch check.overall {
                case .cantRead:
                    Text("RYFT can't read \(tracker.name) data on iPhone today.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .unidentified:
                    Text(verbatim: text.unidentified)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("check.unidentified")
                case .silent:
                    silent
                case .unknownTracker:
                    unknown
                case .checking, .ok, .nightMissing, .needsFix:
                    summary
                    rows
                }
            }
            .animation(Theme.Motion.respecting(reduceMotion), value: check.overall)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: check.app ?? tracker.name))
        .accessibilityIdentifier("check.card.\(tracker.id)")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(tracker))
                .font(.system(size: headerGlyph, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: headerGlyphWidth)
                .accessibilityHidden(true)
            Text(verbatim: tracker.name)
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Numbers first; then, without last night, where it is.
    @ViewBuilder private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if check.overall == .checking {
                    Text("Checking Apple Health…")
                } else {
                    Text(verbatim: text.summary(expected: check.expected, arriving: check.arriving, needsFix: check.needsFix))
                }
            }
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .accessibilityIdentifier("check.summary")
            if check.overall == .nightMissing {
                Group {
                    if storeURL == nil {
                        Text("Last night hasn't reached Apple Health yet.")
                    } else {
                        Text("Last night hasn't reached Apple Health yet. Open \(app) to sync it.")
                    }
                }
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The rows; "That's normal." once, under the first expected gap; the fix once, under the last unexpected one.
    /// Just my iPhone folds what an iPhone can't record into one quiet row (D2 C3).
    private var rows: some View {
        let phone = tracker.id == "iphone" && check.overall != .checking
        let shown = phone ? check.rows.filter { $0.check.isArrived || $0.check.isMissing || $0.signal == .steps } : check.rows
        let firstExpected = shown.first { $0.check == .notShared }?.signal
        let lastMissing = shown.last(where: \.check.isMissing)?.signal
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { row in
                if row.signal != shown.first?.signal { hairline }
                checkRow(row)
                    .accessibilityIdentifier("check.row.\(row.signal.rawValue)")
                if row.signal == firstExpected {
                    Text("That's normal.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, rowGlyphWidth + 10)
                        .padding(.bottom, 8)
                }
                if row.signal == lastMissing {
                    fix.padding(.bottom, 8)
                }
            }
            if phone {
                hairline
                CheckRow(name: String(localized: "Other signals", bundle: text.bundle, locale: locale),
                         result: String(localized: "not available from an iPhone", bundle: text.bundle, locale: locale),
                         kind: .expected)
            }
        }
    }

    private func checkRow(_ row: TrackerCheck.Row) -> CheckRow {
        CheckRow(name: text.name(row.signal),
                 result: text.result(row.check, signal: row.signal, app: check.app, now: now),
                 kind: CheckRow.Kind(row.check),
                 spoken: text.spoken(row.check, signal: row.signal, app: check.app, now: now))
    }

    private var hairline: some View {
        Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline).accessibilityHidden(true)
    }

    /// The vendor's permission first, then RYFT's when RYFT can't see the type at all (§4.5); the steps inline
    /// (ui.md errata 4).
    private var fix: some View {
        let unknown = check.rows.contains { $0.check == .missing(visible: false) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: text.fixLead(check))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            CheckSteps(steps: steps + (unknown ? healthAccess : []))
            buttons(health: unknown, outlined: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("check.fix")
    }

    /// "{app} in the App Store" (it opens the store page, which says "Open" when the app is installed; ui.md
    /// errata 2) and "Open Health". In the raised fix panel they're outlined, or they'd have no shape (errata 4).
    @ViewBuilder private func buttons(health: Bool, outlined: Bool) -> some View {
        if let storeURL {
            PrimaryButton(title: "\(app) in the App Store", style: .secondary) { openURL(storeURL) }
                .overlay { if outlined { Capsule().strokeBorder(Theme.textTertiary, lineWidth: Theme.Metrics.hairline) } }
                .accessibilityIdentifier("check.openApp")
        }
        if health {
            PrimaryButton(title: "Open Health", style: .secondary) { HealthLinks.open(with: openURL) }
                .overlay { if outlined { Capsule().strokeBorder(Theme.textTertiary, lineWidth: Theme.Metrics.hairline) } }
        }
    }

    /// D2 K5: what to do first, the usual cause for a vendor app, and the rows behind Show details. An Apple device
    /// is worn, not opened.
    private var silent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: trayGlyph, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(verbatim: text.silent(check))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("check.silent")
            buttons(health: false, outlined: false)
            if storeURL != nil {
                Text("If it still shows nothing after it has synced, the Apple Health permission is the usual cause.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(showsDetails ? "Hide details" : "Show details") { showsDetails.toggle() }
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityIdentifier("check.details")
            if showsDetails {
                CheckSteps(steps: steps)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(check.rows) { checkRow($0) }
                }
            }
        }
    }

    /// D2 C4: only what apps the catalog doesn't know sent; nothing promised, nothing missing.
    @ViewBuilder private var unknown: some View {
        if check.rows.isEmpty {
            Text(verbatim: text.silent(check))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("check.silent")
        } else {
            Text("From apps RYFT doesn't know yet:")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(check.rows) { row in
                    checkRow(row).accessibilityIdentifier("check.row.\(row.signal.rawValue)")
                }
            }
        }
    }

    /// By tracker id, never by form (ui.md errata 1): Apple's product glyphs only for Apple's own products, so a
    /// remote catalog entry can never get one. The same mapping as T2's tiles.
    static func symbol(_ tracker: Tracker) -> String {
        switch tracker.id {
        case "apple_watch": return "applewatch"
        case "iphone": return "iphone"
        default: break
        }
        guard tracker.integration != .unknown else { return "ellipsis.circle" }
        switch tracker.form {
        case .watch: return "watch.analog"
        case .ring: return "circle.circle"
        case .band: return "figure.run.circle"
        case .phone, .other: return "ellipsis.circle"
        }
    }
}

/// Catalog steps, numbered: plain text only (design.md §2.5).
private struct CheckSteps: View {
    let steps: [String]
    @ScaledMetric(relativeTo: .caption) private var badge: CGFloat = 18

    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: "\(index + 1)")
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                            .frame(width: badge, height: badge)
                            .background(Theme.accent.opacity(0.14), in: Circle())
                            .accessibilityHidden(true)
                        Text(verbatim: step)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private extension View {
    /// Check sync's own panels (not a tracker): the inline-message surface.
    func checkPanel() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
    }
}

/// A check on mock data, run on appearance like the real one. `de` shows the German words, not only German formats.
@MainActor
private func checkPreview(_ scenario: SyncCheckScenario, scheme: ColorScheme = .dark, de: Bool = false,
                          size: DynamicTypeSize = .large,
                          stage: ((TrackerCheckModel) -> Void)? = nil) -> some View {
    let env = AppEnvironment.preview()
    let model = TrackerCheckModel(env: env, health: scenario.store(now: .now), trackers: scenario.trackers)
    stage?(model)
    return NavigationStack { TrackerCheckView(model: model) }
        .previewEnvironment(scheme: scheme)
        .environment(\.locale, Locale(identifier: de ? "de_DE" : "en_US"))
        .environment(\.dynamicTypeSize, size)
}

#Preview("Check sync · Garmin · dark") { checkPreview(.garmin) }
#Preview("Check sync · Garmin · light") { checkPreview(.garmin, scheme: .light) }
#Preview("Check sync · Garmin · light · de") { checkPreview(.garmin, scheme: .light, de: true) }
#Preview("Check sync · Garmin · AX3") { checkPreview(.garmin, size: .accessibility3) }
#Preview("Check sync · sleep should arrive · dark") { checkPreview(.garminSleepOff) }
#Preview("Check sync · sleep should arrive · light") { checkPreview(.garminSleepOff, scheme: .light) }
#Preview("Check sync · night missing · dark") { checkPreview(.garminNightMissing) }
#Preview("Check sync · silent · dark") { checkPreview(.garminSilent) }
#Preview("Check sync · silent · light · de") { checkPreview(.garminSilent, scheme: .light, de: true) }
#Preview("Check sync · nothing readable · dark") { checkPreview(.nothingReadable) }
#Preview("Check sync · Apple Watch · light") { checkPreview(.appleWatch, scheme: .light) }
#Preview("Check sync · running · dark") { checkPreview(.garmin) { $0.stage(.running) } }
#Preview("Check sync · running · light") { checkPreview(.garmin, scheme: .light) { $0.stage(.running) } }
#Preview("Check sync · not asked · dark") { checkPreview(.garmin) { $0.stage(.notAsked) } }
#Preview("Check sync · locked · light") { checkPreview(.garmin, scheme: .light) { $0.stage(.locked) } }

// MARK: - report a problem

/// Profile → About's first row: "Report a problem", and what's still waiting to send.
struct ReportProblemRow: View {
    let waiting: Int
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    status
                }
                Spacer(minLength: 8)
            } else {
                title
                Spacer(minLength: 8)
                status
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Text("Report a problem")
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textPrimary)
    }

    @ViewBuilder private var status: some View {
        if waiting > 0 {
            Text("\(waiting) waiting to send")
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Profile → About → Report a problem (ui.md §5): a message, what it's about, and diagnostics that help find
/// the cause, never a health value. Pushed from Profile, or from an error's Details (`context`), pre-filled.
/// `sent` and `queued` replace the form; a refusal shows on it, with the message kept.
struct ReportProblemView: View {
    let model: ReportProblemModel
    var context: ReportContext?
    /// "What's included" open from the start (previews).
    var showsIncluded = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editing: Bool
    @AccessibilityFocusState private var outcomeFocused: Bool
    @State private var included = false
    @State private var prepared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                switch model.result {
                case .sent?, .queued?:
                    outcome.transition(.opacity)
                default:
                    form.transition(.opacity)
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 16)
            .animation(Theme.Motion.respecting(reduceMotion), value: model.result)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("Report a problem"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editing = false }
            }
        }
        .sensoryFeedback(.success, trigger: model.result) { _, new in new == .sent }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            included = showsIncluded
            // No keyboard on arrival: from Details the message is written already, and the keyboard would
            // cover what's attached.
            model.prepare(context)
        }
        .onChange(of: model.includeDiagnostics) { _, on in if !on { included = false } }
    }

    // MARK: compose

    @ViewBuilder private var form: some View {
        // The request ID shows only while it's attached.
        if let context = model.context { ReportContextChip(context: context, showsRequestID: model.includeDiagnostics) }
        notice
        Group {
            ProfileSection(title: "Message") { message }
            ProfileSection(title: "Category") { categories }
            ProfileSection(title: "Diagnostics") { diagnostics }
        }
        .disabled(model.sending)
        VStack(alignment: .leading, spacing: 8) {
            PrimaryButton(title: model.sending ? "Sending…" : "Send") { await model.send() }
                .disabled(!model.canSend)
                .accessibilityIdentifier("report.send")
            Text("Reports are limited to 10 a day.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What stopped the report, with the message kept to copy.
    @ViewBuilder private var notice: some View {
        switch model.result {
        case .rateLimited?:
            InlineMessage(message: String(localized: "You've reached today's limit of 10 reports. Your message is kept; try again tomorrow."),
                          systemImage: "clock", retryTitle: "Copy message", details: model.resultDetails) {
                model.copyMessage()
            }
            .accessibilityIdentifier("report.rateLimited")
        case .rejected?:
            InlineMessage(message: String(localized: "RYFT couldn't take this report. Copy your message and try again later."),
                          systemImage: "exclamationmark.circle", retryTitle: "Copy message",
                          details: model.resultDetails) {
                model.copyMessage()
            }
        case .saveFailed?:
            InlineMessage(message: String(localized: "Couldn't save your report. Copy it and try again later."),
                          systemImage: "exclamationmark.circle", retryTitle: "Copy message") {
                model.copyMessage()
            }
        case .signedOut?:
            InlineMessage(message: String(localized: "You're signed out, so this report can't be sent. Your message is kept."),
                          systemImage: "person.crop.circle.badge.exclamationmark", retryTitle: "Copy message") {
                model.copyMessage()
            }
            .accessibilityIdentifier("report.signedOut")
        default:
            EmptyView()
        }
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: Bindable(model).message,
                      prompt: Text("What happened? What did you expect?").foregroundStyle(Theme.textTertiary),
                      axis: .vertical)
                .lineLimit(6...)
                .font(.ryft(.body))
                .foregroundStyle(Theme.textPrimary)
                .focused($editing)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                .background(Theme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
                .accessibilityLabel(Text("Message"))
                .accessibilityIdentifier("report.message")
            if model.showsCount {
                Text("\(model.length) / 4000")
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(model.isTooLong ? Theme.warning : Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text("Please don't type health values you'd rather keep private.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One choice: a check in Teal on the chosen row, "selected" for VoiceOver.
    private var categories: some View {
        VStack(spacing: 0) {
            ForEach(Array(FeedbackCategory.allCases.enumerated()), id: \.element) { index, category in
                if index > 0 { Divider().overlay(Theme.separator) }
                let chosen = model.category == category
                Button {
                    model.category = category
                } label: {
                    HStack(spacing: 12) {
                        Text(Self.title(category))
                            .font(.ryft(.body))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .opacity(chosen ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("report.category.\(category.rawValue)")
            }
        }
    }

    static func title(_ category: FeedbackCategory) -> String {
        switch category {
        case .bug: return String(localized: "Something's broken")
        case .idea: return String(localized: "An idea")
        case .data: return String(localized: "My numbers look wrong")
        case .other: return String(localized: "Something else")
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Bindable(model).includeDiagnostics) {
                Text("Include diagnostics")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("report.diagnostics")
            if model.includeDiagnostics {
                DisclosureGroup(isExpanded: $included) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(included(about: model.context != nil), id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(verbatim: "•").accessibilityHidden(true)
                                Text(item).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityElement(children: .combine)
                        }
                        Text("No health values: no scores, no sleep, heart or workout data, and no times of day from Apple Health.")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    Text("What's included")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(minHeight: 44)
                }
                // Like Sleep's "Why this need": the system disclosure keeps VoiceOver's expanded state.
                .tint(Theme.textSecondary)
                .accessibilityIdentifier("report.included")
            } else {
                Text("Nothing is attached except your message.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "What's included": exactly what `FeedbackPayload` sends, in its order.
    private func included(about context: Bool) -> [String] {
        var rows = [
            String(localized: "App version and build"),
            String(localized: "Device model and iOS version"),
            String(localized: "Language and region"),
            String(localized: "The last 20 requests: method, path without its query, status, error code, request ID, time, duration"),
            String(localized: "Loaded data, per area (Today, History, Profile …): when RYFT last loaded it, and its last error's status, code and request ID"),
            String(localized: "Sync state: phase, queue and backlog, and per data type the number of records and days and the date of the newest record"),
            String(localized: "Account gates and feature flags"),
        ]
        if model.includesTrackers {
            rows.append(String(localized: "What you wear, as RYFT's tracker ids (no device names)"))
        }
        // Only while a recent check would go along.
        if model.syncCheck != nil {
            rows.append(String(localized: "Your last Check sync: its day, and per tracker and data type a result code"))
        }
        if context { rows.append(String(localized: "From Details: what failed, its status, error code and request ID")) }
        return rows
    }

    // MARK: sent, queued

    private var outcome: some View {
        let sent = model.result == .sent
        let headline: LocalizedStringKey = switch (sent, model.isDemo) {
        case (true, false): "Thanks, your report reached RYFT."
        // Demo data posts to the in-memory platform: it says so.
        case (true, true): "Sent in demo mode: nothing reached RYFT."
        case (false, _): "Saved. It will be sent as soon as you're back online. You can close the app."
        }
        return VStack(spacing: 18) {
            Image(systemName: sent ? "checkmark.circle" : "clock")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(sent ? Theme.accent : Theme.textSecondary)
                .accessibilityHidden(true)
            Text(headline)
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($outcomeFocused)
                .accessibilityIdentifier(sent ? "report.sent" : "report.queued")
            PrimaryButton(title: "Done", style: .secondary) { dismiss() }
                .accessibilityIdentifier("report.done")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .onAppear { outcomeFocused = true }
    }
}

/// "About: Today · 503 · request 01a14ffa…" above a report from Details; VoiceOver reads the whole ID.
private struct ReportContextChip: View {
    let context: ReportContext
    /// Off with "Include diagnostics": the ID isn't sent then.
    var showsRequestID = true

    private var requestID: String? { showsRequestID ? context.requestID : nil }

    var body: some View {
        text(requestID.map(Self.short))
            .font(.ryft(.caption))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text(requestID))
            .accessibilityIdentifier("report.context")
    }

    private func text(_ id: String?) -> Text {
        if let id {
            return Text("About: \(context.resource) · \(context.statusText) · request \(id)")
        }
        return Text("About: \(context.resource) · \(context.statusText)")
    }

    /// The first 8 characters: enough to recognise it; the whole ID goes in `request_ids`.
    static func short(_ id: String) -> String {
        id.count > 9 ? String(id.prefix(8)) + "…" : id
    }
}

extension ReportContext {
    /// What previews and screenshot runs report about.
    static var preview: ReportContext {
        ReportContext(resource: String(localized: "Today"), status: "503",
                      requestID: "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c")
    }
}

/// One state of Report a problem on mock data (previews).
@MainActor
private func reportPreview(_ scheme: ColorScheme = .dark, de: Bool = false, size: DynamicTypeSize = .large,
                           context: ReportContext? = nil, showsIncluded: Bool = false,
                           stage: (ReportProblemModel) -> Void = { _ in }) -> some View {
    let state = AppState.preview()
    let model = ReportProblemModel(env: state.env, apiStatus: APIStatus()) { FeedbackSync() }
    stage(model)
    return NavigationStack { ReportProblemView(model: model, context: context, showsIncluded: showsIncluded) }
        .previewEnvironment(state, scheme: scheme)
        .environment(\.locale, Locale(identifier: de ? "de" : "en"))
        .dynamicTypeSize(size)
}

private let previewMessage = "Today said calibrating after a full week of nights, and pulling to refresh didn't change it."

#Preview("Report · empty · dark") { reportPreview() }
#Preview("Report · empty · light") { reportPreview(.light) }
#Preview("Report · empty · dark · de") { reportPreview(de: true) }
#Preview("Report · empty · AX3") { reportPreview(size: .accessibility3) }
#Preview("Report · filled · dark") { reportPreview { $0.stage(message: previewMessage, category: .data) } }
#Preview("Report · filled · light") { reportPreview(.light) { $0.stage(message: previewMessage, category: .data) } }
#Preview("Report · from Details · dark") { reportPreview(context: .preview) }
#Preview("Report · from Details · light · de") { reportPreview(.light, de: true, context: .preview) }
#Preview("Report · diagnostics off · dark") {
    reportPreview { $0.stage(message: previewMessage, includeDiagnostics: false) }
}
#Preview("Report · diagnostics off · light") {
    reportPreview(.light) { $0.stage(message: previewMessage, includeDiagnostics: false) }
}
#Preview("Report · disclosure open · dark") { reportPreview(showsIncluded: true) }
#Preview("Report · disclosure open · light") { reportPreview(.light, showsIncluded: true) }
#Preview("Report · disclosure open · AX3") { reportPreview(size: .accessibility3, showsIncluded: true) }
#Preview("Report · sending · dark") { reportPreview { $0.stage(message: previewMessage, sending: true) } }
#Preview("Report · sending · light") { reportPreview(.light) { $0.stage(message: previewMessage, sending: true) } }
#Preview("Report · sent · dark") { reportPreview { $0.stage(result: .sent) } }
#Preview("Report · sent · light") { reportPreview(.light) { $0.stage(result: .sent) } }
#Preview("Report · sent · AX3") { reportPreview(size: .accessibility3) { $0.stage(result: .sent) } }
#Preview("Report · sent · demo · dark") { reportPreview { $0.stage(result: .sent, demo: true) } }
#Preview("Report · sent · demo · light · de") { reportPreview(.light, de: true) { $0.stage(result: .sent, demo: true) } }
#Preview("Report · queued · dark") { reportPreview { $0.stage(result: .queued, waiting: 1) } }
#Preview("Report · queued · light") { reportPreview(.light) { $0.stage(result: .queued, waiting: 1) } }
#Preview("Report · rate limited · dark") {
    reportPreview { $0.stage(message: previewMessage, result: .rateLimited) }
}
#Preview("Report · rate limited · light") {
    reportPreview(.light) { $0.stage(message: previewMessage, result: .rateLimited) }
}
#Preview("Report · signed out · dark") {
    reportPreview { $0.stage(message: previewMessage, result: .signedOut) }
}
#Preview("Report · signed out · light") {
    reportPreview(.light) { $0.stage(message: previewMessage, result: .signedOut) }
}
#Preview("Report · from Details · diagnostics off") {
    reportPreview { $0.stage(message: ReportProblemModel.prefill(.preview), category: .bug, includeDiagnostics: false,
                             context: .preview) }
}
#Preview("Report · over limit · dark") {
    reportPreview { $0.stage(message: String(repeating: "The tiles and the gauge disagree. ", count: 120)) }
}
#Preview("Report · over limit · light") {
    reportPreview(.light) { $0.stage(message: String(repeating: "The tiles and the gauge disagree. ", count: 120)) }
}

#Preview("Report row · dark") {
    VStack(spacing: 12) {
        Card { ReportProblemRow(waiting: 0) }
        Card { ReportProblemRow(waiting: 1) }
    }
    .padding()
    .frame(maxHeight: .infinity)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}

#Preview("Report row · light") {
    VStack(spacing: 12) {
        Card { ReportProblemRow(waiting: 0) }
        Card { ReportProblemRow(waiting: 2) }
    }
    .padding()
    .frame(maxHeight: .infinity)
    .background(Theme.background)
    .preferredColorScheme(.light)
}

// MARK: - devices & sync

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

/// Profile → Data → Devices & sync (ui.md §4): what you wear and each tracker's card, Check sync (T3), what Apple
/// Health has seen, RYFT's own Health access, and Sync details for support.
struct DevicesAndSyncView: View {
    let model: DevicesViewModel
    @Environment(ScreenModels.self) private var screens
    @Environment(\.openURL) private var openURL
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                trackers
                checkSync
                seen
                health
                syncDetails
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("Devices & sync"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.appeared() }
        .sheet(isPresented: $editing) { TrackerPickerSheet(model: model) }
    }

    // MARK: your trackers

    private var trackers: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your trackers").ryftLabelStyle()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !model.trackers.isEmpty {
                    Button("Edit") { editing = true }
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(Text("Edit trackers"))
                        .accessibilityIdentifier("devices.edit")
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    if model.trackers.isEmpty {
                        Text("Tell RYFT what you wear to see how to set up your data.")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        PrimaryButton(title: "Choose", style: .secondary) { editing = true }
                            .accessibilityIdentifier("devices.choose")
                    } else {
                        ForEach(Array(model.trackers.enumerated()), id: \.element.id) { index, tracker in
                            if index > 0 { Divider().overlay(Theme.separator) }
                            NavigationLink {
                                TrackerDetailView(tracker: tracker, model: model) { editing = true }
                            } label: {
                                TrackerRowLabel(tracker: tracker, status: model.status(of: tracker))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Opens setup and details"))
                            .accessibilityIdentifier("devices.row.\(tracker.id)")
                        }
                    }
                }
            }
        }
    }

    // MARK: check sync

    /// T3 wires Check sync here (design.md §4.7, ui.md §4.2 item 2): a section with the screen's one Teal
    /// button, pushing the check, and "Last checked …" under it.
    @ViewBuilder private var checkSync: some View {
        EmptyView()
    }

    // MARK: seen in Apple Health

    private var seen: some View {
        ProfileSection(title: "Seen in Apple Health") {
            let rows = model.sources
            if rows.isEmpty {
                Text("No data from other apps yet.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(Theme.separator) }
                SourceRowView(row: row, lastSeen: model.lastSeenText(row))
            }
            Text("Apps and devices that sent data to RYFT in the last 30 days.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("devices.seen")
    }

    // MARK: Apple Health access

    /// RYFT's own read permission: its status, then the catalog's route in the Health app next to "Open Health".
    private var health: some View {
        ProfileSection(title: "Apple Health access") {
            StatRow(title: "Apple Health", value: model.healthStatusText)
            if model.canAskForHealth {
                PrimaryButton(title: "Allow access", style: .secondary) { await model.requestHealthAccess() }
            }
            let steps = model.healthAccessSteps
            VStack(alignment: .leading, spacing: 10) {
                if !steps.isEmpty {
                    Text("To check what RYFT may read:")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        NumberedStep(number: index + 1, verbatim: step, total: steps.count)
                    }
                }
                PrimaryButton(title: "Open Health", style: .secondary) { HealthLinks.open(with: openURL) }
                    .accessibilityIdentifier("devices.openHealth")
            }
        }
    }

    // MARK: sync details

    private var syncDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            NavigationLink {
                SyncDetailsView(model: screens.profile.syncDetails)
            } label: {
                Label("Sync details", systemImage: "list.bullet.rectangle")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityHint(Text("For support: requests and streams."))
            .accessibilityIdentifier("devices.syncDetails")
            Text("For support: requests and streams.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
    }
}

/// A chosen tracker: its glyph and name, and how its setup stands.
private struct TrackerRowLabel: View {
    let tracker: Tracker
    let status: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: tracker.symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: tracker.title)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                Text(verbatim: status)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tracker.title))
        .accessibilityValue(Text(verbatim: status))
    }
}

/// A source the platform saw: RYFT's name for it, what it sent, when; one RYFT doesn't know is still read.
private struct SourceRowView: View {
    let row: DevicesViewModel.SourceRow
    let lastSeen: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: row.name)
                .font(.ryft(.callout))
                .foregroundStyle(row.known ? Theme.textPrimary : Theme.textSecondary)
            Text(verbatim: row.kinds)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
            Text(verbatim: lastSeen)
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
            if !row.known {
                Text("Not a tracker RYFT knows. It still counts.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("devices.source")
    }
}

/// One tracker's card, pushed from Devices & sync.
struct TrackerDetailView: View {
    let tracker: Tracker
    let model: DevicesViewModel
    /// Just my iPhone: "Add a tracker" opens the picker.
    let addTracker: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            TrackerSetupCard(tracker: tracker,
                             later: TrackerSelectionStore.needsSetup(tracker) ? { model.selection.markLater(tracker.id) } : nil,
                             addTracker: tracker.isJustIPhone ? {
                                 dismiss()
                                 addTracker()
                             } : nil)
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: tracker.cardTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "What do you wear?" from Devices & sync: the same tiles; Done saves, Cancel leaves the choice as it was.
struct TrackerPickerSheet: View {
    let model: DevicesViewModel
    @State private var picked: [String]
    @Environment(\.dismiss) private var dismiss

    init(model: DevicesViewModel) {
        self.model = model
        _picked = State(initialValue: model.selection.trackers)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Pick your watch, band or ring. RYFT then shows how to get its data into Apple Health.")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TrackerPickerGrid(catalog: model.catalog, picked: $picked)
                    Text("RYFT only uses this to show you setup steps and to check that your data arrives.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text("What do you wear?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { SheetTitle(text: "What do you wear?") }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.save(picked)
                        dismiss()
                    }
                    .accessibilityIdentifier("wear.done")
                }
            }
        }
    }
}

/// Devices & sync on mock data: the bundled catalog, a choice, and `User.sources`
/// with a source RYFT doesn't know.
@MainActor
private func devicesPreview(_ picked: [String], scheme: ColorScheme = .dark, de: Bool = false,
                            size: DynamicTypeSize = .large, later: [String] = []) -> some View {
    let state = AppState.preview(flags: [.devicesSetup: true])
    if var user = state.user {
        let now = Date.now
        user.sources = [
            UserSource(name: "Connect", bundleId: "com.garmin.connect.mobile", kinds: [.hr, .sleep, .steps, .workout],
                       lastSeen: now.addingTimeInterval(-1_200)),
            UserSource(name: "Oura", bundleId: "com.ouraring.oura", kinds: [.hr, .sleep, .resp, .workout],
                       lastSeen: now.addingTimeInterval(-26_000)),
            UserSource(name: "Tim's iPhone", bundleId: "com.apple.health.3F0A", kinds: [.steps],
                       lastSeen: now.addingTimeInterval(-600)),
            UserSource(name: "Sleep Cycle", bundleId: "com.lexwarelabs.goodmorning", kinds: [.sleep],
                       lastSeen: now.addingTimeInterval(-90_000)),
        ]
        state.user = user
    }
    let model = DevicesViewModel(state: state, selection: TrackerSelectionStore(env: state.env))
    model.selection.stage(picked)
    later.forEach(model.selection.markLater)
    return NavigationStack { DevicesAndSyncView(model: model) }
        .previewEnvironment(state, scheme: scheme)
        .environment(\.locale, Locale(identifier: de ? "de" : "en"))
        .dynamicTypeSize(size)
}

#Preview("Devices & sync · two trackers · dark") { devicesPreview(["garmin", "oura"], later: ["oura"]) }
#Preview("Devices & sync · two trackers · light") { devicesPreview(["garmin", "oura"], scheme: .light, later: ["oura"]) }
#Preview("Devices & sync · two trackers · de") { devicesPreview(["garmin", "oura"], de: true) }
#Preview("Devices & sync · none chosen · dark") { devicesPreview([]) }
#Preview("Devices & sync · none chosen · light") { devicesPreview([], scheme: .light) }
#Preview("Devices & sync · AX3") { devicesPreview(["garmin"], size: .accessibility3) }

/// A tracker's card or the picker sheet from Devices & sync, on mock data.
@MainActor
private func devicesScreenPreview(_ scheme: ColorScheme, sheet: Bool = false) -> some View {
    let state = AppState.preview(flags: [.devicesSetup: true])
    let model = DevicesViewModel(state: state, selection: TrackerSelectionStore(env: state.env))
    model.selection.stage(["garmin", "oura"])
    return Group {
        if sheet {
            TrackerPickerSheet(model: model)
        } else {
            NavigationStack { TrackerDetailView(tracker: MockData.tracker("garmin"), model: model) {} }
        }
    }
    .previewEnvironment(state, scheme: scheme)
}

#Preview("Tracker detail · dark") { devicesScreenPreview(.dark) }
#Preview("Tracker detail · light") { devicesScreenPreview(.light) }
#Preview("Tracker picker sheet · dark") { devicesScreenPreview(.dark, sheet: true) }
#Preview("Tracker picker sheet · light") { devicesScreenPreview(.light, sheet: true) }

#Preview("Profile · Data row · dark") {
    ProfileView().previewEnvironment(AppState.preview(flags: [.devicesSetup: true]))
}

#Preview("Profile · Data row · light") {
    ProfileView().previewEnvironment(AppState.preview(flags: [.devicesSetup: true]), scheme: .light)
}
