import SwiftUI
import UIKit

/// Account, body settings, data/sync and about. Replaces the scaffold's SettingsView.
struct ProfileView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var sync: SyncService
    @ObservedObject private var apiStatus = APIStatus.shared
    @EnvironmentObject private var state: AppState
    @Environment(\.openURL) private var openURL

    @State private var connection: ConnectionResult?
    @State private var testing = false
    @State private var maxHR = 190
    @State private var sleepBase = 480
    @State private var recomputeStatus: String?
    @State private var recomputing = false
    @State private var showResyncConfirm = false
    @State private var showLogOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showChangePassword = false
    @State private var healthStatus: HealthKitManager.AccessStatus = .unknown
    @State private var legal: LegalPage?
    @State private var exporting = false
    @State private var exported: ExportedFile?
    @State private var exportError: String?

    private enum ConnectionResult {
        case ok(String)
        case failed(String)
    }

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
                appearance
                about
                #if DEBUG
                developer
                #endif
            }
        }
        .safariSheet($legal)
        .sheet(item: $exported) { ShareSheet(items: [$0.url]).presentationDetents([.medium, .large]) }
        .onAppear { applyUser() }
        .onChange(of: state.user) { applyUser() }
        .task { healthStatus = await HealthKitManager.shared.accessStatus() }
        .confirmationDialog("Re-upload the last 90 days of Health data?", isPresented: $showResyncConfirm,
                            titleVisibility: .visible) {
            Button("Re-sync", role: .destructive) {
                Task {
                    await sync.fullResync()
                    try? await state.source.recompute(from: DayFormat.shift(.now, days: -90), to: .now)
                    await state.refresh()
                }
            }
        } message: {
            Text("This uploads everything again. It can take a few minutes on the first run.")
        }
        .confirmationDialog("Log out of RYFT?", isPresented: $showLogOutConfirm, titleVisibility: .visible) {
            Button("Log out", role: .destructive) {
                Task { await auth.signOut() }
            }
        } message: {
            Text("Cached scores and Health sync progress are removed from this iPhone. Your account and data stay on the RYFT platform.")
        }
        .alert("Delete your RYFT account?", isPresented: $showDeleteConfirm) {
            Button("Delete account", role: .destructive) {
                Task { await auth.deleteAccount() }
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
            if auth.isSignedIn {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(accountTitle)
                            .font(.ryft(.headline))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let email = accountEmail, email != accountTitle {
                            Text(email)
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 8)
                    if let badge = providerBadge {
                        ProviderBadge(title: badge.title, systemImage: badge.systemImage)
                    }
                }
                .accessibilityElement(children: .combine)
                if let u = state.user {
                    StatRow(title: "Timezone", value: u.tz,
                            detail: u.tz == TimeZone.current.identifier ? nil
                                : String(localized: "Phone: \(TimeZone.current.identifier)"))
                }
                Divider().overlay(Theme.separator)
                if provider == "email" {
                    PrimaryButton(title: "Change password", style: .secondary) { showChangePassword = true }
                }
                PrimaryButton(title: "Log out", style: .secondary) { showLogOutConfirm = true }
                PrimaryButton(title: "Delete account", style: .destructive, busy: auth.isWorking) {
                    showDeleteConfirm = true
                }
                if let error = auth.errorMessage {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle", details: auth.errorDetails)
                }
            } else {
                StatRow(title: "Signed in", value: String(localized: "No"), valueColor: Theme.textSecondary)
                Text("Turn off Demo data to log in or create an account.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// `User.name` → email → "Apple ID".
    private var accountTitle: String {
        if let name = state.user?.name, !name.isEmpty { return name }
        return accountEmail ?? auth.identityDescription
    }

    private var accountEmail: String? {
        let email = state.user?.email ?? auth.user?.email
        return email?.isEmpty == false ? email : nil
    }

    /// The platform's `User.provider`, else the session's `app_metadata.provider`.
    private var provider: String? { state.user?.provider ?? auth.provider }

    private var providerBadge: (title: LocalizedStringKey, systemImage: String)? {
        switch provider {
        case "apple": return ("Apple", "apple.logo")
        case "email": return ("Email", "envelope.fill")
        default: return nil
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
            FieldLabel("API URL override")
            TextField(Bundle.configValue("RyftAPIURL") ?? "https://api.ryftapp.de", text: $settings.devAPIURLOverride)
                .ryftField()
                .keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            FieldLabel("Ingest URL override (compose: :8081)")
            TextField("Same host as the API", text: $settings.devIngestURLOverride)
                .ryftField()
                .keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()

            Toggle(isOn: $settings.apiKeyMode) {
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
                SecureField("Bearer token", text: $settings.devAPIKey)
                    .ryftField()
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }

            Toggle(isOn: $settings.showRequestIDs) {
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

            PrimaryButton(title: "Test connection", style: .secondary, busy: testing) { await testConnection() }
            switch connection {
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

    private func testConnection() async {
        testing = true
        defer { testing = false }
        guard settings.isConfigured else {
            connection = .failed(APIError.notConfigured.localizedDescription)
            return
        }
        guard auth.isSignedIn else {
            connection = .failed(APIError.signedOut.localizedDescription)
            return
        }
        do {
            let user = try await APIClient.shared.me()
            connection = .ok(String(localized: "Connected as \(user.name.isEmpty ? user.id.uuidString : user.name)"))
            await state.syncAndRefresh(using: sync)
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }
    #endif

    // MARK: body

    private var bodySection: some View {
        ProfileSection(title: "Body") {
            Stepper(value: $maxHR, in: 140...220) {
                StepperLabel(title: "Max heart rate", value: "\(maxHR) bpm")
            }
            Stepper(value: $sleepBase, in: 300...600, step: 10) {
                StepperLabel(title: "Sleep baseline", value: Fmt.duration(minutes: sleepBase))
            }
            PrimaryButton(title: "Apply & recompute 90 days", style: .secondary, busy: recomputing) {
                await applyAndRecompute()
            }
            .disabled(!state.hasDataSource)
            if let recomputeStatus {
                Text(recomputeStatus)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func applyAndRecompute() async {
        recomputing = true
        defer { recomputing = false }
        await state.updateUser(UserPatch(tz: TimeZone.current.identifier, maxHr: maxHR, sleepBaseMin: sleepBase))
        do {
            try await state.source.recompute(from: DayFormat.shift(.now, days: -90), to: .now)
            recomputeStatus = String(localized: "Recomputing — scores update in a few seconds.")
            try? await Task.sleep(for: .seconds(3))
            await state.refresh()
            recomputeStatus = String(localized: "Scores recomputed with your new settings.")
        } catch {
            recomputeStatus = error.localizedDescription
        }
    }

    private func applyUser() {
        if let u = state.user {
            maxHR = u.maxHr
            sleepBase = u.sleepBaseMin
        }
    }

    // MARK: data

    private var data: some View {
        ProfileSection(title: "Data") {
            StatRow(title: "Apple Health", value: healthStatusText,
                    valueColor: healthStatus == .asked ? Theme.textPrimary : Theme.warning)
            HStack(spacing: 10) {
                if healthStatus == .notAsked {
                    PrimaryButton(title: "Allow access", style: .secondary) {
                        try? await HealthKitManager.shared.requestAuthorization()
                        healthStatus = await HealthKitManager.shared.accessStatus()
                    }
                }
                PrimaryButton(title: "Open Health permissions", style: .secondary) { HealthLinks.open(with: openURL) }
            }
            Text("Garmin Connect must write to Apple Health (Garmin Connect → More → Settings → Apple Health), and RYFT must be allowed to read it (Health → Sharing → Apps → RYFT).")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Theme.separator)
            StatRow(title: "Last sync",
                    value: settings.lastSync?.formatted(.relative(presentation: .named)) ?? String(localized: "Never"))
            StatRow(title: "Device ID", value: String(settings.deviceId.uuidString.prefix(8)) + "…")
            if sync.isSyncing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                    Text(sync.progress.isEmpty ? String(localized: "Syncing…") : sync.progress)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if let notice = apiStatus.retryNotice {
                InlineMessage(message: notice, systemImage: "clock.arrow.circlepath")
            } else if let e = sync.lastError, !settings.demoMode {
                InlineMessage(message: e, systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                              details: sync.lastErrorDetails)
            }
            HStack(spacing: 10) {
                PrimaryButton(title: "Sync now", style: .secondary, busy: sync.isSyncing) {
                    await state.syncAndRefresh(using: sync)
                }
                PrimaryButton(title: "Full re-sync", style: .destructive) { showResyncConfirm = true }
            }
            .disabled(sync.isSyncing || !settings.isConfigured || !auth.isSignedIn || settings.demoMode)

            if auth.isSignedIn || settings.demoMode {
                PrimaryButton(title: "Export my data", style: .secondary, busy: exporting) { await export() }
                    .accessibilityHint(Text("Creates a JSON file of your scores, workouts and sessions to share or save"))
                if let exportError {
                    InlineMessage(message: exportError, systemImage: "square.and.arrow.up")
                }
            }

            Divider().overlay(Theme.separator)
            Toggle(isOn: Binding(get: { settings.demoMode }, set: { on in
                settings.demoMode = on
                state.reset()
                Task { await state.refresh() }
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
        }
    }

    private func export() async {
        exporting = true
        exportError = nil
        defer { exporting = false }
        do {
            let archive = try await DataExport.archive(source: state.source, train: TrainSource.current)
            exported = ExportedFile(url: try DataExport.write(archive))
        } catch {
            exportError = String(localized: "The export couldn't be created: \(error.localizedDescription)")
        }
    }

    private var healthStatusText: String {
        switch healthStatus {
        case .unavailable: return String(localized: "Not available")
        case .notAsked: return String(localized: "Not requested")
        case .asked: return String(localized: "Requested")
        case .unknown: return Fmt.placeholder
        }
    }


    // MARK: appearance & about

    private var appearance: some View {
        ProfileSection(title: "Appearance") {
            SegmentedPicker(selection: $settings.appearance, options: Settings.Appearance.allCases) { a in
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
    let title: LocalizedStringKey
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
        case .primary: return Theme.graphite
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
