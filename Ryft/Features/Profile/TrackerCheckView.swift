import SwiftUI

// MARK: - check sync

/// Check sync (ui.md §5): per selected tracker, what reached Apple Health in the last 48 hours, the expected gaps
/// as plain facts, and the fix for an unexpected one. Pushed from Devices & sync, or inline in onboarding's setup
/// step (`embedded`: no scroll view of its own, Check again under the cards). Runs on appearance.
struct TrackerCheckView: View {
    @State private var model: TrackerCheckModel
    private let embedded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    init(model: TrackerCheckModel, embedded: Bool = false) {
        _model = State(initialValue: model)
        self.embedded = embedded
    }

    private var text: TrackerCheckText { TrackerCheckText(locale: locale) }

    var body: some View {
        Group {
            if embedded {
                VStack(alignment: .leading, spacing: 16) {
                    content
                    checkAgain
                }
            } else {
                ScrollView {
                    content
                        .padding(.horizontal, Theme.Metrics.screenPadding)
                        .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
                // Pinned, so it's reachable at every text size.
                .safeAreaInset(edge: .bottom) {
                    checkAgain
                        .padding(.horizontal, Theme.Metrics.screenPadding)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .background(Theme.background)
                }
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle(Text("Check sync"))
                .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Looks at the last 48 hours in Apple Health. The check uploads nothing.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            switch model.phase {
            case .notAsked:
                notAsked
            case .unavailable:
                note("Apple Health isn't available on this device.", systemImage: "heart.slash")
            case .locked:
                note("Unlock your iPhone to check: Apple Health can't be read while it's locked.", systemImage: "lock")
            case .failed:
                note("Apple Health couldn't be read this time. Tap Check again.", systemImage: "exclamationmark.triangle")
            case .idle, .running, .done:
                ForEach(model.checks) { check in
                    if let tracker = model.trackers.first(where: { $0.id == check.trackerID }) {
                        TrackerCheckCard(check: check, tracker: tracker, healthAccess: model.catalog.healthAccess.value(for: locale.identifier),
                                         now: model.checkedAt ?? model.now, text: text)
                    }
                }
                if model.showsPermissionCard { permissionCard }
            }
        }
    }

    /// Teal when it's the screen's one action; secondary inside onboarding's setup step, whose Done is.
    private var checkAgain: some View {
        PrimaryButton(title: model.isRunning ? "Checking…" : "Check again", style: embedded ? .secondary : .primary) {
            await model.run(stagger: !reduceMotion)
        }
            .disabled(model.isRunning || model.phase == .unavailable)
            .accessibilityLabel(model.isRunning ? Text("Checking") : Text("Check again"))
            .accessibilityIdentifier("check.run")
    }

    /// D2 K9: not an error, one action.
    private var notAsked: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RYFT hasn't asked for Health access yet.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Allow access", style: .secondary) { await model.requestAccess() }
                .accessibilityIdentifier("check.allow")
        }
        .checkPanel()
    }

    private func note(_ text: LocalizedStringKey, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .checkPanel()
        .accessibilityIdentifier("check.note")
    }

    /// D2 K7, last: iOS tells RYFT nothing about read access, so both possibilities and where to look; never
    /// "denied" (ui.md errata 5). The Health app opens at its start screen: the catalog's path goes with it.
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
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
            PrimaryButton(title: "Open Health", style: .secondary) { HealthLinks.open(with: openURL) }
                .accessibilityIdentifier("check.openHealth")
        }
        .checkPanel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("check.permission")
    }
}

/// One tracker in Check sync: header, summary, rows, and the fix under the last gap; silent, can't-read, Other and an
/// Apple device RYFT can't tell apart say so instead of a list.
private struct TrackerCheckCard: View {
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
    @ScaledMetric(relativeTo: .callout) private var trayGlyph: CGFloat = 28
    /// "That's normal." lines up with the row names: CheckRow's glyph column (scaled like there) plus its 10 pt.
    @ScaledMetric(relativeTo: .callout) private var rowGlyphWidth: CGFloat = 24

    private var app: String { check.app ?? tracker.name }
    /// Only a vendor's app has a store page to send people to.
    private var storeURL: URL? { tracker.integration == .vendorApp ? tracker.appStoreURL : nil }
    private var steps: [String] { tracker.setup.value(for: locale.identifier) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header
                switch check.overall {
                case .cantRead:
                    Text("RYFT can't read \(tracker.name) data on iPhone today.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .unidentified:
                    Text(verbatim: text.unidentified)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("check.unidentified")
                case .silent:
                    silent
                case .unknownTracker:
                    unknown
                case .checking, .ok, .nightMissing, .needsFix:
                    summary
                    rows
                }
            }
            .animation(Theme.Motion.respecting(reduceMotion), value: check.overall)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: check.app ?? tracker.name))
        .accessibilityIdentifier("check.card.\(tracker.id)")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: tracker.symbol)
                .font(.system(size: headerGlyph, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: headerGlyphWidth)
                .accessibilityHidden(true)
            Text(verbatim: tracker.name)
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Numbers first; then, without last night, where it is.
    @ViewBuilder private var summary: some View {
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
    private var rows: some View {
        let phone = tracker.id == "iphone" && check.overall != .checking
        let shown = phone ? check.rows.filter { $0.check.isArrived || $0.check.isMissing || $0.signal == .steps } : check.rows
        let firstExpected = shown.first { $0.check == .notShared }?.signal
        let lastMissing = shown.last(where: \.check.isMissing)?.signal
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { row in
                if row.signal != shown.first?.signal { hairline }
                checkRow(row)
                    .accessibilityIdentifier("check.row.\(row.signal.rawValue)")
                if row.signal == firstExpected {
                    Text("That's normal.")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, rowGlyphWidth + 10)
                        .padding(.bottom, 8)
                }
                if row.signal == lastMissing {
                    fix.padding(.bottom, 8)
                }
            }
            if phone {
                hairline
                CheckRow(name: String(localized: "Other signals", bundle: text.bundle, locale: locale),
                         result: String(localized: "not available from an iPhone", bundle: text.bundle, locale: locale),
                         kind: .expected)
            }
        }
    }

    private func checkRow(_ row: TrackerCheck.Row) -> CheckRow {
        CheckRow(name: text.name(row.signal),
                 result: text.result(row.check, signal: row.signal, app: check.app, now: now),
                 kind: CheckRow.Kind(row.check),
                 spoken: text.spoken(row.check, signal: row.signal, app: check.app, now: now))
    }

    private var hairline: some View {
        Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline).accessibilityHidden(true)
    }

    /// The vendor's permission first, then RYFT's when RYFT can't see the type at all (§4.5); the steps inline
    /// (ui.md errata 4).
    private var fix: some View {
        let unknown = check.rows.contains { $0.check == .missing(visible: false) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: text.fixLead(check))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            CheckSteps(steps: steps + (unknown ? healthAccess : []))
            buttons(health: unknown, outlined: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("check.fix")
    }

    /// "{app} in the App Store" (it opens the store page, which says "Open" when the app is installed; ui.md
    /// errata 2) and "Open Health". In the raised fix panel they're outlined, or they'd have no shape (errata 4).
    @ViewBuilder private func buttons(health: Bool, outlined: Bool) -> some View {
        if let storeURL {
            PrimaryButton(title: "\(app) in the App Store", style: .secondary) { openURL(storeURL) }
                .overlay { if outlined { Capsule().strokeBorder(Theme.textTertiary, lineWidth: Theme.Metrics.hairline) } }
                .accessibilityIdentifier("check.openApp")
        }
        if health {
            PrimaryButton(title: "Open Health", style: .secondary) { HealthLinks.open(with: openURL) }
                .overlay { if outlined { Capsule().strokeBorder(Theme.textTertiary, lineWidth: Theme.Metrics.hairline) } }
        }
    }

    /// D2 K5: what to do first, the usual cause for a vendor app, and the rows behind Show details. An Apple device
    /// is worn, not opened.
    private var silent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: trayGlyph, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(verbatim: text.silent(check))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("check.silent")
            buttons(health: false, outlined: false)
            if storeURL != nil {
                Text("If it still shows nothing after it has synced, the Apple Health permission is the usual cause.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(showsDetails ? "Hide details" : "Show details") { showsDetails.toggle() }
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityIdentifier("check.details")
            if showsDetails {
                CheckSteps(steps: steps)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(check.rows) { checkRow($0) }
                }
            }
        }
    }

    /// D2 C4: only what apps the catalog doesn't know sent; nothing promised, nothing missing.
    @ViewBuilder private var unknown: some View {
        if check.rows.isEmpty {
            Text(verbatim: text.silent(check))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("check.silent")
        } else {
            Text("From apps RYFT doesn't know yet:")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(check.rows) { row in
                    checkRow(row).accessibilityIdentifier("check.row.\(row.signal.rawValue)")
                }
            }
        }
    }
}

/// Catalog steps, numbered: plain text only (design.md §2.5).
private struct CheckSteps: View {
    let steps: [String]
    @ScaledMetric(relativeTo: .caption) private var badge: CGFloat = 18

    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: "\(index + 1)")
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                            .frame(width: badge, height: badge)
                            .background(Theme.accent.opacity(0.14), in: Circle())
                            .accessibilityHidden(true)
                        Text(verbatim: step)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private extension View {
    /// Check sync's own panels (not a tracker): the inline-message surface.
    func checkPanel() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
    }
}

/// A check on mock data, run on appearance like the real one. `de` shows the German words, not only German formats.
@MainActor
private func checkPreview(_ scenario: SyncCheckScenario, de: Bool = false, size: DynamicTypeSize = .large,
                          stage: ((TrackerCheckModel) -> Void)? = nil) -> some View {
    let env = AppEnvironment.preview()
    let model = TrackerCheckModel(env: env, health: scenario.store(now: .now), trackers: scenario.trackers)
    stage?(model)
    return NavigationStack { TrackerCheckView(model: model) }
        .previewEnvironment()
        .environment(\.locale, Locale(identifier: de ? "de_DE" : "en_US"))
        .environment(\.dynamicTypeSize, size)
}

#Preview("Check sync · Garmin · dark") { checkPreview(.garmin) }
#Preview("Check sync · Garmin · de") { checkPreview(.garmin, de: true) }
#Preview("Check sync · Garmin · AX3") { checkPreview(.garmin, size: .accessibility3) }
#Preview("Check sync · sleep should arrive · dark") { checkPreview(.garminSleepOff) }
#Preview("Check sync · night missing · dark") { checkPreview(.garminNightMissing) }
#Preview("Check sync · silent · dark") { checkPreview(.garminSilent) }
#Preview("Check sync · silent · de") { checkPreview(.garminSilent, de: true) }
#Preview("Check sync · nothing readable · dark") { checkPreview(.nothingReadable) }
#Preview("Check sync · Apple Watch · dark") { checkPreview(.appleWatch) }
#Preview("Check sync · running · dark") { checkPreview(.garmin) { $0.stage(.running) } }
#Preview("Check sync · not asked · dark") { checkPreview(.garmin) { $0.stage(.notAsked) } }
#Preview("Check sync · locked · dark") { checkPreview(.garmin) { $0.stage(.locked) } }
