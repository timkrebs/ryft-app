// Sleep → Bedtime in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-7.3, the draft `draft-sleep-bedtime`): tonight's
// bedtime for your goal as the hero numeral, the planned sleep on Day's ruler, the three goals in the go-to-bed glow tile, Need
// and Time in bed, then the wake time, why the need is what it is and Bedtime & wake. The numbers come from `GET /v1/sleep/plan`
// (`SleepPlannerViewModel`), the goal and the alarm from `BedtimePlanner`; `SleepBedtimeBoard` decides every value and look.
import SwiftUI

// MARK: - the board (pure)

/// Bedtime as values: the numeral and its meridiem, the caption, the ruler, the goals, the tiles, the footer; the look for no
/// schedule, planning, a failed plan and offline. Pure: tests build it without a view.
struct SleepBedtimeBoard: Equatable {
    enum Look: Equatable {
        /// A plan to show.
        case planned
        /// No Bedtime & wake yet: the invitation and the button to the editor; no ruler, no tile.
        case noSchedule
        /// No plan yet and the request in flight: the unlit numeral, the ruler without its needle, outlines.
        case planning
        /// The plan failed with nothing cached: the message with Try again in the tile's place.
        case failed
        /// Offline with nothing cached: the message, no button (it appears once online).
        case offline
    }

    /// One goal in the go-to-bed tile: the marker (filled for your goal, a ring for the others), the bedtime, the share and
    /// the sleep it gives.
    struct Row: Equatable, Identifiable {
        let goal: SleepSchedule.Goal
        /// "10:06 PM".
        let time: String
        /// "100 % of your need".
        let share: String
        /// "8h 01m asleep".
        let asleep: String
        let isGoal: Bool
        /// "10:06 PM, 100 percent of your need, 8 hours 1 minute asleep, your goal".
        let spoken: String
        var id: Int { goal.rawValue }
    }

    let look: Look
    /// "10:06", "22:06"; `nil` draws the unlit "00:00".
    let digits: String?
    /// "PM" after the numeral; `nil` in 24-hour locales.
    let meridiem: String?
    /// "Go to bed at 10:06 PM", "Loading…"; `nil` hides the numeral from VoiceOver (the sentence under it says it).
    let numeralLabel: String?
    /// "In bed by · 100 % of your need", "Loading…"; empty keeps the line.
    let caption: String
    /// The planned sleep against tonight's need; `nil` without a schedule. Without a plan: the ticks, no needle.
    let ruler: SleepRuler?
    /// "wake 7:00 AM" in the tile's head.
    let wake: String
    /// Peak, Perform, Get by (100 / 85 / 70 %), earliest first.
    let rows: [Row]
    /// Need and Time in bed.
    let tiles: [SleepTile]
    /// The tile as one VoiceOver value: the wake time and the three goals.
    let spokenTile: String
    /// The plan's need, term by term ("Why this need"); `nil` without a plan.
    let plan: SleepPlan?
    /// "As of 10:44 AM": the plan is a cached one.
    let asOf: String?
    /// The failed plan's sentence.
    let message: String?
    /// The wake alarm couldn't be set: under the settings card.
    let alarmProblem: String?
    /// Bedtime & wake's row value ("Weekdays 6:30").
    let summary: String

    var isOutline: Bool { look != .planned }

    /// - Parameters:
    ///   - plan: `SleepPlannerViewModel.plan`, for the wake time asked (`wake`).
    ///   - goal: Bedtime & wake's goal; `nil` without a schedule.
    init(plan: SleepPlan?, wake: Date, goal: SleepSchedule.Goal?, isLoading: Bool = false, error: String? = nil,
         isOnline: Bool = true, asOf: Date? = nil, alarmProblem: String? = nil, summary: String = "",
         locale: Locale = .autoupdatingCurrent) {
        self.alarmProblem = alarmProblem
        self.summary = summary
        self.asOf = asOf.map { String(localized: "As of \(Fmt.time($0, locale: locale))") }
        let loading = String(localized: "Loading…")
        guard let goal else {
            look = .noSchedule
            digits = nil
            meridiem = nil
            numeralLabel = nil
            caption = ""
            ruler = nil
            self.wake = String(localized: "wake \(Fmt.time(wake, locale: locale))")
            rows = []
            tiles = []
            spokenTile = ""
            self.plan = nil
            message = nil
            return
        }
        guard let plan else {
            let look: Look = isLoading ? .planning : error != nil ? .failed : !isOnline ? .offline : .planning
            self.look = look
            digits = nil
            meridiem = nil
            numeralLabel = look == .planning ? loading : nil
            caption = look == .planning ? loading : ""
            ruler = SleepRuler(totalMin: nil, needMin: nil, locale: locale)
            self.wake = String(localized: "wake \(Fmt.time(wake, locale: locale))")
            rows = SleepSchedule.Goal.allCases.map {
                Row(goal: $0, time: Fmt.placeholder, share: Self.share($0), asleep: "", isGoal: $0 == goal, spoken: "")
            }
            tiles = [Self.need(nil, locale: locale), Self.timeInBed(nil, efficiency: nil, locale: locale)]
            spokenTile = ""
            self.plan = nil
            switch look {
            case .failed: message = error
            case .offline:
                message = String(localized: "Tonight's bedtime needs a connection. It appears once you're online.")
            default: message = nil
            }
            return
        }
        look = .planned
        message = nil
        self.plan = plan
        let bed = goal.bedtime(in: plan)
        let parts = Fmt.clockParts(bed, locale: locale)
        digits = parts.digits
        meridiem = parts.meridiem
        numeralLabel = String(localized: "Go to bed at \(Fmt.time(bed, locale: locale))",
                              comment: "VoiceOver on Sleep → Bedtime's numeral: tonight's bedtime for your goal (\"Go to bed at 10:06 PM\").")
        caption = String(localized: "In bed by · \(goal.rawValue) % of your need",
                         comment: "Sleep → Bedtime, under the numeral: the bedtime gives this share of tonight's need (\"In bed by · 100 % of your need\").")
        let sleepMin = Self.sleepMin(plan, goal: goal)
        ruler = SleepRuler(totalMin: sleepMin, needMin: plan.needMin, locale: locale)
        self.wake = String(localized: "wake \(Fmt.time(plan.wake, locale: locale))",
                           comment: "Sleep → Bedtime's go-to-bed tile, top right: the wake time the bedtimes are for (\"wake 7:00 AM\"). Lower case.")
        rows = SleepSchedule.Goal.allCases.map { option in
            let time = Fmt.time(option.bedtime(in: plan), locale: locale)
            let minutes = Self.sleepMin(plan, goal: option)
            let asleep = String(localized: "\(Fmt.duration(minutes: minutes)) asleep")
            let spokenShare = String(localized: "\(option.rawValue) percent of your need")
            var spoken = [time, spokenShare,
                          String(localized: "\(Fmt.spokenDuration(minutes: minutes, locale: locale)) asleep")]
            if option == goal {
                spoken.append(String(localized: "your goal",
                                     comment: "VoiceOver on Sleep → Bedtime's go-to-bed tile, after the goal that is yours (the filled marker)."))
            }
            return Row(goal: option, time: time, share: Self.share(option), asleep: asleep, isGoal: option == goal,
                       spoken: spoken.joined(separator: ", "))
        }
        spokenTile = ([self.wake] + rows.map(\.spoken)).joined(separator: ". ")
        let inBed = Int((Double(plan.inBedMin) * Double(goal.rawValue) / 100).rounded())
        tiles = [Self.need(plan.needMin, locale: locale), Self.timeInBed(inBed, efficiency: plan.efficiency, locale: locale)]
    }

    /// The sleep a goal gives: its share of the need.
    static func sleepMin(_ plan: SleepPlan, goal: SleepSchedule.Goal) -> Int {
        Int((Double(plan.needMin) * Double(goal.rawValue) / 100).rounded())
    }

    /// "100 % of your need".
    static func share(_ goal: SleepSchedule.Goal) -> String {
        String(localized: "\(goal.rawValue) % of your need")
    }

    // MARK: tiles

    /// "8:01" + "h"; "–" without a plan.
    static func need(_ minutes: Int?, locale: Locale = .autoupdatingCurrent) -> SleepTile {
        guard let minutes else {
            return SleepTile(kind: .need, value: Fmt.placeholder, unit: nil, notes: [], marks: [],
                             spokenValue: String(localized: "No data"))
        }
        return SleepTile(kind: .need, value: Fmt.clock(minutes: minutes), unit: hours, notes: [], marks: [],
                         spokenValue: Fmt.spokenDuration(minutes: minutes, locale: locale))
    }

    /// "8:54" + "h" and the efficiency it assumes ("90 %") in `textTertiary`; "–" without a plan.
    static func timeInBed(_ minutes: Int?, efficiency: Int?, locale: Locale = .autoupdatingCurrent) -> SleepTile {
        guard let minutes else {
            return SleepTile(kind: .timeInBed, value: Fmt.placeholder, unit: nil, notes: [], marks: [],
                             spokenValue: String(localized: "No data"))
        }
        var spoken = Fmt.spokenDuration(minutes: minutes, locale: locale)
        var notes: [SleepTile.Note] = []
        if let efficiency {
            notes.append(SleepTile.Note(text: "\(efficiency) %", ink: .tertiary))
            spoken += ", " + String(localized: "at \(efficiency) percent efficiency",
                                    comment: "VoiceOver on Sleep → Bedtime's Time in bed tile, after the time: the assumed efficiency (\"at 90 percent …\").")
        }
        return SleepTile(kind: .timeInBed, value: Fmt.clock(minutes: minutes), unit: hours, notes: notes, marks: [],
                         spokenValue: spoken)
    }

    /// The unit after a clock value ("8:01 h"), as on Day's tiles.
    private static var hours: String {
        String(localized: "h", comment: "Hours, the unit after a clock duration on Today's Sleep tile and on Sleep's tiles: \"7:48 h\", \"0:30 h\".")
    }
}

// MARK: - the section

/// Bedtime under the header and the picker (§P5-7.3): the notice, the numeral 22 under the picker, its caption, the ruler, the
/// go-to-bed tile 20 under the ruler's box, the two tiles, the settings card and the footer. Without a schedule: the sentence
/// and the button to Bedtime & wake.
struct SleepBedtimeSection: View {
    let board: SleepBedtimeBoard
    /// The wake time asked ("Wake up at").
    @Binding var wake: Date
    var numeralStyle: DotNumeral.Style = .dots
    /// Previews and tests; `nil` follows the system.
    var reduceTransparency: Bool?
    var notice = SleepModeNotice(issue: nil)
    var retry: () async -> Void = {}

    @Environment(ScreenModels.self) private var screens
    @State private var showsSchedule = false

    var body: some View {
        VStack(spacing: 0) {
            notice
            SleepBedtimeHead(board: board, numeralStyle: numeralStyle)
            switch board.look {
            case .noSchedule:
                invitation
                    .padding(.top, SleepModesLayout.captionGap)
            case .planned, .planning, .failed, .offline:
                planned
            }
        }
        .navigationDestination(isPresented: $showsSchedule) { SleepScheduleView(planner: screens.bedtime) }
    }

    @ViewBuilder private var planned: some View {
        if let ruler = board.ruler {
            RulerScale(range: SleepRuler.range, value: ruler.value, zone: ruler.zone, zoneStyle: .sleep,
                       tickCount: RulerScale.Ticks.sleep, labels: ruler.labels, size: .regular,
                       accessibilityLabel: Text("Planned sleep",
                                                comment: "VoiceOver label of Sleep → Bedtime's ruler: the sleep tonight's bedtime gives, 0 to 10 hours."),
                       accessibilityValue: Text(ruler.spokenValue), followingGap: SleepModesLayout.goToBedGap)
                .accessibilityIdentifier("sleep.bedtime.ruler")
                .padding(.top, SleepModesLayout.rulerGap)
        }
        Group {
            switch board.look {
            case .failed, .offline:
                InlineMessage(message: board.message ?? "",
                              systemImage: board.look == .offline ? "wifi.exclamationmark" : "exclamationmark.circle",
                              retry: board.look == .failed ? retry : nil, identifier: "sleep.bedtime.failure")
            default:
                SleepGoToBedTile(board: board, reduceTransparency: reduceTransparency)
            }
        }
        .padding(.top, SleepModesLayout.goToBedGap)
        SleepTileGrid(tiles: board.tiles, isOutline: board.isOutline)
            .padding(.top, SleepModesLayout.tilesGap)
        SleepBedtimeSettings(board: board, wake: $wake) { showsSchedule = true }
            .padding(.top, SleepModesLayout.settingsGap)
        if let problem = board.alarmProblem {
            InlineMessage(message: problem, systemImage: "alarm", identifier: "sleep.bedtime.alarm", severity: .attention)
                .padding(.top, SleepModesLayout.cardGap)
        }
        if let asOf = board.asOf {
            Text(asOf)
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, GroupedListSpec.rowInset)
                .padding(.top, SleepModesLayout.footerGap)
        }
    }

    /// No Bedtime & wake yet: what it does, and the way in.
    private var invitation: some View {
        VStack(spacing: SleepModesLayout.tileGap) {
            Text("Tell RYFT when you want to wake up. It tells you when to go to bed, with what today's strain and your sleep debt add.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            PillButton(Text("Set up Bedtime & wake"), systemImage: "arrow.right") { showsSchedule = true }
                .accessibilityIdentifier("sleep.bedtime.setUp")
        }
    }
}

/// The bedtime as the numeral, the meridiem 8 after it at its baseline, centred as a pair, 22 under the picker; the caption
/// 12 under it.
struct SleepBedtimeHead: View {
    let board: SleepBedtimeBoard
    var numeralStyle: DotNumeral.Style = .dots

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: SleepModesLayout.meridiemGap) {
                DotNumeral(board.digits, style: numeralStyle, glyphGap: DotNumeral.glyphGapDetail, placeholder: "00:00",
                           accessibilityLabel: Text(board.numeralLabel ?? ""))
                if let meridiem = board.meridiem {
                    Text(meridiem)
                        .font(.ryft(.label))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(board.numeralLabel ?? ""))
            .accessibilityHidden(board.numeralLabel == nil)
            .accessibilityIdentifier("sleep.bedtime.numeral")
            .frame(maxWidth: .infinity)
            .padding(.top, SleepModesLayout.numeralGap)
            Text(verbatim: board.caption.isEmpty ? " " : board.caption)
                .font(.ryft(.label))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(board.caption.isEmpty || board.look == .planning)
                .padding(.top, SleepModesLayout.captionGap)
        }
    }
}

/// The go-to-bed glow tile (§P5-7.3 row 4): "Go to bed" and the wake time; the three goals 12 under the head and 10 apart:
/// the marker (filled for your goal, a ring for the others: shape, not colour), the bedtime (24 pt Light) and, at the end,
/// the share over the sleep it gives, in the glow label's ink. One VoiceOver element. While planning: an outline with the
/// rows unlit.
struct SleepGoToBedTile: View {
    let board: SleepBedtimeBoard
    var reduceTransparency: Bool?

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The bedtimes' 24 pt, growing with Dynamic Type (`ryftNumber` is a fixed size).
    @ScaledMetric(relativeTo: .title2) private var timeSize = SleepModesLayout.optionTimeSize

    var body: some View {
        if board.look == .planned {
            GlowTile(Theme.metricSleep, kind: .hypnogram, minHeight: SleepModesLayout.goToBedMinHeight,
                     reduceTransparency: reduceTransparency) {
                content(lit: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Go to bed"))
            .accessibilityValue(Text(board.spokenTile))
            .accessibilityIdentifier("sleep.bedtime.goToBed")
        } else {
            content(lit: false)
                .padding(GlowTileSpec.padding(for: .hypnogram))
                .frame(maxWidth: .infinity, minHeight: SleepModesLayout.goToBedMinHeight, alignment: .topLeading)
                .background {
                    PlaceholderOutline(RoundedRectangle(cornerRadius: SleepLayout.hypnogramRadius, style: .continuous))
                }
                .accessibilityHidden(true)
        }
    }

    private func content(lit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            head(lit: lit)
            VStack(alignment: .leading, spacing: SleepModesLayout.optionGap) {
                ForEach(board.rows) { row($0, lit: lit) }
            }
            .padding(.top, SleepModesLayout.optionsGap)
        }
    }

    @ViewBuilder private func head(lit: Bool) -> some View {
        let title = Text("Go to bed")
        let wake = Text(board.wake)
        if lit {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title.ryftGlowLabelStyle()
                    Spacer(minLength: 0)
                    wake.ryftGlowLabelStyle(.caption).lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    title.ryftGlowLabelStyle()
                    wake.ryftGlowLabelStyle(.caption)
                }
            }
        } else {
            title.ryftLabelStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder private func row(_ row: SleepBedtimeBoard.Row, lit: Bool) -> some View {
        let marker = SleepGoalMarker(isGoal: row.isGoal, lit: lit)
        let time = Text(row.time)
            .font(.ryftNumber(size: timeSize, weight: .light))
            .foregroundStyle(lit ? Theme.textPrimary : Theme.textTertiary)
            .lineLimit(1)
            .fixedSize()
        // The marker sits on the time's baseline (a shape's baseline is its bottom).
        let bedtime = HStack(alignment: .firstTextBaseline, spacing: SleepModesLayout.markerGap) {
            marker
            time
        }
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                bedtime
                shares(row, lit: lit, alignment: .leading)
                    .padding(.leading, SleepModesLayout.markerSize + SleepModesLayout.markerGap)
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                bedtime
                Spacer(minLength: 0)
                shares(row, lit: lit, alignment: .trailing)
            }
        }
    }

    @ViewBuilder private func shares(_ row: SleepBedtimeBoard.Row, lit: Bool, alignment: HorizontalAlignment) -> some View {
        if lit {
            VStack(alignment: alignment, spacing: 2) {
                Text(row.share).ryftGlowLabelStyle()
                Text(row.asleep).ryftGlowLabelStyle(.caption).monospacedDigit()
            }
            .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        } else {
            Text(row.share).ryftLabelStyle(Theme.textTertiary)
        }
    }
}

/// A goal's marker: a 6 pt dot in `textPrimary` for your goal, a 1 pt ring for the others (shape, not colour); `textTertiary`
/// while unlit.
struct SleepGoalMarker: View {
    let isGoal: Bool
    var lit = true

    var body: some View {
        let ink = lit ? Theme.textPrimary : Theme.textTertiary
        Group {
            if isGoal {
                Circle().fill(ink)
            } else {
                Circle().strokeBorder(ink, lineWidth: SleepModesLayout.markerRing)
            }
        }
        .frame(width: SleepModesLayout.markerSize, height: SleepModesLayout.markerSize)
        .accessibilityHidden(true)
    }
}

/// The settings card (§P5-7.3 row 6): "Wake up at" with the compact time picker, "Why this need" (opens the need's terms in
/// the card), "Bedtime & wake" (→ the editor, its summary as the value).
struct SleepBedtimeSettings: View {
    let board: SleepBedtimeBoard
    @Binding var wake: Date
    let openSchedule: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsWhy = false
    /// The chevron grows as the grouped rows' does.
    @ScaledMetric(relativeTo: .callout) private var glyphScale: CGFloat = 1

    var body: some View {
        GroupedCard {
            GroupedRow.custom(Text("Wake up at")) {
                DatePicker(selection: $wake, displayedComponents: .hourAndMinute) { Text("Wake up at") }
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("sleep.bedtime.wake")
            }
            if let plan = board.plan {
                whyRow
                if showsWhy {
                    NeedBasisRows(plan: plan)
                        .font(.ryft(.callout))
                        .padding(.horizontal, GroupedListSpec.rowInset)
                        .padding(.bottom, GroupedListSpec.textPadding)
                        .transition(.opacity)
                }
            }
            GroupedRow.push(Text("Bedtime & wake"), value: Text(board.summary), action: openSchedule)
                .accessibilityIdentifier("sleep.bedtime.schedule")
        }
    }

    /// "Why this need" and a chevron that turns down while the terms show.
    private var whyRow: some View {
        Button {
            withAnimation(Theme.Motion.respecting(reduceMotion)) { showsWhy.toggle() }
        } label: {
            HStack(spacing: GroupedListSpec.rowSpacing) {
                Text("Why this need")
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: GroupedListSpec.chevronSize * glyphScale, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(GroupedListSpec.accessoryOpacity))
                    .rotationEffect(.degrees(showsWhy ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, GroupedListSpec.rowInset)
            .padding(.vertical, GroupedListSpec.textPadding)
            .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showsWhy ? Text("Expanded") : Text("Collapsed"))
        .accessibilityIdentifier("sleep.bedtime.why")
        .groupedRowHairline()
    }
}

// MARK: - previews

/// Sleep → Bedtime for a state, as `SleepView` lays it out (previews and the hosted tests).
struct SleepBedtimePreviewPage: View {
    enum Scene: String, CaseIterable {
        case planned, perform, noSchedule, planning, failed, offline, alarmProblem
    }

    let scene: Scene

    init(_ scene: Scene) {
        self.scene = scene
    }

    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now

    var board: SleepBedtimeBoard {
        let plan = MockJournal.sleepPlan(wake: "07:00")
        // As Bedtime & wake writes it (`BedtimePlanner.summary`).
        let summary = "06:30 · weekend 08:00"
        switch scene {
        case .planned: return SleepBedtimeBoard(plan: plan, wake: wake, goal: .peak, summary: summary)
        case .perform: return SleepBedtimeBoard(plan: plan, wake: wake, goal: .perform, summary: summary)
        case .noSchedule: return SleepBedtimeBoard(plan: plan, wake: wake, goal: nil)
        case .planning: return SleepBedtimeBoard(plan: nil, wake: wake, goal: .peak, isLoading: true, summary: summary)
        case .failed:
            return SleepBedtimeBoard(plan: nil, wake: wake, goal: .peak,
                                     error: RefreshIssue.Reason.busy.message, summary: summary)
        case .offline:
            return SleepBedtimeBoard(plan: nil, wake: wake, goal: .peak, isOnline: false, summary: summary)
        case .alarmProblem:
            return SleepBedtimeBoard(plan: plan, wake: wake, goal: .peak, asOf: .now.addingTimeInterval(-3_600),
                                     alarmProblem: "The wake-up alarm is off: iOS doesn't allow RYFT's alarms. Turn it on again to allow them.",
                                     summary: summary)
        }
    }

    var body: some View {
        let header = SleepHeaderContent(mode: .plan, night: .now, today: .now, marker: nil, canStepBack: false,
                                        canStepForward: false)
        NavigationStack {
            SleepPage(header: header, mode: .constant(.plan), modes: SleepMode.allCases, step: { _ in }) {
                SleepBedtimeSection(board: board, wake: $wake)
            }
        }
    }
}

#Preview("Sleep · Bedtime") { SleepBedtimePreviewPage(.planned).previewEnvironment() }
#Preview("Sleep · Bedtime · AX3") {
    SleepBedtimePreviewPage(.planned).previewEnvironment().environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Sleep · Bedtime, goal Perform") { SleepBedtimePreviewPage(.perform).previewEnvironment() }
#Preview("Sleep · Bedtime, not set up") { SleepBedtimePreviewPage(.noSchedule).previewEnvironment() }
#Preview("Sleep · Bedtime, not set up · AX3") {
    SleepBedtimePreviewPage(.noSchedule).previewEnvironment().environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Sleep · Bedtime, planning") { SleepBedtimePreviewPage(.planning).previewEnvironment() }
#Preview("Sleep · Bedtime, failed") { SleepBedtimePreviewPage(.failed).previewEnvironment() }
#Preview("Sleep · Bedtime, offline") { SleepBedtimePreviewPage(.offline).previewEnvironment() }
#Preview("Sleep · Bedtime, alarm problem") { SleepBedtimePreviewPage(.alarmProblem).previewEnvironment() }
