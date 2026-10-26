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
    /// The full screen (the card's title, expand and "Show all").
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
    /// Try again (the stale caption, the error).
    var retry: () async -> Void = {}

    /// ＋ has something to offer.
    var hasAddEntries: Bool { addActivity != nil || addSleep != nil || startStrength != nil }

    /// Every entry offered, doing nothing (previews).
    static let preview = MyDayActions(addActivity: {}, addSleep: {}, startStrength: {})
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
            .sheet(item: $adding) { AddActivitySheet(model: $0) }
            .sheet(item: $sleeping) { AddSleepSheet(model: $0) }
            .task(id: state.lastUpdated) {
                await model.load(model.today)
                if let back = autoOpen {
                    autoOpen = nil
                    model.select(DayFormat.shift(model.today, days: -back))
                    showsDay = true
                }
            }
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

/// The card itself, from a day's content: header with ＋, up to five rows, "Show all", Add activity, the stale
/// caption.
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
                    .padding(.top, 10)
                    .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: content.cardRows.map(\.id))
                if content.phase == .ready, content.showsAll { showAll }
                if let add = actions.addActivity { addButton(add) }
                if let since = content.staleSince {
                    MyDayStaleLine(since: since, offersRetry: content.offersRetry, retry: actions.retry)
                        .padding(.top, 6)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("myday.card")
    }

    // MARK: header

    /// The title block and expand are one button (one VoiceOver element); ＋ sits beside it, 8 pt apart.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: actions.openDay) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My Day", comment: "The card and screen with the day's sleep, workouts and activities.")
                            .font(.ryft(.headline))
                            .foregroundStyle(Theme.textPrimary)
                        Text(verbatim: content.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale)))
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("My Day, \(content.day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)))",
                                     comment: "VoiceOver: the My Day card's title and its date."))
            .accessibilityHint(Text("Opens the list", comment: "VoiceOver: the My Day card's title opens the full screen."))
            .accessibilityAddTraits([.isHeader, .isButton])
            .accessibilityIdentifier("myday.title")
            if actions.hasAddEntries {
                MyDayAddMenu(actions: actions)
            }
        }
    }

    // MARK: list

    @ViewBuilder
    private var list: some View {
        switch content.phase {
        case .loading:
            MyDaySkeleton(rows: 2, style: .card)
        case .failed:
            InlineMessage(message: String(localized: "Couldn't load My Day.", comment: "My Day: nothing cached and the read failed."),
                          retry: actions.retry, identifier: "myday.failed")
        case .ready:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(content.cardRows.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: Theme.Metrics.hairline)
                            .padding(.vertical, 5)
                            .accessibilityHidden(true)
                    }
                    row(item)
                        .transition(.opacity)
                }
                if content.hasNoActivities {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing yet today", comment: "My Day card: no workouts or activities today.")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                        if actions.addActivity != nil {
                            Text("Add what you did.", comment: "My Day card: under 'Nothing yet today' when activities can be added.")
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.top, content.items.isEmpty ? 0 : 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("myday.empty")
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: MyDayItem) -> some View {
        if item.opensDetail {
            Button { actions.open(item) } label: { MyDayRow(item: item) }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(item.hint ?? Text(verbatim: ""))
                .accessibilityIdentifier("myday.row.\(item.id)")
        } else {
            MyDayRow(item: item, addSleep: actions.addSleep)
                .accessibilityIdentifier(item.kind.isMissingSleep ? "myday.noSleep" : "myday.row.\(item.id)")
        }
    }

    /// Add activity under the list (ui.md §2.1; Start activity joins it with A4): 16 pt below, hairline above.
    private func addButton(_ add: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: Theme.Metrics.hairline)
                .accessibilityHidden(true)
            PrimaryButton(title: "Add activity", style: .secondary) { add() }
                .accessibilityIdentifier("myday.addActivity")
        }
        .padding(.top, 16)
    }

    private var showAll: some View {
        Button(action: actions.openDay) {
            HStack(spacing: 4) {
                Text("Show all \(content.items.count)", comment: "My Day card: opens the full list of the day's items.")
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .accessibilityIdentifier("myday.showAll")
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

/// ＋: what can be added to the day (ui.md §2.1): Add activity, Start strength workout, Add sleep; Start activity
/// joins with A4. Only the entries offered.
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
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Add to your day", comment: "VoiceOver: My Day's plus menu."))
        .accessibilityIdentifier("myday.add")
    }
}

/// "Showing the list from 14:05", and after two minutes "Try again" (ui.md §2.1 M5): quiet, never red.
struct MyDayStaleLine: View {
    let since: Date
    var offersRetry = false
    var retry: () async -> Void = {}

    @Environment(\.locale) private var locale
    @State private var retrying = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Showing the list from \(Fmt.time(since, locale: locale))",
                 comment: "My Day: the list is the last one loaded; the time it was loaded.")
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
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
                        .font(.ryft(.callout))
                        .foregroundStyle(retrying ? Theme.textTertiary : Theme.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(retrying)
                .accessibilityIdentifier("myday.stale.retry")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("myday.stale")
    }
}

/// Outline rows while nothing is cached (ui.md §2.1 M4): no fill, no pulse, no spinner.
struct MyDaySkeleton: View {
    let rows: Int
    var style: MyDayRow.Style = .card

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { _ in
                RoundedRectangle(cornerRadius: style == .tile ? Theme.Metrics.tileRadius : 12, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline)
                    .frame(height: style == .tile ? 72 : 60)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading My Day", comment: "VoiceOver: My Day's outline rows while nothing is cached."))
        .accessibilityIdentifier("myday.loading")
    }
}

// MARK: - previews

#Preview("My Day card · states") {
    ScrollView {
        SchemePair {
            VStack(spacing: 16) {
                MyDayCardBody(content: MockMyDay.content(.populated), actions: .preview)
                MyDayCardBody(content: MockMyDay.content(.full), actions: .preview)
                MyDayCardBody(content: MockMyDay.content(.nothing), actions: .preview)
                MyDayCardBody(content: MockMyDay.content(.noSleepNothing), actions: .preview)
                MyDayCardBody(content: MockMyDay.content(.noSleepRows), actions: .preview)
                MyDayCardBody(content: MockMyDay.content(.loading), actions: .preview)
                MyDayCardBody(content: MockMyDay.content(.stale), actions: .preview)
                MyDayCardBody(content: MockMyDay.content(.failed), actions: .preview)
            }
        }
    }
}

#Preview("My Day card · populated · dark") {
    ScrollView { MyDayCardBody(content: MockMyDay.content(.full), actions: .preview).padding(20) }
        .background(Theme.background)
        .preferredColorScheme(.dark)
}

#Preview("My Day card · populated · light") {
    ScrollView { MyDayCardBody(content: MockMyDay.content(.full), actions: .preview).padding(20) }
        .background(Theme.background)
        .preferredColorScheme(.light)
}

#Preview("My Day card · de") {
    ScrollView {
        SchemePair {
            VStack(spacing: 16) {
                MyDayCardBody(content: MockMyDay.content(.full), actions: .preview)
                MyDayCardBody(content: MockMyDay.content(.noSleepNothing), actions: .preview)
                MyDayCardBody(content: MockMyDay.content(.stale), actions: .preview)
            }
        }
    }
    .environment(\.locale, Locale(identifier: "de"))
}

#Preview("My Day card · AX3") {
    ScrollView {
        SchemePair {
            VStack(spacing: 16) {
                MyDayCardBody(content: MockMyDay.content(.populated), actions: .preview)
                MyDayCardBody(content: MockMyDay.content(.noSleepNothing), actions: .preview)
            }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
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

#Preview("My Day card · live · dark") {
    MyDayCardHost().previewEnvironment(.preview(flags: [.todayMyDay: true]))
}

#Preview("My Day card · live · light") {
    MyDayCardHost().previewEnvironment(.preview(flags: [.todayMyDay: true]), scheme: .light)
}
