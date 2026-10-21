import SwiftUI
import UIKit

/// Account, body settings, data/sync and about. Replaces the scaffold's SettingsView.
struct ProfileView: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL
    private var apiStatus = APIStatus.shared

    @State private var showResyncConfirm = false
    @State private var showLogOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showChangePassword = false
    @State private var showWithdrawConfirm = false
    @State private var legal: LegalPage?

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
        .onAppear { model.applyUser() }
        .onChange(of: state.user) { model.applyUser() }
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
        ProfileSection(title: "Body") {
            Stepper(value: Bindable(model).maxHR, in: 140...220) {
                StepperLabel(title: "Max heart rate", value: model.maxHRText)
            }
            if let source = model.maxHRSourceText {
                Text(source)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            if model.canUseMaxHREstimate {
                Button("Use the estimate") { Task { await model.useMaxHREstimate() } }
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.accent)
            }
            HStack {
                Text("Birth year").font(.ryft(.body)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker("Birth year", selection: Binding(get: { model.birthYear },
                                                        set: { y in if let y { Task { await model.setBirthYear(y) } } })) {
                    if model.birthYear == nil { Text("Not set").tag(Int?.none) }
                    ForEach(model.birthYears, id: \.self) { Text(verbatim: "\($0)").tag(Int?.some($0)) }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
            }
            .frame(minHeight: 44)
            Stepper(value: Bindable(model).sleepBase, in: 240...720, step: 5) {
                StepperLabel(title: "Sleep baseline", value: model.sleepBaseText)
            }
            if let source = model.sleepBaseSourceText {
                Text(source)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            if model.canUseLearnedBase {
                Button(model.usesLearnedTitle) { Task { await model.useLearnedBase() } }
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.accent)
            }
            Text("Changing a setting doesn't rescore past days until you tap Apply & recompute. Setting the baseline by hand stops RYFT from learning it.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Apply & recompute 90 days", style: .secondary, busy: model.recomputing) {
                await model.applyAndRecompute()
            }
            .disabled(!model.canRecompute)
            if let status = model.recomputeStatus {
                Text(status)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
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

private struct StepperLabel: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.ryft(.body))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
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
