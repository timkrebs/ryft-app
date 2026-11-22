import Foundation
import Observation
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

/// Sleep → Bedtime (`GET /v1/sleep/plan?wake=HH:MM`, behind `sleep.planner`):
/// three bedtimes for a wake time and the need behind them. With Bedtime & wake set
/// up, the wake time is its next one (`follow`), so the numeral is tonight's bedtime,
/// Today's and the widget's, until the picker moves. A wake-time change asks again
/// after 300 ms of quiet; offline, the last plan stays with its time. The account's last plan is kept in its store, demo
/// data's in memory only (`AppEnvironment.accountDocuments`); demo data plans offline too, on the phone.
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
    /// Bumped by `accountChanged()`: an answer asked for before it is dropped.
    @ObservationIgnored private var generation = 0
    /// Bedtime & wake's next wake while the board follows it: answers are aligned to it as Tonight's are
    /// (`BedtimePlanner.align`). `nil` once the picker moved, and without a schedule.
    @ObservationIgnored private var followed: Date?
    /// The schedule `follow` saw last: another one is followed even after the picker moved.
    @ObservationIgnored private var followedSchedule: SleepSchedule?
    /// The picker moved since Bedtime was entered or the schedule changed: the board shows the picker's wake time.
    @ObservationIgnored private(set) var pickerMoved = false

    /// Demo data's last plan: in memory only, never in the account's store (`AppEnvironment.accountDocuments`).
    @ObservationIgnored private var demoCached: Cached?

    init(state: AppState) {
        self.state = state
        let now = state.env.clock.now()
        wake = Self.defaultWake(state: state, now: now)
        adoptCached()
    }

    /// Signed out, another account, or the Demo data switch (an account-state forgetter, `ScreenModels`): the previous side's
    /// plan goes, a request on its way is dropped, and so do the wake time it asked for and the schedule it followed (they
    /// were that side's Bedtime & wake); this side's last plan for the wake time shown stays until it's asked again.
    func accountChanged() {
        pending?.cancel()
        pending = nil
        generation += 1
        demoCached = nil
        plan = nil
        asOf = nil
        failure = nil
        isLoading = false
        wake = Self.defaultWake(state: state, now: state.env.clock.now())
        pickerMoved = false
        followed = nil
        followedSchedule = nil
        adoptCached()
    }

    /// This side's last plan, as kept: the account's in its store, demo data's in memory.
    private var cached: Cached? {
        guard let documents = state.env.accountDocuments else { return demoCached }
        return documents.document(Cached.self, key: Self.cacheKey)
    }

    /// The last plan, when it was asked for the wake time shown (another one's bedtimes aren't this one's).
    private func adoptCached() {
        guard let cached, cached.wake == wakeText else { return }
        plan = cached.plan
        asOf = cached.fetchedAt
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
        let asked = generation
        guard state.hasDataSource else { return }
        // Demo data plans on the phone, with no network to lose (as Tonight's `BedtimePlanner`).
        guard state.isDemo || state.env.connectivity.isOnline else {
            if plan != nil, asOf == nil { asOf = state.env.clock.now() }
            return
        }
        isLoading = plan == nil
        defer { isLoading = false }
        do {
            var fresh = try await state.env.api.sleepPlan(wake: hhmm)
            guard hhmm == wakeText, target == followed else { return }   // superseded by a newer wake time
            guard asked == generation else { return }   // the previous account's (or side's): not this one's to show
            // The API answers for the next `HH:MM`; tonight's wake may be a day later (Friday 07:30 → Saturday 08:00).
            if let target { fresh = BedtimePlanner.align(fresh, to: target) ?? fresh }
            plan = fresh
            asOf = nil
            failure = nil
            keep(Cached(plan: fresh, wake: hhmm, fetchedAt: state.env.clock.now()))
        } catch where error.isCancellation {
            return
        } catch {
            // 422 only for a malformed time, which the picker can't make.
            assert((error as? APIError)?.status != 422, "sleep/plan rejected wake \(hhmm)")
            guard hhmm == wakeText, asked == generation else { return }
            if plan == nil {
                failure = SleepLoadFailure(error, isOnline: state.isDemo || state.env.connectivity.isOnline,
                                           isDemo: state.isDemo, at: state.env.clock.now())
            } else if asOf == nil {
                asOf = cached?.fetchedAt ?? state.env.clock.now()
            }
        }
    }

    private func keep(_ fresh: Cached) {
        guard let documents = state.env.accountDocuments else {
            demoCached = fresh
            return
        }
        documents.saveDocument(fresh, key: Self.cacheKey, at: state.env.clock.now())
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
/// the flag off, signed out or on another account, nothing of it stays on the phone. Demo data
/// plans, edits and turns off a schedule of its own, in memory only, and sets no reminder or
/// alarm: the account's go on as they were (`keepsTheAccounts`).
///
/// A change is saved on this iPhone at once (`commit`); what follows from it (the reminders, the alarms, tonight's plan) runs
/// in passes, one at a time, each with the schedule as it is when it starts (`refresh`). A pass stops at its next step once
/// the schedule or the account changed, and the next pass does the work with what is current: nothing waits behind a plan
/// on its way (a change cancels it), and nothing lands on an account that has gone.
@MainActor
@Observable
final class BedtimePlanner {
    private let state: AppState
    private let alarms: WakeAlarms

    /// Whose a change or a pass is: the account (and demo data or not) and the store's contents when it was made. Work for
    /// an owner that isn't current any more (signed out, wiped, another account, a final 401) writes and schedules nothing.
    struct Owner: Equatable {
        let account: AccountBinding
        let epoch: Int
    }

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
    /// The reminder is on, but there is no plan for the wake time and none was ever fetched to estimate one from: no
    /// reminder is set until there is (Bedtime & wake says so). With an earlier plan they're set from it (`remindWithoutAPlan`).
    private(set) var remindersWaiting = false
    /// What each night planned, by its wake day (planned vs actual).
    private var records: [String: PlannedNight] = [:]
    /// The reminders were last set for this bedtime (the 10-minute rule).
    @ObservationIgnored private(set) var scheduledBedtime: Date?
    /// Bumped by every schedule or account change: an answer asked for before it is dropped.
    @ObservationIgnored private var generation = 0
    /// The passes running (`refresh`), and whether another one is owed when this one ends.
    @ObservationIgnored private var effects: Task<Void, Never>?
    @ObservationIgnored private var again = false
    /// A change was saved since the last pass began: its reminders and alarms go before the plan.
    @ObservationIgnored private var changed = false
    /// Another account (or none) since the last pass: everything the previous one scheduled goes first.
    @ObservationIgnored private var needsTeardown = false
    /// Tonight's plan on its way: a change cancels it (its answer would be for the schedule before).
    @ObservationIgnored private var asking: Task<SleepPlan, Error>?
    /// The alarm times as last set in this process; unknown at launch, so the first look sets them.
    @ObservationIgnored private var alarmsSet: [String]?
    @ObservationIgnored private var alarmsKnown = false
    /// Nothing of RYFT's is scheduled (after `teardown`); unknown at launch.
    @ObservationIgnored private var tornDown = false
    /// Bedtime & wake's page, one for every way in (Profile, Tonight, Sleep → Bedtime): one copy being edited, one save at a
    /// time.
    @ObservationIgnored private(set) lazy var editor = BedtimeScheduleEditor(planner: self)
    /// The one writer of the local reminders (ADR 0024): the app's, through its state.
    var reminders: ReminderScheduler { state.reminders }

    /// A bedtime that moved less than this keeps its reminder.
    static let rescheduleThreshold: TimeInterval = 10 * 60
    /// Reminders ahead: tonight's exact, the following nights from tonight's time in bed.
    static let nightsAhead = 7
    static let reminderPrefix = "bedtime."
    static let wakePrefix = "wake."
    /// `wake.0` (Monday) … `wake.6`: the notifications below iOS 26.
    static let wakeIDs = (0..<7).map { wakePrefix + "\($0)" }
    static let cacheKey = "sleep.tonight"

    /// Tonight's plan as last fetched (offline-first).
    struct Cached: Codable, Equatable {
        let plan: SleepPlan
        let fetchedAt: Date
    }

    /// Demo data's last plan: in memory only, never in the account's store (`AppEnvironment.accountDocuments`), so neither
    /// side plans, reminds or shows from the other's.
    @ObservationIgnored private var demoCached: Cached?
    /// Demo data's schedule and planned nights: in memory only, gone with the side (`forget`), never the account's (`shelf`).
    @ObservationIgnored private var demoSchedule: SleepSchedule?
    @ObservationIgnored private var demoRecords: [String: PlannedNight] = [:]
    /// Whose reminders and alarms iOS holds: the account signed in when they were last taken away (or at launch). Demo data
    /// sets none and leaves these ringing, until that account isn't the one signed in any more (`keepsTheAccounts`).
    @ObservationIgnored private var systemAccount: String?

    init(state: AppState, alarms: WakeAlarms? = nil) {
        self.state = state
        self.alarms = alarms ?? SystemWakeAlarms(notifier: state.env.notifier)
        systemAccount = state.env.auth.accountID
        load()
    }

    private var env: AppEnvironment { state.env }
    private var now: Date { env.clock.now() }
    /// Who is signed in now, and the store's epoch (`Owner`).
    var owner: Owner { Owner(account: AccountBinding(env), epoch: env.persistence.epoch.current) }
    var isEnabled: Bool { env.flags.isOn(.sleepPlanner) }
    /// What the planner asks when it plans (`fetchPlan`): Tonight says offline from it, and plans again once it's back. Demo
    /// data plans on the phone, with no network to lose.
    var isOnline: Bool { state.isDemo || env.connectivity.isOnline }
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
        // swiftlint:disable:next line_length
        return String(localized: "\(weekdays) · weekend\u{00A0}\(weekend)", comment: "Bedtime & wake's summary (Profile's row, Tonight's and Sleep's Bedtime & wake rows): the weekdays' wake time, then the weekend's. A no-break space keeps \"weekend\" with its time when the row wraps (\"6:30 AM · weekend 8:00 AM\").")
    }

    /// "Peak · reminder · alarm".
    var summaryDetail: String? { summaryDetailParts?.joined(separator: " · ") }

    /// The detail's parts ("Peak", "reminder", "alarm"), which Profile's row stands one per line from AX1 (`PartsLine`).
    var summaryDetailParts: [String]? { Self.summaryDetailParts(schedule) }

    /// `summaryDetailParts` for `schedule`; nil without one.
    static func summaryDetailParts(_ schedule: SleepSchedule?) -> [String]? {
        guard let schedule else { return nil }
        var parts = [schedule.goal.title]
        if schedule.reminderOn { parts.append(String(localized: "reminder")) }
        if schedule.alarmOn { parts.append(String(localized: "alarm")) }
        return parts
    }

    /// Today shows Tonight from 17:00, and after midnight while tonight's bedtime is still ahead.
    func isEvening(calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        return hour >= 17 || (hour < 5 && (bedtime ?? .distantPast) > now)
    }

    /// This side's schedule, records and last plan.
    private func load() {
        schedule = savedSchedule()
        records = savedRecords()
        plan = nil
        asOf = nil
        problem = nil
        alarmProblem = nil
        remindersWaiting = false
        scheduledBedtime = nil
        if let schedule { adoptCached(for: schedule.nextWake(after: now)) }
    }

    /// Signed out, another account, a wipe or the Demo data switch, at once (an account-state forgetter, `ScreenModels`):
    /// the previous account's (or side's) plan, an answer on its way, a change it was editing and the widget's bedtime go,
    /// and this side's schedule shows. Demo data's schedule, nights and plan go with the side: turned on again, it starts
    /// afresh. What was scheduled on iOS goes with the next pass (`refresh`), and demo data's side keeps the account's.
    func forget() {
        generation += 1
        asking?.cancel()
        editor.discard()
        demoCached = nil
        demoSchedule = nil
        demoRecords = [:]
        load()
        needsTeardown = true
        state.repository.tonightBedtime = nil
    }

    /// `forget`, then this side's pass: its plan, and the account's reminders and alarms (RyftApp, at a sign-in or another
    /// account).
    func accountChanged() async {
        forget()
        await refresh()
    }

    /// Demo data is shown, and iOS holds the signed-in account's reminders and alarms: they stay as they are (Demo data
    /// sets, moves and takes away none). Once that account signs out, or another signs in, they go on either side.
    private var keepsTheAccounts: Bool { env.isDemo && systemAccount == env.auth.accountID }

    /// Everything this phone scheduled: the reminders, the alarms (but not the account's while demo data is shown,
    /// `keepsTheAccounts`), the widget's bedtime.
    private func teardown() async {
        if !keepsTheAccounts {
            await removeReminders()
            await alarms.cancelAll()
            alarmsSet = nil
            alarmsKnown = true
            tornDown = true
            systemAccount = env.auth.accountID
        }
        scheduledBedtime = nil
        remindersWaiting = false
        state.repository.tonightBedtime = nil
    }

    // MARK: the side's schedule

    /// Where the side's schedule and planned nights are kept: the account's on this iPhone under its ID, demo data's in
    /// memory only. Every read and write goes through it, so neither side reads, changes or removes the other's.
    private enum Shelf {
        case account(String?)
        case demo
    }

    private var shelf: Shelf { env.isDemo ? .demo : .account(env.auth.accountID) }

    private func savedSchedule() -> SleepSchedule? {
        switch shelf {
        case .demo: return demoSchedule
        case .account(let id): return SleepSchedule.load(account: id, defaults: env.defaults)
        }
    }

    /// `nil`: turned off.
    private func save(_ schedule: SleepSchedule?) {
        switch shelf {
        case .demo:
            demoSchedule = schedule
        case .account(let id):
            if let schedule {
                schedule.save(account: id, defaults: env.defaults)
            } else {
                SleepSchedule.remove(account: id, defaults: env.defaults)
            }
        }
    }

    private func savedRecords() -> [String: PlannedNight] {
        switch shelf {
        case .demo:
            return demoRecords
        case .account(let id):
            return env.defaults.data(forKey: Self.recordsKey(id))
                .flatMap { try? JSONDecoder().decode([String: PlannedNight].self, from: $0) } ?? [:]
        }
    }

    private func saveRecords() {
        switch shelf {
        case .demo:
            demoRecords = records
        case .account(let id):
            if let data = try? JSONEncoder().encode(records) { env.defaults.set(data, forKey: Self.recordsKey(id)) }
        }
    }

    /// The sign-out wipe: every account's schedule and records on this phone.
    static func wipe(defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("sleep.schedule.") || key.hasPrefix("sleep.planned.") {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: editing

    /// Saves `new` (`nil`: turned off) on this iPhone at once, online or not, and starts a pass for what follows from it
    /// without waiting for it: a reminder turned off goes and the alarms follow the wake times before the plan is asked
    /// for; a plan on its way for the schedule before is cancelled. `false`, and nothing saved, when `owner` isn't current:
    /// a change made before a sign-out, a wipe or another account's sign-in never lands on the next one.
    @discardableResult
    func commit(_ new: SleepSchedule?, for owner: Owner) -> Bool {
        guard owner == self.owner else { return false }
        generation += 1
        schedule = new
        save(new)
        if new != nil { env.analytics.track(.featureUsed(.sleepScheduleSaved)) }
        scheduledBedtime = nil   // the goal or the wind-down may have moved it
        changed = true
        if new?.alarmOn == true { alarmProblem = nil }
        if let new {
            // A plan for another wake time isn't tonight's: Tonight plans again (or shows the stored one for this wake).
            adoptCached(for: new.nextWake(after: now))
            if plan == nil {
                // Dropped: "Planning tonight…", not the failure of the plan before; the widget shows no bedtime until
                // RYFT has planned this one.
                problem = nil
                state.repository.tonightBedtime = nil
            }
        } else {
            plan = nil
            asOf = nil
            problem = nil
            remindersWaiting = false
            state.repository.tonightBedtime = nil
        }
        asking?.cancel()
        startPasses()
        return true
    }

    /// `commit` for whoever is signed in now, then waits for its pass.
    func update(_ new: SleepSchedule?) async {
        commit(new, for: owner)
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

    /// Asks for tonight's plan and keeps the reminders, the alarms and the widget in step with it, in passes, one at a time:
    /// a call while one runs makes it run once more when it's done (with the schedule as it is then), and waits for that.
    func refresh() async {
        startPasses()
        await effects?.value
    }

    /// Waits for the passes running, without asking for another (Turn off, tests).
    func settle() async {
        await effects?.value
    }

    private func startPasses() {
        guard effects == nil else {
            again = true
            return
        }
        effects = Task {
            repeat {
                again = false
                await pass()
            } while again
            effects = nil
        }
    }

    /// One pass with the schedule and the account as they are when it starts. After every step that waits it stops if
    /// either changed: the pass the change asked for does the work again with what is current.
    private func pass() async {
        let gen = generation, owner = self.owner
        func current() -> Bool { gen == generation && owner == self.owner }
        if needsTeardown {
            // Another account: what the previous one scheduled goes before anything of this one's is set.
            needsTeardown = false
            await teardown()
            guard current() else { return }
        }
        guard isEnabled, state.hasDataSource, let schedule else {
            // The flag went off, nobody is signed in or nothing is set up: nothing stays scheduled.
            if !tornDown { await teardown() }
            return
        }
        tornDown = false
        if changed {
            // A change's reminders and alarms don't need the network: they go first, so they're right however long the
            // plan takes, or offline.
            changed = false
            if !schedule.reminderOn {
                await cancelReminders()
                remindersWaiting = false
            }
            guard current() else { return }
            await syncAlarms(gen: gen, owner: owner)
            guard current() else { return }
        }
        await fetchPlan(for: schedule, gen: gen, owner: owner)
        guard current() else { return }
        // After the plan: Tonight doesn't wait for the alarms (the first look at launch).
        await syncAlarms(gen: gen, owner: owner)
    }

    private func fetchPlan(for schedule: SleepSchedule, gen: Int, owner: Owner) async {
        func current() -> Bool { gen == generation && owner == self.owner }
        let wake = schedule.nextWake(after: now)
        adoptCached(for: wake)
        if isOnline {
            let api = env.api, hhmm = SleepPlannerViewModel.hhmm(wake)
            let request = Task { try await api.sleepPlan(wake: hhmm) }
            asking = request
            defer { if asking == request { asking = nil } }
            do {
                let fresh = try await request.value
                // The schedule or the account changed meanwhile: the answer isn't for this one (nor its store).
                guard current() else { return }
                if let aligned = Self.align(fresh, to: wake) {
                    plan = aligned
                    asOf = nil
                    problem = nil
                    keep(Cached(plan: aligned, fetchedAt: now))
                } else if plan == nil {
                    problem = .otherTimeZone
                }
            } catch {
                guard current(), !error.isCancellation else { return }
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
        guard current() else { return }
        guard let plan else {
            // No plan for this wake (offline, failed, another time zone): the widget shows no bedtime rather than one
            // RYFT didn't plan.
            state.repository.tonightBedtime = nil
            return await remindWithoutAPlan(schedule, wake: wake, gen: gen, owner: owner)
        }
        let bed = schedule.goal.bedtime(in: plan)
        state.repository.tonightBedtime = bed
        record(PlannedNight(bed: bed, wake: plan.wake))
        await rescheduleIfMoved(schedule: schedule, plan: plan, gen: gen, owner: owner)
    }

    /// No plan for tonight's wake (offline, the request failed, another time zone). Reminders set for an earlier schedule
    /// would fire at its bedtimes, so they're set again for this one, estimated as the nights after tonight always are:
    /// the last plan's time in bed before each night's wake. With no plan ever fetched there's nothing to estimate from:
    /// they go, and Bedtime & wake says they resume once RYFT has tonight's plan (`remindersWaiting`).
    private func remindWithoutAPlan(_ schedule: SleepSchedule, wake: Date, gen: Int, owner: Owner) async {
        guard schedule.reminderOn, scheduledBedtime == nil else { return }
        if let last = cached?.plan {
            let estimate = Self.estimate(from: last, wake: wake)
            await scheduleReminders(schedule: schedule, plan: estimate)
            guard gen == generation, owner == self.owner else { return }
            scheduledBedtime = schedule.goal.bedtime(in: estimate)
        } else {
            await cancelReminders()
            guard gen == generation, owner == self.owner else { return }
            remindersWaiting = true
        }
    }

    /// A plan for `wake` from `last`'s need and time in bed: the bedtimes are `wake − share · in_bed_min`, as the reminders
    /// estimate the nights after tonight's.
    static func estimate(from last: SleepPlan, wake: Date) -> SleepPlan {
        func bed(_ share: Double) -> Date { wake.addingTimeInterval(-share * Double(last.inBedMin) * 60) }
        return SleepPlan(wake: wake, needMin: last.needMin, inBedMin: last.inBedMin, efficiency: last.efficiency,
                         bedtime100: bed(1), bedtime85: bed(0.85), bedtime70: bed(0.7), basis: last.basis)
    }

    /// Takes the stored plan when it is for `wake`, and drops one for another night.
    private func adoptCached(for wake: Date) {
        if let plan, abs(plan.wake.timeIntervalSince(wake)) <= 60 { return }
        plan = nil
        asOf = nil
        guard let cached, abs(cached.plan.wake.timeIntervalSince(wake)) <= 60 else { return }
        plan = cached.plan
        asOf = cached.fetchedAt
    }

    /// The plan shown is the stored one: say since when.
    private func markCached() {
        if asOf == nil { asOf = cached?.fetchedAt ?? now }
    }

    /// This side's last plan: the account's, as kept in its store, or demo data's, in memory.
    private var cached: Cached? {
        guard let documents = env.accountDocuments else { return demoCached }
        return documents.document(Cached.self, key: Self.cacheKey)
    }

    private func keep(_ fresh: Cached) {
        guard let documents = env.accountDocuments else {
            demoCached = fresh
            return
        }
        documents.saveDocument(fresh, key: Self.cacheKey, at: now)
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

    private func rescheduleIfMoved(schedule: SleepSchedule, plan: SleepPlan, gen: Int, owner: Owner) async {
        let bed = schedule.goal.bedtime(in: plan)
        if let last = scheduledBedtime, abs(last.timeIntervalSince(bed)) < Self.rescheduleThreshold { return }
        await scheduleReminders(schedule: schedule, plan: plan)
        guard gen == generation, owner == self.owner else { return }
        scheduledBedtime = bed
        remindersWaiting = false
    }

    /// The reminders go; with demo data shown, none does (they're the account's, and Demo data sets none).
    private func cancelReminders() async {
        guard !env.isDemo else { return }
        await removeReminders()
    }

    /// None wanted: the scheduler takes away every `bedtime.*` it knows on iOS (read once per process), with no enumeration.
    private func removeReminders() async {
        await reminders.offerBedtime(.these([]), owner: owner)
    }

    /// `schedule`'s reminders (`reminders`), offered to the one writer of local requests (ADR 0024), which adds what
    /// changed and removes the rest, for this owner only: an offer for one that isn't current is dropped, and a pass for one
    /// that changes meanwhile adds nothing more. Demo data's plan sets none, and the account's stay.
    private func scheduleReminders(schedule: SleepSchedule, plan: SleepPlan) async {
        guard !env.isDemo else { return }
        let account = env.auth.accountID ?? ""
        let wanted = Self.reminders(schedule: schedule, plan: plan, now: now)
            .compactMap { LocalReminder.bedtime($0, account: account) }
        await reminders.offerBedtime(.these(wanted), owner: owner)
    }

    /// Tonight's reminder from the plan; the following nights from tonight's time in bed at each night's wake (refined
    /// when the app plans those nights); none that would fire before `now`, none with the reminder off. Pure.
    static func reminders(schedule: SleepSchedule, plan: SleepPlan, now: Date,
                          calendar: Calendar = .current) -> [UNNotificationRequest] {
        guard schedule.reminderOn else { return [] }
        let share = Double(schedule.goal.rawValue) / 100
        let sleepMin = Int((Double(plan.needMin) * share).rounded())
        var requests: [UNNotificationRequest] = []
        for night in 0..<nightsAhead {
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
                : String(localized: "In bed by \(Fmt.time(bed)) for \(schedule.goal.rawValue)\u{00A0}% of your need: \(Fmt.duration(minutes: sleepMin)).",
                         comment: "The wind-down reminder: the bedtime, the share of the sleep need it gives, that sleep. The % sign is literal.")
            content.sound = .default
            content.categoryIdentifier = PushCategories.bedtime
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            requests.append(UNNotificationRequest(identifier: reminderPrefix + DayFormat.string(from: wakeDay), content: content,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        return requests
    }

    /// Sets the wake alarms the schedule asks for, once per change, and once at launch (a
    /// restore, a new iPhone or an iOS update leaves `alarmOn` without alarms). When iOS doesn't
    /// allow them (any more), the alarm turns off and `alarmProblem` says why. For a pass that a
    /// change overtook nothing more happens (the next pass compares with `alarmsSet`); alarms set
    /// for an account that has gone meanwhile are taken away again. Demo data's wake times set none, and the account's
    /// alarms stay as they are (Demo data off sets them again).
    private func syncAlarms(gen: Int, owner: Owner) async {
        guard !env.isDemo else { return }
        func current() -> Bool { gen == generation && owner == self.owner }
        let want = isEnabled && state.hasDataSource && schedule?.alarmOn == true ? schedule?.wake : nil
        if alarmsKnown, alarmsSet == want { return }
        alarmsKnown = true
        alarmsSet = want
        guard let want else { return await alarms.cancelAll() }
        do {
            guard await alarms.isAllowed() else { throw WakeAlarmError.notAllowed }
            guard current() else {
                // Not set: the next pass mustn't take them for set.
                alarmsKnown = false
                return
            }
            try await alarms.schedule(want)
            // Demo data turned on meanwhile keeps them: they're still the account's (`keepsTheAccounts`).
            if owner != self.owner, !keepsTheAccounts {
                await alarms.cancelAll()
                // Taken away again: the next pass doesn't know what is set.
                alarmsKnown = false
            }
        } catch {
            alarmsSet = nil
            guard current() else {
                alarmsKnown = false
                return
            }
            await alarms.cancelAll()
            alarmProblem = String(localized: "The wake-up alarm is off: iOS doesn't allow RYFT's alarms. Turn it on again to allow them.")
            guard var off = schedule, current() else { return }
            off.alarmOn = false
            schedule = off
            save(off)
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
        saveRecords()
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
        line = String(localized: "for \(schedule.goal.rawValue)\u{00A0}% · wake \(wake) · need \(need)", comment: "Today's Tonight tile, under the bedtime: the share of tonight's need it gives, the wake time and the need as hours:minutes (\"for 100 % · wake 6:30 AM · need 8:18\").")
        goals = SleepSchedule.Goal.allCases.map { option in
            let time = Fmt.time(option.bedtime(in: plan), locale: locale)
            var spoken = [option.title, String(localized: "\(option.rawValue)\u{00A0}percent"), time]
            if option == schedule.goal {
                spoken.append(String(localized: "your goal",
                                     comment: "VoiceOver on Sleep → Bedtime's go-to-bed tile, after the goal that is yours (the filled marker)."))
            }
            return Goal(goal: option, title: String(localized: "\(option.title) · \(option.rawValue)\u{00A0}%"), time: time,
                        isGoal: option == schedule.goal, spoken: spoken.joined(separator: ", "))
        }
        let asOfText = asOf.map { String(localized: "As of \(Fmt.time($0, locale: locale))") }
        self.asOf = asOfText
        let bedTime = Fmt.time(bed, locale: locale), spokenNeed = Fmt.spokenDuration(minutes: plan.needMin, locale: locale)
        // swiftlint:disable:next line_length
        let summary = String(localized: "In bed by \(bedTime), for \(schedule.goal.rawValue)\u{00A0}percent of your need. Wake \(wake), need \(spokenNeed).", comment: "VoiceOver on Today's Tonight tile: tonight's bedtime for the goal, its share of the need, the wake time and the need (\"In bed by 10:41 PM, for 100 percent of your need. Wake 6:30 AM, need 8 hours 18 minutes.\").")
        spoken = ([summary] + (asOfText.map { [$0 + "."] } ?? []) + goals.map { $0.spoken + "." }).joined(separator: " ")
    }

    /// The planning outline's line, and what VoiceOver reads for it.
    static var planningText: String {
        String(localized: "Planning tonight…", comment: "Today's Tonight card while tonight's plan loads with nothing saved on this iPhone.")
    }
}

// MARK: - Bedtime & wake, as the page edits it

/// Bedtime & wake's page (PR 6 C §4.13), one for the planner (`BedtimePlanner.editor`) whichever way it was opened (Profile,
/// Tonight, Sleep → Bedtime): a change shows at once and is saved on this iPhone 400 ms after the last one (a wheel sends
/// many) and when the page goes, online or not, the latest change last. Saving is synchronous (`BedtimePlanner.commit`); the
/// reminders, the alarms and the plan follow in the planner's passes. A change is the account's that made it: after a
/// sign-out, a wipe or another account's sign-in it is dropped, never saved as the next one's. A switch iOS refuses stays
/// off and says why; an alarm iOS stops allowing goes back off with the planner's sentence (`alarmProblem`).
@MainActor
@Observable
final class BedtimeScheduleEditor {
    /// The planner owns the editor.
    unowned let planner: BedtimePlanner
    /// The schedule as changed and not saved yet; `nil` once saved, when the page shows the planner's.
    private var copy: SleepSchedule?
    /// Whose `copy` is: who was signed in when its first change was made.
    private var copyOwner: BedtimePlanner.Owner?
    /// iOS said no: the switch stayed off, and its group says why until it is turned on or the page is left.
    private(set) var reminderRefused = false
    private(set) var alarmRefused = false
    /// Turn off is on its way: the page is disabled and the row says so.
    private(set) var isTurningOff = false
    /// Turn off started since the page opened: changes and leaving do nothing more (leaving doesn't set it up again).
    @ObservationIgnored private var turnedOff = false
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// Quiet after the last change before it is saved.
    static let saveDelay: Duration = .milliseconds(400)

    init(planner: BedtimePlanner) {
        self.planner = planner
    }

    /// What the page shows: the change not saved yet, else the saved schedule (or the starting point).
    var draft: SleepSchedule { liveCopy ?? planner.draft }

    /// A change not saved yet (only then does leaving save).
    var edited: Bool { liveCopy != nil }

    /// `copy`, while it is still the signed-in account's. Both are read every time, so a view that read `draft` before the
    /// first change is redrawn by it.
    private var liveCopy: SleepSchedule? {
        let copy = copy, owner = copyOwner
        return owner == planner.owner ? copy : nil
    }

    /// The page appeared: a Turn off from an earlier visit is over.
    func open() {
        turnedOff = false
    }

    /// A change: shown at once, saved once the page has been still for `saveDelay`.
    func edit(_ change: (inout SleepSchedule) -> Void) {
        guard !turnedOff else { return }
        var next = draft
        change(&next)
        guard next != draft else { return }
        if liveCopy == nil { copyOwner = planner.owner }
        copy = next
        pending?.cancel()
        let clock = planner.clock
        pending = Task { [weak self] in
            do { try await clock.sleep(for: Self.saveDelay) } catch { return }
            // A later change replaced this one while it woke: that one saves.
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            self.save()
        }
    }

    /// The page goes: a change made just before still counts. Opened from "Set up Bedtime & wake" (`settingUp`) and left
    /// without a change, it is set up as the page showed it (`setUp`). After Turn off, nothing.
    func leave(settingUp: Bool = false) {
        reminderRefused = false
        alarmRefused = false
        guard !turnedOff else { return }
        pending?.cancel()
        pending = nil
        if edited {
            save()
        } else if settingUp {
            setUp()
        }
    }

    /// Sets Bedtime & wake up as the page shows it, without a change (the defaults): "Set up Bedtime & wake", then back.
    func setUp() {
        guard planner.schedule == nil, !turnedOff else { return }
        planner.commit(draft, for: planner.owner)
    }

    /// Back to "Off": the schedule (the wake times of each day, the goal, the wind-down), the bedtime reminder and the wake
    /// alarm go. Saved at once; it waits only for the reminders and the alarms to go, never for a plan on its way (the
    /// change cancels it).
    func turnOff() async {
        guard !isTurningOff else { return }
        isTurningOff = true
        turnedOff = true
        pending?.cancel()
        pending = nil
        copy = nil
        copyOwner = nil
        planner.commit(nil, for: planner.owner)
        await planner.settle()
        isTurningOff = false
    }

    /// The reminder asks for notifications as it's turned on. `false`: iOS said no, the switch stays off.
    @discardableResult
    func setReminder(_ on: Bool) async -> Bool {
        guard !turnedOff else { return true }
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
        guard !turnedOff else { return true }
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

    /// The planner turned the alarm off (iOS no longer allows it) while a change with the alarm on wasn't saved yet: the
    /// change keeps everything else, the alarm goes back off. Saved changes need nothing: the page shows the planner's.
    func alarmWentOff() {
        guard planner.schedule?.alarmOn == false, copy?.alarmOn == true else { return }
        copy?.alarmOn = false
    }

    /// Another account (or none): a change not saved yet was the previous one's, and goes.
    func discard() {
        pending?.cancel()
        pending = nil
        copy = nil
        copyOwner = nil
        reminderRefused = false
        alarmRefused = false
    }

    /// Waits for the save in waiting and the planner's passes (tests).
    func settle() async {
        await pending?.value
        await planner.settle()
    }

    /// Hands the change to the planner, which saves it at once; dropped when it was made for an account that has gone.
    private func save() {
        guard let copy, let copyOwner else { return }
        guard planner.commit(copy, for: copyOwner) else { return discard() }
        // Saved: the page shows the planner's schedule again until the next change.
        if planner.schedule == copy {
            self.copy = nil
            self.copyOwner = nil
        }
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

    /// The wake notifications have fixed ids (one per weekday): removed by name, without reading iOS's pending set.
    func cancelAll() async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { AlarmKitWake.cancelAll() }
        #endif
        notifier.removePending(ids: BedtimePlanner.wakeIDs)
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
    /// The alarm's and its Live Activity's tint, as the widget's alarm look: `Theme.textPrimary`'s light ink, #F2F1EC.
    /// Literals, not the Theme colours: `AlarmAttributes` is encoded and drawn by the system's process, where the app's
    /// asset colours may not resolve (`AlarmKitWakeTests` keeps them equal to the Theme's). Never teal: teal is
    /// recovery's (L27).
    static let tint = Color(red: 0.949, green: 0.945, blue: 0.925)
    /// Snooze's words, on the tint: `Theme.background`, #0A0C0B. Stop (iOS 26.0 only) sits on the system's own
    /// fill, so its words stay light.
    static let snoozeText = Color(red: 0.039, green: 0.047, blue: 0.043)

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
            let snoozeButton = AlarmButton(text: LocalizedStringResource("Snooze"), textColor: snoozeText, systemImageName: "zzz")
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
                                             metadata: WakeAlarmMetadata(), tintColor: tint)
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
