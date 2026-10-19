import SwiftUI

/// Greeting, readiness ring, Sleep / Recovery / Strain tiles, 7-day trend.
struct TodayView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var settings: Settings
    @ObservedObject private var apiStatus = APIStatus.shared
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @Environment(\.dynamicTypeSize) private var typeSize

    private var score: DailyScore? { state.today?.score }

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                if state.hasDataSource {
                    greeting
                    readinessRing
                    tiles
                    if state.hasNoHealthData { HealthAccessHint() }
                    TrainTodayCard()
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
            if !connectivity.isOnline {
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
        MetricGauge(spec: .readiness, value: score?.readiness.map(Double.init), size: .large,
                    delta: .vsSevenDayMean(state.readinessWeek?.points ?? []),
                    title: String(localized: "Overall readiness"), showsMark: true)
            .padding(.vertical, 4)
    }

    private var tiles: some View {
        let sleepMin = score?.sleepActualMin ?? state.today?.sleep?.totalMin
        // Three columns truncate at accessibility sizes; stack the tiles there.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            MetricTile(title: "Sleep", value: Fmt.duration(minutes: sleepMin), systemImage: "moon.fill",
                       tint: Theme.metricSleep, accessibilityHint: "Opens Sleep") {
                state.selectedTab = .sleep
            }
            MetricTile(title: "Recovery", value: Fmt.percent(score?.recovery), systemImage: "heart",
                       tint: Theme.band(forScore: score?.recovery),
                       caption: Theme.bandLabel(forScore: score?.recovery), accessibilityHint: "Opens Insights") {
                state.selectedTab = .insights
            }
            MetricTile(title: "Strain", value: Fmt.strain(score?.strain), systemImage: "bolt.fill",
                       tint: Theme.metricStrain, accessibilityHint: "Opens Strain") {
                state.selectedTab = .strain
            }
        }
        .fixedSize(horizontal: false, vertical: !typeSize.isAccessibilitySize)
    }

    private var trends: some View {
        Button {
            state.selectedTab = .insights
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Trends", showsChevron: true)
                    TrendChart(points: state.readinessWeek?.points ?? [], spec: .readiness, window: .week,
                               interactive: false, height: 110)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(Text("Opens Insights"))
    }

    @ViewBuilder
    private var status: some View {
        if let notice = apiStatus.retryNotice {
            InlineMessage(message: notice, systemImage: "clock.arrow.circlepath")
        } else if let error = state.error {
            InlineMessage(message: state.today == nil
                          ? error
                          : String(localized: "Couldn't refresh just now — showing your last loaded data."),
                          details: state.errorDetails,
                          retry: { await state.syncAndRefresh(using: sync) })
        } else if !state.isDemo, let syncError = sync.lastError, settings.isConfigured {
            InlineMessage(message: String(localized: "Health sync paused: \(syncError)"),
                          systemImage: "heart.text.square",
                          details: sync.lastErrorDetails,
                          retry: { await state.syncAndRefresh(using: sync) })
        }
        UpdatedLabel(date: state.lastUpdated, isLoading: state.isLoading || sync.isSyncing, isDemo: state.isDemo,
                     scoredAt: score?.computedAt)
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
    TodayView().previewEnvironment(AppState.preview(), online: false)
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
