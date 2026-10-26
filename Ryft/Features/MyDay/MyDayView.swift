import SwiftUI

/// The full-screen My Day (ui.md §2.5, design.md §7.3), pushed on Today's stack: the week strip pinned under the
/// navigation bar, the day's title and summary, every row on its own tile, Add activity pinned at the bottom for
/// the last 14 days. Manual and recorded activities and typed-in nights can be edited and deleted on any day.
struct MyDayView: View {
    let model: MyDayViewModel

    @Environment(ScreenModels.self) private var screens
    @Environment(AppState.self) private var state
    @Environment(TrainCoordinator.self) private var coordinator
    @State private var workout: Workout?
    @State private var session: UUID?
    @State private var activity: ActivityRoute?
    @State private var adding: AddActivityModel?
    @State private var sleeping: AddSleepModel?
    @State private var deleting: MyDayItem?

    /// The selected day's content; a session finished meanwhile shows at once (`TrainSyncService.sessionsMark`).
    private var content: MyDayContent {
        _ = coordinator.sync.sessionsMark
        return model.content(for: model.date)
    }

    var body: some View {
        let day = model.date
        let content = content
        MyDayPage(content: content, week: model.week, actions: actions(content), select: { model.select($0) })
            .navigationDestination(item: $workout) { WorkoutDetailView(workout: $0) }
            .navigationDestination(item: $session) { SessionDetailView(sessionID: $0).trainDestinations() }
            .navigationDestination(item: $activity) { ActivityDetailView(route: $0) }
            .sheet(item: $adding) { AddActivitySheet(model: $0) }
            .sheet(item: $sleeping) { AddSleepSheet(model: $0) }
            .confirmationDialog(deleting.map(Self.deleteTitle) ?? Text(verbatim: ""),
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { item in
                Button(role: .destructive) { model.delete(item, on: day) } label: {
                    Text("Delete", comment: "Confirms deleting an activity or a night the user added.")
                }
                .accessibilityIdentifier("myday.confirmDelete")
                Button(role: .cancel) {} label: { Text("Keep", comment: "Cancels deleting an activity or a night.") }
            } message: { item in
                Self.deleteMessage(item)
            }
            .task(id: TaskKey(day: day, refreshed: state.lastUpdated)) { await model.load(day) }
            // Today: the app's pull, the activities beside it; a past day: its reads, the spinner capped.
            .refreshable { await model.refresh(model.date) { await screens.pullToRefresh() } }
    }

    private struct TaskKey: Equatable {
        let day: Date
        let refreshed: Date?
    }

    private func actions(_ content: MyDayContent) -> MyDayActions {
        let day = model.date
        return MyDayActions(open: { item in
            MyDayCard.open(item, on: day, model: model, router: screens.router) { destination in
                switch destination {
                case .workout(let w): workout = w
                case .session(let id): session = id
                case .activity(let route): activity = route
                }
            }
        }, addActivity: model.canAdd(on: day) ? { adding = model.addActivityModel(on: day) } : nil,
        addSleep: model.offersAddSleep(on: day, content: content) ? { sleeping = model.addSleepModel(on: day) } : nil,
        // Nothing is started in the past.
        startStrength: model.showsTrain && content.isToday ? { Task { await coordinator.quickStart(.auto) } } : nil,
        edit: model.addsManually ? { item in
            if item.isManualSleep {
                sleeping = model.editSleep(item)
            } else {
                adding = model.editActivity(item, on: day)
            }
        } : nil,
        delete: model.addsManually ? { deleting = $0 } : nil,
        retry: {
            await model.load(day, force: true)
        })
    }

    /// "Delete this activity?" or, for a typed-in night, "Delete this sleep entry?".
    static func deleteTitle(_ item: MyDayItem) -> Text {
        item.isManualSleep ? Text("Delete this sleep entry?") : Text("Delete this activity?")
    }

    /// What deleting does: a recorded activity loses its route too (ui.md §8.1.11, §3.7).
    static func deleteMessage(_ item: MyDayItem) -> Text {
        if item.isManualSleep {
            return Text("Your scores for that night are recalculated.", comment: "Delete a night the user added: what happens.")
        }
        let recorded = item.sources.contains { if case .ryftRecorded = $0 { return true } else { return false } }
        return Text(recorded ? String(localized: "It's removed from RYFT, including its route, and your strain for the day is recalculated.")
                             : String(localized: "It's removed from RYFT and your strain for the day is recalculated."))
    }
}

/// The screen itself, from a day's content and the week.
struct MyDayPage: View {
    let content: MyDayContent
    let week: [DateStrip.Day]
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
            // Pinned: capped at xxxLarge so it doesn't take a quarter of the screen at AX sizes (the rings are fixed;
            // VoiceOver reads each day's name and strain).
            DateStrip(days: week, select: select)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.vertical, 6)
                .background(Theme.background)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline)
                }
        }
        // Add activity pinned above the safe area (Start activity joins it with A4, today only).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let add = actions.addActivity {
                PrimaryButton(title: "Add activity", style: .secondary) { add() }
                    .padding(.horizontal, Theme.Metrics.screenPadding)
                    .padding(.vertical, 10)
                    .background(Theme.background)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline)
                    }
                    .accessibilityIdentifier("myday.view.addActivity")
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("My Day", comment: "The card and screen with the day's sleep, workouts and activities."))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if actions.hasAddEntries {
                ToolbarItem(placement: .topBarTrailing) {
                    MyDayAddMenu(actions: actions)
                }
            }
        }
        // A container: the strip's days and the rows keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("myday.view")
    }

    /// "Today" / "Wed, 21 Oct", then "3 activities · 1h 52m · 14.8 km" and the day's strain once scored. Without
    /// activities the strain sits on the title's row (never alone on a line of its own).
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(verbatim: content.title ?? Fmt.dayTitle(content.day))
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if content.summary == nil, let strain = content.dayStrain {
                    Spacer(minLength: 0)
                    StrainPill(strain: strain)
                }
            }
            if let summary = content.summary {
                HStack(alignment: .center, spacing: 10) {
                    Text(verbatim: summary)
                        .font(.ryft(.callout))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        if item.opensDetail {
            Button { actions.open(item) } label: { MyDayRow(item: item, style: .tile, showsChevron: true) }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(item.hint ?? Text(verbatim: ""))
                .modifier(MyDayRowEditing(item: item, edit: actions.edit, delete: actions.delete))
                .accessibilityIdentifier("myday.view.row.\(item.id)")
        } else {
            MyDayRow(item: item, style: .tile, addSleep: actions.addSleep)
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

/// Edit and Delete on a manual or recorded activity, or a typed-in night: a context menu, and the same as VoiceOver
/// actions (a My Day list isn't a `List`, so no swipe; the detail has both too).
private struct MyDayRowEditing: ViewModifier {
    let item: MyDayItem
    let edit: ((MyDayItem) -> Void)?
    let delete: ((MyDayItem) -> Void)?

    private var offers: Bool {
        guard item.editable else { return false }
        if case .activity = item.kind { return true }
        return item.isManualSleep
    }

    func body(content: Content) -> some View {
        if offers, let edit, let delete {
            content
                .contextMenu {
                    Button { edit(item) } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { delete(item) } label: {
                        if item.isManualSleep {
                            Label("Delete this entry", systemImage: "trash")
                        } else {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .accessibilityActions {
                    Button(String(localized: "Edit")) { edit(item) }
                    Button(String(localized: "Delete")) { delete(item) }
                }
        } else {
            content
        }
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
        MyDayPage(content: MockMyDay.content(.full), week: MockMyDay.week(daysBack: 0), actions: .preview)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}

#Preview("My Day · loading") {
    NavigationStack {
        MyDayPage(content: MockMyDay.content(.loading), week: MockMyDay.week(daysBack: 0), actions: .preview)
    }
    .preferredColorScheme(.dark)
}
