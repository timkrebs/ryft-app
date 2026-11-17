import SwiftUI
import Charts

/// Sleep's measurements in Day mode (Nocturne, docs/work/2026-11-16-nocturne/design.md §P4-2, §P4-11 test 1): the board's
/// gaps and sizes, bottom of one element to the top of the next.
enum SleepLayout {
    /// The header row (`ScreenHeaderSpec.height`).
    static let headerHeight: CGFloat = 40
    /// The mode picker under the header (L20, D4-3).
    static let pickerGap: CGFloat = 12
    /// The numeral under the picker (the board's: under the header).
    static let numeralGap: CGFloat = 22
    static let captionGap: CGFloat = 12
    static let rulerGap: CGFloat = 14
    static let hypnogramGap: CGFloat = 20
    /// The hypnogram tile, the `.hypnogram` glow kind's own: 168 high, radius 28. Its short variants (no timeline, no
    /// stages) are 96.
    static let hypnogramHeight: CGFloat = 168, hypnogramRadius: CGFloat = 28, hypnogramShortHeight: CGFloat = 96
    /// Inside it: the plot 10 under the header row, the totals 8 under the plot.
    static let plotGap: CGFloat = 10, totalsGap: CGFloat = 8
    /// The 2 × 2 tiles under the hypnogram, and between them.
    static let tilesGap: CGFloat = 12, tileGap: CGFloat = 12
    static let tileHeight: CGFloat = 88, tileRadius: CGFloat = Theme.Metrics.neutralTileRadius
    static let tilePadding = EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16)
    /// Inside a tile: the least space between the label and the value row, and between the value and a note at its right;
    /// a note under the value (AX, or a row too narrow) is 4 under it.
    static let tileInnerGap: CGFloat = 8, tileNoteGap: CGFloat = 4, tileStackGap: CGFloat = 4
    /// A note on the value's row may shrink to 90 % (12 → 10.8 pt) before it drops under the value: "3:20 h  Deep + REM"
    /// needs 140 pt and a 169 pt tile has 137 (the board's width, 390).
    static let tileNoteMinimumScale: CGFloat = 0.9
    /// The cards under the tiles (need, stages, details).
    static let cardGap: CGFloat = 12
    /// Week, Month and Bedtime keep their section spacing under the picker.
    static let rangeGap: CGFloat = Theme.Metrics.sectionSpacing
}

/// Sleep: Day (the night in Nocturne: numeral, ruler, hypnogram, tiles, then the need, the stages and the details), Week /
/// Month (nightly bars) and Bedtime, under one header and the mode picker.
struct SleepView: View {
    @Environment(AppState.self) private var state
    @Environment(ScreenModels.self) private var screens

    private var model: SleepViewModel { screens.sleep }

    var body: some View {
        NavigationStack {
            SleepPage(header: model.header, mode: Bindable(model).mode, modes: model.modes, step: step) {
                switch model.mode {
                case .day:
                    SleepDay(board: model.board, sleep: model.sleep, score: model.score, night: model.date,
                             numeralStyle: model.numeralStyle, showsHealthHint: model.hasNoHealthData,
                             retry: { await model.load() })
                case .week, .month: SleepRangeSection(range: model.range, isLoading: model.isLoading)
                case .plan: SleepPlannerSection(model: model.planner)
                }
            }
        }
        .task(id: TaskKey(mode: model.mode, refreshed: state.lastUpdated)) { await model.load() }
    }

    private struct TaskKey: Equatable {
        let mode: SleepMode
        let refreshed: Date?
    }

    /// A step re-reads the new night once it has loaded (§P4-8).
    private func step(_ days: Int) {
        Task {
            await model.step(by: days)
            AccessibilityNotification.Announcement(model.stepAnnouncement).post()
        }
    }
}

/// The page: the header, the mode picker 12 under it, then the mode's content (Day 22 under the picker, the others 24).
struct SleepPage<Content: View>: View {
    let header: SleepHeaderContent
    @Binding var mode: SleepMode
    let modes: [SleepMode]
    let step: (Int) -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScreenScaffold(showsHeader: false) {
            VStack(spacing: 0) {
                SleepHeader(content: header, step: step)
                SleepModePicker(selection: $mode, modes: modes)
                    .padding(.top, SleepLayout.pickerGap)
                content()
                    .padding(.top, mode == .day ? SleepLayout.numeralGap : SleepLayout.rangeGap)
            }
        }
    }
}

/// Sleep's header row (§P4-2 row 1): Previous night · "Sleep" and the night · Next night. Outside Day mode the buttons
/// keep their places, hidden and disabled. A disabled button stays labelled and says why in its hint.
struct SleepHeader: View {
    let content: SleepHeaderContent
    let step: (Int) -> Void

    var body: some View {
        ScreenHeader {
            nightButton("chevron.left", label: Text("Previous night"), enabled: content.canStepBack,
                        hint: Text("No older night to show", comment: "VoiceOver hint on Sleep's disabled Previous night button."),
                        identifier: "sleep.header.previous") { step(-1) }
        } center: {
            VStack(spacing: 2) {
                Text("Sleep")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 5) {
                    Text(content.subtitle)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textTertiary)
                    if let marker = content.marker { DayMarker(kind: marker) }
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Sleep"))
            .accessibilityValue(Text(content.spokenValue))
            .accessibilityAddTraits(.isHeader)
        } trailing: {
            nightButton("chevron.right", label: Text("Next night"), enabled: content.canStepForward,
                        hint: Text("No newer night to show", comment: "VoiceOver hint on Sleep's disabled Next night button."),
                        identifier: "sleep.header.next") { step(1) }
        }
    }

    private func nightButton(_ systemImage: String, label: Text, enabled: Bool, hint: Text, identifier: String,
                             action: @escaping () -> Void) -> some View {
        CircleButton(systemImage: systemImage, accessibilityLabel: label, action: action)
            .disabled(!content.showsNightButtons || !enabled)
            .opacity(content.showsNightButtons ? 1 : 0)
            .accessibilityHidden(!content.showsNightButtons)
            .accessibilityHint(enabled ? Text(verbatim: "") : hint)
            .accessibilityIdentifier(identifier)
    }
}

/// The mode picker (§P4-2 row 2): Day · Week · Month · Bedtime as segments; from AX1 one row, a menu with the current
/// mode, because the segments truncate their titles there (§P4-8). PR 5 restyles both.
struct SleepModePicker: View {
    @Binding var selection: SleepMode
    let modes: [SleepMode]

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            Menu {
                ForEach(modes) { mode in
                    Button {
                        selection = mode
                    } label: {
                        if mode == selection {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selection.title)
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minHitTarget)
                .background(Theme.surface, in: Capsule())
                .contentShape(Capsule())
            }
            .accessibilityIdentifier("sleep.mode")
        } else {
            SegmentedPicker(selection: $selection, options: modes, title: \.title)
        }
    }
}

/// Sleep → Day (§P4-2 rows 3–10, §P4-5): the numeral, its caption, the ruler, the hypnogram tile and the four tiles, then
/// the need, the stages and the details. Fed with values, so previews and tests show every state.
struct SleepDay: View {
    let board: SleepBoard
    let sleep: SleepDetail?
    let score: DailyScore?
    /// The night shown: a step cross-fades the numeral.
    let night: Date
    var numeralStyle: DotNumeral.Style = .dots
    /// "No Health data yet" under a day without a night, when nothing came from Apple Health at all.
    var showsHealthHint = false
    /// Previews and tests; `nil` follows the system.
    var reduceTransparency: Bool?
    var retry: (() async -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            numeral
            caption
                .padding(.top, SleepLayout.captionGap)
            RulerScale(range: SleepRuler.range, value: board.ruler.value, zone: board.ruler.zone, zoneStyle: .sleep,
                       tickCount: RulerScale.Ticks.sleep, labels: board.ruler.labels, size: .regular,
                       accessibilityLabel: Text("Sleep duration scale", comment: "VoiceOver label of Sleep's ruler, 0 to 10 hours."),
                       accessibilityValue: Text(board.ruler.spokenValue))
                .accessibilityIdentifier("sleep.ruler")
                .padding(.top, SleepLayout.rulerGap)
            hypnogram
                .padding(.top, SleepLayout.hypnogramGap)
            SleepTileGrid(tiles: board.tiles, isOutline: board.isOutline)
                .padding(.top, SleepLayout.tilesGap)
            if showsHealthHint, board.look == .noSleep {
                HealthAccessHint()
                    .padding(.top, SleepLayout.cardGap)
            }
            if let sleep, board.look == .night {
                SleepNightCards(sleep: sleep, score: score)
                    .padding(.top, SleepLayout.cardGap)
            }
        }
    }

    /// The time asleep as the hero numeral, unlit "0:00" without one; a new night or value cross-fades (250 ms, none
    /// under Reduce Motion).
    private var numeral: some View {
        let key = "\(DayFormat.string(from: night))|\(board.clock ?? "")"
        return ZStack {
            DotNumeral(board.clock, style: numeralStyle, glyphGap: DotNumeral.glyphGapDetail, placeholder: "0:00",
                       accessibilityLabel: Text(board.numeralLabel ?? ""))
                .accessibilityHidden(board.numeralLabel == nil)
                .accessibilityIdentifier("sleep.numeral")
                .id(key)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .animation(Theme.Motion.respecting(reduceMotion), value: key)
    }

    private var caption: some View {
        Text(board.caption)
            .font(.ryft(.label))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(board.spokenCaption ?? board.caption))
            .accessibilityHidden(board.spokenCaption == nil)
    }

    /// The glow tile with a night; an outline while there is none; the message and Try again after a failed load.
    @ViewBuilder private var hypnogram: some View {
        switch board.look {
        case .night:
            if let content = board.hypnogram {
                SleepHypnogramTile(content: content, reduceTransparency: reduceTransparency)
            }
        case .failed(let message):
            InlineMessage(message: message, retry: retry)
        case .loading, .noSleep, .pending:
            SleepHypnogramOutline()
        }
    }
}

/// Under the board (§P4-2 rows 8–10): the need card (→ the need sheet), the stages, and the details. The rows that repeat
/// a tile (Efficiency, Sleep debt) are gone (L22); the nap moved here from under the numeral.
struct SleepNightCards: View {
    let sleep: SleepDetail
    let score: DailyScore?
    @Environment(ScreenModels.self) private var screens
    @State private var showsNeed = false

    /// What Bedtime & wake planned for this night (by its wake day), if it planned it.
    private var planned: PlannedNight? {
        guard sleep.end != nil, let day = score?.day else { return nil }
        return screens.bedtime.planned(nightEnding: day)
    }

    private var summary: SleepNightSummary { SleepNightSummary(sleep: sleep, score: score) }

    var body: some View {
        VStack(spacing: SleepLayout.cardGap) {
            if let need = sleep.need {
                Button { showsNeed = true } label: {
                    Card { SleepNeedBar(need: need) }
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(Text("Shows how your sleep need adds up, and your baseline to change"))
                .accessibilityIdentifier("sleep.need")
            }
            stages
            details
        }
        .sheet(isPresented: $showsNeed) {
            SleepNeedSheet(need: sleep.need, total: summary.need, editor: screens.bodySettings)
        }
    }

    /// Minutes and shares per stage; none without stages (the hypnogram tile says why).
    @ViewBuilder private var stages: some View {
        let shares = sleep.displayStages
        if sleep.hasStages, shares.contains(where: { $0.min > 0 }) {
            Card {
                VStack(spacing: 14) {
                    ForEach(shares) { StageRow(share: $0) }
                }
            }
        }
    }

    private var details: some View {
        let summary = summary
        return Card {
            VStack(spacing: 14) {
                if let nap = summary.nap {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(nap, systemImage: "powersleep")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.surfaceRaised, in: Capsule())
                        Text("A nap lowers tonight's sleep need.")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    Divider().overlay(Theme.separator)
                }
                quality(summary)
                Divider().overlay(Theme.separator)
                StatRow(title: "Bedtime", value: summary.bedtime)
                StatRow(title: "Wake time", value: summary.wake)
                if let planned {
                    // How close the night came to Bedtime & wake's plan.
                    Text("Planned \(Fmt.time(planned.bed))–\(Fmt.time(planned.wake)) · actual \(summary.bedtime)–\(summary.wake)")
                        .font(.ryft(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(Text("Planned \(Fmt.time(planned.bed)) to \(Fmt.time(planned.wake)), actual \(summary.bedtime) to \(summary.wake)"))
                        .accessibilityIdentifier("sleep.plannedVsActual")
                }
                Divider().overlay(Theme.separator)
                StatRow(title: "Time in bed", value: summary.timeInBed)
                Divider().overlay(Theme.separator)
                if summary.needBreakdown == nil {
                    Button { showsNeed = true } label: {
                        HStack(spacing: 8) {
                            StatRow(title: "Sleep need", value: summary.need)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Shows your baseline sleep need to change"))
                }
                StatRow(title: "Actual", value: summary.actual, detail: summary.actualOfNeed)
            }
        }
    }

    /// "Quality 91 · Good", its bar and how it is made up.
    private func quality(_ summary: SleepNightSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                StatRow(title: "Quality", value: summary.quality)
                ProgressBar(value: summary.qualityFraction)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Sleep quality"))
            .accessibilityValue(Text(summary.quality))
            Text("Quality is 60 % performance, 20 % efficiency and 20 % restorative sleep.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The night's sleep need, term by term (`base + strain + debt − nap credit`), and the
/// baseline (the part that's yours to set) one tap away.
struct SleepNeedSheet: View {
    /// `nil` for nights scored before the breakdown existed.
    let need: SleepNeed?
    let total: String
    let editor: BodySettingsEditor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let need {
                        Card { SleepNeedBar(need: need) }
                    } else {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                StatRow(title: "Sleep need", value: total)
                                Text("This night was scored before RYFT broke the need down.")
                                    .font(.ryft(.caption))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    Text("Your baseline is yours to set. The top-ups follow yesterday's strain and your sleep debt; a nap lowers the next night's need.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Card {
                        NavigationLink {
                            BaselineSleepNeedForm(editor: editor)
                        } label: {
                            SettingRowLabel(title: "Change baseline", value: editor.sleepBaseText,
                                            detail: editor.sleepBaseSourceText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sleepNeed.changeBaseline")
                    }
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Text("Sleep need"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}

/// Thin rounded progress bar in the accent colour.
struct ProgressBar: View {
    let value: Double?
    var color: Color = Theme.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.14))
                Capsule().fill(color).frame(width: geo.size.width * shown)
            }
        }
        .frame(height: 6)
        .onAppear {
            let target = min(max(value ?? 0, 0), 1)
            if reduceMotion { shown = target } else { withAnimation(Theme.ringAnimation) { shown = target } }
        }
        .onChange(of: value) { _, v in shown = min(max(v ?? 0, 0), 1) }
        .accessibilityHidden(true)
    }
}

/// Week / Month: nightly stacked bars, averages, bedtime consistency.
struct SleepRangeSection: View {
    let range: SleepRange?
    let isLoading: Bool

    var body: some View {
        if let range {
            let summary = SleepRangeSummary(range: range)
            VStack(spacing: Theme.Metrics.sectionSpacing) {
                averages(summary)
                chart(summary)
                consistency(summary)
                nights(summary)
            }
        } else if isLoading {
            ProgressView().tint(Theme.accent).padding(.top, 40)
        } else {
            InlineMessage(message: String(localized: "No sleep data for this range yet."), systemImage: "moon.zzz")
        }
    }

    private func averages(_ summary: SleepRangeSummary) -> some View {
        HStack(spacing: 10) {
            average(title: "Avg sleep", value: summary.averageSleep)
            average(title: "Avg quality", value: summary.averageQuality)
            average(title: "Consistency", value: summary.averageConsistency)
        }
    }

    private func average(title: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 8) {
            Text(title).ryftLabelStyle().lineLimit(1).minimumScaleFactor(0.8)
            Text(value)
                .font(.ryft(.metric))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func chart(_ summary: SleepRangeSummary) -> some View {
        let order = SleepRangeSummary.stageOrder
        let names = order.map(\.title) + (summary.hasUnstaged ? [SleepRangeSummary.asleep] : [])
        let colors = order.map(Theme.color(for:)) + (summary.hasUnstaged ? [Theme.accentSecondary] : [])
        let window = summary.window
        let end = summary.end
        let scale = ChartStyle.niceScale([summary.tallestNight, summary.averageHours ?? 0, 0], steps: ChartStyle.hourSteps)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                ChartHeader(spec: .sleepMin, value: summary.totals.last?.value, delta: .vsSevenDayMean(summary.totals),
                            window: window.title)
                Chart {
                    ForEach(summary.bars) { b in
                        BarMark(x: .value("Night", b.date, unit: .day), y: .value("Hours", b.hours))
                            .foregroundStyle(by: .value("Stage", b.stage))
                            .cornerRadius(1)
                    }
                    if let avg = summary.averageHours {
                        BaselineRule(value: avg, label: String(localized: "avg \(summary.averageSleep)"))
                    }
                }
                .chartForegroundStyleScale(domain: names, range: colors)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                // Bars fill whole day bins: the domain runs to the end of the last day.
                .chartXScale(domain: window.start(endingAt: end)...DayFormat.shift(Calendar.current.startOfDay(for: end), days: 1))
                .chartYScale(domain: scale.domain)
                .chartXAxis {
                    ChartStyle.xAxis(window.ticks(endingAt: end), format: window.format, centered: window == .week)
                }
                .chartYAxis { ChartStyle.yAxis(scale.ticks, unit: "h") { $0.formatted(.number.precision(.fractionLength(0...1))) } }
                .frame(height: 200)
                .chartAppear()
                .accessibilityLabel(Text("Sleep per night"))
                .accessibilityValue(Text("Average \(summary.averageSleep)"))
            }
        }
    }

    private func consistency(_ summary: SleepRangeSummary) -> some View {
        let color: Color
        switch summary.regularity {
        case .steady: color = Theme.accent
        case .fair: color = Theme.accentSecondary
        case .irregular: color = Theme.warning
        case .unknown: color = Theme.textTertiary
        }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(color)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bedtime and wake time")
                            .font(.ryft(.headline))
                            .foregroundStyle(Theme.textPrimary)
                        Text(summary.consistencyHint)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                if !summary.bedtimes.isEmpty {
                    BedtimeStrip(bedtimes: summary.bedtimes, rowHeight: summary.bedtimes.count > 10 ? 7 : 14)
                }
            }
        }
    }

    /// Each night with its consistency and nap.
    private func nights(_ summary: SleepRangeSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "\(summary.nights) nights")
                ForEach(summary.nightRows) { row in
                    HStack(spacing: 10) {
                        Text(row.title)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if let nap = row.nap {
                            Label(nap, systemImage: "powersleep")
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(row.total)
                            .font(.ryft(.callout).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        Label(row.consistency ?? Fmt.placeholder, systemImage: "metronome")
                            .font(.ryft(.caption).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(row.title))
                    .accessibilityValue(Text(String(localized: "\(row.total) asleep, quality \(row.quality)")
                                             + (row.consistency.map { ", " + String(localized: "consistency \($0)") } ?? "")
                                             + (row.nap.map { ", " + String(localized: "nap \($0)") } ?? "")))
                }
            }
        }
    }
}
