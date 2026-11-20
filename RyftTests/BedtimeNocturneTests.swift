import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

// C4: Bedtime & wake and Tonight in Nocturne (design-pr6-c-settings.md §4.13). Tonight's board in every state, the plan's
// failures in the app's words (T5.5's open item: never the system's error text), the page's saving (in order, 400 ms after
// the last change, a refused alarm going back) and, in a window, Tonight's six states, the time chips at the default size and
// at AX3, and what VoiceOver reads.

private let enUS = Locale(identifier: "en_US")
/// The narrow no-break space of a time ("6:30 AM") as a space; the summary's no-break space after "weekend" stays.
private func plain(_ text: String?) -> String { (text ?? "").replacingOccurrences(of: "\u{202F}", with: " ") }

/// 2026-11-19 at `hour:minute` (a day `add` later), local time.
private func at(_ hour: Int, _ minute: Int, add: Int = 0) -> Date {
    let day = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19 + add, hour: hour, minute: minute))
    return day ?? .distantPast
}

/// Tonight's plan: wake 6:30 AM, need 8:18, in bed by 10:41 PM (Peak), 11:19 PM (Perform), 12:08 AM (Get by).
private let tonightsPlan = SleepPlan(wake: at(6, 30, add: 1), needMin: 498, inBedMin: 549, efficiency: 91,
                                     bedtime100: at(22, 41), bedtime85: at(23, 19), bedtime70: at(0, 8, add: 1),
                                     basis: SleepPlanBasis(base: 450, strainTopup: 27, debtTopup: 33, napCredit: 12, efficiency: 91))

@MainActor
private func makeState(api: MockPlatformAPI = MockPlatformAPI(), online: Bool = true) -> (AppState, TestClock) {
    let clock = TestClock()
    clock.set(Calendar.current.date(bySettingHour: 17, minute: 42, second: 0, of: clock.now()) ?? clock.now())
    return (AppState(env: .test(api: api, clock: clock, flags: [.sleepPlanner: true], online: online)), clock)
}

// MARK: - Tonight's board

struct TonightBoardTests {
    @Test("Planned: the bedtime as numeral and meridiem, the line, the three goals with yours marked, one summary to hear")
    func planned() {
        let board = TonightBoard(schedule: .default, plan: tonightsPlan, locale: enUS)
        #expect(board.look == .planned && board.digits == "10:41" && board.meridiem == "PM")
        #expect(plain(board.line) == "for 100\u{00A0}% · wake 6:30 AM · need 8:18")
        #expect(board.goals.map(\.title) == ["Peak · 100\u{00A0}%", "Perform · 85\u{00A0}%", "Get by · 70\u{00A0}%"])
        #expect(board.goals.map { plain($0.time) } == ["10:41 PM", "11:19 PM", "12:08 AM"])
        #expect(board.goals.map(\.isGoal) == [true, false, false])
        #expect(plain(board.goals[0].spoken) == "Peak, 100 percent, 10:41 PM, your goal")
        #expect(plain(board.goals[1].spoken) == "Perform, 85 percent, 11:19 PM")
        #expect(board.asOf == nil, "a fresh plan has no As of")
        let need = Fmt.spokenDuration(minutes: 498, locale: enUS)
        #expect(plain(board.spoken).hasPrefix("In bed by 10:41 PM, for 100 percent of your need. Wake 6:30 AM, need \(need). Peak, "),
                "\(plain(board.spoken))")
        #expect(board.plan == tonightsPlan && board.problem == nil && board.summary == BedtimePlanner.summary(.default, locale: enUS))
    }

    @Test("The goal picks the numeral, the line's share and the filled marker")
    func perform() {
        var schedule = SleepSchedule.default
        schedule.goal = .perform
        let board = TonightBoard(schedule: schedule, plan: tonightsPlan, locale: enUS)
        #expect(board.digits == "11:19" && plain(board.line).hasPrefix("for 85\u{00A0}% · "))
        #expect(board.goals.map(\.isGoal) == [false, true, false])
        #expect(board.goals.filter { $0.spoken.contains("your goal") }.count == 1)
    }

    @Test("A plan fetched earlier says As of, after the summary and before the goals")
    func asOf() {
        let board = TonightBoard(schedule: .default, plan: tonightsPlan, asOf: at(17, 42), locale: enUS)
        #expect(plain(board.asOf) == "As of 5:42 PM")
        let spoken = plain(board.spoken)
        let asOf = spoken.range(of: "As of 5:42 PM."), peak = spoken.range(of: "Peak, ")
        #expect(asOf != nil && peak != nil, "\(spoken)")
        if let asOf, let peak { #expect(asOf.lowerBound < peak.lowerBound, "\(spoken)") }
    }

    @Test("A 24-hour clock: no meridiem")
    func twentyFourHours() {
        let board = TonightBoard(schedule: .default, plan: tonightsPlan, locale: Locale(identifier: "en_GB"))
        #expect(board.digits == "22:41" && board.meridiem == nil)
    }

    @Test("Not set up, planning, offline, failed: offline wins with nothing cached; an old offline line isn't shown online")
    func states() {
        let failure = SleepLoadFailure(APIError.http(503, "", requestID: "01JD8K2V9Q7M3X"), isOnline: true, at: .now)
        #expect(TonightBoard(schedule: nil, plan: tonightsPlan, problem: .offline, isOnline: false).look == .notSetUp)
        let planning = TonightBoard(schedule: .default, plan: nil)
        #expect(planning.look == .planning && planning.spoken == TonightBoard.planningText && planning.digits == nil)
        let offline = TonightBoard(schedule: .default, plan: nil, problem: .failed(failure), isOnline: false)
        #expect(offline.look == .offline && offline.problem == .offline)
        #expect(TonightBoard(schedule: .default, plan: nil, problem: .offline, isOnline: true).look == .planning,
                "back online: planning again, not the offline line")
        let failed = TonightBoard(schedule: .default, plan: nil, problem: .failed(failure))
        #expect(failed.look == .failed && failed.problem?.action == .retry)
        #expect(failed.problem?.details?.contains("01JD8K2V9Q7M3X") == true && failed.problem?.message == failure.message)
        let zone = TonightBoard(schedule: .default, plan: nil, problem: .otherTimeZone)
        #expect(zone.look == .failed && zone.problem?.action == .noButton && zone.problem?.details == nil)
        // A plan beats every problem.
        #expect(TonightBoard(schedule: .default, plan: tonightsPlan, problem: .failed(failure), isOnline: false).look == .planned)
    }

    @Test("Offline says so without a button: the plan comes once online")
    func offlineProblem() {
        let offline = TonightProblem.offline
        #expect(offline.message == "Tonight's bedtime needs a connection. It appears once you're online.")
        #expect(offline.action == .noButton && offline.details == nil && offline.systemImage == "wifi.exclamationmark")
    }
}

// MARK: - the plan's failures, in the app's words

@MainActor
struct TonightProblemTests {
    private func failedPlanner(_ error: Error) async -> (BedtimePlanner, AppState) {
        let api = MockPlatformAPI()
        api.failure = error
        let (state, _) = makeState(api: api)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.update(.default)
        return (planner, state)
    }

    @Test("Refused (503): Today's sentence, the status and request ID behind Details, Try again; never the server's text",
          arguments: [503, 500])
    func refused(_ status: Int) async throws {
        let error = APIError.http(status, "upstream unavailable", requestID: "r-plan")
        let (planner, state) = await failedPlanner(error)
        let expected = SleepLoadFailure(error, isOnline: true, at: state.env.clock.now())
        #expect(planner.problem == .failed(expected))
        #expect(planner.error == expected.message && planner.error != error.localizedDescription)
        #expect(!(planner.error ?? "").contains("upstream") && !(planner.error ?? "").contains("503"))
        #expect(planner.problem?.details?.contains("r-plan") == true && planner.problem?.action == .retry)
        #expect(planner.tonight(locale: enUS).look == .failed)
    }

    @Test("No answer and no connection: calm sentences, Try again")
    func noAnswer() async throws {
        let timeout = APIError.transport(URLError(.timedOut))
        let (late, state) = await failedPlanner(timeout)
        #expect(late.error == SleepLoadFailure(timeout, isOnline: true, at: state.env.clock.now()).message)
        #expect(late.error != timeout.localizedDescription && late.problem?.action == .retry)

        let lost = APIError.transport(URLError(.notConnectedToInternet))
        let (offline, _) = await failedPlanner(lost)
        #expect(offline.error == "No connection. Check your internet and try again.")
    }

    @Test("The session ended: Sign in, not Try again")
    func signedOut() async throws {
        let (planner, _) = await failedPlanner(APIError.signedOut)
        #expect(planner.problem?.action == .signIn)
        #expect(planner.error != APIError.signedOut.localizedDescription)
    }

    @Test("Offline with nothing cached: the offline line; back online, Tonight plans")
    func offlineThenOnline() async throws {
        let (state, _) = makeState(online: false)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.update(.default)
        #expect(planner.problem == .offline && planner.tonight(locale: enUS).look == .offline)
        state.env.connectivityMonitor.update(true)
        #expect(planner.tonight(locale: enUS).look == .planning, "online: planning, not offline")
        await planner.refresh()
        #expect(planner.tonight(locale: enUS).look == .planned && planner.problem == nil)
    }

    @Test("Offline with a plan fetched earlier: the plan, As of when it came")
    func offlineCached() async throws {
        let (state, clock) = makeState()
        await BedtimePlanner(state: state, alarms: MockWakeAlarms()).update(.default)
        clock.advance(by: .seconds(3_600))
        state.env.connectivityMonitor.update(false)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.refresh()
        let board = planner.tonight(locale: enUS)
        #expect(board.look == .planned && board.asOf != nil && planner.error == nil)
    }
}

// MARK: - Bedtime & wake's saving

/// Wake alarms whose `schedule` (and, with `holdsCancel`, `cancelAll`) waits until released: a side effect on its way, held.
private final class HeldWakeAlarms: WakeAlarms {
    let ringsLikeAnAlarm = true
    private(set) var scheduled: [[String]] = []
    /// What is set now: the last times scheduled, `nil` after `cancelAll`.
    private(set) var current: [String]?
    private var held: [CheckedContinuation<Void, Never>] = []
    private var holds = true
    var holdsCancel = false
    /// iOS stopped allowing alarms while one was being set: `schedule` throws once released.
    var refuses = false
    var waiting: Int { held.count }

    func authorize() async -> Bool { true }
    func isAllowed() async -> Bool { true }
    func schedule(_ times: [String]) async throws {
        if holds { await withCheckedContinuation { held.append($0) } }
        if refuses { throw WakeAlarmError.notAllowed }
        scheduled.append(times)
        current = times
    }
    func cancelAll() async {
        if holdsCancel { await withCheckedContinuation { held.append($0) } }
        current = nil
    }

    func release() {
        holds = false
        holdsCancel = false
        let waiting = held
        held = []
        for continuation in waiting { continuation.resume() }
    }
}

/// Tonight's plan held open until released (`MockPlatformAPI.beforePlan`); a request cancelled meanwhile ends at once, as
/// a cancelled request does.
private final class PlanGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var cancelled: Set<UUID> = []
    private var isOpen = false

    var held: Int { lock.withLock { waiting.count } }
    /// Requests cancelled while held (or before they were).
    var cancellations: Int { lock.withLock { cancelled.count } }

    func wait() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let go = lock.withLock { () -> Bool in
                    guard !isOpen, !cancelled.contains(id) else { return true }
                    waiting[id] = continuation
                    return false
                }
                if go { continuation.resume() }
            }
        } onCancel: {
            let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                cancelled.insert(id)
                return waiting.removeValue(forKey: id)
            }
            continuation?.resume()
        }
    }

    func release() {
        let all = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            let all = Array(waiting.values)
            waiting = [:]
            return all
        }
        for continuation in all { continuation.resume() }
    }
}

/// The schedule `state`'s signed-in account keeps on this iPhone.
@MainActor
private func stored(_ state: AppState) -> SleepSchedule? {
    SleepSchedule.load(account: state.env.auth.accountID, defaults: state.env.defaults)
}

@MainActor
private func reminders(_ state: AppState) -> [UNNotificationRequest] {
    ((state.env.notifier as? MockNotifier)?.requests ?? []).filter { $0.identifier.hasPrefix(BedtimePlanner.reminderPrefix) }
}

@MainActor
struct BedtimeScheduleEditorTests {
    private func wake(_ hhmm: String) -> (inout SleepSchedule) -> Void {
        { $0.setWeekdays(hhmm); $0.setWeekend(hhmm) }
    }

    @Test("A change shows at once and is saved 400 ms after the last one: a wheel's many values are one save, the last")
    func debounce() async throws {
        let api = MockPlatformAPI()
        let (state, clock) = makeState(api: api)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        let editor = planner.editor
        for hhmm in ["06:35", "06:40", "06:45"] {
            editor.edit(wake(hhmm))
            #expect(editor.draft.wake[0] == hhmm, "shown at once")
        }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: .milliseconds(399))
        #expect(planner.schedule == nil && api.planWakes.isEmpty, "not before 400 ms")
        clock.advance(by: .milliseconds(1))
        await editor.settle()
        #expect(planner.schedule?.wake.allSatisfy { $0 == "06:45" } == true)
        #expect(api.planWakes == ["06:45"], "one save")
        #expect(!editor.edited, "saved: the page shows the planner's schedule again")
    }

    @Test("A change is saved on this iPhone at once, while the change before it still waits for its alarms; the last one's alarms stay")
    func savesInOrder() async throws {
        let (state, clock) = makeState()
        let alarms = HeldWakeAlarms()
        let planner = BedtimePlanner(state: state, alarms: alarms)
        let editor = planner.editor
        editor.edit { $0.alarmOn = true; $0.setWeekdays("06:45"); $0.setWeekend("06:45") }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        #expect(await eventually { alarms.waiting == 1 }, "the first change's alarms on their way")
        #expect(planner.schedule?.wake[0] == "06:45" && stored(state)?.wake[0] == "06:45")

        editor.edit(wake("07:15"))
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        #expect(await eventually { planner.schedule?.wake[0] == "07:15" }, "saved without waiting for the first's alarms")
        #expect(stored(state)?.wake[0] == "07:15" && stored(state)?.alarmOn == true, "and on this iPhone")
        #expect(alarms.waiting == 1 && alarms.scheduled.isEmpty, "its side effects wait for the first's")

        alarms.release()
        await editor.settle()
        #expect(alarms.current?.allSatisfy { $0 == "07:15" } == true, "the alarms are the last change's: \(String(describing: alarms.current))")
        #expect(alarms.scheduled.last?[0] == "07:15")
    }

    @Test("A change doesn't wait for the plan asked for the one before: that request is cancelled, the next one asked at once")
    func aChangeDoesNotWaitForTheNetwork() async throws {
        let api = MockPlatformAPI()
        let gate = PlanGate()
        api.beforePlan = { _ in await gate.wait() }
        let (state, clock) = makeState(api: api)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        let editor = planner.editor
        editor.edit(wake("06:45"))
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        #expect(await eventually { gate.held == 1 }, "the first plan on its way")

        editor.edit(wake("07:15"))
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        #expect(await eventually { planner.schedule?.wake[0] == "07:15" } && stored(state)?.wake[0] == "07:15")
        #expect(await eventually { gate.cancellations == 1 }, "the first request was cancelled")
        #expect(await eventually { gate.held == 1 }, "the second one on its way, before the first answered")
        #expect(api.planWakes == ["06:45", "07:15"], "\(api.planWakes)")

        gate.release()
        await editor.settle()
        #expect(planner.plan.map { SleepPlannerViewModel.hhmm($0.wake) } == "07:15")
    }

    @Test("Leaving saves a change made just before; leaving without one saves nothing")
    func leave() async throws {
        let api = MockPlatformAPI()
        let (state, clock) = makeState(api: api)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        let editor = planner.editor
        editor.leave()
        await editor.settle()
        #expect(planner.schedule == nil && api.planWakes.isEmpty)

        editor.edit { $0.goal = .getBy }
        editor.leave()
        await editor.settle()
        #expect(planner.schedule?.goal == .getBy && clock.pendingSleeps == 0)
    }

    @Test("One page for every way in: a change made on one shows on the other, and leaving the other never reverts it")
    func oneEditorForEveryWayIn() async throws {
        let (state, clock) = makeState()
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.update(.default)
        let profile = planner.editor, tonight = planner.editor
        #expect(profile === tonight, "Profile's, Tonight's and Sleep's page edit the same copy")

        profile.edit { $0.goal = .getBy }
        #expect(tonight.draft.goal == .getBy, "seen on the other")
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        await profile.settle()
        #expect(planner.schedule?.goal == .getBy && !profile.edited, "saved: the copy is the saved schedule")

        tonight.edit { $0.windDownMin = 45 }
        profile.leave()   // Profile's page goes after Tonight's change: it saves that change, never an older copy
        await tonight.settle()
        #expect(planner.schedule?.goal == .getBy && planner.schedule?.windDownMin == 45)
        tonight.leave()
        await tonight.settle()
        #expect(planner.schedule?.windDownMin == 45 && clock.pendingSleeps == 0)
    }

    @Test("An alarm iOS no longer allows can't be set: the switch goes back off and the planner says why")
    func refusedAlarmGoesBack() async throws {
        let (state, clock) = makeState()
        let alarms = MockWakeAlarms()
        let planner = BedtimePlanner(state: state, alarms: alarms)
        let editor = planner.editor
        #expect(await editor.setAlarm(true))
        #expect(editor.draft.alarmOn && !editor.alarmRefused)
        alarms.allowed = false   // allowed when asked, then turned off in iOS Settings before the save
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        await editor.settle()
        #expect(!editor.draft.alarmOn && planner.schedule?.alarmOn == false, "back as it was")
        #expect(planner.alarmProblem == "The wake-up alarm is off: iOS doesn't allow RYFT's alarms. Turn it on again to allow them.")
    }

    @Test("A change not saved yet keeps everything else when the planner turns the alarm off meanwhile")
    func alarmWentOffKeepsTheChange() async throws {
        let (state, clock) = makeState()
        let alarms = HeldWakeAlarms()
        alarms.refuses = true
        let planner = BedtimePlanner(state: state, alarms: alarms)
        let editor = planner.editor
        editor.edit { $0.alarmOn = true }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        #expect(await eventually { alarms.waiting == 1 }, "the alarm being set")
        editor.edit { $0.goal = .perform }   // the next change, with the alarm still on
        alarms.release()
        #expect(await eventually { planner.schedule?.alarmOn == false }, "iOS refused: the planner turned it off")
        editor.alarmWentOff()   // the page's onChange
        #expect(!editor.draft.alarmOn && editor.draft.goal == .perform && editor.edited)
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        await editor.settle()
        #expect(planner.schedule?.goal == .perform && planner.schedule?.alarmOn == false && alarms.current == nil)
    }

    @Test("A switch iOS refuses stays off, says so, and saves nothing")
    func refusedSwitches() async throws {
        let notifier = MockNotifier()
        notifier.status = .denied
        let clock = TestClock()
        let state = AppState(env: .test(clock: clock, notifier: notifier, flags: [.sleepPlanner: true]))
        let alarms = MockWakeAlarms()
        alarms.allows = false
        let planner = BedtimePlanner(state: state, alarms: alarms)
        let editor = planner.editor
        #expect(await !editor.setReminder(true))
        #expect(await !editor.setAlarm(true))
        #expect(editor.reminderRefused && editor.alarmRefused && !editor.draft.reminderOn && !editor.draft.alarmOn)
        #expect(clock.pendingSleeps == 0 && !editor.edited)
        editor.leave()
        #expect(!editor.reminderRefused && !editor.alarmRefused, "the page gone, the next visit asks again")
    }

    @Test("Opened from Set up and left without a change, it is set up as shown; opened from Profile's Off row, it isn't")
    func setUpThenBack() async throws {
        let (state, _) = makeState()
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        let editor = planner.editor
        editor.open()
        editor.leave()
        #expect(planner.schedule == nil && stored(state) == nil, "an ordinary visit sets nothing up")

        editor.open()
        editor.leave(settingUp: true)
        await editor.settle()
        #expect(planner.schedule == .default && stored(state) == .default, "the defaults the page showed")
        #expect(planner.plan != nil, "and Tonight plans with them")

        // Set up again after turning off: a change made on the way is what's set up.
        await editor.turnOff()
        editor.open()
        editor.edit { $0.goal = .getBy }
        editor.leave(settingUp: true)
        await editor.settle()
        #expect(planner.schedule?.goal == .getBy)
    }

    @Test("Turn off saves at once and waits only for the reminders and alarms; meanwhile changes and leaving do nothing")
    func turnOff() async throws {
        let (state, clock) = makeState()
        let alarms = HeldWakeAlarms()
        alarms.release()   // set the first alarms at once
        let planner = BedtimePlanner(state: state, alarms: alarms)
        var schedule = SleepSchedule.default
        schedule.alarmOn = true
        schedule.reminderOn = true
        await planner.update(schedule)
        #expect(alarms.current != nil && !reminders(state).isEmpty)
        let editor = planner.editor
        editor.open()
        editor.edit { $0.goal = .perform }

        alarms.holdsCancel = true
        let turning = Task { await editor.turnOff() }
        #expect(await eventually { alarms.waiting == 1 }, "the alarms going")
        #expect(editor.isTurningOff && planner.schedule == nil && stored(state) == nil, "saved at once")
        #expect(clock.pendingSleeps == 0, "the change waiting was dropped")
        editor.edit { $0.goal = .getBy }
        editor.leave(settingUp: true)
        #expect(planner.schedule == nil && clock.pendingSleeps == 0, "no change, no set-up while it turns off")

        alarms.release()
        await turning.value
        #expect(!editor.isTurningOff && alarms.current == nil && reminders(state).isEmpty && state.repository.tonightBedtime == nil)
        editor.leave(settingUp: true)
        #expect(planner.schedule == nil, "leaving after Turn off doesn't set it up again")
    }

    @Test("Turn off doesn't wait for a plan on its way: the request is cancelled", .timeLimit(.minutes(1)))
    func turnOffDoesNotWaitForTheNetwork() async throws {
        let api = MockPlatformAPI()
        let gate = PlanGate()
        let (state, _) = makeState(api: api)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        var schedule = SleepSchedule.default
        schedule.reminderOn = true
        await planner.update(schedule)
        #expect(!reminders(state).isEmpty)
        api.beforePlan = { _ in await gate.wait() }
        let refreshing = Task { await planner.refresh() }
        #expect(await eventually { gate.held == 1 }, "a plan on its way")

        await planner.editor.turnOff()
        #expect(planner.schedule == nil && reminders(state).isEmpty && gate.held == 0, "done without its answer")
        await refreshing.value
        gate.release()
    }
}

// MARK: - the passes: whose they are, and reminders without a plan

/// The wipe a sign-out runs, on a test environment: Bedtime & wake's schedules and records, and the store (its epoch moves on).
@MainActor
private final class WipeTarget {
    var env: AppEnvironment?
}

@MainActor
private func signedInState(api: MockPlatformAPI = MockPlatformAPI()) -> (AppState, TestClock, AuthService, MockAuthClient) {
    let clock = TestClock()
    clock.set(Calendar.current.date(bySettingHour: 17, minute: 42, second: 0, of: clock.now()) ?? clock.now())
    let client = MockAuthClient(session: .preview())
    let target = WipeTarget()
    let auth = AuthService(client: client, defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard,
                           wipeLocalData: { _ in
                               guard let env = target.env else { return true }
                               BedtimePlanner.wipe(defaults: env.defaults)
                               return env.persistence.wipe()
                           },
                           deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                           postAppleAuthorization: { _ in })
    let env = AppEnvironment.test(api: api, clock: clock, auth: auth, flags: [.sleepPlanner: true])
    target.env = env
    return (AppState(env: env), clock, auth, client)
}

/// When a reminder fires, from its trigger's components (not from the real time, as `nextTriggerDate` is).
private func fireDate(_ request: UNNotificationRequest) -> Date? {
    (request.trigger as? UNCalendarNotificationTrigger).flatMap { Calendar.current.date(from: $0.dateComponents) }
}

@MainActor
struct BedtimePassTests {
    /// Nothing of Bedtime & wake's under `account` on this iPhone: no schedule, no planned nights.
    private func nothingStored(_ state: AppState, account: String?) -> Bool {
        SleepSchedule.load(account: account, defaults: state.env.defaults) == nil
            && state.env.defaults.data(forKey: "sleep.planned.\(account ?? "signed-out")") == nil
    }

    @Test("A change whose alarms were on their way at a sign-out and another sign-in writes nothing for either; its alarms go")
    func aSignOutDropsTheWorkOnItsWay() async throws {
        let (state, clock, auth, client) = signedInState()
        let a = auth.accountID
        for _ in 0..<20 { await Task.yield() }   // the auth service's session observation starts listening
        let alarms = HeldWakeAlarms()
        let planner = BedtimePlanner(state: state, alarms: alarms)
        planner.editor.edit { $0.alarmOn = true; $0.reminderOn = true; $0.goal = .perform }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        #expect(await eventually { alarms.waiting == 1 }, "the alarms on their way")
        #expect(stored(state)?.goal == .perform, "saved for A")

        await auth.signOut()
        #expect(auth.accountID == nil && stored(state) == nil, "the sign-out wiped A's")
        let b = UUID()
        client.emit(.signedIn, .preview(id: b))
        #expect(await eventually { auth.accountID == b.uuidString })

        alarms.release()
        await planner.settle()
        #expect(nothingStored(state, account: nil) && nothingStored(state, account: b.uuidString), "nothing for signed-out or B")
        #expect(state.env.persistence.document(BedtimePlanner.Cached.self, key: BedtimePlanner.cacheKey) == nil, "no plan in B's store")
        #expect(alarms.current == nil, "A's alarms, set as it signed out, went: \(String(describing: alarms.current))")
        #expect(reminders(state).isEmpty && state.repository.tonightBedtime == nil)
        #expect(a != nil && a != auth.accountID)

        // The app's account change then: B has nothing set up, and nothing stays scheduled.
        await planner.accountChanged()
        #expect(planner.schedule == nil && alarms.current == nil && reminders(state).isEmpty)
    }

    @Test("A change made just before a sign-out isn't saved after it, for nobody nor the next account")
    func aChangeWaitingAtASignOutGoes() async throws {
        let (state, clock, auth, _) = signedInState()
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        planner.editor.edit { $0.goal = .getBy }
        #expect(await eventually { clock.pendingSleeps == 1 })
        await auth.signOut()
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        await planner.editor.settle()
        #expect(nothingStored(state, account: nil) && planner.schedule == nil)
        #expect(!planner.editor.edited && planner.editor.draft == .default, "the change went with the account")
    }

    @Test("A plan that answers after a sign-out isn't kept: the next account's store gets nothing")
    func aLateAnswerIsDropped() async throws {
        let api = MockPlatformAPI()
        let gate = PlanGate()
        let (state, _, auth, _) = signedInState(api: api)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        api.beforePlan = { _ in await gate.wait() }
        planner.commit(.default, for: planner.owner)
        #expect(await eventually { gate.held == 1 })
        await auth.signOut()
        gate.release()
        await planner.settle()
        #expect(state.env.persistence.document(BedtimePlanner.Cached.self, key: BedtimePlanner.cacheKey) == nil)
        #expect(planner.plan == nil && state.repository.tonightBedtime == nil && nothingStored(state, account: nil))
    }

    @Test("Offline, a new wake time sets the reminders again from the last plan's time in bed: the old bedtime's never fire")
    func offlineWakeChangeMovesTheReminders() async throws {
        let (state, clock) = makeState()
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        var schedule = SleepSchedule.default
        schedule.reminderOn = true
        await planner.update(schedule)
        let last = try #require(planner.plan)
        let before = reminders(state).compactMap(fireDate)
        #expect(!before.isEmpty && state.repository.tonightBedtime != nil)

        state.env.connectivityMonitor.update(false)
        schedule.setWeekdays("07:30")
        schedule.setWeekend("09:00")
        await planner.update(schedule)
        #expect(planner.plan == nil && planner.problem == .offline, "no plan for 07:30 offline")
        #expect(state.repository.tonightBedtime == nil, "the widget shows no bedtime RYFT didn't plan")
        let wake = schedule.nextWake(after: clock.now())
        let fire = wake.addingTimeInterval(-Double(last.inBedMin) * 60 - Double(schedule.windDownMin) * 60)
        let tonight = try #require(reminders(state).first { $0.identifier == "bedtime." + DayFormat.string(from: wake) })
        let fires = try #require(fireDate(tonight))
        #expect(abs(fires.timeIntervalSince(fire)) < 60, "tonight's from the new wake: \(fires) vs \(fire)")
        let after = reminders(state).compactMap(fireDate)
        #expect(Set(after).isDisjoint(with: Set(before)), "none at the old bedtimes")
        #expect(!planner.remindersWaiting)
    }

    @Test("A wake change drops the plan: Planning tonight…, not the failure before; another time zone's answer, no bedtime")
    func aDroppedPlan() async throws {
        let api = MockPlatformAPI()
        let gate = PlanGate()
        let (state, clock) = makeState(api: api)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.update(.default)
        #expect(planner.plan != nil && state.repository.tonightBedtime != nil)

        // The answer for 07:30 is for another time zone's 07:30 (3 hours off): not tonight's plan.
        api.planFor = { hhmm in
            let p = MockJournal.sleepPlan(wake: hhmm, now: clock.now()), off: TimeInterval = 3 * 3_600
            return SleepPlan(wake: p.wake + off, needMin: p.needMin, inBedMin: p.inBedMin, efficiency: p.efficiency,
                             bedtime100: p.bedtime100 + off, bedtime85: p.bedtime85 + off, bedtime70: p.bedtime70 + off,
                             basis: p.basis)
        }
        var later = SleepSchedule.default
        later.setWeekdays("07:30")
        later.setWeekend("07:30")
        await planner.update(later)
        #expect(planner.plan == nil && planner.problem == .otherTimeZone)
        #expect(state.repository.tonightBedtime == nil, "no bedtime the widget could show")

        // Another change, its plan on its way: the failure before isn't shown, Tonight plans.
        api.planFor = nil
        api.beforePlan = { _ in await gate.wait() }
        var earlier = later
        earlier.setWeekdays("06:00")
        earlier.setWeekend("06:00")
        planner.commit(earlier, for: planner.owner)
        #expect(planner.problem == nil && planner.tonight(locale: enUS).look == .planning)
        #expect(await eventually { gate.held == 1 })
        gate.release()
        await planner.settle()
        #expect(planner.plan != nil && state.repository.tonightBedtime != nil)
    }

    @Test("Offline with no plan ever: no reminder at an old bedtime, the page says they resume; online, they're set")
    func offlineWithoutAPlanWaits() async throws {
        let notifier = MockNotifier()
        let clock = TestClock()
        clock.set(Calendar.current.date(bySettingHour: 17, minute: 42, second: 0, of: clock.now()) ?? clock.now())
        let state = AppState(env: .test(clock: clock, notifier: notifier, flags: [.sleepPlanner: true], online: false))
        // A reminder from before (an earlier schedule's bedtime), still pending.
        let content = UNMutableNotificationContent()
        content.title = "Wind down"
        try await notifier.add(UNNotificationRequest(identifier: "bedtime.2026-11-20", content: content, trigger: nil))
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        var schedule = SleepSchedule.default
        schedule.reminderOn = true
        await planner.update(schedule)
        #expect(reminders(state).isEmpty && planner.remindersWaiting, "none left to fire at the wrong time")

        state.env.connectivityMonitor.update(true)
        await planner.refresh()
        #expect(!planner.remindersWaiting && !reminders(state).isEmpty && planner.plan != nil)
    }

    @Test("Estimated bedtimes are the wake time less each share of the last plan's time in bed")
    func estimate() {
        let wake = at(7, 30, add: 1)
        let estimate = BedtimePlanner.estimate(from: tonightsPlan, wake: wake)
        #expect(estimate.wake == wake && estimate.needMin == tonightsPlan.needMin)
        #expect(estimate.bedtime100 == wake.addingTimeInterval(-549 * 60))
        #expect(estimate.bedtime70 == wake.addingTimeInterval(-0.7 * 549 * 60))
    }
}

// MARK: - the rules

struct BedtimeRuleTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Ryft")

    /// The code only: a comment may name a token to say why it isn't used. `//` after a colon is a URL's.
    private static func code(_ path: String) throws -> String {
        let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        return source.replacing(#/(^|[^:])//.*/#) { String($0.output.1) }
    }

    @Test("Sleep shows no system error text: no localizedDescription in Features/Sleep")
    func noLocalizedDescription() throws {
        let folder = Self.root.appendingPathComponent("Features/Sleep")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") }
        #expect(files.count > 5)
        for file in files {
            #expect(try !Self.code("Features/Sleep/\(file)").contains("localizedDescription"), "\(file)")
        }
    }

    @Test("The wake alarm's look is literals, not asset colours (the system draws it): no Theme colour, no teal")
    func alarmLookIsLiterals() throws {
        let code = try Self.code("Features/Sleep/SleepPlannerViewModel.swift")
        let start = try #require(code.range(of: "enum AlarmKitWake {"))
        let end = try #require(code.range(of: "static func cancelAll()", range: start.upperBound..<code.endIndex))
        let wake = String(code[start.lowerBound..<end.lowerBound])
        #expect(wake.contains("static let tint = Color(red: 0.949, green: 0.945, blue: 0.925)"))
        #expect(wake.contains("static let snoozeText = Color(red: 0.039, green: 0.047, blue: 0.043)"))
        #expect(wake.contains("tintColor: tint") && wake.contains("textColor: snoozeText"))
        #expect(!wake.contains("Theme.") && !wake.contains("Color(\""), "an asset colour in the alarm's look")
        #expect(wake.firstMatch(of: #/\.(teal|mint|cyan)\b/#) == nil)
    }

    @Test("Tonight, Bedtime & wake and the wake alarm use no teal: teal is recovery's (L27)",
          arguments: ["Features/Sleep/SleepPlannerView.swift", "Features/Sleep/SleepBedtimeSection.swift",
                      "Features/Sleep/SleepPlannerViewModel.swift"])
    func noTeal(_ path: String) throws {
        let code = try Self.code(path)
        let teal = #/Theme\.(teal|accent\w*|onAccent|recovery)|Color\("(Accent|Teal|Recovery)|\.(teal|mint|cyan)\b|accentColor/#
        #expect(code.firstMatch(of: teal) == nil, "\(path): \(code.firstMatch(of: teal).map { String($0.output.0) } ?? "")")
        for token in ["Locale(identifier: \"de\")", "scheme: .light", "ProgressView", "navigationTitle", "Color.accentColor"] {
            #expect(!code.contains(token), "\(path) names \(token)")
        }
    }
}

// MARK: - in a window

#if canImport(AlarmKit)
@MainActor
struct AlarmKitWakeTests {
    private func rgb(_ color: Color) -> [Float] {
        let resolved = color.resolve(in: EnvironmentValues())
        return [resolved.red, resolved.green, resolved.blue]
    }

    @Test("The alarm's tint is Theme.textPrimary (#F2F1EC) and Snooze's words Theme.background (#0A0C0B), as literals")
    func literalsAreTheThemes() throws {
        guard #available(iOS 26.0, *) else { return }
        for (literal, theme, name) in [(AlarmKitWake.tint, Theme.textPrimary, "tint"),
                                       (AlarmKitWake.snoozeText, Theme.background, "Snooze")] {
            for (a, b) in zip(rgb(literal), rgb(theme)) {
                #expect(abs(a - b) < 0.002, "\(name): \(rgb(literal)) vs \(rgb(theme))")
            }
        }
    }
}
#endif

@MainActor
@Suite("C4: Tonight and Bedtime & wake in a window", .serialized)
struct BedtimeHostedTests {
    nonisolated private static let width: CGFloat = 390

    private func host(_ view: AnyView, height: CGFloat = 1_400, ax3: Bool = false,
                      body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: Self.width, height: height, bottomInset: 0,
                                   typeSize: ax3 ? .accessibility3 : .large,
                                   category: ax3 ? .accessibilityExtraLarge : .large, view, body: body)
    }

    private func node(_ w: HostedWindow, id: String) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.identifier == id }, "\(id) on screen")
    }

    private func has(_ w: HostedWindow, id: String) -> Bool { w.nodes().contains { $0.identifier == id } }

    private static func datePickers(in view: UIView) -> [UIDatePicker] {
        ((view as? UIDatePicker).map { [$0] } ?? []) + view.subviews.flatMap(datePickers)
    }

    // MARK: Tonight

    @Test("Set up: one element, Tonight, the summary as its value, no hint; then Why this need and Bedtime & wake")
    func tonightPlanned() async throws {
        let screen = await BedtimeShotScreen.screen("tonight")
        try await host(screen.view) { w in
            try await w.wait("the tile") { has(w, id: "tonight.tile") }
            try await w.settle()
            let tile = try node(w, id: "tonight.tile")
            #expect(tile.label == "Tonight")
            #expect(plain(tile.value).hasPrefix("In bed by ") && plain(tile.value).contains("percent of your need. Wake 6:30 AM"),
                    "\(plain(tile.value))")
            #expect(plain(tile.value).contains("your goal") && (tile.hint ?? "").isEmpty, "no hint: \(tile.hint ?? "")")
            #expect(w.node("Peak · 100\u{00A0}%") == nil && w.node("In bed by", exactly: true) == nil, "inside the one element")
            let why = try node(w, id: "tonight.why"), schedule = try node(w, id: "tonight.schedule")
            #expect(why.frame.minY >= tile.frame.maxY + TonightLayout.groupGap - 0.5 && schedule.frame.minY >= why.frame.maxY - 0.5)
            #expect(schedule.label == "Bedtime & wake" && plain(schedule.value) == "6:30 AM · weekend\u{00A0}8:00 AM",
                    "\(plain(schedule.value).unicodeScalars.map { String(format: "%04X", $0.value) })")
            #expect(tile.frame.height >= TonightLayout.tileMinHeight - 0.5)
            #expect(why.value == "Collapsed" && why.activate())
            try await w.wait("the need's terms") { w.node("Tonight's need") != nil }
            #expect(w.node("Baseline") != nil && w.node("Sleep debt") != nil)
        }
    }

    @Test("Not set up: the sentence and Set up Bedtime & wake")
    func tonightNotSetUp() async throws {
        let screen = await BedtimeShotScreen.screen("tonight-not-set-up")
        try await host(screen.view) { w in
            try await w.wait("Set up") { has(w, id: "tonight.setUp") }
            #expect(w.node("Tell RYFT when you want to wake up.") != nil)
            #expect(!has(w, id: "tonight.tile") && !has(w, id: "tonight.planning"))
        }
    }

    @Test("Loading: while the plan is on its way the outline, \"Planning tonight…\", no spinner; then the plan")
    func tonightLoading() async throws {
        let api = MockPlatformAPI()
        let gate = PlanGate()
        api.beforePlan = { _ in await gate.wait() }
        let (state, _) = BedtimeShotScreen.state(api: api)
        SleepSchedule.default.save(account: state.env.auth.accountID, defaults: state.env.defaults)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        try await host(BedtimeShotScreen.tonight(state, planner)) { w in
            try await w.wait("the request held") { gate.held == 1 }
            try await w.wait("planning") { has(w, id: "tonight.planning") }
            let planning = try node(w, id: "tonight.planning")
            #expect(planning.label == "Tonight" && planning.value == TonightBoard.planningText)
            #expect(Self.activityIndicators(in: w.host.view).isEmpty, "no spinner")
            gate.release()
            try await w.wait("the plan, the outline gone") { has(w, id: "tonight.tile") && !has(w, id: "tonight.planning") }
        }
    }

    @Test("Offline with a plan fetched earlier: the tile, As of")
    func tonightOfflineCached() async throws {
        let screen = await BedtimeShotScreen.screen("tonight-offline-cached")
        try await host(screen.view) { w in
            try await w.wait("the tile") { has(w, id: "tonight.tile") }
            #expect(plain(try node(w, id: "tonight.tile").value).contains("As of 5:42 PM."))
        }
    }

    @Test("Offline with nothing cached: the offline line, no button, never the outline; back online, the plan")
    func tonightOffline() async throws {
        let (state, _) = BedtimeShotScreen.state(online: false)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.update(.default)
        try await host(BedtimeShotScreen.tonight(state, planner)) { w in
            let line = "Tonight's bedtime needs a connection. It appears once you're online."
            try await w.wait("the offline line") { w.node(line) != nil }
            try await w.settle()
            #expect(!has(w, id: "tonight.planning") && !has(w, id: "tonight.failure.retry") && w.node("Details") == nil)
            state.env.connectivityMonitor.update(true)
            try await w.wait("the plan once online") { has(w, id: "tonight.tile") }
        }
    }

    @Test("Failed with nothing cached: Today's sentence, Details, Try again; the status only behind Details")
    func tonightFailed() async throws {
        let screen = await BedtimeShotScreen.screen("tonight-failed")
        try await host(screen.view) { w in
            try await w.wait("Try again") { has(w, id: "tonight.failure.retry") }
            let expected = SleepLoadFailure(APIError.http(503, "", requestID: "01JD8K2V9Q7M3X"), isOnline: true, at: .now)
            #expect(w.node(expected.message) != nil, "\(expected.message)")
            #expect(w.node("Details") != nil && !w.nodes().contains { $0.label.contains("HTTP 503") })
        }
    }

    @Test("AX3: the tile and the group on the page, the goals' times under their titles inside the tile")
    func tonightAX3() async throws {
        let screen = await BedtimeShotScreen.screen("tonight")
        try await host(screen.view, height: 2_400, ax3: true) { w in
            try await w.wait("the tile") { has(w, id: "tonight.tile") }
            try await w.settle()
            for node in w.nodes() {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= Self.width + 0.5, "\(node.label) cut: \(node.frame)")
            }
            let tile = try node(w, id: "tonight.tile")
            #expect(tile.frame.width <= Self.width - 2 * Theme.Metrics.screenPadding + 0.5)
        }
    }

    @Test("AX3, the widest bedtime (12:08 AM on a 12-hour clock): every part of the tile inside it")
    func tonightAX3WorstCase() async throws {
        var schedule = SleepSchedule.default
        schedule.goal = .getBy
        let board = TonightBoard(schedule: schedule, plan: tonightsPlan, asOf: at(17, 42), locale: enUS)
        #expect(board.digits == "12:08" && board.meridiem == "AM")
        let side = Theme.Metrics.screenPadding
        let view = AnyView(TonightTile(board: board)
            .padding(.horizontal, side)
            .frame(width: Self.width)
            .environment(\.locale, enUS))
        try await host(view, height: 1_600, ax3: true) { w in
            try await w.wait("the tile's parts") { w.node("In bed by", exactly: true) != nil }
            try await w.settle()
            let inset = GlowTileSpec.padding(for: .hypnogram)
            let inner = CGRect(x: side + inset.leading - 0.5, y: 0,
                               width: Self.width - 2 * side - inset.leading - inset.trailing + 1, height: 1_600)
            let parts = w.nodes()
            for label in ["Tonight", "In bed by", "AM", "12:08 AM"] {
                #expect(parts.contains { plain($0.label) == label }, "\(label) on screen: \(parts.map(\.label))")
            }
            for part in parts {
                #expect(part.frame.minX >= inner.minX && part.frame.maxX <= inner.maxX,
                        "\(part.label) outside the tile's padding: \(part.frame) vs \(inner)")
            }
        }
    }

    @Test("Set up, then back without a change: set up with what the page showed, and Tonight plans")
    func tonightSetUpThenBack() async throws {
        let (state, _) = BedtimeShotScreen.state()
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        try await host(BedtimeShotScreen.tonight(state, planner)) { w in
            try await w.wait("Set up") { has(w, id: "tonight.setUp") }
            #expect(try node(w, id: "tonight.setUp").activate())
            try await w.wait("the page") { has(w, id: "schedule.sameOnWeekdays") }
            try await w.settle()
            #expect(planner.schedule == nil, "nothing set up while it shows")
            #expect(try node(w, id: "subpage.back").activate())
            try await w.wait("back on Tonight, planned") { has(w, id: "tonight.tile") }
            #expect(planner.schedule == .default)
        }
    }

    // MARK: Bedtime & wake

    @Test("The time chips: Weekdays and Weekend beside their titles; each day once the weekdays differ; each reads its time")
    func timeChips() async throws {
        let screen = await BedtimeShotScreen.screen("bedtime-wake")
        try await host(screen.view) { w in
            try await w.wait("the page") { has(w, id: "schedule.sameOnWeekdays") }
            try await w.settle()
            var pickers = Self.datePickers(in: w.host.view)
            #expect(pickers.count == 2, "Weekdays and Weekend")
            for (title, picker) in zip(["Weekdays", "Weekend"], pickers.sorted { $0.frame(in: w).minY < $1.frame(in: w).minY }) {
                let label = try #require(w.node(title, exactly: true), "\(title)")
                #expect(abs(picker.frame(in: w).midY - label.frame.midY) < 4, "\(title) beside its chip")
                // VoiceOver: "Weekdays, 6:30 AM": the picker's name, then the time its button shows.
                #expect(picker.accessibilityLabel == title, "\(picker.accessibilityLabel ?? "")")
                let spoken = Self.spoken(in: picker)
                #expect(spoken.contains { plain($0).contains(title == "Weekdays" ? "6:30 AM" : "8:00 AM") }, "\(spoken)")
            }
            let same = try node(w, id: "schedule.sameOnWeekdays")
            #expect(same.activate())
            try await w.wait("each day") { Self.datePickers(in: w.host.view).count == 7 }
            pickers = Self.datePickers(in: w.host.view)
            #expect(w.node(Calendar.current.standaloneWeekdaySymbols[2], exactly: true) != nil, "Tuesday by its name")
        }
    }

    @Test("AX3: every chip under its title, on the page; the wind-down is a menu row")
    func timeChipsAX3() async throws {
        let screen = await BedtimeShotScreen.screen("bedtime-wake-days")
        try await host(screen.view, height: 4_000, ax3: true) { w in
            try await w.wait("the page") { has(w, id: "schedule.sameOnWeekdays") }
            try await w.settle()
            let pickers = Self.datePickers(in: w.host.view).map { $0.frame(in: w) }.sorted { $0.minY < $1.minY }
            #expect(pickers.count == 7)
            let names = Calendar.current.standaloneWeekdaySymbols
            for (name, chip) in zip(Array(names[1...]) + [names[0]], pickers) {
                let label = try #require(w.node(name, exactly: true), "\(name)")
                // The system picker over the chip reaches past it: its middle is the chip's.
                #expect(chip.midY > label.frame.maxY, "\(name): under its title, \(chip) \(label.frame)")
                #expect(chip.minX >= 0 && chip.maxX <= Self.width + 0.5, "\(name): on the page")
            }
            for node in w.nodes() {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= Self.width + 0.5, "\(node.label) cut: \(node.frame)")
            }
            #expect(has(w, id: "schedule.windDown"), "the menu row")
        }
    }

    @Test("A goal reads its share and selected; the reminder keeps its identifier; Turn off ends the page")
    func goalsAndIdentifiers() async throws {
        let screen = await BedtimeShotScreen.screen("bedtime-wake")
        try await host(screen.view) { w in
            try await w.wait("the page") { has(w, id: "schedule.goal.100") }
            let peak = try node(w, id: "schedule.goal.100")
            #expect(peak.label == "Peak" && plain(peak.value) == "100\u{00A0}% of your need" && peak.isSelected)
            #expect(try !node(w, id: "schedule.goal.85").isSelected)
            for id in ["schedule.reminder", "schedule.alarm", "schedule.turnOff"] { #expect(has(w, id: id), "\(id)") }
            #expect(w.node("Changes save as you make them.") != nil)
        }
    }

    @Test("iOS refuses the alarm: an amber row in its group with Open Settings, the switch off")
    func refusedAlarm() async throws {
        let screen = await BedtimeShotScreen.screen("bedtime-wake-refused")
        try await host(screen.view) { w in
            try await w.wait("the page") { has(w, id: "schedule.alarm") }
            try await w.settle()
            let before = try node(w, id: "schedule.alarm").value
            if let interact = screen.interact { try await interact(w) }
            let row = try node(w, id: "schedule.alarm.refused")
            let alarm = try node(w, id: "schedule.alarm"), turnOff = try node(w, id: "schedule.turnOff")
            #expect(row.frame.minY >= alarm.frame.maxY - 0.5 && row.frame.maxY <= turnOff.frame.minY, "in the alarm's group")
            let open = try node(w, id: "schedule.alarm.refused.openSettings")
            #expect(open.label == "Open Settings" && open.frame.height >= Theme.Metrics.minHitTarget - 0.5)
            // Open Settings on its own line, so the sentence keeps one (a callout line is about 20 pt; two would be 40).
            #expect(open.frame.minY >= row.frame.maxY - 0.5, "under the sentence: \(open.frame) \(row.frame)")
            #expect(row.frame.height < 30, "the sentence on one line: \(row.frame)")
            #expect(alarm.value == before, "still off: \(alarm.value ?? "")")
        }
    }

    @Test("iOS stopped allowing the alarm: the planner's sentence, amber, in the alarm's group")
    func alarmProblem() async throws {
        let screen = await BedtimeShotScreen.screen("bedtime-wake-alarm-problem")
        try await host(screen.view) { w in
            try await w.wait("the sentence") { has(w, id: "schedule.alarm.problem") }
            let row = try node(w, id: "schedule.alarm.problem"), alarm = try node(w, id: "schedule.alarm")
            #expect(row.label.hasPrefix("The wake-up alarm is off") && row.frame.minY >= alarm.frame.maxY - 0.5)
        }
    }

    @Test("Turn off asks first: the dialog from the row, Turn off destructive, Cancel; what goes in the footer; the tap alone turns nothing off")
    func turnOffAsksFirst() async throws {
        let (state, _) = BedtimeShotScreen.state()
        let alarms = MockWakeAlarms()
        let planner = BedtimePlanner(state: state, alarms: alarms)
        var schedule = SleepSchedule.default
        schedule.reminderOn = true
        schedule.alarmOn = true
        await planner.update(schedule)
        #expect(alarms.scheduled != nil && !reminders(state).isEmpty)
        try await host(SubpageShotScreen.pushed(state) { SleepScheduleView(planner: planner) }) { w in
            try await w.wait("the page") { has(w, id: "schedule.turnOff") }
            try await w.settle()
            // What goes is said before the tap: the footer under the row (the dialog keeps to its title).
            let row = try node(w, id: "schedule.turnOff")
            let footer = try #require(w.node(Self.turnOffFooter, exactly: true), "the footer")
            #expect(footer.frame.minY >= row.frame.maxY - 0.5, "under the row: \(footer.frame) \(row.frame)")
            #expect(row.activate())
            var alert: UIAlertController?
            try await w.wait("the dialog") {
                alert = Self.presentedAlert(w.host)
                return alert != nil
            }
            let dialog = try #require(alert)
            #expect(dialog.title == "Turn off Bedtime & wake?")
            #expect((dialog.message ?? "").isEmpty, "the dialog's message: \(dialog.message ?? "")")
            // iOS 26 draws it as a popover from its source: the row, not the alarm's card above it or the page.
            if let popover = dialog.popoverPresentationController, let source = popover.sourceView {
                let anchor = source.convert(popover.sourceRect, to: nil)
                let onTheRow = row.frame.insetBy(dx: -1, dy: -1).contains(CGPoint(x: anchor.midX, y: anchor.midY))
                #expect(onTheRow && anchor.height < row.frame.height * 2, "the dialog's source \(anchor), the row \(row.frame)")
            } else if #available(iOS 26, *) {
                Issue.record("no popover source for the dialog")
            }
            #expect(dialog.actions.contains { $0.title == "Turn off" && $0.style == .destructive })
            #expect(dialog.actions.contains { $0.style == .cancel })
            #expect(has(w, id: "schedule.sameOnWeekdays"), "still set up while it asks")
            #expect(planner.schedule != nil, "the tap alone turns nothing off")

            // Turn off: it turns off, and the page goes (dismiss).
            try Self.choose("Turn off", in: dialog)
            try await w.wait("turned off") { planner.schedule == nil && !planner.editor.isTurningOff }
            try await w.wait("the page gone") { !has(w, id: "schedule.sameOnWeekdays") }
            #expect(planner.schedule == nil && stored(state) == nil && !planner.editor.isTurningOff)
            #expect(alarms.scheduled == nil && reminders(state).isEmpty && state.repository.tonightBedtime == nil)
        }
    }

    /// The footer under Turn off: what turning it off removes and stops.
    private static let turnOffFooter = "Your wake times, goal and wind-down are removed from this iPhone, and the bedtime reminder and the wake-up alarm stop."

    /// The dialog's button `title`, as a tap runs it: the dialog goes, then its handler runs (UIKit keeps it private).
    private static func choose(_ title: String, in alert: UIAlertController) throws {
        typealias Handler = @convention(block) (UIAlertAction) -> Void
        let action = try #require(alert.actions.first { $0.title == title }, "\(alert.actions.map(\.title))")
        let handler = try #require(action.value(forKey: "handler") as AnyObject?, "a handler")
        let run = { unsafeBitCast(handler, to: Handler.self)(action) }
        if alert.presentingViewController != nil { alert.dismiss(animated: false, completion: run) } else { run() }
    }

    @Test("While Turn off runs: the row keeps its title, is busy and asks nothing again; the rest of the page takes no taps")
    func turnOffBusy() async throws {
        let (state, _) = BedtimeShotScreen.state()
        let alarms = HeldWakeAlarms()
        alarms.release()
        let planner = BedtimePlanner(state: state, alarms: alarms)
        var schedule = SleepSchedule.default
        schedule.alarmOn = true
        await planner.update(schedule)
        let view = SubpageShotScreen.pushed(state) { SleepScheduleView(planner: planner) }
        try await host(view) { w in
            try await w.wait("the page") { has(w, id: "schedule.turnOff") }
            try await w.settle()
            alarms.holdsCancel = true
            let turning = Task { await planner.editor.turnOff() }
            try await w.wait("busy") { w.nodes().first { $0.identifier == "schedule.turnOff" }?.value == "In progress" }
            let row = try node(w, id: "schedule.turnOff")
            #expect(row.label == "Turn off Bedtime & wake", "the busy rule: the title stays (\(row.label))")
            row.activate()
            try await w.settle()
            #expect(Self.presentedAlert(w.host) == nil, "a tap while it turns off asks nothing")
            #expect(try !node(w, id: "schedule.goal.85").isEnabled && !node(w, id: "schedule.alarm").isEnabled, "the page disabled")
            alarms.release()
            await turning.value
            try await w.wait("off") { !has(w, id: "schedule.turnOff") }
            #expect(planner.schedule == nil && alarms.current == nil)
        }
    }

    @Test("Offline with no plan ever and the reminder on: the reminder's group says they resume once there is a plan")
    func remindersWaiting() async throws {
        let (state, _) = BedtimeShotScreen.state(online: false)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        var schedule = SleepSchedule.default
        schedule.reminderOn = true
        await planner.update(schedule)
        #expect(planner.remindersWaiting)
        let view = SubpageShotScreen.pushed(state) { SleepScheduleView(planner: planner) }
        try await host(view) { w in
            try await w.wait("the line") { has(w, id: "schedule.reminder.waiting") }
            let line = try node(w, id: "schedule.reminder.waiting"), toggle = try node(w, id: "schedule.reminder")
            #expect(line.label == "Reminders resume once RYFT has tonight's plan.")
            #expect(line.frame.minY >= toggle.frame.maxY - 0.5, "under the switch, in its group")
        }
    }

    @Test("Two ways in on one planner: a change on one page shows on the other; the other leaving keeps it")
    func twoWaysIn() async throws {
        let (state, _) = BedtimeShotScreen.state()
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.update(.default)
        let shown = TwoPages()
        let view = AnyView(VStack(spacing: 0) {
            NavigationStack { SleepScheduleView(planner: planner) }.frame(height: 900)
            TwoPages.Second(shown: shown, planner: planner).frame(height: 900)
        }
        .previewEnvironment(state)
        .toggleStyle(.ryft)
        .environment(\.locale, enUS))
        try await host(view, height: 1_800) { w in
            try await w.wait("both pages") { w.nodes().filter { $0.identifier == "schedule.goal.70" }.count == 2 }
            try await w.settle()
            let first = try #require(w.nodes().filter { $0.identifier == "schedule.goal.70" }.min { $0.frame.minY < $1.frame.minY })
            #expect(first.activate())
            try await w.wait("selected on both") {
                let rows = w.nodes().filter { $0.identifier == "schedule.goal.70" }
                return rows.count == 2 && rows.allSatisfy(\.isSelected)
            }
            shown.second = false   // the second page goes (its onDisappear leaves)
            try await w.wait("one page") { w.nodes().filter { $0.identifier == "schedule.goal.70" }.count == 1 }
            await planner.editor.settle()
            #expect(planner.schedule?.goal == .getBy, "leaving the other page saved the change, never an older copy")
        }
    }

    @Test("Opened from Set up: the first leave sets it up, once; after a Turn off elsewhere, leaving again sets nothing up")
    func setUpOnce() async throws {
        let (state, _) = BedtimeShotScreen.state()
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        let path = PagePath()
        let view = AnyView(PagePath.Stack(path: path, planner: planner)
            .previewEnvironment(state)
            .toggleStyle(.ryft)
            .environment(\.locale, enUS))
        try await host(view) { w in
            path.pages = [.schedule]
            try await w.wait("the page") { has(w, id: "schedule.sameOnWeekdays") }
            try await w.settle()
            #expect(planner.schedule == nil)
            path.pages = [.schedule, .other]   // a page over it: it is left
            try await w.wait("covered") { has(w, id: "other.page") }
            try await w.wait("set up as it showed") { planner.schedule == .default }

            await planner.editor.turnOff()   // elsewhere (Profile's page)
            #expect(planner.schedule == nil)
            path.pages = [.schedule]
            try await w.wait("the page again") { has(w, id: "schedule.sameOnWeekdays") }
            path.pages = []
            try await w.wait("gone") { !has(w, id: "schedule.sameOnWeekdays") }
            try await w.settle()
            await planner.editor.settle()
            #expect(planner.schedule == nil && stored(state) == nil, "not set up again")
        }
    }

    @Test("Today: Bedtime & wake pushed from Tonight stays open when the evening ends and Tonight leaves Today")
    func todayKeepsThePage() async throws {
        let (state, clock) = BedtimeShotScreen.state()
        // Scored days on this iPhone: Today isn't a first import (which shows no Tonight).
        state.history = MockData.history
        state.insights = MockData.insights
        state.readinessWeek = MockData.trend(.readiness, range: .week)
        state.today = MockData.todayDetail
        SleepSchedule.default.save(account: state.env.auth.accountID, defaults: state.env.defaults)
        let sync = SyncService(env: state.env)
        let screens = ScreenModels(state: state, sync: sync,
                                   coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync),
                                                                clock: state.env.clock),
                                   store: TrainPreview.store, library: TrainPreview.library)
        let poke = TodayPoke()
        let view = AnyView(TodayPoke.Today(poke: poke)
            .environment(\.appEnvironment, state.env)
            .environment(screens)
            // The graph's own settings (a private defaults suite, `AppEnvironment.test`): never the test host's.
            .environment(state.env.settings)
            .environment(state.env.auth)
            .environment(sync)
            .environment(state)
            .environment(TrainPreview.library)
            .environment(TrainPreview.sync)
            .environment(TrainPreview.coordinator)
            .environment(state.env.connectivityMonitor)
            .environment(\.locale, enUS))
        try await host(view, height: 2_400) { w in
            do {
                try await w.wait("Tonight's row", timeout: .seconds(20)) { has(w, id: "tonight.schedule") }
            } catch {
                Issue.record("Today without Tonight: importing \(screens.today.content.hero.isImporting), plan \(screens.bedtime.plan != nil)")
                throw error
            }
            #expect(try node(w, id: "tonight.schedule").activate())
            try await w.wait("the page") { has(w, id: "schedule.sameOnWeekdays") }
            try await w.settle()
            // Today under the page, as it is: Tonight in it (what the check below sees once Tonight has gone).
            try await w.wait("Today under the page, with Tonight") { Self.covered(w).contains("tonight.schedule") }
            // 9:00 the next day, after its wake: the planner plans the next night, and Today no longer shows Tonight.
            let next = Calendar.current.date(byAdding: .day, value: 1, to: clock.now()) ?? clock.now()
            clock.set(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: next) ?? next)
            await screens.bedtime.refresh()
            #expect(!screens.bedtime.isEvening())
            // Today redraws under the page (its text size changes), now without Tonight: the card goes.
            poke.size = .xLarge
            try await w.wait("Tonight gone from Today under the page") {
                let under = Self.covered(w)
                return !under.contains("tonight.schedule") && under.contains { $0.hasPrefix("today.") }
            }
            try await w.settle()
            #expect(has(w, id: "schedule.sameOnWeekdays") && Self.stackDepth(w) == 2, "the page still on top")
            #expect(try node(w, id: "subpage.back").activate())
            try await w.wait("back on Today") { !has(w, id: "schedule.sameOnWeekdays") }
            #expect(!has(w, id: "tonight.schedule"), "Today without Tonight")
        }
    }

    /// The navigation stack in the window.
    private static func navigation(_ controller: UIViewController) -> UINavigationController? {
        if let navigation = controller as? UINavigationController { return navigation }
        for child in controller.children { if let found = navigation(child) { return found } }
        return nil
    }

    private static func stackDepth(_ w: HostedWindow) -> Int { navigation(w.host)?.viewControllers.count ?? 0 }

    /// The identifiers in the stack's root while a page covers it: UIKit takes the root's view out of the window, so
    /// `nodes()` can't reach it. Empty when nothing covers the root.
    private static func covered(_ w: HostedWindow) -> [String] {
        guard let stack = navigation(w.host), stack.viewControllers.count > 1,
              let root = stack.viewControllers.first?.view else { return [] }
        var found: [String] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ object: NSObject, depth: Int) {
            guard depth < 40, seen.insert(ObjectIdentifier(object)).inserted else { return }
            if let id = object.value(forKey: "accessibilityIdentifier") as? String, !id.isEmpty { found.append(id) }
            if let elements = object.accessibilityElements {
                for case let child as NSObject in elements { walk(child, depth: depth + 1) }
            } else {
                let count = object.accessibilityElementCount()
                if count != NSNotFound, count > 0 {
                    for i in 0..<count { if let child = object.accessibilityElement(at: i) as? NSObject { walk(child, depth: depth + 1) } }
                }
            }
            if let view = object as? UIView { for sub in view.subviews { walk(sub, depth: depth + 1) } }
        }
        walk(root, depth: 0)
        return found
    }

    private static func presentedAlert(_ controller: UIViewController) -> UIAlertController? {
        if let alert = controller as? UIAlertController { return alert }
        for child in controller.children { if let found = presentedAlert(child) { return found } }
        return controller.presentedViewController.flatMap(presentedAlert)
    }

    /// What VoiceOver can read inside `object`: each element's label and value.
    private static func spoken(in object: NSObject, depth: Int = 0) -> [String] {
        guard depth < 12 else { return [] }
        var found: [String] = []
        if object.isAccessibilityElement {
            found.append([object.accessibilityLabel, object.accessibilityValue].compactMap { $0 }.joined(separator: ", "))
        }
        if let elements = object.accessibilityElements {
            for case let child as NSObject in elements { found += spoken(in: child, depth: depth + 1) }
        }
        if let view = object as? UIView { for sub in view.subviews { found += spoken(in: sub, depth: depth + 1) } }
        return found
    }

    private static func activityIndicators(in view: UIView) -> [UIActivityIndicatorView] {
        ((view as? UIActivityIndicatorView).map { [$0] } ?? []) + view.subviews.flatMap(activityIndicators)
    }
}

private extension UIView {
    func frame(in w: HostedWindow) -> CGRect { convert(bounds, to: w.window) }
}

/// Whether the second of two Bedtime & wake pages is on screen (`twoWaysIn`).
@MainActor
@Observable
private final class TwoPages {
    var second = true

    struct Second: View {
        let shown: TwoPages
        let planner: BedtimePlanner

        var body: some View {
            if shown.second {
                NavigationStack { SleepScheduleView(planner: planner) }
            } else {
                Color.clear
            }
        }
    }
}

/// Today with a text size the test changes: a change Today's body reads (`todayKeepsThePage`).
@MainActor
@Observable
private final class TodayPoke {
    var size = DynamicTypeSize.large

    struct Today: View {
        let poke: TodayPoke

        var body: some View {
            TodayView().environment(\.dynamicTypeSize, poke.size)
        }
    }
}

/// A stack the test pushes on: Bedtime & wake opened from Set up, and a page over it (`setUpOnce`).
@MainActor
@Observable
private final class PagePath {
    enum Page: Hashable {
        case schedule, other
    }

    var pages: [Page] = []

    struct Stack: View {
        @Bindable var path: PagePath
        let planner: BedtimePlanner

        var body: some View {
            NavigationStack(path: $path.pages) {
                Color.clear.navigationDestination(for: Page.self) { page in
                    switch page {
                    case .schedule: SleepScheduleView(planner: planner, opening: .setUp)
                    case .other: Text(verbatim: "Over it").accessibilityIdentifier("other.page")
                    }
                }
            }
        }
    }
}
