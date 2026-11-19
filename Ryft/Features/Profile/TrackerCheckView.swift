import SwiftUI

// MARK: - check sync

/// Check sync (ui.md §5; Nocturne PR 6 C2, design-pr6-c-settings.md §4.5, drafts c-08, c-08b): per selected tracker, what
/// reached Apple Health in the last 48 hours, the expected gaps as plain facts, and the fix for an unexpected one. Pushed from
/// Devices & sync (the subpage frame, the one primary pinned), or inline in onboarding's setup step (`embedded`: the same
/// blocks, no frame of its own, the action as the secondary pill under them, since the step's Done is the primary). Runs on
/// appearance. Offline it says RYFT can't be reached; the check itself reads Apple Health on this iPhone and still runs.
struct TrackerCheckView: View {
    @State private var model: TrackerCheckModel
    /// Allow access's prompt is up: the pill is busy until it answers.
    @State private var asking = false
    private let embedded: Bool
    private let placement: DevicesPagePlacement

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    init(model: TrackerCheckModel, embedded: Bool = false, placement: DevicesPagePlacement = .pushed) {
        _model = State(initialValue: model)
        self.embedded = embedded
        self.placement = placement
    }

    private var text: TrackerCheckText { TrackerCheckText(locale: locale) }

    var body: some View {
        Group {
            if embedded {
                VStack(alignment: .leading, spacing: CheckSyncSpec.blockSpacing) {
                    content
                    primary(.secondary)
                }
            } else {
                SubpageScaffold(Text("Check sync"), navigation: placement.navigation, isSheet: placement.isSheet) {
                    content
                }
                // Pinned, so it's reachable at every text size.
                .pinnedBar { primary(.primary) }
                .devicesPagePlacement(placement)
            }
        }
        .task { await model.start(stagger: !reduceMotion) }
        .onChange(of: model.phase) { _, phase in
            // One announcement when it's done; the rows stay silent while they resolve.
            guard phase == .done else { return }
            AccessibilityNotification.Announcement(text.announcement(model.checks)).post()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: CheckSyncSpec.blockSpacing) {
            Text("Looks at the last 48 hours in Apple Health. The check uploads nothing.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.isOffline {
                notice(Self.offline, systemImage: "wifi.slash")
                    .accessibilityIdentifier("check.offline")
            }
            switch model.phase {
            case .notAsked:
                // D2 K9: not an error; the pinned pill is Allow access.
                notice(String(localized: "RYFT hasn't asked for Health access yet."), systemImage: "lock")
            case .unavailable:
                notice(String(localized: "Apple Health isn't available on this device."), systemImage: "heart.slash")
                    .accessibilityIdentifier("check.note")
            case .locked:
                notice(String(localized: "Unlock your iPhone to check: Apple Health can't be read while it's locked."),
                       systemImage: "lock")
                    .accessibilityIdentifier("check.note")
            case .failed:
                notice(String(localized: "Apple Health couldn't be read this time. Tap Check again."),
                       systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("check.note")
            case .idle, .running, .done:
                ForEach(model.checks) { check in
                    if let tracker = model.trackers.first(where: { $0.id == check.trackerID }) {
                        TrackerCheckBlock(check: check, tracker: tracker,
                                          healthAccess: model.catalog.healthAccess.value(for: locale.identifier),
                                          now: model.checkedAt ?? model.now, text: text)
                    }
                }
                if model.showsPermissionCard { permissionCard }
            }
        }
    }

    /// Offline: what works (the check reads this iPhone) and what waits (RYFT).
    static var offline: String {
        String(localized: "You're offline. RYFT can't be reached, but the check reads Apple Health on this iPhone. Your data syncs when you're back online.",
               comment: "Check sync without a connection: the check runs on the iPhone; uploads wait for the connection.")
    }

    /// The page's one primary (§4.5, D6C-15): Allow access while RYFT never asked, else Check again, busy while it runs.
    @ViewBuilder private func primary(_ style: PillButton.Style) -> some View {
        switch CheckSyncPrimary.decide(model.phase) {
        case .allowAccess:
            PillButton(Text("Allow access"), style: style, busy: asking) {
                // Busy before the task starts: a second tap in the same frame finds it busy.
                asking = true
                Task {
                    await model.requestAccess()
                    asking = false
                }
            }
            .accessibilityIdentifier("check.allow")
        case .checkAgain(let busy, let enabled):
            PillButton(busy ? Text("Checking…") : Text("Check again"), style: style, systemImage: PillButton.Icon.retry,
                       busy: busy) {
                await model.run(stagger: !reduceMotion)
            }
            .disabled(!enabled)
            .accessibilityIdentifier("check.run")
        }
    }

    /// A notice that is part of the page: read as one element when VoiceOver gets to it, not announced.
    private func notice(_ message: String, systemImage: String) -> some View {
        InlineMessage(message: message, systemImage: systemImage, announces: false, readsAsOne: true)
    }

    /// D2 K7, last: iOS tells RYFT nothing about read access, so both possibilities and where to look; never
    /// "denied" (ui.md errata 5). The Health app opens at its start screen: the catalog's path goes with it.
    private var permissionCard: some View {
        GroupedCard {
            HStack(alignment: .firstTextBaseline, spacing: InlineMessageSpec.glyphGap) {
                Image(systemName: "lock")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: CheckSyncSpec.stepSpacing) {
                    if model.mayNotRead {
                        Text("Even your iPhone's steps aren't arriving, so RYFT may not be allowed to read Health.")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("check.mayNotRead")
                    }
                    // swiftlint:disable:next line_length
                    Text("iOS doesn't tell apps whether they may read Health data: RYFT only sees what it's allowed to read. So “nothing yet” can mean no data, or that RYFT isn't allowed to read it.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    CheckSteps(steps: model.catalog.healthAccess.value(for: locale.identifier))
                }
            }
            .padding(.horizontal, GroupedListSpec.rowInset)
            .padding(.vertical, CheckSyncSpec.blockPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            GroupedRow.action(Text("Open Health"), systemImage: "arrow.up.right", hint: ProfileView.healthAppHint,
                              identifier: "check.openHealth") {
                HealthLinks.open(with: openURL)
            }
        }
        .accessibilityIdentifier("check.permission")
    }
}

/// Check sync's own numbers (§4.5); rows and cards are the grouped list's (`GroupedListSpec`).
enum CheckSyncSpec {
    /// Between the page's blocks: the sentence, the notices, one tracker and the next.
    static let blockSpacing: CGFloat = 24
    /// A tracker's name → its summary → its rows card.
    static let summaryGap: CGFloat = 8, rowsGap: CGFloat = 12
    /// The fix panel: `surfaceRaised`, radius 16, 8 in from the card, 16 inside.
    static let fixRadius: CGFloat = 16, fixInset: CGFloat = 8, fixPadding: CGFloat = 16
    /// A block of text in a card, and the numbered steps.
    static let blockPadding: CGFloat = 14, stepSpacing: CGFloat = 10
    /// CheckRow's glyph column → its name ("That's normal." lines up with the names).
    static let rowGlyphGap: CGFloat = 10
}

/// One tracker in Check sync: the glyph and name, the summary, the rows card with the fix under the last gap, and the
/// links the fix needs; silent, can't-read, Other and an Apple device RYFT can't tell apart say so instead of a list.
/// VoiceOver: a container named for the tracker.
private struct TrackerCheckBlock: View {
    let check: TrackerCheck
    let tracker: Tracker
    /// The catalog's steps for RYFT's own read permission.
    let healthAccess: [String]
    let now: Date
    let text: TrackerCheckText

    @State private var showsDetails = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .headline) private var headerGlyph: CGFloat = 17
    @ScaledMetric(relativeTo: .headline) private var headerGlyphWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .callout) private var trayGlyph: CGFloat = 24
    /// "That's normal." lines up with the row names: CheckRow's glyph column (scaled like there) plus its 10 pt.
    @ScaledMetric(relativeTo: .callout) private var rowGlyphWidth: CGFloat = 24

    private var app: String { check.app ?? tracker.name }
    /// Only a vendor's app has a store page to send people to.
    private var storeURL: URL? { tracker.integration == .vendorApp ? tracker.appStoreURL : nil }
    private var steps: [String] { tracker.setup.value(for: locale.identifier) }
    /// RYFT can't see a missing type at all: its own permission's steps and Open Health go with the fix.
    private var unknownType: Bool { check.rows.contains { $0.check == .missing(visible: false) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            switch check.overall {
            case .cantRead:
                sentence(Text("RYFT can't read \(tracker.name) data on iPhone today."))
            case .unidentified:
                sentence(Text(verbatim: text.unidentified))
                    .accessibilityIdentifier("check.unidentified")
            case .silent:
                silent
            case .unknownTracker:
                unknown
            case .checking, .ok, .nightMissing, .needsFix:
                summary
                    .padding(.top, CheckSyncSpec.summaryGap)
                GroupedCard { rows }
                    .padding(.top, CheckSyncSpec.rowsGap)
                if check.rows.contains(where: \.check.isMissing) {
                    links(health: unknownType)
                        .padding(.top, GroupedListSpec.groupSpacing)
                }
            }
        }
        .animation(Theme.Motion.respecting(reduceMotion), value: check.overall)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: check.app ?? tracker.name))
        .accessibilityIdentifier("check.card.\(tracker.id)")
    }

    private var header: some View {
        HStack(spacing: CheckSyncSpec.rowGlyphGap) {
            Image(systemName: tracker.symbol)
                .font(.system(size: headerGlyph, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: headerGlyphWidth)
                .accessibilityHidden(true)
            Text(verbatim: tracker.name)
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func sentence(_ text: Text) -> some View {
        text
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, CheckSyncSpec.summaryGap)
    }

    /// Numbers first; then, without last night, where it is.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if check.overall == .checking {
                    Text("Checking Apple Health…")
                } else {
                    Text(verbatim: text.summary(expected: check.expected, arriving: check.arriving, needsFix: check.needsFix))
                }
            }
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .accessibilityIdentifier("check.summary")
            if check.overall == .nightMissing {
                Group {
                    if storeURL == nil {
                        Text("Last night hasn't reached Apple Health yet.")
                    } else {
                        Text("Last night hasn't reached Apple Health yet. Open \(app) to sync it.")
                    }
                }
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The rows; "That's normal." once, under the first expected gap; the fix once, under the last unexpected one.
    /// Just my iPhone folds what an iPhone can't record into one quiet row (D2 C3).
    @ViewBuilder private var rows: some View {
        let phone = tracker.id == "iphone" && check.overall != .checking
        let shown = phone ? check.rows.filter { $0.check.isArrived || $0.check.isMissing || $0.signal == .steps } : check.rows
        let firstExpected = shown.first { $0.check == .notShared }?.signal
        let lastMissing = shown.last(where: \.check.isMissing)?.signal
        ForEach(shown) { row in
            VStack(alignment: .leading, spacing: 0) {
                checkRow(row)
                    .accessibilityIdentifier("check.row.\(row.signal.rawValue)")
                if row.signal == firstExpected {
                    Text("That's normal.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, rowGlyphWidth + CheckSyncSpec.rowGlyphGap)
                        .padding(.bottom, CheckSyncSpec.stepSpacing)
                }
            }
            .padding(.horizontal, GroupedListSpec.rowInset)
            .groupedRowHairline()
            if row.signal == lastMissing {
                fix
                    .padding(.horizontal, CheckSyncSpec.fixInset)
                    .padding(.bottom, CheckSyncSpec.fixInset)
            }
        }
        if phone {
            CheckRow(name: String(localized: "Other signals", bundle: text.bundle, locale: locale),
                     result: String(localized: "not available from an iPhone", bundle: text.bundle, locale: locale),
                     kind: .expected)
                .padding(.horizontal, GroupedListSpec.rowInset)
                .groupedRowHairline()
        }
    }

    private func checkRow(_ row: TrackerCheck.Row) -> CheckRow {
        CheckRow(name: text.name(row.signal),
                 result: text.result(row.check, signal: row.signal, app: check.app, now: now),
                 kind: CheckRow.Kind(row.check),
                 spoken: text.spoken(row.check, signal: row.signal, app: check.app, now: now))
    }

    /// The fix panel: the vendor's permission first, then RYFT's when RYFT can't see the type at all (§4.5); the steps
    /// inline (ui.md errata 4). Its links follow under the card.
    private var fix: some View {
        VStack(alignment: .leading, spacing: CheckSyncSpec.stepSpacing) {
            Text(verbatim: text.fixLead(check))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            CheckSteps(steps: steps + (unknownType ? healthAccess : []))
        }
        .padding(CheckSyncSpec.fixPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: CheckSyncSpec.fixRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("check.fix")
    }

    /// "{app} in the App Store" (it opens the store page, which says "Open" when the app is installed; ui.md errata 2) and
    /// "Open Health", as link-out rows in a card of their own.
    @ViewBuilder private func links(health: Bool) -> some View {
        if storeURL != nil || health {
            GroupedCard { linkRows(health: health) }
        }
    }

    @ViewBuilder private func linkRows(health: Bool) -> some View {
        if let storeURL {
            GroupedRow.linkOut(Text("\(app) in the App Store"), hint: Text("Opens the App Store."), identifier: "check.openApp",
                               url: storeURL)
        }
        if health {
            GroupedRow.action(Text("Open Health"), systemImage: "arrow.up.right", hint: ProfileView.healthAppHint) {
                HealthLinks.open(with: openURL)
            }
        }
    }

    /// D2 K5: what to do first, the usual cause for a vendor app, and the rows behind Show details. An Apple device
    /// is worn, not opened.
    private var silent: some View {
        GroupedCard {
            VStack(alignment: .leading, spacing: CheckSyncSpec.stepSpacing) {
                Image(systemName: "tray")
                    .font(.system(size: trayGlyph, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                Text(verbatim: text.silent(check))
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("check.silent")
                if storeURL != nil {
                    Text("If it still shows nothing after it has synced, the Apple Health permission is the usual cause.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, GroupedListSpec.rowInset)
            .padding(.vertical, CheckSyncSpec.blockPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            linkRows(health: false)
            GroupedRow.action(showsDetails ? Text("Hide details") : Text("Show details"),
                              systemImage: showsDetails ? "chevron.up" : "chevron.down", identifier: "check.details") {
                showsDetails.toggle()
            }
            if showsDetails {
                if !steps.isEmpty {
                    CheckSteps(steps: steps)
                        .padding(.horizontal, GroupedListSpec.rowInset)
                        .padding(.vertical, CheckSyncSpec.blockPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .groupedRowHairline()
                }
                ForEach(check.rows) {
                    checkRow($0)
                        .padding(.horizontal, GroupedListSpec.rowInset)
                        .groupedRowHairline()
                }
            }
        }
        .padding(.top, CheckSyncSpec.summaryGap)
    }

    /// D2 C4: only what apps the catalog doesn't know sent; nothing promised, nothing missing.
    @ViewBuilder private var unknown: some View {
        if check.rows.isEmpty {
            Text(verbatim: text.silent(check))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, CheckSyncSpec.summaryGap)
                .accessibilityIdentifier("check.silent")
        } else {
            sentence(Text("From apps RYFT doesn't know yet:"))
            GroupedCard {
                ForEach(check.rows) { row in
                    checkRow(row)
                        .accessibilityIdentifier("check.row.\(row.signal.rawValue)")
                        .padding(.horizontal, GroupedListSpec.rowInset)
                        .groupedRowHairline()
                }
            }
            .padding(.top, CheckSyncSpec.rowsGap)
        }
    }
}

/// Catalog steps, numbered (`NumberedStep`, the outlined circle): plain text only (design.md §2.5).
private struct CheckSteps: View {
    let steps: [String]

    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: CheckSyncSpec.stepSpacing) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    NumberedStep(number: index + 1, verbatim: step, total: steps.count)
                }
            }
        }
    }
}

// Previews only: `MockDevicesStates` is a debug type, and a Release build has no previews.
#if DEBUG
/// A check on mock data in one state, without reading (`MockDevicesStates.staged`).
@MainActor
private func checkPreview(_ scenario: SyncCheckScenario, _ phase: TrackerCheckModel.Phase = .done, online: Bool = true,
                          size: DynamicTypeSize = .large) -> some View {
    let g = MockDevicesStates.graph(demo: online, online: online, trackers: scenario.trackers)
    let model = g.check(scenario)
    MockDevicesStates.staged(model, phase, scenario: scenario)
    return NavigationStack { TrackerCheckView(model: model) }
        .previewEnvironment(g.state)
        .environment(\.dynamicTypeSize, size)
}

#Preview("Check sync · Garmin") { checkPreview(.garmin) }
#Preview("Check sync · Garmin · AX3") { checkPreview(.garmin, size: .accessibility3) }
#Preview("Check sync · sleep should arrive") { checkPreview(.garminSleepOff) }
#Preview("Check sync · night missing") { checkPreview(.garminNightMissing) }
#Preview("Check sync · silent") { checkPreview(.garminSilent) }
#Preview("Check sync · nothing readable") { checkPreview(.nothingReadable) }
#Preview("Check sync · Apple Watch") { checkPreview(.appleWatch) }
#Preview("Check sync · running") { checkPreview(.garmin, .running) }
#Preview("Check sync · offline") { checkPreview(.garmin, online: false) }
#Preview("Check sync · not asked") { checkPreview(.garmin, .notAsked) }
#Preview("Check sync · locked") { checkPreview(.garmin, .locked) }
#endif
