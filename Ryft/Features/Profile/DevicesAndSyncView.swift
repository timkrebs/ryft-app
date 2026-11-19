import SwiftUI

// MARK: - devices & sync

/// Profile → Devices & sync (Nocturne PR 6 C2, design-pr6-c-settings.md §4.4, drafts c-05 … c-05x): what you wear and each
/// tracker's card, Check sync (the page's one primary, in flow after the thing it checks), what Apple Health has seen, RYFT's
/// own Health access, and Sync details for support. The cached list says when it was loaded (the offline-first rule).
struct DevicesAndSyncView: View {
    let model: DevicesViewModel
    var placement: DevicesPagePlacement = .pushed

    @Environment(ScreenModels.self) private var screens
    @Environment(\.appEnvironment) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editing = false
    @State private var route: DevicesRoute?
    /// The pushed Check sync's model: made on the tap, once, not on every redraw.
    @State private var check: TrackerCheckModel?
    @State private var askingForHealth = false

    var body: some View {
        SubpageScaffold(Text("Devices & sync"), navigation: placement.navigation, isSheet: placement.isSheet) {
            VStack(alignment: .leading, spacing: 0) {
                trackers
                if model.trackers.isEmpty {
                    choose.padding(.top, GroupedListSpec.groupSpacing)
                } else {
                    checkSync.padding(.top, GroupedListSpec.groupSpacing)
                }
                seen.padding(.top, DevicesSpec.seenGap)
                health.padding(.top, GroupedListSpec.groupSpacing)
                syncDetails.padding(.top, GroupedListSpec.groupSpacing)
            }
        }
        .devicesPagePlacement(placement)
        .task { await model.appeared() }
        // Back from Check sync: "Last checked" and the rows' results.
        .onAppear { model.reloadCheck() }
        .navigationDestination(item: $route) { destination($0) }
        .sheet(isPresented: $editing) { TrackerPickerSheet(model: model).presentedRoot() }
    }

    @ViewBuilder private func destination(_ route: DevicesRoute) -> some View {
        switch route {
        case .tracker(let id):
            if let tracker = model.catalog.tracker(id) {
                TrackerDetailView(tracker: tracker, model: model, placement: placement.pushed) { editing = true }
            }
        case .check:
            if let check { TrackerCheckView(model: check, placement: placement.pushed) }
        case .syncDetails:
            SyncDetailsView(model: screens.profile.syncDetails, placement: placement.pushed)
        }
    }

    // MARK: your trackers

    /// "Your trackers" with "Edit" on its line (its own line from AX1), then a push row per tracker: the glyph circle, the
    /// name, how its setup stands. Without a tracker the card holds the sentence; Choose goes under it.
    private var trackers: some View {
        VStack(alignment: .leading, spacing: 0) {
            trackersTitle
                .padding(.bottom, GroupedListSpec.titleGap)
            GroupedCard {
                if model.trackers.isEmpty {
                    sentenceRow(Text("Tell RYFT what you wear to see how to set up your data."))
                } else {
                    ForEach(model.trackers, id: \.id) { tracker in
                        GroupedRow.push(Text(verbatim: tracker.title), detail: Text(verbatim: model.status(of: tracker)),
                                        icon: tracker.symbol, hint: Text("Opens setup and details"),
                                        identifier: "devices.row.\(tracker.id)") {
                            route = .tracker(tracker.id)
                        }
                    }
                }
            }
        }
    }

    /// The group title with its text action: `GroupTitle`'s look, with the action's own VoiceOver label and identifier.
    private var trackersTitle: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: GroupedListSpec.rowSpacing))
        return layout {
            Text("Your trackers")
                .font(.ryft(.label))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if !model.trackers.isEmpty {
                Button { editing = true } label: { Text("Edit") }
                    .ryftLink()
                    // On the title's line the link's 44 pt box reaches past it without moving the card.
                    .padding(.vertical, stacked ? 0 : -GroupedListSpec.titleActionOverhang)
                    .accessibilityLabel(Text("Edit trackers"))
                    .accessibilityIdentifier("devices.edit")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    /// No tracker yet: the one primary is Choose.
    private var choose: some View {
        PillButton(Text("Choose"), systemImage: "plus") { editing = true }
            .accessibilityIdentifier("devices.choose")
    }

    // MARK: check sync

    /// Check sync on the selection, the page's one primary, and "Last checked …" under it.
    private var checkSync: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("See whether your trackers' data arrives in Apple Health.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PillButton(Text("Check sync")) {
                check = .make(env: env, trackers: model.selection.trackers)
                route = .check
            }
            .accessibilityIdentifier("devices.checkSync")
            .padding(.top, DevicesSpec.pillGap)
            Text(model.lastCheckedText)
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, DevicesSpec.captionGap)
                .accessibilityIdentifier("devices.lastChecked")
        }
    }

    // MARK: seen in Apple Health

    /// `User.sources`: a row per source, or the outline card while the first load runs. A list from an earlier load (offline,
    /// or the loads fail) keeps its rows and says when it was loaded.
    @ViewBuilder private var seen: some View {
        let freshness = model.sourcesFreshness
        if freshness == .loading {
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle(Text("Seen in Apple Health"))
                    .padding(.bottom, GroupedListSpec.titleGap)
                PlaceholderRow(height: GroupedListSpec.rowMinHeight) {
                    Text("Loading…")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
                GroupFooter(seenFooter(freshness))
                    .padding(.top, GroupedListSpec.footerGap)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("devices.seen")
        } else {
            GroupedCard(Text("Seen in Apple Health"), footer: seenFooter(freshness)) {
                let rows = model.sources
                if freshness == .notLoaded {
                    sentenceRow(Text("Not loaded yet"))
                } else if rows.isEmpty {
                    sentenceRow(Text("No data from other apps yet."))
                } else {
                    ForEach(rows) { row in
                        SourceRowView(row: row, lastSeen: model.lastSeenText(row))
                    }
                }
            }
            .accessibilityIdentifier("devices.seen")
        }
    }

    private func seenFooter(_ freshness: SourcesFreshness) -> Text {
        let footer = Text("Apps and devices that sent data to RYFT in the last 30 days.")
        guard case .stale(let loaded) = freshness else { return footer }
        return footer + Text(verbatim: " ") + Text(verbatim: model.lastLoadedText(loaded))
    }

    // MARK: Apple Health access

    /// RYFT's own read permission: its status (`warning` with its word when it needs the user), Allow access while RYFT may
    /// still ask, the catalog's route in the Health app, and Open Health.
    private var health: some View {
        GroupedCard(Text("Apple Health access")) {
            GroupedRow.value(Text("Apple Health"),
                             value: Text(model.healthStatusText)
                                 .foregroundStyle(model.healthNeedsAttention ? Theme.warning : Theme.textTertiary))
            if model.canAskForHealth {
                GroupedRow.action(Text("Allow access"), systemImage: "heart", busy: askingForHealth) {
                    // Busy before the task starts: a second tap in the same frame finds it busy.
                    askingForHealth = true
                    Task {
                        await model.requestHealthAccess()
                        askingForHealth = false
                    }
                }
            }
            let steps = model.healthAccessSteps
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: DevicesSpec.stepSpacing) {
                    Text("To check what RYFT may read:")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        NumberedStep(number: index + 1, verbatim: step, total: steps.count)
                    }
                }
                .padding(.horizontal, GroupedListSpec.rowInset)
                .padding(.vertical, DevicesSpec.blockPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .groupedRowHairline()
                .accessibilityElement(children: .contain)
            }
            GroupedRow.action(Text("Open Health"), systemImage: "arrow.up.right", hint: ProfileView.healthAppHint,
                              identifier: "devices.openHealth") {
                HealthLinks.open(with: openURL)
            }
        }
    }

    // MARK: sync details

    private var syncDetails: some View {
        GroupedCard {
            GroupedRow.push(Text("Sync details"), detail: Text("For support: requests and streams."),
                            hint: Text("Opens sync details"), identifier: "devices.syncDetails") {
                route = .syncDetails
            }
        }
    }

    /// A sentence where the card's rows would be (none chosen, nothing loaded): 15 pt `textSecondary`.
    private func sentenceRow(_ text: Text) -> some View {
        text
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, GroupedListSpec.rowInset)
            .padding(.vertical, DevicesSpec.blockPadding)
            .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
            .groupedRowHairline()
    }
}

/// Devices & sync's own numbers (§4.4): the rest is the grouped list's (`GroupedListSpec`).
enum DevicesSpec {
    /// The sentence → the Check sync pill, the pill → "Last checked".
    static let pillGap: CGFloat = 12, captionGap: CGFloat = 8
    /// "Last checked" → "Seen in Apple Health".
    static let seenGap: CGFloat = 24
    /// A block of text in a card (a sentence, the Health steps): 14 above and below, the steps 10 apart.
    static let blockPadding: CGFloat = 14, stepSpacing: CGFloat = 10
}

/// What Devices & sync pushes.
private enum DevicesRoute: Hashable {
    case tracker(String)
    case check
    case syncDetails
}

/// A source the platform saw: RYFT's name for it, what it sent, when; one RYFT doesn't know is still read. Not interactive:
/// one element.
private struct SourceRowView: View {
    let row: DevicesViewModel.SourceRow
    let lastSeen: String

    var body: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
            Text(verbatim: row.name)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
            Group {
                Text(verbatim: row.kinds)
                Text(verbatim: lastSeen)
                    .monospacedDigit()
                if !row.known {
                    Text("Not a tracker RYFT knows. It still counts.")
                }
            }
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textTertiary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, GroupedListSpec.textPadding)
        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
        .groupedRowHairline()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("devices.source")
    }
}

// Previews only: `MockDevicesStates` is a debug type, and a Release build has no previews.
#if DEBUG
#Preview("Devices & sync · two trackers") {
    let g = MockDevicesStates.graph(later: ["oura"])
    NavigationStack { DevicesAndSyncView(model: g.devices) }
        .previewEnvironment(g.state)
}

#Preview("Devices & sync · none chosen") {
    let g = MockDevicesStates.graph(trackers: [], checkedAgo: nil)
    NavigationStack { DevicesAndSyncView(model: g.devices) }
        .previewEnvironment(g.state)
}

#Preview("Devices & sync · offline, stale list") {
    let g = MockDevicesStates.graph(demo: false, online: false, sources: .loaded(ago: 7_200))
    NavigationStack { DevicesAndSyncView(model: g.devices) }
        .previewEnvironment(g.state)
}

#Preview("Devices & sync · loading") {
    let g = MockDevicesStates.graph(demo: false, sources: .never)
    NavigationStack { DevicesAndSyncView(model: g.devices) }
        .previewEnvironment(g.state)
}

#Preview("Devices & sync · AX3") {
    let g = MockDevicesStates.graph(trackers: ["garmin"])
    NavigationStack { DevicesAndSyncView(model: g.devices) }
        .previewEnvironment(g.state)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
