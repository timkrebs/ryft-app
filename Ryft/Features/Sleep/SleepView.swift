import SwiftUI

/// Sleep's measurements in Day mode (Nocturne, docs/work/2026-11-16-nocturne/design.md §P4-2, §P4-11 test 1): the board's
/// gaps and sizes, bottom of one element to the top of the next.
enum SleepLayout {
    /// The header row (`ScreenHeaderSpec.height`).
    static let headerHeight: CGFloat = 40
    /// The mode picker under the header (L20, D4-3), 40 high (`SegmentedPickerSpec.inkFill`, §P5-7.1; PR 4's was 52, so
    /// Day's content sits 12 higher than on the board).
    static let pickerGap: CGFloat = 12, pickerHeight: CGFloat = 40
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
}

/// Sleep: Day (the night in Nocturne: numeral, ruler, hypnogram, tiles, then the need, the stages and the details), Week /
/// Month (the average, bed and wake times, the nightly stages and the nights) and Bedtime (tonight's bedtime for your goal),
/// under one header and the mode picker.
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
                             failure: model.failure, retry: { await model.load() }, signIn: { await model.signIn() })
                case .week, .month:
                    SleepRangeSection(board: model.rangeBoard, numeralStyle: model.numeralStyle,
                                      showsHealthHint: model.hasNoHealthData, notice: notice,
                                      retry: { await model.load() }, signIn: { await model.signIn() })
                case .plan:
                    SleepBedtimeSection(board: model.bedtimeBoard(screens.bedtime),
                                        wake: Binding(get: { model.planner.wake }, set: { model.planner.setWake($0) }),
                                        numeralStyle: model.numeralStyle, notice: notice,
                                        retry: { await model.planner.load() }, signIn: { await model.signIn() })
                        // Bedtime & wake's own plan (its reminders and alarm) when there is a schedule and no plan yet.
                        .task {
                            let bedtime = screens.bedtime
                            if bedtime.schedule != nil, bedtime.plan == nil { await bedtime.refresh() }
                        }
                }
            }
        }
        // Bedtime follows Bedtime & wake: a new schedule loads again (tonight's bedtime, until the picker moves).
        .task(id: TaskKey(mode: model.mode, refreshed: state.lastUpdated,
                          schedule: model.mode == .plan ? screens.bedtime.schedule : nil)) {
            await model.load(bedtime: screens.bedtime)
        }
    }

    /// Today's calm card under the picker outside Day, while reads fail or the data is old.
    private var notice: SleepModeNotice {
        SleepModeNotice(issue: model.refreshIssue, isDemo: model.isDemo, retry: { await model.retryRefresh() },
                        signIn: { await model.signIn() })
    }

    private struct TaskKey: Equatable {
        let mode: SleepMode
        let refreshed: Date?
        let schedule: SleepSchedule?
    }

    /// A step re-reads the new night once it has loaded (§P4-8).
    private func step(_ days: Int) {
        Task {
            await model.step(by: days)
            AccessibilityNotification.Announcement(model.stepAnnouncement).post()
        }
    }
}

/// The page: the header, the mode picker 12 under it, then the mode's content: Day's numeral 22 under the picker; Week, Month
/// and Bedtime place their notice and numeral themselves (`SleepModesLayout`).
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
                    .padding(.top, mode == .day ? SleepLayout.numeralGap : 0)
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

/// The mode picker (§P4-2 row 2, §P5-7.1): Day · Week · Month · Bedtime as `SegmentedPicker`'s ink fill (40 high, the selected
/// segment `textPrimary` with `background` text); from AX1 one row, `SegmentedMenu` with the current mode, because the
/// segments truncate their titles there (§P4-8).
struct SleepModePicker: View {
    @Binding var selection: SleepMode
    let modes: [SleepMode]

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            SegmentedMenu(selection: $selection, options: modes, label: Self.menuLabel, title: \.title)
                .accessibilityIdentifier("sleep.mode")
        } else {
            SegmentedPicker(selection: $selection, options: modes, look: .inkFill, title: \.title)
        }
    }

    /// The menu's VoiceOver label, before the current mode: "Range, Week".
    static var menuLabel: Text {
        // Its own key: "Range" is the training import's range picker.
        Text(String(localized: "sleep.mode.menu", defaultValue: "Range",
                    comment: "VoiceOver: the name of Sleep's mode menu (the largest text sizes), read before the current mode: \"Range, Week\"."))
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
    /// A failed load's symbol, Details and button (the board has its sentence).
    var failure: SleepLoadFailure?
    var retry: (() async -> Void)?
    /// A signed-out failure's button instead of Try again.
    var signIn: (() async -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            numeral
            caption
                .padding(.top, SleepLayout.captionGap)
            RulerScale(range: SleepRuler.range, value: board.ruler.value, zone: board.ruler.zone, zoneStyle: .sleep,
                       tickCount: RulerScale.Ticks.sleep, labels: board.ruler.labels, size: .regular,
                       accessibilityLabel: Text("Sleep duration scale", comment: "VoiceOver label of Sleep's ruler, 0 to 10 hours."),
                       accessibilityValue: Text(board.ruler.spokenValue), followingGap: SleepLayout.hypnogramGap)
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
        // An empty caption (a failed load) keeps its line, so nothing below moves.
        Text(verbatim: board.caption.isEmpty ? " " : board.caption)
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
            // The button as on Today's card (`RefreshIssue.Reason.Action`): Try again, Sign in, or none.
            let action = failure?.action ?? .retry
            InlineMessage(message: message, systemImage: failure?.systemImage ?? "wifi.exclamationmark",
                          retryTitle: action.title, details: failure?.details,
                          retry: action.button(retry: retry, signIn: signIn), identifier: "sleep.failure")
        case .loading, .noSleep, .pending, .awaitingNight:
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
            if let need = sleep.needBreakdown(score: score) {
                SleepNeedCard(need: need) { showsNeed = true }
            }
            stages
            details
        }
        .sheet(isPresented: $showsNeed) {
            SleepNeedSheet(need: sleep.needBreakdown(score: score), total: summary.need, needMinutes: score?.sleepNeedMin,
                           night: screens.sleep.subtitle, editor: screens.bodySettings).presentedRoot()
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
            Text("Quality is 60\u{00A0}% performance, 20\u{00A0}% efficiency and 20\u{00A0}% restorative sleep.")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Thin rounded progress bar, in the sleep colour by default (§P5-7.4).
struct ProgressBar: View {
    let value: Double?
    var color: Color = Theme.metricSleep

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
