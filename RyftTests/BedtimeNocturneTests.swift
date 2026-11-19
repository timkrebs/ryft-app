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
        #expect(plain(board.line) == "for 100 % · wake 6:30 AM · need 8:18")
        #expect(board.goals.map(\.title) == ["Peak · 100 %", "Perform · 85 %", "Get by · 70 %"])
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
        #expect(board.digits == "11:19" && plain(board.line).hasPrefix("for 85 % · "))
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
        (state.env.connectivity as? ConnectivityMonitor)?.update(true)
        #expect(planner.tonight(locale: enUS).look == .planning, "online: planning, not offline")
        await planner.refresh()
        #expect(planner.tonight(locale: enUS).look == .planned && planner.problem == nil)
    }

    @Test("Offline with a plan fetched earlier: the plan, As of when it came")
    func offlineCached() async throws {
        let (state, clock) = makeState()
        await BedtimePlanner(state: state, alarms: MockWakeAlarms()).update(.default)
        clock.advance(by: .seconds(3_600))
        (state.env.connectivity as? ConnectivityMonitor)?.update(false)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.refresh()
        let board = planner.tonight(locale: enUS)
        #expect(board.look == .planned && board.asOf != nil && planner.error == nil)
    }
}

// MARK: - Bedtime & wake's saving

/// Wake alarms whose `schedule` waits until released: a save on its way, held.
private final class HeldWakeAlarms: WakeAlarms {
    let ringsLikeAnAlarm = true
    private(set) var scheduled: [[String]] = []
    private var held: [CheckedContinuation<Void, Never>] = []
    private var holds = true
    var waiting: Int { held.count }

    func authorize() async -> Bool { true }
    func isAllowed() async -> Bool { true }
    func schedule(_ times: [String]) async throws {
        if holds { await withCheckedContinuation { held.append($0) } }
        scheduled.append(times)
    }
    func cancelAll() async {}

    func release() {
        holds = false
        let waiting = held
        held = []
        for continuation in waiting { continuation.resume() }
    }
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
        let editor = BedtimeScheduleEditor(planner: planner)
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
    }

    @Test("Saves go one after the other: a change made while one is on its way waits for it, and the last one stays")
    func savesInOrder() async throws {
        let (state, clock) = makeState()
        let alarms = HeldWakeAlarms()
        let planner = BedtimePlanner(state: state, alarms: alarms)
        let editor = BedtimeScheduleEditor(planner: planner)
        editor.edit { $0.alarmOn = true; $0.setWeekdays("06:45"); $0.setWeekend("06:45") }
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        #expect(await eventually { alarms.waiting == 1 }, "the first save on its way")

        editor.edit(wake("07:15"))
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        #expect(await eventually { clock.pendingSleeps == 0 })
        for _ in 0..<20 { await Task.yield() }
        #expect(planner.schedule?.wake[0] == "06:45" && alarms.waiting == 1, "the second waits for the first")

        alarms.release()
        await editor.settle()
        #expect(planner.schedule?.wake[0] == "07:15" && planner.schedule?.alarmOn == true)
        #expect(alarms.scheduled.map { $0[0] } == ["06:45", "07:15"], "in order")
    }

    @Test("Leaving saves a change made just before; leaving without one saves nothing")
    func leave() async throws {
        let api = MockPlatformAPI()
        let (state, clock) = makeState(api: api)
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        let untouched = BedtimeScheduleEditor(planner: planner)
        untouched.leave()
        await untouched.settle()
        #expect(planner.schedule == nil && api.planWakes.isEmpty)

        let editor = BedtimeScheduleEditor(planner: planner)
        editor.edit { $0.goal = .getBy }
        editor.leave()
        await editor.settle()
        #expect(planner.schedule?.goal == .getBy && clock.pendingSleeps == 0)
    }

    @Test("An alarm iOS no longer allows can't be set: the switch goes back off and the planner says why")
    func refusedAlarmGoesBack() async throws {
        let (state, clock) = makeState()
        let alarms = MockWakeAlarms()
        let planner = BedtimePlanner(state: state, alarms: alarms)
        let editor = BedtimeScheduleEditor(planner: planner)
        #expect(await editor.setAlarm(true))
        #expect(editor.draft.alarmOn && !editor.alarmRefused)
        alarms.allowed = false   // allowed when asked, then turned off in iOS Settings before the save
        #expect(await eventually { clock.pendingSleeps == 1 })
        clock.advance(by: BedtimeScheduleEditor.saveDelay)
        await editor.settle()
        #expect(!editor.draft.alarmOn && planner.schedule?.alarmOn == false, "back as it was")
        #expect(planner.alarmProblem == "The wake-up alarm is off: iOS doesn't allow RYFT's alarms. Turn it on again to allow them.")
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
        let editor = BedtimeScheduleEditor(planner: planner)
        #expect(await !editor.setReminder(true))
        #expect(await !editor.setAlarm(true))
        #expect(editor.reminderRefused && editor.alarmRefused && !editor.draft.reminderOn && !editor.draft.alarmOn)
        #expect(clock.pendingSleeps == 0 && !editor.edited)
    }

    @Test("Turn off waits for the saves before it, then there's no schedule")
    func turnOff() async throws {
        let (state, clock) = makeState()
        let planner = BedtimePlanner(state: state, alarms: MockWakeAlarms())
        await planner.update(.default)
        let editor = BedtimeScheduleEditor(planner: planner)
        editor.edit { $0.goal = .perform }
        await editor.turnOff()
        #expect(planner.schedule == nil && clock.pendingSleeps == 0)
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

    @Test("Tonight and Bedtime & wake use no teal: teal is recovery's (L27)",
          arguments: ["Features/Sleep/SleepPlannerView.swift", "Features/Sleep/SleepBedtimeSection.swift"])
    func noTeal(_ path: String) throws {
        let code = try Self.code(path)
        #expect(code.firstMatch(of: #/Theme\.(teal|accent\w*|onAccent|recovery)|Color\("(Accent|Teal|Recovery)/#) == nil, "\(path)")
        for token in ["Locale(identifier: \"de\")", "scheme: .light", "ProgressView", "navigationTitle", "Color.accentColor"] {
            #expect(!code.contains(token), "\(path) names \(token)")
        }
    }
}

// MARK: - in a window

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

    @Test("Set up: one element, Tonight, the summary as its value and a hint; then Why this need and Bedtime & wake")
    func tonightPlanned() async throws {
        let screen = await BedtimeShotScreen.screen("tonight")
        try await host(screen.view) { w in
            try await w.wait("the tile") { has(w, id: "tonight.tile") }
            try await w.settle()
            let tile = try node(w, id: "tonight.tile")
            #expect(tile.label == "Tonight")
            #expect(plain(tile.value).hasPrefix("In bed by ") && plain(tile.value).contains("percent of your need. Wake 6:30 AM"),
                    "\(plain(tile.value))")
            #expect(plain(tile.value).contains("your goal") && !(tile.hint ?? "").isEmpty)
            #expect(w.node("Peak · 100 %") == nil && w.node("In bed by", exactly: true) == nil, "inside the one element")
            let why = try node(w, id: "tonight.why"), schedule = try node(w, id: "tonight.schedule")
            #expect(why.frame.minY >= tile.frame.maxY + TonightLayout.groupGap - 0.5 && schedule.frame.minY >= why.frame.maxY - 0.5)
            #expect(schedule.label == "Bedtime & wake" && plain(schedule.value) == "6:30 AM · weekend 8:00 AM")
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

    @Test("Loading: the outline, \"Planning tonight…\", no spinner")
    func tonightLoading() async throws {
        let screen = await BedtimeShotScreen.screen("tonight-loading")
        try await host(screen.view) { w in
            try await w.wait("planning") { has(w, id: "tonight.planning") }
            let planning = try node(w, id: "tonight.planning")
            #expect(planning.label == "Tonight" && planning.value == TonightBoard.planningText)
            #expect(Self.activityIndicators(in: w.host.view).isEmpty, "no spinner")
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
            (state.env.connectivity as? ConnectivityMonitor)?.update(true)
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
            #expect(peak.label == "Peak" && plain(peak.value) == "100 % of your need" && peak.isSelected)
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
