import SwiftUI

/// What a My Day row, header or button does; the live card and screen fill it, previews leave it empty.
struct MyDayActions {
    /// The full screen (the card's title, expand and "Show all").
    var openDay: () -> Void = {}
    /// A row: sleep opens Sleep, a workout its detail, a session Train's (design.md §7.3).
    var open: (MyDayItem) -> Void = { _ in }
    /// ＋ → Start strength workout (the shipped Train flow).
    var startStrength: () -> Void = {}
    /// Try again (the stale caption, the error).
    var retry: () async -> Void = {}
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
    /// `-RyftOpenMyDay <days back>` opens the full screen once on that day (Debug, screenshots and UI tests).
    @State private var autoOpen = MyDayCard.requestedDaysBack

    var body: some View {
        MyDayCardBody(content: model.card, showsAdd: model.showsTrain, actions: actions)
            .navigationDestination(isPresented: $showsDay) { MyDayView(model: model) }
            .navigationDestination(item: $workout) { WorkoutDetailView(workout: $0) }
            .navigationDestination(item: $session) { SessionDetailView(sessionID: $0).trainDestinations() }
            .task(id: state.lastUpdated) {
                await model.load(model.today)
                if let back = autoOpen {
                    autoOpen = nil
                    model.select(DayFormat.shift(model.today, days: -back))
                    showsDay = true
                }
            }
    }

    private var actions: MyDayActions {
        MyDayActions(openDay: {
            model.select(model.today)
            showsDay = true
        }, open: { item in
            MyDayCard.open(item, on: model.today, model: model, router: screens.router,
                           workout: { workout = $0 }, session: { session = $0 })
        }, startStrength: {
            Task { await coordinator.quickStart(.auto) }
        }, retry: {
            await model.load(model.today, force: true)
        })
    }

    /// Sleep → the Sleep tab on that night; a workout → its detail; a session → Train's. Activities wait for A2.
    static func open(_ item: MyDayItem, on day: Date, model: MyDayViewModel, router: DeepLinkRouter,
                     workout: (Workout) -> Void, session: (UUID) -> Void) {
        switch item.kind {
        case .sleep:
            Task { await router.open(.sleep(day)) }
        case .workout(let id):
            if let w = model.workout(id, on: day) { workout(w) }
        case .session(let id):
            session(id)
        case .activity, .missingSleep:
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

/// The card itself, from a day's content: header with ＋, up to five rows, "Show all", the stale caption.
struct MyDayCardBody: View {
    let content: MyDayContent
    /// ＋ with "Start strength workout" (`train.enabled`); hidden without an entry.
    var showsAdd = false
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
            if showsAdd {
                MyDayAddMenu(startStrength: actions.startStrength)
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
                    Text("Nothing yet today", comment: "My Day card: no workouts or activities today.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, content.items.isEmpty ? 0 : 10)
                        .accessibilityIdentifier("myday.empty")
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: MyDayItem) -> some View {
        if item.kind.opensDetail {
            Button { actions.open(item) } label: { MyDayRow(item: item) }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(item.kind.hint ?? Text(verbatim: ""))
                .accessibilityIdentifier("myday.row.\(item.id)")
        } else {
            MyDayRow(item: item)
                .accessibilityIdentifier(item.kind.isMissingSleep ? "myday.noSleep" : "myday.row.\(item.id)")
        }
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

extension MyDayItem.Kind {
    /// VoiceOver: what tapping the row does; nil for rows that open nothing.
    var hint: Text? {
        switch self {
        case .sleep: return Text("Opens Sleep")
        case .workout: return Text("Opens the workout", comment: "VoiceOver: a My Day row opens the workout's detail.")
        case .session: return Text("Opens the session", comment: "VoiceOver: a My Day row opens the Train session.")
        case .activity, .missingSleep: return nil
        }
    }
}

/// ＋: what can be added to the day. In A1 only "Start strength workout" (Add activity, Start activity and Add
/// sleep come with A2 and A4).
struct MyDayAddMenu: View {
    let startStrength: () -> Void

    var body: some View {
        Menu {
            Button(action: startStrength) {
                Label("Start strength workout", systemImage: "dumbbell")
            }
            .accessibilityIdentifier("myday.add.strength")
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
                MyDayCardBody(content: MockMyDay.content(.populated), showsAdd: true)
                MyDayCardBody(content: MockMyDay.content(.full), showsAdd: true)
                MyDayCardBody(content: MockMyDay.content(.nothing), showsAdd: true)
                MyDayCardBody(content: MockMyDay.content(.noSleepNothing), showsAdd: true)
                MyDayCardBody(content: MockMyDay.content(.noSleepRows))
                MyDayCardBody(content: MockMyDay.content(.loading), showsAdd: true)
                MyDayCardBody(content: MockMyDay.content(.stale), showsAdd: true)
                MyDayCardBody(content: MockMyDay.content(.failed), showsAdd: true)
            }
        }
    }
}

#Preview("My Day card · populated · dark") {
    ScrollView { MyDayCardBody(content: MockMyDay.content(.full), showsAdd: true).padding(20) }
        .background(Theme.background)
        .preferredColorScheme(.dark)
}

#Preview("My Day card · populated · light") {
    ScrollView { MyDayCardBody(content: MockMyDay.content(.full), showsAdd: true).padding(20) }
        .background(Theme.background)
        .preferredColorScheme(.light)
}

#Preview("My Day card · de") {
    ScrollView {
        SchemePair {
            VStack(spacing: 16) {
                MyDayCardBody(content: MockMyDay.content(.full), showsAdd: true)
                MyDayCardBody(content: MockMyDay.content(.noSleepNothing), showsAdd: true)
                MyDayCardBody(content: MockMyDay.content(.stale), showsAdd: true)
            }
        }
    }
    .environment(\.locale, Locale(identifier: "de"))
}

#Preview("My Day card · AX3") {
    ScrollView {
        SchemePair {
            VStack(spacing: 16) {
                MyDayCardBody(content: MockMyDay.content(.populated), showsAdd: true)
                MyDayCardBody(content: MockMyDay.content(.noSleepNothing), showsAdd: true)
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
