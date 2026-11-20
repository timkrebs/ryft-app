import SwiftUI

/// The full-screen My Day (ui.md §2.5, design.md §7.3; Nocturne PR 6 B §9.2, `b-18`, `b-26`), pushed on Today's stack: the
/// pushed header, the week strip, the day's summary and strain, every row on its own tile, Add activity pinned at the bottom
/// for the last 14 days. Manual and recorded activities and typed-in nights can be edited and deleted on any day.
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
            .sheet(item: $adding) { AddActivitySheet(model: $0).presentedRoot() }
            .sheet(item: $sleeping) { AddSleepSheet(model: $0).presentedRoot() }
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
            .task(id: TaskKey(day: day, refreshed: state.lastUpdated, online: state.env.connectivity.isOnline)) {
                await model.load(day)
            }
            // Today: the app's pull, the activities beside it; a past day: its reads, the spinner capped.
            .refreshable { await model.refresh(model.date) { await screens.pullToRefresh() } }
    }

    /// The day, today's refresh, and the iPhone back online (offline nothing was read).
    private struct TaskKey: Equatable {
        let day: Date
        let refreshed: Date?
        let online: Bool
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
        }, retryRow: { item in
            Task { await model.retryUpload(item) }
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

/// The screen itself, from a day's content and the week (B §9.2): `PushedHeader` "My Day" over "Today · Wed, Nov 18" with the
/// plus menu; 8 below the date strip (S11); 18 below the summary line and the day's strain; 12 below the rows as tiles, 8
/// apart. Add activity is a primary pill pinned above the tab bar on a 24 pt fade; the page scrolls under it. A day switch
/// cross-fades (250 ms, instant under Reduce Motion).
struct MyDayPage: View {
    let content: MyDayContent
    let week: [DateStrip.Day]
    var actions = MyDayActions()
    var select: (Date) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PushedHeader(Text("My Day", comment: "The card and screen with the day's sleep, workouts and activities."),
                             subtitle: Text(verbatim: subtitle), spokenSubtitle: Text(verbatim: spokenSubtitle),
                             identifierPrefix: "myday.view") {
                    if actions.hasAddEntries {
                        MyDayAddMenu(actions: actions)
                    } else {
                        PushedHeaderEmptySlot()
                    }
                }
                DateStrip(days: week, select: select)
                    .padding(.top, MyDayLayout.stripGap)
                day
                    // A day switch: a 250 ms cross-fade, instant under Reduce Motion.
                    .id(content.day)
                    .transition(.opacity)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, MyDayLayout.bottomPadding)
        }
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: content.day)
        .scrollIndicators(.hidden)
        // Add activity pinned above the tab bar on a 24 pt fade (Start activity joins it with A4, today only); the page
        // scrolls under the fade.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let add = actions.addActivity {
                VStack(spacing: 0) {
                    LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: .bottom)
                        .frame(height: MyDayLayout.pinnedFade)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    PillButton(Text("Add activity"), systemImage: "plus") { add() }
                        .accessibilityIdentifier("myday.view.addActivity")
                        .padding(.horizontal, MyDayLayout.pinnedSides)
                        .padding(.bottom, MyDayLayout.pinnedBottom)
                        .background(Theme.background)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        // The back button's title on a detail pushed from here; the bar itself is hidden (the pushed header draws it).
        .navigationTitle(Text("My Day", comment: "The card and screen with the day's sleep, workouts and activities."))
        .toolbar(.hidden, for: .navigationBar)
        .keepsBackSwipe()
        // A container: the header, the strip's days and the rows keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("myday.view")
    }

    // MARK: header words

    /// "Today · Wed, Nov 18", "Yesterday · Tue, Nov 17", "Sat, Nov 14".
    private var subtitle: String {
        let date = content.day.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated).month(.abbreviated).day())
        if content.isToday {
            return String(localized: "Today · \(date)", comment: "My Day's header under \"My Day\": today, then its date (\"Wed, Nov 18\").")
        }
        if content.isYesterday {
            return String(localized: "Yesterday · \(date)",
                          comment: "Sleep's header under \"Sleep\": the night that ended yesterday morning, then its date (\"Sat, Nov 14\").")
        }
        return date
    }

    /// The subtitle for VoiceOver, the date in full: "Today, Wednesday, November 18".
    private var spokenSubtitle: String {
        let date = content.day.formatted(Date.FormatStyle(locale: locale).weekday(.wide).month(.wide).day())
        if content.isToday || content.isYesterday { return "\(dayWord), \(date)" }
        return date
    }

    /// The day's word against the environment's clock ("Today", "Yesterday").
    private var dayWord: String { content.title ?? Fmt.dayTitle(content.day) }

    // MARK: the day

    private var day: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsSummary {
                summary
                    .padding(.top, MyDayLayout.summaryGap)
            }
            list
                .padding(.top, showsSummary ? MyDayLayout.rowsGap : MyDayLayout.summaryGap)
            if let since = content.staleSince {
                MyDayStaleLine(since: since, offersRetry: content.offersRetry, retry: actions.retry)
                    .padding(.top, MyDayLayout.rowsGap)
            }
        }
    }

    /// The summary line once the day is read and has activities or a strain.
    private var showsSummary: Bool { content.phase == .ready && (content.summary != nil || content.dayStrain != nil) }

    /// "4 activities · 2h 13m · 6.8 mi" in `label` `textSecondary`; trailing "Strain" in `axis` `textTertiary` and the day's
    /// strain, 20 Light ("–" while unscored). One VoiceOver element; from AX1 the strain goes under the summary.
    private var summary: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ActivityListRowSpec.metaGap))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: MyDayLayout.strainLabelGap))
        return layout {
            Text(verbatim: content.summary ?? "")
                .font(.ryft(.label))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: typeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: MyDayLayout.strainLabelGap) {
                Text("Strain")
                    .font(.ryft(.axis))
                    .foregroundStyle(Theme.textTertiary)
                StrainPill(strain: content.dayStrain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenSummary))
        .accessibilityIdentifier("myday.view.summary")
    }

    /// "4 activities, 2 hours 13 minutes, 6.8 miles, Strain 12.4" ("No strain" while unscored).
    private var spokenSummary: String {
        let strain = content.dayStrain.map { String(localized: "Strain \(Fmt.strain($0))") }
            ?? String(localized: "No strain", comment: "VoiceOver in an activity row without a strain.")
        return [content.spokenSummary(locale: locale), strain].compactMap(\.self).joined(separator: ", ")
    }

    @ViewBuilder
    private var list: some View {
        switch content.phase {
        case .loading:
            MyDaySkeleton()
        case .failed:
            MyDayFailedMessage(details: content.failedDetails, retry: actions.retry)
        case .offline:
            MyDayOfflineMessage(retry: actions.retry)
        case .ready:
            LazyVStack(alignment: .leading, spacing: MyDayLayout.rowSpacing) {
                ForEach(content.items) { item in
                    tile(item)
                        .transition(.opacity)
                }
                if content.isToday ? content.hasNoActivities : content.isEmpty {
                    MyDayEmptyLine(isToday: content.isToday)
                        .padding(.top, MyDayLayout.screenEmptyGap)
                        .accessibilityIdentifier("myday.view.empty")
                }
            }
            .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: content.items.map(\.id))
        }
    }

    @ViewBuilder
    private func tile(_ item: MyDayItem) -> some View {
        let retry = actions.rowRetry(for: item)
        if item.opensDetail {
            Button { actions.open(item) } label: { MyDayRow(item: item, style: .tile, showsChevron: true, retry: retry) }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(item.hint ?? Text(verbatim: ""))
                .myDayRowRetry(retry)
                .modifier(MyDayRowEditing(item: item, edit: actions.edit, delete: actions.delete))
                .accessibilityIdentifier("myday.view.row.\(item.id)")
        } else {
            MyDayRow(item: item, style: .tile, retry: retry, addSleep: actions.addSleep)
                .myDayRowRetry(retry)
                .accessibilityIdentifier(item.kind.isMissingSleep ? "myday.view.noSleep" : "myday.view.row.\(item.id)")
        }
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

// MARK: - previews (dark only)

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

#Preview("My Day · today") {
    MyDayViewHost().previewEnvironment(.preview(flags: [.todayMyDay: true]))
}

#Preview("My Day · yesterday") {
    MyDayViewHost(daysBack: 1).previewEnvironment(.preview(flags: [.todayMyDay: true]))
}

#Preview("My Day · missing night") {
    NavigationStack {
        MyDayPage(content: MockMyDay.content(.noSleepRows), week: MockMyDay.week(daysBack: 0), actions: .preview)
    }
    .preferredColorScheme(.dark)
}

#Preview("My Day · past empty") {
    NavigationStack {
        MyDayPage(content: MockMyDay.content(.pastEmpty), week: MockMyDay.week(daysBack: 3))
    }
    .preferredColorScheme(.dark)
}

#Preview("My Day · AX3") {
    NavigationStack {
        MyDayPage(content: MockMyDay.content(.full), week: MockMyDay.week(daysBack: 0), actions: .preview)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}

#Preview("My Day · offline, nothing saved") {
    NavigationStack {
        MyDayPage(content: MyDayContent(day: MockMyDay.today, isToday: true, phase: .offline, items: []),
                  week: MockMyDay.week(daysBack: 0), actions: .preview)
    }
    .preferredColorScheme(.dark)
}

#Preview("My Day · loading") {
    NavigationStack {
        MyDayPage(content: MockMyDay.content(.loading), week: MockMyDay.week(daysBack: 0), actions: .preview)
    }
    .preferredColorScheme(.dark)
}
