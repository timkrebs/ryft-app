import SwiftUI

/// Strain (Nocturne, design.md §P5-3): the header with Add activity, the week strip, the day's numeral and ruler, the
/// heart-rate zones, steps and energy, Train (today), and the day's activities. Wiring only; `StrainPage` lays it out.
struct StrainView: View {
    @Environment(AppState.self) private var state
    @Environment(ScreenModels.self) private var screens
    @Environment(TrainCoordinator.self) private var coordinator
    @Environment(\.locale) private var locale
    @State private var path = NavigationPath()
    /// `-RyftOpenWorkout YES` pushes the first workout once (screenshots).
    @State private var autoOpen = UserDefaults.standard.bool(forKey: "RyftOpenWorkout")
    /// The Add activity sheet for the shown day.
    @State private var adding: AddActivityModel?

    private var model: StrainViewModel { screens.strain }

    var body: some View {
        NavigationStack(path: $path) {
            StrainPage(content: content, actions: actions)
                .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
                .navigationDestination(for: ActivityRoute.self) { ActivityDetailView(route: $0) }
                .trainDestinations()
        }
        .sheet(item: $adding) { AddActivitySheet(model: $0).presentedRoot() }
        .task(id: TaskKey(date: model.date, refreshed: state.lastUpdated)) {
            await model.load()
            guard !Task.isCancelled else { return }
            if let announcement = model.takeStepAnnouncement() {
                AccessibilityNotification.Announcement(announcement).post()
            }
            if autoOpen, let first = model.detail?.workouts.first {
                autoOpen = false
                path.append(first)
            }
        }
        // A deep link to a session or plan: on top of a fresh stack.
        .task(id: model.requestedRoute) {
            guard let route = model.requestedRoute else { return }
            path = NavigationPath()
            path.append(route)
            model.requestedRoute = nil
        }
    }

    private struct TaskKey: Equatable {
        let date: Date
        let refreshed: Date?
    }

    private var content: StrainPageContent {
        // A finished session is in the list at once (the store changes, not the day's detail).
        _ = coordinator.sync.sessionsMark
        return StrainPageContent(board: model.board, day: model.date, week: model.week, status: model.status,
                                 showsTrain: model.showsTrainSection, rows: model.rows(locale: locale),
                                 showsHealthHint: model.hasNoHealthData, numeralStyle: model.numeralStyle,
                                 isDemo: model.isDemo, dayTitle: model.title, dateLine: model.dateLine)
    }

    private var actions: StrainActions {
        let myDay = screens.myDay
        let day = model.date
        let canAdd = myDay.isEnabled && myDay.canAdd(on: day)
        return StrainActions(select: { model.step(to: $0) },
                             add: canAdd ? { adding = myDay.addActivityModel(on: day) } : nil,
                             retry: { await model.load() }, signIn: { await model.signIn() },
                             refresh: { await screens.pullToRefresh() })
    }
}

/// What the Strain page shows, as values: the screen builds it from its model, previews and shot tests from mock data.
struct StrainPageContent {
    var board: StrainBoard
    /// The shown day (the numeral cross-fades when it changes).
    var day: Date
    var week: [DateStrip.Day]
    var status: StrainStatus?
    /// Today's Train section (`train.enabled`).
    var showsTrain: Bool
    var rows: [StrainRow]
    /// No Health data at all: the hint under an empty list.
    var showsHealthHint: Bool
    var numeralStyle: DotNumeral.Style = .dots
    var isDemo = false
    /// The header's spoken value: "Today", "Yesterday", "Mon, 16 Nov".
    var dayTitle: String?
    /// Under the header on another day: "Mon 16 Nov"; nil today.
    var dateLine: String?

    /// The date line for `day`: nil today, else its short date ("Mon 16 Nov").
    static func dateLine(_ day: Date, today: Date, calendar: Calendar = .current) -> String? {
        calendar.isDate(day, inSameDayAs: today) ? nil : day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// The page's buttons.
struct StrainActions {
    var select: (Date) -> Void = { _ in }
    /// Add activity for the shown day; nil hides the button (My Day off, or a day it can't add to), its place kept.
    var add: (() -> Void)?
    /// The board's failure: Try again.
    var retry: () async -> Void = {}
    var signIn: () async -> Void = {}
    /// The refresh card's and the stale line's Try again: the app's refresh.
    var refresh: () async -> Void = {}
}

/// The page (§P5-3.1): header 40, the refresh card 12 under it, the strip 12 under that, the status line, the numeral 22
/// under the strip, caption, split and ruler, the zones tile at the ruler's top + 56, the tiles 12 under it (its footnote
/// between), Train 24 under the tiles, Activities 24 under Train (18 under the tiles without it), the hint 12 under the list.
struct StrainPage: View {
    let content: StrainPageContent
    var actions = StrainActions()
    /// Previews and tests; nil follows the system.
    var reduceTransparency: Bool?

    var body: some View {
        ScreenScaffold(showsHeader: false) {
            VStack(spacing: 0) {
                header
                if let line = content.dateLine {
                    Text(verbatim: line)
                        .font(.ryft(.label))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, StrainLayout.dateLineGap)
                        // The header's value says the day.
                        .accessibilityHidden(true)
                }
                if case .issue(let issue) = content.status {
                    RefreshIssueCard(issue: issue, isDemo: content.isDemo, retry: actions.refresh, signIn: actions.signIn)
                        .padding(.top, StrainLayout.statusGap)
                }
                DateStrip(days: content.week, select: actions.select)
                    .padding(.top, StrainLayout.stripGap)
                if case .line(let line) = content.status {
                    SyncStatusLineView(line: line, retry: actions.refresh, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, StrainLayout.statusGap)
                }
                StrainHeroView(hero: content.board.hero, key: DayFormat.string(from: content.day),
                               numeralStyle: content.numeralStyle,
                               pendingLabel: content.board.look == .loading ? StrainBoard.loadingLabel : nil)
                    .padding(.top, StrainLayout.numeralGap)
                zones
                StrainTiles(board: content.board)
                    .padding(.top, StrainLayout.tilesGap)
                if content.showsTrain {
                    TrainSection()
                        .padding(.top, StrainLayout.sectionGap)
                }
                activities
                    .padding(.top, content.showsTrain ? StrainLayout.sectionGap : StrainLayout.activitiesGap)
            }
        }
    }

    private var header: some View {
        ScreenHeader(title: Text("Strain"), value: content.dayTitle.map { Text(verbatim: $0) }) {
            CircleButton(systemImage: "plus", iconSize: 14, accessibilityLabel: Text("Add activity")) {
                actions.add?()
            }
            .accessibilityHint(Text("Opens the add-activity sheet",
                                    comment: "VoiceOver hint on Strain's header button: it opens Add activity for the shown day."))
            .accessibilityIdentifier("strain.header.add")
            .opacity(actions.add == nil ? 0 : 1)
            .disabled(actions.add == nil)
            .accessibilityHidden(actions.add == nil)
        }
    }

    /// The zones tile, its outline while loading, or the failure's sentence in its place (§P5-3.7).
    @ViewBuilder private var zones: some View {
        let board = content.board
        if let failure = board.failure {
            let action = failure.action
            InlineMessage(message: failure.message, systemImage: failure.systemImage, retryTitle: action.title,
                          details: failure.details, retry: action.button(retry: actions.retry, signIn: actions.signIn),
                          identifier: "strain.failure")
        } else {
            StrainZonesTile(zones: board.zones, missing: board.zonesMissing, isOutline: board.isOutline,
                            reduceTransparency: reduceTransparency)
        }
    }

    private var activities: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activities")
                .ryftLabelStyle()
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: StrainLayout.rowGap) {
                if content.board.isOutline {
                    ActivityListRowPlaceholder()
                    ActivityListRowPlaceholder()
                } else if content.rows.isEmpty {
                    InlineMessage(message: String(localized: "No workouts recorded on this day."), systemImage: "figure.walk",
                                  identifier: "strain.empty", announces: false)
                } else {
                    ForEach(content.rows) { StrainRowLink(row: $0) }
                }
            }
            .padding(.top, StrainLayout.listTitleGap)
            if !content.board.isOutline, content.rows.isEmpty, content.showsHealthHint {
                HealthAccessHint()
                    .padding(.top, StrainLayout.footerGap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("strain.activities")
    }
}

/// One activity row: a link to its workout, session or activity (the whole row; its hint says where), or the plain row.
private struct StrainRowLink: View {
    let row: StrainRow

    var body: some View {
        switch row.destination {
        case .workout(let w): link(w)
        case .session(let id): link(TrainRoute.session(id))
        case .activity(let route): link(route)
        case .none:
            ActivityListRow(content: row.content)
                .accessibilityIdentifier(row.identifier)
        }
    }

    private func link(_ value: some Hashable) -> some View {
        NavigationLink(value: value) { ActivityListRow(content: row.content) }
            .buttonStyle(PressableButtonStyle())
            .accessibilityHint(Text(verbatim: row.hint ?? ""))
            .accessibilityIdentifier(row.identifier)
    }
}

// MARK: - previews (dark only)

/// The page's states from mock data: today scored, loading, failed, no zones, no workouts, another day.
enum StrainPreview {
    static var today: Date { Calendar.current.startOfDay(for: .now) }

    /// A Train coordinator of its own with a session running (the shared preview store stays idle for the others).
    @MainActor static let liveTrain: TrainCoordinator = {
        let store = TrainStore(inMemory: true)
        let sync = TrainSyncService.preview(store: store)
        _ = MockTrain.liveSession(in: store)
        return TrainCoordinator(sync: sync, library: TrainLibrary.preview(store: store, outbox: sync), liveActivities: false)
    }()

    static func week(selected: Date = today) -> [DateStrip.Day] {
        DateStrip.week(endingAt: today, selected: selected) { day in
            MockData.history.first { $0.day == DayFormat.string(from: day) }
        }
    }

    static func prior(_ day: Date) -> [TrendPoint] {
        (1..<MetricDelta.windowDays).map { offset in
            let key = DayFormat.string(from: DayFormat.shift(day, days: -offset))
            return TrendPoint(day: key, value: MockData.history.first { $0.day == key }?.strain)
        }
    }

    /// The day from `MockData`, or the state asked for.
    static func content(day: Date = today, loading: Bool = false, failure: SleepLoadFailure? = nil,
                        zones: Bool = true, workouts: Bool = true, showsTrain: Bool = true,
                        status: StrainStatus? = nil, pending: Bool = false) -> StrainPageContent {
        var detail: DayDetail? = loading || failure != nil ? nil : MockData.detail(for: day)
        if pending {
            // API.md's placeholder while the platform scores the day: no strain, no zones yet.
            detail?.strain = nil
            detail?.score.strain = nil
            detail?.score.scoringState = .pending
        }
        if !zones, var d = detail?.strain {
            d = DayStrain(trimp: d.trimp, hrMin: d.hrMin, zoneMin: [], steps: d.steps, activeKcal: d.activeKcal)
            detail?.strain = d
        }
        if !workouts { detail?.workouts = [] }
        let score = pending ? detail?.score : detail?.score ?? MockData.history.first { $0.day == DayFormat.string(from: day) }
        let isToday = Calendar.current.isDate(day, inSameDayAs: today)
        let board = StrainBoard(detail: detail, score: loading || failure != nil ? nil : score, prior: prior(day),
                                split: nil, isLoading: loading, failure: failure,
                                scoring: StrainBoard.DayScoring(score?.scoringState, isToday: isToday))
        let rows = (detail?.workouts ?? []).map { StrainRow(.workout($0, nil), locale: .autoupdatingCurrent) }
        return StrainPageContent(board: board, day: day, week: week(selected: day), status: status,
                                 showsTrain: showsTrain && isToday, rows: rows, showsHealthHint: false,
                                 dayTitle: Fmt.dayTitle(day, today: today),
                                 dateLine: StrainPageContent.dateLine(day, today: today))
    }
}

#Preview("Strain") {
    StrainView().previewEnvironment()
}

#Preview("Strain · My Day list (today.my_day)") {
    StrainView().previewEnvironment(.preview(flags: [.todayMyDay: true]))
}

#Preview("Strain · loading") {
    NavigationStack { StrainPage(content: StrainPreview.content(loading: true)) }
        .previewEnvironment()
}

#Preview("Strain · failed") {
    NavigationStack {
        StrainPage(content: StrainPreview.content(failure: SleepLoadFailure(reason: .unreachable, details: "HTTP 503")))
    }
    .previewEnvironment()
}

#Preview("Strain · no zones, no workouts") {
    NavigationStack { StrainPage(content: StrainPreview.content(zones: false, workouts: false)) }
        .previewEnvironment()
}

/// §P5-11: the Train section while a session runs (its resume banner instead of Start workout).
#Preview("Strain · Train in progress") {
    NavigationStack {
        StrainPage(content: StrainPreview.content())
            .environment(StrainPreview.liveTrain)
    }
    .previewEnvironment()
}

#Preview("Strain · another day, offline") {
    NavigationStack {
        StrainPage(content: StrainPreview.content(day: DayFormat.shift(StrainPreview.today, days: -2), status: .line(.offline)))
    }
    .previewEnvironment()
}

/// Today while the platform scores newer data: "Scoring your latest data", the zone rows with "–", no absence sentence.
#Preview("Strain · scoring (pending)") {
    NavigationStack { StrainPage(content: StrainPreview.content(pending: true)) }
        .previewEnvironment()
}

/// A deep link older than the week strip: no cell selected, the date line names the day.
#Preview("Strain · ten days ago") {
    NavigationStack { StrainPage(content: StrainPreview.content(day: DayFormat.shift(StrainPreview.today, days: -10))) }
        .previewEnvironment()
}

#Preview("Strain · AX3") {
    StrainView().previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}
