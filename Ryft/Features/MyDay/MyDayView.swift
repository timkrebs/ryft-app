import SwiftUI

/// The full-screen My Day (ui.md §2.5, design.md §7.3), pushed on Today's stack: the week strip pinned under the
/// navigation bar, the day's title and summary, every row on its own tile. Past days are read-only in A1.
struct MyDayView: View {
    let model: MyDayViewModel

    @Environment(ScreenModels.self) private var screens
    @Environment(AppState.self) private var state
    @Environment(TrainCoordinator.self) private var coordinator
    @State private var workout: Workout?
    @State private var session: UUID?

    var body: some View {
        let day = model.date
        MyDayPage(content: model.content(for: day), week: model.week, showsAdd: model.showsTrain, actions: actions,
                  select: { model.select($0) })
            .navigationDestination(item: $workout) { WorkoutDetailView(workout: $0) }
            .navigationDestination(item: $session) { SessionDetailView(sessionID: $0).trainDestinations() }
            .task(id: TaskKey(day: day, refreshed: state.lastUpdated)) { await model.load(day) }
            .refreshable {
                await screens.pullToRefresh()
                await model.load(model.date, force: true)
            }
    }

    private struct TaskKey: Equatable {
        let day: Date
        let refreshed: Date?
    }

    private var actions: MyDayActions {
        MyDayActions(open: { item in
            MyDayCard.open(item, on: model.date, model: model, router: screens.router,
                           workout: { workout = $0 }, session: { session = $0 })
        }, startStrength: {
            Task { await coordinator.quickStart(.auto) }
        }, retry: {
            await model.load(model.date, force: true)
        })
    }
}

/// The screen itself, from a day's content and the week.
struct MyDayPage: View {
    let content: MyDayContent
    let week: [DateStrip.Day]
    /// ＋ with "Start strength workout" (`train.enabled`), today only: nothing is started in the past.
    var showsAdd = false
    var actions = MyDayActions()
    var select: (Date) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                list
                if let since = content.staleSince {
                    MyDayStaleLine(since: since, offersRetry: content.offersRetry, retry: actions.retry)
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 32)
            // A day switch: a 250 ms cross-fade, instant under Reduce Motion.
            .id(content.day)
            .transition(.opacity)
        }
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: content.day)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            DateStrip(days: week, select: select)
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.vertical, 6)
                .background(Theme.background)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline)
                }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("My Day", comment: "The card and screen with the day's sleep, workouts and activities."))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if showsAdd, content.isToday {
                ToolbarItem(placement: .topBarTrailing) {
                    MyDayAddMenu(startStrength: actions.startStrength)
                }
            }
        }
        // A container: the strip's days and the rows keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("myday.view")
    }

    /// "Today" / "Wed, 21 Oct", then "3 activities · 1h 52m · 14.8 km" and the day's strain once scored.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: Fmt.dayTitle(content.day))
                .font(.ryft(.title))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if content.summary != nil || content.dayStrain != nil {
                HStack(alignment: .center, spacing: 10) {
                    if let summary = content.summary {
                        Text(verbatim: summary)
                            .font(.ryft(.callout))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if let strain = content.dayStrain { StrainPill(strain: strain) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("myday.view.header")
    }

    @ViewBuilder
    private var list: some View {
        switch content.phase {
        case .loading:
            MyDaySkeleton(rows: 3, style: .tile)
        case .failed:
            InlineMessage(message: String(localized: "Couldn't load My Day.", comment: "My Day: nothing cached and the read failed."),
                          retry: actions.retry, identifier: "myday.failed")
        case .ready:
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(content.items) { item in
                    tile(item)
                        .transition(.opacity)
                }
                if content.isToday ? content.hasNoActivities : content.isEmpty { empty }
            }
            .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: content.items.map(\.id))
        }
    }

    @ViewBuilder
    private func tile(_ item: MyDayItem) -> some View {
        if item.kind.opensDetail {
            Button { actions.open(item) } label: { MyDayRow(item: item, style: .tile, showsChevron: true) }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(item.kind.hint ?? Text(verbatim: ""))
                .accessibilityIdentifier("myday.view.row.\(item.id)")
        } else {
            MyDayRow(item: item, style: .tile)
                .accessibilityIdentifier(item.kind.isMissingSleep ? "myday.view.noSleep" : "myday.view.row.\(item.id)")
        }
    }

    /// F3: nothing on a past day; today: nothing yet.
    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            if content.isToday {
                Text("Nothing yet today", comment: "My Day card: no workouts or activities today.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Nothing recorded on this day", comment: "My Day: a past day without sleep, workouts or activities.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                Text("Anything your tracker syncs later will appear here.",
                     comment: "My Day: under 'Nothing recorded on this day'.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("myday.view.empty")
    }
}

// MARK: - previews

/// The live screen on the preview environment's own model (`screens.myDay`), `daysBack` before today.
private struct MyDayViewHost: View {
    var daysBack = 0
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        NavigationStack {
            MyDayView(model: screens.myDay)
                .onAppear { screens.myDay.select(DayFormat.shift(screens.myDay.today, days: -daysBack)) }
        }
    }
}

#Preview("My Day · today · dark") {
    MyDayViewHost().previewEnvironment(.preview(flags: [.todayMyDay: true]))
}

#Preview("My Day · today · light") {
    MyDayViewHost().previewEnvironment(.preview(flags: [.todayMyDay: true]), scheme: .light)
}

#Preview("My Day · yesterday · dark") {
    MyDayViewHost(daysBack: 1).previewEnvironment(.preview(flags: [.todayMyDay: true]))
}

#Preview("My Day · past day · light") {
    MyDayViewHost(daysBack: 2).previewEnvironment(.preview(flags: [.todayMyDay: true]), scheme: .light)
}

#Preview("My Day · past empty") {
    NavigationStack {
        MyDayPage(content: MockMyDay.content(.pastEmpty), week: MockMyDay.week(daysBack: 3))
    }
    .preferredColorScheme(.dark)
}

#Preview("My Day · past empty · light") {
    NavigationStack {
        MyDayPage(content: MockMyDay.content(.pastEmpty), week: MockMyDay.week(daysBack: 3))
    }
    .preferredColorScheme(.light)
}

#Preview("My Day · states · AX3") {
    NavigationStack {
        MyDayPage(content: MockMyDay.content(.full), week: MockMyDay.week(daysBack: 0), showsAdd: true)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}

#Preview("My Day · loading") {
    NavigationStack {
        MyDayPage(content: MockMyDay.content(.loading), week: MockMyDay.week(daysBack: 0), showsAdd: true)
    }
    .preferredColorScheme(.dark)
}
