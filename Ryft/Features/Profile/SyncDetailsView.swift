import SwiftUI

/// Profile → Sync details (Nocturne PR 6 C2, design-pr6-c-settings.md §4.6, drafts c-09, c-09b): for support, what the sync
/// knows, numbers first: the engine (its state never "Up to date" without an upload on record or a connection; the last
/// upload's real age), what waits to be sent (activities and nights, workouts, reports), what the app loaded, each stream,
/// the last requests with their IDs, and "Sync last 3 days again", "Copy diagnostics", "Full resync" (the two that upload
/// are disabled offline, and the footer says why). Monospace only for paths and IDs.
struct SyncDetailsView: View {
    let model: SyncDetailsModel
    var placement: DevicesPagePlacement = .pushed
    @State private var showResyncConfirm = false
    @State private var resending = false
    @State private var resyncing = false

    var body: some View {
        SubpageScaffold(Text("Sync details"), navigation: placement.navigation, isSheet: placement.isSheet) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                if model.isOffline {
                    InlineMessage(message: String(localized: "Offline — will sync when back"), systemImage: "wifi.slash",
                                  announces: false, readsAsOne: true)
                        .accessibilityIdentifier("syncDetails.offline")
                }
                engine
                waiting
                loadedData
                streams
                requests
                actions
            }
        }
        .devicesPagePlacement(placement)
        .task { await model.loadQueue() }
        .onChange(of: model.copied) { _, copied in
            if copied { AccessibilityNotification.Announcement(String(localized: "Copied")).post() }
        }
        .confirmationDialog("Re-upload the last 90\u{00A0}days of Health data?", isPresented: $showResyncConfirm,
                            titleVisibility: .visible) {
            Button("Re-sync", role: .destructive) {
                resyncing = true
                Task {
                    await model.fullResync()
                    resyncing = false
                }
            }
        } message: {
            Text("This uploads everything again. It can take a few minutes on the first run.")
        }
        .analyticsScreen(.syncDetails)
    }

    private var engine: some View {
        GroupedCard(Text("Engine")) {
            GroupedRow.value(Text("State"),
                             value: Text(model.phaseText)
                                 .foregroundStyle(model.stateNeedsAttention ? Theme.warning : Theme.textTertiary),
                             identifier: "syncDetails.state")
            // The last upload's age, kept current like Loaded data's times.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                GroupedRow.value(Text("Last sync"), value: Text(model.lastSyncText(now: context.date)),
                                 identifier: "syncDetails.lastSync")
            }
            GroupedRow.value(Text("Scoring"), value: Text(model.scoringText),
                             detail: model.scoringIsSlow ? Text("Taking longer than usual") : nil)
            GroupedRow.value(Text("Queue"), value: Text(model.queueText))
            GroupedRow.value(Text("Backlog"), value: Text(model.backlogText))
            GroupedRow.value(Text("Uploaded"), value: Text(model.uploadedText))
            if model.engine.pendingDeletions > 0 {
                GroupedRow.value(Text("Deletions kept"), value: Text(model.engine.pendingDeletions.formatted()))
            }
            if let error = model.lastErrorText {
                Text(verbatim: error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.warning)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, GroupedListSpec.rowInset)
                    .padding(.vertical, SyncDetailsSpec.blockPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .groupedRowHairline()
                    .accessibilityIdentifier("syncDetails.lastError")
            }
        }
        .accessibilityIdentifier("syncDetails.engine")
    }

    /// What this iPhone keeps until RYFT confirms it, beside Apple Health's uploads: a count per kind, "None" when nothing
    /// waits, and why the workouts wait when a gate holds them. A recording isn't counted until it is saved.
    private var waiting: some View {
        GroupedCard(Text("Waiting to send", comment: "Sync details: the group of what this iPhone keeps until RYFT confirms it.")) {
            GroupedRow.value(Text("Activities and nights",
                                  comment: "Sync details → Waiting to send: activities and nights saved on this iPhone."),
                             value: Text(verbatim: SyncDetailsModel.waitingText(model.unsentActivities)),
                             identifier: "syncDetails.unsent")
            GroupedRow.value(Text("Workouts"), value: Text(verbatim: SyncDetailsModel.waitingText(model.unsentWorkouts)),
                             detail: model.workoutsHeldText.map { Text(verbatim: $0).foregroundStyle(Theme.warning) },
                             identifier: "syncDetails.unsentWorkouts")
            GroupedRow.value(Text("Reports", comment: "Sync details → Waiting to send: problem reports kept for later."),
                             value: Text(verbatim: SyncDetailsModel.waitingText(model.unsentReports)),
                             identifier: "syncDetails.unsentReports")
        }
        .accessibilityIdentifier("syncDetails.waiting")
    }

    /// What the app reads (uploads are Streams): when each loaded, and how its last fetches went.
    private var loadedData: some View {
        GroupedCard(Text("Loaded data")) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.resources) { row in
                        LoadedDataRow(row: row, now: context.date)
                    }
                }
            }
        }
    }

    private var streams: some View {
        GroupedCard(Text("Streams")) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.streams) { row in
                        let newest = Text(verbatim: row.newestLine(now: context.date))
                        let lines = row.lastPageText.map { newest + Text(verbatim: "\n") + Text($0) } ?? newest
                        GroupedRow.value(Text(row.title), value: Text((row.progress?.sent ?? 0).formatted()), detail: lines,
                                         identifier: "syncDetails.stream.\(row.id)")
                    }
                }
            }
        }
    }

    private var requests: some View {
        GroupedCard(Text("Last requests")) {
            if model.requests.isEmpty {
                Text("No requests since launch.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, GroupedListSpec.rowInset)
                    .padding(.vertical, SyncDetailsSpec.blockPadding)
                    .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: SyncDetailsSpec.requestSpacing) {
                    ForEach(model.requests) { RequestLine(request: $0) }
                }
                .padding(.horizontal, GroupedListSpec.rowInset)
                .padding(.vertical, SyncDetailsSpec.blockPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("syncDetails.requests")
    }

    /// The actions as rows: two that work here, the destructive one last; none while a sync can't run, and offline the
    /// footer says why (copying always can).
    private var actions: some View {
        GroupedCard(footer: actionsFooter) {
            GroupedRow.action(Text("Sync last 3\u{00A0}days again"), systemImage: "arrow.clockwise", busy: resending,
                              identifier: "syncDetails.resendRecent") {
                // Busy before the task starts: a second tap in the same frame finds it busy.
                resending = true
                Task {
                    await model.resendRecent()
                    resending = false
                }
            }
            .disabled(!model.canSyncAgain)
            GroupedRow.action(model.copied ? Text("Copied") : Text("Copy diagnostics"),
                              systemImage: model.copied ? "checkmark" : "doc.on.doc", hint: SyncDetailsView.diagnosticsNote,
                              identifier: "syncDetails.copy") {
                Task { await model.copyAndConfirm() }
            }
            GroupedRow.destructive(Text("Full resync"), busy: resyncing, identifier: "syncDetails.fullResync") {
                showResyncConfirm = true
            }
                .disabled(!model.canSyncAgain)
        }
    }

    private var actionsFooter: Text {
        guard model.isOffline else { return SyncDetailsView.diagnosticsNote }
        return Text("You're offline. Syncing again works when you're back online.",
                    comment: "Sync details: under the actions while offline; Sync last 3 days again and Full resync are disabled.")
            + Text(verbatim: " ") + SyncDetailsView.diagnosticsNote
    }

    /// What Copy diagnostics copies: the group's footer and the row's VoiceOver hint.
    static var diagnosticsNote: Text {
        Text("Counts, dates and request IDs for support; no health data.",
             comment: "Sync details: under the actions, and the VoiceOver hint of Copy diagnostics.")
    }
}

/// Sync details' own numbers (§4.6); the rest is the grouped list's.
enum SyncDetailsSpec {
    /// A block of text in a card (the last error, the requests), and one request line → the next.
    static let blockPadding: CGFloat = 12, requestSpacing: CGFloat = 10
}

/// Sync details as a sheet (Today's status line): the sheet's page, with Close.
struct SyncDetailsSheet: View {
    let model: SyncDetailsModel

    var body: some View {
        SyncDetailsView(model: model, placement: .sheet)
    }
}

/// One request: the status, the method and the path in 12 pt monospace (`warning` when it wasn't a 2xx), then its request ID
/// and time in 11 pt. Both wrap; one element.
private struct RequestLine: View {
    let request: APIStatus.RequestFailure

    private var served: Bool { (200..<300).contains(request.status) }

    var body: some View {
        let r = request
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(r.transport ?? String(r.status))\(r.code.map { " \($0)" } ?? "") \(r.method) \(redactedPath(r.path))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(served ? Theme.textSecondary : Theme.warning)
            Text(verbatim: "\(r.requestID ?? "–") · \(r.date.formatted(date: .omitted, time: .standard))")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}

/// One resource in Sync details → Loaded data: name and load time, then its last error or "No errors" (`textSecondary`
/// after a failure, `warning` from the threshold on, the words always saying it).
private struct LoadedDataRow: View {
    let row: SyncDetailsModel.ResourceRow
    let now: Date

    private var statusColor: Color {
        row.isWarning ? Theme.warning : row.state.consecutiveFailures > 0 ? Theme.textSecondary : Theme.textTertiary
    }

    var body: some View {
        GroupedRowLabel(Text(row.name), value: Text(row.fetchedText(now: now)),
                        detail: Text(row.statusText(now: now)).foregroundStyle(statusColor))
            .groupedRowHairline()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(row.spoken(now: now)))
            .accessibilityIdentifier("syncDetails.loaded.\(row.id)")
    }
}

// Previews only: `MockDevicesStates` is a debug type, and a Release build has no previews.
#if DEBUG
#Preview("Sync details") {
    let g = MockDevicesStates.graph(demo: false)
    NavigationStack { SyncDetailsView(model: g.details) }
        .previewEnvironment(g.state)
}

#Preview("Sync details · offline, last sync 3 h ago") {
    let g = MockDevicesStates.graph(demo: false, online: false, lastSync: 3 * 3_600)
    NavigationStack { SyncDetailsView(model: g.details) }
        .previewEnvironment(g.state)
}

#Preview("Sync details · reports waiting") {
    let g = MockDevicesStates.graph(demo: false, reportsWaiting: 2)
    NavigationStack { SyncDetailsView(model: g.details) }
        .previewEnvironment(g.state)
}

#Preview("Sync details · never synced") {
    let g = MockDevicesStates.graph(demo: false, lastSync: nil)
    NavigationStack { SyncDetailsView(model: g.details) }
        .previewEnvironment(g.state)
}

#Preview("Sync details · sheet") {
    let g = MockDevicesStates.graph(demo: false)
    SyncDetailsSheet(model: g.details)
        .previewEnvironment(g.state)
}

#Preview("Sync details · AX3") {
    let g = MockDevicesStates.graph(demo: false)
    NavigationStack { SyncDetailsView(model: g.details) }
        .previewEnvironment(g.state)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
