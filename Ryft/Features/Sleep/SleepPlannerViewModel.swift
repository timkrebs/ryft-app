import Foundation
import Observation
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Sleep → Bedtime (`GET /v1/sleep/plan?wake=HH:MM`, behind `sleep.planner`):
/// three bedtimes for a wake time and the need behind them. With Bedtime & wake set
/// up, the wake time is its next one (`follow`), so the numeral is tonight's bedtime,
/// Today's and the widget's, until the picker moves. A wake-time change asks again
/// after 300 ms of quiet; offline, the last plan stays with its time.
@MainActor
@Observable
final class SleepPlannerViewModel {
    private let state: AppState

    static let cacheKey = "sleep.plan"
    static let debounce: Duration = .milliseconds(300)

    /// The last plan and when it was fetched (offline-first).
    struct Cached: Codable, Equatable {
        let plan: SleepPlan
        let wake: String
        let fetchedAt: Date
    }

    /// The wake time asked for, local: Bedtime & wake's next one while the board follows it, else the picker's.
    private(set) var wake: Date
    private(set) var plan: SleepPlan?
    /// Set when `plan` is a cached one (offline or the request failed).
    private(set) var asOf: Date?
    private(set) var isLoading = false
    /// Why the plan couldn't load with nothing cached: the app's calm sentence, the Details and the button
    /// (`SleepLoadFailure`), never the system's error text.
    private(set) var failure: SleepLoadFailure?
    /// The failure's sentence.
    var error: String? { failure?.message }
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Bedtime & wake's next wake while the board follows it: answers are aligned to it as Tonight's are
    /// (`BedtimePlanner.align`). `nil` once the picker moved, and without a schedule.
    @ObservationIgnored private var followed: Date?
    /// The schedule `follow` saw last: another one is followed even after the picker moved.
    @ObservationIgnored private var followedSchedule: SleepSchedule?
    /// The picker moved since Bedtime was entered or the schedule changed: the board shows the picker's wake time.
    @ObservationIgnored private(set) var pickerMoved = false

    init(state: AppState) {
        self.state = state
        let now = state.env.clock.now()
        wake = Self.defaultWake(state: state, now: now)
        if let cached = state.env.persistence.document(Cached.self, key: Self.cacheKey) {
            plan = cached.plan
            asOf = cached.fetchedAt
        }
    }

    /// The most recent wake time from the week's bedtimes, else 07:00.
    static func defaultWake(state: AppState, now: Date) -> Date {
        let cal = Calendar.current
        let last = state.cachedSleepRange(.week)?.bedtimes.max { $0.wake < $1.wake }?.wake
        let parts = last.map { cal.dateComponents([.hour, .minute], from: $0) } ?? DateComponents(hour: 7, minute: 0)
        return cal.date(bySettingHour: parts.hour ?? 7, minute: parts.minute ?? 0, second: 0, of: now) ?? now
    }

    var wakeText: String { Self.hhmm(wake) }

    static func hhmm(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: what the screen shows

    struct Option: Identifiable, Equatable {
        let share: Int
        let bedtime: Date
        /// Sleep at that share of the need.
        let sleepMin: Int
        var id: Int { share }
    }

    /// 100 %, 85 %, 70 %, earliest first (the API's order).
    var options: [Option] {
        guard let plan else { return [] }
        return [(100, plan.bedtime100), (85, plan.bedtime85), (70, plan.bedtime70)].map { share, bed in
            Option(share: share, bedtime: bed, sleepMin: Int((Double(plan.needMin) * Double(share) / 100).rounded()))
        }
    }

    // MARK: loading

    func load() async {
        await fetch()
    }

    /// Bedtime & wake's next wake (design.md §P5-7.3): on entering Bedtime and whenever the schedule changes, the board
    /// shows tonight's bedtime, the one Today's Tonight card, the reminder and the widget show, until the picker moves.
    /// `tonight` is Bedtime & wake's plan (`BedtimePlanner.plan`), taken when it is for that wake, so the numbers match at
    /// once and offline. Without a schedule nothing changes: the picker's wake (or the last one slept) stays.
    func follow(_ schedule: SleepSchedule?, tonight: SleepPlan? = nil, tonightAsOf: Date? = nil) {
        if schedule != followedSchedule {
            followedSchedule = schedule
            resumeFollowing()
        }
        guard let schedule else {
            followed = nil
            return
        }
        guard !pickerMoved else { return }
        let next = schedule.nextWake(after: state.env.clock.now())
        followed = next
        wake = next
        if let plan, Self.isPlan(plan, for: next) { return }
        if let tonight, Self.isPlan(tonight, for: next) {
            plan = tonight
            asOf = tonightAsOf
            failure = nil
        } else {
            // Another night's plan (the picker's, or one from yesterday) isn't tonight's bedtime.
            plan = nil
            asOf = nil
        }
    }

    /// Leaving Bedtime (or a new schedule): the schedule is followed again, and the picker's pending request dropped.
    func resumeFollowing() {
        guard pickerMoved else { return }
        pickerMoved = false
        pending?.cancel()
        pending = nil
    }

    /// `plan` answers for `wake` (within the minute, as `BedtimePlanner` takes a stored plan).
    private static func isPlan(_ plan: SleepPlan, for wake: Date) -> Bool {
        abs(plan.wake.timeIntervalSince(wake)) <= 60
    }

    /// The picker moved: ask again once it has been still for 300 ms.
    func setWake(_ date: Date) {
        guard date != wake else { return }
        wake = date
        pickerMoved = true
        followed = nil
        pending?.cancel()
        let clock = state.env.clock
        pending = Task { [weak self] in
            do { try await clock.sleep(for: Self.debounce) } catch { return }
            await self?.fetch()
        }
    }

    /// Waits for a debounced request (tests).
    func settle() async { await pending?.value }

    private func fetch() async {
        let hhmm = wakeText
        let target = followed
        guard state.hasDataSource else { return }
        guard state.env.connectivity.isOnline else {
            if plan != nil, asOf == nil { asOf = state.env.clock.now() }
            return
        }
        isLoading = plan == nil
        defer { isLoading = false }
        do {
            var fresh = try await state.env.api.sleepPlan(wake: hhmm)
            guard hhmm == wakeText, target == followed else { return }   // superseded by a newer wake time
            // The API answers for the next `HH:MM`; tonight's wake may be a day later (Friday 07:30 → Saturday 08:00).
            if let target { fresh = BedtimePlanner.align(fresh, to: target) ?? fresh }
            plan = fresh
            asOf = nil
            failure = nil
            state.env.persistence.saveDocument(Cached(plan: fresh, wake: hhmm, fetchedAt: state.env.clock.now()),
                                               key: Self.cacheKey, at: state.env.clock.now())
        } catch where error.isCancellation {
            return
        } catch {
            // 422 only for a malformed time, which the picker can't make.
            assert((error as? APIError)?.status != 422, "sleep/plan rejected wake \(hhmm)")
            guard hhmm == wakeText else { return }
            if plan == nil {
                failure = SleepLoadFailure(error, isOnline: state.isDemo || state.env.connectivity.isOnline,
                                           isDemo: state.isDemo, at: state.env.clock.now())
            } else if asOf == nil {
                asOf = state.env.persistence.document(Cached.self, key: Self.cacheKey)?.fetchedAt ?? state.env.clock.now()
            }
        }
    }
}

// MARK: - Bedtime & wake

/// When you want to wake up (per weekday), how much of your need you aim for, and how long
/// before bed RYFT reminds you. Per account, on this phone, until the platform keeps it
/// (`docs/API_REQUESTS.md` → sleep schedule on the account).
struct SleepSchedule: Codable, Equatable, Sendable {
    /// The share of tonight's need: `GET /v1/sleep/plan` → `bedtime_100/85/70`.
    enum Goal: Int, Codable, CaseIterable, Identifiable, Sendable {
        case peak = 100, perform = 85, getBy = 70
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .peak: return String(localized: "Peak")
            case .perform: return String(localized: "Perform")
            case .getBy: return String(localized: "Get by")
            }
        }

        func bedtime(in plan: SleepPlan) -> Date {
            switch self {
            case .peak: return plan.bedtime100
            case .perform: return plan.bedtime85
            case .getBy: return plan.bedtime70
            }
        }
    }

    /// "HH:MM" per weekday, Monday first.
    var wake: [String]
    /// Edited as weekdays and weekend (two times) rather than each day.
    var sameOnWeekdays = true
    var goal = Goal.peak
    var windDownMin = 30
    var reminderOn = false
    var alarmOn = false

    static let `default` = SleepSchedule(wake: Array(repeating: "06:30", count: 5) + ["08:00", "08:00"])
    static let windDownChoices = [15, 30, 45, 60]

    /// Monday-first index of `date`'s weekday.
    static func index(of date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    /// The night ending on `day` wakes at that weekday's time.
    func wakeTime(on day: Date, calendar: Calendar = .current) -> String { wake[Self.index(of: day, calendar: calendar)] }

    /// The next wake: today's while it is still ahead (the night in progress), else tomorrow's.
    /// The API resolves `wake=HH:MM` the same way, to its next occurrence (`BedtimePlanner.align`).
    func nextWake(after now: Date, calendar: Calendar = .current) -> Date {
        let today = Self.date(wakeTime(on: now, calendar: calendar), on: now, calendar: calendar)
        if today > now { return today }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return Self.date(wakeTime(on: tomorrow, calendar: calendar), on: tomorrow, calendar: calendar)
    }

    /// `hhmm` on `day`, local (a DST gap moves it forward, as the clock does).
    static func date(_ hhmm: String, on day: Date, calendar: Calendar = .current) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return day }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) ?? day
    }

    /// "HH:MM" as the locale writes a time ("6:30 AM", "06:30"); a malformed one as it is.
    static func clock(_ hhmm: String, locale: Locale = .autoupdatingCurrent, calendar: Calendar = .current) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return hhmm }
        return Fmt.time(hour: parts[0], minute: parts[1], locale: locale, calendar: calendar)
    }

    /// Weekdays get the first one's time, the weekend Saturday's (two-time editing).
    mutating func setWeekdays(_ hhmm: String) { for i in 0..<5 { wake[i] = hhmm } }
    mutating func setWeekend(_ hhmm: String) { wake[5] = hhmm; wake[6] = hhmm }

    /// Back to two times: every weekday takes Monday's, the weekend Saturday's (the alarms
    /// would otherwise ring at times no longer shown).
    mutating func setSameOnWeekdays(_ on: Bool) {
        sameOnWeekdays = on
        guard on else { return }
        setWeekdays(wake[0])
        setWeekend(wake[5])
    }

    static func key(_ account: String?) -> String { "sleep.schedule.\(account ?? "signed-out")" }

    static func load(account: String?, defaults: UserDefaults) -> SleepSchedule? {
        let schedule = defaults.data(forKey: key(account)).flatMap { try? JSONDecoder().decode(SleepSchedule.self, from: $0) }
        return schedule?.wake.count == 7 ? schedule : nil
    }

    func save(account: String?, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key(account)) }
    }

    static func remove(account: String?, defaults: UserDefaults) { defaults.removeObject(forKey: key(account)) }
}

/// The night a schedule planned, kept so the morning can compare with what happened.
struct PlannedNight: Codable, Equatable, Sendable {
    let bed: Date
    let wake: Date
}

/// Tonight's bedtime from the schedule and `GET /v1/sleep/plan`, the reminder before it and
/// the wake alarm. Re-asks after syncs that touch today and in the evening refresh; moves the
/// reminders only when the bedtime moved by 10 minutes or more. Behind `sleep.planner`: with
/// the flag off, signed out or on another account, nothing of it stays on the phone.
@MainActor
@Observable
final class BedtimePlanner {
    private let state: AppState
    private let alarms: WakeAlarms

    /// `nil` until set up ("Bedtime & wake") and after "Turn off".
    private(set) var schedule: SleepSchedule?
    /// Tonight's plan, for the schedule's next wake (`align`).
    private(set) var plan: SleepPlan?
    /// Set when `plan` is the last one fetched (offline, or the request failed).
    private(set) var asOf: Date?
    /// Why there is no plan to show (nothing cached): offline, another time zone, or the request's failure in calm words
    /// (`SleepLoadFailure`, as Sleep → Bedtime says it), never the system's error text.
    private(set) var problem: TonightProblem?
    /// The problem's sentence.
    var error: String? { problem?.message }
    /// iOS doesn't allow the alarm (any more): it was turned off, and this says why.
    private(set) var alarmProblem: String?
    /// What each night planned, by its wake day (planned vs actual).
    private var records: [String: PlannedNight] = [:]
    /// The reminders were last set for this bedtime (the 10-minute rule).
    @ObservationIgnored private(set) var scheduledBedtime: Date?
    /// Bumped by every schedule or account change: an answer asked for before it is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var again = false
    /// The alarm times as last set in this process; unknown at launch, so the first look sets them.
    @ObservationIgnored private var alarmsSet: [String]?
    @ObservationIgnored private var alarmsKnown = false
    /// Nothing of RYFT's is scheduled (after `teardown`); unknown at launch.
    @ObservationIgnored private var tornDown = false

    /// A bedtime that moved less than this keeps its reminder.
    static let rescheduleThreshold: TimeInterval = 10 * 60
    /// Reminders ahead: tonight's exact, the following nights from tonight's time in bed.
    static let nightsAhead = 7
    static let reminderPrefix = "bedtime."
    static let wakePrefix = "wake."
    static let cacheKey = "sleep.tonight"

    /// Tonight's plan as last fetched (offline-first).
    struct Cached: Codable, Equatable {
        let plan: SleepPlan
        let fetchedAt: Date
    }

    init(state: AppState, alarms: WakeAlarms? = nil) {
        self.state = state
        self.alarms = alarms ?? SystemWakeAlarms(notifier: state.env.notifier)
        load()
    }

    private var env: AppEnvironment { state.env }
    private var now: Date { env.clock.now() }
    var isEnabled: Bool { env.flags.isOn(.sleepPlanner) }
    /// What the planner asks when it plans (`fetchPlan`): Tonight says offline from it, and plans again once it's back.
    var isOnline: Bool { env.connectivity.isOnline }
    /// The app's clock: Bedtime & wake's page waits its 400 ms on it (`BedtimeScheduleEditor`).
    var clock: AppClock { env.clock }
    /// The schedule to edit: the saved one, or a starting point.
    var draft: SleepSchedule { schedule ?? .default }
    var alarmsRing: Bool { alarms.ringsLikeAnAlarm }

    /// Tonight's bedtime for the goal.
    var bedtime: Date? { plan.flatMap { p in schedule.map { $0.goal.bedtime(in: p) } } }

    /// Profile's row and Bedtime's settings card: "6:30 AM", "6:30 AM · weekend 8:00 AM" ("06:30 · weekend 08:00" on a
    /// 24-hour clock), or "Off".
    var summary: String { Self.summary(schedule) }

    /// `summary` in `locale`: the weekdays' wake time, and the weekend's when it differs, as `Fmt.time` writes a time. Pure
    /// (Tonight's board builds it off the main actor's planner).
    nonisolated static func summary(_ schedule: SleepSchedule?, locale: Locale = .autoupdatingCurrent,
                                    calendar: Calendar = .current) -> String {
        guard let schedule else { return String(localized: "Off") }
        let weekdays = SleepSchedule.clock(schedule.wake[0], locale: locale, calendar: calendar)
        guard schedule.wake[0] != schedule.wake[5] else { return weekdays }
        let weekend = SleepSchedule.clock(schedule.wake[5], locale: locale, calendar: calendar)
        return String(localized: "\(weekdays) · weekend \(weekend)")
    }

    /// "Peak · reminder · alarm".
    var summaryDetail: String? {
        guard let schedule else { return nil }
        var parts = [schedule.goal.title]
        if schedule.reminderOn { parts.append(String(localized: "reminder")) }
        if schedule.alarmOn { parts.append(String(localized: "alarm")) }
        return parts.joined(separator: " · ")
    }

    /// Today shows Tonight from 17:00, and after midnight while tonight's bedtime is still ahead.
    func isEvening(calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        return hour >= 17 || (hour < 5 && (bedtime ?? .distantPast) > now)
    }

    /// This account's schedule, records and last plan.
    private func load() {
        let account = env.auth.accountID
        schedule = SleepSchedule.load(account: account, defaults: env.defaults)
        records = env.defaults.data(forKey: Self.recordsKey(account))
            .flatMap { try? JSONDecoder().decode([String: PlannedNight].self, from: $0) } ?? [:]
        plan = nil
        asOf = nil
        problem = nil
        alarmProblem = nil
        scheduledBedtime = nil
        if let schedule { adoptCached(for: schedule.nextWake(after: now)) }
    }

    /// Signed out or another account signed in: the previous account's reminders, alarms and
    /// widget bedtime go; this account's come back.
    func accountChanged() async {
        generation += 1
        load()
        await teardown()
        await refresh()
    }

    /// Everything this phone scheduled: the reminders, the alarms, the widget's bedtime.
    func teardown() async {
        await cancelReminders()
        await alarms.cancelAll()
        alarmsSet = nil
        alarmsKnown = true
        scheduledBedtime = nil
        state.repository.tonightBedtime = nil
        tornDown = true
    }

    /// The sign-out wipe: every account's schedule and records on this phone.
    static func wipe(defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("sleep.schedule.") || key.hasPrefix("sleep.planned.") {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: editing

    /// Saves the schedule (`nil`: turned off) and plans with it. A reminder turned off goes at
    /// once, online or not; the alarms follow the wake times.
    func update(_ new: SleepSchedule?) async {
        generation += 1
        schedule = new
        let account = env.auth.accountID
        if let new { new.save(account: account, defaults: env.defaults) } else { SleepSchedule.remove(account: account, defaults: env.defaults) }
        scheduledBedtime = nil   // the goal or the wind-down may have moved it
        if new?.alarmOn == true { alarmProblem = nil }
        if new?.reminderOn != true { await cancelReminders() }
        await syncAlarms()
        guard new != nil else {
            plan = nil
            problem = nil
            state.repository.tonightBedtime = nil
            return
        }
        await refresh()
    }

    /// Turning the reminder on asks for notifications (a good moment: you asked for it).
    /// Provisional ones arrive silently in Notification Center, so they ask too. `false` when iOS says no.
    func allowReminders() async -> Bool {
        let status = await env.notifier.authorizationStatus()
        if status == .notDetermined || status == .provisional {
            return (try? await env.notifier.requestAuthorization()) ?? false
        }
        return status == .authorized || status == .ephemeral
    }

    /// The alarm asks for AlarmKit (iOS 26+) or notifications (older iOS).
    func allowAlarm() async -> Bool { await alarms.authorize() }

    /// A failed plan's Sign in (the session ended), as Sleep → Bedtime's: the sign-in screen, Bedtime & wake kept.
    func signIn() async { await state.signInAgain() }

    // MARK: planning

    /// Asks for tonight's plan and keeps the reminders, the alarms and the widget in step with
    /// it. One at a time: a call while one runs makes it run once more when it's done.
    func refresh() async {
        if let running = refreshing {
            again = true
            return await running.value
        }
        let task = Task {
            repeat {
                again = false
                await planTonight()
            } while again
            refreshing = nil
        }
        refreshing = task
        await task.value
    }

    private func planTonight() async {
        guard isEnabled, state.hasDataSource, let schedule else {
            // The flag went off, nobody is signed in or nothing is set up: nothing stays scheduled.
            if !tornDown { await teardown() }
            return
        }
        tornDown = false
        await fetchPlan(for: schedule)
        // After the plan: Tonight doesn't wait for the alarms.
        await syncAlarms()
    }

    private func fetchPlan(for schedule: SleepSchedule) async {
        let gen = generation
        let wake = schedule.nextWake(after: now)
        adoptCached(for: wake)
        if env.connectivity.isOnline {
            do {
                let fresh = try await env.api.sleepPlan(wake: SleepPlannerViewModel.hhmm(wake))
                guard gen == generation else { return }   // the schedule or the account changed meanwhile
                guard let aligned = Self.align(fresh, to: wake) else {
                    if plan == nil { problem = .otherTimeZone }
                    return
                }
                plan = aligned
                asOf = nil
                problem = nil
                env.persistence.saveDocument(Cached(plan: aligned, fetchedAt: now), key: Self.cacheKey, at: now)
            } catch {
                guard gen == generation, !error.isCancellation else { return }
                if plan == nil {
                    // Offline, no answer or refused, in the app's words; the status and request ID go to Details.
                    problem = .failed(SleepLoadFailure(error, isOnline: state.isDemo || env.connectivity.isOnline,
                                                       isDemo: state.isDemo, at: now))
                } else {
                    markCached()
                }
            }
        } else if plan == nil {
            problem = .offline
        } else {
            markCached()
        }
        guard let plan, gen == generation else { return }
        let bed = schedule.goal.bedtime(in: plan)
        state.repository.tonightBedtime = bed
        record(PlannedNight(bed: bed, wake: plan.wake))
        await rescheduleIfMoved(schedule: schedule, plan: plan)
    }

    /// Takes the stored plan when it is for `wake`, and drops one for another night.
    private func adoptCached(for wake: Date) {
        if let plan, abs(plan.wake.timeIntervalSince(wake)) <= 60 { return }
        plan = nil
        asOf = nil
        guard let cached = env.persistence.document(Cached.self, key: Self.cacheKey),
              abs(cached.plan.wake.timeIntervalSince(wake)) <= 60 else { return }
        plan = cached.plan
        asOf = cached.fetchedAt
    }

    /// The plan shown is the stored one: say since when.
    private func markCached() {
        if asOf == nil { asOf = env.persistence.document(Cached.self, key: Self.cacheKey)?.fetchedAt ?? now }
    }

    /// The plan for `wake`. The API takes `HH:MM` and answers for its next occurrence, so on a
    /// morning when tomorrow's wake time is later than now (Friday 07:30, Saturday 08:00) it
    /// answers for today's. Tonight's need is the same either way, and the bedtimes are
    /// `wake − share · in_bed_min`, so they move with the wake by that day
    /// (`docs/API_REQUESTS.md` → `day=`). Any other difference (the profile's time zone isn't
    /// this iPhone's): `nil`.
    static func align(_ plan: SleepPlan, to wake: Date, calendar: Calendar = .current) -> SleepPlan? {
        if abs(plan.wake.timeIntervalSince(wake)) <= 60 { return plan }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: plan.wake),
              abs(nextDay.timeIntervalSince(wake)) <= 60 else { return nil }
        let shift = wake.timeIntervalSince(plan.wake)
        return SleepPlan(wake: wake, needMin: plan.needMin, inBedMin: plan.inBedMin, efficiency: plan.efficiency,
                         bedtime100: plan.bedtime100.addingTimeInterval(shift),
                         bedtime85: plan.bedtime85.addingTimeInterval(shift),
                         bedtime70: plan.bedtime70.addingTimeInterval(shift), basis: plan.basis)
    }

    private func rescheduleIfMoved(schedule: SleepSchedule, plan: SleepPlan) async {
        let bed = schedule.goal.bedtime(in: plan)
        if let last = scheduledBedtime, abs(last.timeIntervalSince(bed)) < Self.rescheduleThreshold { return }
        await scheduleReminders(schedule: schedule, plan: plan)
        scheduledBedtime = bed
    }

    private func cancelReminders() async {
        let pending = await env.notifier.pendingIDs().filter { $0.hasPrefix(Self.reminderPrefix) }
        env.notifier.removePending(ids: pending)
    }

    /// Tonight's reminder from the plan; the following nights from tonight's time in bed at
    /// each night's wake (refined when the app plans those nights). Stops when the schedule
    /// changes meanwhile.
    func scheduleReminders(schedule: SleepSchedule, plan: SleepPlan, calendar: Calendar = .current) async {
        let gen = generation
        await cancelReminders()
        guard schedule.reminderOn else { return }
        let share = Double(schedule.goal.rawValue) / 100
        let sleepMin = Int((Double(plan.needMin) * share).rounded())
        for night in 0..<Self.nightsAhead {
            let wakeDay = calendar.date(byAdding: .day, value: night, to: plan.wake) ?? plan.wake
            let nightWake = night == 0 ? plan.wake
                : SleepSchedule.date(schedule.wakeTime(on: wakeDay, calendar: calendar), on: wakeDay, calendar: calendar)
            let bed = night == 0 ? schedule.goal.bedtime(in: plan)
                : nightWake.addingTimeInterval(-share * Double(plan.inBedMin) * 60)
            let fire = bed.addingTimeInterval(-Double(schedule.windDownMin) * 60)
            guard fire > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Wind down")
            content.body = schedule.goal == .peak
                ? String(localized: "In bed by \(Fmt.time(bed)) for your full \(Fmt.duration(minutes: sleepMin)).")
                : String(localized: "In bed by \(Fmt.time(bed)) for \(schedule.goal.rawValue) % of your need: \(Fmt.duration(minutes: sleepMin)).")
            content.sound = .default
            content.categoryIdentifier = PushCategories.bedtime
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let id = Self.reminderPrefix + DayFormat.string(from: wakeDay)
            guard gen == generation else { return }
            try? await env.notifier.add(UNNotificationRequest(identifier: id, content: content,
                                                              trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }

    /// Sets the wake alarms the schedule asks for, once per change, and once at launch (a
    /// restore, a new iPhone or an iOS update leaves `alarmOn` without alarms). When iOS doesn't
    /// allow them (any more), the alarm turns off and `alarmProblem` says why.
    private func syncAlarms() async {
        let want = isEnabled && state.hasDataSource && schedule?.alarmOn == true ? schedule?.wake : nil
        if alarmsKnown, alarmsSet == want { return }
        alarmsKnown = true
        alarmsSet = want
        guard let want else { return await alarms.cancelAll() }
        do {
            guard await alarms.isAllowed() else { throw WakeAlarmError.notAllowed }
            try await alarms.schedule(want)
        } catch {
            alarmsSet = nil
            await alarms.cancelAll()
            alarmProblem = String(localized: "The wake-up alarm is off: iOS doesn't allow RYFT's alarms. Turn it on again to allow them.")
            guard var off = schedule else { return }
            off.alarmOn = false
            schedule = off
            off.save(account: env.auth.accountID, defaults: env.defaults)
        }
    }

    // MARK: planned vs actual

    private static func recordsKey(_ account: String?) -> String { "sleep.planned.\(account ?? "signed-out")" }

    /// Keyed by the night's wake day; the last 14 are kept. Once the planned bedtime has
    /// passed the night keeps it (after midnight today's strain starts again from zero).
    private func record(_ night: PlannedNight) {
        let day = DayFormat.string(from: night.wake)
        if let kept = records[day], kept.bed <= now || kept == night { return }
        records[day] = night
        if records.count > 14 { for k in records.keys.sorted().dropLast(14) { records[k] = nil } }
        if let data = try? JSONEncoder().encode(records) { env.defaults.set(data, forKey: Self.recordsKey(env.auth.accountID)) }
    }

    /// What the schedule planned for the night ending on `day`.
    func planned(nightEnding day: String) -> PlannedNight? { records[day] }

    /// The user's hero numbers (Profile → Display): Tonight's numeral draws as Sleep's and Strain's do.
    var numeralStyle: DotNumeral.Style { env.settings.heroNumerals.style }

    /// Tonight as the card shows it.
    func tonight(locale: Locale = .autoupdatingCurrent) -> TonightBoard {
        TonightBoard(schedule: schedule, plan: plan, problem: problem, isOnline: isOnline, asOf: asOf,
                     alarmProblem: alarmProblem, locale: locale)
    }
}

// MARK: - Tonight, as the card shows it

/// Why Tonight has no plan to show with nothing cached (PR 6 C §4.13; T5.5's open item): calm words, never the system's
/// error text.
enum TonightProblem: Equatable {
    /// Offline before asking: the plan comes by itself once the iPhone is back online (Tonight asks again then).
    case offline
    /// The platform answered for another time zone than this iPhone's: asking again gives the same answer.
    case otherTimeZone
    /// The request failed: offline, no answer or refused, as Sleep → Bedtime says it (`SleepLoadFailure`), the status and
    /// request ID as Details, and the button that helps: Try again, Sign in once the session ended, none for an outdated app.
    case failed(SleepLoadFailure)

    var message: String {
        switch self {
        case .offline: return String(localized: "Tonight's bedtime needs a connection. It appears once you're online.")
        case .otherTimeZone: return String(localized: "Tonight's plan is for another time zone than this iPhone's.")
        case .failed(let failure): return failure.message
        }
    }

    var systemImage: String {
        switch self {
        case .offline: return "wifi.exclamationmark"
        case .otherTimeZone: return "globe"
        case .failed(let failure): return failure.systemImage
        }
    }

    /// "HTTP 503 · Request ID …" behind Details; none without a response.
    var details: String? {
        if case .failed(let failure) = self { return failure.details }
        return nil
    }

    /// No button offline (the plan comes once online) or for another time zone (trying again doesn't change it).
    var action: RefreshIssue.Reason.Action {
        if case .failed(let failure) = self { return failure.action }
        return .noButton
    }
}

/// Tonight as values (PR 6 C §4.13): which state the card is in, the bedtime as the numeral and its meridiem, the line under
/// it, the three goals, the "As of" note of a plan fetched earlier, why there is none, and what VoiceOver reads. Pure:
/// tests build it without a view.
struct TonightBoard: Equatable {
    enum Look: Equatable {
        /// No Bedtime & wake: the outline card, the sentence and Set up.
        case notSetUp
        /// A plan, fresh or the last one fetched ("As of"): the glow tile, then Why this need and Bedtime & wake.
        case planned
        /// Asking with nothing cached: the outline card, the unlit numeral, "Planning tonight…". Never a spinner.
        case planning
        /// Offline with nothing cached: the offline line; the plan comes once online. Never the planning outline.
        case offline
        /// The plan couldn't load with nothing cached: the calm sentence, Details and Try again (or Sign in).
        case failed
    }

    /// One goal in the tile: the marker (filled for the user's goal, a ring for the others), "Peak · 100 %", the bedtime.
    struct Goal: Equatable, Identifiable {
        let goal: SleepSchedule.Goal
        /// "Peak · 100 %".
        let title: String
        /// "10:41 PM".
        let time: String
        let isGoal: Bool
        /// "Peak, 100 percent, 10:41 PM, your goal".
        let spoken: String
        var id: Int { goal.rawValue }
    }

    let look: Look
    /// "10:41" and "PM" (`nil` on a 24-hour clock); `nil` digits draw the unlit "00:00".
    let digits: String?
    let meridiem: String?
    /// "for 100 % · wake 6:30 AM · need 8:18".
    let line: String
    let goals: [Goal]
    /// "As of 5:42 PM": the plan is the last one fetched (offline, or the request failed).
    let asOf: String?
    /// The tile as one VoiceOver summary: the bedtime, the wake and the need, "As of", then the three goals.
    let spoken: String
    /// Why there is no plan (offline, failed).
    let problem: TonightProblem?
    /// The need, term by term (Why this need).
    let plan: SleepPlan?
    /// The wake alarm couldn't be set: an amber notice above the group.
    let alarmProblem: String?
    /// Bedtime & wake's row value (`BedtimePlanner.summary`: "6:30 AM · weekend 8:00 AM").
    let summary: String

    /// - Parameters:
    ///   - isOnline: what the planner asks before planning. Offline with nothing cached is always the offline line; online,
    ///     an offline problem from before is not shown while Tonight asks again.
    init(schedule: SleepSchedule?, plan: SleepPlan?, problem: TonightProblem? = nil, isOnline: Bool = true,
         asOf: Date? = nil, alarmProblem: String? = nil, locale: Locale = .autoupdatingCurrent) {
        self.alarmProblem = alarmProblem
        summary = BedtimePlanner.summary(schedule, locale: locale)
        guard let schedule, let plan else {
            self.plan = nil
            digits = nil
            meridiem = nil
            line = ""
            goals = []
            self.asOf = nil
            if schedule == nil {
                look = .notSetUp
                self.problem = nil
            } else if !isOnline {
                look = .offline
                self.problem = .offline
            } else if let problem, problem != .offline {
                look = .failed
                self.problem = problem
            } else {
                look = .planning
                self.problem = nil
            }
            spoken = look == .planning ? Self.planningText : ""
            return
        }
        look = .planned
        self.plan = plan
        self.problem = nil
        let bed = schedule.goal.bedtime(in: plan)
        let parts = Fmt.clockParts(bed, locale: locale)
        digits = parts.digits
        meridiem = parts.meridiem
        let wake = Fmt.time(plan.wake, locale: locale)
        let need = Fmt.clock(minutes: plan.needMin)
        // swiftlint:disable:next line_length
        line = String(localized: "for \(schedule.goal.rawValue) % · wake \(wake) · need \(need)", comment: "Today's Tonight tile, under the bedtime: the share of tonight's need it gives, the wake time and the need as hours:minutes (\"for 100 % · wake 6:30 AM · need 8:18\").")
        goals = SleepSchedule.Goal.allCases.map { option in
            let time = Fmt.time(option.bedtime(in: plan), locale: locale)
            var spoken = [option.title, String(localized: "\(option.rawValue) percent"), time]
            if option == schedule.goal {
                spoken.append(String(localized: "your goal",
                                     comment: "VoiceOver on Sleep → Bedtime's go-to-bed tile, after the goal that is yours (the filled marker)."))
            }
            return Goal(goal: option, title: String(localized: "\(option.title) · \(option.rawValue) %"), time: time,
                        isGoal: option == schedule.goal, spoken: spoken.joined(separator: ", "))
        }
        let asOfText = asOf.map { String(localized: "As of \(Fmt.time($0, locale: locale))") }
        self.asOf = asOfText
        let bedTime = Fmt.time(bed, locale: locale), spokenNeed = Fmt.spokenDuration(minutes: plan.needMin, locale: locale)
        // swiftlint:disable:next line_length
        let summary = String(localized: "In bed by \(bedTime), for \(schedule.goal.rawValue) percent of your need. Wake \(wake), need \(spokenNeed).", comment: "VoiceOver on Today's Tonight tile: tonight's bedtime for the goal, its share of the need, the wake time and the need (\"In bed by 10:41 PM, for 100 percent of your need. Wake 6:30 AM, need 8 hours 18 minutes.\").")
        spoken = ([summary] + (asOfText.map { [$0 + "."] } ?? []) + goals.map { $0.spoken + "." }).joined(separator: " ")
    }

    /// The planning outline's line, and what VoiceOver reads for it.
    static var planningText: String {
        String(localized: "Planning tonight…", comment: "Today's Tonight card while tonight's plan loads with nothing saved on this iPhone.")
    }
}

// MARK: - Bedtime & wake, as the page edits it

/// Bedtime & wake's page (PR 6 C §4.13): the schedule as edited. A change shows at once and is saved 400 ms after the last
/// one (a wheel sends many) and when the page goes, one save after the other, so the last change is the one kept. Saving is
/// the planner's, on this iPhone, online or not. A switch iOS refuses stays off and says why; an alarm iOS stops allowing
/// goes back off with the planner's sentence (`alarmProblem`).
@MainActor
@Observable
final class BedtimeScheduleEditor {
    let planner: BedtimePlanner
    private(set) var draft: SleepSchedule
    /// iOS said no: the switch stayed off, and its group says why until it is turned on.
    private(set) var reminderRefused = false
    private(set) var alarmRefused = false
    /// Changed here: only then does leaving save (opening "Set up" and going back doesn't).
    @ObservationIgnored private(set) var edited = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var lastSave: Task<Void, Never>?

    /// Quiet after the last change before it is saved.
    static let saveDelay: Duration = .milliseconds(400)

    init(planner: BedtimePlanner) {
        self.planner = planner
        draft = planner.draft
    }

    /// A change: shown at once, saved once the page has been still for `saveDelay`.
    func edit(_ change: (inout SleepSchedule) -> Void) {
        var next = draft
        change(&next)
        guard next != draft else { return }
        draft = next
        edited = true
        pending?.cancel()
        let clock = planner.clock
        pending = Task { [weak self] in
            do { try await clock.sleep(for: Self.saveDelay) } catch { return }
            // A later change replaced this one while it woke: that one saves.
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            self.save(self.draft)
        }
    }

    /// The page goes: a change made just before still counts.
    func leave() {
        pending?.cancel()
        pending = nil
        guard edited, draft != planner.schedule else { return }
        save(draft)
    }

    /// Back to "Off": no reminders, no alarms, no Tonight. Waits for the saves before it.
    func turnOff() async {
        pending?.cancel()
        pending = nil
        edited = false
        await save(nil).value
    }

    /// The reminder asks for notifications as it's turned on. `false`: iOS said no, the switch stays off.
    @discardableResult
    func setReminder(_ on: Bool) async -> Bool {
        guard on else {
            edit { $0.reminderOn = false }
            return true
        }
        guard await planner.allowReminders() else {
            reminderRefused = true
            return false
        }
        reminderRefused = false
        edit { $0.reminderOn = true }
        return true
    }

    /// The alarm asks for AlarmKit (or notifications) as it's turned on. `false`: iOS said no, the switch stays off.
    @discardableResult
    func setAlarm(_ on: Bool) async -> Bool {
        guard on else {
            edit { $0.alarmOn = false }
            return true
        }
        guard await planner.allowAlarm() else {
            alarmRefused = true
            return false
        }
        alarmRefused = false
        edit { $0.alarmOn = true }
        return true
    }

    /// The planner turned the alarm off (iOS no longer allows it): the switch goes back off. Nothing to save: the planner
    /// saved it, and a save still waiting takes the draft as it is now.
    func alarmWentOff() {
        guard planner.schedule?.alarmOn == false, draft.alarmOn else { return }
        draft.alarmOn = false
    }

    /// Waits for the save in waiting and the saves on their way (tests).
    func settle() async {
        await pending?.value
        await lastSave?.value
    }

    /// Hands `schedule` to the planner once the saves before it are done. An alarm iOS doesn't allow (any more) can't be
    /// set: the planner turns it off and says why (`alarmProblem`, amber in the alarm's group), and the switch goes back.
    @discardableResult
    private func save(_ schedule: SleepSchedule?) -> Task<Void, Never> {
        let before = lastSave
        let turn = Task { [weak self, planner] in
            await before?.value
            await planner.update(schedule)
            if schedule?.alarmOn == true, planner.schedule?.alarmOn == false { self?.alarmWentOff() }
        }
        lastSave = turn
        return turn
    }
}

enum WakeAlarmError: Error {
    case notAllowed
}

// MARK: - wake alarm

/// The wake alarm, behind a seam: AlarmKit on iOS 26+ (rings through Silent mode and Focus, Stop
/// and Snooze), a notification at the wake time below (it doesn't ring like an alarm).
@MainActor
protocol WakeAlarms: AnyObject {
    /// AlarmKit (a real alarm) or a notification.
    var ringsLikeAnAlarm: Bool { get }
    /// Asks iOS when it hasn't been asked.
    func authorize() async -> Bool
    /// Allowed already; never asks (launch, a restore).
    func isAllowed() async -> Bool
    /// Replaces RYFT's wake alarms: one per weekday at `times` ("HH:MM", Monday first).
    func schedule(_ times: [String]) async throws
    func cancelAll() async
}

extension WakeAlarms {
    /// The weekdays (Monday-first indices) that share each time, earliest first: one repeating
    /// alarm per time.
    static func groups(_ times: [String]) -> [(time: String, days: [Int])] {
        var groups: [String: [Int]] = [:]
        for (i, hhmm) in times.enumerated() { groups[hhmm, default: []].append(i) }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }
}

final class SystemWakeAlarms: WakeAlarms {
    private let notifier: Notifier

    init(notifier: Notifier) {
        self.notifier = notifier
    }

    var ringsLikeAnAlarm: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    func authorize() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return await AlarmKitWake.authorize() }
        #endif
        // Provisional notifications arrive silently: not a wake-up.
        let status = await notifier.authorizationStatus()
        if status == .notDetermined || status == .provisional { return (try? await notifier.requestAuthorization()) ?? false }
        return status == .authorized || status == .ephemeral
    }

    func isAllowed() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return AlarmManager.shared.authorizationState == .authorized }
        #endif
        let status = await notifier.authorizationStatus()
        return status == .authorized || status == .ephemeral
    }

    func schedule(_ times: [String]) async throws {
        await cancelAll()
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            try await AlarmKitWake.schedule(times)
            return
        }
        #endif
        // Below iOS 26: a notification at each weekday's wake time (it won't ring like an alarm).
        // Time Sensitive breaks through Focus once the capability is added in Xcode; without it
        // iOS delivers it as an ordinary notification.
        for (i, hhmm) in times.enumerated() {
            let parts = hhmm.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Time to get up")
            content.body = String(localized: "Your wake time from Bedtime & wake.")
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            // Calendar weekday: Sunday 1 … Saturday 7; index 0 is Monday.
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: parts[0], minute: parts[1],
                                                                                     weekday: (i + 1) % 7 + 1),
                                                        repeats: true)
            try await notifier.add(UNNotificationRequest(identifier: BedtimePlanner.wakePrefix + "\(i)", content: content,
                                                         trigger: trigger))
        }
    }

    func cancelAll() async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { AlarmKitWake.cancelAll() }
        #endif
        let ours = await notifier.pendingIDs().filter { $0.hasPrefix(BedtimePlanner.wakePrefix) }
        notifier.removePending(ids: ours)
    }
}

/// Records what it was asked to do (tests, previews).
final class MockWakeAlarms: WakeAlarms {
    var ringsLikeAnAlarm = true
    /// What iOS answers when asked, and whether it was allowed already.
    var allows = true
    var allowed = true
    private(set) var scheduled: [String]?
    private(set) var schedulings = 0
    private(set) var cancellations = 0

    func authorize() async -> Bool {
        allowed = allows
        return allows
    }

    func isAllowed() async -> Bool { allowed }

    func schedule(_ times: [String]) async throws {
        schedulings += 1
        scheduled = times
    }

    func cancelAll() async {
        cancellations += 1
        scheduled = nil
    }
}

#if canImport(AlarmKit)
/// Keep identical to `RyftWidgets/WakeAlarmMetadata.swift`: the alarm's Live Activity (the
/// snooze countdown) decodes it in the widget extension.
@available(iOS 26.0, *)
struct WakeAlarmMetadata: AlarmMetadata {}

/// The wake alarm with AlarmKit: one weekly alarm per wake time (weekdays sharing it), Stop and
/// Snooze (9 minutes).
@available(iOS 26.0, *)
@MainActor
enum AlarmKitWake {
    static let snooze: TimeInterval = 9 * 60

    static func authorize() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized: return true
        case .denied: return false
        case .notDetermined: return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
        @unknown default: return false
        }
    }

    static func schedule(_ times: [String]) async throws {
        let weekdays: [Locale.Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        for group in SystemWakeAlarms.groups(times) {
            let parts = group.time.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let schedule = Alarm.Schedule.relative(.init(time: .init(hour: parts[0], minute: parts[1]),
                                                         repeats: .weekly(group.days.map { weekdays[$0] })))
            let snoozeButton = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white, systemImageName: "zzz")
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                // The system draws Stop itself from 26.1 on.
                alert = AlarmPresentation.Alert(title: LocalizedStringResource("Time to get up"),
                                                secondaryButton: snoozeButton, secondaryButtonBehavior: .countdown)
            } else {
                alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource("Time to get up"),
                    stopButton: AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.circle"),
                    secondaryButton: snoozeButton, secondaryButtonBehavior: .countdown)
            }
            let countdown = AlarmPresentation.Countdown(title: LocalizedStringResource("Snoozing"))
            let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert, countdown: countdown),
                                             metadata: WakeAlarmMetadata(), tintColor: .teal)
            let configuration = AlarmManager.AlarmConfiguration(
                countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: snooze),
                schedule: schedule, attributes: attributes)
            _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
        }
    }

    static func cancelAll() {
        for alarm in (try? AlarmManager.shared.alarms) ?? [] {
            try? AlarmManager.shared.cancel(id: alarm.id)
        }
    }
}
#endif
