import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var state: AppState

    @State private var apiKeyDraft = ""
    @State private var maxHR = 190
    @State private var sleepBase = 460
    @State private var showResyncConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("API URL (https://ryft.example.com)", text: $settings.apiURLString)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Ingest URL (optional, defaults to API URL)", text: $settings.ingestURLString)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API key", text: $apiKeyDraft)
                        .onSubmit { settings.apiKey = apiKeyDraft }
                    Button("Save & test connection") {
                        settings.apiKey = apiKeyDraft
                        Task { await state.refresh(); if let u = state.user { maxHR = u.maxHr; sleepBase = u.sleepBaseMin } }
                    }
                    if let u = state.user {
                        LabeledContent("Connected as", value: u.name)
                        LabeledContent("Server timezone", value: u.tz)
                    }
                }

                Section("Scoring") {
                    Stepper("Max heart rate: \(maxHR) bpm", value: $maxHR, in: 140...220)
                    Stepper("Sleep baseline: \(sleepBase.asHoursMinutes)", value: $sleepBase, in: 300...600, step: 10)
                    Button("Apply & recompute last 90 days") {
                        Task {
                            await state.updateUser(UserPatch(tz: TimeZone.current.identifier, maxHr: maxHR, sleepBaseMin: sleepBase))
                            try? await APIClient.shared.recompute(
                                from: Calendar.current.date(byAdding: .day, value: -90, to: .now)!, to: .now)
                            try? await Task.sleep(for: .seconds(3))
                            await state.refresh()
                        }
                    }
                }

                Section("Sync") {
                    LabeledContent("Last sync", value: settings.lastSync?.formatted(.relative(presentation: .named)) ?? "never")
                    LabeledContent("Device ID", value: settings.deviceId.uuidString.prefix(8) + "…")
                    Button(sync.isSyncing ? "Syncing… \(sync.progress)" : "Sync now") {
                        Task { await sync.syncNow(); await state.refresh() }
                    }
                    .disabled(sync.isSyncing)
                    Button("Full re-sync (last 90 days)", role: .destructive) { showResyncConfirm = true }
                        .disabled(sync.isSyncing)
                    if let e = sync.lastError { Text(e).font(.footnote).foregroundStyle(.red) }
                }

                Section {
                    Text("Data comes from Apple Health. Make sure Garmin Connect is allowed to write to Health (Garmin Connect → More → Settings → Apple Health) and that Ryft is allowed to read it (Settings → Health → Data Access & Devices → Ryft).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                apiKeyDraft = settings.apiKey ?? ""
                if let u = state.user { maxHR = u.maxHr; sleepBase = u.sleepBaseMin }
            }
            .confirmationDialog("Re-upload the last 90 days of Health data?", isPresented: $showResyncConfirm) {
                Button("Re-sync", role: .destructive) {
                    Task {
                        await sync.fullResync()
                        try? await APIClient.shared.recompute(
                            from: Calendar.current.date(byAdding: .day, value: -90, to: .now)!, to: .now)
                        await state.refresh()
                    }
                }
            }
        }
    }
}
