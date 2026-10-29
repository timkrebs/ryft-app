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
        let vm = {
            let sync = SyncService.ungated(env: env)
            return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()
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
        let vm = {
            let sync = SyncService.ungated(env: env)
            return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()
        #expect(vm.greeting == String(localized: "Good morning,"))
        clock.set(Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now)!)
        #expect(vm.greeting == String(localized: "Good evening,"))
    }

    /// Nothing cached at all: the card shows after one failed pass (a blank Today is the alternative).
    @Test func failureWithoutDataShowsTheCardAfterOnePass() async {
        let api = MockPlatformAPI()
        api.failure = APIError.http(500, "", requestID: "rid-500")
        let (env, state, _) = makeState(api: api)
        let vm = {
            let sync = SyncService.ungated(env: env)
            return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()

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
        let vm = {
            let sync = SyncService.ungated(env: env)
            return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()

        await state.refresh()

        guard case .refreshIssue(let issue) = vm.status else {
            Issue.record("expected the card, got \(String(describing: vm.status))")
            return
        }
        #expect(issue.resourceName == ReadResource.today.displayName)
        #expect(issue.statusText == "503" && issue.error.requestID == "rid-503")
        #expect(issue.error.code == "consent_required")
        #expect(vm.syncLine.text(now: env.clock.now()) == String(localized: "Couldn't load today · Details"))
    }

    /// Criterion 8: the line's tap. With the card on screen it scrolls to the card (once per tap) and
    /// opens nothing; otherwise it opens Sync details.
    @Test func tappingTheIssueLineScrollsToTheCardInsteadOfOpeningDetails() async {
        let api = MockPlatformAPI()
        api.failure = APIError.http(500, "", requestID: "rid-500")
        let (env, state, _) = makeState(api: api)
        let vm = {
            let sync = SyncService.ungated(env: env)
            return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()
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
        let vm = {
            let sync = SyncService.ungated(env: env)
            return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()
        await state.refresh()
        #expect(vm.syncLine == .upToDate(state.lastUpdated, demo: false))

        vm.resolveLine()

        #expect(vm.showsSyncDetails && vm.scrollToIssue == 0)
    }

    @Test func tappingTheOfflineLineOpensSyncDetails() {
        let (env, state, _) = makeState(online: false)
        let vm = {
            let sync = SyncService.ungated(env: env)
            return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()
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
        let vm = {
            let sync = SyncService.ungated(env: env)
            return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()
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
        let vm = {
            let sync = SyncService.ungated(env: env)
            return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()

        await vm.refresh()

        #expect(vm.isOffline)
        #expect(api.calls.isEmpty)
        #expect(vm.status == nil)
    }

    @Test func calibratingSaysTheBaselinesAreForming() {
        let (env, state, _) = makeState()
        var detail = MockData.todayDetail
        detail.score = MockData.calibratingScore
        state.today = detail
        let vm = {
            let sync = SyncService.ungated(env: env)
            return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()
        // The gauge counts the nights ("Baselines · 3 of 7 nights"); the sentence says what they're for (ui.md §1.5).
        #expect(vm.hero == .calibrating(nights: MockData.calibratingScore.baselineDays))
        #expect(vm.sentence == String(localized: "Your baselines are still forming."))
        #expect(vm.readiness == nil)
    }

    @Test func failedHealthUploadPausesSync() async {
        let health = MockHealthStore(streams: [.quantity(.heartRate)], pages: [.quantity(.heartRate): [
            HealthDelta(samples: [Sample(type: .heartRate, start: .now, end: .now, value: 60, unit: "bpm", source: "x")])
        ]])
        let api = MockPlatformAPI()
        api.failNext = APIError.http(500, "")
        let (env, state, _) = makeState(api: api, health: health)
        let sync = SyncService.ungated(env: env)
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
        let vm = {
            let sync = SyncService.ungated(env: env)
            return TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()
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
        // A scored row has a `computed_at`, also a calibrating one without a readiness; the rest is unscored.
        DailyScore(day: day ?? todayKey, readiness: readiness, state: readiness == nil ? .calibrating : .balanced,
                   baselineDays: baselineDays, calibrating: calibrating,
                   computedAt: readiness != nil || calibrating ? morning : nil, scoringState: state)
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
            $0.prior = [yesterday]
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
        let sync = SyncService.ungated(env: state.env)
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
        // Nothing pretends to be today's: the gauge is an outline, the tiles are yesterday's, dimmed and dated.
        #expect(vm.readiness == nil && vm.tilesDimmed && vm.tileCaption == String(localized: "Yesterday"))
        #expect(vm.sleepText == Fmt.duration(minutes: 430) && vm.recoveryCaption == String(localized: "Yesterday"))
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

// MARK: - Today: the night not in Apple Health, slow scoring (tracker setup T1)

/// design.md §6: `nightGap` as a table, `scoringSlow`, the line's new branches and the hint's kinds, from the
/// facts alone; then `SyncService`'s wait start and the view model's names.
@Suite("Today: night not in Apple Health, slow scoring")
@MainActor
struct TodayNightAndScoringTests {
    private let base = Date(timeIntervalSince1970: 1_792_400_000)

    private func at(_ hour: Int, _ minute: Int = 0, daysAgo: Int = 0) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: base) ?? base
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func connect(_ newest: Date) -> SourceFreshness {
        SourceFreshness(source: "Connect", bundleID: "com.garmin.connect.mobile", newest: newest)
    }

    private func watch(_ newest: Date) -> SourceFreshness {
        SourceFreshness(source: "Tim's Apple Watch", bundleID: "com.apple.health.4B1C2D3E", newest: newest, deviceModel: "Watch")
    }

    private func phone(_ newest: Date) -> SourceFreshness {
        SourceFreshness(source: "Tim's iPhone", bundleID: "com.apple.health.3F0A9B8C", newest: newest, deviceModel: "iPhone")
    }

    private func status(_ state: ScoringState, now: Date, pending: [String]? = nil, latestSleep: Date? = nil,
                        expected: Int = 20) -> SyncStatus {
        let key = DayFormat.string(from: now)
        return SyncStatus(gate: nil, lastSyncAt: now, lastSyncDevice: "iPhone", latest: latestSleep.map { ["sleep": $0] } ?? [:],
                          today: TodayState(day: key, state: state, scoredAt: nil, modelVersion: "2026.10.1"),
                          pendingDays: pending ?? (state == .pending ? [key] : []), expectedWithinSec: expected,
                          resyncRequestedAt: nil)
    }

    /// 09:12 by default: the platform waits for sleep, Garmin Connect has been quiet since 23:24, the day
    /// before is scored. The names come from the bundled catalog, as the view model resolves them.
    private func facts(now: Date? = nil, _ change: (inout TodaySyncFacts) -> Void = { _ in }) -> TodaySyncFacts {
        let now = now ?? at(9, 12)
        var f = TodaySyncFacts(now: now)
        f.engine.backfillDone = true
        f.hasScoredDay = true
        f.lastUpdated = now.addingTimeInterval(-120)
        f.prior = [DailyScore(day: DayFormat.string(from: DayFormat.shift(now, days: -1)), readiness: 76, state: .balanced,
                              baselineDays: 30, calibrating: false, computedAt: now.addingTimeInterval(-86_400), scoringState: .scored)]
        f.status = status(.waitingForSleep, now: now)
        f.statusReadAt = now // the platform's latest word, just read
        f.freshness = [connect(at(23, 24, daysAgo: 1))]
        change(&f)
        f.sourceApps = SourceApp.resolve(f.sourceRefs, in: .bundled)
        return f
    }

    private func content(_ f: TodaySyncFacts) -> TodayContent {
        let p = TodayPresentation.decide(f.scores)
        return TodayContent(facts: f, presentation: p, hero: TodayStates.hero(f, presentation: p), hasDataSource: true,
                            readinessWeek: [], detailSleepMin: nil)
    }

    private let garminStore = URL(string: "https://apps.apple.com/app/id583446403")

    // MARK: the night hint

    @Test func theNightGapNamesTheAppToOpen() throws {
        let f = facts()
        let gap = try #require(TodayStates.nightGap(f))
        #expect(gap == NightGap(name: "Garmin Connect", kind: .app, storeURL: garminStore, newest: at(23, 24, daysAgo: 1)))
        let hint = try #require(TodayStates.watchHint(f))
        #expect(hint.isNight && hint.source == "Garmin Connect" && hint.opensApp && hint.storeURL == garminStore)
        #expect(hint.systemImage == "moon.zzz")
        #expect(hint.text(now: f.now)
                == String(localized: "Your night hasn't reached Apple Health yet. Open \("Garmin Connect") to sync it."))
        let time = at(23, 24, daysAgo: 1).formatted(.dateTime.weekday(.abbreviated).hour().minute())
        #expect(hint.caption() == String(localized: "Last data from \("Garmin Connect"): \(time)"))
        #expect(hint.storeTitle == String(localized: "\("Garmin Connect") in the App Store"))
        // The screen's locale, not the phone's: 24-hour German, 12-hour US.
        let de = Locale(identifier: "de_DE"), us = Locale(identifier: "en_US")
        #expect(hint.caption(locale: de)?.contains(at(23, 24, daysAgo: 1).formatted(Date.FormatStyle(locale: de).hour().minute())) == true)
        #expect(hint.caption(locale: de)?.contains("23:24") == true && hint.caption(locale: us)?.contains("11:24") == true)
    }

    @Test func onlyFromEightUntilThree() {
        #expect(TodayStates.nightGap(facts(now: at(7, 59))) == nil)
        #expect(TodayStates.nightGap(facts(now: at(8, 0))) != nil)
        #expect(TodayStates.nightGap(facts(now: at(14, 59))) != nil)
        #expect(TodayStates.nightGap(facts(now: at(15, 0))) == nil)
    }

    @Test func anyNightEvidenceAfterFourCancelsIt() {
        // The tracker wrote after 04:00: it synced.
        #expect(TodayStates.nightGap(facts { $0.freshness = [connect(at(4, 1))] }) == nil)
        #expect(TodayStates.nightGap(facts { $0.freshness = [connect(at(4, 0))] }) != nil) // at 04:00, not after
        // The platform's newest sleep is after it (another device, or a record HealthKit didn't list here).
        #expect(TodayStates.nightGap(facts { $0.status = status(.waitingForSleep, now: $0.now, latestSleep: at(6, 50)) }) == nil)
        #expect(TodayStates.nightGap(facts {
            $0.status = status(.waitingForSleep, now: $0.now, latestSleep: at(23, 0, daysAgo: 1))
        }) != nil)
    }

    @Test func theIPhonesInBedSleepIsNotTheNight() {
        // The sleep schedule's in-bed record at 07:05 doesn't cancel Garmin's missing night.
        let f = facts { $0.freshness = [connect(at(23, 24, daysAgo: 1)), phone(at(7, 5))] }
        #expect(TodayStates.nightGap(f)?.name == "Garmin Connect")
        // The iPhone alone, or nothing: no tracker to wait for.
        #expect(TodayStates.nightGap(facts { $0.freshness = [phone(at(1, 0))] }) == nil)
        #expect(TodayStates.nightGap(facts { $0.freshness = [] }) == nil)
        // An Apple-prefixed source without a device model isn't known to be the phone: a candidate.
        let unknown = SourceFreshness(source: "Device", bundleID: "com.apple.health.77AA", newest: at(7, 5))
        #expect(TodayStates.nightGap(facts { $0.freshness = [connect(at(23, 24, daysAgo: 1)), unknown] }) == nil)
    }

    @Test func theWatchIsACandidateWithItsOwnSentence() throws {
        let f = facts { $0.freshness = [watch(at(22, 10, daysAgo: 1)), connect(at(20, 0, daysAgo: 1))] }
        let gap = try #require(TodayStates.nightGap(f))
        #expect(gap.kind == .appleDevice && gap.name == "Tim's Apple Watch" && gap.storeURL == nil)
        let hint = try #require(TodayStates.watchHint(f))
        #expect(!hint.opensApp)
        #expect(hint.text(now: f.now) == String(
            localized: "Your night hasn't reached Apple Health yet. Keep your Apple Watch near your iPhone so it syncs."))
        // A watch worn this morning: its heart rate is the evidence.
        #expect(TodayStates.nightGap(facts { $0.freshness = [watch(at(9, 0)), connect(at(20, 0, daysAgo: 1))] }) == nil)
    }

    @Test func anUnknownSourceKeepsItsNameAndGetsNoButton() throws {
        let diary = SourceFreshness(source: "Sleep Diary", bundleID: "com.example.sleep", newest: at(23, 0, daysAgo: 1))
        let hint = try #require(TodayStates.watchHint(facts { $0.freshness = [diary] }))
        #expect(hint.isNight && hint.source == "Sleep Diary" && !hint.opensApp)
        #expect(hint.text(now: at(9, 12)) == String(localized: "Your night hasn't reached Apple Health yet."))
    }

    @Test func notWhenTheNightIsScoredOrBeingScoredOrNoOneCanAct() {
        // Scored: the night arrived.
        #expect(TodayStates.nightGap(facts {
            $0.today = DailyScore(day: DayFormat.string(from: $0.now), readiness: 72, state: .balanced, baselineDays: 30,
                                  calibrating: false, computedAt: $0.now, scoringState: .scored)
            $0.status = status(.scored, now: $0.now)
        }) == nil)
        // Uploaded and pending: the gauge says it's being scored (D2's exclusivity).
        #expect(TodayStates.nightGap(facts { $0.status = status(.pending, now: $0.now) }) == nil)
        // Offline (noise), the first import, a locked phone, an account that doesn't sync.
        #expect(TodayStates.nightGap(facts { $0.online = false }) == nil)
        #expect(TodayStates.nightGap(facts { $0.engine.backfillDone = false }) == nil)
        #expect(TodayStates.nightGap(facts { $0.waitingForUnlock = true }) == nil)
        #expect(TodayStates.nightGap(facts { $0.syncs = false }) == nil)
    }

    @Test func outsideTheMorningTheQuietHintUsesTheDisplayName() throws {
        let f = facts(now: at(16, 0)) { $0.freshness = [connect(at(1, 0))] }
        let hint = try #require(TodayStates.watchHint(f))
        #expect(!hint.isNight && hint.source == "Garmin Connect" && hint.storeURL == garminStore && hint.caption() == nil)
        #expect(hint.systemImage == "antenna.radiowaves.left.and.right") // Apple's watch glyph is the Apple Watch's
        #expect(hint.text(now: f.now) == String(
            localized: "Nothing new from \("Garmin Connect") since \(Fmt.time(at(1, 0))). Open the \("Garmin Connect") app to sync it to Apple Health."))
        // Without a name (the map is the facts builder's), HealthKit's.
        var plain = f
        plain.sourceApps = [:]
        #expect(TodayStates.watchHint(plain)?.source == "Connect")
        #expect(TodayStates.watchHint(plain)?.opensApp == false)
    }

    // MARK: the line

    @Test func neverScoringBesideANightGap() {
        // The iPhone's steps were uploaded and are being scored; the night hasn't arrived.
        let f = facts { $0.phase = .awaitingScores }
        #expect(TodayStates.nightGap(f) != nil)
        #expect(TodayStates.line(f) == .upToDate(f.lastUpdated, demo: false))
        // After 15:00: newer data is being scored, not the night the gauge still waits for.
        #expect(TodayStates.line(facts(now: at(15, 30)) { $0.phase = .awaitingScores }) == .scoring(night: false))
        // What's truer still wins over the gap's line.
        #expect(TodayStates.line(facts { $0.phase = .awaitingScores; $0.activity = .reading(.sleep) }) == .reading(.sleep))
        #expect(TodayStates.line(facts { $0.phase = .refreshing }) == .updating)
        #expect(TodayStates.line(facts { $0.syncFailed = true }) == .paused)
    }

    @Test func slowAfterThreeTimesTheEstimateWithAFloor() {
        func slow(_ seconds: TimeInterval, expected: Int?) -> Bool {
            let now = at(10, 0).addingTimeInterval(seconds)
            return TodayStates.scoringSlow(since: at(10, 0), expected: expected, now: now, checkedAt: now)
        }
        #expect(!slow(60, expected: 5) && slow(61, expected: 5)) // the 60 s floor
        #expect(!slow(90, expected: 30) && slow(91, expected: 30)) // 3 × 30 s
        #expect(!slow(300, expected: 100) && slow(301, expected: 100))
        #expect(!slow(90, expected: nil) && slow(91, expected: nil)) // no estimate yet: API.md's 30 s
        #expect(!TodayStates.scoringSlow(since: nil, expected: 20, now: at(12, 0), checkedAt: at(12, 0)))
        // Only on the platform's word after the threshold: no read since, or one before it, isn't enough.
        #expect(!TodayStates.scoringSlow(since: at(10, 0), expected: 20, now: at(12, 0), checkedAt: nil))
        #expect(!TodayStates.scoringSlow(since: at(10, 0), expected: 20, now: at(12, 0), checkedAt: at(10, 0).addingTimeInterval(59)))
        #expect(TodayStates.scoringSlow(since: at(10, 0), expected: 20, now: at(12, 0), checkedAt: at(10, 1)))
        #expect(SyncLine.scoringSlow.text(now: .now) == String(localized: "Taking longer than usual · Details"))
        #expect(SyncLine.scoringSlow.systemImage == "clock" && !SyncLine.scoringSlow.isActive)
    }

    @Test func theLineTurnsSlowDuringTheWaitAndStaysAfterTheCutOff() {
        // The night is being scored (20 s expected): 30 s in, scoring; past 60 s, slow.
        var f = facts(now: at(10, 0)) {
            $0.status = status(.pending, now: $0.now)
            $0.phase = .awaitingScores
            $0.scoringSince = $0.now.addingTimeInterval(-30)
        }
        #expect(TodayStates.line(f) == .scoring(night: true))
        f.scoringSince = f.now.addingTimeInterval(-61)
        #expect(TodayStates.line(f) == .scoringSlow)
        // Until a read after the threshold lists the night, still "Scoring".
        f.statusReadAt = f.now.addingTimeInterval(-30)
        #expect(TodayStates.line(f) == .scoring(night: true))
        f.statusReadAt = f.now
        // The coordinator gave up at 300 s and is idle; the platform still lists the day: slow, not "Up to date".
        f.phase = .idle
        f.scoringSince = f.now.addingTimeInterval(-400)
        #expect(TodayStates.line(f) == .scoringSlow)
        // A later read that no longer lists it: not slow, whatever the clock says.
        f.status = status(.scored, now: f.now)
        #expect(!TodayStates.scoringSlow(f))
        // No start (cleared by the platform's word): the shipped line.
        f.scoringSince = nil
        #expect(TodayStates.line(f) == .scoring(night: true))

        // Newer data than the night (today scored): "Scoring your latest data", then slow, also after the wait.
        let scored = DailyScore(day: DayFormat.string(from: at(16, 0)), readiness: 72, state: .balanced, baselineDays: 30,
                                calibrating: false, computedAt: at(9, 0), scoringState: .scored)
        var day = facts(now: at(16, 0)) {
            $0.today = scored
            $0.status = status(.scored, now: $0.now, pending: [DayFormat.string(from: $0.now)])
            $0.phase = .awaitingScores
            $0.scoringSince = $0.now.addingTimeInterval(-20)
        }
        #expect(TodayStates.line(day) == .scoring(night: false))
        day.scoringSince = day.now.addingTimeInterval(-120)
        #expect(TodayStates.line(day) == .scoringSlow)
        day.phase = .done
        #expect(TodayStates.line(day) == .scoringSlow)
        // The error card and a stale read still win.
        #expect(TodayStates.line(day, card: .today) == .issue(.today))
    }

    @Test func thePendingGaugeSaysWhatsTrue() {
        // Waiting for sleep with a night gap: row C as shipped; the hint card under it names the app.
        let gap = content(facts())
        #expect(gap.pendingTitle == String(localized: "Waiting for last night's sleep"))
        #expect(gap.pendingDetail.isEmpty) // the hint card says it, once
        #expect(!gap.pendingIsStatic && gap.watchHint?.isNight == true)
        #expect(gap.sentence == String(localized: "Yesterday's readiness, until last night is scored."))
        // Without the hint (after 15:00), the gauge's own line again.
        #expect(content(facts(now: at(15, 30))).pendingDetail == String(localized: "It's scored as soon as Apple Health has it."))
        // Scoring in time: the shipped words.
        let onTime = content(facts { $0.status = status(.pending, now: $0.now); $0.scoringSince = $0.now.addingTimeInterval(-10) })
        #expect(onTime.pendingTitle == String(localized: "Scoring your night…"))
        #expect(onTime.pendingDetail == String(localized: "Usually ready within 20 s.") && !onTime.pendingIsStatic)
        // Slow: no promise, no breathing.
        let slow = content(facts { $0.status = status(.pending, now: $0.now); $0.scoringSince = $0.now.addingTimeInterval(-120) })
        #expect(slow.pendingTitle == String(localized: "Still scoring your night"))
        #expect(slow.pendingDetail == String(localized: "Your data is safe. RYFT will keep trying.") && slow.pendingIsStatic)
        // Last night's source by its display name.
        let night = content(facts {
            $0.status = status(.pending, now: $0.now)
            $0.lastNight = RawNight(asleepMin: 430, bedtime: at(23, 0, daysAgo: 1), wake: at(6, 50), source: "Connect",
                                    bundleID: "com.garmin.connect.mobile")
        })
        #expect(night.rawNight?.source == "Connect" && night.rawNightSource == "Garmin Connect")
    }

    // MARK: through SyncService and the view model

    @Test func theWaitsStartStaysOnlyWhileThePlatformSaysPending() {
        let (env, _, clock) = makeState(now: at(10, 0))
        let sync = SyncService.ungated(env: env)
        sync.advance(to: .reading)
        sync.advance(to: .awaitingScores)
        #expect(sync.scoringWaitStart == at(10, 0))
        #expect(sync.scoringSince(pendingDays: []) == at(10, 0)) // during the wait, whatever was said before
        // Scored before the cut-off (a push, or GET /v1/me/sync): gone.
        clock.advance(by: .seconds(40))
        sync.advance(to: .refreshing)
        #expect(sync.scoringWaitStart == nil)

        // A wait that ran into the cut-off keeps its start while the platform lists pending days.
        sync.advance(to: .done)
        sync.advance(to: .reading)
        sync.advance(to: .awaitingScores)
        let start = clock.now()
        clock.advance(by: SyncCoordinator.maximumScoringWait)
        sync.advance(to: .refreshing)
        sync.advance(to: .done)
        #expect(sync.scoringSince(pendingDays: ["2026-10-18"]) == start)
        #expect(sync.scoringSince(pendingDays: []) == nil)
        // The platform's word, nothing pending: cleared for good.
        sync.receive(status(.scored, now: clock.now()))
        #expect(sync.scoringWaitStart == nil && sync.scoringSince(pendingDays: ["2026-10-18"]) == nil)

        // A silent push's refresh (the platform scored a day) clears it too; so does another account.
        sync.advance(to: .reading)
        sync.advance(to: .awaitingScores)
        clock.advance(by: SyncCoordinator.maximumScoringWait)
        sync.advance(to: .refreshing)
        sync.advance(to: .done)
        #expect(sync.scoringWaitStart != nil)
        sync.receive(status(.pending, now: clock.now())) // still pending: kept
        #expect(sync.scoringWaitStart != nil)
        sync.advance(to: .refreshing)
        #expect(sync.scoringWaitStart == nil)
        sync.advance(to: .done)
        sync.advance(to: .reading)
        sync.advance(to: .awaitingScores)
        sync.accountChanged()
        #expect(sync.scoringWaitStart == nil)
    }

    @Test func theIPhonesInBedSleepOnThePlatformIsNotTheNightEither() {
        // The iPhone's in-bed record at 07:05, here and as the platform's newest sleep: still no night.
        func withLatest(_ latest: Date, phone: Date?) -> NightGap? {
            TodayStates.nightGap(facts {
                $0.freshness = [connect(at(23, 24, daysAgo: 1))] + [phone.map(phone(_:))].compactMap { $0 }
                $0.status = status(.waitingForSleep, now: $0.now, latestSleep: latest)
            })
        }
        #expect(withLatest(at(7, 5), phone: at(7, 5)) != nil)
        #expect(withLatest(at(7, 5).addingTimeInterval(45), phone: at(7, 5)) != nil) // within a minute
        #expect(withLatest(at(7, 0), phone: at(7, 5)) != nil)                         // older than the phone's
        // Newer than anything the phone wrote, or no phone at all: another source's night.
        #expect(withLatest(at(7, 30), phone: at(7, 5)) == nil)
        #expect(withLatest(at(7, 5), phone: nil) == nil)
    }

    @Test func theQuietHintNeverNamesThePhoneAndHidesOffline() throws {
        let afternoon = at(16, 0)
        // The iPhone's in-bed record from 01:00 is no watch gone quiet.
        #expect(TodayStates.watchHint(facts(now: afternoon) { $0.freshness = [phone(at(1, 0))] }) == nil)
        let both = try #require(TodayStates.watchHint(facts(now: afternoon) { $0.freshness = [phone(at(15, 0)), connect(at(1, 0))] }))
        #expect(both.source == "Garmin Connect")
        // Offline it's noise.
        #expect(TodayStates.watchHint(facts(now: afternoon) { $0.freshness = [connect(at(1, 0))]; $0.online = false }) == nil)
        // The Apple Watch keeps its own glyph.
        let watchHint = try #require(TodayStates.watchHint(facts(now: afternoon) { $0.freshness = [watch(at(1, 0))] }))
        #expect(watchHint.systemImage == "applewatch.radiowaves.left.and.right" && !watchHint.opensApp)
    }

    @Test func aWaitThatEndsEarlyForgetsItsStart() {
        let (env, _, clock) = makeState(now: at(10, 0))
        let sync = SyncService.ungated(env: env)
        // Cancelled (background, sign-out) or failed before the cut-off: no start left to call slow hours later.
        for end in [SyncPhase.idle, .failed] {
            sync.advance(to: .reading)
            sync.advance(to: .awaitingScores)
            clock.advance(by: .seconds(30))
            sync.advance(to: end)
            #expect(sync.scoringWaitStart == nil, "\(end)")
            #expect(sync.scoringSince(pendingDays: ["2026-10-18"]) == nil)
        }
        // A wait that ran into the cut-off keeps it, also when it then ends cancelled.
        sync.advance(to: .reading)
        sync.advance(to: .awaitingScores)
        let start = clock.now()
        clock.advance(by: SyncCoordinator.maximumScoringWait)
        sync.advance(to: .idle)
        #expect(sync.scoringWaitStart == start)
        // A run that uploads nothing doesn't touch it: GET /v1/me/sync decides.
        sync.advance(to: .reading)
        sync.advance(to: .refreshing)
        #expect(sync.scoringWaitStart == start)
    }

    @Test func statusReadsStartAndClearTheClockButNeverMidWait() {
        let (env, _, clock) = makeState(now: at(10, 0))
        let sync = SyncService.ungated(env: env)
        // Days pending that nobody here waits for (a relaunch, another device): timed from now, on this clock.
        sync.receive(status(.pending, now: clock.now()))
        #expect(sync.scoringWaitStart == at(10, 0) && sync.statusReadAt == at(10, 0))
        clock.advance(by: .seconds(30))
        sync.receive(status(.pending, now: clock.now()))
        #expect(sync.scoringWaitStart == at(10, 0)) // the first sighting stays
        #expect(sync.statusReadAt == at(10, 0).addingTimeInterval(30)) // every read is recorded
        // During a wait an empty answer can predate the upload: the wait's start stays.
        sync.advance(to: .reading)
        sync.advance(to: .awaitingScores)
        let start = clock.now()
        sync.receive(status(.scored, now: clock.now()))
        #expect(sync.scoringWaitStart == start && sync.scoringSince(pendingDays: []) == start)
        // Outside a wait it clears.
        clock.advance(by: SyncCoordinator.maximumScoringWait)
        sync.advance(to: .refreshing)
        sync.advance(to: .done)
        sync.receive(status(.scored, now: clock.now()))
        #expect(sync.scoringWaitStart == nil)
        sync.accountChanged()
        #expect(sync.statusReadAt == nil)
    }

    @Test func theFactsTimeTheWaitAndTheGaugeStopsBreathing() {
        let now = at(10, 0)
        let (_, state, clock) = makeState(now: now)
        let sync = SyncService.ungated(env: state.env)
        let vm = TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        state.syncStatus = status(.pending, now: now)
        state.history = [DailyScore(day: DayFormat.string(from: DayFormat.shift(now, days: -1)), readiness: 76, state: .balanced,
                                    baselineDays: 30, calibrating: false, computedAt: now.addingTimeInterval(-86_400),
                                    scoringState: .scored)]
        #expect(vm.facts.scoringSince == nil)
        sync.advance(to: .reading)
        sync.advance(to: .awaitingScores)
        #expect(vm.facts.scoringSince == now)
        #expect(vm.content.pendingIsStatic == false && vm.syncLine.isScoring)
        // Past the threshold, before the platform said anything since: still scoring, still breathing.
        clock.advance(by: .seconds(61))
        #expect(!vm.content.pendingIsStatic && vm.syncLine == .scoring(night: true))
        // The coordinator's poll still lists the night: static, "Still scoring your night", line 5b.
        sync.receive(status(.pending, now: clock.now()))
        #expect(vm.content.pendingIsStatic && vm.content.pendingTitle == String(localized: "Still scoring your night"))
        #expect(vm.syncLine == .scoringSlow)
    }

    /// A start from a status read (the app opened after a background upload, no wait, no poll) and no silent push.
    private func firstSight(scoredBeforeTheThreshold: Bool) async -> (TodayViewModel, SyncService, MockPlatformAPI, TestClock) {
        let now = at(7, 0)
        let api = MockPlatformAPI()
        let (_, state, clock) = makeState(api: api, now: now)
        let sync = SyncService.ungated(env: state.env)
        let pipeline = coordinator(state, sync)
        let vm = TodayViewModel(state: state, sync: sync, coordinator: pipeline, apiStatus: APIStatus())
        let today = DayFormat.string(from: now)
        api.scoringToday = TodayState(day: today, state: .pending, scoredAt: nil, modelVersion: "2026.10.1")
        api.pendingDays = [today]
        await pipeline.refreshStatus() // app active's read: today pending, timed from now
        #expect(sync.scoringWaitStart == now && vm.facts.scoringSince == now)
        if scoredBeforeTheThreshold {
            clock.advance(by: .seconds(10)) // scored at 07:00:10; nobody tells this phone
            api.scoringToday = TodayState(day: today, state: .scored, scoredAt: clock.now(), modelVersion: "2026.10.1")
            api.pendingDays = []
        }
        // The one read at the threshold (60 s for API.md's 20 s estimate): asleep until then.
        let check = Task { await vm.confirmSlowScoring() }
        let deadline = Date().addingTimeInterval(5)
        while clock.pendingSleeps == 0, Date() < deadline { await Task.yield() }
        #expect(clock.pendingSleeps == 1)
        #expect(vm.syncLine != .scoringSlow) // before it, never slow
        clock.advance(by: .seconds(scoredBeforeTheThreshold ? 51 : 61))
        await check.value
        return (vm, sync, api, clock)
    }

    @Test func aFirstSightStartScoredMeanwhileIsClearedByTheOneReadAndNeverSlow() async {
        let (vm, sync, api, clock) = await firstSight(scoredBeforeTheThreshold: true)
        #expect(api.calls.filter { $0 == "syncStatus" }.count == 2) // app active's, and exactly one more
        #expect(sync.scoringWaitStart == nil && vm.facts.scoringSince == nil)
        clock.advance(by: .seconds(600))
        #expect(vm.syncLine != .scoringSlow && !TodayStates.scoringSlow(vm.facts))
        await vm.confirmSlowScoring() // nothing left to confirm: no further read
        #expect(api.calls.filter { $0 == "syncStatus" }.count == 2)
    }

    @Test func aFirstSightStartStillPendingAfterTheOneReadIsSlow() async {
        let (vm, _, api, _) = await firstSight(scoredBeforeTheThreshold: false)
        #expect(api.calls.filter { $0 == "syncStatus" }.count == 2)
        #expect(TodayStates.scoringSlow(vm.facts))
        // Decided: running it again asks nothing more.
        await vm.confirmSlowScoring()
        #expect(api.calls.filter { $0 == "syncStatus" }.count == 2)
    }

    @Test func theViewModelNamesSourcesFromTheCatalog() async {
        let health = MockHealthStore()
        let now = Date()
        health.freshness = [SourceFreshness(source: "Connect", bundleID: "com.garmin.connect.mobile", newest: now.addingTimeInterval(-3_600))]
        health.night = RawNight(asleepMin: 400, bedtime: now.addingTimeInterval(-30_000), wake: now.addingTimeInterval(-3_000),
                                source: "Connect", bundleID: "com.garmin.connect.mobile")
        let (_, state, _) = makeState(health: health, now: now)
        let sync = SyncService.ungated(env: state.env)
        let vm = TodayViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        #expect(vm.facts.sourceApps.isEmpty) // nothing to name before HealthKit answered
        await vm.loadHealthFacts()
        let apps = vm.facts.sourceApps
        #expect(apps[health.freshness[0].ref] == SourceApp(name: "Garmin Connect", kind: .app, appStoreURL: garminStore))
        #expect(apps[health.night!.ref]?.name == "Garmin Connect")
    }
}

// MARK: - Today: one decision for gauge, tiles and note (T2)

/// `TodayPresentation.decide` as design.md §7's table, row by row (ui.md's letter in brackets),
/// then through the view model and the demo scenarios.
@Suite("Today: one decision for gauge, tiles and note")
@MainActor
struct TodayPresentationTests {
    private let now = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0,
                                            of: Date(timeIntervalSince1970: 1_792_600_000))!
    private var key: String { DayFormat.string(from: now) }
    private func dayKey(_ offset: Int) -> String { DayFormat.string(from: DayFormat.shift(now, days: offset)) }
    private var yesterday: Date { DayFormat.date(from: dayKey(-1))! }
    private let lastNight = RawNight(asleepMin: 437, bedtime: .now.addingTimeInterval(-30_000), wake: .now.addingTimeInterval(-3_000),
                                     source: "Garmin Connect")

    /// `n` scored days before today, oldest first; yesterday 76 · 75 % · 7h 10m · 0.9.
    private func history(_ n: Int = 30, vitals: Bool = true) -> [DailyScore] {
        (1...n).reversed().map { offset in
            DailyScore(day: dayKey(-offset), readiness: offset == 1 ? 76 : 70, recovery: offset == 1 ? 75 : 60,
                       strain: offset == 1 ? 0.9 : 8, sleepActualMin: offset == 1 ? 430 : 420,
                       hrvMs: vitals ? 55 : nil, rhr: vitals ? 50 : nil, baselineDays: 30,
                       computedAt: DayFormat.shift(now, days: -offset))
        }
    }

    /// The reported screenshot's row: readiness 80, recovery 75, strain 0.9, `calibrating: true`, `baseline_days: 0`.
    private var screenshot: DailyScore {
        DailyScore(day: key, readiness: 80, state: .balanced, recovery: 75, strain: 0.9, sleepActualMin: 437,
                   baselineDays: 0, calibrating: true, computedAt: now, scoringState: .scored)
    }

    /// Scored (a `computed_at`), calibrating, no readiness: ui.md preview 7.
    private var scoredWithoutReadiness: DailyScore {
        DailyScore(day: key, state: .calibrating, baselineDays: 0, calibrating: true, computedAt: now, scoringState: .scored)
    }

    /// API.md → `GET /v1/days/{day}`: a day not scored yet, exactly as the platform sends it.
    private func placeholder() throws -> DailyScore {
        let json = #"{"day":"\#(key)","state":"calibrating","baseline_days":0,"calibrating":false,"#
            + #""computed_at":"0001-01-01T00:00:00Z","scoring_state":"pending"}"#
        return try APIClient.jsonDecoder.decode(DailyScore.self, from: Data(json.utf8))
    }

    private func decide(_ today: DailyScore?, _ prior: [DailyScore], _ state: ScoringState?) -> TodayPresentation {
        .decide(TodayScoreFacts(day: key, today: today, scoringState: state, prior: prior, expectedWithinSec: 20,
                                lastNight: lastNight))
    }

    // MARK: the table

    @Test func standingSaysWhatARowIs() throws {
        #expect(try placeholder().standing == .unscored)
        #expect(DailyScore.empty(day: key).standing == .unscored)
        #expect(scoredWithoutReadiness.standing == .calibrating(baselineDays: 0))
        #expect(screenshot.standing == .calibrating(baselineDays: 0))
        #expect(history(1)[0].standing == .scored)
        #expect(DailyScore(day: key, readiness: 70).standing == .scored) // a cache from before computed_at
    }

    @Test func row1E_nothingScoredEver() throws {
        for p in [decide(nil, [], nil), decide(.empty(day: key), [], nil), decide(try placeholder(), [], .stale),
                  decide(try placeholder(), [], .scored)] {
            #expect(p.row == .firstImport && p.gauge == .firstImport)
            #expect(p.tiles.source == nil && p.note == nil && p.rawNight == nil && !p.showsDelta)
        }
        // The platform scoring the first night is C, with nothing to dim (ui.md preview 5).
        let first = decide(nil, [], .pending)
        #expect(first.row == .pending && first.tiles.source == nil)
        #expect(first.gauge == .pending(PendingNight(waitingForSleep: false, expectedWithinSec: 20)))
    }

    /// The definition of done: an unscored today with a scored history is pending, never "0 of 7".
    @Test func row2C_anUnscoredTodayWithScoredHistoryIsPending() throws {
        let prior = history()
        for today in [try placeholder(), DailyScore.empty(day: key), nil] {
            let p = decide(today, prior, .pending)
            #expect(p.row == .pending)
            #expect(p.gauge == .pending(PendingNight(waitingForSleep: false, expectedWithinSec: 20, previousReadiness: 76,
                                                     previousDay: yesterday)))
            #expect(p.tiles == TodayPresentation.Tiles(source: prior.last, isEarlierDay: true))
            #expect(p.note == nil && p.rawNight == lastNight && !p.showsDelta)
        }
        // Even an unscored row that claims calibrating is not the baselines: it isn't scored.
        var claims = try placeholder()
        claims.calibrating = true
        #expect(decide(claims, prior, .scored).row == .pending)
        #expect(decide(claims, [], .scored).row == .firstImport)
    }

    @Test func row2C_withoutTheNightNothingClaimsItIsScored() throws {
        for state in [ScoringState.waitingForSleep, .stale, nil] {
            let p = decide(try placeholder(), history(), state)
            guard case .pending(let night) = p.gauge else { Issue.record("expected pending for \(String(describing: state))"); continue }
            #expect(night.waitingForSleep && night.expectedWithinSec == nil && night.previousReadiness == 76)
            #expect(p.rawNight == nil) // no night arrived: no Apple Health card
            #expect(p.tiles.isEarlierDay && p.tiles.source?.readiness == 76)
        }
    }

    @Test func row2C_aScoredDayWithoutReadinessWhileScoring() {
        let p = decide(scoredWithoutReadiness, history(), .pending)
        #expect(p.row == .pending && p.tiles.source?.day == dayKey(-1))
        // A score that landed is never pending again.
        #expect(decide(screenshot, history(), .pending).row == .recalculating)
    }

    /// The screenshot: the platform says calibrating with 0 baseline days, the history has 30 nights with HRV and RHR.
    @Test func row3D_theScreenshotShowsTheScoreAndRecalculating() {
        let p = decide(screenshot, history(), .scored)
        #expect(p.row == .recalculating)
        #expect(p.gauge == .readiness(80))
        #expect(p.tiles == TodayPresentation.Tiles(source: screenshot)) // the gauge's day: today, not dimmed
        #expect(p.note == .recalculating)
        #expect(!p.showsDelta)
        #expect(p.gauge != .baselines(nights: 0))
    }

    @Test func row3D_fromTheLatestScoredDay() {
        let prior = history()
        let p = decide(scoredWithoutReadiness, prior, .scored)
        #expect(p.row == .recalculating && p.gauge == .readiness(76) && p.note == .recalculating)
        #expect(p.tiles == TodayPresentation.Tiles(source: prior.last, isEarlierDay: true))
    }

    @Test func row3D_needsSevenNightsWithVitals() {
        var prior = history(30, vitals: false)
        for i in prior.indices.suffix(6) { prior[i].hrvMs = 55; prior[i].rhr = 50 }
        #expect(decide(screenshot, prior, .scored).row == .calibrating) // 6 nights with both
        prior[prior.count - 7].hrvMs = 55
        prior[prior.count - 7].rhr = 50
        #expect(decide(screenshot, prior, .scored).row == .recalculating) // 7
        // Older than the 30 scored days before: they don't count.
        let old = history(40, vitals: false).enumerated().map { i, d in
            var d = d
            if i < 10 { d.hrvMs = 55; d.rhr = 50 }
            return d
        }
        #expect(decide(screenshot, old, .scored).row == .calibrating)
    }

    /// A phone-only account (no HRV): legitimately calibrating. Not "0 / 7" beside a scored day's tiles
    /// (lead decision 2, amended): the platform's readiness with the reason under it, today's tiles as they are.
    @Test func row4B_aLongHistoryWithoutHRVShowsTheReadinessAndWhy() {
        let p = decide(screenshot, history(30, vitals: false), .scored)
        #expect(p.row == .calibrating && p.gauge == .readiness(80))
        #expect(p.tiles == TodayPresentation.Tiles(source: screenshot)) // no "calibrating" caption: the note says it
        #expect(p.note == .needsVitals && !p.showsDelta)
        #expect(p.gauge != .baselines(nights: 0))
        #expect(decide(screenshot, history(7, vitals: false), .scored).note == .needsVitals)
        // A short history is row B as before: today's baseline days, "calibrating" under the tiles.
        let short = decide(screenshot, history(6, vitals: false), .scored)
        #expect(short.gauge == .baselines(nights: 0) && short.note == nil && short.tiles.calibrating)
    }

    /// Without a readiness from the platform: the baselines, counting the nights that count (with HRV and RHR).
    @Test func row4B_aLongHistoryWithoutHRVOrReadinessCountsHeartRateNights() {
        var prior = history(30, vitals: false)
        for i in prior.indices.suffix(3) { prior[i].hrvMs = 55; prior[i].rhr = 50 }
        let p = decide(scoredWithoutReadiness, prior, .scored)
        #expect(p.row == .calibrating && p.gauge == .baselines(nights: 3)) // not today's baseline_days (0)
        #expect(p.tiles == TodayPresentation.Tiles(source: scoredWithoutReadiness))
        #expect(p.note == .needsVitals && !p.showsDelta)
        #expect(p.previousReadiness == 76)
    }

    @Test func row4B_aShortHistoryCountsTodaysBaselineDays() {
        var today = scoredWithoutReadiness
        today.baselineDays = 4
        let p = decide(today, history(4), .scored)
        #expect(p.row == .calibrating && p.gauge == .baselines(nights: 4) && p.note == nil)
        #expect(p.tiles.source == today && p.tiles.calibrating && !p.tiles.isEarlierDay)
    }

    @Test func row5A_scored() {
        let today = DailyScore(day: key, readiness: 84, recovery: 82, strain: 12.4, baselineDays: 30, computedAt: now,
                               scoringState: .scored)
        let p = decide(today, history(), .scored)
        #expect(p.row == .scored && p.gauge == .readiness(84) && p.tiles == TodayPresentation.Tiles(source: today))
        #expect(p.note == nil && p.showsDelta)
    }

    /// The "vs 7 d" delta only beside today's settled readiness (row A with a number): never next to an empty
    /// gauge, a night being scored, the baselines, the import, or a calibrating or borrowed number (review T2).
    @Test func theDeltaOnlyStandsBesideTodaysReadiness() throws {
        let a = DailyScore(day: key, readiness: 84, recovery: 82, strain: 12.4, baselineDays: 30, computedAt: now,
                           scoringState: .scored)
        #expect(decide(a, history(), .scored).showsDelta)                                       // A
        // A scored day the platform gave no readiness (not calibrating, not scoring): "—", no change beside it.
        let empty = DailyScore(day: key, recovery: 60, strain: 3, baselineDays: 30, computedAt: now, scoringState: .scored)
        let e = decide(empty, history(), .scored)
        #expect(e.row == .scored && e.gauge == .readiness(nil) && !e.showsDelta)
        let vitals = history(30, vitals: false)
        #expect(!decide(screenshot, history(4), .scored).showsDelta)                            // B, short
        #expect(!decide(screenshot, vitals, .scored).showsDelta)                                // B with a readiness
        #expect(!decide(scoredWithoutReadiness, vitals, .scored).showsDelta)                    // B, heart-rate nights
        #expect(!decide(try placeholder(), history(), .pending).showsDelta)                     // C
        #expect(!decide(nil, history(), .waitingForSleep).showsDelta)                           // C, waiting
        #expect(!decide(screenshot, history(), .scored).showsDelta)                             // D
        #expect(!decide(scoredWithoutReadiness, history(), .scored).showsDelta)                 // D from yesterday
        #expect(!decide(nil, [], nil).showsDelta)                                               // E
        // Through the view model: a 7-day trend is cached, the gauge is empty, and no change is shown.
        let vm = model(today: empty, history: history(), status: .scored)
        #expect(vm.readiness == nil && !vm.readinessWeek.isEmpty && vm.readinessDelta == nil)
        #expect(model(today: a, history: history(), status: .scored).readinessDelta != nil)
        #expect(model(today: nil, history: [], status: nil, backfillDone: true).readinessDelta == nil)
    }

    /// Every row carries the latest readiness before today (the widget writes it; tomorrow shows it dimmed).
    @Test func everyRowCarriesTheLatestReadiness() throws {
        #expect(decide(screenshot, history(), .scored).previousReadiness == 76)                   // D
        #expect(decide(scoredWithoutReadiness, history(), .scored).previousReadiness == 76)       // D from yesterday
        #expect(decide(screenshot, history(30, vitals: false), .scored).previousReadiness == 76)  // B
        #expect(decide(try placeholder(), history(), .pending).previousReadiness == 76)           // C
        #expect(decide(nil, [], nil).previousReadiness == nil)                                    // E
    }

    @Test func priorIgnoresUnscoredRowsAndTodayItself() throws {
        var prior = history(3)
        prior.append(DailyScore.empty(day: dayKey(-1))) // an unscored copy of yesterday
        prior.append(screenshot) // today's own row in the list
        let p = decide(try placeholder(), prior, .pending)
        guard case .pending(let night) = p.gauge else { Issue.record("expected pending"); return }
        #expect(night.previousReadiness == 76 && night.previousDay == yesterday)
    }

    // MARK: through the view model

    private func model(today: DailyScore?, history: [DailyScore], status: ScoringState?,
                       backfillDone: Bool = false) -> TodayViewModel {
        let env = AppEnvironment.test(clock: TestClock(now: now))
        if backfillDone, let account = env.auth.accountID {
            var engine = SyncEngineState()
            engine.backfillDone = true
            engine.save(account: account, defaults: env.defaults)
        }
        let state = AppState(env: env)
        state.history = history
        if let today { state.today = DayDetail(score: today, sleep: nil, workouts: []) }
        state.readinessWeek = TrendSeries(metric: "readiness", range: "7d",
                                          points: (0..<7).map { TrendPoint(day: dayKey(-6 + $0), value: Double(70 + 2 * $0)) },
                                          avg: 76, min: 70, max: 82, baseline: nil)
        if let status {
            state.syncStatus = SyncStatus(gate: nil, lastSyncAt: now, lastSyncDevice: nil, latest: [:],
                                          today: TodayState(day: key, state: status, scoredAt: nil, modelVersion: "x"),
                                          pendingDays: [], expectedWithinSec: 20, resyncRequestedAt: nil)
        }
        let sync = SyncService.ungated(env: env)
        return TodayViewModel(state: state, sync: sync,
                              coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: env.clock),
                              apiStatus: APIStatus())
    }

    @Test func theSentenceTilesAndNoteFollowTheRow() throws {
        let yesterdayTitle = String(localized: "Yesterday")
        // A: the band word, the delta.
        let a = model(today: DailyScore(day: key, readiness: 84, recovery: 82, strain: 12.4, baselineDays: 30,
                                        computedAt: now, scoringState: .scored), history: history(), status: .scored)
        #expect(a.hero == .score && a.readiness == 84 && a.readinessDelta != nil)
        #expect(a.recoveryCaption == a.recoveryBand && a.recoveryBand != nil && a.tileCaption == nil && !a.tilesDimmed)
        #expect(a.gaugeNote == nil && a.gaugeSpokenNote == nil && a.showsTiles)
        // B, a short history: "calibrating" under all three, no band word, no delta.
        let b = model(today: screenshot, history: history(4), status: .scored)
        #expect(b.hero == .calibrating(nights: 0) && b.readinessDelta == nil)
        #expect(b.sentence == String(localized: "Your baselines are still forming."))
        #expect(b.tileCaption == String(localized: "today.tile.calibrating", defaultValue: "calibrating"))
        #expect(b.recoveryCaption == b.tileCaption && b.recoveryBand == nil && !b.tilesDimmed)
        #expect(b.recoveryText == Fmt.percent(75) && b.strainText == Fmt.strain(0.9))
        #expect(b.gaugeNote == nil && b.gaugeSpokenNote == nil)
        // B, a long history without HRV: the platform's 80, no delta, today's tiles without "calibrating", the
        // reason under the gauge and read with it.
        let bv = model(today: screenshot, history: history(30, vitals: false), status: .scored)
        #expect(bv.hero == .score && bv.readiness == 80 && bv.readinessDelta == nil)
        #expect(bv.sentence == String(localized: "Your baselines are still forming."))
        #expect(bv.tileCaption == nil && !bv.tilesDimmed && bv.recoveryCaption == bv.recoveryBand && bv.recoveryBand != nil)
        #expect(bv.recoveryText == Fmt.percent(75) && bv.strainText == Fmt.strain(0.9))
        #expect(bv.gaugeNote == .needsVitals && bv.gaugeSpokenNote == TodayPresentation.Note.needsVitals.text)
        // ... and without a readiness: the baselines counting heart-rate nights, the note read on its own.
        let bb = model(today: scoredWithoutReadiness, history: history(30, vitals: false), status: .scored)
        #expect(bb.hero == .calibrating(nights: 0) && bb.gaugeNote == .needsVitals && bb.gaugeSpokenNote == nil)
        #expect(bb.tileCaption == nil && bb.sentence == String(localized: "Your baselines are still forming."))
        // C: yesterday's tiles, dimmed and dated; the raw night stays out until Apple Health has one.
        let c = model(today: try placeholder(), history: history(), status: .pending)
        #expect(c.hero.isPending && c.readiness == nil && c.readinessDelta == nil)
        #expect(c.tilesDimmed && c.tileCaption == yesterdayTitle && c.recoveryCaption == yesterdayTitle)
        #expect(c.sleepText == Fmt.duration(minutes: 430) && c.recoveryText == Fmt.percent(75) && c.strainText == Fmt.strain(0.9))
        #expect(c.sentence == String(localized: "Yesterday's readiness, until last night is scored."))
        #expect(c.gaugeNote == nil)
        // D, today: the score without a delta, the note, today's tiles.
        let d = model(today: screenshot, history: history(), status: .scored)
        #expect(d.hero == .score && d.readiness == 80 && d.readinessDelta == nil)
        #expect(d.recoveryText == Fmt.percent(75) && !d.tilesDimmed && d.recoveryBand != nil)
        #expect(d.sentence == String(localized: "Your baselines are being recalculated."))
        #expect(d.gaugeNote == .recalculating && d.gaugeSpokenNote == TodayPresentation.Note.recalculating.text)
        // D, from yesterday: the day is in the sentence, the tiles and what VoiceOver hears.
        let dy = model(today: scoredWithoutReadiness, history: history(), status: .scored)
        #expect(dy.hero == .score && dy.readiness == 76 && dy.tilesDimmed && dy.tileCaption == yesterdayTitle)
        let date = yesterday.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        #expect(dy.sentence == String(localized: "Readiness from \(date), while your baselines are recalculated."))
        #expect(dy.gaugeSpokenNote?.hasPrefix(TodayPresentation.Note.recalculating.text + ". ") == true)
        // E: no tiles, no note; during the import the card stands in ...
        let e = model(today: nil, history: [], status: nil)
        #expect(e.hero.isImporting && e.presentation.row == .firstImport && !e.showsTiles && e.gaugeNote == nil)
        // ... and with the backfill done and still nothing scored, the row alone hides them.
        let done = model(today: nil, history: [], status: nil, backfillDone: true)
        #expect(!done.hero.isImporting && done.presentation.row == .firstImport)
        #expect(!done.showsTiles && done.gaugeNote == nil && done.readiness == nil)
        #expect(done.sentence == String(localized: "Your scores appear after the first synced night."))
    }

    /// The dimmed number's day, in the sentence as on the gauge and tiles: a night without the watch
    /// left a gap, so the latest readiness is from two days ago, not yesterday's (review T2).
    @Test func rowC_afterAGapDayTheSentenceSaysWhichDay() throws {
        let gap = Array(history().dropLast()) // no yesterday: the latest scored day is two days ago, readiness 70
        let c = model(today: try placeholder(), history: gap, status: .pending)
        let twoDaysAgo = try #require(DayFormat.date(from: dayKey(-2)))
        guard case .pending(let night) = c.hero else { Issue.record("expected pending"); return }
        #expect(night.previousReadiness == 70 && night.previousDay == twoDaysAgo)
        let date = twoDaysAgo.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        #expect(c.sentence == String(localized: "Readiness from \(date), until last night is scored."))
        #expect(c.tileCaption == Fmt.dayTitle(twoDaysAgo, today: now) && c.tileCaption != String(localized: "Yesterday"))
        // Yesterday scored: the sentence says so.
        let y = model(today: try placeholder(), history: history(), status: .pending)
        #expect(y.sentence == String(localized: "Yesterday's readiness, until last night is scored."))
    }

    /// `TodayView` reads one `TodayContent` per body: it says what the accessors say.
    @Test func theContentIsWhatTheAccessorsSay() throws {
        for vm in [model(today: screenshot, history: history(), status: .scored),
                   model(today: try placeholder(), history: history(), status: .pending),
                   model(today: screenshot, history: history(30, vitals: false), status: .scored)] {
            let c = vm.content
            #expect(c.hero == vm.hero && c.presentation == vm.presentation && c.sentence == vm.sentence)
            #expect(c.readiness == vm.readiness && c.readinessDelta == vm.readinessDelta && c.gaugeNote == vm.gaugeNote)
            #expect(c.sleepText == vm.sleepText && c.recoveryCaption == vm.recoveryCaption && c.tilesDimmed == vm.tilesDimmed)
            #expect(c.rawNight == vm.rawNight && c.showsTiles == vm.showsTiles)
        }
    }

    @Test func everyRowHasADemoScenario() {
        func vm(_ scenario: TodayScenario) -> TodayViewModel {
            let state = AppState.preview(scenario: scenario)
            let sync = SyncService.ungated(env: state.env)
            return TodayViewModel(state: state, sync: sync,
                                  coordinator: SyncCoordinator(steps: LiveSyncSteps(state: state, sync: sync), clock: state.env.clock),
                                  apiStatus: APIStatus())
        }
        #expect(vm(.importing).hero.isImporting)
        #expect(vm(.calibrating).presentation.row == .calibrating && vm(.calibrating).gaugeNote == nil)
        let vitals = vm(.needsVitals)
        #expect(vitals.presentation.row == .calibrating && vitals.gaugeNote == .needsVitals)
        #expect(vitals.readiness == 80 && vitals.tileCaption == nil && vitals.recoveryText == Fmt.percent(75))
        let baselines = vm(.needsVitalsBaselines)
        #expect(baselines.hero == .calibrating(nights: 2) && baselines.gaugeNote == .needsVitals)
        let pending = vm(.pending)
        #expect(pending.presentation.row == .pending && pending.rawNight != nil && pending.tilesDimmed)
        let waiting = vm(.waitingForSleep)
        guard case .pending(let night) = waiting.hero else { Issue.record("expected pending"); return }
        #expect(night.waitingForSleep && waiting.rawNight == nil && waiting.tilesDimmed)
        let nothing = vm(.pendingNoPrevious)
        #expect(nothing.hero.isPending && nothing.sleepText == Fmt.placeholder && !nothing.tilesDimmed)
        let d = vm(.recalculating)
        #expect(d.presentation.row == .recalculating && d.readiness == 80 && !d.tilesDimmed && d.recoveryText == Fmt.percent(75))
        let dy = vm(.recalculatingYesterday)
        #expect(dy.presentation.row == .recalculating && dy.readiness == 76 && dy.tilesDimmed)
        #expect(vm(.watch).presentation.row == .scored)
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
        let sync = SyncService.ungated(env: state.env)
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
        let sync = SyncService.ungated(env: state.env)
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
        let sync = SyncService.ungated(env: state.env)
        let model = SyncDetailsModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        await sync.syncNow()
        let before = health.recentReads

        await model.resendRecent()

        #expect(health.recentReads == before + 1)
        #expect(!sync.engineState.recentRequested)
    }

    @Test func theScoringRowSaysSinceWhenAndWhetherItsSlow() {
        let (_, state, clock) = makeState()
        let sync = SyncService.ungated(env: state.env)
        let model = SyncDetailsModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        #expect(model.scoringText == String(localized: "Nothing waiting") && !model.scoringIsSlow)
        #expect(model.diagnostics.contains("scoring since - · expected 30 s · slow false"))

        sync.advance(to: .reading)
        sync.advance(to: .awaitingScores)
        let start = clock.now()
        state.syncStatus = SyncStatus(gate: nil, lastSyncAt: start, lastSyncDevice: "iPhone", latest: [:],
                                      today: TodayState(day: DayFormat.string(from: start), state: .pending, scoredAt: nil,
                                                        modelVersion: "2026.10.1"),
                                      pendingDays: [DayFormat.string(from: start)], expectedWithinSec: 20, resyncRequestedAt: nil)
        #expect(model.scoringText == String(localized: "Waiting since \(Fmt.time(start)) · usually \(20) s"))
        #expect(!model.scoringIsSlow)
        clock.advance(by: .seconds(61))
        #expect(!model.scoringIsSlow) // not before a read after the threshold
        sync.receive(state.syncStatus!)
        #expect(model.scoringIsSlow)
        #expect(model.diagnostics.contains("scoring since \(start.ISO8601Format()) · expected 20 s · slow true"))

        // The platform lists days this app isn't timing: it says so instead of "Nothing waiting".
        sync.accountChanged()
        #expect(model.scoringText == String(localized: "Pending: \(DayFormat.string(from: start))"))
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
        let vm = {
            let sync = SyncService.ungated(env: env)
            return ProfileViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()
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
        let vm = {
            let sync = SyncService.ungated(env: env)
            return ProfileViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()
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
        let vm = {
            let sync = SyncService.ungated(env: env)
            return ProfileViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()
        api.failure = APIError.http(429, "")
        await vm.bodySettings.rescore()
        #expect(vm.bodySettings.rescoreStatus == APIError.http(429, "").localizedDescription)
    }

    @Test func healthStatusComesFromTheStore() async {
        let health = MockHealthStore()
        health.access = .notAsked
        let (env, state, _) = makeState(health: health)
        let vm = {
            let sync = SyncService.ungated(env: env)
            return ProfileViewModel(state: state, sync: sync, coordinator: coordinator(state, sync), apiStatus: APIStatus())
        }()
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
        sync.gate = { _ in nil } // open: these tests are about what happens past it
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

    /// `devices.setup`: "What do you wear?" after About you, until answered or skipped once; the flag off, as before.
    static let wearCases: [(Facts, [OnboardingCoordinator.Step])] = [
        (Facts(userKnown: true, betaAccess: false, policyVersion: "v2", devicesSetup: true), [.consent, .aboutYou, .wear]),
        (Facts(userKnown: true, consentVersion: "v2", policyVersion: "v2", aboutYouDone: true, devicesSetup: true), [.wear]),
        (Facts(userKnown: true, consentVersion: "v2", policyVersion: "v2", aboutYouDone: true, wearAsked: true,
               devicesSetup: true), []),
        (Facts(userKnown: true, consentVersion: "v2", policyVersion: "v2", aboutYouDone: true, devicesSetup: false), []),
        // Nothing known (offline, nothing cached): nothing to ask.
        (Facts(devicesSetup: true), []),
    ]

    @Test(arguments: wearCases)
    func wear(facts: Facts, expected: [OnboardingCoordinator.Step]) {
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
        #expect(model.uploadGate(for: .healthKit) == .gate(.consentRequired))
        #expect(state.user != nil && api.count("syncStatus") == 1 && api.count("config") == 1)

        #expect(await model.agree())
        #expect(api.consentPosts == [MockData.policyVersion])
        #expect(starts.runs == 1) // the first sync starts right away
        #expect(model.uploadGate(for: .healthKit) == nil)
        #expect(model.flowStep == .aboutYou)

        #expect(await model.saveAboutYou(birthYear: 1990))
        #expect(state.user?.birthYear == 1990 && state.user?.maxHrSource == .estimated)
        #expect(model.flowStep == .aboutYou) // shows the estimate until Continue
        model.finishAboutYou()
        #expect(model.flowStep == nil)
    }

    /// Minimum age 16 (Art. 8 GDPR): the youngest year offered is this year − 16, valid under the
    /// platform's old (− 13) and new (− 16) check alike.
    @Test func birthYearsStopAtTheMinimumAgeOf16() throws {
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12)))
        let years = OnboardingCoordinator.birthYears(now: now)
        #expect(OnboardingCoordinator.minimumAge == 16)
        #expect(OnboardingCoordinator.latestBirthYear(now: now) == 2010)
        #expect(years.first == 2010 && years.last == 1920 && years.count == 91)
        #expect(!years.contains(2011) && !years.contains(1919))
        // New Year's Eve and Day: the bound moves with the calendar year.
        let eve = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23)))
        let day = try #require(Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 0, minute: 1)))
        #expect(OnboardingCoordinator.latestBirthYear(now: eve) == 2010)
        #expect(OnboardingCoordinator.latestBirthYear(now: day) == 2011)
    }

    @Test func aBirthYearUnder16IsRefusedWithTheRange() async {
        let api = MockPlatformAPI()
        let (model, state, _) = onboarding(api)
        await model.check()
        let latest = OnboardingCoordinator.latestBirthYear(now: .now)

        #expect(!(await model.saveAboutYou(birthYear: latest + 1)))
        #expect(model.errorMessage == String(localized: "Choose a year between 1920 and \(latest)."))
        #expect(state.user?.birthYear != latest + 1 && !model.aboutYouSaved)

        #expect(!(await model.saveAboutYou(birthYear: 1919)))
        #expect(await model.saveAboutYou(birthYear: 1920))
        #expect(await model.saveAboutYou(birthYear: latest))
        #expect(state.user?.birthYear == latest && model.errorMessage == nil)
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
        let sync = SyncService.ungated(env: env)
        sync.gate = { model.uploadGate(for: .healthKit) }
        await model.check()

        #expect(try await sync.upload() == [])
        #expect(sync.pausedFor == .gate(.consentRequired) && sync.lastError == nil)
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
        let sync = SyncService.ungated(env: .test(api: api, health: health)) // no gate wired: the platform refuses

        let touched = try? await sync.upload()

        #expect(touched == [])
        #expect(sync.pausedFor == .gate(.consentRequired) && sync.lastError == nil && sync.phase == .idle)
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
        #expect(model.sheetStep == nil && model.pendingGate == .consent && model.uploadGate(for: .healthKit) == .gate(.consentRequired))
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
        #expect(model.uploadGate(for: .healthKit) == .gate(.inviteRequired))

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
        #expect(model.flowStep == .invite && model.canDefer(.invite) && model.uploadGate(for: .healthKit) == nil)
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
        #expect(model.uploadGate(for: .healthKit) == nil)
        #expect(await model.withdrawConsent())
        #expect(model.uploadGate(for: .healthKit) == .gate(.consentRequired))
        #expect(model.sheetStep == nil) // asked again only from Profile or Today
        #expect(model.pendingGate == .consent)
    }

    // MARK: what do you wear (devices.setup)

    /// The flag on for this graph's flags.
    private func wearing(_ api: MockPlatformAPI = MockPlatformAPI(), flag: Bool = true)
        -> (OnboardingCoordinator, AppState) {
        let (model, state, _) = onboarding(api)
        (state.env.flags as? StaticFlags)?.overrides[.devicesSetup] = flag
        return (model, state)
    }

    @Test func whatDoYouWearComesAfterAboutYouAndBeforeAppleHealth() async {
        let (model, state) = wearing()
        await model.check()
        #expect(model.flowStep == .aboutYou)
        model.finishAboutYou()
        #expect(model.flowStep == .wear && !OnboardingCoordinator.Step.wear.isGate && model.canDefer(.wear))
        #expect(model.uploadGate(for: .healthKit) == nil) // not a gate: the sync doesn't wait for it

        model.answerWear(["oura", "garmin"])

        #expect(model.flowStep == nil) // RootView goes on to Apple Health
        #expect(model.devices.trackers == ["garmin", "oura"])
        // Answered for this account on this phone: not asked again after a relaunch.
        model.switchAccount(state.env.auth.accountID)
        #expect(model.wearAsked && model.missing.isEmpty)
    }

    @Test func skipSavesNothingAndDoesntAskAgain() async {
        let (model, _) = wearing()
        await model.check()
        model.finishAboutYou()
        model.later(.wear)
        #expect(model.flowStep == nil && model.devices.selection == nil && model.wearAsked)
        #expect(!model.showsTrackerSetup)
    }

    @Test func withTheFlagOffOnboardingIsAsBefore() async {
        let (model, _) = wearing(flag: false)
        await model.check()
        model.finishAboutYou()
        #expect(model.flowStep == nil && !model.missing.contains(.wear))
        model.devices.set(["garmin"])
        #expect(!model.showsTrackerSetup)
    }

    @Test func theSetupScreenFollowsAppleHealthForTrackersThatNeedIt() async {
        let (model, _) = wearing()
        await model.check()
        model.answerWear(["apple_watch"])
        #expect(!model.showsTrackerSetup) // the Apple Watch alone: nothing to set up elsewhere
        model.answerWear(["iphone"])
        #expect(!model.showsTrackerSetup)

        model.answerWear(["apple_watch", "garmin", "oura"])
        #expect(model.showsTrackerSetup && model.setupTrackers.map(\.id) == ["garmin", "oura"])
        model.devices.markLater("oura") // a card's "Show me again later"
        model.finishTrackerSetup(later: false)

        #expect(!model.showsTrackerSetup)
        #expect(model.devices.selection?.setUp == ["garmin"] && model.devices.selection?.later == ["oura"])
    }

    @Test func showMeAgainLaterPutsEveryGuideOff() async {
        let (model, _) = wearing()
        await model.check()
        model.answerWear(["garmin", "fitbit"])
        model.finishTrackerSetup(later: true)
        #expect(!model.showsTrackerSetup && model.devices.selection?.later == ["garmin", "fitbit"])
    }

    @Test func theSetupScreenBelongsToTheFirstRun() async {
        let (model, _) = wearing()
        await model.check()
        model.answerWear(["garmin"])
        model.reachedTabs()
        #expect(!model.showsTrackerSetup) // later it's Profile → Devices & sync
    }

    @Test func demoModeHasNoGates() async {
        let demo = OnboardingCoordinator(state: AppState.preview(), apiStatus: APIStatus()) {}
        await demo.check()
        #expect(demo.missing.isEmpty && !demo.holdsFirstRun)
        // HealthKit's client is the platform's: it holds in demo (privacy review S1). The others go to the mock.
        #expect(demo.uploadGate(for: .healthKit) == .demo)
        #expect(demo.uploadGate(for: .activities) == nil && demo.uploadGate(for: .train) == nil)
    }

    @Test func todaySaysWhatsNeededAndOpensTheStep() async {
        let api = MockPlatformAPI()
        api.accountConsent = nil
        let (env, state, _) = makeState(api: api)
        let model = OnboardingCoordinator(state: state, apiStatus: APIStatus()) {}
        model.reachedTabs()
        await model.check()
        model.later(.consent)
        let sync = SyncService.ungated(env: env)
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
        let sync = SyncService.ungated(env: env)
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
        #expect(model.uploadGate(for: .healthKit) == .gate(.consentRequired)) // a consent can't be assumed
        #expect(model.pendingGate == nil) // and it isn't the user's to fix
    }

    @Test func withdrawingClearsTheConsentEvenIfTheRecheckFails() async {
        let api = MockPlatformAPI()
        let (model, state, _) = onboarding(api, introDone: true)
        await model.check()
        api.failAfterRevoke = true
        #expect(await model.withdrawConsent())
        #expect(state.user?.consent == nil && model.uploadGate(for: .healthKit) == .gate(.consentRequired))
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
        let sync = SyncService.ungated(env: .test(api: api, health: health))
        let withdrawn = Flag()
        sync.gate = { withdrawn.isSet ? .gate(.consentRequired) : nil }
        api.afterSync = { withdrawn.set() } // consent withdrawn meanwhile

        _ = try? await sync.upload()

        #expect(api.count("sync") == 1 && health.committed.count == 1) // the second page stays
        #expect(sync.pausedFor == .gate(.consentRequired) && sync.lastError == nil)
    }

    @Test func trainKeepsWritesRefusedAtAGate() {
        #expect(TrainSyncService.isRetryable(.http(403, "", code: .inviteRequired)))
        #expect(TrainSyncService.isRetryable(.http(403, "", code: .consentRequired)))
        #expect(!TrainSyncService.isRetryable(.http(403, "built-in"))) // a real refusal is set aside
    }

    @Test func signInMethodsBelongToTheirAccount() async {
        let client = MockAuthClient(session: .preview(provider: "email"))
        let auth = AuthService(client: client, defaults: UserDefaults(suiteName: "ryft.test.\(UUID())") ?? .standard,
                               wipeLocalData: { _ in }, deleteRemoteAccount: { AccountDeleted(status: "deleted", authUserDeleted: true) },
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
        let sync = SyncService.ungated(env: env)
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

@Suite("Day loads and cancellation")
@MainActor
struct DayLoadCancellationTests {
    /// Code review should-fix 1: Strain's and Sleep's `.task(id:)` loads restart (are cancelled) when the
    /// day or the data changes; that shows no "The operation couldn't be completed".
    @Test func aCancelledDayLoadShowsNoError() async {
        let api = MockPlatformAPI()
        api.faults["day"] = .init(.cancel)
        let (_, state, _) = makeState(api: api)
        let strain = StrainViewModel(state: state, store: TrainStore(inMemory: true))
        await strain.load()
        #expect(strain.error == nil)
        let sleep = SleepViewModel(state: state)
        await sleep.load()
        #expect(sleep.error == nil)
        #expect(api.count("day") >= 1)                          // it was asked, and came back cancelled
    }
}
