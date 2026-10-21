import SwiftUI

/// Greeting, readiness gauge, Sleep / Recovery / Strain tiles, Train, 7-day trend.
/// Layout only: everything shown comes from `TodayViewModel`.
struct TodayView: View {
    @Environment(ScreenModels.self) private var screens
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: TodayViewModel { screens.today }
    @State private var showsJournal = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScreenScaffold {
                    if model.hasDataSource {
                        greeting
                        readinessRing
                            .coachMarkTarget(.gauges)
                            .id(CoachMarkTarget.gauges)
                        tiles
                            .coachMarkTarget(.physiology)
                            .id(CoachMarkTarget.physiology)
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
                        if model.showsTrain { TrainTodayCard() }
                        trends
                            .coachMarkTarget(.trends)
                            .id(CoachMarkTarget.trends)
                        status
                    } else {
                        greeting
                        SetupCard { model.open(.profile) }
                    }
                }
                .coachMarks(model.coachMarks, enabled: model.showsCoachMarks)
                .onAppear { LaunchSignpost.todayAppeared(cached: model.readiness != nil || model.lastUpdated != nil) }
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
        VStack(spacing: 6) {
            Text(model.greeting)
                .font(.ryft(.title))
                .foregroundStyle(Theme.textPrimary)
            Text(model.sentence)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if model.isOffline {
                OfflinePill().padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    /// Readiness on its 0–100 scale with band ticks, the band word and the change
    /// against the days before (from the 7-day trend).
    private var readinessRing: some View {
        MetricGauge(spec: .readiness, value: model.readiness, size: .large, delta: model.readinessDelta,
                    title: String(localized: "Overall readiness"), showsMark: true)
            .padding(.vertical, 4)
    }

    private var tiles: some View {
        // Three columns truncate at accessibility sizes; stack the tiles there.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            MetricTile(title: "Sleep", value: model.sleepText, systemImage: "moon.fill",
                       tint: Theme.metricSleep, accessibilityHint: "Opens Sleep") {
                model.open(.sleep)
            }
            MetricTile(title: "Recovery", value: model.recoveryText, systemImage: "heart",
                       tint: Theme.band(forScore: model.recovery),
                       caption: model.recoveryBand, accessibilityHint: "Opens Insights") {
                model.open(.insights)
            }
            MetricTile(title: "Strain", value: model.strainText, systemImage: "bolt.fill",
                       tint: Theme.metricStrain, accessibilityHint: "Opens Strain") {
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

    @ViewBuilder
    private var status: some View {
        switch model.status {
        case .actionNeeded(let step, let message, let action):
            InlineMessage(message: message, systemImage: "hand.raised", retryTitle: LocalizedStringKey(action),
                          retry: { model.resolve(step) })
                .accessibilityIdentifier("today.actionNeeded")
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
        UpdatedLabel(date: model.lastUpdated, isLoading: model.isRefreshing, isDemo: model.isDemo,
                     scoredAt: model.scoredAt)
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
