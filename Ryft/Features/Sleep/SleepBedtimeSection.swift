// Sleep → Bedtime in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-7.3, the draft `draft-sleep-bedtime`): tonight's
// bedtime for your goal as the hero numeral, the planned sleep on Day's ruler, the three goals in the go-to-bed glow tile, Need
// and Time in bed, then the wake time, why the need is what it is and Bedtime & wake. Without Bedtime & wake: the invitation
// over the three bedtimes for the wake time asked and the settings card. The numbers come from `GET /v1/sleep/plan`
// (`SleepPlannerViewModel`), the goal and the alarm from `BedtimePlanner`; `SleepBedtimeBoard` decides every value and look.
import SwiftUI

// MARK: - the board (pure)

/// Bedtime as values: the numeral and its meridiem, the caption, the ruler, the goals, the tiles, the footer; the look for
/// planning, a failed plan and offline, with or without Bedtime & wake. Pure: tests build it without a view.
struct SleepBedtimeBoard: Equatable {
    /// The plan's state.
    enum Look: Equatable {
        /// A plan to show.
        case planned
        /// No plan yet and the request in flight: the unlit numeral, the ruler without its needle, outlines.
        case planning
        /// The plan failed with nothing cached: the calm sentence, Details and Today's button in the tile's place.
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
    /// Bedtime & wake is set up: the numeral, the caption, the ruler and the tiles are its goal's. Without it the invitation
    /// stands over the three bedtimes (no "your goal") and the settings card.
    let hasSchedule: Bool
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
    /// What the ruler says without a plan (not Day's "No time asleep yet").
    static var rulerPlaceholder: String {
        String(localized: "No plan yet, on a scale from 0 to 10 hours.",
               comment: "VoiceOver on Sleep → Bedtime's ruler (\"Planned sleep\") while tonight's plan is loading, failed or offline.")
    }
    /// "wake 7:00 AM" in the tile's head.
    let wake: String
    /// Peak, Perform, Get by (100 / 85 / 70 %), earliest first.
    let rows: [Row]
    /// Need and Time in bed; none without a schedule (Time in bed is the goal's share).
    let tiles: [SleepTile]
    /// The tile as one VoiceOver value: the wake time and the three goals.
    let spokenTile: String
    /// The plan's need, term by term ("Why this need"); `nil` without a plan.
    let plan: SleepPlan?
    /// "As of 10:44 AM": the plan is a cached one.
    let asOf: String?
    /// The failed plan's sentence, or the offline one.
    let message: String?
    /// The failed plan's symbol, Details and button (`SleepLoadFailure`).
    let failure: SleepLoadFailure?
    /// The wake alarm couldn't be set: under the settings card.
    let alarmProblem: String?
    /// Bedtime & wake's row value (`BedtimePlanner.summary`: "6:30 AM · weekend 8:00 AM", "Off").
    let summary: String

    var isOutline: Bool { look != .planned }

    /// - Parameters:
    ///   - plan: `SleepPlannerViewModel.plan`, for the wake time asked (`wake`).
    ///   - goal: Bedtime & wake's goal; `nil` without a schedule.
    ///   - failure: why the plan couldn't load with nothing cached; offline is said first.
    init(plan: SleepPlan?, wake: Date, goal: SleepSchedule.Goal?, isLoading: Bool = false, failure: SleepLoadFailure? = nil,
         isOnline: Bool = true, asOf: Date? = nil, alarmProblem: String? = nil, summary: String = "",
         locale: Locale = .autoupdatingCurrent) {
        self.alarmProblem = alarmProblem
        self.summary = summary
        self.asOf = asOf.map { String(localized: "As of \(Fmt.time($0, locale: locale))") }
        hasSchedule = goal != nil
        let look: Look = plan != nil ? .planned : isLoading ? .planning : !isOnline ? .offline
            : failure != nil ? .failed : .planning
        self.look = look
        self.plan = plan
        self.failure = look == .failed ? failure : nil
        switch look {
        case .failed: message = failure?.message
        case .offline: message = String(localized: "Tonight's bedtime needs a connection. It appears once you're online.")
        case .planned, .planning: message = nil
        }
        let loading = String(localized: "Loading…")
        guard let plan else {
            digits = nil
            meridiem = nil
            numeralLabel = look == .planning && goal != nil ? loading : nil
            caption = look == .planning && goal != nil ? loading : ""
            ruler = goal.map { _ in SleepRuler(totalMin: nil, needMin: nil, unknown: Self.rulerPlaceholder, locale: locale) }
            self.wake = String(localized: "wake \(Fmt.time(wake, locale: locale))")
            rows = SleepSchedule.Goal.allCases.map {
                Row(goal: $0, time: Fmt.placeholder, share: Self.share($0), asleep: "", isGoal: $0 == goal, spoken: "")
            }
            tiles = goal == nil ? [] : [Self.need(nil, locale: locale), Self.timeInBed(nil, efficiency: nil, locale: locale)]
            spokenTile = ""
            return
        }
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
        guard let goal else {
            digits = nil
            meridiem = nil
            numeralLabel = nil
            caption = ""
            ruler = nil
            tiles = []
            return
        }
        let bed = goal.bedtime(in: plan)
        let parts = Fmt.clockParts(bed, locale: locale)
        digits = parts.digits
        meridiem = parts.meridiem
        numeralLabel = String(localized: "Go to bed at \(Fmt.time(bed, locale: locale))",
                              comment: "VoiceOver on Sleep → Bedtime's numeral: tonight's bedtime for your goal (\"Go to bed at 10:06 PM\").")
        caption = String(localized: "In bed by · \(goal.rawValue)\u{00A0}% of your need",
                         comment: "Sleep → Bedtime, under the numeral: the bedtime gives this share of tonight's need (\"In bed by · 100 % of your need\").")
        ruler = SleepRuler(totalMin: Self.sleepMin(plan, goal: goal), needMin: plan.needMin, locale: locale)
        let inBed = Int((Double(plan.inBedMin) * Double(goal.rawValue) / 100).rounded())
        tiles = [Self.need(plan.needMin, locale: locale), Self.timeInBed(inBed, efficiency: plan.efficiency, locale: locale)]
    }

    /// The sleep a goal gives: its share of the need.
    static func sleepMin(_ plan: SleepPlan, goal: SleepSchedule.Goal) -> Int {
        Int((Double(plan.needMin) * Double(goal.rawValue) / 100).rounded())
    }

    /// "100 % of your need".
    static func share(_ goal: SleepSchedule.Goal) -> String {
        String(localized: "\(goal.rawValue)\u{00A0}% of your need")
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
            notes.append(SleepTile.Note(text: "\(efficiency)\u{00A0}%", ink: .tertiary))
            spoken += ", " + String(localized: "at \(efficiency)\u{00A0}percent efficiency",
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
/// and the button to Bedtime & wake over the three bedtimes for the wake time asked and the settings card.
struct SleepBedtimeSection: View {
    let board: SleepBedtimeBoard
    /// The wake time asked ("Wake up at").
    @Binding var wake: Date
    var numeralStyle: DotNumeral.Style = .dots
    /// Previews and tests; `nil` follows the system.
    var reduceTransparency: Bool?
    var notice = SleepModeNotice(issue: nil)
    /// A failed plan's Try again and Sign in (`SleepLoadFailure.action`).
    var retry: (() async -> Void)?
    var signIn: (() async -> Void)?

    @Environment(ScreenModels.self) private var screens
    /// Bedtime & wake, pushed: from the settings card, or from Set up (leaving it without a change sets it up).
    @State private var opening: SleepScheduleView.Opening?

    var body: some View {
        VStack(spacing: 0) {
            notice
            SleepBedtimeHead(board: board, numeralStyle: numeralStyle)
            if !board.hasSchedule {
                invitation
                    .padding(.top, SleepModesLayout.captionGap)
            }
            planned
        }
        .navigationDestination(item: $opening) { SleepScheduleView(planner: screens.bedtime, opening: $0) }
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
            case .failed:
                let failure = board.failure
                let action = failure?.action ?? .retry
                // Part of the section, as on Bedtime & wake and Tonight: read in place, not announced.
                InlineMessage(message: board.message ?? "", systemImage: failure?.systemImage ?? "exclamationmark.circle",
                              retryTitle: action.title, details: failure?.details,
                              retry: action.button(retry: retry, signIn: signIn), identifier: "sleep.bedtime.failure",
                              announces: false)
            case .offline:
                InlineMessage(message: board.message ?? "", systemImage: "wifi.exclamationmark",
                              identifier: "sleep.bedtime.failure", announces: false)
            case .planned, .planning:
                SleepGoToBedTile(board: board, reduceTransparency: reduceTransparency)
            }
        }
        .padding(.top, board.hasSchedule ? SleepModesLayout.goToBedGap : SleepModesLayout.tileGap)
        if !board.tiles.isEmpty {
            SleepTileGrid(tiles: board.tiles, isOutline: board.isOutline)
                .padding(.top, SleepModesLayout.tilesGap)
        }
        SleepBedtimeSettings(board: board, wake: $wake) { opening = .edit }
            .padding(.top, SleepModesLayout.settingsGap)
        if let problem = board.alarmProblem {
            InlineMessage(message: problem, systemImage: "alarm", identifier: "sleep.bedtime.alarm", severity: .attention,
                          announces: false)
                .padding(.top, SleepModesLayout.cardGap)
        }
        if let asOf = board.asOf {
            SleepAsOfNote(text: asOf, identifier: "sleep.bedtime.asOf")
        }
    }

    /// No Bedtime & wake yet: what it does, and the way in, over the bedtimes for the wake time asked.
    private var invitation: some View {
        VStack(spacing: SleepModesLayout.tileGap) {
            Text("Tell RYFT when you want to wake up. It tells you when to go to bed, with what today's strain and your sleep debt add.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            // Tonight's glyph for the same action (§4.13).
            PillButton(Text("Set up Bedtime & wake"), systemImage: "bed.double") { opening = .setUp }
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
/// the card, as Tonight's does: `NeedDisclosure`), "Bedtime & wake" (→ the editor, its summary as the value).
struct SleepBedtimeSettings: View {
    let board: SleepBedtimeBoard
    @Binding var wake: Date
    let openSchedule: () -> Void

    var body: some View {
        GroupedCard {
            GroupedRow.custom(Text("Wake up at")) {
                DatePicker(selection: $wake, displayedComponents: .hourAndMinute) { Text("Wake up at") }
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("sleep.bedtime.wake")
            }
            if let plan = board.plan {
                NeedDisclosure(plan: plan, identifier: "sleep.bedtime.why")
            }
            GroupedRow.push(Text("Bedtime & wake"), value: Text(board.summary), action: openSchedule)
                .accessibilityIdentifier("sleep.bedtime.schedule")
        }
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
        // Bedtime & wake's row, as it writes its default schedule (`BedtimePlanner.summary`).
        let summary = BedtimePlanner.summary(.default)
        switch scene {
        case .planned: return SleepBedtimeBoard(plan: plan, wake: wake, goal: .peak, summary: summary)
        case .perform: return SleepBedtimeBoard(plan: plan, wake: wake, goal: .perform, summary: summary)
        case .noSchedule:
            return SleepBedtimeBoard(plan: plan, wake: wake, goal: nil, summary: BedtimePlanner.summary(nil))
        case .planning: return SleepBedtimeBoard(plan: nil, wake: wake, goal: .peak, isLoading: true, summary: summary)
        case .failed:
            let failure = SleepLoadFailure(APIError.http(503, "", requestID: "01JD8K2V9Q7M3X"), isOnline: true, at: .now)
            return SleepBedtimeBoard(plan: nil, wake: wake, goal: .peak, failure: failure, summary: summary)
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
                SleepBedtimeSection(board: board, wake: $wake, retry: scene == .failed ? {} : nil)
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
