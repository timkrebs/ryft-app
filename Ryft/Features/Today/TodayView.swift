import OSLog
import SwiftUI

/// Greeting and the sync's status line, readiness gauge (or what's true while data is on
/// its way: the first import, a night being scored, the baseline being learned), Sleep /
/// Recovery / Strain tiles, Train, 7-day trend. Layout only: everything shown comes from
/// `TodayViewModel`.
struct TodayView: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(\.appEnvironment) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: TodayViewModel { screens.today }
    /// The error card's scroll target (the status line's "Couldn't load today · Details").
    static let issueCardID = "today.refreshIssue"
    @State private var showsJournal = false
    /// Counts scores that landed while the night was pending: one success haptic each.
    @State private var landed = 0
    /// The calibration note's link, open in a sheet (design.md §7 rev. 2 §2).
    @State private var calibrationLink: CalibrationLink?
    /// Check sync's model for that sheet: made on the tap, once, not on every redraw.
    @State private var linkCheck: TrackerCheckModel?

    var body: some View {
        // The day's facts and decision, read once for the whole body.
        let day = model.content
        NavigationStack {
            ScrollViewReader { proxy in
                ScreenScaffold {
                    if model.hasDataSource {
                        greeting(day)
                        if let row = day.importRow { ImportRow(progress: row) }
                        hero(day)
                            .coachMarkTarget(.gauges)
                            .id(CoachMarkTarget.gauges)
                        if let night = day.rawNight { RawNightCard(night: night, sourceName: day.rawNightSource) }
                        if let hint = day.watchHint { WatchSyncHintCard(hint: hint, showsAction: !model.showsRefreshIssue) }
                        if day.showsTiles {
                            tiles(day)
                                .coachMarkTarget(.physiology)
                                .id(CoachMarkTarget.physiology)
                        }
                        if model.showsRedesign, let night = model.lastNight {
                            Card { MiniHypnogram(sleep: night) { model.open(.sleep) } }
                        }
                        if model.showsHealthHint { HealthAccessHint() }
                        if model.showsPushPrompt {
                            PushPrePromptCard {
                                Task { await model.enablePush() }
                            } dismiss: {
                                withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick)) {
                                    model.dismissPushPrompt()
                                }
                            }
                            .transition(.opacity)
                        }
                        if screens.myDay.isEnabled { MyDayCard(model: screens.myDay) }
                        if screens.journal.isLive {
                            JournalCard(store: screens.journal) { showsJournal = true }
                        }
                        // From 17:00: when to be in bed tonight (Bedtime & wake).
                        if screens.bedtime.isEnabled, screens.bedtime.isEvening(), !day.hero.isImporting {
                            TonightCard(planner: screens.bedtime)
                        }
                        if model.showsTrain, !day.hero.isImporting { TrainTodayCard() }
                        if !day.hero.isImporting {
                            trends(day)
                                .coachMarkTarget(.trends)
                                .id(CoachMarkTarget.trends)
                        }
                        status
                    } else {
                        greeting(day)
                        SetupCard { model.open(.profile) }
                    }
                }
                .coachMarks(model.coachMarks, enabled: model.showsCoachMarks)
                .onAppear { LaunchSignpost.todayAppeared(cached: day.readiness != nil || model.lastUpdated != nil) }
                // Last night from Apple Health and the newest record per source, after each sync.
                .task(id: model.healthFactsKey) { await model.loadHealthFacts() }
                // One status read at the slow threshold when nothing else asks then (per start, cancelled with it).
                .task(id: model.slowScoringCheck) { await model.confirmSlowScoring() }
                // The night was pending and its score landed: one subtle change, one haptic.
                .onChange(of: day.hero.isPending) { was, now in
                    if was, !now { landed += 1 }
                }
                .sensoryFeedback(.success, trigger: landed)
                .sheet(isPresented: $showsJournal) {
                    JournalSheet(model: JournalSheetModel(store: screens.journal))
                }
                // The status line's tap: Sync details over Today, with its own stack.
                .sheet(isPresented: Binding(get: { model.showsSyncDetails }, set: { model.showsSyncDetails = $0 })) {
                    SyncDetailsSheet(model: screens.profile.syncDetails)
                }
                // The calibration note's link: the tracker's card, Check sync or Devices & sync, with Done.
                .sheet(item: $calibrationLink, onDismiss: { linkCheck = nil }) { link in
                    CalibrationLinkSheet(link: link, check: linkCheck)
                }
                // The journal: whether it's live (M5), and yesterday's answer for the card.
                .task(id: model.lastUpdated) {
                    await screens.journal.load()
                    await screens.journal.loadDay(screens.journal.yesterday)
                }
                // "Couldn't load today · Details": the card is last on Today; bring it into view.
                .onChange(of: model.scrollToIssue) {
                    withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.standard)) {
                        proxy.scrollTo(Self.issueCardID, anchor: .bottom)
                    }
                }
                // Each mark scrolls its target into view.
                .onChange(of: model.coachMarks.step) { _, step in
                    guard let step else { return }
                    withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.slow)) {
                        proxy.scrollTo(step, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: sections

    private func greeting(_ day: TodayContent) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 6) {
                Text(model.greeting)
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                Text(day.sentence)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            if model.hasDataSource {
                // While anything is being scored, the line is asked again every 15 s: "Taking longer than usual"
                // comes with time alone. One read of the line per tick.
                TimelineView(.periodic(from: .now, by: day.facts.scoringSince != nil ? 15 : 3_600)) { _ in
                    SyncStatusLineView(line: model.syncLine, action: { model.resolveLine() }, retry: { await model.refresh() })
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// The gauge, or what takes its place while data is on its way.
    @ViewBuilder
    private func hero(_ day: TodayContent) -> some View {
        Group {
            switch day.hero {
            case .importing(let progress):
                ImportCard(progress: progress, asksForPush: model.showsImportPushPrompt) {
                    Task { await model.enablePush() }
                } dismissPush: {
                    model.dismissPushPrompt()
                }
                .accessibilityIdentifier("today.importCard")
            case .pending:
                // While scoring, asked again every 15 s, like the line: slow scoring stops the breathing.
                let ticking = day.facts.scoringSince != nil
                TimelineView(.periodic(from: .now, by: ticking ? 15 : 3_600)) { _ in
                    pendingOrbit(ticking ? model.content : day)
                }
                .padding(.vertical, 4)
            case .calibrating:
                VStack(spacing: 8) {
                    // The outer orbit fills night by night. What it counts comes from the mapping (`OrbitGaugeMode
                    // +Today`): the heart-rate nights over a long history without HRV, the one signal that fills
                    // while the other is absent (F3), else any night.
                    OrbitGauge(mode: day.orbit, size: .large,
                               caption: OrbitGauge.Caption(title: String(localized: "Baselines")),
                               identifier: "today.baselineGauge", entrance: gaugeEntrance(day.orbit))
                        .modifier(GaugeEntranceConsumer(model: model, mode: day.orbit))
                    // Why the nights don't fill (row B over a long history without HRV), or why only one signal's
                    // count (F3); read on its own after the gauge.
                    if let note = day.gaugeNote { noteBlock(note, readWithGauge: false) }
                }
                .padding(.vertical, 4)
            case .score:
                VStack(spacing: 8) {
                    readinessRing(day)
                    // Rows D and B: in the band/delta line's place, read as part of the gauge.
                    if let note = day.gaugeNote { noteBlock(note, readWithGauge: day.gaugeSpokenNote != nil) }
                }
                .padding(.vertical, 4)
            }
        }
        .transition(.opacity)
        // One row to another: a 250 ms cross-fade (ui.md §1.3); an instant swap under Reduce Motion.
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: day.hero.kind)
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: day.gaugeNote)
    }

    /// A gauge with something to show assembles until one has been seen in this process (`TodayGaugeEntrance`).
    /// A gauge latches this when it is built, so a later change (another hero row, a refresh) builds a plain one.
    private func gaugeEntrance(_ mode: OrbitGaugeMode) -> OrbitGauge.Entrance {
        TodayGaugeEntrance.entrance(flag: model.assemblesGauge, mode: mode)
    }

    /// The orbit: readiness in the centre, Recovery and Sleep on the inner orbit, Strain on the outer; under it the
    /// caption, the band word and the change against the days before (from the 7-day trend, row A only).
    private func readinessRing(_ day: TodayContent) -> some View {
        OrbitGauge(mode: day.orbit, size: .large,
                   caption: OrbitGauge.Caption(title: String(localized: "Overall readiness"), delta: day.readinessDelta,
                                               showsBand: day.showsReadinessBand),
                   accessibilityNote: day.gaugeSpokenNote, identifier: "today.readinessGauge",
                   entrance: gaugeEntrance(day.orbit))
            .modifier(GaugeEntranceConsumer(model: model, mode: day.orbit))
    }

    /// A night not scored yet: the latest scored day's orbit, dimmed, breathing until scoring takes longer
    /// than usual; the day it's from, then "Scoring your night…" and when to expect it. VoiceOver hears the title
    /// and the day in the gauge's value; the line under them is read on its own.
    private func pendingOrbit(_ day: TodayContent) -> some View {
        VStack(spacing: 8) {
            OrbitGauge(mode: day.orbit, size: .large, accessibilityNote: day.pendingSpokenNote,
                       identifier: "today.pendingGauge", breathes: !day.pendingIsStatic,
                       entrance: gaugeEntrance(day.orbit))
                .modifier(GaugeEntranceConsumer(model: model, mode: day.orbit))
            if let scored = day.pendingScoredDay {
                Text(scored)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 2) {
                Text(day.pendingTitle)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityHidden(true)
                // None while a card under the gauge says it (the night hint).
                if !day.pendingDetail.isEmpty {
                    Text(day.pendingDetail)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The note under the gauge and, under it, its link when there is one (a blocked baseline with
    /// `devices.setup` on). `readWithGauge`: VoiceOver hears the note in the gauge's value, so the line itself is
    /// hidden; the link stays its own button either way.
    private func noteBlock(_ note: TodayPresentation.Note, readWithGauge: Bool) -> some View {
        VStack(spacing: 0) {
            gaugeNote(note)
                .accessibilityHidden(readWithGauge)
            if let link = note.link {
                GaugeNoteLink(title: link.title) { open(link) }
                    .transition(.opacity)
                    .accessibilityIdentifier("today.gaugeNote.link")
            }
        }
    }

    private func gaugeNote(_ note: TodayPresentation.Note) -> some View {
        GaugeNote(text: note.text, systemImage: note.systemImage)
            .transition(.opacity)
            .accessibilityIdentifier("today.gaugeNote")
    }

    /// The note's link: Check sync's model is made here, on the tap, for the sheet to keep.
    private func open(_ link: CalibrationLink) {
        linkCheck = link == .checkSync ? .make(env: env, trackers: screens.devices.trackers) : nil
        calibrationLink = link
    }

    /// One day for all three (ui.md §1): today's, or the latest scored day dimmed with its date.
    private func tiles(_ day: TodayContent) -> some View {
        // Three columns truncate at accessibility sizes; stack the tiles there.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            MetricTile(title: "Sleep", value: day.sleepText, systemImage: "moon.fill",
                       tint: Theme.metricSleep, caption: day.tileCaption, isDimmed: day.tilesDimmed,
                       accessibilityHint: "Opens Sleep") {
                model.open(.sleep)
            }
            MetricTile(title: "Recovery", value: day.recoveryText, systemImage: "heart",
                       tint: Theme.band(forScore: day.recovery),
                       caption: day.recoveryCaption, isDimmed: day.tilesDimmed, accessibilityHint: "Opens Insights") {
                model.open(.insights)
            }
            MetricTile(title: "Strain", value: day.strainText, systemImage: "bolt.fill",
                       tint: Theme.metricStrain, caption: day.tileCaption, isDimmed: day.tilesDimmed,
                       accessibilityHint: "Opens Strain") {
                model.open(.strain)
            }
        }
        .fixedSize(horizontal: false, vertical: !typeSize.isAccessibilitySize)
    }

    private func trends(_ day: TodayContent) -> some View {
        Button {
            model.open(.insights)
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Trends", showsChevron: true)
                    TrendChart(points: day.readinessWeek, spec: .readiness, window: .week,
                               interactive: false, height: 110)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(Text("Opens Insights"))
    }

    /// What needs explaining beyond the status line (a gate is the line's to show).
    @ViewBuilder
    private var status: some View {
        switch model.status {
        case .actionNeeded(let step, let message, let action):
            InlineMessage(message: message, systemImage: "hand.raised", retryTitle: LocalizedStringKey(action),
                          retry: { model.resolve(step) })
        case .retrying(let notice):
            InlineMessage(message: notice, systemImage: "clock.arrow.circlepath")
        case .refreshIssue(let issue):
            RefreshIssueCard(issue: issue, retry: { await model.refresh() }, signIn: { await model.signIn() })
                .id(Self.issueCardID)
        case .syncPaused(let message, let details):
            InlineMessage(message: message, systemImage: "heart.text.square", details: details,
                          retry: { await model.refresh() })
        case nil:
            EmptyView()
        }
    }
}

extension TodayHero {
    var isImporting: Bool { if case .importing = self { return true } else { return false } }
    var isPending: Bool { if case .pending = self { return true } else { return false } }

    /// Which view, for the cross-fade between them (not their values).
    var kind: Int {
        switch self {
        case .importing: return 0
        case .pending: return 1
        case .calibrating: return 2
        case .score: return 3
        }
    }
}

/// The decisions behind Today's once-per-process gauge entrance (architecture.md §4), pure so every row is tested
/// (`TodayGaugeEntranceTests`).
///
/// - The entrance plays on the first gauge with something to show (`hasSomethingToShow`). A first launch or demo mode
///   can draw Today before its data is there; that empty gauge never assembles and never counts. When the data
///   arrives the gauge is a new instance (its identity includes `hasSomethingToShow`), which latches `.assemble`.
/// - Consumed on that gauge's first appearance while the scene is active, or when the scene becomes active with the
///   gauge already there (a cold launch draws its first frames while still inactive; the entrance plays from those).
///   Not at init: a process launched in the background (HealthKit delivery, `BGAppRefreshTask`) and opened later
///   still plays it once.
/// - A gauge that played where nobody could see it (drawn in the background, or the scene went to the background
///   before it was ever active) is built again once when it is next seen.
/// - The import card shows no gauge and consumes nothing.
enum TodayGaugeEntrance {
    enum Event: Equatable {
        /// The gauge appeared (built for the first time, or built again), in the scene phase passed with it.
        case appeared
        /// The scene changed to the phase passed with it while the gauge was there.
        case phaseChanged
    }

    struct Outcome: Equatable {
        /// Call `TodayViewModel.gaugeDidAssemble()`.
        var consume = false
        /// Build the gauge again: the new instance latches `.assemble` (the flag still holds) and plays it.
        var rebuild = false
        /// This instance has played (or is playing) its entrance unseen; the next time it is seen it is built again.
        var playedUnseen = false
    }

    /// Something worth assembling: a day with at least one score, the baselines filling, or a pending night over a
    /// previous day with a score. Not the empty orbit (no data yet, the first import, a day with nothing scored, a
    /// pending night without a previous day): tracks alone would assemble with no dots and then just fade in the arcs.
    static func hasSomethingToShow(_ mode: OrbitGaugeMode) -> Bool {
        switch mode {
        case .scored(let values, _): return !values.isEmpty
        case .calibrating: return true
        case .pending(let previous): return previous.map { !$0.isEmpty } ?? false
        }
    }

    /// The gauge's entrance parameter: `.assemble` while the flag holds and the gauge has something to show.
    static func entrance(flag: Bool, mode: OrbitGaugeMode) -> OrbitGauge.Entrance {
        flag && hasSomethingToShow(mode) ? .assemble : .none
    }

    /// `flag`: `TodayViewModel.assemblesGauge`. `showable`: `hasSomethingToShow` of the gauge's mode. `phase`: the
    /// scene phase now (after the change, for `.phaseChanged`).
    static func decide(flag: Bool, showable: Bool, phase: ScenePhase, event: Event, playedUnseen: Bool) -> Outcome {
        // Consumed: nothing plays again in this process, and nothing is remembered. Nothing to show: this gauge
        // doesn't assemble and doesn't count; the one with data is a new instance and starts afresh.
        guard flag, showable else { return Outcome() }
        switch (event, phase) {
        case (_, .background):
            // Whatever this instance plays now, or has played while inactive, nobody sees.
            return Outcome(playedUnseen: true)
        case (.appeared, .active):
            // Played unseen: build it again first (an appearance can come before the phase change); the new
            // instance consumes on its own appearance.
            return playedUnseen ? Outcome(rebuild: true) : Outcome(consume: true)
        case (.appeared, _):
            // Inactive: on screen (a cold launch's first frames); consumed when the scene becomes active. Whatever
            // was played unseen stays so until the rebuild.
            return Outcome(playedUnseen: playedUnseen)
        case (.phaseChanged, _) where playedUnseen:
            // Once: the rebuilt instance consumes on its own appearance (active) or at the next `.active`.
            return Outcome(rebuild: true)
        case (.phaseChanged, .active):
            return Outcome(consume: true)
        case (.phaseChanged, _):
            return Outcome()
        }
    }
}

/// Applies `TodayGaugeEntrance.decide` where a gauge is shown; it decides nothing itself.
private struct GaugeEntranceConsumer: ViewModifier {
    let model: TodayViewModel
    /// The gauge's mode: whether it has something to show is part of its identity.
    let mode: OrbitGaugeMode
    @Environment(\.scenePhase) private var scenePhase
    /// Bumped only to build again a gauge that played unseen.
    @State private var run = 0
    @State private var playedUnseen = false

    /// The gauge's identity: a new instance when its data first becomes showable (it latches `.assemble` then, while
    /// the flag holds), and when one that played unseen is built again.
    private struct Identity: Hashable {
        var run: Int
        var showable: Bool
    }

    private var showable: Bool { TodayGaugeEntrance.hasSomethingToShow(mode) }

    func body(content: Content) -> some View {
        content
            // Inside the identity: a gauge built again appears again.
            .onAppear { apply(.appeared, phase: scenePhase) }
            .id(Identity(run: run, showable: showable))
            .onChange(of: scenePhase) { _, phase in apply(.phaseChanged, phase: phase) }
    }

    private func apply(_ event: TodayGaugeEntrance.Event, phase: ScenePhase) {
        let flag = model.assemblesGauge
        let outcome = TodayGaugeEntrance.decide(flag: flag, showable: showable, phase: phase, event: event,
                                                playedUnseen: playedUnseen)
        if outcome.playedUnseen != playedUnseen { playedUnseen = outcome.playedUnseen }
        if outcome.rebuild { run += 1 }
        if outcome.consume { model.gaugeDidAssemble() }
        if flag {
            let what = "\(event) in \(phase), showable \(showable)"
            Self.log.debug("gauge entrance: \(what, privacy: .public)")
        }
    }

    private static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "today")
}

/// Where the calibration note's link goes (design.md §7 rev. 2 §2): the tracker's card, Check sync or Devices &
/// sync, each with its own stack and "Done", like Sync details from the status line.
private struct CalibrationLinkSheet: View {
    let link: CalibrationLink
    /// Check sync's model, made on the tap (`TodayView.open`).
    let check: TrackerCheckModel?

    @Environment(ScreenModels.self) private var screens
    @Environment(\.appEnvironment) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            destination
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("today.calibrationSheet.done")
                    }
                }
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch link {
        case .setup(let id, _):
            // A newer catalog may have dropped the tracker: Devices & sync then.
            if let tracker = env.trackerCatalog.tracker(id) {
                TrackerDetailView(tracker: tracker, model: screens.profile.devices) {}
            } else {
                DevicesAndSyncView(model: screens.profile.devices)
            }
        case .checkSync:
            if let check { TrackerCheckView(model: check) } else { DevicesAndSyncView(model: screens.profile.devices) }
        case .devices:
            DevicesAndSyncView(model: screens.profile.devices)
        }
    }
}

/// "Setting up RYFT": the first import, from Health access until the first scored day, in
/// real counts and days of the window (no percent it can't back).
struct ImportCard: View {
    let progress: ImportProgress
    var asksForPush = false
    var enablePush: () -> Void = {}
    var dismissPush: () -> Void = {}

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    RyftMark()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Theme.accent)
                    Text("Setting up RYFT")
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                steps
                VStack(spacing: 8) {
                    row("Sleep", value: String(localized: "\(progress.nights) nights"))
                    row("Heart rate", value: String(localized: "\(progress.heartRateReadings.formatted()) readings"))
                    row("Workouts", value: progress.workouts.formatted())
                }
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress.fraction)
                        .tint(Theme.accent)
                        .accessibilityHidden(true)
                    Text(progress.coverageText)
                        .font(.ryft(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("You can leave the app — RYFT keeps going in the background.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if asksForPush {
                    Divider().overlay(Theme.separator)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Tell me when my first scores are ready", systemImage: "bell.badge")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            Button(action: enablePush) { Text("Allow") }
                                .buttonStyle(TealButtonStyle(prominent: true))
                            Button(action: dismissPush) { Text("Not now") }
                                .buttonStyle(TealButtonStyle(prominent: false))
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    /// Reading Apple Health → Uploading → Scoring, the current one lit.
    private var steps: some View {
        HStack(spacing: 6) {
            ForEach(ImportProgress.Step.allCases, id: \.self) { step in
                if step != .reading {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(step.title)
                    .font(.ryft(.caption))
                    .foregroundStyle(step == progress.step ? Theme.onAccent
                                     : step < progress.step ? Theme.textSecondary : Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(step == progress.step ? Theme.accent : .clear, in: Capsule())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(progress.step.rawValue + 1) of 3: \(progress.step.title)"))
    }

    private func row(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .font(.ryft(.callout))
        .accessibilityElement(children: .combine)
    }
}

/// The import going on after the first score: one slim row under the header.
struct ImportRow: View {
    let progress: ImportProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Importing your history")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(progress.coveredDays) of \(ImportProgress.windowDays) days")
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            .font(.ryft(.caption))
            ProgressView(value: progress.fraction)
                .tint(Theme.accent)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Importing your history"))
        .accessibilityValue(Text(progress.coverageText))
        .accessibilityIdentifier("today.importRow")
    }
}

/// Last night as Apple Health has it, beside the pending gauge: raw totals, labelled as
/// not scored (the phone computes no scores).
struct RawNightCard: View {
    let night: RawNight
    /// The source's display name ("Garmin Connect"); HealthKit's without one.
    var sourceName: String?
    /// The times in the screen's locale: "23:17" in German, the user's 12/24-hour setting in the app.
    @Environment(\.locale) private var locale
    private var bedtime: String { Fmt.time(night.bedtime, locale: locale) }
    private var wake: String { Fmt.time(night.wake, locale: locale) }
    private var source: String { sourceName ?? night.source }
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                // Side by side; stacked at accessibility sizes, where the two squeeze each other.
                let header = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                header {
                    Text("Last night")
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                    if !typeSize.isAccessibilitySize { Spacer() }
                    Text("From Apple Health · not scored yet")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.duration(minutes: night.asleepMin))
                        .font(.ryftNumber(size: 28))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("asleep")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(verbatim: "\(bedtime) – \(wake) · \(source)")
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last night, from Apple Health, not scored yet"))
        .accessibilityValue(Text("\(Fmt.duration(minutes: night.asleepMin)) asleep, \(bedtime) to \(wake), \(source)"))
        .accessibilityIdentifier("today.rawNight")
    }
}

/// "Nothing new from Garmin Connect since 23:40", or in the morning "Your night hasn't reached Apple Health
/// yet. Open Garmin Connect to sync it." with the data's age and "Garmin Connect in the App Store" (ui.md §6.2,
/// errata 2). A quiet hint: no dismissal; it goes when the night arrives. Times in the screen's locale.
struct WatchSyncHintCard: View {
    let hint: WatchSyncHint
    /// The App Store button; dropped while the error card offers its own action (one action on screen).
    var showsAction = true

    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            InlineMessage(message: hint.text(now: context.date, locale: locale), systemImage: hint.systemImage,
                          caption: hint.caption(locale: locale), identifier: hint.isNight ? "today.nightHint" : "today.watchHint",
                          action: action)
        }
        // A container: VoiceOver (and UI tests) reach the sentence, its age and "Open …" one by one.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(hint.isNight ? "today.nightHint" : "today.watchHint")
    }

    private var action: (title: String, perform: () -> Void)? {
        guard showsAction, hint.opensApp, let url = hint.storeURL else { return nil }
        return (hint.storeTitle, { openURL(url) })
    }
}

extension SyncLine {
    /// Scoring, slow or not: the line can change with time alone.
    var isScoring: Bool {
        switch self {
        case .scoring, .scoringSlow: return true
        default: return false
        }
    }
}

/// "Offline": the numbers are the last loaded ones; sync resumes on reconnect.
struct OfflinePill: View {
    var body: some View {
        Label("Offline", systemImage: "wifi.slash")
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
            .accessibilityLabel(Text("Offline. Showing your last loaded data."))
    }
}

#Preview("Today · offline") {
    TodayView().previewEnvironment(.preview(online: false), online: false)
}

#Preview("Today · dark") {
    TodayView().previewEnvironment()
}

#Preview("Today · light") {
    TodayView().previewEnvironment(scheme: .light)
}

#Preview("Today · calibrating") {
    TodayView().previewEnvironment(.preview(calibrating: true))
}

#Preview("Today · coach marks") {
    TodayView().previewEnvironment(.preview(coachMarks: true))
}

#Preview("Today · redesign (flags on)") {
    TodayView().previewEnvironment(.preview(flags: [.todayRedesign: true]))
}

#Preview("Today · redesign · light") {
    TodayView().previewEnvironment(.preview(flags: [.todayRedesign: true]), scheme: .light)
}

#Preview("Today · not set up") {
    TodayView().previewEnvironment(.preview(empty: true))
}

#Preview("Today · first import") {
    TodayView().previewEnvironment(.preview(scenario: .importing))
}

#Preview("Today · first import · light · de") {
    TodayView().previewEnvironment(.preview(scenario: .importing), scheme: .light)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Today · night pending") {
    TodayView().previewEnvironment(.preview(scenario: .pending))
}

#Preview("Today · night pending · light · de") {
    TodayView().previewEnvironment(.preview(scenario: .pending), scheme: .light)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Today · calibrating · light") {
    TodayView().previewEnvironment(.preview(scenario: .calibrating), scheme: .light)
}

#Preview("Today · watch hasn't synced") {
    TodayView().previewEnvironment(.preview(scenario: .watch))
}

#Preview("Today · watch hasn't synced · light") {
    TodayView().previewEnvironment(.preview(scenario: .watch), scheme: .light)
}

// MARK: one preview per Today row (ui.md §1.6): A scored, B calibrating, C pending, D recalculating, E first import

#Preview("Today · A scored") {
    TodayView().previewEnvironment()
}

#Preview("Today · A scored · light") {
    TodayView().previewEnvironment(scheme: .light)
}

#Preview("Today · B calibrating") {
    TodayView().previewEnvironment(.preview(scenario: .calibrating))
}

#Preview("Today · B needs HRV (note)") {
    TodayView().previewEnvironment(.preview(scenario: .needsVitals))
}

#Preview("Today · B needs HRV (note) · light · de") {
    TodayView().previewEnvironment(.preview(scenario: .needsVitals), scheme: .light)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Today · B needs HRV, no readiness") {
    TodayView().previewEnvironment(.preview(scenario: .needsVitalsBaselines))
}

#Preview("Today · B needs HRV, no readiness · light · de") {
    TodayView().previewEnvironment(.preview(scenario: .needsVitalsBaselines), scheme: .light)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Today · B needs HRV, no readiness · AX3") {
    TodayView().previewEnvironment(.preview(scenario: .needsVitalsBaselines))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Today · C pending") {
    TodayView().previewEnvironment(.preview(scenario: .pending))
}

#Preview("Today · C pending · light") {
    TodayView().previewEnvironment(.preview(scenario: .pending), scheme: .light)
}

#Preview("Today · C waiting for sleep") {
    TodayView().previewEnvironment(.preview(scenario: .waitingForSleep))
}

#Preview("Today · C waiting for sleep · light") {
    TodayView().previewEnvironment(.preview(scenario: .waitingForSleep), scheme: .light)
}

#Preview("Today · C pending, no previous") {
    TodayView().previewEnvironment(.preview(scenario: .pendingNoPrevious))
}

#Preview("Today · C pending, no previous · light") {
    TodayView().previewEnvironment(.preview(scenario: .pendingNoPrevious), scheme: .light)
}

#Preview("Today · D recalculating (note)") {
    TodayView().previewEnvironment(.preview(scenario: .recalculating))
}

#Preview("Today · D recalculating (note) · light") {
    TodayView().previewEnvironment(.preview(scenario: .recalculating), scheme: .light)
}

#Preview("Today · D recalculating · de") {
    TodayView().previewEnvironment(.preview(scenario: .recalculating))
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Today · D recalculating, yesterday") {
    TodayView().previewEnvironment(.preview(scenario: .recalculatingYesterday))
}

#Preview("Today · D recalculating, yesterday · light · de") {
    TodayView().previewEnvironment(.preview(scenario: .recalculatingYesterday), scheme: .light)
        .environment(\.locale, Locale(identifier: "de"))
}

// MARK: honest calibration (design.md §7 rev. 2): S2 learning, N1 blocked with a readiness, N2 without one

#Preview("Today · N1 blocked HRV (Garmin)") {
    TodayView().previewEnvironment(.preview(scenario: .blockedHRV))
}

#Preview("Today · N1 blocked HRV (Garmin) · light") {
    TodayView().previewEnvironment(.preview(scenario: .blockedHRV), scheme: .light)
}

#Preview("Today · N1 blocked HRV (Garmin) · de") {
    TodayView().previewEnvironment(.preview(scenario: .blockedHRV))
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Today · N1 blocked HRV (Garmin) · light · de") {
    TodayView().previewEnvironment(.preview(scenario: .blockedHRV), scheme: .light)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Today · N1 blocked HRV (Garmin) · AX3") {
    TodayView().previewEnvironment(.preview(scenario: .blockedHRV))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Today · N1 blocked both (Oura)") {
    TodayView().previewEnvironment(.preview(scenario: .blockedOura))
}

#Preview("Today · N1 blocked both (Oura) · light · de") {
    TodayView().previewEnvironment(.preview(scenario: .blockedOura), scheme: .light)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Today · N2 blocked, no night") {
    TodayView().previewEnvironment(.preview(scenario: .blockedNoNight))
}

#Preview("Today · N2 blocked, no night · light") {
    TodayView().previewEnvironment(.preview(scenario: .blockedNoNight), scheme: .light)
}

#Preview("Today · S2 learning HRV") {
    TodayView().previewEnvironment(.preview(scenario: .learningHRV))
}

#Preview("Today · S2 learning HRV · light") {
    TodayView().previewEnvironment(.preview(scenario: .learningHRV), scheme: .light)
}

// MARK: F3: the counter counts what is filling, one story between gauge and tiles, N1 as soon as the setup knows

#Preview("Today · S1 counting resting HR") {
    TodayView().previewEnvironment(.preview(scenario: .learningRestingHR))
}

#Preview("Today · S1 counting resting HR · light") {
    TodayView().previewEnvironment(.preview(scenario: .learningRestingHR), scheme: .light)
}

#Preview("Today · S1 counting resting HR · AX3") {
    TodayView().previewEnvironment(.preview(scenario: .learningRestingHR))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Today · S2 resting HR, readiness") {
    TodayView().previewEnvironment(.preview(scenario: .learningRestingHRScored))
}

#Preview("Today · S2 resting HR, readiness · light") {
    TodayView().previewEnvironment(.preview(scenario: .learningRestingHRScored), scheme: .light)
}

#Preview("Today · N1 early (Garmin, first week)") {
    TodayView().previewEnvironment(.preview(scenario: .blockedEarly))
}

#Preview("Today · N1 early (Garmin, first week) · light") {
    TodayView().previewEnvironment(.preview(scenario: .blockedEarly), scheme: .light)
}

#Preview("Today · E first import · light") {
    TodayView().previewEnvironment(.preview(scenario: .importing), scheme: .light)
}

#Preview("Today · B · AX3") {
    TodayView().previewEnvironment(.preview(scenario: .calibrating))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Today · C · AX3") {
    TodayView().previewEnvironment(.preview(scenario: .pending))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Today · D yesterday · AX3") {
    TodayView().previewEnvironment(.preview(scenario: .recalculatingYesterday))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Import, raw night, hint", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 16) {
            ImportCard(progress: TodayStates.progress(TodayScenario.importing.apply(to: TodaySyncFacts(now: .now))),
                       asksForPush: true)
            ImportRow(progress: TodayStates.progress(TodayScenario.importing.apply(to: TodaySyncFacts(now: .now))))
            RawNightCard(night: RawNight(asleepMin: 437, bedtime: .now.addingTimeInterval(-8 * 3_600),
                                         wake: .now.addingTimeInterval(-40 * 60), source: "Garmin Connect"))
            WatchSyncHintCard(hint: WatchSyncHint(source: "Garmin Connect", since: .now.addingTimeInterval(-14 * 3_600),
                                                  isApp: true))
        }
    }
}

// MARK: the night that hasn't reached Apple Health, and slow scoring (ui.md §6, previews 12–14)

/// Mock hints: Garmin Connect quiet since last night 23:24, the Apple Watch, an unknown source.
private enum PreviewHint {
    static let lastNight = Calendar.current.date(bySettingHour: 23, minute: 24, second: 0,
                                                 of: .now.addingTimeInterval(-86_400)) ?? .now
    static func night(_ kind: SourceApp.Kind, name: String) -> WatchSyncHint {
        WatchSyncHint(night: NightGap(name: name, kind: kind,
                                      storeURL: kind == .app ? URL(string: "https://apps.apple.com/app/id583446403") : nil,
                                      newest: lastNight))
    }
    static let quiet = WatchSyncHint(source: "Garmin Connect", since: lastNight, isApp: true,
                                     storeURL: URL(string: "https://apps.apple.com/app/id583446403"))
}

#Preview("Night hint · app, watch, unknown, quiet", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 16) {
            WatchSyncHintCard(hint: PreviewHint.night(.app, name: "Garmin Connect"))
            WatchSyncHintCard(hint: PreviewHint.night(.appleDevice, name: "Tim's Apple Watch"))
            WatchSyncHintCard(hint: PreviewHint.night(.unknown, name: "Sleep Diary"))
            WatchSyncHintCard(hint: PreviewHint.quiet)
            // The error card shows: one action on screen, so no "Open".
            WatchSyncHintCard(hint: PreviewHint.night(.app, name: "Garmin Connect"), showsAction: false)
        }
    }
}

#Preview("Night hint · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        WatchSyncHintCard(hint: PreviewHint.night(.app, name: "Garmin Connect"))
    }
    .environment(\.locale, Locale(identifier: "de"))
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Today · night hasn't arrived") {
    TodayView().previewEnvironment(.preview(scenario: .nightGap))
}

#Preview("Today · night hasn't arrived · light") {
    TodayView().previewEnvironment(.preview(scenario: .nightGap), scheme: .light)
}

#Preview("Today · night hasn't arrived · light · de") {
    TodayView().previewEnvironment(.preview(scenario: .nightGap), scheme: .light)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Today · night hasn't arrived · AX3") {
    TodayView().previewEnvironment(.preview(scenario: .nightGap))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Today · taking longer") {
    TodayView().previewEnvironment(.preview(scenario: .scoringSlow))
}

#Preview("Today · taking longer · light") {
    TodayView().previewEnvironment(.preview(scenario: .scoringSlow), scheme: .light)
}

#Preview("Today · taking longer · de") {
    TodayView().previewEnvironment(.preview(scenario: .scoringSlow))
        .environment(\.locale, Locale(identifier: "de"))
}

// MARK: My Day (today.my_day): between the scores and Journal, Train and Trends (ui.md §14.4)

#Preview("Today · My Day") {
    TodayView().previewEnvironment(.preview(flags: [.todayMyDay: true]))
}

#Preview("Today · My Day · light") {
    TodayView().previewEnvironment(.preview(flags: [.todayMyDay: true]), scheme: .light)
}

#Preview("Today · My Day · watch hasn't synced") {
    TodayView().previewEnvironment(.preview(flags: [.todayMyDay: true], scenario: .watch))
}

#Preview("Today · My Day · watch hasn't synced · light") {
    TodayView().previewEnvironment(.preview(flags: [.todayMyDay: true], scenario: .watch), scheme: .light)
}
