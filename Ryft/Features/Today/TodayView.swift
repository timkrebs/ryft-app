import OSLog
import SwiftUI

/// Today in Nocturne (docs/work/2026-11-16-nocturne/design.md §P4-1): the header lock-up and the calendar, the greeting
/// and the sub-line, the sync's status row, the hero gauge with its label row and ruler (or what's true while data is on
/// its way: the first import, a night being scored, the baselines being learned), the attention cards, the glow tiles
/// (Recovery and Sleep, then Strain), and the cards below. Layout only: everything shown comes from `TodayViewModel`.
struct TodayView: View {
    /// Previews and tests: the hero numerals and Reduce Transparency; `nil` follows the setting and the system.
    var heroNumerals: HeroNumerals?
    var reduceTransparency: Bool?

    @Environment(ScreenModels.self) private var screens
    @Environment(Settings.self) private var settings
    @Environment(\.appEnvironment) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    /// The launch sequence covers Today (taps, VoiceOver): its gauge is built without the entrance.
    @Environment(\.launchCoversRoot) private var launchCovers
    /// The launch still reveals Today: covered, or its mark still flying into the header (design.md §P4-7). The gauge's
    /// entrance waits for it; during the move the gauge's slot is empty.
    @Environment(\.launchRevealsRoot) private var launchReveals

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
    /// The empty orbit (data on its way) has been on screen while the gauge still assembles: the gauge with data then
    /// assembles over its tracks (`TodayGaugeEntrance`).
    @State private var gaugePlaceholderSeen = false

    private var numeral: DotNumeral.Style { (heroNumerals ?? settings.heroNumerals).style }

    var body: some View {
        // The day's facts and decision, read once for the whole body.
        let day = model.content
        NavigationStack {
            ScrollViewReader { proxy in
                ScreenScaffold(showsHeader: false) {
                    VStack(spacing: 0) {
                        TodayHeader()
                        intro(day)
                            .padding(.top, TodayLayout.headerToGreeting)
                        if model.hasDataSource {
                            if let row = day.importRow {
                                ImportRow(progress: row)
                                    .padding(.top, TodayLayout.statusToImportRow)
                            }
                            hero(day)
                                .padding(.top, TodayLayout.statusToGauge)
                                .coachMarkTarget(.gauges)
                                .id(CoachMarkTarget.gauges)
                            attentionCards(day)
                            if day.showsTiles {
                                TodayTiles(content: TodayTilesContent(day), reduceTransparency: reduceTransparency) {
                                    model.open($0)
                                }
                                .padding(.top, hasAttentionCard(day) ? TodayLayout.cardGap : TodayLayout.rulerToTiles)
                                .coachMarkTarget(.physiology)
                                .id(CoachMarkTarget.physiology)
                            }
                            cardsBelow(day)
                                .padding(.top, TodayLayout.glowToCards)
                        } else {
                            SetupCard { model.open(.profile) }
                                .padding(.top, TodayLayout.statusToGauge)
                        }
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
                // The status line's tap: Sync details over Today, a sheet's page with Close.
                .sheet(isPresented: Binding(get: { model.showsSyncDetails }, set: { model.showsSyncDetails = $0 })) {
                    SyncDetailsSheet(model: screens.profile.syncDetails)
                }
                // The calibration note's link: the tracker's card, Check sync or Devices & sync, each with Close.
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

    // MARK: rows 2–4: greeting, sub-line, status

    /// "Good evening, Alex", then "Sunday, Nov 15 · Your health is in balance." (one VoiceOver element, a header), then
    /// the sync's status row, all leading.
    private func intro(_ day: TodayContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: TodayLayout.greetingToSubLine) {
                Text(verbatim: model.greeting)
                    .font(.ryft(.title))
                    .tracking(TodayLayout.greetingTracking)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(verbatim: day.subLine(locale: locale))
                    .font(.ryft(.label))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Self.spokenIntro(greeting: model.greeting, day: day, locale: locale)))
            .accessibilityAddTraits(.isHeader)
            if model.hasDataSource {
                // While anything is being scored, the line is asked again every 15 s: "Taking longer than usual"
                // comes with time alone. One read of the line per tick.
                TimelineView(.periodic(from: .now, by: day.facts.scoringSince != nil ? 15 : 3_600)) { _ in
                    SyncStatusLineView(line: model.syncLine, action: { model.resolveLine() },
                                       retry: { await model.refresh() }, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, TodayLayout.subLineToStatus)
            }
        }
    }

    /// "Good evening, Alex. Sunday, November 15. Your health is in balance." (§P4-8 row 3).
    static func spokenIntro(greeting: String, day: TodayContent, locale: Locale) -> String {
        let intro = "\(greeting). \(TodayContent.spokenDate(day.facts.now, locale: locale))."
        let sentence = day.sentence
        return sentence.isEmpty ? intro : "\(intro) \(sentence)"
    }

    // MARK: rows 6–9: the hero

    /// The gauge with its label row, note and ruler, or what takes their place while data is on its way.
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
                    pendingHero(ticking ? model.content : day)
                }
            case .calibrating:
                VStack(spacing: 0) {
                    // The outer orbit fills night by night. What it counts comes from the mapping (`OrbitGaugeMode
                    // +Today`): the heart-rate nights over a long history without HRV, the one signal that fills
                    // while the other is absent (F3), else any night.
                    gaugeSlot {
                        OrbitGauge(mode: day.orbit, size: .hero,
                                   caption: OrbitGauge.Caption(title: String(localized: "Baselines")), showsCaption: false,
                                   identifier: "today.baselineGauge", numeral: numeral, entrance: gaugeEntrance(day.orbit))
                            .modifier(gaugeEntranceConsumer(day.orbit))
                    }
                    labelRow(day)
                    // Why the nights don't fill (row B over a long history without HRV), or why only one signal's
                    // count (F3); read on its own after the gauge.
                    if let note = day.gaugeNote {
                        noteBlock(note, readWithGauge: false)
                            .padding(.top, TodayLayout.labelToNote)
                    }
                    ruler(day)
                }
            case .score:
                VStack(spacing: 0) {
                    gaugeSlot { readinessGauge(day) }
                    labelRow(day)
                    // Rows D and B: under the label row, read as part of the gauge.
                    if let note = day.gaugeNote {
                        noteBlock(note, readWithGauge: day.gaugeSpokenNote != nil)
                            .padding(.top, TodayLayout.labelToNote)
                    }
                    ruler(day)
                }
            }
        }
        .transition(.opacity)
        // One row to another: a 250 ms cross-fade (ui.md §1.3); an instant swap under Reduce Motion.
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: day.hero.kind)
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: day.gaugeNote)
    }

    /// The gauge's 260 × 260 place. While the launch's mark flies into the header (handing off, the root uncovered but
    /// not yet revealed) it stays empty; at the landing the gauge is built and its entrance plays (design.md §P4-7).
    @ViewBuilder
    private func gaugeSlot(@ViewBuilder _ gauge: () -> some View) -> some View {
        if Self.gaugeSlotIsEmpty(covers: launchCovers, reveals: launchReveals) {
            Color.clear
                .frame(width: TodayLayout.heroFrame, height: TodayLayout.heroFrame)
                .accessibilityHidden(true)
        } else {
            gauge()
        }
    }

    /// The slot is empty only between the hand-off's start and the landing of a matched move: uncovered, not revealed.
    nonisolated static func gaugeSlotIsEmpty(covers: Bool, reveals: Bool) -> Bool {
        reveals && !covers
    }

    /// A gauge with something to show assembles until one has been seen in this process (`TodayGaugeEntrance`).
    /// A gauge latches this when it is built, so a later change (another hero row, a refresh) builds a plain one.
    /// Until the launch has revealed Today it is built static: the entrance plays at the landing.
    private func gaugeEntrance(_ mode: OrbitGaugeMode) -> OrbitGauge.Entrance {
        TodayGaugeEntrance.entrance(flag: model.assemblesGauge && !launchReveals, mode: mode,
                                    placeholderSeen: gaugePlaceholderSeen)
    }

    private func gaugeEntranceConsumer(_ mode: OrbitGaugeMode) -> GaugeEntranceConsumer {
        GaugeEntranceConsumer(model: model, mode: mode) {
            if !gaugePlaceholderSeen { gaugePlaceholderSeen = true }
        }
    }

    /// The orbit at the hero size: readiness in the centre, Recovery and Sleep on the inner orbit, Strain on the outer.
    /// Its caption (the band and the change) is drawn by the label row; the gauge keeps it for its spoken sentence.
    private func readinessGauge(_ day: TodayContent) -> some View {
        OrbitGauge(mode: day.orbit, size: .hero,
                   caption: OrbitGauge.Caption(title: String(localized: "Overall readiness"), delta: day.readinessDelta,
                                               showsBand: day.showsReadinessBand),
                   showsCaption: false, accessibilityNote: day.gaugeSpokenNote, identifier: "today.readinessGauge",
                   numeral: numeral, entrance: gaugeEntrance(day.orbit))
            .modifier(gaugeEntranceConsumer(day.orbit))
    }

    /// Row 7: "Readiness · High" and "▲ +11 vs 7 d", 10 apart, centred; stacked at accessibility sizes. Hidden from
    /// VoiceOver: the gauge says both.
    private func labelRow(_ day: TodayContent) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .center, spacing: TodayLayout.pendingLineGap))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: TodayLayout.labelGap))
        return layout {
            Text(verbatim: day.readinessLabel)
                .font(.ryft(.label))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let delta = day.readinessDelta {
                DeltaLabel(spec: .readiness, delta: delta, reference: String(localized: "vs 7 d"), font: .ryft(.label),
                           referenceColor: DeltaLabel.color(delta, spec: .readiness))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TodayLayout.gaugeToLabel)
        .accessibilityHidden(true)
    }

    /// A night not scored yet (§P4-5): the latest scored day's orbit, dimmed, breathing until scoring takes longer than
    /// usual; in the label row's place the day it's from, "Scoring your night…" and when to expect it; then the ruler
    /// without a needle. VoiceOver hears the title and the day in the gauge's value; the detail is read on its own.
    private func pendingHero(_ day: TodayContent) -> some View {
        VStack(spacing: 0) {
            gaugeSlot {
                OrbitGauge(mode: day.orbit, size: .hero, showsCaption: false, accessibilityNote: day.pendingSpokenNote,
                           identifier: "today.pendingGauge", breathes: !day.pendingIsStatic, numeral: numeral,
                           entrance: gaugeEntrance(day.orbit))
                    .modifier(gaugeEntranceConsumer(day.orbit))
            }
            VStack(spacing: TodayLayout.pendingLineGap) {
                if let scored = day.pendingScoredDay {
                    Text(scored)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(day.pendingTitle)
                    .font(.ryft(.label))
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
            .frame(maxWidth: .infinity)
            .padding(.top, TodayLayout.gaugeToLabel)
            ruler(day)
        }
    }

    /// Row 9: 0–100, the high band marked (not "the current band"), the needle at the readiness. No zone and only the
    /// ends labelled where the number isn't placed in a band; no needle without a number. The next block is measured
    /// from its 36 pt box; the labels overflow it (VF1).
    private func ruler(_ day: TodayContent) -> some View {
        RulerScale(range: 0...100, value: day.rulerValue, zone: day.rulerZone, zoneStyle: .standard,
                   tickCount: RulerScale.Ticks.today, labels: day.rulerLabels, size: .regular,
                   accessibilityLabel: Text("Readiness scale", comment: "VoiceOver label of Today's readiness ruler (0 to 100)."),
                   accessibilityValue: Text(verbatim: day.rulerSpoken), followingGap: belowRuler(day))
            .accessibilityIdentifier("today.ruler")
            .padding(.top, TodayLayout.labelToRuler)
    }

    /// The note under the label row and, under it, its link when there is one (a blocked baseline with `devices.setup`
    /// on). `readWithGauge`: VoiceOver hears the note in the gauge's value, so the line itself is hidden; the link stays
    /// its own button either way.
    private func noteBlock(_ note: TodayPresentation.Note, readWithGauge: Bool) -> some View {
        VStack(spacing: 0) {
            GaugeNote(text: note.text, systemImage: note.systemImage)
                .transition(.opacity)
                .accessibilityIdentifier("today.gaugeNote")
                .accessibilityHidden(readWithGauge)
            if let link = note.link {
                GaugeNoteLink(title: link.title) { open(link) }
                    .transition(.opacity)
                    .accessibilityIdentifier("today.gaugeNote.link")
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The note's link: Check sync's model is made here, on the tap, for the sheet to keep.
    private func open(_ link: CalibrationLink) {
        linkCheck = link == .checkSync ? .make(env: env, trackers: screens.devices.trackers) : nil
        calibrationLink = link
    }

    // MARK: row 10: attention cards

    private func hasAttentionCard(_ day: TodayContent) -> Bool {
        day.rawNight != nil || day.watchHint != nil
    }

    /// The gap under the ruler: to the attention cards, else the tiles, else the cards below.
    private func belowRuler(_ day: TodayContent) -> CGFloat {
        TodayLayout.belowRuler(hasAttentionCard: hasAttentionCard(day), showsTiles: day.showsTiles)
    }

    /// Last night from Apple Health and the night hint (pending only), 12 below the ruler and 12 apart.
    @ViewBuilder
    private func attentionCards(_ day: TodayContent) -> some View {
        if hasAttentionCard(day) {
            VStack(spacing: TodayLayout.cardGap) {
                if let night = day.rawNight { RawNightCard(night: night, sourceName: day.rawNightSource) }
                if let hint = day.watchHint { WatchSyncHintCard(hint: hint, showsAction: !model.showsRefreshIssue) }
            }
            .padding(.top, TodayLayout.rulerToCards)
        }
    }

    // MARK: row 13: the cards below

    /// In today's order, 12 apart; the error cards last (the status line's "Details" scrolls to them).
    private func cardsBelow(_ day: TodayContent) -> some View {
        VStack(spacing: TodayLayout.cardGap) {
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
        }
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
            RefreshIssueCard(issue: issue, isDemo: model.isDemo, retry: { await model.refresh() },
                             signIn: { await model.signIn() })
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
///   before it was ever active) is built again once when it is next seen. Not yet revealed by the launch sequence
///   counts as unseen, like the background (`launchRevealsRoot`, ADR 0017, design.md §P4-7): the entrance plays at the
///   hand-off, or when the lock-up has landed in the header after the matched move.
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
        /// A placeholder (nothing to show) is on screen while the flag holds: the gauge with something to show that
        /// replaces it assembles over its tracks. Remembered by Today; never reset (the flag ends it).
        var placeholderSeen = false
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

    /// The gauge's entrance parameter: while the flag holds and the gauge has something to show, `.assemble`, or
    /// `.assembleOverTracks` when it replaces a placeholder that was on screen (its tracks never vanish and trim in
    /// again). `.none` otherwise.
    static func entrance(flag: Bool, mode: OrbitGaugeMode, placeholderSeen: Bool = false) -> OrbitGauge.Entrance {
        guard flag, hasSomethingToShow(mode) else { return .none }
        return placeholderSeen ? .assembleOverTracks : .assemble
    }

    /// Whether the gauge's identity counts it as showable. Only while the flag holds: data that becomes showable then
    /// makes a new instance, which latches the entrance. Once consumed it is fixed, so data that comes or goes later
    /// animates the values in one instance (PR 1) instead of popping in. Consuming happens only on a showable gauge,
    /// so the identity does not change at that moment.
    static func identityShowable(flag: Bool, showable: Bool) -> Bool {
        !flag || showable
    }

    /// `flag`: `TodayViewModel.assemblesGauge`. `showable`: `hasSomethingToShow` of the gauge's mode. `phase`: the
    /// scene phase now (after the change, for `.phaseChanged`).
    static func decide(flag: Bool, showable: Bool, phase: ScenePhase, event: Event, playedUnseen: Bool) -> Outcome {
        // Consumed: nothing plays again in this process, and nothing is remembered. Nothing to show: this gauge
        // doesn't assemble and doesn't count (the one with data is a new instance and starts afresh); on screen, it
        // is a placeholder whose tracks the next gauge keeps.
        guard flag else { return Outcome() }
        guard showable else { return Outcome(placeholderSeen: phase != .background) }
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
    /// The gauge's mode: whether it has something to show is part of its identity while the flag holds.
    let mode: OrbitGaugeMode
    /// Today remembers that a placeholder was on screen (`Outcome.placeholderSeen`).
    let placeholderSeen: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.launchRevealsRoot) private var launchReveals
    /// Bumped only to build again a gauge that played unseen.
    @State private var run = 0
    @State private var playedUnseen = false

    /// The gauge's identity: a new instance when its data becomes showable while the flag holds (it latches its
    /// entrance then; `TodayGaugeEntrance.identityShowable`), and when one that played unseen is built again.
    private struct Identity: Hashable {
        var run: Int
        var showable: Bool
    }

    private var showable: Bool { TodayGaugeEntrance.hasSomethingToShow(mode) }

    /// The phase as the gauge is seen: not yet revealed by the launch sequence is the background.
    private func seen(_ phase: ScenePhase) -> ScenePhase { launchReveals ? .background : phase }

    func body(content: Content) -> some View {
        content
            // Inside the identity: a gauge built again appears again.
            .onAppear { apply(.appeared, phase: seen(scenePhase)) }
            .id(Identity(run: run,
                         showable: TodayGaugeEntrance.identityShowable(flag: model.assemblesGauge, showable: showable)))
            .onChange(of: scenePhase) { _, phase in apply(.phaseChanged, phase: seen(phase)) }
            // Revealed (at the hand-off, or when the matched move lands): a phase change into what the scene is in now.
            .onChange(of: launchReveals) { apply(.phaseChanged, phase: seen(scenePhase)) }
    }

    private func apply(_ event: TodayGaugeEntrance.Event, phase: ScenePhase) {
        let flag = model.assemblesGauge
        let outcome = TodayGaugeEntrance.decide(flag: flag, showable: showable, phase: phase, event: event,
                                                playedUnseen: playedUnseen)
        if outcome.playedUnseen != playedUnseen { playedUnseen = outcome.playedUnseen }
        if outcome.rebuild { run += 1 }
        if outcome.consume { model.gaugeDidAssemble() }
        if outcome.placeholderSeen { placeholderSeen() }
        if flag {
            let what = "\(event) in \(phase), showable \(showable)"
            Self.log.debug("gauge entrance: \(what, privacy: .public)")
        }
    }

    private static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "today")
}

/// Where the calibration note's link goes (design.md §7 rev. 2 §2): the tracker's card, Check sync or Devices &
/// sync, each the root of its own stack as a sheet's page with Close (Nocturne PR 6 C2); what Devices & sync pushes keeps
/// the sheet's top inset (`DevicesPagePlacement.pushedInSheet`). Sync details from the status line is the same kind of page.
private struct CalibrationLinkSheet: View {
    let link: CalibrationLink
    /// Check sync's model, made on the tap (`TodayView.open`).
    let check: TrackerCheckModel?

    @Environment(ScreenModels.self) private var screens
    @Environment(\.appEnvironment) private var env

    var body: some View {
        NavigationStack { destination }
    }

    @ViewBuilder
    private var destination: some View {
        switch link {
        case .setup(let id, _):
            // A newer catalog may have dropped the tracker: Devices & sync then.
            if let tracker = env.trackerCatalog.tracker(id) {
                TrackerDetailView(tracker: tracker, model: screens.profile.devices, placement: .sheet) {}
            } else {
                DevicesAndSyncView(model: screens.profile.devices, placement: .sheet)
            }
        case .checkSync:
            if let check {
                TrackerCheckView(model: check, placement: .sheet)
            } else {
                DevicesAndSyncView(model: screens.profile.devices, placement: .sheet)
            }
        case .devices:
            DevicesAndSyncView(model: screens.profile.devices, placement: .sheet)
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
/// yet. Open Garmin Connect to sync it." with the data's age (ui.md §6.2, errata 2). A quiet hint: no dismissal; it goes
/// when the night arrives. Times in the screen's locale.
///
/// The whole card is the control (design.md §D3): "Open Garmin Connect" when the app's scheme is known and installed,
/// else "Garmin Connect in the App Store", else (an Apple device, or the error card's action on screen) no button at all.
/// VoiceOver reads two elements: the sentence with its age, then the action.
struct WatchSyncHintCard: View {
    let hint: WatchSyncHint
    /// The action; dropped while the error card offers its own (one action on screen).
    var showsAction = true

    @Environment(\.openURL) private var openURL
    @Environment(\.appInstalled) private var appInstalled
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    /// 15 pt at the default size, growing with the callout text (as `InlineMessage`'s icon).
    @ScaledMetric(relativeTo: .callout) private var iconSize: CGFloat = 15
    /// The leading glyph's column: as wide as the widest glyph (the watch with its waves), so the text starts at the same
    /// place whichever glyph the card shows.
    @ScaledMetric(relativeTo: .callout) private var iconColumn: CGFloat = 28

    private var identifier: String { hint.isNight ? "today.nightHint" : "today.watchHint" }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            // Asked on every build of the card, never cached: each minute, and on each scene-phase change, because the
            // closure reads `scenePhase` (the user may have installed or removed the app meanwhile, often in the App
            // Store page this card opened). No `.id` rebuild, so VoiceOver keeps its focus on the button.
            let _ = scenePhase
            if showsAction, let action = hint.action(canOpen: { appInstalled($0) }) {
                Button { perform(action) } label: { card(now: context.date, action: action) }
                    .buttonStyle(PressableButtonStyle())
                    // Sighted users tap anywhere. VoiceOver gets the design's two elements instead (design.md §D3.5): a
                    // Button's children would all read as buttons, the sentence too.
                    .accessibilityRepresentation { spoken(now: context.date, action: action) }
            } else {
                card(now: context.date, action: nil)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func card(now: Date, action: WatchSyncHint.Action?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hint.systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: iconColumn)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: hint.text(now: now, locale: locale))
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption = hint.caption(locale: locale) {
                        // Secondary ink: tertiary was under 4.5:1 on the card in light mode.
                        Text(verbatim: caption)
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                if let action { verbRow(action) }
            }
            Spacer(minLength: 0)
        }
        // `Card`'s surface (design.md §D3.2): no hairline, the surface is the edge.
        .padding(Theme.Metrics.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
    }

    /// What VoiceOver reads when the card is a button: the sentence with its age (static text), then the action.
    private func spoken(now: Date, action: WatchSyncHint.Action) -> some View {
        VStack {
            Text(verbatim: [hint.text(now: now, locale: locale), hint.caption(locale: locale)].compactMap { $0 }.joined(separator: "\n"))
            Button { perform(action) } label: { Text(verbatim: hint.title(action)) }
                .accessibilityHint(action.opensApp ? Text("Leaves RYFT.") : Text("Opens the App Store."))
                .accessibilityIdentifier("\(identifier).action")
        }
    }

    /// "Open Garmin Connect ↗" in ink, the glyph saying it leaves RYFT; the store page gets its own glyph so the two
    /// destinations don't look the same. At AX sizes the title wraps and the glyph stays on its first line.
    private func verbRow(_ action: WatchSyncHint.Action) -> some View {
        let title = hint.title(action)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: title)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: action.opensApp ? "arrow.up.forward.app" : "arrow.down.app")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
    }

    /// The app, and its store page if it doesn't open after all (`Action.fallback(accepted:)`; no error: the page shows
    /// Open or Get). Nothing is logged: whether the app opened says whether it's installed (ADR 0012, Privacy).
    private func perform(_ action: WatchSyncHint.Action) {
        switch action {
        case .store(let url):
            openURL(url)
        case .openApp(let url, _):
            openURL(url) { accepted in
                if let store = action.fallback(accepted: accepted) { openURL(store) }
            }
        }
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

// MARK: - previews (dark only, default and AX3; design.md §P4-10)

/// A state of Today on mock data, at the default size or AX3.
private struct TodayPreview: View {
    var state: AppState = .preview()
    var online = true
    var heroNumerals: HeroNumerals?
    var reduceTransparency: Bool?
    var ax3 = false

    var body: some View {
        TodayView(heroNumerals: heroNumerals, reduceTransparency: reduceTransparency)
            .previewEnvironment(state, online: online)
            .environment(\.dynamicTypeSize, ax3 ? .accessibility3 : .large)
    }
}

/// Row E: signed in (demo data source), nothing scored and nothing cached yet: the empty gauge, no tiles.
@MainActor
private func noScoresState() -> AppState {
    let state = AppState(env: .preview())
    state.user = MockData.user
    return state
}

/// The account without a name (Sign in with Apple may deliver none, R-N2): "Good evening", no comma.
@MainActor
private func namelessState() -> AppState {
    let state = AppState.preview()
    let user = MockData.user
    state.user = User(id: user.id, name: "", tz: user.tz, maxHr: user.maxHr, sleepBaseMin: user.sleepBaseMin)
    return state
}

#Preview("Today · scored") { TodayPreview() }
#Preview("Today · scored · AX3") { TodayPreview(ax3: true) }
#Preview("Today · thin digits") { TodayPreview(heroNumerals: .thin) }
#Preview("Today · thin digits · AX3") { TodayPreview(heroNumerals: .thin, ax3: true) }
#Preview("Today · pending with a previous day") { TodayPreview(state: .preview(scenario: .pending)) }
#Preview("Today · pending with a previous day · AX3") { TodayPreview(state: .preview(scenario: .pending), ax3: true) }
#Preview("Today · pending slow") { TodayPreview(state: .preview(scenario: .scoringSlow)) }
#Preview("Today · pending slow · AX3") { TodayPreview(state: .preview(scenario: .scoringSlow), ax3: true) }
#Preview("Today · pending, nothing scored") { TodayPreview(state: .preview(scenario: .pendingNoPrevious)) }
#Preview("Today · pending, nothing scored · AX3") { TodayPreview(state: .preview(scenario: .pendingNoPrevious), ax3: true) }
#Preview("Today · calibrating") { TodayPreview(state: .preview(scenario: .calibrating)) }
#Preview("Today · calibrating · AX3") { TodayPreview(state: .preview(scenario: .calibrating), ax3: true) }
#Preview("Today · calibrating with a readiness") { TodayPreview(state: .preview(scenario: .learningHRV)) }
#Preview("Today · calibrating with a readiness · AX3") { TodayPreview(state: .preview(scenario: .learningHRV), ax3: true) }
#Preview("Today · blocked, with a readiness") { TodayPreview(state: .preview(scenario: .blockedHRV)) }
#Preview("Today · blocked, with a readiness · AX3") { TodayPreview(state: .preview(scenario: .blockedHRV), ax3: true) }
#Preview("Today · recalculating, yesterday") { TodayPreview(state: .preview(scenario: .recalculatingYesterday)) }
#Preview("Today · recalculating, yesterday · AX3") {
    TodayPreview(state: .preview(scenario: .recalculatingYesterday), ax3: true)
}
#Preview("Today · first import") { TodayPreview(state: .preview(scenario: .importing)) }
#Preview("Today · first import · AX3") { TodayPreview(state: .preview(scenario: .importing), ax3: true) }
#Preview("Today · baselines without a readiness") { TodayPreview(state: .preview(scenario: .needsVitalsBaselines)) }
#Preview("Today · baselines without a readiness · AX3") {
    TodayPreview(state: .preview(scenario: .needsVitalsBaselines), ax3: true)
}
#Preview("Today · no scores yet") { TodayPreview(state: noScoresState()) }
#Preview("Today · no scores yet · AX3") { TodayPreview(state: noScoresState(), ax3: true) }
#Preview("Today · not set up") { TodayPreview(state: .preview(empty: true)) }
#Preview("Today · not set up · AX3") { TodayPreview(state: .preview(empty: true), ax3: true) }
#Preview("Today · offline") { TodayPreview(state: .preview(online: false), online: false) }
#Preview("Today · offline · AX3") { TodayPreview(state: .preview(online: false), online: false, ax3: true) }
#Preview("Today · demo") { TodayPreview(state: .preview(coachMarks: true)) }
#Preview("Today · demo · AX3") { TodayPreview(state: .preview(coachMarks: true), ax3: true) }
#Preview("Today · with attention cards (night hint)") { TodayPreview(state: .preview(scenario: .nightGap)) }
#Preview("Today · with attention cards (night hint) · AX3") { TodayPreview(state: .preview(scenario: .nightGap), ax3: true) }
#Preview("Today · quiet tracker hint") { TodayPreview(state: .preview(scenario: .watch)) }
#Preview("Today · quiet tracker hint · AX3") { TodayPreview(state: .preview(scenario: .watch), ax3: true) }
#Preview("Today · without a name") { TodayPreview(state: namelessState()) }
#Preview("Today · without a name · AX3") { TodayPreview(state: namelessState(), ax3: true) }
#Preview("Today · Reduce Transparency") { TodayPreview(reduceTransparency: true) }
#Preview("Today · Reduce Transparency · AX3") { TodayPreview(reduceTransparency: true, ax3: true) }
#Preview("Today · My Day") { TodayPreview(state: .preview(flags: [.todayMyDay: true])) }
#Preview("Today · My Day · AX3") { TodayPreview(state: .preview(flags: [.todayMyDay: true]), ax3: true) }

/// The matched move over the Today layout at one moment (design.md §P4-7): the header's lock-up hidden, the gauge's slot
/// empty, the background and tagline fading by elapsed time; τ 1 is the landing (the overlay is gone after it). The
/// targets are the header's own, as it reports them to `LaunchHost` in the app.
private struct TodayHandOffPreview: View {
    var time: Double
    @Environment(\.self) private var environment
    @State private var targets = Targets()

    @MainActor @Observable final class Targets {
        var mark: CGRect?
        var wordmark: CGRect?
    }

    var body: some View {
        let palette = LaunchFrame.Palette.resolved(in: environment)
        let elapsed = time * LaunchSequence.Timing.moveHandOff
        let fade = 1 - LaunchFrame.Easing.easeOut(elapsed / LaunchSequence.Timing.moveFade)
        ZStack {
            TodayView()
                .environment(\.launchRevealsRoot, time < 1)
                .environment(\.launchHidesHandOffTargets, time < 1)
                .environment(\.launchHandOffRegistrar, LaunchHandOffRegistrar { [targets] role, frame in
                    switch role {
                    case .mark: targets.mark = frame
                    case .wordmark: targets.wordmark = frame
                    }
                })
            if time < 1, let mark = targets.mark {
                LaunchFullScreen { bottom in
                    ZStack {
                        Theme.background.opacity(fade)
                        LaunchStage(frame: LaunchFrame(t: 1, palette: palette), safeAreaBottom: bottom,
                                    move: LaunchStage.Move(mark: mark, wordmark: targets.wordmark, time: time,
                                                           taglineOpacity: fade, palette: palette))
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .previewEnvironment()
    }
}

#Preview("Today · hand-off τ 0") { TodayHandOffPreview(time: 0) }
#Preview("Today · hand-off τ 0.25") { TodayHandOffPreview(time: 0.25) }
#Preview("Today · hand-off τ 0.5") { TodayHandOffPreview(time: 0.5) }
#Preview("Today · hand-off τ 0.79") { TodayHandOffPreview(time: 0.79) }
#Preview("Today · hand-off τ 1") { TodayHandOffPreview(time: 1) }

#Preview("Import, raw night, hint", traits: .sizeThatFitsLayout) {
    DarkPreview {
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

/// Mock hints: Garmin Connect quiet since last night 23:24, the Apple Watch, an unknown source; Garmin's scheme and
/// `sync` sentence from the bundled catalog, as Today resolves them.
private enum PreviewHint {
    static let lastNight = Calendar.current.date(bySettingHour: 23, minute: 24, second: 0,
                                                 of: .now.addingTimeInterval(-86_400)) ?? .now
    static let store = URL(string: "https://apps.apple.com/app/id583446403")
    static let garmin = MockData.tracker("garmin")
    static func night(_ kind: SourceApp.Kind, name: String) -> WatchSyncHint {
        WatchSyncHint(night: NightGap(name: name, kind: kind, storeURL: kind == .app ? store : nil, newest: lastNight,
                                      appURL: kind == .app ? garmin.appURL : nil))
    }
    /// Garmin Connect quiet since last night, with the catalog's `sync` sentence and the app's scheme.
    static let quiet = WatchSyncHint(source: "Garmin Connect", since: lastNight, isApp: true, storeURL: store,
                                     appURL: garmin.appURL, sync: garmin.sync)
    /// The same source without a `sync` sentence: today's full sentence.
    static let quietNoSync = WatchSyncHint(source: "Garmin Connect", since: lastNight, isApp: true, storeURL: store)
    static let appleWatch = WatchSyncHint(source: "Apple Watch", since: lastNight, isApp: false)
}

/// The hint's states (design.md §D3.3): the app installed (Open), not installed (App Store), an Apple device (no button).
private struct HintStates: View {
    var body: some View {
        VStack(spacing: 16) {
            WatchSyncHintCard(hint: PreviewHint.quiet)
                .environment(\.appInstalled, .installed)
            WatchSyncHintCard(hint: PreviewHint.quiet)
                .environment(\.appInstalled, .notInstalled)
            WatchSyncHintCard(hint: PreviewHint.appleWatch)
        }
    }
}

#Preview("Quiet hint · open, store, Apple device", traits: .sizeThatFitsLayout) {
    DarkPreview { HintStates() }
}

#Preview("Quiet hint · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 16) {
            WatchSyncHintCard(hint: PreviewHint.quiet)
                .environment(\.appInstalled, .installed)
            WatchSyncHintCard(hint: PreviewHint.quietNoSync)
                .environment(\.appInstalled, .notInstalled)
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Night hint · app, watch, unknown, quiet", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 16) {
            WatchSyncHintCard(hint: PreviewHint.night(.app, name: "Garmin Connect"))
                .environment(\.appInstalled, .installed)
            WatchSyncHintCard(hint: PreviewHint.night(.app, name: "Garmin Connect"))
                .environment(\.appInstalled, .notInstalled)
            WatchSyncHintCard(hint: PreviewHint.night(.appleDevice, name: "Apple Watch"))
            WatchSyncHintCard(hint: PreviewHint.night(.unknown, name: "Sleep Diary"))
            WatchSyncHintCard(hint: PreviewHint.quietNoSync)
                .environment(\.appInstalled, .notInstalled)
            // The error card shows: one action on screen, so no "Open".
            WatchSyncHintCard(hint: PreviewHint.night(.app, name: "Garmin Connect"), showsAction: false)
        }
    }
}

#Preview("Night hint · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        WatchSyncHintCard(hint: PreviewHint.night(.app, name: "Garmin Connect"))
            .environment(\.appInstalled, .installed)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
