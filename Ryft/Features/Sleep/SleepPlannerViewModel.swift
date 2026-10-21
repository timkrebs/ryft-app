import Foundation
import Observation
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Sleep → Planner (`GET /v1/sleep/plan?wake=HH:MM`, behind `sleep.planner`):
/// three bedtimes for a wake time and the need behind them. A wake-time change
/// asks again after 300 ms of quiet; offline, the last plan stays with its time.
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

    /// The wake time asked for, local.
    private(set) var wake: Date
    private(set) var plan: SleepPlan?
    /// Set when `plan` is a cached one (offline or the request failed).
    private(set) var asOf: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    @ObservationIgnored private var pending: Task<Void, Never>?

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

    /// The picker moved: ask again once it has been still for 300 ms.
    func setWake(_ date: Date) {
        wake = date
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
        guard state.hasDataSource else { return }
        guard state.env.connectivity.isOnline else {
            if plan != nil, asOf == nil { asOf = state.env.clock.now() }
            return
        }
        isLoading = plan == nil
        defer { isLoading = false }
        do {
            let fresh = try await state.env.api.sleepPlan(wake: hhmm)
            guard hhmm == wakeText else { return }   // superseded by a newer wake time
            plan = fresh
            asOf = nil
            error = nil
            state.env.persistence.saveDocument(Cached(plan: fresh, wake: hhmm, fetchedAt: state.env.clock.now()),
                                               key: Self.cacheKey, at: state.env.clock.now())
        } catch {
            // 422 only for a malformed time, which the picker can't make.
            assert((error as? APIError)?.status != 422, "sleep/plan rejected wake \(hhmm)")
            if plan == nil {
                self.error = error.localizedDescription
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

    /// The wake of the night after `now`: it ends tomorrow, except after midnight (before
    /// 03:00), when the night in progress ends this morning.
    func nextWake(after now: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.component(.hour, from: now) < 3 ? now : calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return Self.date(wakeTime(on: day, calendar: calendar), on: day, calendar: calendar)
    }

    /// `hhmm` on `day`, local (a DST gap moves it forward, as the clock does).
    static func date(_ hhmm: String, on day: Date, calendar: Calendar = .current) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return day }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) ?? day
    }

    /// Weekdays get the first one's time, the weekend Saturday's (two-time editing).
    mutating func setWeekdays(_ hhmm: String) { for i in 0..<5 { wake[i] = hhmm } }
    mutating func setWeekend(_ hhmm: String) { wake[5] = hhmm; wake[6] = hhmm }

    static func key(_ account: String?) -> String { "sleep.schedule.\(account ?? "signed-out")" }

    static func load(account: String?, defaults: UserDefaults) -> SleepSchedule? {
        defaults.data(forKey: key(account)).flatMap { try? JSONDecoder().decode(SleepSchedule.self, from: $0) }
    }

    func save(account: String?, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key(account)) }
    }
}

/// The night a schedule planned, kept so the morning can compare with what happened.
struct PlannedNight: Codable, Equatable, Sendable {
    let bed: Date
    let wake: Date
}

/// Tonight's bedtime from the schedule and `GET /v1/sleep/plan`, the reminder before it and
/// the wake alarm. Re-asks after syncs that touch today and in the evening refresh; moves the
/// reminders only when the bedtime moved by 10 minutes or more. Behind `sleep.planner`.
@MainActor
@Observable
final class BedtimePlanner {
    private let state: AppState
    private let alarms: WakeAlarms

    /// `nil` until set up ("Bedtime & wake").
    private(set) var schedule: SleepSchedule?
    private(set) var plan: SleepPlan?
    /// The wake `plan` was asked for.
    private(set) var wake: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    /// The reminders were last set for this bedtime (the 10-minute rule).
    @ObservationIgnored private(set) var scheduledBedtime: Date?

    /// A bedtime that moved less than this keeps its reminder.
    static let rescheduleThreshold: TimeInterval = 10 * 60
    /// Reminders ahead: tonight's exact, the following nights from tonight's time in bed.
    static let nightsAhead = 7
    static let reminderPrefix = "bedtime."
    static let wakePrefix = "wake."

    init(state: AppState, alarms: WakeAlarms? = nil) {
        self.state = state
        self.alarms = alarms ?? SystemWakeAlarms(notifier: state.env.notifier)
        schedule = SleepSchedule.load(account: state.env.auth.accountID, defaults: state.env.defaults)
    }

    private var env: AppEnvironment { state.env }
    private var now: Date { env.clock.now() }
    var isEnabled: Bool { env.flags.isOn(.sleepPlanner) }
    /// The schedule to edit: the saved one, or a starting point.
    var draft: SleepSchedule { schedule ?? .default }
    var alarmsRing: Bool { alarms.ringsLikeAnAlarm }

    /// Tonight's bedtime for the goal.
    var bedtime: Date? { plan.flatMap { p in schedule.map { $0.goal.bedtime(in: p) } } }

    /// Profile's row: "06:30" (weekdays) or "Off".
    var summary: String {
        guard let schedule else { return String(localized: "Off") }
        return schedule.wake[0] == schedule.wake[5] ? schedule.wake[0]
            : String(localized: "\(schedule.wake[0]) · weekend \(schedule.wake[5])")
    }

    /// "Peak · reminder · alarm".
    var summaryDetail: String? {
        guard let schedule else { return nil }
        var parts = [schedule.goal.title]
        if schedule.reminderOn { parts.append(String(localized: "reminder")) }
        if schedule.alarmOn { parts.append(String(localized: "alarm")) }
        return parts.joined(separator: " · ")
    }

    /// From 17:00 on Today; the Sleep tab always shows it.
    func isEvening(calendar: Calendar = .current) -> Bool { calendar.component(.hour, from: now) >= 17 }

    /// Another account signed in: its schedule.
    func accountChanged() {
        schedule = SleepSchedule.load(account: env.auth.accountID, defaults: env.defaults)
        plan = nil
        scheduledBedtime = nil
    }

    // MARK: editing

    /// Saves the schedule and plans with it: reminders and alarms follow at once.
    func update(_ new: SleepSchedule) async {
        let old = schedule
        schedule = new
        new.save(account: env.auth.accountID, defaults: env.defaults)
        if old?.wake != new.wake || old?.alarmOn != new.alarmOn { await setAlarms(for: new) }
        scheduledBedtime = nil // the goal or the wind-down may have moved it
        await refresh()
    }

    /// Turning the reminder on asks for notifications (a good moment: you asked for it).
    /// `false` when iOS says no.
    func allowReminders() async -> Bool {
        let status = await env.notifier.authorizationStatus()
        if status == .notDetermined { return (try? await env.notifier.requestAuthorization()) ?? false }
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// The alarm asks for AlarmKit (iOS 26+) or notifications (older iOS).
    func allowAlarm() async -> Bool { await alarms.authorize() }

    // MARK: planning

    /// Asks for tonight's plan and keeps the reminders in step with it.
    func refresh() async {
        guard isEnabled, let schedule, state.hasDataSource else { return }
        let wake = schedule.nextWake(after: now)
        guard env.connectivity.isOnline else { return }
        isLoading = plan == nil
        defer { isLoading = false }
        do {
            let fresh = try await env.api.sleepPlan(wake: SleepPlannerViewModel.hhmm(wake))
            plan = fresh
            self.wake = wake
            error = nil
            record(PlannedNight(bed: schedule.goal.bedtime(in: fresh), wake: fresh.wake))
            await rescheduleIfMoved(schedule: schedule, plan: fresh, wake: wake)
        } catch {
            if plan == nil { self.error = error.localizedDescription }
        }
    }

    private func rescheduleIfMoved(schedule: SleepSchedule, plan: SleepPlan, wake: Date) async {
        let bed = schedule.goal.bedtime(in: plan)
        if let last = scheduledBedtime, abs(last.timeIntervalSince(bed)) < Self.rescheduleThreshold { return }
        await scheduleReminders(schedule: schedule, plan: plan, wake: wake)
        scheduledBedtime = bed
        state.repository.tonightBedtime = bed
    }

    /// Tonight's reminder from the plan; the following nights from tonight's time in bed at
    /// each night's wake (refined when the app plans those nights).
    func scheduleReminders(schedule: SleepSchedule, plan: SleepPlan, wake: Date, calendar: Calendar = .current) async {
        let pending = await env.notifier.pendingIDs().filter { $0.hasPrefix(Self.reminderPrefix) }
        env.notifier.removePending(ids: pending)
        guard schedule.reminderOn else { return }
        let share = Double(schedule.goal.rawValue) / 100
        let sleepMin = Int((Double(plan.needMin) * share).rounded())
        for night in 0..<Self.nightsAhead {
            let wakeDay = calendar.date(byAdding: .day, value: night, to: wake) ?? wake
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
            try? await env.notifier.add(UNNotificationRequest(identifier: id, content: content,
                                                              trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }

    private func setAlarms(for schedule: SleepSchedule) async {
        if schedule.alarmOn {
            try? await alarms.schedule(schedule.wake)
        } else {
            await alarms.cancelAll()
        }
    }

    // MARK: planned vs actual

    private static func recordsKey(_ account: String?) -> String { "sleep.planned.\(account ?? "signed-out")" }

    /// Keyed by the night's wake day; the last 14 are kept.
    private func record(_ night: PlannedNight) {
        let key = Self.recordsKey(env.auth.accountID)
        var all = (env.defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: PlannedNight].self, from: $0) }) ?? [:]
        all[DayFormat.string(from: night.wake)] = night
        if all.count > 14 { for k in all.keys.sorted().dropLast(14) { all[k] = nil } }
        if let data = try? JSONEncoder().encode(all) { env.defaults.set(data, forKey: key) }
    }

    /// What the schedule planned for the night ending on `day`.
    func planned(nightEnding day: String) -> PlannedNight? {
        let key = Self.recordsKey(env.auth.accountID)
        let all = env.defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: PlannedNight].self, from: $0) }
        return all?[day]
    }
}

// MARK: - wake alarm

/// The wake alarm, behind a seam: AlarmKit on iOS 26+ (rings through Silent mode and Focus, Stop
/// and Snooze), a notification at the wake time below (it doesn't ring like an alarm).
@MainActor
protocol WakeAlarms: AnyObject {
    /// AlarmKit (a real alarm) or a notification.
    var ringsLikeAnAlarm: Bool { get }
    func authorize() async -> Bool
    /// Replaces RYFT's wake alarms: one per weekday at `times` ("HH:MM", Monday first).
    func schedule(_ times: [String]) async throws
    func cancelAll() async
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
        let status = await notifier.authorizationStatus()
        if status == .notDetermined { return (try? await notifier.requestAuthorization()) ?? false }
        return status == .authorized || status == .provisional || status == .ephemeral
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
    var allows = true
    private(set) var scheduled: [String]?
    private(set) var cancellations = 0

    func authorize() async -> Bool { allows }
    func schedule(_ times: [String]) async throws { scheduled = times }
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

/// The wake alarm with AlarmKit: one weekly alarm per weekday, Stop and Snooze (9 minutes).
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
        for (i, hhmm) in times.enumerated() {
            let parts = hhmm.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let schedule = Alarm.Schedule.relative(.init(time: .init(hour: parts[0], minute: parts[1]),
                                                         repeats: .weekly([weekdays[i]])))
            let alert = AlarmPresentation.Alert(
                title: LocalizedStringResource("Time to get up"),
                stopButton: AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.circle"),
                secondaryButton: AlarmButton(text: LocalizedStringResource("Snooze"), textColor: .white,
                                             systemImageName: "zzz"),
                secondaryButtonBehavior: .countdown)
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
