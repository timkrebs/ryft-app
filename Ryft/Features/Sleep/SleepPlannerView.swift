// Tonight and Bedtime & wake in Nocturne (docs/work/2026-11-16-nocturne/design-pr6-c-settings.md §4.13, drafts c-21 … c-22c):
// Tonight's bedtime as a dot numeral in the sleep glow tile, the three goals, why the need is what it is and the way to
// Bedtime & wake; Bedtime & wake as a subpage of grouped cards. `TonightBoard` decides Tonight's values and look,
// `BedtimeScheduleEditor` the page's saving; `BedtimePlanner` plans, saves and schedules.
import SwiftUI
import UIKit

/// Tonight's layout and Bedtime & wake's own numbers (§4.13).
enum TonightLayout {
    /// The glow tile: at least 218 high.
    nonisolated static let tileMinHeight: CGFloat = 218
    /// Head → "In bed by" 14, → the numeral 8, → the line 10, → the goals 16; the goals 8 apart.
    nonisolated static let labelGap: CGFloat = 14, numeralGap: CGFloat = 8, lineGap: CGFloat = 10, goalsGap: CGFloat = 16
    nonisolated static let goalGap: CGFloat = 8
    /// The marker → the goal's title; the numeral → its meridiem (Sleep → Bedtime's).
    nonisolated static let markerGap: CGFloat = 10, meridiemGap = SleepModesLayout.meridiemGap
    /// The tile → the group under it (and the alarm's notice), as groups stand apart.
    nonisolated static let groupGap = GroupedListSpec.groupSpacing
    /// The outline cards (not set up, planning): the sleep tile's 28 corner, the hypnogram tile's padding; 14 between parts.
    nonisolated static let outlineRadius: CGFloat = 28, outlineGap: CGFloat = 14, pillGap: CGFloat = 16
    /// Bedtime & wake's wind-down row: its title over the segments, 14 above and below.
    nonisolated static let windDownPadding: CGFloat = 14
}

/// Tonight's need, term by term (`GET /v1/sleep/plan` → `basis`), as value rows of the card it opens in: Baseline, Today's
/// strain so far, Sleep debt, Nap credit (when there is one), Tonight's need.
struct NeedBasisRows: View {
    let plan: SleepPlan

    var body: some View {
        GroupedRow.value(Text("Baseline"), value: Text(Fmt.duration(minutes: plan.basis.base)))
        GroupedRow.value(Text("Today's strain so far"), value: Text(verbatim: "+" + Fmt.duration(minutes: plan.basis.strainTopup)))
        GroupedRow.value(Text("Sleep debt"), value: Text(verbatim: "+" + Fmt.duration(minutes: plan.basis.debtTopup)))
        if plan.basis.napCredit > 0 {
            GroupedRow.value(Text("Nap credit"), value: Text(Fmt.duration(minutes: -plan.basis.napCredit)))
        }
        GroupedRow.value(Text("Tonight's need"), value: Text(Fmt.duration(minutes: plan.needMin)))
    }
}

/// "Why this need" in a grouped card (Tonight, Sleep → Bedtime): a row whose chevron turns down while the need's terms show
/// under it as value rows of the same card. VoiceOver: a button, "Collapsed" or "Expanded".
struct NeedDisclosure: View {
    let plan: SleepPlan
    let identifier: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen = false
    /// The chevron grows as the grouped rows' does.
    @ScaledMetric(relativeTo: .callout) private var glyphScale: CGFloat = 1

    var body: some View {
        Button {
            withAnimation(Theme.Motion.respecting(reduceMotion)) { isOpen.toggle() }
        } label: {
            HStack(spacing: GroupedListSpec.rowSpacing) {
                Text("Why this need")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: GroupedListSpec.chevronSize * glyphScale, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(GroupedListSpec.accessoryOpacity))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, GroupedListSpec.rowInset)
            .padding(.vertical, GroupedListSpec.textPadding)
            .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
        .accessibilityIdentifier(identifier)
        .groupedRowHairline()
        if isOpen {
            NeedBasisRows(plan: plan)
                .transition(.opacity)
        }
    }
}

// MARK: - Tonight

/// Tonight on Today (and in the debug screen): `TonightView` for the planner's board; it plans when there is no plan yet,
/// and again once the iPhone is back online with none, so offline never stays on screen after the connection returns.
/// Bedtime & wake opens through `openSchedule` when the screen hosts it on a view that stays (Today: the card leaves when
/// the evening ends or a first import starts, and the page mustn't go with it); without one the card pushes it itself.
struct TonightCard: View {
    let planner: BedtimePlanner
    var openSchedule: ((SleepScheduleView.Opening) -> Void)?
    @Environment(\.locale) private var locale
    @State private var opening: SleepScheduleView.Opening?

    var body: some View {
        TonightView(board: planner.tonight(locale: locale), numeralStyle: planner.numeralStyle,
                    retry: { await planner.refresh() }, signIn: { await planner.signIn() },
                    openSchedule: { if let openSchedule { openSchedule($0) } else { opening = $0 } })
            .navigationDestination(item: $opening) { SleepScheduleView(planner: planner, opening: $0) }
            .task { if planner.plan == nil { await planner.refresh() } }
            .onChange(of: planner.isOnline) { _, online in
                guard online, planner.plan == nil else { return }
                Task { await planner.refresh() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tonight.card")
    }
}

/// Tonight for a board (§4.13):
///
/// - Planned: the sleep glow tile ("Tonight" and "As of" when the plan is the last one fetched; "In bed by"; the bedtime as a
///   dot numeral with its meridiem; "for 100 % · wake 6:30 AM · need 8:18"; the three goals, filled marker for yours), one
///   VoiceOver element with the summary as its value; 18 under it the alarm's amber notice when iOS stopped allowing it, and
///   a group with Why this need and Bedtime & wake.
/// - Not set up: an outline card with "Tonight", what it does and the pill Set up Bedtime & wake.
/// - Planning (nothing cached yet): the outline card with the unlit numeral and "Planning tonight…", never a spinner.
/// - Offline or failed with nothing cached: "Tonight" over the notice, its button (Try again, Sign in) when one helps.
struct TonightView: View {
    let board: TonightBoard
    var numeralStyle: DotNumeral.Style = .dots
    /// Previews and tests; `nil` follows the system.
    var reduceTransparency: Bool?
    var retry: (() async -> Void)?
    var signIn: (() async -> Void)?
    /// Bedtime & wake: from the group's row, or from Set up (`.setUp`: leaving without a change sets it up).
    var openSchedule: (SleepScheduleView.Opening) -> Void = { _ in }

    var body: some View {
        switch board.look {
        case .planned: planned
        case .notSetUp: notSetUp
        case .planning: planning
        case .offline, .failed: notice
        }
    }

    // MARK: planned

    private var planned: some View {
        VStack(alignment: .leading, spacing: TonightLayout.groupGap) {
            TonightTile(board: board, numeralStyle: numeralStyle, reduceTransparency: reduceTransparency)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Tonight"))
                .accessibilityValue(Text(board.spoken))
                .accessibilityIdentifier("tonight.tile")
            if let alarm = board.alarmProblem {
                // Part of the card: VoiceOver reads it in place, not as an announcement.
                InlineMessage(message: alarm, systemImage: "alarm", identifier: "tonight.alarm", severity: .attention,
                              announces: false)
            }
            GroupedCard {
                if let plan = board.plan {
                    NeedDisclosure(plan: plan, identifier: "tonight.why")
                }
                GroupedRow.push(Text("Bedtime & wake"), value: Text(board.summary), identifier: "tonight.schedule") {
                    openSchedule(.edit)
                }
            }
        }
    }
}

/// Tonight's glow tile (§4.13): "Tonight" and "As of" when the plan is the last one fetched; "In bed by"; the bedtime as a dot
/// numeral with its meridiem; "for 100 % · wake 6:30 AM · need 8:18"; the three goals, the filled marker for yours. In
/// `TonightView` it is one VoiceOver element; on its own (tests) its parts are.
struct TonightTile: View {
    let board: TonightBoard
    var numeralStyle: DotNumeral.Style = .dots
    var reduceTransparency: Bool?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GlowTile(Theme.metricSleep, kind: .hypnogram, minHeight: TonightLayout.tileMinHeight,
                 reduceTransparency: reduceTransparency) {
            VStack(alignment: .leading, spacing: 0) {
                head
                Text("In bed by")
                    .ryftGlowLabelStyle()
                    .padding(.top, TonightLayout.labelGap)
                numeral
                    .padding(.top, TonightLayout.numeralGap)
                Text(board.line)
                    .ryftGlowLabelStyle()
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TonightLayout.lineGap)
                VStack(alignment: .leading, spacing: TonightLayout.goalGap) {
                    ForEach(board.goals) { goalRow($0) }
                }
                .padding(.top, TonightLayout.goalsGap)
            }
        }
    }

    /// "Tonight" and, when the plan is the last one fetched, "As of 5:42 PM" at the end of the line (under it when it
    /// doesn't fit).
    @ViewBuilder private var head: some View {
        let title = Text("Tonight").ryftGlowLabelStyle()
        if let asOf = board.asOf {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title
                    Spacer(minLength: 0)
                    Text(asOf).ryftGlowLabelStyle(.caption).monospacedDigit().lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    Text(asOf).ryftGlowLabelStyle(.caption).monospacedDigit()
                }
            }
        } else {
            title
        }
    }

    /// The bedtime as the numeral (Light from AX1), the meridiem 8 after it on its baseline.
    private var numeral: some View {
        HStack(alignment: .lastTextBaseline, spacing: TonightLayout.meridiemGap) {
            DotNumeral(board.digits, style: numeralStyle, glyphGap: DotNumeral.glyphGapDetail, placeholder: "00:00",
                       accessibilityLabel: Text("Tonight"))
            if let meridiem = board.meridiem {
                Text(meridiem)
                    .ryftGlowLabelStyle()
                    .fixedSize()
            }
        }
    }

    /// The marker (filled for your goal, a ring for the others), "Peak · 100 %" and, at the end, the bedtime in full ink; at
    /// accessibility sizes the bedtime goes under the title.
    @ViewBuilder private func goalRow(_ goal: TonightBoard.Goal) -> some View {
        let title = HStack(alignment: .center, spacing: TonightLayout.markerGap) {
            SleepGoalMarker(isGoal: goal.isGoal)
            Text(goal.title)
                .ryftGlowLabelStyle()
                .fixedSize(horizontal: false, vertical: true)
        }
        let time = Text(goal.time)
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                title
                time.padding(.leading, SleepModesLayout.markerSize + TonightLayout.markerGap)
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                title
                Spacer(minLength: 0)
                time
            }
        }
    }
}

extension TonightView {
    // MARK: not set up, planning

    private var notSetUp: some View {
        outline {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tonight").ryftLabelStyle()
                    .accessibilityAddTraits(.isHeader)
                Text("Tell RYFT when you want to wake up. It tells you when to go to bed, with what today's strain and your sleep debt add.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TonightLayout.outlineGap)
                PillButton(Text("Set up Bedtime & wake"), systemImage: "bed.double") { openSchedule(.setUp) }
                    .accessibilityIdentifier("tonight.setUp")
                    .padding(.top, TonightLayout.pillGap)
            }
        }
    }

    /// The outline with the unlit numeral: the card keeps its place while tonight's plan comes.
    private var planning: some View {
        outline {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tonight").ryftLabelStyle()
                DotNumeral(nil, style: numeralStyle, glyphGap: DotNumeral.glyphGapDetail, placeholder: "00:00",
                           accessibilityLabel: Text(TonightBoard.planningText))
                    .padding(.top, TonightLayout.outlineGap)
                Text(TonightBoard.planningText)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TonightLayout.outlineGap)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Tonight"))
        .accessibilityValue(Text(TonightBoard.planningText))
        .accessibilityIdentifier("tonight.planning")
    }

    private func outline<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(GlowTileSpec.padding(for: .hypnogram))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                PlaceholderOutline(RoundedRectangle(cornerRadius: TonightLayout.outlineRadius, style: .continuous))
            }
    }

    // MARK: offline, failed

    /// "Tonight" as a group's title over the notice: offline (no button, the plan comes once online), or the failure in
    /// calm words with Details and Try again or Sign in.
    @ViewBuilder private var notice: some View {
        if let problem = board.problem {
            VStack(alignment: .leading, spacing: GroupedListSpec.titleGap) {
                GroupTitle(Text("Tonight"))
                // Part of the card, as on Sleep → Bedtime: read in place, not announced.
                InlineMessage(message: problem.message, systemImage: problem.systemImage, retryTitle: problem.action.title,
                              details: problem.details, retry: problem.action.button(retry: retry, signIn: signIn),
                              identifier: "tonight.failure", announces: false)
            }
        }
    }
}

// MARK: - Bedtime & wake

/// Bedtime & wake (§4.13): the wake times first ("Wake up at": the same time on weekdays, or each day, as time chips), the
/// goal, the wind-down, the reminder and the alarm, then Turn off. Every change shows at once and is saved on this iPhone
/// (the planner's `BedtimeScheduleEditor`, one for every way in: 400 ms after the last change, and when the page goes),
/// online or not. A switch iOS refuses stays off with an amber row and Open Settings; an alarm iOS stopped allowing goes back
/// off with the planner's sentence. Turn off asks first, then the page waits, disabled, while the reminders and alarms go.
struct SleepScheduleView: View {
    /// How the page was opened: from a "Set up Bedtime & wake" button, leaving it the first time without a change sets it
    /// up as shown (once: not again after a Turn off elsewhere).
    enum Opening: Hashable, Sendable {
        case edit, setUp
    }

    /// Pushed (Back) or a root page with a title only (the debug screen).
    enum Placement: Sendable {
        case pushed, root
    }

    let planner: BedtimePlanner
    var placement: Placement
    /// Opened from Set up, and not left yet with nothing set up: leaving sets it up. Spent by the first leave, or once
    /// there is a schedule.
    @State private var setsUp: Bool
    @State private var confirmsTurnOff = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init(planner: BedtimePlanner, opening: Opening = .edit, placement: Placement = .pushed) {
        self.planner = planner
        self.placement = placement
        _setsUp = State(initialValue: opening == .setUp)
    }

    private var editor: BedtimeScheduleEditor { planner.editor }
    private var draft: SleepSchedule { editor.draft }

    /// The calendar's own day names, in the user's language, put in Monday-first order.
    private static let weekdayNames: [String] = {
        let symbols = Calendar.current.standaloneWeekdaySymbols
        return Array(symbols[1...]) + [symbols[0]]
    }()

    var body: some View {
        SubpageScaffold(Text("Bedtime & wake"), navigation: placement == .root ? .none : .back()) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                wake
                goal
                windDown
                reminder
                alarm
                last
            }
            .disabled(editor.isTurningOff)
        }
        // iOS stopped allowing the alarm: the planner turned it off.
        .onChange(of: planner.schedule?.alarmOn) { _, on in
            if on == false { editor.alarmWentOff() }
        }
        .onAppear { editor.open() }
        .onDisappear {
            editor.leave(settingUp: setsUp)
            setsUp = false
        }
        .onChange(of: planner.schedule != nil) { _, isSetUp in
            if isSetUp { setsUp = false }
        }
    }

    // MARK: wake

    private var wake: some View {
        GroupedCard(Text("Wake up at")) {
            GroupedRow.toggle(Text("Same time on weekdays"), identifier: "schedule.sameOnWeekdays",
                              isOn: Binding(get: { draft.sameOnWeekdays }, set: { on in
                                  // The seven days open without animation under Reduce Motion.
                                  withAnimation(Theme.Motion.respecting(reduceMotion)) {
                                      editor.edit { $0.setSameOnWeekdays(on) }
                                  }
                              }))
            if draft.sameOnWeekdays {
                timeRow(Text("Weekdays"), index: 0) { $0.setWeekdays($1) }
                timeRow(Text("Weekend"), index: 5) { $0.setWeekend($1) }
            } else {
                ForEach(0..<7, id: \.self) { i in
                    timeRow(Text(verbatim: Self.weekdayNames[i]), index: i) { $0.wake[i] = $1 }
                }
            }
        }
    }

    /// A day's wake time as a time chip (the system's compact picker over it); from AX1 under its title.
    private func timeRow(_ title: Text, index: Int,
                         set: @escaping (inout SleepSchedule, String) -> Void) -> some View {
        ValueChipRow(title) {
            ValueChip(title, date: Binding(get: { SleepSchedule.date(draft.wake[index], on: .now) },
                                           set: { date in editor.edit { set(&$0, SleepPlannerViewModel.hhmm(date)) } }),
                      displayedComponents: .hourAndMinute)
        }
    }

    // MARK: goal

    private var goal: some View {
        GroupedCard(Text("Aim for")) {
            ForEach(SleepSchedule.Goal.allCases) { goal in
                GroupedRow.select(Text(goal.title), detail: Text(SleepBedtimeBoard.share(goal)),
                                  isSelected: draft.goal == goal, identifier: "schedule.goal.\(goal.rawValue)") {
                    editor.edit { $0.goal = goal }
                }
            }
        }
    }

    // MARK: wind down

    private var windDown: some View {
        let minutes = Binding(get: { draft.windDownMin }, set: { new in editor.edit { $0.windDownMin = new } })
        return GroupedCard(Text("Wind down")) {
            if typeSize.isAccessibilitySize {
                // Segments would cut their titles: a menu row.
                GroupedRow.menu(Text("Remind me before bedtime"), value: Text(Self.minutes(draft.windDownMin)),
                                identifier: "schedule.windDown") {
                    Picker(selection: minutes) {
                        ForEach(SleepSchedule.windDownChoices, id: \.self) { Text(Self.minutes($0)).tag($0) }
                    } label: {
                        Text("Remind me before bedtime")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: GroupedListSpec.rowSpacing) {
                    Text("Remind me before bedtime")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    SegmentedPicker(selection: minutes, options: SleepSchedule.windDownChoices, look: .inkFill) {
                        Self.minutes($0)
                    }
                }
                .padding(.horizontal, GroupedListSpec.rowInset)
                .padding(.vertical, TonightLayout.windDownPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .groupedRowHairline()
                .accessibilityElement(children: .contain)
            }
        }
    }

    /// "30 min".
    private static func minutes(_ value: Int) -> String { String(localized: "\(value) min") }

    // MARK: reminder, alarm

    private var reminder: some View {
        GroupedCard(Text("Bedtime reminder")) {
            GroupedRow.toggle(Text("Remind me to wind down"),
                              detail: Text("A notification \(draft.windDownMin) min before tonight's bedtime. It moves with your day."),
                              identifier: "schedule.reminder",
                              isOn: Binding(get: { draft.reminderOn }, set: { on in
                                  Task {
                                      let allowed = await editor.setReminder(on)
                                      if !allowed { announceRefusal() }
                                  }
                              }))
            if editor.reminderRefused {
                refused(systemImage: "bell.slash", identifier: "schedule.reminder.refused")
            } else if draft.reminderOn, planner.remindersWaiting {
                // No plan yet, and none to estimate one from: the reminder isn't set, and the page says so.
                ScheduleNoticeRow(message: Self.remindersWaiting, systemImage: "bell.slash", tone: .neutral,
                                  identifier: "schedule.reminder.waiting")
            }
        }
    }

    private var alarm: some View {
        GroupedCard(Text("Wake-up alarm")) {
            GroupedRow.toggle(Text("Wake me at my wake time"),
                              detail: Text(planner.alarmsRing
                                           ? "A real alarm: it rings in Silent mode and Focus, with Stop and Snooze."
                                           : "A notification at your wake time. It won't ring like an alarm on this iOS version."),
                              identifier: "schedule.alarm",
                              isOn: Binding(get: { draft.alarmOn }, set: { on in
                                  Task {
                                      let allowed = await editor.setAlarm(on)
                                      if !allowed { announceRefusal() }
                                  }
                              }))
            if editor.alarmRefused {
                refused(systemImage: "alarm", identifier: "schedule.alarm.refused")
            } else if let problem = planner.alarmProblem {
                ScheduleNoticeRow(message: Text(problem), systemImage: "alarm", identifier: "schedule.alarm.problem")
            }
        }
    }

    // swiftlint:disable:next line_length
    private static var remindersWaiting: Text { Text("Reminders resume once RYFT has tonight's plan.", comment: "Bedtime & wake, under the reminder: no plan for the wake time yet (offline, or it couldn't load) and none from before, so no reminder is set.") }

    /// VoiceOver hears why the switch stayed off.
    private func announceRefusal() {
        AccessibilityNotification.Announcement(String(localized: "Not allowed in iOS Settings.")).post()
    }

    /// iOS said no: an amber row, and where to change it.
    private func refused(systemImage: String, identifier: String) -> some View {
        ScheduleNoticeRow(message: Text("Not allowed in iOS Settings."), systemImage: systemImage, identifier: identifier) {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }

    // MARK: turn off

    /// Turn off asks first: the system dialog, anchored on the row (iOS 26 draws it as a popover from its source), its
    /// title and destructive button only; what goes is the group's footer, there before the tap and at any text size.
    /// While the reminders and alarms go the row says so and the page takes no changes. The page's last line says there
    /// is no Save button.
    @ViewBuilder private var last: some View {
        if planner.schedule != nil || editor.isTurningOff {
            GroupedCard(footer: Self.turnOffFooter) {
                GroupedRow.destructive(editor.isTurningOff
                                       ? Text("Turning off…", comment: "Bedtime & wake's Turn off row while it turns off.")
                                       : Text("Turn off Bedtime & wake"),
                                       busy: editor.isTurningOff, identifier: "schedule.turnOff") {
                    confirmsTurnOff = true
                }
                .confirmationDialog(Text("Turn off Bedtime & wake?",
                                         comment: "Bedtime & wake: the confirmation before Turn off."),
                                    isPresented: $confirmsTurnOff, titleVisibility: .visible) {
                    Button(role: .destructive) {
                        turnOff()
                    } label: {
                        Text("Turn off", comment: "Bedtime & wake's confirmation: turns it off.")
                    }
                    .accessibilityIdentifier("schedule.turnOff.confirm")
                    Button(role: .cancel) {} label: {
                        Text("Cancel")
                    }
                }
            }
        }
        GroupFooter(Text("Changes save as you make them.",
                         comment: "Footer at the end of Bedtime & wake: there is no Save button."))
    }

    /// Under Turn off: what it removes and stops.
    static var turnOffFooter: Text {
        Text("Your wake times, goal and wind-down are removed from this iPhone, and the bedtime reminder and the wake-up alarm stop.",
             comment: "Bedtime & wake: the footer under Turn off, what turning it off removes and stops.")
    }

    private func turnOff() {
        Task {
            await editor.turnOff()
            switch placement {
            case .pushed: dismiss()
            // Nothing to go back to: the page stays, not set up, and takes changes again.
            case .root: editor.open()
            }
        }
    }
}

/// A row at the end of a group (Bedtime & wake's reminder and alarm), its glyph and its sentence (§2.3: a tone never
/// alone): amber where something needs the user (a switch iOS refused, an alarm iOS stopped allowing), neutral where it
/// only says what's true (the reminder waits for a plan). "Open Settings ↗" on its own line under the sentence when iOS
/// Settings is where to change it, so the sentence keeps its line. VoiceOver reads the sentence, then the link.
private struct ScheduleNoticeRow: View {
    enum Tone {
        case attention, neutral
    }

    let message: Text
    let systemImage: String
    var tone = Tone.attention
    let identifier: String
    var openSettings: (() -> Void)?

    /// The glyph grows with the sentence, as `InlineMessage`'s does.
    @ScaledMetric(relativeTo: .callout) private var glyphSize = InlineMessageSpec.glyphSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: InlineMessageSpec.glyphGap) {
                Image(systemName: systemImage)
                    .font(.system(size: glyphSize))
                    .foregroundStyle(tone == .attention ? Theme.warning : Theme.textSecondary)
                    .accessibilityHidden(true)
                message
                    .font(.ryft(.callout))
                    .foregroundStyle(tone == .attention ? Theme.warning : Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier)
            }
            if let openSettings {
                Button(action: openSettings) {
                    HStack(spacing: 4) {
                        Text("Open Settings")
                        Image(systemName: PillButton.Icon.linkOut)
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                }
                .ryftLink()
                .fixedSize()
                .accessibilityHint(GroupedRow.outsideLinkHint)
                .accessibilityIdentifier("\(identifier).openSettings")
            }
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, GroupedListSpec.textPadding / 2)
        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
        .groupedRowHairline()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - previews (dark only)

/// Tonight in each of its states, from boards on the mock plan in the preview's locale (previews; the shots use the real
/// planner).
@MainActor
enum TonightPreview {
    static let alarmProblem = "The wake-up alarm is off: iOS doesn't allow RYFT's alarms. Turn it on again to allow them."

    static func board(_ look: TonightBoard.Look, cached: Bool = false, alarm: Bool = false,
                      locale: Locale) -> TonightBoard {
        let plan = MockJournal.sleepPlan(wake: "06:30")
        switch look {
        case .planned:
            return TonightBoard(schedule: .default, plan: plan, asOf: cached ? .now.addingTimeInterval(-3_600) : nil,
                                alarmProblem: alarm ? alarmProblem : nil, locale: locale)
        case .notSetUp:
            return TonightBoard(schedule: nil, plan: nil, locale: locale)
        case .planning:
            return TonightBoard(schedule: .default, plan: nil, locale: locale)
        case .offline:
            return TonightBoard(schedule: .default, plan: nil, problem: .offline, isOnline: false, locale: locale)
        case .failed:
            let failure = SleepLoadFailure(APIError.http(503, "", requestID: "01JD8K2V9Q7M3X"), isOnline: true, at: .now)
            return TonightBoard(schedule: .default, plan: nil, problem: .failed(failure), locale: locale)
        }
    }

    static func page(_ look: TonightBoard.Look, cached: Bool = false, alarm: Bool = false,
                     size: DynamicTypeSize = .large) -> some View {
        NavigationStack {
            ScrollView {
                Page(look: look, cached: cached, alarm: alarm)
                    .padding(.horizontal, Theme.Metrics.screenPadding)
                    .padding(.vertical, 16)
            }
            .background(Theme.background.ignoresSafeArea())
        }
        .previewEnvironment()
        .dynamicTypeSize(size)
    }

    /// The board in the environment's locale, as `TonightCard` builds it.
    private struct Page: View {
        let look: TonightBoard.Look
        let cached: Bool
        let alarm: Bool
        @Environment(\.locale) private var locale

        var body: some View {
            TonightView(board: TonightPreview.board(look, cached: cached, alarm: alarm, locale: locale), retry: {})
        }
    }
}

#Preview("Tonight") { TonightPreview.page(.planned) }
#Preview("Tonight · as of, alarm off") { TonightPreview.page(.planned, cached: true, alarm: true) }
#Preview("Tonight · not set up") { TonightPreview.page(.notSetUp) }
#Preview("Tonight · planning") { TonightPreview.page(.planning) }
#Preview("Tonight · offline") { TonightPreview.page(.offline) }
#Preview("Tonight · failed") { TonightPreview.page(.failed) }
#Preview("Tonight · AX3") { TonightPreview.page(.planned, cached: true, size: .accessibility3) }

@MainActor
private func schedulePreview(_ schedule: SleepSchedule?, alarmsAllowed: Bool = true, online: Bool = true,
                             turningOff: Bool = false, size: DynamicTypeSize = .large) -> some View {
    // Offline is an account's: demo data plans on the phone, with no network to lose. So are a refused alarm and Turn off
    // on its way: demo data sets and takes away no alarm.
    let account = !online || !alarmsAllowed || turningOff
    let state = account ? AppState(env: .test(clock: TestClock(now: .now), flags: [.sleepPlanner: true], online: online))
        : AppState.preview(flags: [.sleepPlanner: true])
    if account { state.user = MockData.user }
    let planner: BedtimePlanner
    let stuck = turningOff ? StuckWakeAlarms() : nil
    if let stuck {
        planner = BedtimePlanner(state: state, alarms: stuck)
    } else {
        let alarms = MockWakeAlarms()
        alarms.allowed = alarmsAllowed
        planner = BedtimePlanner(state: state, alarms: alarms)
    }
    return SchedulePreview(planner: planner, schedule: schedule, turningOff: stuck)
        .previewEnvironment(state)
        .toggleStyle(.ryft)
        .dynamicTypeSize(size)
}

/// The page once the planner has the schedule: it starts from the planner's (the page edits a copy).
private struct SchedulePreview: View {
    let planner: BedtimePlanner
    let schedule: SleepSchedule?
    /// Turn off started and held: the page as it waits.
    var turningOff: StuckWakeAlarms?
    @State private var ready = false

    var body: some View {
        NavigationStack {
            if ready { SleepScheduleView(planner: planner) } else { Theme.background.ignoresSafeArea() }
        }
        .task {
            if let schedule { await planner.update(schedule) }
            ready = true
            if let turningOff {
                turningOff.sticks = true
                await planner.editor.turnOff()
            }
        }
    }
}

/// Wake alarms whose taking-away doesn't finish once `sticks`: Turn off stays on its way (previews).
private final class StuckWakeAlarms: WakeAlarms {
    let ringsLikeAnAlarm = true
    var sticks = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func authorize() async -> Bool { true }
    func isAllowed() async -> Bool { true }
    func schedule(_ times: [String]) async throws {}
    func cancelAll() async {
        guard sticks else { return }
        await withCheckedContinuation { waiting.append($0) }
    }
}

private extension SleepSchedule {
    /// Each day on its own, Friday later.
    static var eachDay: SleepSchedule {
        var schedule = SleepSchedule.default
        schedule.sameOnWeekdays = false
        schedule.wake[4] = "07:15"
        schedule.reminderOn = true
        return schedule
    }

    static var withAlarm: SleepSchedule {
        var schedule = SleepSchedule.default
        schedule.alarmOn = true
        return schedule
    }

    static var withReminder: SleepSchedule {
        var schedule = SleepSchedule.default
        schedule.reminderOn = true
        return schedule
    }
}

#Preview("Bedtime & wake") { schedulePreview(.default) }
#Preview("Bedtime & wake · not set up") { schedulePreview(nil) }
#Preview("Bedtime & wake · each day") { schedulePreview(.eachDay) }
#Preview("Bedtime & wake · alarm not allowed") { schedulePreview(.withAlarm, alarmsAllowed: false) }
#Preview("Bedtime & wake · reminders wait for a plan") { schedulePreview(.withReminder, online: false) }
#Preview("Bedtime & wake · turning off") { schedulePreview(.withAlarm, turningOff: true) }
#Preview("Bedtime & wake · AX3") { schedulePreview(.eachDay, size: .accessibility3) }
