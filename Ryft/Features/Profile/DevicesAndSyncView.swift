import SwiftUI

// MARK: - devices & sync

/// Profile → Data → Devices & sync (ui.md §4): what you wear and each tracker's card, Check sync (T3), what Apple
/// Health has seen, RYFT's own Health access, and Sync details for support.
struct DevicesAndSyncView: View {
    let model: DevicesViewModel
    @Environment(ScreenModels.self) private var screens
    @Environment(\.appEnvironment) private var env
    @Environment(\.openURL) private var openURL
    @State private var editing = false
    /// The pushed Check sync's model: made on the tap, once, not on every redraw.
    @State private var check: TrackerCheckModel?

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
        // Back from Check sync: "Last checked" and the rows' results.
        .onAppear { model.reloadCheck() }
        .navigationDestination(isPresented: Binding(get: { check != nil }, set: { if !$0 { check = nil } })) {
            if let check { TrackerCheckView(model: check) }
        }
        .sheet(isPresented: $editing) { TrackerPickerSheet(model: model).presentedRoot() }
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

    /// Check sync (design.md §4.7, ui.md §4.2 item 2): a section with the screen's one Teal button, pushing the
    /// check on the selection, and "Last checked …" under it. Nothing to check before a choice.
    @ViewBuilder private var checkSync: some View {
        if !model.trackers.isEmpty {
            ProfileSection(title: "Check sync") {
                Text("See whether your trackers' data arrives in Apple Health.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    check = .make(env: env, trackers: model.selection.trackers)
                } label: {
                    Text("Check sync")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("devices.checkSync")
                Text(model.lastCheckedText)
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityIdentifier("devices.lastChecked")
            }
        }
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

/// Devices & sync on mock data: the bundled catalog, a choice, and `User.sources`
/// with a source RYFT doesn't know.
@MainActor
private func devicesPreview(_ picked: [String], de: Bool = false, size: DynamicTypeSize = .large,
                            later: [String] = [], checked: Bool = false) -> some View {
    let state = AppState.preview(flags: [.devicesSetup: true])
    // A check ten minutes ago (demo data keeps it in memory): the rows' results and "Last checked".
    TrackerCheckRecord.demo = checked ? previewCheckRecord(picked) : nil
    if var user = state.user {
        let now = Date.now
        user.sources = [
            UserSource(name: "Connect", bundleId: "com.garmin.connect.mobile", kinds: [.hr, .sleep, .steps, .workout],
                       lastSeen: now.addingTimeInterval(-1_200)),
            UserSource(name: "Oura", bundleId: "com.ouraring.oura", kinds: [.hr, .sleep, .resp, .workout],
                       lastSeen: now.addingTimeInterval(-26_000)),
            UserSource(name: "Alex's iPhone", bundleId: "com.apple.health.3F0A", kinds: [.steps],
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
        .previewEnvironment(state)
        .environment(\.locale, Locale(identifier: de ? "de" : "en"))
        .dynamicTypeSize(size)
}

#Preview("Devices & sync · two trackers · dark") { devicesPreview(["garmin", "oura"], later: ["oura"]) }
#Preview("Devices & sync · checked · dark") { devicesPreview(["garmin", "oura"], checked: true) }
#Preview("Devices & sync · checked · de") { devicesPreview(["garmin", "oura"], de: true, checked: true) }
#Preview("Devices & sync · two trackers · de") { devicesPreview(["garmin", "oura"], de: true) }
#Preview("Devices & sync · none chosen · dark") { devicesPreview([]) }
#Preview("Devices & sync · AX3") { devicesPreview(["garmin"], size: .accessibility3) }

/// The Garmin-like store's check for these trackers, ten minutes ago.
@MainActor
private func previewCheckRecord(_ ids: [String]) -> TrackerCheckRecord {
    let now = Date.now
    let store = MockHealthStore.garminLike(now: now, sleepOff: true)
    let catalog = TrackerCatalog.bundled
    let trackers = ids.compactMap(catalog.tracker)
    let checks = trackers.map {
        TrackerCheckRules.classify($0, samples: store.samples, visible: store.visible, now: now, catalog: catalog,
                                   alongside: trackers)
    }
    return TrackerCheckRecord(account: "demo", at: now.addingTimeInterval(-600), checks: checks)
}
