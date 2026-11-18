#if DEBUG
import SwiftUI

/// The catalog's "Nocturne · structures" section (design.md §P5-11; T5.0-B): the grouped list with every row kind, the neutral
/// tile, the placeholder outline, the date strip, the segmented picker's looks, the titled header, the zones and idea glow tiles,
/// the zone block, the trend line and the delta colours. Its own file, so the other tickets' sections merge beside it.
/// Verbatim words: the screens own the strings.
struct NocturneStructuresCatalog: View {
    /// The catalog's parts, in order; the shots (`NocturneStructuresShotsTests`) draw each on its own.
    enum Part: String, CaseIterable {
        case groupedList = "grouped-list", tiles, dateStrip = "date-strip", picker = "segmented-picker", header = "screen-header"
        case zones, idea, trend = "trend-line", delta
    }

    var parts: [Part] = Part.allCases

    @State private var reminder = true
    @State private var units = "Metric"
    @State private var mode = "Day"
    @State private var range = "30 D"
    @State private var layout = "List"
    /// The insight title's 17 Light (§P5-5.1 row 3) grows with Dynamic Type like `.headline`.
    @ScaledMetric(relativeTo: .headline) private var ideaTitleSize: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(parts, id: \.self) { part($0) }
        }
        .toggleStyle(.ryft)
    }

    @ViewBuilder private func part(_ part: Part) -> some View {
        switch part {
        case .groupedList: groupedList
        case .tiles: tiles
        case .dateStrip: dateStrip
        case .picker: picker
        case .header: header
        case .zones: zones
        case .idea: ideas
        case .trend: trends
        case .delta: deltas
        }
    }

    private var tiles: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("neutral tile · value, unit, note · no note · no value")
            HStack(spacing: Theme.Metrics.itemSpacing) {
                NeutralTile(Text(verbatim: "Steps"), value: Text(verbatim: "8,412"), note: Text(verbatim: "Goal 10k"))
                NeutralTile(Text(verbatim: "Active energy"), value: Text(verbatim: "512"), unit: Text(verbatim: "kcal"))
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Metrics.itemSpacing) {
                NeutralTile(Text(verbatim: "Duration"), value: Text(verbatim: "42:10"))
                NeutralTile(Text(verbatim: "Avg heart rate"), value: Text(verbatim: "–"), unit: Text(verbatim: "bpm"))
            }
            .fixedSize(horizontal: false, vertical: true)
            caption("placeholder · rows 60 (radius 20) and 46, a tile")
            PlaceholderRow(height: 60, radius: 20)
            PlaceholderRow(height: Theme.Metrics.listRowHeight) {
                Text(verbatim: "Loading…").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
            }
            HStack(spacing: Theme.Metrics.itemSpacing) {
                NeutralTile(Text(verbatim: "Steps"), value: Text(verbatim: "–")).hidden().placeholderOutline()
                    .overlay(alignment: .topLeading) {
                        Text(verbatim: "Steps").font(.ryft(.label)).foregroundStyle(Theme.textTertiary).padding(NeutralTile.padding)
                    }
                Color.clear.frame(maxWidth: .infinity)
            }
        }
    }

    private var dateStrip: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("date strip · today selected · a past day, a pending day, unscored days")
            DateStrip(days: Self.week(selected: 0)) { _ in }
            DateStrip(days: Self.week(selected: 2, pending: 1, unscoredFrom: 5)) { _ in }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("segmented picker · capsule (PR 4, default) · ink fill · menu (AX1+)")
            SegmentedPicker(selection: $mode, options: ["Day", "Week", "Month", "Bedtime"]) { $0 }
            SegmentedPicker(selection: $mode, options: ["Day", "Week", "Month", "Bedtime"], look: .inkFill) { $0 }
            SegmentedMenu(selection: $mode, options: ["Day", "Week", "Month", "Bedtime"]) { $0 }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("header · title with a button, with a control (content width), alone")
            ScreenHeader(title: Text(verbatim: "Strain")) {
                CircleButton(systemImage: "plus", iconSize: 14, accessibilityLabel: Text(verbatim: "Add activity")) {}
            }
            ScreenHeader(title: Text(verbatim: "Insights"), trailingLayout: .wide) {
                SegmentedPicker(selection: $range, options: ["7 D", "30 D", "90 D"], look: .inkFill, width: .content,
                                spokenTitle: { "\($0.dropLast(2)) days" }) { $0 }
            }
            ScreenHeader(title: Text(verbatim: "Profile"))
        }
    }

    private var zones: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("glow · zones with the zone block · aligned at 318")
            VStack(alignment: .leading, spacing: 8) {
                GlowTile(Theme.metricStrain, kind: .zones) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "Heart-rate zones").ryftGlowLabelStyle()
                            Spacer(minLength: 0)
                            Text(verbatim: "82 min · TRIMP 112").font(.ryft(.caption))
                        }
                        ZoneBlock(zones: Self.zoneRows(), accessibilityLabel: Text(verbatim: "Heart-rate zones"))
                    }
                }
                Text(verbatim: "Zones are in % of heart-rate reserve.").font(.ryft(.axis)).foregroundStyle(Theme.textTertiary)
            }
            caption("zone block · stacked at 303 · no data")
            ZoneBlock(zones: Self.zoneRows(), accessibilityLabel: Text(verbatim: "Heart-rate zones")).frame(width: 303)
            ZoneBlock(zones: Self.zoneRows(minutes: [nil, nil, nil, nil, nil]), accessibilityLabel: Text(verbatim: "Heart-rate zones"))
        }
    }

    private var ideas: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("glow · idea · 120 · flat above 420 · zones under Reduce Transparency")
            GlowTile(Theme.recovery, kind: .idea) { idea }
            GlowTile(Theme.recovery, kind: .idea, minHeight: 440) { idea }
            GlowTile(Theme.metricStrain, kind: .zones, reduceTransparency: true) {
                Text(verbatim: "Heart-rate zones").ryftGlowLabelStyle()
            }
        }
    }

    private var trends: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("trend line · above · within, broken · below · lone point · pending")
            trendCard(TrendLine(values: Self.series(last: 74), band: 56...68, color: Theme.textPrimary, bandOpacity: 0.06,
                                accessibilityLabel: Text(verbatim: "Readiness over 30 days")))
            trendCard(TrendLine(values: Self.series(last: 63, gap: true), band: 56...68, color: Theme.recovery,
                                accessibilityLabel: Text(verbatim: "HRV over 30 days")))
            trendCard(TrendLine(values: Self.series(last: 50), band: 56...68, color: Theme.metricSleep,
                                accessibilityLabel: Text(verbatim: "Sleep over 30 days")))
            trendCard(TrendLine(values: [nil, nil, 9, nil, 11, 12, 10, nil, 14], color: Theme.metricStrain,
                                accessibilityLabel: Text(verbatim: "Strain"), spokenLatest: Text(verbatim: "14")))
            trendCard(TrendLine(values: [], color: Theme.recovery, isPending: true, accessibilityLabel: Text(verbatim: "HRV")))
        }
    }

    private var deltas: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("delta · good in the metric's colour · bad alert · flat")
            VStack(alignment: .leading, spacing: 8) {
                DeltaLabel(spec: .readiness, delta: MetricDelta(current: 84, reference: 73), reference: "vs 7 d")
                DeltaLabel(spec: .hrv, delta: MetricDelta(current: 58, reference: 52), reference: "vs 7 d")
                DeltaLabel(spec: .sleepMin, delta: MetricDelta(current: 468, reference: 451), reference: "vs 7 d")
                DeltaLabel(spec: .rhr, delta: MetricDelta(current: 47, reference: 50), reference: "vs 7 d")
                DeltaLabel(spec: .rhr, delta: MetricDelta(current: 53, reference: 50), reference: "vs 7 d")
                DeltaLabel(spec: .strain, delta: MetricDelta(current: 14, reference: 11), reference: "vs 7 d")
                DeltaLabel(spec: .hrv, delta: MetricDelta(current: 52.4, reference: 52), reference: "vs 7 d")
            }
        }
    }

    // MARK: grouped list

    private var groupedList: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
            caption("grouped list · every row kind")
            GroupedCard(Text(verbatim: "Account"), footer: Text(verbatim: "Signed in with Apple. Your data stays in the EU.")) {
                GroupedRow.value(Text(verbatim: "Email"), value: Text(verbatim: "alex@example.com"))
                GroupedRow.push(Text(verbatim: "Units"), value: Text(verbatim: units)) {}
                GroupedRow.linkOut(Text(verbatim: "Privacy policy"), url: Self.privacyURL)
                GroupedRow.action(Text(verbatim: "Sync now"), detail: Text(verbatim: "Last sync 2 min ago"),
                                  systemImage: "arrow.triangle.2.circlepath") {}
                GroupedRow.action(Text(verbatim: "Copy diagnostics"), busy: true) {}
            }
            GroupedCard(title: GroupTitle(Text(verbatim: "Units"), action: .init(Text(verbatim: "Edit")) {})) {
                ForEach(["Metric", "Imperial"], id: \.self) { option in
                    GroupedRow.select(Text(verbatim: option), isSelected: units == option) { units = option }
                }
            }
            GroupedCard(Text(verbatim: "Reminders")) {
                GroupedRow.toggle(Text(verbatim: "Bedtime reminder"), detail: Text(verbatim: "30 min before 22:30"), isOn: $reminder)
                GroupedRow.menu(Text(verbatim: "Session layout"), value: Text(verbatim: layout)) {
                    Button { layout = "List" } label: { Text(verbatim: "List") }
                    Button { layout = "Focused" } label: { Text(verbatim: "Focused") }
                }
                GroupedRow.push(Text(verbatim: "Disabled"), value: Text(verbatim: "Off")) {}
                    .disabled(true)
            }
            GroupedCard(Text(verbatim: "Train")) {
                GroupedRow.push(Text(verbatim: "Plan"), detail: Text(verbatim: "Upper / lower · week 3"), icon: "calendar",
                                route: "plan")
                GroupedRow.push(Text(verbatim: "History"), detail: Text(verbatim: "24 sessions"), icon: "clock.arrow.circlepath",
                                route: "history")
            }
            GroupedCard {
                GroupedRow.destructive(Text(verbatim: "Delete account")) {}
            }
        }
    }

    private var idea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Theme.signal).frame(width: 6, height: 6)
                Text(verbatim: "Insight").font(.ryft(.label))
            }
            Text(verbatim: "Three nights over 7 h in a row").font(.ryftNumber(size: ideaTitleSize, weight: .light))
            Text(verbatim: "Your recovery followed. Keep the bedtime.").font(.ryft(.label))
        }
    }

    private func trendCard(_ line: TrendLine) -> some View {
        line
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text).font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
    }

    // MARK: data

    private static let privacyURL = URL(string: "https://example.com/privacy") ?? URL(fileURLWithPath: "/")

    private static func week(selected: Int, pending: Int? = nil, unscoredFrom: Int = 99) -> [DateStrip.Day] {
        let today = Calendar.current.startOfDay(for: .now)
        let strains: [Double] = [12.4, 11, 12, 16, 6, 15, 15]
        return (0..<DateStrip.length).reversed().map { back in
            DateStrip.Day(date: DayFormat.shift(today, days: -back), strain: back >= unscoredFrom ? nil : strains[back],
                          isSelected: back == selected,
                          marker: back == pending ? .pending : (back >= unscoredFrom ? nil : .scored), isToday: back == 0)
        }
    }

    private static func zoneRows(minutes: [Double?] = [6, 14, 27, 24, 11]) -> [ZoneBlock.Zone] {
        let names = ["Z5 · Max", "Z4 · Threshold", "Z3 · Tempo", "Z2 · Aerobic", "Z1 · Easy"]
        return zip(names, minutes).map { name, m in
            ZoneBlock.Zone(label: Text(verbatim: name), minutes: m, value: Text(verbatim: m.map { "\(Int($0))m" } ?? "–"),
                           accessibilityLabel: Text(verbatim: "\(name), \(m.map { "\(Int($0)) minutes" } ?? "no data")"))
        }
    }

    private static func series(last: Double, gap: Bool = false) -> [Double?] {
        (0..<30).map { i -> Double? in
            if gap, (12...14).contains(i) { return nil }
            return i == 29 ? last : 62 + 6 * sin(Double(i) / 3)
        }
    }
}

#Preview("Nocturne · structures") {
    NavigationStack {
        ScrollView {
            NocturneStructuresCatalog()
                .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background)
    }
    .previewEnvironment()
}

#Preview("Nocturne · structures · AX3") {
    NavigationStack {
        ScrollView {
            NocturneStructuresCatalog()
                .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background)
    }
    .previewEnvironment()
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
