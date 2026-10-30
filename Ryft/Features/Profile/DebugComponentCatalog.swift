#if DEBUG
import SwiftUI

/// Profile → Developer → Component catalog (Debug builds only): every `Design/`
/// component in its configurations and sizes, in dark or light, at Dynamic Type
/// XS, L or AX3. The regression surface for "reusable, configurable" components:
/// change one, scroll here, see every use.
struct DebugComponentCatalog: View {
    @State private var scheme: ColorScheme = .dark
    @State private var typeSize: CatalogTypeSize = .large

    enum CatalogTypeSize: String, CaseIterable, Identifiable {
        case xSmall = "XS", large = "L", accessibility3 = "AX3"
        var id: String { rawValue }
        var size: DynamicTypeSize {
            switch self {
            case .xSmall: return .xSmall
            case .large: return .large
            case .accessibility3: return .accessibility3
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    section("OrbitGauge") { orbits }
                    section("MetricGauge") { gauges }
                    section("RangeBar") { rangeBars }
                    section("DeltaLabel") { deltas }
                    section("TrendChart") { trends }
                    section("ZoneBar") { zones }
                    section("Sleep") { sleep }
                    section("MetricTile") { tiles }
                    section("ScoreRing") { rings }
                    section("Cards and rows") { cards }
                    section("Messages") { messages }
                    section("Buttons and pickers") { buttons }
                    section("Insights") { insights }
                    section("Brand") { brand }
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background)
            .environment(\.colorScheme, scheme)
            .dynamicTypeSize(typeSize.size)
        }
        .navigationTitle("Component catalog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("Appearance", selection: $scheme) {
                Text("Dark").tag(ColorScheme.dark)
                Text("Light").tag(ColorScheme.light)
            }
            Picker("Text size", selection: $typeSize) {
                ForEach(CatalogTypeSize.allCases) { Text(verbatim: $0.rawValue).tag($0) }
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Metrics.screenPadding)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: title)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            content()
        }
    }

    // MARK: sections

    /// Today's gauge in its modes and sizes (synthetic values). Calibrating (the count fills the segments) and pending (the previous day, dimmed).
    private var orbits: some View {
        let scored = OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)
        return VStack(alignment: .leading, spacing: 18) {
            OrbitGauge(mode: .scored(scored), size: .large,
                       caption: OrbitGauge.Caption(title: String(localized: "Overall readiness"),
                                                   delta: MetricDelta(current: 71, reference: 67)))
            HStack(alignment: .top, spacing: 12) {
                OrbitGauge(mode: .scored(scored), size: .medium)
                // A watch without HRV, no sleep yet: Recovery from what was scored, Sleep a hollow dot.
                OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, strain: 6.2)), size: .medium)
            }
            HStack(spacing: 12) {
                OrbitGauge(mode: .scored(scored), size: .small)
                OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 100, recovery: 1, sleep: 1, strain: 21)), size: .small)
                OrbitGauge(mode: .scored(.empty), size: .small)
            }
            HStack(spacing: 12) {
                OrbitGauge(mode: .scored(scored), size: .custom(dial: 44))
                OrbitGauge(mode: .pending(previous: nil), size: .small)
                OrbitGauge(mode: .pending(previous: scored), size: .small)
            }
            // Calibrating: the nights counted of seven; the segments step in when it appears.
            HStack(alignment: .top, spacing: 12) {
                OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .medium)
                OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 0)), size: .small)
                OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 7)), size: .small)
                OrbitGauge(mode: .pending(previous: scored), size: .medium)
            }
        }
    }

    private var gauges: some View {
        VStack(alignment: .leading, spacing: 18) {
            MetricGauge(spec: .readiness, value: 84, size: .large, delta: MetricDelta(current: 84, reference: 76),
                        title: String(localized: "Overall readiness"), showsMark: true)
            HStack(alignment: .top, spacing: 12) {
                MetricGauge(spec: .strain, value: 12.4, size: .medium, target: 11...14,
                            delta: MetricDelta(current: 12.4, reference: 10))
                MetricGauge(spec: .recovery, value: 28, size: .medium, delta: MetricDelta(current: 28, reference: 61))
            }
            HStack(spacing: 12) {
                MetricGauge(spec: .recovery, value: 55, size: .small)
                MetricGauge(spec: .strain, value: 19.2, size: .small)
                MetricGauge(spec: .readiness, value: nil, size: .small)
            }
        }
    }

    private var rangeBars: some View {
        VStack(spacing: 16) {
            RangeBar(spec: .hrv, value: 58, range: 41...66, typical: 48...56, baseline: 53)
            RangeBar(spec: .rhr, value: 47, range: 45...56, typical: 48...51, baseline: 50)
            RangeBar(spec: .respRate, value: 14.6, range: 13.8...15.9, typical: 14.2...15)
            RangeBar(spec: .spo2, value: nil, range: 94...98)
        }
    }

    private var deltas: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeltaLabel(spec: .hrv, delta: MetricDelta(current: 56, reference: 52), reference: String(localized: "vs 7 d"))
            DeltaLabel(spec: .hrv, delta: MetricDelta(current: 47, reference: 52), reference: String(localized: "vs 7 d"))
            DeltaLabel(spec: .rhr, delta: MetricDelta(current: 47, reference: 50), reference: String(localized: "vs 7 d"))
            DeltaLabel(spec: .strain, delta: MetricDelta(current: 14, reference: 11))
            DeltaLabel(spec: .sleepMin, delta: MetricDelta(current: 468, reference: 443))
            DeltaLabel(spec: .hrv, delta: MetricDelta(current: 52.4, reference: 52))
        }
    }

    private var trends: some View {
        VStack(spacing: 24) {
            TrendChart(points: MockData.trend(.readiness, range: .week).points, spec: .readiness, window: .week, height: 110)
            let hrv = MockData.trend(.hrv, range: .month)
            TrendChart(points: hrv.points, spec: .hrv, window: .month, baseline: hrv.baseline,
                       band: hrv.min.flatMap { lo in hrv.max.map { lo...$0 } })
            TrendChart(points: MockData.trend(.strain, range: .quarter).points, spec: .strain, window: .quarter)
            TrendChart(points: Array(MockData.trend(.rhr, range: .week).points.prefix(1)), spec: .rhr, window: .week,
                       height: 80)
        }
    }

    private var zones: some View {
        VStack(spacing: 18) {
            ZoneBar(minutes: [31, 25, 16, 6, 2])
            ZoneBar(minutes: [3, 41, 18, 2, 0])
            ZoneBar(minutes: nil)
        }
    }

    @ViewBuilder
    private var sleep: some View {
        if let night = MockData.todayDetail.sleep {
            VStack(spacing: 16) {
                Card { MiniHypnogram(sleep: night, action: {}) }
                Card { Hypnogram(segments: night.segments) }
                StageBar(stages: night.displayStages)
                StageBar(stages: [])
                ForEach(night.displayStages) { StageRow(share: $0) }
            }
        }
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            MetricTile(title: "Sleep", value: "7h 48m", systemImage: "moon.fill", tint: Theme.metricSleep, action: {})
            MetricTile(title: "Recovery", value: "82%", systemImage: "heart", tint: Theme.band(forScore: 82),
                       caption: String(localized: "High"), action: {})
            MetricTile(title: "Strain", value: Fmt.placeholder, systemImage: "bolt.fill", tint: Theme.metricStrain)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rings: some View {
        HStack(spacing: 16) {
            ScoreRing(progress: 0.6, size: 36, lineWidth: 3, color: Theme.metricStrain,
                      accessibilityLabel: Text("Strain"), accessibilityValue: Text("12")) {
                Text(verbatim: "12").font(.ryftNumber(size: 11)).foregroundStyle(Theme.textPrimary)
            }
            ScoreRing(progress: nil, size: 36, lineWidth: 3,
                      accessibilityLabel: Text("Strain"), accessibilityValue: Text("No data")) {
                Text(Fmt.placeholder).font(.ryftNumber(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var cards: some View {
        VStack(spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Trends", trailing: "7 days", showsChevron: true)
                    StatRow(title: "Bedtime", value: "22:58")
                    StatRow(title: "Sleep debt", value: "1h 05m", valueColor: Theme.warning)
                    StatRow(title: "Timezone", value: "Europe/Berlin", detail: "Phone: Europe/Lisbon")
                }
            }
            ChartHeader(spec: .hrv, value: 58, delta: MetricDelta(current: 58, reference: 53), window: String(localized: "30 d"))
            ScrubReadout(value: "58 ms", date: "Mon, 13 Oct", delta: "+5 ms vs baseline")
            SetupCard {}
        }
    }

    private var messages: some View {
        VStack(spacing: 12) {
            InlineMessage(message: String(localized: "Nothing stands out today. Insights appear when your data shifts."),
                          systemImage: "checkmark.circle")
            InlineMessage(message: APIError.http(503, "").localizedDescription, details: "HTTP 503 · Request ID 01ab",
                          retry: {})
            OfflinePill()
            UpdatedLabel(date: .now.addingTimeInterval(-300))
            UpdatedLabel(date: nil, isLoading: true)
            HealthAccessHint()
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: "Continue") {}
            PrimaryButton(title: "Log out", style: .secondary) {}
            PrimaryButton(title: "Delete account", style: .destructive) {}
            PrimaryButton(title: "Sync now", style: .secondary, busy: true) {}
            Button("Start") {}.buttonStyle(TealButtonStyle())
            Button("New plan") {}.buttonStyle(TealButtonStyle(prominent: false))
            CatalogPicker()
        }
    }

    private var insights: some View {
        VStack(spacing: 12) {
            ForEach(MockData.insights) { InsightCard(insight: $0, onDismiss: {}) }
        }
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 16) {
            RyftHeader()
            BrandLockup()
            HStack(spacing: 16) {
                RyftMark().frame(width: 24, height: 24)
                RyftMark().frame(width: 48, height: 48)
            }
            .foregroundStyle(Theme.textPrimary)
            HealthIllustration()
        }
    }
}

private struct CatalogPicker: View {
    @State private var range: TrendRange = .month

    var body: some View {
        SegmentedPicker(selection: $range, options: TrendRange.allCases, title: InsightsViewModel.rangeTitle)
    }
}

#Preview("Component catalog") {
    NavigationStack { DebugComponentCatalog() }
        .previewEnvironment()
}

#Preview("Component catalog · light, AX3") {
    NavigationStack { DebugComponentCatalog() }
        .previewEnvironment(scheme: .light)
}
#endif
