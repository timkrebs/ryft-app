#if DEBUG
import SwiftUI

/// Profile → Developer → Component catalog (Debug builds only): every `Design/`
/// component in its configurations and sizes, at Dynamic Type XS, L or AX3 (the
/// app is dark only). The regression surface for "reusable, configurable"
/// components: change one, scroll here, see every use.
struct DebugComponentCatalog: View {
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
                    section("Nocturne · gauge") { OrbitGaugePreviewBoard() }
                    section("Nocturne · launch") { LaunchCatalogEntry() }
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
                    section("Nocturne · numeral") { nocturneNumerals }
                    section("Nocturne · ruler") { nocturneRulers }
                    section("Nocturne · glow tile") { nocturneGlowTiles }
                    section("Nocturne · rows") { nocturneRows }
                    section("Nocturne · buttons") { nocturneButtons }
                    section("Nocturne · glow kinds") { nocturneGlowKinds }
                    section("Nocturne · sparkline") { nocturneSparklines }
                    section("Nocturne · hypnogram") { nocturneHypnograms }
                    section("Nocturne · header") { nocturneHeaders }
                    section("Nocturne · controls") { NocturneControlsCatalog() }
                    section("Nocturne · structures") { NocturneStructuresCatalog() }
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background)
            .dynamicTypeSize(typeSize.size)
        }
        .navigationTitle("Component catalog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var controls: some View {
        Picker("Text size", selection: $typeSize) {
            ForEach(CatalogTypeSize.allCases) { Text(verbatim: $0.rawValue).tag($0) }
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
            // The hypnogram is the glow tile further down (`CatalogHypnogramTile`).
            Card {
                VStack(spacing: 14) {
                    ForEach(night.displayStages) { StageRow(share: $0) }
                }
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

    // MARK: Nocturne (design.md §P2-6). From AX1 the numeral falls back to Light digits and the tick rows stack.

    /// Both glyph gaps, every glyph, the Light style; pending under each value (its template keeps the width), and in Light.
    private var nocturneNumerals: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 24) {
                DotNumeral("84", accessibilityLabel: Text("Readiness 84 of 100"))
                DotNumeral("7:48", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("7 hours 48 minutes asleep"))
            }
            HStack(alignment: .top, spacing: 24) {
                DotNumeral(nil, accessibilityLabel: Text("Readiness, no value yet"))
                DotNumeral(nil, glyphGap: DotNumeral.glyphGapDetail, placeholder: "0:00",
                           accessibilityLabel: Text("Time asleep, no value yet"))
            }
            DotNumeral("01234", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("0 1 2 3 4"))
            DotNumeral("56789", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("5 6 7 8 9"))
            HStack(alignment: .top, spacing: 24) {
                DotNumeral("12.4", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("Strain 12.4 of 21"))
                DotNumeral("12,4", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("Strain 12.4 of 21"))
            }
            HStack(alignment: .top, spacing: 24) {
                DotNumeral("84", style: .light, accessibilityLabel: Text("Readiness 84 of 100"))
                DotNumeral(nil, style: .light, accessibilityLabel: Text("Readiness, no value yet"))
                DotNumeral(nil, style: .light, placeholder: "0:00", accessibilityLabel: Text("Time asleep, no value yet"))
            }
        }
    }

    /// The boards' rulers (Today, Sleep, Strain, Today's compact strain tile), no value, a value past the end.
    private var nocturneRulers: some View {
        VStack(alignment: .leading, spacing: 22) {
            RulerScale(range: 0...100, value: 84, zone: 67...100, tickCount: RulerScale.Ticks.today,
                       labels: ["0", "low", "moderate", "high", "100"], accessibilityLabel: Text("Readiness scale"),
                       accessibilityValue: Text("84, high, on a scale from 0 to 100"))
            RulerScale(range: 0...10, value: 7.8, zone: 7.5...8.3, zoneStyle: .sleep,
                       tickCount: RulerScale.Ticks.sleep, labels: ["0 h", "need 8:18", "10 h"],
                       accessibilityLabel: Text("Sleep scale"),
                       accessibilityValue: Text("7 hours 48 minutes, need 8 hours 18 minutes, on a scale from 0 to 10 hours"))
            RulerScale(range: 0...21, value: 12.4, zone: 10...14, zoneStyle: .strain,
                       tickCount: RulerScale.Ticks.strain, labels: ["0", "target 10–14", "21"],
                       accessibilityLabel: Text("Strain scale"),
                       accessibilityValue: Text("12.4, in target 10 to 14, on a scale from 0 to 21"))
            HStack(alignment: .top, spacing: Theme.Metrics.itemSpacing) {
                GlowTile(Theme.recovery, kind: .twoUp) {
                    catalogTileText("Recovery", "82")
                }
                GlowTile(Theme.metricStrain, kind: .twoUp) {
                    VStack(alignment: .leading, spacing: 6) {
                        catalogTileText("Strain", "12.4")
                        Spacer(minLength: 0)
                        RulerScale(range: 0...21, value: 12.4, zone: 10...14, tickCount: RulerScale.Ticks.strainCompact,
                                   labels: ["0", "21"], size: .compact, accessibilityLabel: Text("Strain scale"),
                                   accessibilityValue: Text("12.4, in target 10 to 14, on a scale from 0 to 21"))
                    }
                }
            }
            RulerScale(range: 0...100, value: nil, zone: 67...100, tickCount: RulerScale.Ticks.today,
                       labels: ["0", "low", "moderate", "high", "100"], accessibilityLabel: Text("Readiness scale"),
                       accessibilityValue: Text("No value yet, on a scale from 0 to 100"))
            RulerScale(range: 0...21, value: 23.5, zone: 10...14, zoneStyle: .strain,
                       tickCount: RulerScale.Ticks.strain, labels: ["0", "target 10–14", "21"],
                       accessibilityLabel: Text("Strain scale"),
                       accessibilityValue: Text("23.5, above target, on a scale from 0 to 21"))
        }
    }

    /// The three legend colours as 2-up tiles and as panels, and one tile forced flat (Reduce Transparency).
    private var nocturneGlowTiles: some View {
        VStack(spacing: Theme.Metrics.itemSpacing) {
            HStack(spacing: Theme.Metrics.itemSpacing) {
                GlowTile(Theme.recovery, kind: .twoUp) { catalogTileText("Recovery", "82") }
                GlowTile(Theme.metricSleep, kind: .twoUp) { catalogTileText("Sleep", "7:48") }
            }
            HStack(spacing: Theme.Metrics.itemSpacing) {
                GlowTile(Theme.metricStrain, kind: .twoUp) { catalogTileText("Strain", "12.4") }
                GlowTile(Theme.recovery, kind: .twoUp, reduceTransparency: true) {
                    catalogTileText("Flat", "82")
                }
            }
            GlowTile(Theme.recovery, kind: .panel) {
                catalogTileText("Recovery", "82")
            }
            GlowTile(Theme.metricSleep, kind: .panel) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Time asleep").ryftGlowLabelStyle()
                    DotNumeral("7:48", glyphGap: DotNumeral.glyphGapDetail,
                               accessibilityLabel: Text("7 hours 48 minutes asleep"))
                }
            }
            GlowTile(Theme.metricStrain, kind: .panel) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Strain").ryftGlowLabelStyle()
                    DotNumeral("12.4", glyphGap: DotNumeral.glyphGapDetail, accessibilityLabel: Text("Strain 12.4 of 21"))
                }
            }
        }
    }

    /// Dot rows (all full, mixed with today, all missed, today only) and the five zones.
    private var nocturneRows: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                DotRow(Array(repeating: .full, count: 7), accessibilityLabel: Text("Slept enough on 7 of the last 7 nights"))
                DotRow([.full, .missed, .full, .full, .missed, .full, .today],
                       accessibilityLabel: Text("Slept enough on 4 of the last 6 nights; tonight is marked"))
                DotRow(Array(repeating: .missed, count: 7), accessibilityLabel: Text("Slept enough on none of the last 7 nights"))
                DotRow([.today], accessibilityLabel: Text("Tonight is marked"))
                DotRow([.full, .missed, .full, .noData, .missed, .full, .today],
                       accessibilityLabel: Text(verbatim: "Slept enough on 4 of the last 7 nights; 1 night has no data"))
            }
            VStack(alignment: .leading, spacing: TickRow.rowSpacing) {
                ForEach(Array(Self.catalogZoneMinutes.enumerated()), id: \.offset) { index, minutes in
                    let zone = "Zone \(index + 1)"
                    TickRow(label: Text(verbatim: zone), minutes: minutes, scaleMax: 60,
                            value: Text(verbatim: minutes.map { "\(Int($0))m" } ?? "–"),
                            accessibilityLabel: Text(verbatim: minutes.map { "\(zone), \(Int($0)) minutes" } ?? "\(zone), no data"))
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// Circle and pill buttons, enabled and disabled.
    private var nocturneButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CircleButton(systemImage: "chevron.left", accessibilityLabel: Text("Previous night")) {}
                CircleButton(systemImage: "chevron.right", accessibilityLabel: Text("Next night")) {}
                    .disabled(true)
                CircleButton(systemImage: "calendar", accessibilityLabel: Text("Choose a day")) {}
                CircleButton(systemImage: "plus", accessibilityLabel: Text("Add an activity")) {}
            }
            PillButton(Text("Continue")) {}
            PillButton(Text("Continue")) {}
                .disabled(true)
            PillButton(Text("Not now"), style: .secondary) {}
            PillButton(Text("Not now"), style: .secondary) {}
                .disabled(true)
        }
    }

    /// The four kinds at the board's sizes (design.md §P4-3), the 2-up at 350 wide (the panel's ellipse takes over), and
    /// each kind flat (Reduce Transparency).
    private var nocturneGlowKinds: some View {
        VStack(spacing: Theme.Metrics.itemSpacing) {
            ForEach([false, true], id: \.self) { flat in
                HStack(spacing: Theme.Metrics.itemSpacing) {
                    GlowTile(Theme.recovery, kind: .twoUp, reduceTransparency: flat) { catalogTileText("Recovery", "82") }
                    GlowTile(Theme.metricSleep, kind: .twoUp, reduceTransparency: flat) { catalogTileText("Sleep", "7:48") }
                }
                GlowTile(Theme.metricStrain, kind: .strain, reduceTransparency: flat) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: "Strain").ryftGlowLabelStyle()
                            Spacer(minLength: 0)
                            Text(verbatim: "12.4").font(.ryftNumber(size: 30, weight: .light))
                            Text(verbatim: "of 21 · moderate").ryftGlowLabelStyle()
                        }
                        RulerScale(range: 0...21, value: 12.4, zone: 10...14, tickCount: RulerScale.Ticks.strainCompact,
                                   size: .compact, accessibilityLabel: Text(verbatim: "Strain scale"),
                                   accessibilityValue: Text(verbatim: "12.4, moderate, on a scale from 0 to 21"))
                            .padding(.top, 8)
                    }
                }
                CatalogHypnogramTile(variant: .full, flat: flat)
                GlowTile(Theme.recovery, kind: .panel, reduceTransparency: flat) { catalogTileText("An idea", "64") }
            }
            GlowTile(Theme.recovery, kind: .twoUp) { catalogTileText("Recovery · 2-up at 350, panel ellipse", "82") }
        }
    }

    /// The HRV week (the board's: lowest 51, highest 66), a missing day, no value on the last day, one value (pending).
    private var nocturneSparklines: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(Self.catalogSparklines.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 16) {
                    Sparkline(values: entry.values)
                    Text(verbatim: entry.title).font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private static let catalogSparklines: [(title: String, values: [Double?])] = [
        ("week", [58, 51, 60, 55, 62, 57, 66]), ("a missing day", [58, 51, nil, 55, 62, 57, 66]),
        ("lone days", [58, nil, 60, nil, 62, 57, 66]), ("no value today", [58, 51, 60, 55, 62, 57, nil]),
        ("flat", [60, 60, 60, 60, 60, 60, 60]), ("pending", [nil, nil, nil, nil, nil, nil, 66]),
    ]

    /// The board's night, a night without its timeline (header and totals), a night without stages.
    private var nocturneHypnograms: some View {
        VStack(spacing: Theme.Metrics.itemSpacing) {
            CatalogHypnogramTile(variant: .full)
            CatalogHypnogramTile(variant: .noTimeline)
            CatalogHypnogramTile(variant: .noStages)
        }
    }

    /// Today's (lock-up and calendar; without My Day), Sleep's three slots, the next night disabled.
    private var nocturneHeaders: some View {
        VStack(spacing: 18) {
            ScreenHeader {
                CircleButton(systemImage: "calendar", iconSize: 16, accessibilityLabel: Text(verbatim: "Calendar")) {}
            }
            ScreenHeader { EmptyView() }
            ScreenHeader {
                CircleButton(systemImage: "chevron.left", accessibilityLabel: Text(verbatim: "Previous night")) {}
            } center: {
                VStack(spacing: 2) {
                    Text(verbatim: "Sleep").font(.ryft(.callout)).foregroundStyle(Theme.textPrimary)
                    Text(verbatim: "Last night · Sun, Nov 15").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                }
                .multilineTextAlignment(.center)
            } trailing: {
                CircleButton(systemImage: "chevron.right", accessibilityLabel: Text(verbatim: "Next night")) {}
                    .disabled(true)
            }
        }
    }

    /// Minutes per heart-rate zone; the last has no data.
    private static let catalogZoneMinutes: [Double?] = [12, 31, 24, 7, nil]

    private func catalogTileText(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: label).ryftGlowLabelStyle()
            Text(verbatim: value).font(.ryft(.metric))
        }
    }
}

/// Sleep's hypnogram glow tile as the catalog composes it from `HypnogramPlot` and the board's night (`MockData`): the
/// screen's own tile is `SleepHypnogramTile` (T4.3), with its strings and VoiceOver.
private struct CatalogHypnogramTile: View {
    enum Variant { case full, noTimeline, noStages }
    let variant: Variant
    var flat = false

    var body: some View {
        let sleep = MockData.todayDetail.sleep
        GlowTile(Theme.metricSleep, kind: .hypnogram, minHeight: variant == .full ? nil : 96, reduceTransparency: flat) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "Hypnogram").ryftGlowLabelStyle()
                    Spacer(minLength: 8)
                    Text(verbatim: "\(Fmt.time(sleep?.start)) – \(Fmt.time(sleep?.end))").ryftGlowLabelStyle(.caption)
                }
                switch variant {
                case .full:
                    if let sleep, let start = sleep.start, let end = sleep.end {
                        HypnogramPlot(segments: sleep.segments, start: start, end: end,
                                      stageNames: ["Awake", "REM", "Light", "Deep"])
                            .padding(.top, 10)
                    }
                    totals(sleep).padding(.top, 8)
                case .noTimeline:
                    Text(verbatim: "The timeline isn't available for this night.").ryftGlowLabelStyle(.caption).padding(.top, 10)
                    Spacer(minLength: 8)
                    totals(sleep)
                case .noStages:
                    Text(verbatim: "Your watch didn't record sleep stages for this night — only the total.")
                        .ryftGlowLabelStyle(.caption)
                        .padding(.top, 10)
                }
            }
        }
    }

    private func totals(_ sleep: SleepDetail?) -> some View {
        let minutes = Dictionary((sleep?.stages ?? []).map { ($0.stage, $0.min) }, uniquingKeysWith: { a, _ in a })
        return HStack(spacing: 0) {
            ForEach(Array([SleepStageKind.deep, .rem, .light, .awake].enumerated()), id: \.offset) { index, stage in
                if index > 0 { Spacer(minLength: 6) }
                Text(verbatim: "\(stage.title) \(Fmt.clock(minutes: minutes[stage]))")
            }
        }
        .ryftGlowLabelStyle(.caption)
    }
}

/// The launch at 60 % (design.md §P3-7): scrub t, jump to a keyframe, the reduced variant, and Play, which replays the
/// sequence from a local `LaunchSequence` (not the process's model) with its hand-off; a tap on the stage skips it.
private struct LaunchCatalogEntry: View {
    @Environment(\.appEnvironment) private var env
    @Environment(\.self) private var environment
    @State private var t = 1.0
    @State private var reduced = false
    /// A replay in progress.
    @State private var run: LaunchSequence?

    private static let scale: CGFloat = 0.6
    private static let keyframes: [Double] = [0, 0.26, 0.5, 0.76, 1]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            stage
                .frame(width: 390, height: 844)
                .scaleEffect(Self.scale, anchor: .topLeading)
                .frame(width: 390 * Self.scale, height: 844 * Self.scale, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { run?.send(.tap, at: env.clock.now()) }
            Slider(value: $t, in: 0...1) { Text(verbatim: "t") }
                .disabled(reduced || run != nil)
            Text(verbatim: String(format: "t = %.3f · %.2f s", reduced ? 1 : t, (reduced ? 1 : t) * LaunchFrame.duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 8) {
                ForEach(Self.keyframes, id: \.self) { value in
                    Button { t = value } label: { Text(verbatim: String(format: "%.2f", value)) }
                        .buttonStyle(.bordered)
                        .disabled(reduced || run != nil)
                }
            }
            Toggle(isOn: $reduced) { Text(verbatim: "Reduce Motion (the t = 1 frame, faded)") }
            Button {
                let now = env.clock.now()
                var sequence = LaunchSequence(decision: .play(reduced ? .reduced : .full), createdAt: now)
                sequence.send(.scene(.active), at: now)
                t = 1
                run = sequence
            } label: { Text(verbatim: run == nil ? "Play" : "Playing… tap the stage to skip") }
                .buttonStyle(.borderedProminent)
                .disabled(run != nil)
        }
        // The replay's end: back to the scrubbed (last) frame.
        .task(id: run?.doneAt) {
            guard let done = run?.doneAt else { return }
            let wait = done.timeIntervalSince(env.clock.now())
            if wait > 0 { try? await env.clock.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            run = nil
        }
    }

    @ViewBuilder
    private var stage: some View {
        let palette = LaunchFrame.Palette.resolved(in: environment)
        if let playing = run {
            TimelineView(.animation) { context in
                ZStack {
                    Theme.background
                    LaunchStage(frame: LaunchFrame(t: playing.frameProgress(at: context.date), palette: palette))
                        .opacity(playing.contentOpacity(at: context.date))
                }
                .opacity(1 - playing.handOff(at: context.date))
            }
            // As `LaunchOverlay`: t = 0 is the first frame on screen.
            .onAppear { run?.send(.firstFrame, at: env.clock.now()) }
        } else {
            ZStack {
                Theme.background
                LaunchStage(frame: LaunchFrame(t: reduced ? 1 : t, palette: palette))
            }
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
#endif
