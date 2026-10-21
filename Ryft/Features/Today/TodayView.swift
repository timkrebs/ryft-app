import SwiftUI

/// Greeting and the sync's status line, readiness gauge (or what's true while data is on
/// its way: the first import, a night being scored, the baseline being learned), Sleep /
/// Recovery / Strain tiles, Train, 7-day trend. Layout only: everything shown comes from
/// `TodayViewModel`.
struct TodayView: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: TodayViewModel { screens.today }
    @State private var showsJournal = false
    /// Counts scores that landed while the night was pending: one success haptic each.
    @State private var landed = 0

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScreenScaffold {
                    if model.hasDataSource {
                        greeting
                        if let row = model.importRow { ImportRow(progress: row) }
                        hero
                            .coachMarkTarget(.gauges)
                            .id(CoachMarkTarget.gauges)
                        if let night = model.rawNight { RawNightCard(night: night) }
                        if let hint = model.watchHint { WatchSyncHintCard(hint: hint) }
                        if model.showsTiles {
                            tiles
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
                        if screens.journal.isLive {
                            JournalCard(store: screens.journal) { showsJournal = true }
                        }
                        // From 17:00: when to be in bed tonight (Bedtime & wake).
                        if screens.bedtime.isEnabled, screens.bedtime.isEvening(), !model.hero.isImporting {
                            TonightCard(planner: screens.bedtime)
                        }
                        if model.showsTrain, !model.hero.isImporting { TrainTodayCard() }
                        if !model.hero.isImporting {
                            trends
                                .coachMarkTarget(.trends)
                                .id(CoachMarkTarget.trends)
                        }
                        status
                    } else {
                        greeting
                        SetupCard { model.open(.profile) }
                    }
                }
                .coachMarks(model.coachMarks, enabled: model.showsCoachMarks)
                .onAppear { LaunchSignpost.todayAppeared(cached: model.readiness != nil || model.lastUpdated != nil) }
                // Last night from Apple Health and the newest record per source, after each sync.
                .task(id: model.healthFactsKey) { await model.loadHealthFacts() }
                // The night was pending and its score landed: one subtle change, one haptic.
                .onChange(of: model.hero.isPending) { was, now in
                    if was, !now { landed += 1 }
                }
                .sensoryFeedback(.success, trigger: landed)
                .sheet(isPresented: $showsJournal) {
                    JournalSheet(model: JournalSheetModel(store: screens.journal))
                }
                // The journal: whether it's live (M5), and yesterday's answer for the card.
                .task(id: model.lastUpdated) {
                    await screens.journal.load()
                    await screens.journal.loadDay(screens.journal.yesterday)
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

    private var greeting: some View {
        VStack(spacing: 8) {
            VStack(spacing: 6) {
                Text(model.greeting)
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                Text(model.sentence)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            if model.hasDataSource {
                SyncStatusLineView(line: model.syncLine) { model.resolveLine() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// The gauge, or what takes its place while data is on its way.
    @ViewBuilder
    private var hero: some View {
        Group {
            switch model.hero {
            case .importing(let progress):
                ImportCard(progress: progress, asksForPush: model.showsImportPushPrompt) {
                    Task { await model.enablePush() }
                } dismissPush: {
                    model.dismissPushPrompt()
                }
                .accessibilityIdentifier("today.importCard")
            case .pending(let night):
                PendingGauge(previous: night.previousReadiness, previousDay: night.previousDay,
                             title: night.title, detail: night.detail)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("today.pendingGauge")
            case .calibrating(let nights):
                VStack(spacing: 8) {
                    BaselineGauge(nights: nights)
                        .accessibilityIdentifier("today.baselineGauge")
                    // Row B over a long history without HRV: why the nights don't fill.
                    if let note = model.gaugeNote { gaugeNote(note) }
                }
                .padding(.vertical, 4)
            case .score:
                VStack(spacing: 8) {
                    readinessRing
                    // Row D: in the band/delta line's place, read as part of the gauge.
                    if let note = model.gaugeNote {
                        gaugeNote(note)
                            .accessibilityHidden(model.gaugeSpokenNote != nil)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .transition(.opacity)
        // One row to another: a 250 ms cross-fade (ui.md §1.3); an instant swap under Reduce Motion.
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: model.hero.kind)
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: model.gaugeNote)
    }

    /// Readiness on its 0–100 scale with band ticks, the band word and the change
    /// against the days before (from the 7-day trend, row A only).
    private var readinessRing: some View {
        MetricGauge(spec: .readiness, value: model.readiness, size: .large, delta: model.readinessDelta,
                    title: String(localized: "Overall readiness"), showsMark: true,
                    accessibilityNote: model.gaugeSpokenNote)
            .accessibilityIdentifier("today.readinessGauge")
    }

    private func gaugeNote(_ note: TodayPresentation.Note) -> some View {
        GaugeNote(text: note.text, systemImage: note.systemImage)
            .transition(.opacity)
            .accessibilityIdentifier("today.gaugeNote")
    }

    /// One day for all three (ui.md §1): today's, or the latest scored day dimmed with its date.
    private var tiles: some View {
        // Three columns truncate at accessibility sizes; stack the tiles there.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            MetricTile(title: "Sleep", value: model.sleepText, systemImage: "moon.fill",
                       tint: Theme.metricSleep, caption: model.tileCaption, isDimmed: model.tilesDimmed,
                       accessibilityHint: "Opens Sleep") {
                model.open(.sleep)
            }
            MetricTile(title: "Recovery", value: model.recoveryText, systemImage: "heart",
                       tint: Theme.band(forScore: model.recovery),
                       caption: model.recoveryCaption, isDimmed: model.tilesDimmed, accessibilityHint: "Opens Insights") {
                model.open(.insights)
            }
            MetricTile(title: "Strain", value: model.strainText, systemImage: "bolt.fill",
                       tint: Theme.metricStrain, caption: model.tileCaption, isDimmed: model.tilesDimmed,
                       accessibilityHint: "Opens Strain") {
                model.open(.strain)
            }
        }
        .fixedSize(horizontal: false, vertical: !typeSize.isAccessibilitySize)
    }

    private var trends: some View {
        Button {
            model.open(.insights)
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Trends", showsChevron: true)
                    TrendChart(points: model.readinessWeek, spec: .readiness, window: .week,
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
        case .error(let message, let details):
            InlineMessage(message: message, details: details, retry: { await model.refresh() })
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
    /// The times in the screen's locale: "23:17" in German, the user's 12/24-hour setting in the app.
    @Environment(\.locale) private var locale
    private var bedtime: String { Fmt.time(night.bedtime, locale: locale) }
    private var wake: String { Fmt.time(night.wake, locale: locale) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Last night")
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("From Apple Health · not scored yet")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.trailing)
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
                Text(verbatim: "\(bedtime) – \(wake) · \(night.source)")
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last night, from Apple Health, not scored yet"))
        .accessibilityValue(Text("\(Fmt.duration(minutes: night.asleepMin)) asleep, \(bedtime) to \(wake), \(night.source)"))
        .accessibilityIdentifier("today.rawNight")
    }
}

/// "Nothing new from Garmin Connect since 23:40": a quiet hint, the source's own name.
struct WatchSyncHintCard: View {
    let hint: WatchSyncHint

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            InlineMessage(message: hint.text(now: context.date), systemImage: "applewatch.radiowaves.left.and.right")
        }
        .accessibilityIdentifier("today.watchHint")
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
