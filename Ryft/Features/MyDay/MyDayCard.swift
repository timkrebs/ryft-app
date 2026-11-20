import SwiftUI

extension TrainSyncService {
    /// What changes when a session is finished or discarded (the outbox's count) and when the platform answers a
    /// finish (`lastCompletion`). `TrainStore` isn't observable, so My Day reads this to show a new session at once.
    struct SessionsMark: Equatable {
        let pending: Int
        let completed: UUID?
    }

    var sessionsMark: SessionsMark { SessionsMark(pending: pendingCount, completed: lastCompletion?.id) }
}

/// What a My Day row, header or button does; the live card and screen fill it, previews leave it empty. An entry
/// that's nil isn't offered (its flag is off, or the day is too far back).
struct MyDayActions {
    /// The full screen (the card's title and "Show all").
    var openDay: () -> Void = {}
    /// A row: sleep opens Sleep, a workout its detail, a session Train's, an activity its own (design.md §7.3).
    var open: (MyDayItem) -> Void = { _ in }
    /// ＋ and the button under the list: Add activity (`activities.manual`, the last 14 days).
    var addActivity: (() -> Void)?
    /// ＋ and "No sleep recorded · Add sleep" (`activities.manual`, while the day has no night).
    var addSleep: (() -> Void)?
    /// ＋ → Start strength workout (the shipped Train flow; `train.enabled`, today).
    var startStrength: (() -> Void)?
    /// A row's Edit and Delete (manual and recorded activities, a night the user added).
    var edit: ((MyDayItem) -> Void)?
    var delete: ((MyDayItem) -> Void)?
    /// Try again (the stale caption, the error, offline).
    var retry: () async -> Void = {}
    /// Retry on a row whose upload failed (R4): the uploader sends the activity or the night now.
    var retryRow: ((MyDayItem) -> Void)?

    /// ＋ has something to offer.
    var hasAddEntries: Bool { addActivity != nil || addSleep != nil || startStrength != nil }

    /// A row's Retry: only on a failed upload, and only where the uploader is wired.
    func rowRetry(for item: MyDayItem) -> (() -> Void)? {
        guard let retryRow, ActivityStateMark.State(item).isFailed else { return nil }
        return { retryRow(item) }
    }

    /// Every entry offered, and a failed row's Retry, doing nothing (previews).
    static let preview = MyDayActions(addActivity: {}, addSleep: {}, startStrength: {}, retryRow: { _ in })
}

/// My Day on Today (ui.md §2.1, design.md §7.1): always today. Loads on Today's refreshes, opens the full screen
/// and the rows' details in Today's stack.
struct MyDayCard: View {
    let model: MyDayViewModel

    @Environment(ScreenModels.self) private var screens
    @Environment(AppState.self) private var state
    @Environment(TrainCoordinator.self) private var coordinator
    @State private var showsDay = false
    @State private var workout: Workout?
    @State private var session: UUID?
    @State private var activity: ActivityRoute?
    @State private var adding: AddActivityModel?
    @State private var sleeping: AddSleepModel?
    /// `-RyftOpenMyDay <days back>` opens the full screen once on that day (Debug, screenshots and UI tests).
    @State private var autoOpen = MyDayCard.requestedDaysBack

    /// Today's content. Train's sessions are in a store SwiftUI doesn't observe: reading the sync's mark here
    /// re-renders the card when one finishes.
    private var content: MyDayContent {
        _ = coordinator.sync.sessionsMark
        return model.card
    }

    var body: some View {
        let content = content
        MyDayCardBody(content: content, actions: actions(content))
            .navigationDestination(isPresented: $showsDay) { MyDayView(model: model) }
            .navigationDestination(item: $workout) { WorkoutDetailView(workout: $0) }
            .navigationDestination(item: $session) { SessionDetailView(sessionID: $0).trainDestinations() }
            .navigationDestination(item: $activity) { ActivityDetailView(route: $0) }
            .sheet(item: $adding) { AddActivitySheet(model: $0).presentedRoot() }
            .sheet(item: $sleeping) { AddSleepSheet(model: $0).presentedRoot() }
            // Again when the iPhone is back online: offline nothing was read (B §11).
            .task(id: LoadKey(refreshed: state.lastUpdated, online: state.env.connectivity.isOnline)) {
                await model.load(model.today)
                if let back = autoOpen {
                    autoOpen = nil
                    model.select(DayFormat.shift(model.today, days: -back))
                    showsDay = true
                }
            }
    }

    private struct LoadKey: Equatable {
        let refreshed: Date?
        let online: Bool
    }

    private func actions(_ content: MyDayContent) -> MyDayActions {
        let today = model.today
        return MyDayActions(openDay: {
            model.select(today)
            showsDay = true
        }, open: { item in
            MyDayCard.open(item, on: today, model: model, router: screens.router, show: show)
        }, addActivity: model.canAdd(on: today) ? { adding = model.addActivityModel(on: today) } : nil,
        addSleep: model.offersAddSleep(on: today, content: content) ? { sleeping = model.addSleepModel(on: today) } : nil,
        startStrength: model.showsTrain ? { Task { await coordinator.quickStart(.auto) } } : nil,
        retry: {
            await model.load(today, force: true)
        }, retryRow: { item in
            Task { await model.retryUpload(item) }
        })
    }

    private func show(_ destination: MyDayDestination) {
        switch destination {
        case .workout(let w): workout = w
        case .session(let id): session = id
        case .activity(let route): activity = route
        }
    }

    /// Where a row leads in the stack (the Sleep tab is the router's).
    enum MyDayDestination {
        case workout(Workout), session(UUID), activity(ActivityRoute)
    }

    /// Sleep → the Sleep tab on that night; a workout → its detail; a session → Train's; an activity → its own
    /// (a merged one links its tracker's workout there).
    static func open(_ item: MyDayItem, on day: Date, model: MyDayViewModel, router: DeepLinkRouter,
                     show: (MyDayDestination) -> Void) {
        switch item.kind {
        case .sleep:
            Task { await router.open(.sleep(day)) }
        case .workout(let id):
            if let w = model.workout(id, on: day) { show(.workout(w)) }
        case .session(let id):
            show(.session(id))
        case .activity(let id):
            if item.opensDetail { show(.activity(ActivityRoute(id: id, day: day))) }
        case .missingSleep:
            break
        }
    }

    private static var requestedDaysBack: Int? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "RyftOpenMyDay").flatMap(Int.init).map { abs($0) }
        #else
        nil
        #endif
    }
}

/// The card itself, from a day's content (PR 6 B §9.1, `b-17`): the header ("My Day" over the day's summary, the plus menu),
/// up to five rows in the card style with hairlines between them (the missing night is the dashed row), "Show all", the Add
/// activity pill, the stale caption. Loading is three outline rows; nothing today says so; a failed read, or nothing
/// cached while offline, is an `InlineMessage` with Try again.
struct MyDayCardBody: View {
    let content: MyDayContent
    var actions = MyDayActions()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                header
                list
                    .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: content.cardRows.map(\.id))
                if showsAll { showAll }
                if let add = actions.addActivity {
                    PillButton(Text("Add activity"), style: .secondary) { add() }
                        .accessibilityIdentifier("myday.addActivity")
                        .padding(.top, showsAll ? MyDayLayout.addGapUnderShowAll : MyDayLayout.addGap)
                }
                if let since = content.staleSince {
                    MyDayStaleLine(since: since, offersRetry: content.offersRetry, retry: actions.retry)
                        .padding(.top, MyDayLayout.staleGap)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("myday.card")
    }

    /// "Show all" opens the full screen whenever the day has activities (the card shows at most five rows).
    private var showsAll: Bool { content.phase == .ready && !content.hasNoActivities }

    // MARK: header

    /// The title block is one button (one VoiceOver element, a header): "My Day" over "3 activities · 2h 13m · 6.8 mi"; the
    /// plus menu beside it, its circle on the card's inset.
    private var header: some View {
        HStack(alignment: .center, spacing: ScreenHeaderSpec.minGap) {
            Button(action: actions.openDay) {
                VStack(alignment: .leading, spacing: MyDayLayout.headerSubtitleGap) {
                    Text("My Day", comment: "The card and screen with the day's sleep, workouts and activities.")
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.textPrimary)
                    if content.phase == .ready, let summary = content.summary {
                        Text(verbatim: summary)
                            .font(.ryft(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: MyDayLayout.headerHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("My Day, \(content.day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)))",
                                     comment: "VoiceOver: the My Day card's title and its date."))
            .accessibilityValue(Text(verbatim: content.phase == .ready ? content.spokenSummary(locale: locale) ?? "" : ""))
            .accessibilityHint(Text("Opens the list", comment: "VoiceOver: the My Day card's title opens the full screen."))
            .accessibilityAddTraits([.isHeader, .isButton])
            .accessibilityIdentifier("myday.title")
            if actions.hasAddEntries {
                MyDayAddMenu(actions: actions)
                    .padding(-ScreenHeaderSpec.buttonOverhang)
            }
        }
    }

    // MARK: list

    @ViewBuilder
    private var list: some View {
        switch content.phase {
        case .loading:
            MyDaySkeleton(rows: MyDayLayout.placeholderRows)
                .padding(.top, MyDayLayout.stateGap)
        case .failed:
            MyDayFailedMessage(retry: actions.retry)
                .padding(.top, MyDayLayout.stateGap)
        case .offline:
            MyDayOfflineMessage(retry: actions.retry)
                .padding(.top, MyDayLayout.stateGap)
        case .ready:
            VStack(alignment: .leading, spacing: 0) {
                let rows = content.cardRows
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { MyDayRowSeparator(dashed: item.kind.isMissingSleep || rows[index - 1].kind.isMissingSleep) }
                    row(item)
                        .padding(.top, index == 0 && item.kind.isMissingSleep ? MyDayLayout.dashedRowGap : 0)
                        .transition(.opacity)
                }
                if content.hasNoActivities {
                    let afterDashed = rows.last?.kind.isMissingSleep == true
                    if !rows.isEmpty { MyDayRowSeparator(dashed: afterDashed) }
                    MyDayEmptyLine(isToday: true)
                        .padding(.top, rows.isEmpty ? MyDayLayout.emptyTopAlone
                                     : afterDashed ? MyDayLayout.emptyPadding - MyDayRowSeparator.gap : MyDayLayout.emptyPadding)
                        .accessibilityIdentifier("myday.empty")
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: MyDayItem) -> some View {
        let retry = actions.rowRetry(for: item)
        if item.opensDetail {
            Button { actions.open(item) } label: { MyDayRow(item: item, retry: retry) }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(item.hint ?? Text(verbatim: ""))
                .myDayRowRetry(retry)
                .accessibilityIdentifier("myday.row.\(item.id)")
        } else {
            MyDayRow(item: item, retry: retry, addSleep: actions.addSleep)
                .myDayRowRetry(retry)
                .accessibilityIdentifier(item.kind.isMissingSleep ? "myday.noSleep" : "myday.row.\(item.id)")
        }
    }

    /// "Show all" and a chevron on a 46 pt row under a hairline: opens the full screen.
    private var showAll: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: Theme.Metrics.hairline)
                .accessibilityHidden(true)
            Button(action: actions.openDay) {
                HStack(spacing: GroupedListSpec.rowSpacing) {
                    Text("Show all")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: GroupedListSpec.chevronSize, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(GroupedListSpec.accessoryOpacity))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: MyDayLayout.showAllHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("myday.showAll")
        }
    }
}

/// Nothing cached and the read failed (or was held back): "Couldn't load My Day." with Try again.
struct MyDayFailedMessage: View {
    var retry: () async -> Void = {}

    var body: some View {
        InlineMessage(message: String(localized: "Couldn't load My Day.", comment: "My Day: nothing cached and the read failed."),
                      retry: retry, identifier: "myday.failed")
    }
}

/// Nothing cached and offline: a calm line, no outlines (they would wait for good), and Try again.
struct MyDayOfflineMessage: View {
    var retry: () async -> Void = {}

    var body: some View {
        InlineMessage(message: String(localized: "My Day appears once you're online.",
                                      comment: "My Day: offline with nothing saved on this iPhone for the day yet."),
                      systemImage: "wifi.slash", retry: retry, identifier: "myday.offline")
    }
}

extension View {
    /// VoiceOver's "Retry" on the element a My Day row is (its button, or the row itself): the row speaks as one
    /// element, so its Retry link is reached as an action (B §9.1).
    @ViewBuilder
    func myDayRowRetry(_ retry: (() -> Void)?) -> some View {
        if let retry {
            accessibilityActions {
                Button(String(localized: "Retry", comment: "My Day: send a failed upload again."), action: retry)
            }
        } else {
            self
        }
    }
}

/// Between two card rows: a hairline (`separator`); next to the dashed missing night, 8 pt of space instead (an outline
/// beside a hairline would draw the edge twice).
struct MyDayRowSeparator: View {
    let dashed: Bool

    /// The space beside the dashed row.
    nonisolated static let gap: CGFloat = 8

    var body: some View {
        if dashed {
            Color.clear.frame(height: Self.gap)
                .accessibilityHidden(true)
        } else {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: Theme.Metrics.hairline)
                .accessibilityHidden(true)
        }
    }
}

/// A day without activities: "Nothing logged yet today." on today; "Nothing recorded on this day" and what may still come on
/// a past day. Calm `textSecondary`, never an alarm.
struct MyDayEmptyLine: View {
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isToday {
                Text("Nothing logged yet today.", comment: "My Day: no workouts or activities today yet.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Nothing recorded on this day", comment: "My Day: a past day without sleep, workouts or activities.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Anything your tracker syncs later will appear here.",
                     comment: "My Day: under 'Nothing recorded on this day'.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension MyDayContent {
    /// The summary as VoiceOver reads it: "3 activities, 2 hours 13 minutes, 6.8 miles"; nil without activities.
    func spokenSummary(locale: Locale) -> String? {
        let list = activities
        guard !list.isEmpty else { return nil }
        var parts = [String(localized: "\(list.count) activities", comment: "My Day: how many workouts and activities a day has.")]
        let duration = list.map(\.duration).reduce(0, +)
        if duration >= 60 { parts.append(Fmt.spokenDuration(minutes: Int((duration / 60).rounded()), locale: locale)) }
        let distance = list.compactMap(\.distanceM).reduce(0, +)
        if distance > 0 {
            parts.append(Measurement(value: distance, unit: UnitLength.meters)
                .formatted(.measurement(width: .wide, usage: .road, numberFormatStyle: .number.precision(.fractionLength(1)))
                    .locale(locale)))
        }
        return parts.joined(separator: ", ")
    }
}

extension MyDayItem {
    /// VoiceOver: what tapping the row does; nil for rows that open nothing.
    var hint: Text? {
        guard opensDetail else { return nil }
        switch kind {
        case .sleep: return Text("Opens Sleep")
        case .workout: return Text("Opens the workout", comment: "VoiceOver hint: the row opens the workout's detail.")
        case .activity: return Text("Opens the activity", comment: "VoiceOver hint: a My Day row opens the activity's detail.")
        case .session: return Text("Opens the session", comment: "VoiceOver: a My Day row opens the Train session.")
        case .missingSleep: return nil
        }
    }
}

/// ＋: what can be added to the day (ui.md §2.1; PR 6 B §9): Add activity, Start strength workout, Add sleep; Start activity
/// joins with A4. Only the entries offered. A menu, so a `CircleButton` (a button) can't be it: the label draws the circle
/// button's look from its numbers (a 40 pt outlined circle in a 44 pt box, the 14 pt glyph), as the live workout's More does.
struct MyDayAddMenu: View {
    let actions: MyDayActions

    var body: some View {
        Menu {
            if let add = actions.addActivity {
                Button(action: add) { Label("Add activity", systemImage: "square.and.pencil") }
                    .accessibilityIdentifier("myday.add.activity")
            }
            if let start = actions.startStrength {
                Button(action: start) { Label("Start strength workout", systemImage: "dumbbell") }
                    .accessibilityIdentifier("myday.add.strength")
            }
            if let sleep = actions.addSleep {
                Button(action: sleep) { Label("Add sleep", systemImage: "bed.double") }
                    .accessibilityIdentifier("myday.add.sleep")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: CircleButton.iconSize, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: CircleButton.diameter, height: CircleButton.diameter)
                .overlay {
                    Circle().strokeBorder(Theme.textPrimary.opacity(CircleButton.borderOpacity), lineWidth: Theme.Metrics.hairline)
                }
                .frame(width: CircleButton.hitSize, height: CircleButton.hitSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Add", comment: "VoiceOver: My Day's plus menu (Add activity, Add sleep, Start strength workout)."))
        .accessibilityShowsLargeContentViewer {
            Label { Text("Add", comment: "VoiceOver: My Day's plus menu (Add activity, Add sleep, Start strength workout).") } icon: {
                Image(systemName: "plus")
            }
        }
        .accessibilityIdentifier("myday.add")
    }
}

/// "Showing the list from 14:05" in `caption` `textSecondary`, and after two minutes "Try again" (ui.md §2.1 M5), a text
/// button 44 high in the link's ink: quiet, never red. From AX1 Try again goes under the words.
struct MyDayStaleLine: View {
    let since: Date
    var offersRetry = false
    var retry: () async -> Void = {}

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var retrying = false

    var body: some View {
        // From AX1 Try again goes under the words (B §12): beside them it would squeeze the time into a column.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: MyDayLayout.staleRetryGap))
        layout {
            Text("Showing the list from \(Fmt.time(since, locale: locale))",
                 comment: "My Day: the list is the last one loaded; the time it was loaded.")
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if offersRetry {
                Button {
                    Task {
                        retrying = true
                        await retry()
                        retrying = false
                    }
                } label: {
                    Text("Try again")
                }
                .ryftLink()
                .disabled(retrying)
                .accessibilityIdentifier("myday.stale.retry")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("myday.stale")
    }
}

/// Three outline rows while nothing is cached (ui.md §2.1 M4; B §1.5): the activity row's outline (`ActivityListRowPlaceholder`),
/// 8 apart; no pulse, no spinner. VoiceOver hears "Loading My Day" once.
struct MyDaySkeleton: View {
    var rows = MyDayLayout.placeholderRows

    var body: some View {
        VStack(spacing: MyDayLayout.placeholderSpacing) {
            ForEach(0..<rows, id: \.self) { _ in ActivityListRowPlaceholder() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading My Day", comment: "VoiceOver: My Day's outline rows while nothing is cached."))
        .accessibilityIdentifier("myday.loading")
    }
}

// MARK: - previews (dark only)

/// The card's states: rows, over the cap, nothing yet, the missing night with and without rows, loading, stale, failed.
private struct MyDayCardPreviewStates: View {
    let cases: [MockMyDay.Case]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(Array(cases.enumerated()), id: \.offset) { _, c in
                    MyDayCardBody(content: MockMyDay.content(c), actions: .preview)
                }
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background)
    }
}

#Preview("My Day card · states") {
    MyDayCardPreviewStates(cases: [.populated, .full, .nothing, .noSleepNothing, .noSleepRows, .loading, .stale, .failed])
        .preferredColorScheme(.dark)
}

#Preview("My Day card · offline") {
    ScrollView {
        MyDayCardBody(content: MyDayContent(day: MockMyDay.today, isToday: true, phase: .offline, items: []), actions: .preview)
            .padding(Theme.Metrics.screenPadding)
    }
    .background(Theme.background)
    .preferredColorScheme(.dark)
}

#Preview("My Day card · AX3") {
    MyDayCardPreviewStates(cases: [.populated, .noSleepNothing, .stale])
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}

/// The live card on the preview environment's own model (`screens.myDay`), loading from the mock platform.
private struct MyDayCardHost: View {
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        NavigationStack {
            ScrollView { MyDayCard(model: screens.myDay).padding(20) }
                .background(Theme.background)
        }
    }
}

#Preview("My Day card · live") {
    MyDayCardHost().previewEnvironment(.preview(flags: [.todayMyDay: true]))
}
