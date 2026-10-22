import Foundation
import Testing
import UIKit
@testable import Ryft

/// A signed-in test graph (in-memory store), its read state and the clock.
@MainActor
private func makeState(api: MockPlatformAPI = MockPlatformAPI(), health: MockHealthStore = MockHealthStore(),
                       now: Date = .now, online: Bool = true) -> (AppEnvironment, AppState, TestClock) {
    let clock = TestClock(now: now)
    let env = AppEnvironment.test(api: api, health: health, clock: clock, online: online)
    return (env, AppState(env: env), clock)
}

/// The live pipeline over the test graph (fakes behind it, TestClock for its waits).
@MainActor
private func coordinator(_ state: AppState, _ sync: SyncService) -> SyncCoordinator {
    SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: state.env.clock)
}

private func day(_ offset: Int, from date: Date = .now) -> String {
    DayFormat.string(from: DayFormat.shift(date, days: offset))
}

// MARK: - Today

/// Each view model gets its own `APIStatus`: the shared one carries retry notices
/// from other suites running in parallel.
@Suite("Today view model")
@MainActor
struct TodayViewModelTests {
    @Test func loadsTheBriefing() async {
        let (env, state, _) = makeState()
        let vm = { let sync = SyncService(env: env); return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()
        #expect(vm.readiness == nil)
        #expect(vm.sleepText == Fmt.placeholder)

        await state.refresh()

        #expect(vm.readiness == state.today?.score.readiness.map(Double.init))
        #expect(vm.recoveryText == Fmt.percent(state.today?.score.recovery))
        #expect(vm.recoveryBand != nil)
        #expect(vm.readinessWeek.count == state.readinessWeek?.points.count)
        #expect(vm.status == nil)
        #expect(vm.lastUpdated == env.clock.now())
    }

    @Test func greetingFollowsTheClock() {
        let morning = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        let (env, state, clock) = makeState(now: morning)
        let vm = { let sync = SyncService(env: env); return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()
        #expect(vm.greeting == String(localized: "Good morning,"))
        clock.set(Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now)!)
        #expect(vm.greeting == String(localized: "Good evening,"))
    }

    /// Nothing cached at all: the card shows after one failed pass (a blank Today is the alternative).
    @Test func failureWithoutDataShowsTheCardAfterOnePass() async {
        let api = MockPlatformAPI()
        api.failure = APIError.http(500, "", requestID: "rid-500")
        let (env, state, _) = makeState(api: api)
        let vm = { let sync = SyncService(env: env); return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()

        await state.refresh()

        guard case .refreshIssue(let issue) = vm.status else {
            Issue.record("expected the card, got \(String(describing: vm.status))")
            return
        }
        #expect(issue.reason == .busy && issue.resource == .today && issue.failures == 1 && issue.dataFrom == nil)
        #expect(issue.error.status == 500 && issue.error.requestID == "rid-500" && issue.error.attempts == 3)
        #expect(api.count("day") == 3) // two silent retries first
    }

    /// Criterion 8/9 from the failure itself: status, code, request ID and resource reach the card's issue,
    /// and the line then reads "Couldn't load today · Details".
    @Test func theCardCarriesTheFailuresStatusCodeAndRequestID() async {
        let api = MockPlatformAPI()
        api.failure = APIError.http(503, "request timed out", requestID: "rid-503", code: .consentRequired)
        let (env, state, _) = makeState(api: api)
        let vm = { let sync = SyncService(env: env); return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()

        await state.refresh()

        guard case .refreshIssue(let issue) = vm.status else {
            Issue.record("expected the card, got \(String(describing: vm.status))")
            return
        }
        #expect(issue.resourceName == ReadResource.today.displayName)
        #expect(issue.statusText == "503" && issue.error.requestID == "rid-503")
        #expect(vm.syncLine.text(now: env.clock.now()) == String(localized: "Couldn't load today · Details"))
    }

    /// Criterion 8: the line's tap. With the card on screen it scrolls to the card (once per tap) and
    /// opens nothing; otherwise it opens Sync details.
    @Test func tappingTheIssueLineScrollsToTheCardInsteadOfOpeningDetails() async {
        let api = MockPlatformAPI()
        api.failure = APIError.http(500, "", requestID: "rid-500")
        let (env, state, _) = makeState(api: api)
        let vm = { let sync = SyncService(env: env); return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()
        await state.refresh()
        #expect(vm.syncLine == .issue(.today))
        #expect(vm.scrollToIssue == 0)

        vm.resolveLine()
        #expect(vm.scrollToIssue == 1 && !vm.showsSyncDetails)
        vm.resolveLine()
        #expect(vm.scrollToIssue == 2 && !vm.showsSyncDetails)
    }

    @Test func tappingAnyOtherLineOpensSyncDetails() async {
        let (env, state, _) = makeState()
        let vm = { let sync = SyncService(env: env); return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()
        await state.refresh()
        #expect(vm.syncLine == .upToDate(state.lastUpdated, demo: false))

        vm.resolveLine()

        #expect(vm.showsSyncDetails && vm.scrollToIssue == 0)
    }

    @Test func tappingTheOfflineLineOpensSyncDetails() {
        let (env, state, _) = makeState(online: false)
        let vm = { let sync = SyncService(env: env); return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()
        #expect(vm.syncLine == .offline)
        vm.resolveLine()
        #expect(vm.showsSyncDetails && vm.scrollToIssue == 0)
    }

    /// With data on screen a failure changes nothing until it lasts: 3 in a row and older than 2 h.
    @Test func failureWithDataShowsNoCardUntilThreeFailuresAndTwoHours() async {
        let api = MockPlatformAPI()
        // Morning, so 2 h later is still the same day (a new day has no data of its own yet).
        let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now)!
        let (env, state, clock) = makeState(api: api, now: morning)
        let vm = { let sync = SyncService(env: env); return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()
        await state.refresh()
        let loaded = state.lastUpdated
        #expect(loaded != nil)
        api.failure = APIError.http(503, "")
        clock.advance(by: .seconds(6 * 60)) // today's 5 minutes are over: it asks again

        for _ in 0..<3 { await state.refresh() }

        #expect(state.resourceStates[.today]?.consecutiveFailures == 3)
        #expect(vm.status == nil)                                  // under 2 h: nothing changes on screen
        #expect(vm.syncLine == .upToDate(loaded, demo: false))
        #expect(vm.readiness != nil)                               // still on screen

        clock.advance(by: .seconds(2 * 3600))
        guard case .refreshIssue(let issue) = vm.status else {
            Issue.record("expected the card past 2 h, got \(String(describing: vm.status))")
            return
        }
        #expect(issue.resource == .today && issue.dataFrom == loaded && issue.failures == 3)
        // One "Try again" on screen, the card's; the line points to the card (last on Today).
        #expect(vm.syncLine == .issue(.today))
    }

    @Test func offlineShowsThePillAndRequestsNothing() async {
        let api = MockPlatformAPI()
        let (env, state, _) = makeState(api: api, online: false)
        let vm = { let sync = SyncService(env: env); return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()

        await vm.refresh()

        #expect(vm.isOffline)
        #expect(api.calls.isEmpty)
        #expect(vm.status == nil)
    }

    @Test func calibratingSaysHowManyNightsToGo() {
        let (env, state, _) = makeState()
        var detail = MockData.todayDetail
        detail.score = MockData.calibratingScore
        state.today = detail
        let vm = { let sync = SyncService(env: env); return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()
        #expect(vm.sentence == ReadinessCopy.sentence(score: MockData.calibratingScore))
        #expect(vm.readiness == nil)
    }

    @Test func failedHealthUploadPausesSync() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [
            HealthDelta(samples: [Sample(type: .heartRate, start: .now, end: .now, value: 60, unit: "bpm", source: "x")])
        ]])
        let api = MockPlatformAPI()
        api.failNext = APIError.http(500, "")
        let (env, state, _) = makeState(api: api, health: health)
        let sync = SyncService(env: env)
        let vm = TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())

        await sync.syncNow()

        guard case .syncPaused(let message, let details) = vm.status else {
            Issue.record("expected syncPaused, got \(String(describing: vm.status))")
            return
        }
        #expect(message.contains(APIError.http(500, "").localizedDescription))
        #expect(details == "HTTP 500")
    }

    @Test func tilesOpenTheirTabs() {
        let (env, state, _) = makeState()
        let vm = { let sync = SyncService(env: env); return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()
        vm.open(.strain)
        #expect(state.selectedTab == .strain)
    }
}

// MARK: - Today's in-between states

/// Which state wins, from the facts alone (`TodayStates`), then through the view model.
@Suite("Today: in-between states")
@MainActor
struct TodayStatesTests {
    private let morning = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date(timeIntervalSince1970: 1_792_400_000))!
    private var todayKey: String { DayFormat.string(from: morning) }

    private func facts(_ change: (inout TodaySyncFacts) -> Void = { _ in }) -> TodaySyncFacts {
        var f = TodaySyncFacts(now: morning)
        f.engine.backfillDone = true
        f.hasScoredDay = true
        f.lastUpdated = morning.addingTimeInterval(-120)
        change(&f)
        return f
    }

    private func score(readiness: Int?, calibrating: Bool = false, baselineDays: Int = 30,
                       state: ScoringState? = .scored, day: String? = nil) -> DailyScore {
        DailyScore(day: day ?? todayKey, readiness: readiness, state: readiness == nil ? .calibrating : .balanced,
                   baselineDays: baselineDays, calibrating: calibrating, computedAt: readiness == nil ? nil : morning,
                   scoringState: state)
    }

    private func status(_ state: ScoringState, day: String? = nil, expected: Int = 20) -> SyncStatus {
        SyncStatus(gate: nil, lastSyncAt: morning, lastSyncDevice: "iPhone", latest: [:],
                   today: TodayState(day: day ?? todayKey, state: state, scoredAt: nil, modelVersion: "2026.10.1"),
                   pendingDays: state == .pending ? [todayKey] : [], expectedWithinSec: expected, resyncRequestedAt: nil)
    }

    // MARK: hero

    @Test func theImportCardShowsUntilADayIsScored() {
        let importing = facts {
            $0.engine = TodayScenario.importingEngine(now: morning)
            $0.hasScoredDay = false
            $0.phase = .uploading
        }
        guard case .importing(let p) = TodayStates.hero(importing) else {
            Issue.record("expected the import card, got \(TodayStates.hero(importing))")
            return
        }
        #expect(p.step == .uploading)
        #expect(p.nights == 58 && p.heartRateReadings == 84_213 && p.workouts == 41)
        #expect(p.coveredDays == 61)
        #expect(p.oldestDay == DayFormat.date(from: DayFormat.string(from: DayFormat.shift(morning, days: -60))))
        #expect(TodayStates.importRow(importing) == nil) // the card says it all

        // The first score: the gauge's place goes back to the score, the import to a slim row.
        var scored = importing
        scored.hasScoredDay = true
        scored.today = score(readiness: 72)
        #expect(TodayStates.hero(scored) == .score)
        #expect(TodayStates.importRow(scored)?.coveredDays == 61)

        // The backfill done: no row.
        scored.engine.backfillDone = true
        #expect(TodayStates.importRow(scored) == nil)
    }

    @Test func noImportWithoutASyncingAccount() {
        let demo = facts { $0.syncs = false; $0.engine.backfillDone = false; $0.hasScoredDay = false }
        #expect(TodayStates.hero(demo) == .score)
        #expect(TodayStates.importRow(demo) == nil)
    }

    @Test func importStepsFollowThePipeline() {
        func step(_ phase: SyncPhase, pending: [String] = [], streams: Bool = true) -> ImportProgress.Step {
            TodayStates.progress(facts {
                $0.phase = phase
                $0.engine = streams ? TodayScenario.importingEngine(now: morning) : SyncEngineState()
                if !pending.isEmpty { $0.status = status(.pending) }
            }).step
        }
        #expect(step(.reading) == .reading)
        #expect(step(.uploading) == .uploading)
        #expect(step(.awaitingScores) == .scoring)
        #expect(step(.refreshing) == .scoring)
        #expect(step(.idle, pending: [todayKey]) == .scoring) // the platform is on it
        #expect(step(.idle) == .uploading) // between runs, mid-import
        #expect(step(.idle, streams: false) == .reading) // nothing sent yet
    }

    @Test func coverageCountsOnlyTheWindow() {
        var engine = SyncEngineState()
        var hr = SyncEngineState.StreamProgress()
        hr.days = [todayKey, DayFormat.string(from: DayFormat.shift(morning, days: -89)),
                   DayFormat.string(from: DayFormat.shift(morning, days: -90)), "2025-01-01"]
        engine.streams = ["heart_rate": hr]
        let p = TodayStates.progress(facts { $0.engine = engine })
        #expect(p.coveredDays == 2)
        #expect(p.fraction == 2.0 / 90)
        #expect(ImportProgress(step: .reading).coverageText == String(localized: "Starting with your last few days"))
    }

    @Test func aNightBeingScoredShowsThePendingGaugeWithTheDayBefore() {
        let yesterday = score(readiness: 78, day: DayFormat.string(from: DayFormat.shift(morning, days: -1)))
        let f = facts {
            $0.status = status(.pending, expected: 20)
            $0.previous = yesterday
        }
        #expect(TodayStates.hero(f) == .pending(PendingNight(waitingForSleep: false, expectedWithinSec: 20,
                                                              previousReadiness: 78,
                                                              previousDay: DayFormat.date(from: yesterday.day))))
        // No answer from GET /v1/me/sync yet: the upload's estimate.
        let fromUpload = facts { $0.today = score(readiness: nil, state: .pending); $0.expectedScoringSec = 45 }
        guard case .pending(let night) = TodayStates.hero(fromUpload) else { Issue.record("expected pending"); return }
        #expect(night.expectedWithinSec == 45 && !night.waitingForSleep)
    }

    @Test func noNightYetWaitsForSleepWithoutAnEstimate() {
        let f = facts { $0.status = status(.waitingForSleep) }
        guard case .pending(let night) = TodayStates.hero(f) else { Issue.record("expected pending"); return }
        #expect(night.waitingForSleep && night.expectedWithinSec == nil)
        #expect(night.title == String(localized: "Waiting for last night's sleep"))
    }

    @Test func aScoreThatLandedIsNeverPendingAgain() {
        // The silent push refreshed the day; GET /v1/me/sync wasn't asked again since.
        let f = facts { $0.today = score(readiness: 81); $0.status = status(.pending) }
        #expect(TodayStates.hero(f) == .score)
        // Yesterday's answer doesn't speak for today.
        let old = facts {
            $0.today = score(readiness: 81)
            $0.status = status(.pending, day: DayFormat.string(from: DayFormat.shift(morning, days: -1)))
        }
        #expect(TodayStates.todayState(old) == .scored)
    }

    @Test func pendingWinsOverCalibratingThenTheBaselineShows() {
        let calibrating = score(readiness: nil, calibrating: true, baselineDays: 4, state: .scored)
        let pending = facts { $0.today = calibrating; $0.status = status(.pending) }
        #expect(TodayStates.hero(pending).isPending)
        let scored = facts { $0.today = calibrating; $0.status = status(.scored) }
        #expect(TodayStates.hero(scored) == .calibrating(nights: 4))
    }

    // MARK: status line

    @Test func theLineSaysTheMostUrgentThingFirst() {
        var f = facts {
            $0.gate = .consent
            $0.online = false
            $0.waitingForUnlock = true
            $0.activity = .uploading(.quantity(.heartRate), records: 12_400)
            $0.phase = .awaitingScores
            $0.syncFailed = true
        }
        #expect(TodayStates.line(f) == .actionNeeded(.consent))
        f.gate = nil
        #expect(TodayStates.line(f) == .offline)
        f.online = true
        #expect(TodayStates.line(f) == .waitingForUnlock)
        f.waitingForUnlock = false
        #expect(TodayStates.line(f) == .uploading(records: 12_400))
        f.activity = .reading(.sleep)
        #expect(TodayStates.line(f) == .reading(.sleep))
        f.activity = nil
        #expect(TodayStates.line(f) == .scoring(night: false))
        f.phase = .refreshing
        #expect(TodayStates.line(f) == .updating)
        f.phase = .idle
        #expect(TodayStates.line(f) == .paused)
        f.syncFailed = false
        #expect(TodayStates.line(f) == .upToDate(morning.addingTimeInterval(-120), demo: false))
    }

    @Test func theLineSaysTheNightIsBeingScoredWhileThePlatformIsOnIt() {
        let f = facts { $0.status = status(.pending) }
        #expect(TodayStates.line(f) == .scoring(night: true))
        let waiting = facts { $0.status = status(.waitingForSleep) }
        #expect(TodayStates.line(waiting) == .upToDate(morning.addingTimeInterval(-120), demo: false))
    }

    @Test func theLineReadsLikeAFewWords() {
        let now = morning
        #expect(SyncLine.upToDate(now.addingTimeInterval(-20), demo: false).text(now: now)
                == String(localized: "Up to date · just now"))
        #expect(SyncLine.upToDate(nil, demo: true).text(now: now)
                == String(localized: "Demo data · ") + String(localized: "Not updated yet"))
        #expect(SyncLine.actionNeeded(.invite).text(now: now) == String(localized: "Action needed: enter your invite code"))
        #expect(SyncLine.actionNeeded(.aboutYou).text(now: now) == String(localized: "Action needed: agree to the privacy policy"))
        #expect(SyncLine.uploading(records: 12_400).isActive && !SyncLine.offline.isActive)
    }

    // MARK: watch hint

    @Test func aQuietSourceIsNamedAfterSixHoursInTheMorning() throws {
        let garmin = SourceFreshness(source: "Garmin Connect", bundleID: "com.garmin.connect.mobile",
                                     newest: morning.addingTimeInterval(-7 * 3_600))
        let hint = try #require(TodayStates.watchHint(facts { $0.freshness = [garmin] }))
        #expect(hint == WatchSyncHint(source: "Garmin Connect", since: garmin.newest, isApp: true))
        #expect(hint.text(now: morning).contains("Garmin Connect"))
        // Five hours: not yet.
        let recent = SourceFreshness(source: "Garmin Connect", bundleID: nil, newest: morning.addingTimeInterval(-5 * 3_600))
        #expect(TodayStates.watchHint(facts { $0.freshness = [recent] }) == nil)
    }

    @Test func duringTheDayTwelveHoursAndTheFreshestSourceCount() {
        let afternoon = morning.addingTimeInterval(7 * 3_600) // 14:30
        let watch = SourceFreshness(source: "Apple Watch", bundleID: "com.apple.health.1", newest: afternoon.addingTimeInterval(-11 * 3_600))
        let old = SourceFreshness(source: "Oura", bundleID: "com.ouraring.oura", newest: afternoon.addingTimeInterval(-40 * 3_600))
        var f = facts { $0.freshness = [old, watch] }
        f.now = afternoon
        #expect(TodayStates.watchHint(f) == nil) // the watch synced 11 h ago
        f.freshness = [old]
        #expect(TodayStates.watchHint(f)?.source == "Oura")
        // Not while importing, locked, or for an account that doesn't sync.
        #expect(TodayStates.watchHint(facts { $0.freshness = [old]; $0.engine.backfillDone = false }) == nil)
        #expect(TodayStates.watchHint(facts { $0.freshness = [old]; $0.waitingForUnlock = true }) == nil)
        #expect(TodayStates.watchHint(facts { $0.freshness = [old]; $0.syncs = false }) == nil)
    }

    @Test func pendingNightSaysWhenToExpectIt() {
        #expect(PendingNight(waitingForSleep: false, expectedWithinSec: 20).detail == String(localized: "Usually ready within 20 s."))
        #expect(PendingNight(waitingForSleep: false, expectedWithinSec: 150).detail == String(localized: "Usually ready within 3 min."))
        #expect(PendingNight(waitingForSleep: false).detail == String(localized: "Usually ready within a minute."))
    }

    @Test func dayMarkersFollowTheScoringState() {
        #expect(DayMarker.kind(for: nil) == nil)
        #expect(DayMarker.kind(for: score(readiness: 70)) == .scored)
        #expect(DayMarker.kind(for: score(readiness: 70, state: .pending)) == .pending)
        #expect(DayMarker.kind(for: score(readiness: nil, state: .waitingForSleep)) == .pending)
        #expect(DayMarker.kind(for: score(readiness: 70, state: nil)) == .scored) // a cache from before the field
        #expect(DayMarker.kind(for: score(readiness: nil, state: nil)) == nil)
    }

    // MARK: through the view model

    private func model(_ state: AppState) -> TodayViewModel {
        let sync = SyncService(env: state.env)
        return TodayViewModel(state: state, sync: sync,
                              coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: state.env.clock),
                              apiStatus: APIStatus())
    }

    @Test func aFreshAccountImportsAndTheSentenceSaysSo() {
        let env = AppEnvironment.test()
        let vm = model(AppState(env: env))
        #expect(vm.hero.isImporting) // signed in, nothing scored, no backfill yet
        #expect(vm.sentence == String(localized: "Your history is on its way."))
        #expect(vm.syncLine == .upToDate(nil, demo: false))
    }

    @Test func scenariosDriveTheStatesInDemoMode() {
        let state = AppState.preview(scenario: .pending)
        let vm = model(state)
        #expect(vm.hero.isPending)
        #expect(vm.rawNight?.source == "Garmin Connect")
        #expect(vm.readiness == nil && vm.sleepText == Fmt.placeholder) // nothing pretends to be today's
        #expect(vm.sentence == String(localized: "Yesterday's readiness, until last night is scored."))
        state.todayScenario = .importing
        #expect(vm.hero.isImporting && vm.showsImportPushPrompt)
        state.todayScenario = .calibrating
        #expect(vm.hero == .calibrating(nights: MockData.calibratingScore.baselineDays))
        state.todayScenario = .watch
        #expect(vm.watchHint?.source == "Garmin Connect")
    }

    @Test func healthFactsComeFromAppleHealth() async {
        let health = MockHealthStore()
        let now = Date()
        health.night = RawNight(asleepMin: 400, bedtime: now.addingTimeInterval(-30_000), wake: now.addingTimeInterval(-3_000),
                                source: "Garmin Connect")
        health.freshness = [SourceFreshness(source: "Garmin Connect", bundleID: nil, newest: now.addingTimeInterval(-3_000)),
                            SourceFreshness(source: "Old band", bundleID: nil, newest: now.addingTimeInterval(-30 * 86_400))]
        let (_, state, _) = makeState(health: health, now: now)
        let vm = model(state)
        await vm.loadHealthFacts()
        #expect(vm.lastNightRaw == health.night)
        #expect(vm.freshness.map(\.source) == ["Garmin Connect"]) // older than two weeks: not the watch in use
    }
}

// MARK: - Sync details

@Suite("Profile: sync details")
@MainActor
struct SyncDetailsTests {
    @Test func streamsComeInDrainOrderWithTheirLastAnswer() async {
        let health = MockHealthStore(streams: [.sleep, .quantity(.heartRate)], pages: [.quantity(.heartRate): [
            HealthDelta(samples: (0..<4).map { _ in Sample(type: .heartRate, start: .now, end: .now, value: 60, unit: "bpm", source: "x") })
        ]])
        let api = MockPlatformAPI()
        api.syncResponse = SyncResponse(samples: 3, sleep: 0, workouts: 0, daysTouched: [],
                                        ignored: SyncIgnored(samples: IgnoredCounts(duplicate: 1, outsideWindow: 0, unknownType: 0),
                                                             sleep: .none, workouts: .none))
        let (_, state, _) = makeState(api: api, health: health)
        let sync = SyncService(env: state.env)
        let model = SyncDetailsModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        await sync.syncNow()

        #expect(model.streams.map { $0.id } == ["sleep", "heart_rate"])
        // Sleep had nothing: drained (backfilled), nothing sent, no answer to show.
        #expect(model.streams[0].progress?.sent == 0 && model.streams[0].progress?.backfilled == true)
        #expect(model.streams[0].lastPageText == nil && model.streams[0].newestText == String(localized: "Nothing sent yet"))
        let hr = model.streams[1]
        #expect(hr.progress?.sent == 4)
        #expect(SyncDetailsModel.StreamRow(id: "hrv_sdnn", name: "HRV", progress: nil).title == "HRV")
        #expect(SyncDetailsModel.StreamRow(id: "x", name: "resting heart rate", progress: nil).title == "Resting heart rate")
        #expect(hr.lastPageText == String(localized: "\(3.formatted()) accepted") + " · " + String(localized: "\(1.formatted()) duplicates"))
        #expect(model.phaseText == String(localized: "Up to date"))
        #expect(model.backlogText == String(localized: "None"))
    }

    @Test func diagnosticsHoldCountsAndIDsButNoHealthValues() async {
        let status = APIStatus()
        status.served(.init(date: .now, method: "POST", path: "/v1/sync", status: 200, requestID: "rid-1"))
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [
            HealthDelta(samples: [Sample(type: .heartRate, start: .now, end: .now, value: 61.5, unit: "bpm", source: "x")])
        ]])
        let (_, state, _) = makeState(health: health)
        let sync = SyncService(env: state.env)
        let model = SyncDetailsModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: status)
        await sync.syncNow()
        await model.loadQueue()

        let text = model.diagnostics
        #expect(text.contains("rid-1") && text.contains("heart_rate: 1 rec"))
        #expect(text.contains(state.env.settings.deviceId.uuidString.lowercased()))
        #expect(!text.contains("61.5")) // a value never leaves through diagnostics
        #expect(model.queueText == String(localized: "Idle"))
    }

    @Test func syncingTheLastThreeDaysAgainRunsThePipeline() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [
            HealthDelta(samples: [Sample(type: .heartRate, start: .now, end: .now, value: 60, unit: "bpm", source: "x")])
        ]], recent: [.quantity(.heartRate): [
            HealthDelta(samples: [Sample(type: .heartRate, start: .now, end: .now, value: 60, unit: "bpm", source: "x")])
        ]])
        let api = MockPlatformAPI()
        // Nothing to score: the coordinator doesn't wait on the test clock.
        api.syncResponse = SyncResponse(samples: 1, sleep: 0, workouts: 0, daysTouched: [])
        let (_, state, _) = makeState(api: api, health: health)
        let sync = SyncService(env: state.env)
        let model = SyncDetailsModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        await sync.syncNow()
        let before = health.recentReads

        await model.resendRecent()

        #expect(health.recentReads == before + 1)
        #expect(!sync.engineState.recentRequested)
    }
}

// MARK: - Strain

@Suite("Strain view model")
@MainActor
struct StrainViewModelTests {
    @Test func startsOnTodayWithAWeekStrip() {
        let (_, state, _) = makeState()
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        #expect(vm.isToday)
        #expect(vm.title == String(localized: "Today"))
        #expect(vm.week.count == 7)
        #expect(vm.week.last?.isSelected == true)
        #expect(vm.week.filter(\.isSelected).count == 1)
    }

    @Test func pastDayLoadsItsDetail() async {
        let api = MockPlatformAPI()
        let (_, state, _) = makeState(api: api)
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        vm.select(DayFormat.shift(.now, days: -1))

        await vm.load()

        #expect(!vm.isToday)
        #expect(vm.title == String(localized: "Yesterday"))
        #expect(vm.detail?.score.day == day(-1))
        #expect(api.count("day") == 1)
        #expect(vm.week[5].isSelected)
    }

    @Test func deltaAgainstTheSevenDaysBefore() {
        let (_, state, _) = makeState()
        state.history = (1...7).map { DailyScore(day: day(-$0), strain: 10) } + [DailyScore(day: day(0), strain: 13)]
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        #expect(vm.strain == 13)
        #expect(vm.strainDelta == MetricDelta(current: 13, reference: 10))
        #expect(vm.week.map(\.strain) == [10, 10, 10, 10, 10, 10, 13])
    }

    @Test func failureWithoutCacheShowsTheError() async {
        let api = MockPlatformAPI()
        api.failure = APIError.transport(URLError(.notConnectedToInternet))
        let (_, state, _) = makeState(api: api)
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))

        await vm.load()

        #expect(vm.error != nil)
        #expect(vm.activities.isEmpty)
    }

    @Test func offlineKeepsTheCachedDay() async throws {
        let api = MockPlatformAPI()
        let (_, state, _) = makeState(api: api)
        _ = try await state.dayDetail(for: .now) // cached once
        api.failure = APIError.transport(URLError(.notConnectedToInternet))
        let vm = StrainViewModel(state: state, store: TrainStore(inMemory: true))

        await vm.load()

        #expect(vm.error == nil)
        #expect(vm.detail != nil)
    }
}

// MARK: - Sleep

@Suite("Sleep view model")
@MainActor
struct SleepViewModelTests {
    @Test func stepsBackButNotIntoTheFuture() async {
        let (_, state, _) = makeState()
        let vm = SleepViewModel(state: state)
        vm.mode = .day
        #expect(vm.subtitle == String(localized: "Last night"))
        #expect(!vm.canStepForward)

        await vm.step(by: -1)
        #expect(vm.subtitle == String(localized: "Yesterday"))
        #expect(vm.canStepForward)
        #expect(vm.sleep != nil)

        await vm.step(by: 1)
        await vm.step(by: 1) // refused: tomorrow
        #expect(vm.isToday)
    }

    @Test func weekModeLoadsTheRange() async {
        let (_, state, _) = makeState()
        let vm = SleepViewModel(state: state)
        vm.mode = .week
        await vm.load()
        #expect(vm.range?.range == SleepRangeKind.week.rawValue)
        #expect(vm.subtitle == String(localized: "Last 7 nights"))
        #expect(!vm.canStepBack)
    }

    @Test func failureWithoutCacheShowsTheError() async {
        let api = MockPlatformAPI()
        api.failure = APIError.http(500, "")
        let (_, state, _) = makeState(api: api)
        let vm = SleepViewModel(state: state)
        vm.mode = .day
        await vm.load()
        #expect(vm.error != nil)
    }

    @Test func nightSummaryComparesWithTheNeed() throws {
        let sleep = try #require(MockData.todayDetail.sleep)
        let score = DailyScore(day: day(0), sleepNeedMin: 500, sleepActualMin: 450, sleepDebtMin: 60)
        let summary = SleepNightSummary(sleep: sleep, score: score)
        #expect(summary.actualOfNeed == String(localized: "90% of need"))
        #expect(summary.debtIsHigh)
        #expect(SleepNightSummary(sleep: sleep, score: DailyScore(day: day(0), sleepDebtMin: 0)).debt
            == String(localized: "None"))
    }

    @Test func rangeSummaryBuildsBarsAndRegularity() {
        let summary = SleepRangeSummary(range: MockData.sleepRange(.week))
        #expect(!summary.bars.isEmpty)
        #expect(summary.window == .week)
        #expect(summary.tallestNight > 0)
        #expect(summary.regularity != .unknown)
    }
}

// MARK: - Insights

@Suite("Insights view model")
@MainActor
struct InsightsViewModelTests {
    @Test func loadsEveryMetricAndBandsOnlyPersonalRanges() async {
        let (_, state, _) = makeState()
        let vm = InsightsViewModel(state: state)
        vm.range = .week

        await vm.load()

        #expect(vm.series.count == TrendMetric.allCases.count)
        #expect(vm.monthly[.hrv]?.range == TrendRange.month.rawValue)
        #expect(vm.band(for: .hrv) != nil)
        #expect(vm.band(for: .strain) == nil)
    }

    @Test func emptyMessageDependsOnWhy() async {
        let (_, state, _) = makeState()
        let vm = InsightsViewModel(state: state)
        #expect(vm.emptyMessage == String(localized: "Nothing stands out today. Insights appear when your data shifts."))
        state.insights = MockData.insights
        #expect(vm.emptyMessage == nil)
        for i in MockData.insights { vm.dismiss(i) }
        #expect(vm.emptyMessage == String(localized: "All caught up for today."))
    }

    @Test func noDataSourceLoadsNothing() async {
        let api = MockPlatformAPI()
        let env = AppEnvironment.test(api: api, auth: .preview(signedIn: false))
        let state = AppState(env: env)
        let vm = InsightsViewModel(state: state)
        await vm.load()
        #expect(api.calls.isEmpty)
    }
}

// MARK: - Profile

@Suite("Profile view model")
@MainActor
struct ProfileViewModelTests {
    @Test func accountFallsBackFromNameToEmail() {
        let (env, state, _) = makeState()
        let vm = { let sync = SyncService(env: env); return ProfileViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()
        state.user = User(id: UUID(), name: "", email: "a@b.c", provider: "email", tz: TimeZone.current.identifier,
                          maxHr: 185, sleepBaseMin: 450)
        #expect(vm.accountTitle == "a@b.c")
        #expect(vm.accountSubtitle == nil)
        #expect(vm.canChangePassword)
        #expect(vm.providerBadge?.systemImage == "envelope.fill")
        #expect(vm.timezoneDetail == nil)
        #expect(vm.bodySettings.maxHR == 185 && vm.bodySettings.sleepBase == 450)
    }

    @Test func rescoringSendsNoSettings() async {
        let api = MockPlatformAPI()
        let (env, state, clock) = makeState(api: api)
        let vm = { let sync = SyncService(env: env); return ProfileViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()
        let run = Task { await vm.bodySettings.rescore() }
        #expect(await eventually { clock.pendingSleeps == 1 })
        #expect(api.count("recompute") == 1 && api.count("patchMe") == 0) // settings saved when they changed
        clock.advance(by: SyncService.rescoreDelay)
        await run.value
        #expect(!vm.bodySettings.rescoring)
    }

    @Test func failedRescoreSaysWhy() async {
        let api = MockPlatformAPI()
        let (env, state, _) = makeState(api: api)
        let vm = { let sync = SyncService(env: env); return ProfileViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()
        api.failure = APIError.http(429, "")
        await vm.bodySettings.rescore()
        #expect(vm.bodySettings.rescoreStatus == APIError.http(429, "").localizedDescription)
    }

    @Test func healthStatusComesFromTheStore() async {
        let health = MockHealthStore()
        health.access = .notAsked
        let (env, state, _) = makeState(health: health)
        let vm = { let sync = SyncService(env: env); return ProfileViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus()) }()
        await vm.refreshHealthStatus()
        #expect(vm.canAskForHealth && vm.healthNeedsAttention)
        await vm.requestHealthAccess()
        #expect(health.authorizationRequests == 1)
        #expect(vm.healthStatusText == String(localized: "Requested"))
    }
}

// MARK: - Train

@Suite("Train: start from anywhere", .serialized)
@MainActor
struct TrainQuickStartTests {
    private func coordinator(_ api: MockPlatformAPI = MockPlatformAPI()) -> (TrainCoordinator, TrainLibrary, TrainStore) {
        let store = TrainStore(inMemory: true)
        let sync = TrainSyncService(store: store, remote: { api }, debounce: .milliseconds(30), monitorsNetwork: false)
        let library = TrainLibrary(store: store, remote: { api }, restore: false)
        return (TrainCoordinator(sync: sync, library: library, liveActivities: false), library, store)
    }

    /// The launcher's static state, put back after each test.
    private func withLauncher(account: Bool, restoring: Bool = false, _ body: () async throws -> Void) async rethrows {
        let saved = (WorkoutLauncher.hasAccount, WorkoutLauncher.isRestoring, WorkoutLauncher.tabsVisible)
        defer {
            (WorkoutLauncher.hasAccount, WorkoutLauncher.isRestoring) = (saved.0, saved.1)
            if saved.2 { Task { await WorkoutLauncher.tabsAppeared() } } else { WorkoutLauncher.tabsDisappeared() }
            WorkoutLauncher.discardPending()
        }
        WorkoutLauncher.hasAccount = { account }
        WorkoutLauncher.isRestoring = { restoring }
        WorkoutLauncher.tabsDisappeared()
        WorkoutLauncher.discardPending()
        try await body()
    }

    @Test func aRunningWorkoutIsResumedNeverASecondOneStarted() async throws {
        let (c, _, store) = coordinator()
        #expect(await c.quickStart(.empty) == .empty)
        let first = try #require(store.activeSession())
        for kind in TrainCoordinator.QuickStart.allCases {
            #expect(await c.quickStart(kind) == .resumed)
        }
        #expect(store.activeSession()?.id == first.id && c.live?.session.id == first.id)
    }

    @Test func withoutAPlanAutoStartsAnEmptyWorkout() async {
        let (c, library, store) = coordinator()
        #expect(library.today == nil)
        #expect(await c.quickStart(.auto) == .empty)
        #expect(store.activeSession()?.orderedExercises.isEmpty == true)
    }

    @Test func withAPlanAutoStartsTodaysDay() async throws {
        let (c, library, store) = coordinator()
        await library.refresh()
        let today = try #require(library.today)
        #expect(await c.quickStart(.auto) == .plan)
        #expect(store.activeSession()?.planDayId == today.day.id)
    }

    @Test func aPlanDayCachedOnAnotherDayIsAskedForAgain() async throws {
        let api = MockPlatformAPI()
        let (c, library, store) = coordinator(api)
        await library.refresh()
        let today = try #require(library.today)
        store.saveDocument(today, key: "train.today", at: .now.addingTimeInterval(-86_400)) // yesterday's copy
        #expect(library.todayIsStale())
        #expect(await c.quickStart(.auto) == .plan)
        #expect(!library.todayIsStale())

        // Offline: no plan day from yesterday; an empty workout instead.
        let (offline, offlineLibrary, offlineStore) = coordinator(api)
        await offlineLibrary.refresh()
        offlineStore.saveDocument(try #require(offlineLibrary.today), key: "train.today", at: .now.addingTimeInterval(-86_400))
        api.failure = APIError.transport(URLError(.notConnectedToInternet))
        #expect(await offline.quickStart(.auto) == .empty)
    }

    @Test func repeatLastStartsTheLastWorkoutAgain() async throws {
        let (c, library, store) = coordinator()
        let last = try #require(await library.lastSession())
        #expect(await c.quickStart(.repeatLast) == .repeated)
        #expect(store.activeSession()?.title == last.title)
    }

    @Test func aStartWaitsForTheTabs() async {
        // Onboarding (or the Health explanation) is showing: the start waits, then runs.
        let (c, _, store) = coordinator()
        await withLauncher(account: true) {
            await WorkoutLauncher.start(.empty, coordinator: c)
            #expect(store.activeSession() == nil)
            await WorkoutLauncher.tabsAppeared(coordinator: c)
            #expect(store.activeSession() != nil)
        }
        // A cold launch from the home screen: the session is being restored.
        let (cold, _, coldStore) = coordinator()
        await withLauncher(account: false, restoring: true) {
            await WorkoutLauncher.start(.empty, coordinator: cold)
            WorkoutLauncher.hasAccount = { true } // restored
            await WorkoutLauncher.tabsAppeared(coordinator: cold)
            #expect(coldStore.activeSession() != nil)
        }
    }

    @Test func signingOutDropsAWaitingStart() async {
        let (c, _, store) = coordinator()
        await withLauncher(account: true) {
            await WorkoutLauncher.start(.empty, coordinator: c)
            WorkoutLauncher.discardPending() // signed out, or another account
            await WorkoutLauncher.tabsAppeared(coordinator: c)
            #expect(store.activeSession() == nil)
        }
        // Signed out and not restoring: nothing starts, nothing waits.
        let (other, _, otherStore) = coordinator()
        await withLauncher(account: false) {
            await WorkoutLauncher.start(.empty, coordinator: other)
            WorkoutLauncher.hasAccount = { true }
            await WorkoutLauncher.tabsAppeared(coordinator: other)
            #expect(otherStore.activeSession() == nil)
        }
    }

    @Test func aLinkOnlyResumes() async {
        let (c, _, store) = coordinator()
        await withLauncher(account: true) {
            await WorkoutLauncher.tabsAppeared(coordinator: c)
            #expect(!c.handle(URL(string: "ryft://train/start?kind=empty")!)) // no link starts a workout
            #expect(c.handle(URL(string: "ryft://train/session")!))
            #expect(store.activeSession() == nil && c.live == nil)
            #expect(!WorkoutLauncher.resume(coordinator: c)) // nothing to resume
            await c.quickStart(.empty)
            c.close()
            #expect(WorkoutLauncher.resume(coordinator: c) && c.live != nil)
        }
    }

    @Test func anAccountChangeClosesThePreviousWorkout() async {
        let (c, _, _) = coordinator()
        await c.quickStart(.empty)
        #expect(c.live != nil)
        c.accountChanged()
        #expect(c.live == nil && c.summary == nil)
    }

    @Test func intentsAndQuickActionsMapToTheSameStarts() async {
        #expect(WorkoutChoice.today.quickStart == .auto)
        #expect(WorkoutChoice.empty.quickStart == .empty)
        #expect(WorkoutChoice.repeatLast.quickStart == .repeatLast)
        #expect(StartStrengthWorkoutIntent.openAppWhenRun && ResumeWorkoutIntent.openAppWhenRun && OpenWorkoutIntent.openAppWhenRun)
        await withLauncher(account: false) {
            #expect(WorkoutLauncher.handle(UIApplicationShortcutItem(type: WorkoutLauncher.startType, localizedTitle: "Start")))
            #expect(WorkoutLauncher.handle(UIApplicationShortcutItem(type: WorkoutLauncher.resumeType, localizedTitle: "Resume")))
            #expect(!WorkoutLauncher.handle(UIApplicationShortcutItem(type: "other", localizedTitle: "Other")))
            await Task.yield()
        }
    }

    @Test func theNextSetSaysWhatToLift() {
        #expect(SessionController.target(reps: 5, kg: 80) == "5 × \(Fmt.kg(80))")
        #expect(SessionController.target(reps: 8, kg: nil) == String(localized: "8 reps"))
        #expect(SessionController.target(reps: nil, kg: 20) == Fmt.kg(20))
        #expect(SessionController.target(reps: nil, kg: nil) == nil)
    }

    @Test func anActivityFromAnOlderVersionStillDecodesAndIsNeverReused() throws {
        let state = try JSONDecoder().decode(RestTimerAttributes.ContentState.self, from: Data(
            #"{"endsAt": 800000000, "totalSec": 90, "exercise": "Bench press", "next": "Bench press · set 2 of 3", "finished": false}"#.utf8))
        #expect(state.resting) // it was a rest
        let attributes = try JSONDecoder().decode(RestTimerAttributes.self, from: Data(#"{"sessionTitle": "Upper A"}"#.utf8))
        #expect(attributes.sessionID == nil) // matches no workout: ended, not taken over
    }
}

@Suite("Train view models")
@MainActor
struct TrainViewModelTests {
    private func library(_ api: MockPlatformAPI = MockPlatformAPI()) -> TrainLibrary {
        TrainLibrary(store: TrainStore(inMemory: true), remote: { api }, restore: false)
    }

    @Test func historyGroupsByWeekNewestFirst() async {
        let vm = TrainHistoryViewModel(library: library())
        #expect(!vm.loaded)
        await vm.load()
        #expect(vm.loaded)
        let weeks = vm.weeks
        #expect(!weeks.isEmpty)
        #expect(zip(weeks, weeks.dropFirst()).allSatisfy { $0.start > $1.start })
        #expect(weeks.flatMap(\.sessions).count == vm.sessions.count)
    }

    @Test func exerciseDetailKeepsTheLast90Days() async {
        let clock = TestClock(now: .now)
        let vm = ExerciseDetailViewModel(exerciseID: MockTrain.bench.id, library: library(), clock: clock)
        #expect(vm.emptyChartText == String(localized: "Loading…"))
        await vm.load()
        #expect(vm.loaded)
        let from = DayFormat.string(from: DayFormat.shift(clock.now(), days: -89))
        #expect(vm.points.allSatisfy { $0.day >= from })
        #expect(vm.hasTrend == (vm.points.count >= 2))
        #expect(vm.recentRows.count <= 10)
        // Moving the clock 200 days on empties the window.
        clock.advance(by: .seconds(200 * 86_400))
        #expect(vm.points.isEmpty && vm.change == nil)
    }

    @Test func planDetailFiltersByWeek() async {
        let lib = library()
        let vm = PlanDetailViewModel(planID: MockTrain.weightlifting.id, library: lib)
        await vm.load()
        #expect(vm.plan?.id == MockTrain.weightlifting.id)
        if vm.weeks.count > 1 {
            vm.week = vm.weeks[1]
            #expect(vm.shownDays.allSatisfy { $0.week == nil || $0.week == vm.weeks[1] })
        }
        #expect(vm.shownDays == vm.shownDays.sorted { $0.dayIndex < $1.dayIndex })
    }

    @Test func planBuilderValidatesOnSaveAndEditsDays() async throws {
        let vm = PlanBuilderViewModel(plan: .blank(), library: library())
        #expect(vm.isNew && !vm.hasChanges)
        #expect(vm.shownIssues.isEmpty) // not before the first Save

        #expect(await vm.save() == false)
        #expect(!vm.shownIssues.isEmpty)

        vm.addDay()
        #expect(vm.plan.days.map(\.name).last == String(localized: "Day B"))
        let dayID = try #require(vm.plan.days.first?.id)
        vm.add(MockTrain.bench, toDay: dayID)
        vm.add(MockTrain.squat, toDay: dayID)
        vm.link(dayID: dayID, 0, true)
        #expect(vm.isLinked(dayID: dayID, 0))
        vm.move(dayID: dayID, 0, by: 1)
        #expect(vm.plan.days[0].exercises.map(\.position) == [0, 1])
        vm.remove(dayID: dayID, 0)
        #expect(vm.plan.days[0].exercises.count == 1)
        #expect(vm.plan.days[0].exercises[0].supersetGroup == nil) // a superset of one isn't one
        vm.removeDay(vm.plan.days[1].id)
        #expect(vm.plan.days.count == 1)
    }

    @Test func customExerciseSlug() {
        var draft = CustomExerciseDraft(name: "  Landmine Press (1-arm) ")
        #expect(draft.slug == "landmine-press-1-arm")
        #expect(draft.exercise.name == "Landmine Press (1-arm)")
        draft.loadType = .bodyweight
        #expect(draft.exercise.bodyweightFactor == 1)
        #expect(!CustomExerciseDraft(name: "   ").canSave)
    }
}

// MARK: - Onboarding (invite, consent, about you)

@MainActor
private final class SyncStarts {
    var runs = 0
}

/// A coordinator over the test graph; `introDone` stands in for `Settings.healthIntroDone`
/// (first run: false).
@MainActor
private func onboarding(_ api: MockPlatformAPI = MockPlatformAPI(), introDone: Bool = false,
                        status: APIStatus? = nil) -> (OnboardingCoordinator, AppState, SyncStarts) {
    let (_, state, _) = makeState(api: api)
    let starts = SyncStarts()
    let model = OnboardingCoordinator(state: state, apiStatus: status ?? APIStatus()) {
        starts.runs += 1
    }
    if introDone { model.reachedTabs() }
    return (model, state, starts)
}

@Suite("Onboarding: what's missing")
struct OnboardingDecisionTests {
    typealias Facts = OnboardingCoordinator.Facts

    /// Every case names the facts and the steps they must lead to.
    @Test(arguments: [
        // The beta gate off (production today): a new account consents and says its age.
        (Facts(userKnown: true, betaAccess: false, policyVersion: "v2"), [OnboardingCoordinator.Step.consent, .aboutYou]),
        // The gate on (or warning): the code comes first.
        (Facts(userKnown: true, betaAccess: false, policyVersion: "v2", serverGate: .inviteRequired),
         [.invite, .consent, .aboutYou]),
        (Facts(userKnown: true, betaAccess: false, policyVersion: "v2", reported: [.inviteRequired]),
         [.invite, .consent, .aboutYou]),
        // Access already: a stale header doesn't ask again.
        (Facts(userKnown: true, betaAccess: true, consentVersion: "v2", policyVersion: "v2",
               reported: [.inviteRequired], birthYear: 1990), []),
        // The policy changed since the consent.
        (Facts(userKnown: true, consentVersion: "v1", policyVersion: "v2", birthYear: 1990), [.consent]),
        // Consent current, birth year known: nothing.
        (Facts(userKnown: true, consentVersion: "v2", policyVersion: "v2", birthYear: 1990), []),
        // The platform says consent is missing although this phone thinks it isn't: the platform wins.
        (Facts(userKnown: true, consentVersion: "v2", policyVersion: "v2", serverGate: .consentRequired,
               birthYear: 1990), [.consent]),
        // No config (offline): any consent counts until the platform says otherwise.
        (Facts(userKnown: true, consentVersion: "v1", birthYear: 1990), []),
        (Facts(userKnown: true, birthYear: 1990), [.consent]),
        // Nothing known (offline, nothing cached): no step, unless a refusal said so.
        (Facts(), []),
        (Facts(reported: [.consentRequired]), [.consent]),
        // "About you" answered or skipped once.
        (Facts(userKnown: true, consentVersion: "v2", policyVersion: "v2", aboutYouDone: true), []),
    ])
    func missing(facts: Facts, expected: [OnboardingCoordinator.Step]) {
        #expect(OnboardingCoordinator.missing(facts) == expected)
    }
}

@Suite("Onboarding coordinator")
@MainActor
struct OnboardingCoordinatorTests {
    @Test func aNewAccountConsentsThenSyncsThenSaysItsAge() async {
        let api = MockPlatformAPI()
        api.betaAccess = false
        api.accountConsent = nil
        let (model, state, starts) = onboarding(api)
        #expect(model.holdsFirstRun) // splash until the platform answered

        await model.check()

        #expect(!model.holdsFirstRun)
        #expect(model.flowStep == .consent) // the gate is off: no invite step
        #expect(model.syncGate == .consentRequired)
        #expect(state.user != nil && api.count("syncStatus") == 1 && api.count("config") == 1)

        #expect(await model.agree())
        #expect(api.consentPosts == [MockData.policyVersion])
        #expect(starts.runs == 1) // the first sync starts right away
        #expect(model.syncGate == nil)
        #expect(model.flowStep == .aboutYou)

        #expect(await model.saveAboutYou(birthYear: 1990))
        #expect(state.user?.birthYear == 1990 && state.user?.maxHrSource == .estimated)
        #expect(model.flowStep == .aboutYou) // shows the estimate until Continue
        model.finishAboutYou()
        #expect(model.flowStep == nil)
    }

    @Test func nothingSyncsBeforeConsent() async throws {
        let api = MockPlatformAPI()
        api.accountConsent = nil
        let health = MockHealthStore(pages: [.quantity(.heartRate): [HealthDelta(samples: [
            Sample(type: .heartRate, start: .now, end: .now, value: 60, unit: "bpm", source: "Watch")])]])
        let env = AppEnvironment.test(api: api, health: health)
        let state = AppState(env: env)
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        model.reachedTabs()
        let sync = SyncService(env: env)
        sync.gate = { model.syncGate }
        await model.check()

        #expect(try await sync.upload() == [])
        #expect(sync.pausedFor == .consentRequired && sync.lastError == nil)
        #expect(api.count("sync") == 0 && health.committed.isEmpty)

        _ = await model.agree()
        _ = try? await sync.upload()
        #expect(api.count("sync") == 1 && sync.pausedFor == nil)
    }

    @Test func aRefusalAtTheGatePausesTheSyncAndKeepsTheAnchor() async {
        let api = MockPlatformAPI()
        api.accountConsent = nil
        api.enforcesConsent = true
        let health = MockHealthStore(pages: [.quantity(.heartRate): [HealthDelta(samples: [
            Sample(type: .heartRate, start: .now, end: .now, value: 60, unit: "bpm", source: "Watch")])]])
        let sync = SyncService(env: .test(api: api, health: health)) // no gate wired: the platform refuses

        let touched = try? await sync.upload()

        #expect(touched == [])
        #expect(sync.pausedFor == .consentRequired && sync.lastError == nil && sync.phase == .idle)
        #expect(health.committed.isEmpty) // the page goes again once consent is given
    }

    @Test func afterTheFirstRunAGateIsASheetThatCanWaitAndComesBack() async {
        let api = MockPlatformAPI()
        api.accountConsent = Consent(policyVersion: "2026-01-01", grantedAt: .now) // an older policy
        let (model, _, _) = onboarding(api, introDone: true)
        await model.check()

        #expect(model.flowStep == nil)
        #expect(model.sheetStep == .consent)
        #expect(model.earlierConsent?.policyVersion == "2026-01-01")
        model.sheetStep = nil // swiped away
        #expect(model.sheetStep == nil && model.pendingGate == .consent && model.syncGate == .consentRequired)
        model.show(.consent) // Today's "Review"
        #expect(model.sheetStep == .consent)
    }

    @Test func aGateReportedMidSessionAppearsOnTheNextCheck() async {
        let status = APIStatus()
        let (model, _, _) = onboarding(introDone: true, status: status)
        await model.check()
        #expect(model.sheetStep == nil)

        status.observe([.consentRequired], enforced: true) // a sync answered 403 consent_required
        #expect(model.sheetStep == .consent)
        await model.check(force: true) // the platform: consent is current after all
        #expect(model.sheetStep == nil && status.gates.isEmpty)
    }

    @Test func inviteCodes() async {
        let api = MockPlatformAPI()
        api.betaAccess = false
        api.inviteGateOn = true
        let status = APIStatus()
        let (model, _, _) = onboarding(api, status: status)
        status.observe([.inviteRequired], enforced: true)
        await model.check()
        #expect(model.flowStep == .invite)
        #expect(!model.canDefer(.invite)) // enforced: nothing works without it
        #expect(model.syncGate == .inviteRequired)

        model.inviteCode = "RYFT-0000-0000"
        #expect(await !model.redeemInvite())
        #expect(model.errorMessage == String(localized: "This code doesn't work. Ask the person who invited you for a new one."))

        model.inviteCode = " ryft-7k3m qx9p "
        #expect(await model.redeemInvite())
        #expect(!status.inviteBlocked && model.inviteCode.isEmpty && model.errorMessage == nil)
        #expect(model.flowStep == .aboutYou) // consented already (the mock's default)
    }

    @Test func aWarningInviteGateCanWait() async {
        let api = MockPlatformAPI()
        api.betaAccess = false
        api.inviteGateOn = true
        let (model, _, _) = onboarding(api)
        await model.check()
        #expect(model.flowStep == .invite && model.canDefer(.invite) && model.syncGate == nil)
        model.later(.invite)
        #expect(model.flowStep == .aboutYou)
    }

    @Test func anOutdatedPolicyAsksToReadAgain() async {
        let api = MockPlatformAPI()
        api.accountConsent = nil
        let (model, _, starts) = onboarding(api)
        await model.check()
        api.remoteConfig = RemoteConfig(flags: [:], evaluatedAt: .now, ttlSec: 21_600,
                                        privacyPolicyVersion: "2026-11-01", privacyPolicyUrl: nil)
        #expect(await !model.agree()) // the screen showed 2026-10-20
        #expect(model.errorMessage == String(localized: "The privacy policy was just updated. Read the new version, then agree again."))
        #expect(starts.runs == 0)
        #expect(await eventually { model.policyVersion == "2026-11-01" })
    }

    @Test func theAccountHintShowsOncePerAccount() async {
        let api = MockPlatformAPI()
        api.accountHint = AccountHint(kind: "other_account_on_device", otherProvider: "email", otherLastSync: .now)
        let (model, _, _) = onboarding(api, introDone: true)
        await model.check()
        #expect(model.accountHint?.otherProvider == "email")
        #expect(model.sheetStep == nil) // the hint first
        model.keepThisAccount()
        #expect(model.accountHint == nil)
    }

    @Test func useTheOtherAccountSignsOut() async {
        let api = MockPlatformAPI()
        api.accountHint = AccountHint(kind: "other_account_on_device", otherProvider: "email", otherLastSync: .now)
        let (model, state, _) = onboarding(api)
        await model.check()
        await model.useOtherAccount()
        #expect(!state.env.auth.isSignedIn)
    }

    @Test func anotherAccountStartsFromItsOwnFacts() async {
        let status = APIStatus()
        let api = MockPlatformAPI()
        api.accountConsent = nil
        let (model, _, _) = onboarding(api, introDone: true, status: status)
        await model.check()
        model.later(.consent)
        status.observe([.inviteRequired], enforced: true)

        model.switchAccount("someone-else")
        #expect(status.gates.isEmpty && !status.inviteBlocked)
        status.observe([.consentRequired], enforced: true)
        model.switchAccount(nil) // signed out

        #expect(status.gates.isEmpty && !status.inviteBlocked)
        #expect(model.deferred.isEmpty && model.phase == .idle && model.syncStatus == nil)
    }

    @Test func withdrawingStopsSyncWithoutAsking() async {
        let (model, _, _) = onboarding(introDone: true)
        await model.check()
        #expect(model.syncGate == nil)
        #expect(await model.withdrawConsent())
        #expect(model.syncGate == .consentRequired)
        #expect(model.sheetStep == nil) // asked again only from Profile or Today
        #expect(model.pendingGate == .consent)
    }

    @Test func demoModeHasNoGates() async {
        let demo = OnboardingCoordinator(state: AppState.preview(), apiStatus: APIStatus()) {}
        await demo.check()
        #expect(demo.missing.isEmpty && demo.syncGate == nil && !demo.holdsFirstRun)
    }

    @Test func todaySaysWhatsNeededAndOpensTheStep() async {
        let api = MockPlatformAPI()
        api.accountConsent = nil
        let (env, state, _) = makeState(api: api)
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        model.reachedTabs()
        await model.check()
        model.later(.consent)
        let sync = SyncService(env: env)
        let today = TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync),
                                   onboarding: model, apiStatus: APIStatus())

        guard case .actionNeeded(let step, _, _)? = today.status else {
            Issue.record("expected an action, got \(String(describing: today.status))")
            return
        }
        #expect(step == .consent)
        today.resolve(step)
        #expect(model.sheetStep == .consent)
    }
}

@Suite("Profile: privacy and about you")
@MainActor
struct ProfilePrivacyTests {
    private func profile(_ api: MockPlatformAPI = MockPlatformAPI())
        -> (ProfileViewModel, OnboardingCoordinator, AppState) {
        let (env, state, _) = makeState(api: api)
        let onboarding = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        onboarding.reachedTabs()
        let sync = SyncService(env: env)
        let vm = ProfileViewModel(state: state, sync: sync, coordinator: coordinator(state, sync),
                                  onboarding: onboarding, apiStatus: APIStatus())
        return (vm, onboarding, state)
    }

    @Test func consentGivenThenWithdrawn() async {
        let (vm, onboarding, _) = profile()
        await onboarding.check()
        #expect(vm.consentIsCurrent && vm.consentText == String(localized: "Given"))
        #expect(vm.consentDetail?.contains(MockData.policyVersion) == true)
        #expect(vm.policyPage == .privacy)

        await vm.withdrawConsent()

        #expect(!vm.consentIsCurrent && vm.consentText == String(localized: "Not given"))
        #expect(vm.consentDetail == String(localized: "RYFT doesn't sync or score your health data until you agree."))
        #expect(!vm.withdrawingConsent && vm.consentError == nil)
        vm.reviewConsent()
        #expect(onboarding.sheetStep == .consent)
    }

    @Test func aConsentToAnOlderPolicyIsShownAsOutdated() async {
        let api = MockPlatformAPI()
        api.accountConsent = Consent(policyVersion: "2026-01-01", grantedAt: .now)
        let (vm, onboarding, _) = profile(api)
        await onboarding.check()
        #expect(!vm.consentIsCurrent && vm.consentText == String(localized: "Policy updated"))
    }

    @Test func birthYearSetsTheEstimateAndManualCanGoBack() async {
        let (vm, _, state) = profile()
        let body = vm.bodySettings
        state.user = MockData.user
        #expect(body.maxHRSourceText == String(localized: "Default · add your birth year for an estimate"))
        #expect(body.birthYear == nil && body.birthYears.first == OnboardingCoordinator.latestBirthYear(now: .now))
        #expect(body.birthYears.last == 1920)

        await body.setBirthYear(1990)
        #expect(body.birthYear == 1990 && state.user?.maxHrSource == .estimated)
        #expect(body.maxHRSourceText?.contains("1990") == true)
        #expect(body.maxHR == state.user?.maxHr && !body.canUseMaxHREstimate)

        var manual = MockData.user
        manual.maxHrSource = .manual
        state.user = manual
        #expect(body.canUseMaxHREstimate && body.maxHRSourceText == String(localized: "Set by you"))
        #expect(await body.useMaxHREstimate())
        #expect(body.savedChange) // the sheet offers the rescore
    }

    @Test func maxHeartRateSavesAsYoursAndARefusalSaysTheRange() async {
        let api = MockPlatformAPI()
        let (vm, _, state) = profile(api)
        let body = vm.bodySettings
        state.user = MockData.user
        #expect(await body.setMaxHR(184))
        #expect(api.mePatches.last?.maxHr == 184 && state.user?.maxHr == 184)
        api.failNext = APIError.http(422, "max_hr out of range")
        #expect(!(await body.setMaxHR(229)))
        #expect(body.error == String(localized: "RYFT takes a maximum heart rate between 100 and 230 bpm."))
        #expect(body.maxHR == 184)
    }
}

/// A flag set from any thread.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// The review on #8: what must hold however the platform answers.
@Suite("Onboarding: edge cases")
@MainActor
struct OnboardingEdgeTests {
    @Test func nothingSyncsWhileTheAccountIsUnknown() async {
        let api = MockPlatformAPI()
        api.failure = APIError.transport(URLError(.timedOut)) // the first check gets no answer
        let (model, state, _) = onboarding(api)
        await model.check()
        #expect(state.user == nil && model.missing.isEmpty)
        #expect(model.syncGate == .consentRequired) // a consent can't be assumed
        #expect(model.pendingGate == nil) // and it isn't the user's to fix
    }

    @Test func withdrawingClearsTheConsentEvenIfTheRecheckFails() async {
        let api = MockPlatformAPI()
        let (model, state, _) = onboarding(api, introDone: true)
        await model.check()
        api.failAfterRevoke = true
        #expect(await model.withdrawConsent())
        #expect(state.user?.consent == nil && model.syncGate == .consentRequired)
    }

    @Test func anotherAccountOnAPhoneThatAllowedHealthStillGetsItsSteps() async {
        let api = MockPlatformAPI()
        api.accountConsent = nil
        let (model, _, _) = onboarding(api, introDone: true) // the first account reached the tabs
        await model.check()
        #expect(!model.isFirstRun)
        model.switchAccount("second-account")
        #expect(model.isFirstRun) // per account, not per device
    }

    @Test func aGateWhileUploadingStopsBeforeTheNextPage() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [
            HealthDelta(samples: [Sample(type: .heartRate, start: .now, end: .now, value: 60, unit: "bpm", source: "W")]),
            HealthDelta(samples: [Sample(type: .heartRate, start: .now, end: .now, value: 61, unit: "bpm", source: "W")]),
        ]])
        let api = MockPlatformAPI()
        let sync = SyncService(env: .test(api: api, health: health))
        let withdrawn = Flag()
        sync.gate = { withdrawn.isSet ? .consentRequired : nil }
        api.afterSync = { withdrawn.set() } // consent withdrawn meanwhile

        _ = try? await sync.upload()

        #expect(api.count("sync") == 1 && health.committed.count == 1) // the second page stays
        #expect(sync.pausedFor == .consentRequired && sync.lastError == nil)
    }

    @Test func trainKeepsWritesRefusedAtAGate() {
        #expect(TrainSyncService.isRetryable(.http(403, "", code: .inviteRequired)))
        #expect(TrainSyncService.isRetryable(.http(403, "", code: .consentRequired)))
        #expect(!TrainSyncService.isRetryable(.http(403, "built-in"))) // a real refusal is set aside
    }

    @Test func signInMethodsBelongToTheirAccount() async {
        let client = MockAuthClient(session: .preview(provider: "email"))
        let auth = AuthService(client: client, defaults: UserDefaults(suiteName: "ryft.test.\(UUID())") ?? .standard,
                               wipeLocalData: {}, deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
                               postAppleAuthorization: { _ in })
        await auth.loadSignInMethods()
        #expect(auth.signInMethods.map(\.provider) == ["email"])
        await auth.signOut()
        #expect(auth.signInMethods.isEmpty && !auth.hasAppleSignIn)
    }
}

// MARK: - T0 refresh resilience: root-cause tests, now asserting the fix (T1)
//
// T0 wrote these against the all-or-nothing refresh, wrapped in `withKnownIssue`. T1 (per-resource reads through
// `ReadScheduler`, `RefreshPolicy` for the card) made them pass; they now assert the fixed behaviour.

#if DEBUG
@Suite("T0: refresh per resource")
@MainActor
struct RefreshAllOrNothingTests {
    private func model(_ api: MockPlatformAPI) -> (TodayViewModel, AppState, TestClock) {
        let (env, state, clock) = makeState(api: api)
        let sync = SyncService(env: env)
        let vm = TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        return (vm, state, clock)
    }

    /// Item 1: `/v1/me` or `/v1/days` failing no longer turns a refresh whose other calls worked into a card.
    @Test(arguments: [("me", FaultInjection.Fault.timeout), ("days", .unavailable), ("me", .tooManyRequests)])
    func oneFailingReadShowsNoCard(route: String, fault: FaultInjection.Fault) async {
        let api = MockPlatformAPI()
        let (vm, state, clock) = model(api)
        await state.refresh()                  // everything cached and current
        api.faults[route] = .init(fault)

        await vm.refresh()                     // pull to refresh: returns after today and the sync status
        await finishPull(state, clock)         // me and history come in phase 3

        #expect(api.count(route) >= 2)         // it did fail, and was retried
        #expect(state.lastUpdated != nil)      // the day itself loaded fine
        #expect(vm.status == nil, "got \(String(describing: vm.status))")
    }

    /// Phase 3 to its end, moving the test clock through retries and the rate-limit hold-back.
    private func finishPull(_ state: AppState, _ clock: TestClock) async {
        guard let phases = state.pullPhases else { return }
        let done = PullDone()
        let waiter = Task {
            await phases.value
            done.value = true
        }
        for _ in 0..<120 where !done.value {
            clock.advance(by: .seconds(1))
            try? await Task.sleep(for: .milliseconds(2))
        }
        await waiter.value
    }

    /// A failing `/v1/days/{day}` with a cached copy is swallowed by the repository (and counted).
    @Test func aFailingDayWithACachedCopyIsSwallowed() async {
        let api = MockPlatformAPI()
        let (vm, state, clock) = model(api)
        await state.refresh()
        api.faults["day"] = .init(.timeout)
        await vm.refresh()
        await finishPull(state, clock)
        #expect(vm.status == nil)
    }

    /// Trends and insights are independent of `/v1/me`: a failed `/v1/me` costs nothing else.
    @Test func aFailedMeLeavesTheRestOfTheRefresh() async {
        let api = MockPlatformAPI()
        let (_, state, _) = model(api)
        await state.refresh()
        let trends = api.count("trends"), insights = api.count("insights")
        api.faults["me"] = .init(.timeout)

        await state.refresh(force: true)

        #expect(api.count("trends") == trends + 1 && api.count("insights") == insights + 1)
        #expect(state.resourceStates[.me]?.consecutiveFailures == 1)
        #expect(state.resourceStates[.me]?.lastError?.transport == "timedOut")
        #expect(state.resourceStates[.trends]?.consecutiveFailures == 0)
    }

    /// Item 1, second path: `refreshDays` (after a sync, a silent push) records a failed read per resource and
    /// neither throws it nor owns the card.
    @Test func aFailedHistoryAfterASyncShowsNoCard() async throws {
        let api = MockPlatformAPI()
        let (vm, state, _) = model(api)
        await state.refresh()
        api.faults["days"] = .init(.timeout)

        try await state.refreshDays([])

        #expect(vm.status == nil, "got \(String(describing: vm.status))")
        #expect(state.resourceStates[.history]?.consecutiveFailures == 1)
    }

    /// Item 2, cancellation: a cancelled request (`URLError.cancelled` in `.transport`, the mock's `cancel`
    /// fault) is no failure: no card, no count, no `lastError`.
    @Test(arguments: [FaultInjection.Fault.cancel])
    func aCancelledRefreshIsNotAFailure(fault: FaultInjection.Fault) async {
        let api = MockPlatformAPI()
        let (vm, state, _) = model(api)
        await state.refresh()
        api.faults["days"] = .init(fault)
        api.faults["me"] = .init(fault)

        await state.refresh(force: true)

        #expect(vm.status == nil)
        for resource in [ReadResource.history, .me] {
            #expect(state.resourceStates[resource]?.lastError == nil)
            #expect(state.resourceStates[resource]?.consecutiveFailures == 0)
        }
        #expect(api.count("me") == 2) // never retried
    }

    /// The other cancellation shape: Swift's `CancellationError`.
    @Test func aSwiftCancellationErrorIsNotAFailureEither() async {
        let api = MockPlatformAPI()
        let (vm, state, _) = model(api)
        await state.refresh()
        api.failure = CancellationError()

        await state.refresh(force: true)

        #expect(vm.status == nil)
        #expect(state.resourceStates.values.allSatisfy { $0.lastError == nil && $0.consecutiveFailures == 0 })
    }

    /// And after a sync, `refreshDays` records nothing for a cancellation.
    @Test func refreshDaysRecordsNoCancellation() async {
        let api = MockPlatformAPI()
        let (_, state, _) = model(api)
        await state.refresh()
        api.failure = CancellationError()

        try? await state.refreshDays([])

        #expect(state.resourceStates.values.allSatisfy { $0.lastError == nil && $0.consecutiveFailures == 0 })
    }

    /// Item 5: every card has Details: the resource, the status (or "no response" and the transport), the
    /// request ID when there was one. A cancellation never makes a card.
    @Test func everyCardHasDetails() async {
        for fault in [FaultInjection.Fault.unavailable, .timeout, .cancel] {
            let api = MockPlatformAPI()
            let (vm, state, _) = model(api)
            api.faults["day"] = .init(fault)       // nothing cached: one failed pass shows the card
            api.faults["days"] = .init(fault)
            await vm.refresh()
            await state.pullPhases?.value
            guard fault != .cancel else {
                #expect(vm.status == nil, "\(fault): \(String(describing: vm.status))")
                continue
            }
            guard case .refreshIssue(let issue) = vm.status else { Issue.record("no card for \(fault)"); continue }
            #expect(issue.resource == .today && issue.failures >= 1)
            if fault == .unavailable {
                #expect(issue.reason == .busy && issue.error.status == 503 && issue.error.requestID == "fault-day")
            } else {
                #expect(issue.reason == .unreachable && issue.error.status == nil && issue.error.transport == "timedOut")
            }
            #expect(issue.copyText.contains(String(localized: "Today")))
        }
    }
}
#endif

/// Set once the awaited work has ended (main actor).
@MainActor
private final class PullDone {
    var value = false
}
