import Foundation
import Observation

/// My Day: the card on Today (always today) and the full screen with its week strip (design.md §7). Reads come
/// only from caches (the day detail, the day's activities, this iPhone's activities and sessions); `load`
/// revalidates through the Repository. Behind `today.myDay`.
@MainActor
@Observable
final class MyDayViewModel {
    private let state: AppState
    private let store: TrainStore
    /// T1's night gap for today (`TodayStates.nightGap`): the tracker's night is only late.
    @ObservationIgnored private let nightGap: @MainActor () -> Bool

    /// The full screen's day (start of day). The card shows today whatever this says.
    var date: Date
    /// Days whose load failed with nothing cached: an error instead of the skeleton.
    private(set) var failed: Set<String> = []

    init(state: AppState, store: TrainStore, nightGap: @escaping @MainActor () -> Bool = { false }) {
        self.state = state
        self.store = store
        self.nightGap = nightGap
        date = Calendar.current.startOfDay(for: state.env.clock.now())
    }

    private var env: AppEnvironment { state.env }
    private var calendar: Calendar { .current }
    var today: Date { calendar.startOfDay(for: env.clock.now()) }

    /// The card, the full screen and Strain's list (`today.myDay`, dark until the UI review).
    var isEnabled: Bool { env.flags.isOn(.todayMyDay) }
    /// "Start strength workout" in the ＋ menu follows `train.enabled`; it's the menu's only entry until A2 and A4.
    var showsTrain: Bool { env.flags.isOn(.trainEnabled) }

    // MARK: reads

    /// The day's rows as cached, oldest first (the night first).
    func items(for day: Date) -> [MyDayItem] {
        MyDayAssembler.items(input(for: day), catalog: env.trackerCatalog, now: env.clock.now())
    }

    func input(for day: Date) -> MyDayInput {
        let isToday = calendar.isDate(day, inSameDayAs: today)
        return .cached(day: day, state: state, store: store) { isToday && self.nightGap() }
    }

    /// The card: today.
    var card: MyDayContent { content(for: today) }

    /// What a day shows: its rows, whether it's still loading or failed, and whether the list is stale.
    func content(for day: Date) -> MyDayContent {
        let day = calendar.startOfDay(for: day)
        let key = DayFormat.string(from: day)
        let items = items(for: day)
        let cached = state.cachedDayDetail(for: day) != nil || state.repository.activitiesFetchedAt(day: key) != nil
        let phase: MyDayContent.Phase = cached || !items.isEmpty ? .ready : failed.contains(key) ? .failed : .loading
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let stale = phase == .ready ? staleSince(key, isToday: isToday) : nil
        let score = state.cachedDayDetail(for: day)?.score ?? state.score(for: day)
        return MyDayContent(day: day, isToday: isToday, phase: phase, items: items, staleSince: stale,
                            offersRetry: stale.map { env.clock.now().timeIntervalSince($0) > MyDayContent.retryAfter } ?? false,
                            dayStrain: DayMarker.kind(for: score) == .scored ? score?.strain : nil)
    }

    /// The full screen's week strip: today and the six days before, the selected one highlighted.
    var week: [DateStrip.Day] {
        DateStrip.week(endingAt: today, selected: date) { state.score(for: $0) }
    }

    func select(_ day: Date) {
        date = calendar.startOfDay(for: day)
    }

    /// The cached workout behind a row (`WorkoutDetailView`).
    func workout(_ id: UUID, on day: Date) -> Workout? {
        state.cachedDayDetail(for: day)?.workouts.first { $0.id == id }
    }

    /// The list is older than the platform's word: offline, or the day's or the activities' last read failed.
    /// The older of the two fetch times; nil when fresh or nothing was ever fetched.
    private func staleSince(_ key: String, isToday: Bool) -> Date? {
        _ = env.reads.revision
        let online = env.isDemo || env.connectivity.isOnline
        let states = env.reads.states
        let failing = [isToday ? ReadResource.today : .day, .activities]
            .contains { (states[$0]?.consecutiveFailures ?? 0) > 0 }
        guard !online || failing else { return nil }
        return [state.repository.detailFetchedAt(key), state.repository.activitiesFetchedAt(day: key)].compactMap { $0 }.min()
    }

    // MARK: loads

    /// Revalidates a day: its detail (Today's own read for today: fresh, so no request) and its activities, side
    /// by side. Cached and fresh → nothing is sent; `force` (pull to refresh, Try again) asks now.
    func load(_ day: Date, force: Bool = false) async {
        guard state.hasDataSource else { return }
        let day = calendar.startOfDay(for: day)
        let key = DayFormat.string(from: day)
        let mode: ReadMode = force ? .latest : .ifStale
        failed.remove(key)
        async let detail = loadDetail(day, mode: mode, userInitiated: force)
        async let activities: Void = loadActivities(key, mode: mode, userInitiated: force)
        let loaded = await detail
        await activities
        if !loaded, state.cachedDayDetail(for: day) == nil { failed.insert(key) }
    }

    /// False when the read failed (a cancellation isn't a failure: the next load says what's true).
    private func loadDetail(_ day: Date, mode: ReadMode, userInitiated: Bool) async -> Bool {
        do {
            _ = try await state.repository.refreshDay(day, mode: mode, userInitiated: userInitiated)
            return true
        } catch {
            return error.isCancellation
        }
    }

    /// A failure keeps what's cached; the read record says it failed (the stale caption).
    private func loadActivities(_ key: String, mode: ReadMode, userInitiated: Bool) async {
        _ = try? await state.repository.refreshActivities(key, mode: mode, userInitiated: userInitiated)
    }
}

/// One day of My Day as the card and the full screen show it.
struct MyDayContent: Equatable {
    enum Phase: Equatable {
        /// Nothing cached yet: outline rows, no spinner.
        case loading
        /// Nothing cached and the read failed.
        case failed
        case ready
    }

    /// The card shows up to five rows (ui.md §2.1).
    static let cardCap = 5
    /// "Try again" joins the stale caption after two minutes (the refresh-resilience threshold).
    static let retryAfter: TimeInterval = 120

    var day: Date
    var isToday: Bool
    var phase: Phase
    /// Every row, oldest first (the night first).
    var items: [MyDayItem]
    /// "Showing the list from 14:05".
    var staleSince: Date?
    var offersRetry = false
    /// The day's strain once it's scored (the full screen's header).
    var dayStrain: Double?

    /// No workout, session or activity (the night may be there): "Nothing yet today" (ui.md §2.1 M2).
    var hasNoActivities: Bool { !items.contains { !$0.kind.isSleep } }
    /// Nothing at all but, maybe, the missing night: "Nothing recorded on this day" (F3).
    var isEmpty: Bool { items.allSatisfy(\.kind.isMissingSleep) }

    /// The card's rows: all of them up to the cap; over it the night, then the latest others in order.
    var cardRows: [MyDayItem] {
        guard items.count > Self.cardCap else { return items }
        let night = items.filter(\.kind.isSleep)
        let others = items.filter { !$0.kind.isSleep }
        return night + others.suffix(max(0, Self.cardCap - night.count))
    }

    /// "Show all 9" when the card leaves rows out.
    var showsAll: Bool { items.count > cardRows.count }

    /// Everything but the night: workouts, sessions, activities.
    var activities: [MyDayItem] { items.filter { !$0.kind.isSleep } }

    /// "3 activities · 1h 52m · 14.8 km"; nil without any.
    var summary: String? {
        let list = activities
        guard !list.isEmpty else { return nil }
        var parts = [String(localized: "\(list.count) activities", comment: "My Day: how many workouts and activities a day has.")]
        let duration = list.map(\.duration).reduce(0, +)
        if duration >= 60 { parts.append(Fmt.duration(seconds: duration)) }
        let distance = list.compactMap(\.distanceM).reduce(0, +)
        if distance > 0 { parts.append(Fmt.distance(meters: distance)) }
        return parts.joined(separator: " · ")
    }
}

extension MyDayInput {
    /// A day as cached: the detail, the platform's activities, this iPhone's activities, sessions and manual
    /// night. My Day and Strain's list read the same.
    @MainActor
    static func cached(day: Date, state: AppState, store: TrainStore,
                       nightGap: @MainActor () -> Bool = { false }) -> MyDayInput {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let key = DayFormat.string(from: start)
        let activities = state.env.activities
        let detail = state.cachedDayDetail(for: start)
        let server = state.repository.activities(day: key)
        var local = activities.snapshots(onDay: key)
        if !server.isEmpty {
            // An edit that moved one of the day's activities elsewhere still hides the platform's copy here.
            let ids = Set(local.map(\.id))
            let serverIDs = Set(server.map(\.id))
            local += activities.unconfirmed().filter { serverIDs.contains($0.id) && !ids.contains($0.id) }
        }
        let sleep = activities.manualSleep(onDay: key)
        let sessions = store.completedSessions(from: start, to: end).map(\.summary)
        let missing = detail != nil && detail?.sleep == nil && sleep == nil
        return MyDayInput(day: key, server: .dayDetail(detail, activities: server), local: local,
                          localSessions: sessions, localSleep: sleep, nightGap: missing && nightGap())
    }
}
