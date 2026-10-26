import Foundation
import Observation

/// My Day: the card on Today (always today) and the full screen with its week strip (design.md §7). Reads come
/// only from caches (the day detail, the day's activities, this iPhone's activities and sessions); `load`
/// revalidates through the Repository. Behind `today.my_day`.
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
    /// The tracker catalog was parsed off the main actor (`load`): rows name trackers by it from then on, and by
    /// HealthKit's raw source names before (ui.md §2.3), so Today's first frame never parses it.
    private(set) var namesTrackers = false

    init(state: AppState, store: TrainStore, nightGap: @escaping @MainActor () -> Bool = { false }) {
        self.state = state
        self.store = store
        self.nightGap = nightGap
        date = Calendar.current.startOfDay(for: state.env.clock.now())
    }

    private var env: AppEnvironment { state.env }
    private var calendar: Calendar { .current }
    var today: Date { calendar.startOfDay(for: env.clock.now()) }

    /// The card, the full screen and Strain's list (`today.my_day`, dark until the UI review).
    var isEnabled: Bool { env.flags.isOn(.todayMyDay) }
    /// "Start strength workout" in the ＋ menu follows `train.enabled`; it's the menu's only entry until A2 and A4.
    var showsTrain: Bool { env.flags.isOn(.trainEnabled) }

    // MARK: reads

    /// The day's rows as cached, oldest first (the night first).
    func items(for day: Date) -> [MyDayItem] {
        let input = input(for: day)
        return MyDayAssembler.items(input, catalog: input.catalog(env, ready: namesTrackers), now: env.clock.now())
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
        let detail = state.cachedDayDetail(for: day)
        let cached = detail != nil || state.repository.activitiesFetchedAt(day: key) != nil
        let phase: MyDayContent.Phase = cached || !items.isEmpty ? .ready : failed.contains(key) ? .failed : .loading
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let stale = phase == .ready ? staleSince(key, isToday: isToday) : nil
        let score = detail?.score ?? state.score(for: day)
        return MyDayContent(day: day, isToday: isToday, phase: phase, items: items, staleSince: stale,
                            offersRetry: stale.map { env.clock.now().timeIntervalSince($0) > MyDayContent.retryAfter } ?? false,
                            dayStrain: DayMarker.kind(for: score) == .scored ? score?.strain : nil,
                            title: Fmt.dayTitle(day, today: today))
    }

    /// The full screen's week strip: today and the six days before, the selected one highlighted.
    var week: [DateStrip.Day] {
        DateStrip.week(endingAt: today, selected: date) { state.score(for: $0) }
    }

    func select(_ day: Date) {
        date = calendar.startOfDay(for: day)
    }

    // MARK: adding and editing (`activities.manual`)

    /// Add activity, Add sleep, edit and delete (behind `activities.manual`).
    var addsManually: Bool { env.flags.isOn(.activitiesManual) }

    /// Add activity and Add sleep reach 14 days back (plan D2-1).
    func canAdd(on day: Date) -> Bool {
        let day = calendar.startOfDay(for: day)
        return addsManually && day <= today && day >= DayFormat.shift(today, days: -AddActivityModel.daysBack)
    }

    /// Add sleep is offered while the day has no night (hidden once the tracker's or a typed-in night is there).
    func offersAddSleep(on day: Date, content: MyDayContent) -> Bool {
        canAdd(on: day) && !content.items.contains {
            if case .sleep = $0.kind { return true }
            return false
        }
    }

    func addActivityModel(on day: Date) -> AddActivityModel { AddActivityModel(env: env, day: day) }

    func addSleepModel(on day: Date) -> AddSleepModel {
        AddSleepModel(env: env, day: day, trackerHasNight: state.cachedDayDetail(for: day)?.sleep != nil)
    }

    /// The detail's model for an activity row.
    func detailModel(_ id: UUID, on day: Date) -> ActivityDetailViewModel {
        ActivityDetailViewModel(route: ActivityRoute(id: id, day: day), state: state)
    }

    /// The edit sheet for a row: an editable activity, or a night the user added.
    func editActivity(_ item: MyDayItem, on day: Date) -> AddActivityModel? {
        guard addsManually, item.editable, case .activity(let id) = item.kind else { return nil }
        return detailModel(id, on: day).editModel()
    }

    func editSleep(_ item: MyDayItem) -> AddSleepModel? {
        guard addsManually, item.isManualSleep, case .sleep(let key) = item.kind,
              let night = env.activities.manualSleep(onDay: key) else { return nil }
        return AddSleepModel(env: env, editing: night)
    }

    /// Delete a row after its confirmation: an activity (a tombstone until the platform confirms) or a night the
    /// user added.
    func delete(_ item: MyDayItem, on day: Date) {
        guard addsManually, item.editable else { return }
        switch item.kind {
        case .activity(let id): detailModel(id, on: day).delete()
        case .sleep(let key) where item.isManualSleep: env.uploader.sleepDeleted(day: key)
        default: break
        }
    }

    /// The cached workout behind a row (`WorkoutDetailView`).
    func workout(_ id: UUID, on day: Date) -> Workout? {
        state.cachedDayDetail(for: day)?.workouts.first { $0.id == id }
    }

    /// The list is older than the platform's word: offline, or the day's or the activities' last read failed
    /// (`AppState.failingDayReads`, stored: other reads don't re-render the card). The older of the two fetch
    /// times; nil when fresh or nothing was ever fetched.
    /// Per resource, not per day: the read record keeps one state per resource (`ReadScheduler.states`), so a
    /// failed read of another day's activities marks this day's list too until a read of them succeeds again.
    private func staleSince(_ key: String, isToday: Bool) -> Date? {
        let online = env.isDemo || env.connectivity.isOnline
        let failing = state.failingDayReads
        guard !online || failing.contains(isToday ? .today : .day) || failing.contains(.activities) else { return nil }
        return [state.repository.detailFetchedAt(key), state.repository.activitiesFetchedAt(day: key)].compactMap { $0 }.min()
    }

    // MARK: loads

    /// Revalidates a day: its detail (Today's own read for today: fresh, so no request) and, behind the flag, its
    /// activities, side by side. Cached and fresh → nothing is sent; `force` (Try again) asks now.
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
        // Workouts to name: the catalog's first parse off the main actor, then the rows name trackers by it.
        if !namesTrackers, state.cachedDayDetail(for: day)?.workouts.isEmpty == false {
            _ = await TrackerCatalog.loadBundled()
            namesTrackers = true
        }
    }

    /// The activities read a pull on today started beside the app's pull (tests await it).
    @ObservationIgnored private(set) var pullActivities: Task<Void, Never>?

    /// Pull to refresh on the full screen. The app's pull runs either way (`pullToday`: the upload, today's read
    /// and status; its spinner capped at `AppState.spinnerCap`).
    /// - Today: the day's activities are asked beside it and not waited for; today's detail isn't asked a second
    ///   time.
    /// - A past day: its detail and activities too, side by side with the app's pull; the spinner waits for them
    ///   at most `AppState.spinnerCap` (the reads go on after it), so the whole pull stays within the cap.
    func refresh(_ day: Date, pullToday: @escaping @MainActor () async -> Void) async {
        let day = calendar.startOfDay(for: day)
        if calendar.isDate(day, inSameDayAs: today) {
            let key = DayFormat.string(from: day)
            pullActivities = Task { await self.loadActivities(key, mode: .latest, userInitiated: true) }
            await pullToday()
            return
        }
        async let pulled: Void = pullToday()
        async let reads: Void = loadCapped(day)
        _ = await (pulled, reads)
    }

    /// A past day's forced load, waited for at most `AppState.spinnerCap`.
    private func loadCapped(_ day: Date) async {
        let (done, finish) = AsyncStream<Void>.makeStream()
        Task {
            await self.load(day, force: true)
            finish.finish()
        }
        let clock = env.clock
        // Iterating the stream stops on cancellation (`Task.value` wouldn't), so the cap can end the wait.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in done {} }
            group.addTask { try? await clock.sleep(for: AppState.spinnerCap) }
            await group.next()
            group.cancelAll()
        }
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

    /// Behind `today.my_day` only. A failure keeps what's cached; the read record says it failed (the stale caption).
    private func loadActivities(_ key: String, mode: ReadMode, userInitiated: Bool) async {
        guard isEnabled else { return }
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
    /// "Today", "Yesterday", "Wed 21 Oct" against the environment's clock (`Fmt.dayTitle`); nil: against `.now`.
    var title: String?

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
        return MyDayText.join(parts)
    }
}

extension MyDayInput {
    /// A day as cached: the detail, the platform's activities, this iPhone's activities, sessions and (with the
    /// night) manual sleep. My Day and Strain's list read the same. Fetches only the day's local rows and the
    /// rows of the day's platform activities, wherever those start now.
    @MainActor
    static func cached(day: Date, state: AppState, store: TrainStore, includingSleep: Bool = true,
                       nightGap: @MainActor () -> Bool = { false }) -> MyDayInput {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let key = DayFormat.string(from: start)
        let activities = state.env.activities
        let detail = state.cachedDayDetail(for: start)
        let server = state.repository.activities(day: key)
        var local = activities.snapshots(onDay: key)
        // The day's platform activities whose row on this iPhone starts on another day now (rule 4).
        let onDay = Set(local.map(\.id))
        local += activities.snapshots(ids: server.map(\.id).filter { !onDay.contains($0) })
        let sleep = includingSleep ? activities.manualSleep(onDay: key) : nil
        let sessions = store.completedSessions(from: start, to: end).map(\.summary)
        let missing = includingSleep && sleep == nil && detail.map(MyDayAssembler.mayMissNight) == true
        // The uploader knows more than the rows: offline, retrying, gated, failed, not available yet.
        let uploader = state.env.uploader
        let uploads = Dictionary(local.filter(\.needsUpload).map { ($0.id, uploader.state(for: $0)) },
                                 uniquingKeysWith: { first, _ in first })
        return MyDayInput(day: key, server: .dayDetail(detail, activities: server), local: local, uploads: uploads,
                          localSessions: sessions, localSleep: sleep,
                          sleepUpload: sleep.map(uploader.sleepState(for:)), nightGap: missing && nightGap())
    }

    /// A row needs a tracker's name: the day has workouts (a merged activity names its workout's tracker).
    var namesTrackers: Bool {
        switch server {
        case .dayDetail(let detail, _): return !(detail?.workouts.isEmpty ?? true)
        }
    }

    /// The catalog to name trackers by: the environment's once it's parsed (`ready`) and there is one to name;
    /// otherwise none, and the rows show HealthKit's source names (ui.md §2.3).
    @MainActor
    func catalog(_ env: AppEnvironment, ready: Bool) -> TrackerCatalog {
        namesTrackers && ready ? env.trackerCatalog : .unnamed
    }
}

extension TrackerCatalog {
    /// No trackers: every source keeps its own name (before the catalog is parsed).
    static let unnamed = TrackerCatalog(version: "unnamed", trackers: [], healthAccess: Localized(en: [], de: []))
}
