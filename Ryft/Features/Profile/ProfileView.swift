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
                data
                if model.showsNotifications { notifications }
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
            Stepper(value: Bindable(model).sleepBase, in: 300...600, step: 10) {
                StepperLabel(title: "Sleep baseline", value: model.sleepBaseText)
            }
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

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - building blocks

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

#Preview("Profile · dark") {
    ProfileView().previewEnvironment()
}

#Preview("Profile · light") {
    ProfileView().previewEnvironment(scheme: .light)
}
