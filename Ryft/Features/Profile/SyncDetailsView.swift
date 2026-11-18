import SwiftUI

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

#Preview("Sync details · de") {
    let state = AppState.preview()
    let sync = SyncService(env: state.env)
    NavigationStack {
        SyncDetailsView(model: SyncDetailsModel(state: state, sync: sync,
                                                coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                             clock: state.env.clock)))
    }
    .previewEnvironment(state)
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

#Preview("Sync details · loaded data · de · AX3") {
    let state = AppState.preview()
    let sync = SyncService(env: state.env)
    SyncDetailsPreview.seed(state.env.reads)
    return NavigationStack {
        SyncDetailsView(model: SyncDetailsModel(state: state, sync: sync,
                                                coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                             clock: state.env.clock)))
    }
    .previewEnvironment(state)
    .environment(\.locale, Locale(identifier: "de"))
    .environment(\.dynamicTypeSize, .accessibility3)
}
