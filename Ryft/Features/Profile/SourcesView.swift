import SwiftUI

/// Profile → Devices & sync → Sources (design.md §D4.2): per source, its name and glyph, the kinds of data it wrote
/// in 7 days as chips, when it last wrote, a count once one covers the window, and the notes (A, C, B). Pull to
/// refresh reads Apple Health and `GET /v1/me` again. A row opens nothing (per-metric pinning comes later, §D4.6).
struct SourcesView: View {
    let model: SourcesViewModel
    @Environment(\.appEnvironment) private var env
    @Environment(\.openURL) private var openURL
    /// "Check sync" from the nothing-detected state: made on the tap, once.
    @State private var check: TrackerCheckModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                if model.isDemo {
                    Text(String(localized: "Sample data", comment: "Sources in demo mode: the rows are mock data."))
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("sources.sample")
                }
                content
                silent
                footer
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .refreshable { await model.refresh() }
        .navigationTitle(Text(SourcesView.title))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.appeared() }
        .navigationDestination(isPresented: Binding(get: { check != nil }, set: { if !$0 { check = nil } })) {
            if let check { TrackerCheckView(model: check) }
        }
    }

    static var title: String { String(localized: "Sources", comment: "Profile → Devices & sync → Sources: title and row.") }

    // MARK: the state

    @ViewBuilder private var content: some View {
        switch model.screen {
        case .loading:
            section { LoadingRows() }
        case .sources:
            section {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().overlay(Theme.separator) }
                            SourceRow(row: row)
                        }
                    }
                }
            }
        case .nothing:
            section { nothing }
        case .notAsked:
            message(String(localized: "RYFT hasn't asked for Apple Health yet.",
                           comment: "Sources: Apple Health access was never requested."), id: "sources.notAsked") {
                if !model.isDemo {
                    PrimaryButton(title: "Allow access", style: .secondary) { await model.requestAccess() }
                        .accessibilityIdentifier("sources.allowAccess")
                }
            }
        case .unavailable:
            message(String(localized: "Apple Health isn't available on this device."), id: "sources.unavailable") {}
        case .locked:
            message(String(localized: "Unlock your iPhone, then pull to refresh: Apple Health can't be read while it's locked.",
                           comment: "Sources: the phone is locked, so Apple Health can't be read."), id: "sources.locked") {}
        case .failed:
            message(String(localized: "RYFT couldn't read Apple Health. Pull to refresh to try again.",
                           comment: "Sources: reading Apple Health failed."), id: "sources.failed") {}
        }
    }

    /// "LAST 7 DAYS" and its content.
    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let content = content()
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Last 7 days", comment: "Sources: section label over the rows."))
                .ryftLabelStyle()
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }

    /// States 3 and 5: nothing in 7 days, which may also mean RYFT can't read (HealthKit doesn't say which).
    private var nothing: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Apple Health has no data for the last 7 days.",
                                comment: "Sources: nothing detected in 7 days."))
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                    Text(String(localized: "That can mean your tracker has not synced, or that RYFT isn't allowed to read it.",
                                comment: "Sources: nothing detected; HealthKit can't tell an empty store from a denied read."))
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("sources.nothing")
                if model.canCheckSync {
                    PrimaryButton(title: "Check sync", style: .secondary) {
                        check = .make(env: env, trackers: model.checkTrackers)
                    }
                    .accessibilityIdentifier("sources.checkSync")
                }
                if !model.isDemo {
                    PrimaryButton(title: "Open Health", style: .secondary) { HealthLinks.open(with: openURL) }
                        .accessibilityIdentifier("sources.openHealth")
                }
            }
        }
    }

    private func message<Actions: View>(_ text: String, id: String, @ViewBuilder actions: () -> Actions) -> some View {
        let actions = actions()
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(text)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(id)
                actions
            }
        }
    }

    // MARK: picked, not seen

    @ViewBuilder private var silent: some View {
        let rows = model.silentRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Picked in setup, not seen",
                            comment: "Sources: section of trackers picked in setup with nothing in 7 days."))
                    .ryftLabelStyle()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .accessibilityAddTraits(.isHeader)
                ForEach(rows) { row in
                    SilentSourceRow(row: row) { url in openURL(url) }
                }
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.isPlatformOffline {
                Text(String(localized: "RYFT can't reach its server. Counts are from Apple Health.",
                            comment: "Sources: GET /v1/me failed; the rows come from Apple Health alone."))
                    .accessibilityIdentifier("sources.offline")
            }
            Text(String(localized: "Apps and devices that sent data to Apple Health in the last 7 days.",
                        comment: "Sources: footer, the window the rows cover."))
            Text(String(localized: "Pull to refresh re-reads Apple Health.", comment: "Sources: footer."))
        }
        .font(.ryft(.caption))
        // Secondary ink: tertiary is under 4.5:1 on the background in light mode.
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A Sources row (design.md §D4.2): glyph, name, last seen, chips, the count; then its notes, each its own
/// VoiceOver element after the row (they can carry an action). The row isn't a button.
private struct SourceRow: View {
    let row: SourcesViewModel.Row
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .callout) private var glyphColumn: CGFloat = 22
    @ScaledMetric(relativeTo: .callout) private var glyph: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: row.symbol)
                    .font(.system(size: glyph, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: glyphColumn)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    header
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(row.chips, id: \.self) { SourceBadge(title: $0, glyph: nil) }
                    }
                    if let count = row.count {
                        Text(verbatim: count)
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if !row.known {
                        Text(verbatim: SourcesViewModel.unknownSource)
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: row.spoken))
            .accessibilityIdentifier("sources.row.\(row.id)")
            ForEach(row.notes) { note in
                SourceNoteView(note: note)
                    .padding(.leading, glyphColumn + 12)
            }
        }
    }

    /// Name and last seen on one line; at accessibility sizes the time drops under the name.
    @ViewBuilder private var header: some View {
        let name = Text(verbatim: row.name)
            .font(.ryft(.callout))
            .foregroundStyle(row.known ? Theme.textPrimary : Theme.textSecondary)
        let seen = Text(verbatim: row.lastSeen)
            .font(.ryft(.caption))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                name.fixedSize(horizontal: false, vertical: true)
                seen
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                name.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                seen
            }
        }
    }
}

/// A note (design.md §D4.3): a 16 pt glyph, words beside it. Only the glyph takes amber (note A); the text stays
/// primary or secondary, so it keeps 4.5:1 on the card in light mode.
private struct SourceNoteView: View {
    let note: SourcesViewModel.Note
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 16

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: note.glyph)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(verbatim: note.text)
                .font(.ryft(.caption))
                .foregroundStyle(note.kind == .silent ? Theme.textPrimary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sources.note.\(note.kind.rawValue)")
    }

    private var tint: Color {
        switch note.kind {
        case .silent: return Theme.warning
        case .notReceived: return Theme.textSecondary
        case .noHRV: return Theme.textTertiary
        }
    }
}

/// A tracker picked in setup with nothing in 7 days: a dashed outline, no fill. Expected, not present; not an error.
private struct SilentSourceRow: View {
    let row: SourcesViewModel.SilentRow
    let open: (URL) -> Void
    @ScaledMetric(relativeTo: .callout) private var glyphColumn: CGFloat = 22
    @ScaledMetric(relativeTo: .callout) private var glyph: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: row.symbol)
                    .font(.system(size: glyph, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: glyphColumn)
                    .accessibilityHidden(true)
                Text(verbatim: row.name)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: row.spoken))
            .accessibilityIdentifier("sources.silent.\(row.id)")
            SourceNoteView(note: row.note)
            if let title = row.storeTitle, let url = row.storeURL {
                Button { open(url) } label: {
                    Text(verbatim: title)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.surfaceRaised, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(Text(String(localized: "Leaves RYFT.", comment: "VoiceOver hint: the button opens another app.")))
                .accessibilityIdentifier("sources.silent.\(row.id).store")
            }
        }
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
            .strokeBorder(Theme.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// The first read (state 1): two outline rows, hairline and no fill, "Reading Apple Health…" in the first. No
/// spinner, no shimmer.
private struct LoadingRows: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { index in
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline)
                    .frame(minHeight: 72)
                    .overlay(alignment: .leading) {
                        if index == 0 {
                            Text(String(localized: "Reading Apple Health…", comment: "Sources: the first read is in flight."))
                                .font(.ryft(.callout))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(Theme.Metrics.cardPadding)
                                .accessibilityIdentifier("sources.loading")
                        }
                    }
                    .accessibilityHidden(index > 0)
            }
        }
    }
}

/// A row that opens Sources: title, the count line under it, chevron (Devices & sync, the tracker setup step).
struct SourcesLinkRow: View {
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: subtitle ?? ""))
        .accessibilityAddTraits(.isButton)
    }
}

/// Sources in a sheet of its own (the tracker setup step; Today's provenance line later): Done closes it.
struct SourcesSheet: View {
    let model: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SourcesView(model: model)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("sources.done")
                    }
                }
        }
    }
}

// MARK: - previews

#if DEBUG

/// Sources on mock data in one state. `store`: a scripted Health (a live read through `SourceDetector`, never this
/// phone's); `platform`: `User.sources` for note C (nil: none); `offline`: `GET /v1/me` fails; `demo`: demo mode.
@MainActor
private func sourcesPreview(_ state: SourcesPreviewState, scheme: ColorScheme = .dark, de: Bool = false,
                            size: DynamicTypeSize = .large) -> some View {
    let (app, model) = state.make()
    return NavigationStack { SourcesView(model: model) }
        .previewEnvironment(app, scheme: scheme)
        .environment(\.locale, Locale(identifier: de ? "de" : "en"))
        .dynamicTypeSize(size)
}

/// The states of design.md §D4.4 on mock data: previews, and `-RyftScreen sources -RyftSourcesState <state>`.
@MainActor
enum SourcesPreviewState: String {
    case sources, notReceived, loading, nothing, mayNotRead, notAsked, offline, demo, locked

    func make() -> (AppState, SourcesViewModel) {
        let now = Date.now
        switch self {
        case .demo:
            let state = AppState.preview(flags: [.devicesSetup: true])
            let selection = TrackerSelectionStore(env: state.env)
            selection.stage(["garmin", "oura"])
            return (state, SourcesViewModel(state: state, selection: selection))
        case .loading, .locked:
            let state = AppState.preview(flags: [.devicesSetup: true])
            let model = SourcesViewModel(state: state, selection: TrackerSelectionStore(env: state.env))
            model.stage(self == .locked ? .locked : nil)
            return (state, model)
        default:
            break
        }
        let store: MockHealthStore
        switch self {
        case .nothing:
            // Something is readable (the iPhone wrote steps once, long ago), just nothing in 7 days.
            store = MockHealthStore()
            store.visible = [.quantity(.steps)]
        case .mayNotRead:
            store = MockHealthStore()
        default:
            store = MockHealthStore.garminLike(now: now)
            store.samples += MockHealthStore.ouraLike(now: now).samples
        }
        if self == .notAsked { store.access = .notAsked }
        let env = AppEnvironment.test(health: store, clock: TestClock(now: now), flags: [.devicesSetup: true],
                                      online: self != .offline)
        let state = AppState(env: env)
        var user = MockData.user
        // The platform has Garmin's heart rate, sleep and steps, and nothing from Oura yet: note C on Oura.
        user.sources = self == .notReceived ? [
            UserSource(name: "Connect", bundleId: "com.garmin.connect.mobile", kinds: [.hr, .sleep, .steps, .workout],
                       lastSeen: now.addingTimeInterval(-1_200)),
            UserSource(name: "Tim's iPhone", bundleId: SourceRef.mockPhone.bundleID, kinds: [.steps], lastSeen: now),
        ] : []
        state.user = user
        let selection = TrackerSelectionStore(env: env)
        selection.stage(["garmin", "oura", "polar"])
        return (state, SourcesViewModel(state: state, selection: selection))
    }
}

#Preview("Sources · Garmin and Oura · dark") { sourcesPreview(.sources) }
#Preview("Sources · Garmin and Oura · light") { sourcesPreview(.sources, scheme: .light) }
#Preview("Sources · not received yet · dark") { sourcesPreview(.notReceived) }
#Preview("Sources · not received yet · light · de") { sourcesPreview(.notReceived, scheme: .light, de: true) }
#Preview("Sources · loading · dark") { sourcesPreview(.loading) }
#Preview("Sources · loading · light") { sourcesPreview(.loading, scheme: .light) }
#Preview("Sources · nothing detected · dark") { sourcesPreview(.nothing) }
#Preview("Sources · nothing detected · light") { sourcesPreview(.nothing, scheme: .light) }
#Preview("Sources · may not read · dark") { sourcesPreview(.mayNotRead) }
#Preview("Sources · not asked · dark") { sourcesPreview(.notAsked) }
#Preview("Sources · not asked · light · de") { sourcesPreview(.notAsked, scheme: .light, de: true) }
#Preview("Sources · offline · dark") { sourcesPreview(.offline) }
#Preview("Sources · offline · light") { sourcesPreview(.offline, scheme: .light) }
#Preview("Sources · locked · dark") { sourcesPreview(.locked) }
#Preview("Sources · demo · dark") { sourcesPreview(.demo) }
#Preview("Sources · demo · light · de") { sourcesPreview(.demo, scheme: .light, de: true) }
#Preview("Sources · AX3 · dark") { sourcesPreview(.sources, size: .accessibility3) }
#Preview("Sources · AX3 · light · de") { sourcesPreview(.notReceived, scheme: .light, de: true, size: .accessibility3) }
#endif
