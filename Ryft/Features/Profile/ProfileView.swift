import SwiftUI
import UIKit

/// Account, body settings, data/sync and about. Replaces the scaffold's SettingsView.
struct ProfileView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var state: AppState
    @Environment(\.openURL) private var openURL

    @State private var apiKeyDraft = ""
    @State private var connection: ConnectionResult?
    @State private var testing = false
    @State private var maxHR = 190
    @State private var sleepBase = 480
    @State private var recomputeStatus: String?
    @State private var recomputing = false
    @State private var showResyncConfirm = false
    @State private var healthStatus: HealthKitManager.AccessStatus = .unknown

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
            }
        }
        .onAppear {
            apiKeyDraft = settings.apiKey ?? ""
            applyUser()
        }
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
    }

    // MARK: account

    private var account: some View {
        ProfileSection(title: "Account") {
            FieldLabel("Server URL")
            TextField("https://ryft.example.com", text: $settings.apiURLString)
                .ryftField()
                .keyboardType(.URL).textContentType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            FieldLabel("Ingest URL (optional)")
            TextField("Defaults to the server URL", text: $settings.ingestURLString)
                .ryftField()
                .keyboardType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            FieldLabel("API key")
            SecureField("Bearer token", text: $apiKeyDraft)
                .ryftField()
                .textContentType(.password)
                .onSubmit { settings.apiKey = apiKeyDraft }

            PrimaryButton(title: "Save & test connection", busy: testing) { await saveAndTest() }

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

            if let u = state.user {
                Divider().overlay(Theme.separator)
                StatRow(title: "Connected as", value: u.name)
                StatRow(title: "Timezone", value: u.tz,
                        detail: u.tz == TimeZone.current.identifier ? nil
                            : String(localized: "Phone: \(TimeZone.current.identifier)"))
            }
        }
    }

    private func saveAndTest() async {
        testing = true
        defer { testing = false }
        settings.apiKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.isConfigured else {
            connection = .failed(APIError.notConfigured.localizedDescription)
            return
        }
        do {
            let user = try await APIClient.shared.me()
            connection = .ok(String(localized: "Connected as \(user.name)"))
            if settings.demoMode {
                settings.demoMode = false
                state.reset()
            }
            await state.syncAndRefresh(using: sync)
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }

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
                PrimaryButton(title: "Open Health permissions", style: .secondary) { openHealth() }
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
            if let e = sync.lastError, !settings.demoMode {
                InlineMessage(message: e, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            }
            HStack(spacing: 10) {
                PrimaryButton(title: "Sync now", style: .secondary, busy: sync.isSyncing) {
                    await state.syncAndRefresh(using: sync)
                }
                PrimaryButton(title: "Full re-sync", style: .destructive) { showResyncConfirm = true }
            }
            .disabled(sync.isSyncing || !settings.isConfigured || settings.demoMode)

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

    private var healthStatusText: String {
        switch healthStatus {
        case .unavailable: return String(localized: "Not available")
        case .notAsked: return String(localized: "Not requested")
        case .asked: return String(localized: "Requested")
        case .unknown: return Fmt.placeholder
        }
    }

    private func openHealth() {
        if let health = URL(string: "x-apple-health://"), UIApplication.shared.canOpenURL(health) {
            openURL(health)
        } else if let app = URL(string: UIApplication.openSettingsURLString) {
            openURL(app)
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
            Divider().overlay(Theme.separator)
            if settings.isConfigured, let url = settings.apiURL {
                LinkRow(title: "Your RYFT server", url: url)
            }
            LinkRow(title: "Garmin Connect and Apple Health", url: URL(string: "https://support.garmin.com/?q=apple%20health"))
            LinkRow(title: "Apple Health privacy", url: URL(string: "https://www.apple.com/legal/privacy/data/en/health-app/"))
            LinkRow(title: "Satoshi typeface (Fontshare)", url: URL(string: "https://www.fontshare.com/fonts/satoshi"))
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
