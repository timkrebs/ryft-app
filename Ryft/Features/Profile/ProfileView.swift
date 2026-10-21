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
                        Text(verbatim: "\(f.status) \(f.method) \(f.path)")
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
            StatRow(title: "Apple Health", value: model.healthStatusText,
                    valueColor: model.healthNeedsAttention ? Theme.warning : Theme.textPrimary)
            HStack(spacing: 10) {
                if model.canAskForHealth {
                    PrimaryButton(title: "Allow access", style: .secondary) { await model.requestHealthAccess() }
                }
                PrimaryButton(title: "Open Health permissions", style: .secondary) { HealthLinks.open(with: openURL) }
            }
            Text("Garmin Connect must write to Apple Health (Garmin Connect → More → Settings → Apple Health), and RYFT must be allowed to read it (Health → Sharing → Apps → RYFT).")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

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
            LinkRow(title: "Garmin Connect and Apple Health", url: URL(string: "https://support.garmin.com/?q=apple%20health"))
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
                    Text(verbatim: "\(r.status)\(r.code.map { " \($0)" } ?? "") \(r.method) \(r.path)")
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

    let title: LocalizedStringKey
    var style: Style = .primary
    var busy = false
    let action: () async -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            ZStack {
                if busy {
                    ProgressView().controlSize(.small).tint(foreground)
                } else {
                    Text(title)
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

#Preview("Profile · dark") {
    ProfileView().previewEnvironment()
}

#Preview("Profile · light") {
    ProfileView().previewEnvironment(scheme: .light)
}

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
            model.prepare(context)
            // From Details the message is written already: the caret waits at its end.
            if context != nil { editing = true }
        }
        .onChange(of: model.includeDiagnostics) { _, on in if !on { included = false } }
    }

    // MARK: compose

    @ViewBuilder private var form: some View {
        if let context = model.context { ReportContextChip(context: context) }
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
                        ForEach(Self.included, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(verbatim: "•").accessibilityHidden(true)
                                Text(item).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityElement(children: .combine)
                        }
                        Text("No health values. Nothing from Apple Health, no scores, no sleep or heart data.")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                } label: {
                    Text("What's included")
                        .font(.ryft(.callout))
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

    /// "What's included", in the order of `FeedbackPayload`.
    private static var included: [String] {
        [
            String(localized: "App version and build"),
            String(localized: "Device model and iOS version"),
            String(localized: "The last 20 requests: method, path, status, error code, request ID, duration"),
            String(localized: "Per resource: when it was loaded, last error"),
            String(localized: "Sync state, account gates and feature flags"),
        ]
    }

    // MARK: sent, queued

    private var outcome: some View {
        let sent = model.result == .sent
        let headline: LocalizedStringKey = sent
            ? "Thanks, your report reached RYFT."
            : "Saved. It will be sent as soon as you're back online. You can close the app."
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

    var body: some View {
        text(context.requestID.map(Self.short))
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
            .accessibilityLabel(text(context.requestID))
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
    let model = ReportProblemModel(env: state.env, apiStatus: APIStatus()) { "RYFT 1.0.0 (1) · iOS 27.0" }
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
#Preview("Report · queued · dark") { reportPreview { $0.stage(result: .queued, waiting: 1) } }
#Preview("Report · queued · light") { reportPreview(.light) { $0.stage(result: .queued, waiting: 1) } }
#Preview("Report · rate limited · dark") {
    reportPreview { $0.stage(message: previewMessage, result: .rateLimited) }
}
#Preview("Report · rate limited · light") {
    reportPreview(.light) { $0.stage(message: previewMessage, result: .rateLimited) }
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
