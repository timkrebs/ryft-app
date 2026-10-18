import SwiftUI

/// Greeting, readiness ring, Sleep / Recovery / Strain tiles, 7-day trend.
struct TodayView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var settings: Settings

    private var score: DailyScore? { state.today?.score }

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                if state.hasDataSource {
                    greeting
                    readinessRing
                    tiles
                    trends
                    status
                } else {
                    greeting
                    SetupCard { state.selectedTab = .profile }
                }
            }
        }
    }

    // MARK: sections

    private var greeting: some View {
        VStack(spacing: 6) {
            Text(ReadinessCopy.greeting())
                .font(.ryft(.title))
                .foregroundStyle(Theme.textPrimary)
            Text(state.hasDataSource ? ReadinessCopy.sentence(score: score)
                                     : String(localized: "Let's get you set up."))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var readinessRing: some View {
        let readiness = score?.readinessValue
        return ScoreRing(progress: readiness.map { Double($0) / 100 }, size: 220, lineWidth: 11,
                         accessibilityLabel: Text("Readiness"),
                         accessibilityValue: readiness.map { Text("\($0) of 100") } ?? Text("No score yet")) {
            VStack(spacing: 6) {
                RyftMark()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Theme.textPrimary)
                CountingText(value: readiness.map(Double.init))
                    .font(.ryftNumber(size: 58))
                    .foregroundStyle(readiness == nil ? Theme.textTertiary : Theme.textPrimary)
                Text("Overall readiness")
                    .font(.ryftNumber(size: 9, weight: .medium))
                    .textCase(.uppercase)
                    .tracking(1.6)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var tiles: some View {
        let sleepMin = score?.sleepActualMin ?? state.today?.resolvedSleep?.totalMin
        return HStack(spacing: 10) {
            MetricTile(title: "Sleep", value: Fmt.duration(minutes: sleepMin), systemImage: "moon.fill",
                       tint: Theme.stageLight, accessibilityHint: "Opens Sleep") {
                state.selectedTab = .sleep
            }
            MetricTile(title: "Recovery", value: Fmt.percent(score?.recovery), systemImage: "heart",
                       tint: Theme.band(forScore: score?.recovery), accessibilityHint: "Opens Insights") {
                state.selectedTab = .insights
            }
            MetricTile(title: "Strain", value: Fmt.strain(score?.strain), systemImage: "bolt.fill",
                       accessibilityHint: "Opens Strain") {
                state.selectedTab = .strain
            }
        }
    }

    private var trends: some View {
        Button {
            state.selectedTab = .insights
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    CardHeader(title: "Trends", trailing: "7 days", showsChevron: true)
                    TrendChart(points: state.derivedTrend(.readiness, range: .week).points,
                               title: String(localized: "Readiness, last 7 days"), height: 84)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(Text("Opens Insights"))
    }

    @ViewBuilder
    private var status: some View {
        if let error = state.error {
            InlineMessage(message: state.today == nil
                          ? error
                          : String(localized: "Couldn't refresh just now — showing your last loaded data."),
                          retry: { await state.syncAndRefresh(using: sync) })
        } else if !state.isDemo, let syncError = sync.lastError, settings.isConfigured {
            InlineMessage(message: String(localized: "Health sync paused: \(syncError)"),
                          systemImage: "heart.text.square",
                          retry: { await state.syncAndRefresh(using: sync) })
        }
        UpdatedLabel(date: state.lastUpdated, isLoading: state.isLoading || sync.isSyncing, isDemo: state.isDemo)
    }
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

#Preview("Today · not set up") {
    TodayView().previewEnvironment(.preview(empty: true))
}
