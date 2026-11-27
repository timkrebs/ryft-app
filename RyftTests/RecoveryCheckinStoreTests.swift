import Foundation
import Testing
@testable import Ryft

@MainActor
private struct RecoveryRig {
    let api = MockPlatformAPI()
    let apiStatus = APIStatus()
    let env: AppEnvironment
    let store: RecoveryCheckinStore

    init(flag: Bool = true, online: Bool = true) {
        let date = Date(timeIntervalSince1970: 1_795_737_600)
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        env = .test(api: api, clock: TestClock(now: now), flags: [.recoveryCheckin: flag], online: online)
        store = RecoveryCheckinStore(env: env, apiStatus: apiStatus)
    }

    static func answer(now: Date, rating: Int = 7, hours: Int = 8) -> RecoveryCheckinPut {
        let wake = now.addingTimeInterval(-15 * 60)
        return RecoveryCheckinPut(bedtime: wake.addingTimeInterval(Double(-hours * 3600)), wakeTime: wake,
                                 tzOffsetSec: TimeZone.current.secondsFromGMT(for: wake),
                                 perceivedSleepQuality: rating, perceivedFreshness: rating, soreness: false)
    }

    var answer: RecoveryCheckinPut { Self.answer(now: store.now) }

    func save() async throws -> RecoveryCheckinStore.SaveResult {
        try await store.save(date: store.today, body: answer, as: store.owner)
    }

    var diskPending: [RecoveryCheckinStore.Pending]? {
        env.persistence.document([RecoveryCheckinStore.Pending].self, key: RecoveryCheckinStore.pendingKey)
    }
}

@Suite("Morning check-in store")
@MainActor
struct RecoveryCheckinStoreTests {
    @Test func flagOffSendsNothingEvenWithAnOutbox() async {
        let rig = RecoveryRig(flag: false)
        let pending = [RecoveryCheckinStore.Pending(date: rig.store.today, body: rig.answer)]
        rig.env.persistence.saveDocument(pending, key: RecoveryCheckinStore.pendingKey, at: rig.store.now)
        await rig.store.load()
        await #expect(throws: CancellationError.self) { try await rig.save() }
        rig.store.skip()
        #expect(rig.api.calls.isEmpty && rig.store.card == nil)
        #expect(rig.diskPending == pending)
        #expect(!FeatureFlag.recoveryCheckin.compiledDefault)
    }

    @Test func wearableAndSupersededAlwaysWin() throws {
        let fixture = try Fixture.decode(RecoveryStatus.self, "recovery_status_checkin")
        let sample = try #require(fixture.checkin)
        let wearable = RecoveryStatus(date: fixture.date, source: .wearable, confidence: .high, recoveryScore: 88,
                                      needsCheckin: false, checkin: nil, suggestedBedtime: nil, suggestedWakeTime: nil,
                                      suggestionBasis: nil)
        let history = RecoveryCheckin(date: sample.date, bedtime: sample.bedtime, wakeTime: sample.wakeTime,
                                      tzOffsetSec: sample.tzOffsetSec, perceivedSleepQuality: 3, perceivedFreshness: 4,
                                      soreness: false, sleepDurationMin: 300, recoveryScore: 31, components: sample.components,
                                      acuteDrop: true, confounders: [], confidence: .low, superseded: true,
                                      n2rBedtimeApplied: true, modelVersion: sample.modelVersion, createdAt: sample.createdAt,
                                      updatedAt: sample.updatedAt)
        let superseded = RecoveryStatus(date: fixture.date, source: .checkin, confidence: .low, recoveryScore: 31,
                                        needsCheckin: false, checkin: history, suggestedBedtime: nil, suggestedWakeTime: nil,
                                        suggestionBasis: nil)
        for status in [wearable, superseded] {
            #expect(RecoveryCheckinStore.card(flag: true, today: fixture.date, status: status, pending: true, skipped: false) == nil)
        }
    }

    @Test func dueThenSkipPersistsAndMakesNoRequest() async {
        let rig = RecoveryRig()
        await rig.store.load()
        #expect(rig.store.card == .due)
        rig.store.skip()
        #expect(rig.store.card == .skipped && rig.api.calls == ["recoveryStatus"])
        rig.env.connectivityMonitor.update(false)
        let relaunched = RecoveryCheckinStore(env: rig.env)
        await relaunched.load()
        #expect(relaunched.card == .skipped && rig.api.calls == ["recoveryStatus"])
    }

    @Test func beforeCheckinIsDueThereIsNoCard() async {
        let rig = RecoveryRig()
        rig.api.recoveryStatusOverride = RecoveryStatus(date: rig.store.today, source: .none, confidence: nil, recoveryScore: nil,
                                                       needsCheckin: false, checkin: nil, suggestedBedtime: nil, suggestedWakeTime: nil,
                                                       suggestionBasis: nil)
        await rig.store.load()
        #expect(rig.store.card == nil)
    }

    @Test func successfulSaveShowsTheReturnedCheckin() async throws {
        let rig = RecoveryRig()
        await rig.store.load()
        #expect(try await rig.save() == .saved)
        let checkin = try #require(rig.store.status?.checkin)
        #expect(checkin.perceivedSleepQuality == 7)
        #expect(rig.store.card == .done(checkin) && rig.diskPending == nil)
    }

    @Test func offlineSaveRetriesAndClearsThePersistedOutbox() async throws {
        let rig = RecoveryRig()
        await rig.store.load()
        rig.env.connectivityMonitor.update(false)
        #expect(try await rig.save() == .waiting)
        #expect(rig.store.card == .waiting)
        #expect(rig.diskPending?.map(\.body) == [rig.answer] && rig.api.count("putRecoveryCheckin") == 0)

        rig.env.connectivityMonitor.update(true)
        await rig.store.load()
        #expect(rig.api.calls == ["recoveryStatus", "putRecoveryCheckin", "recoveryStatus"])
        #expect(rig.store.pending.isEmpty && rig.diskPending == nil)
        let checkin = try #require(rig.store.status?.checkin)
        #expect(rig.store.card == .done(checkin))
    }

    @Test(arguments: [401, 408, 429, 500, 501, 503])
    func retryableFailuresKeepAnAnswer(_ status: Int) async throws {
        let rig = RecoveryRig()
        await rig.store.load()
        rig.api.failNext = APIError.http(status, "")
        #expect(try await rig.save() == .waiting)
        #expect(rig.diskPending?.count == 1 && rig.store.card == .waiting)
    }

    @Test func transportTimeoutKeepsAnAnswer() async throws {
        let rig = RecoveryRig()
        await rig.store.load()
        rig.api.failNext = APIError.transport(URLError(.timedOut))
        #expect(try await rig.save() == .waiting)
        #expect(rig.diskPending?.count == 1 && rig.store.card == .waiting)
    }

    @Test func editPrefillsTheCheckinsOwnClock() throws {
        let rig = RecoveryRig()
        let status = try Fixture.decode(RecoveryStatus.self, "recovery_status_checkin")
        let model = CheckinSheetModel(store: rig.store, status: status, canSkip: false, timeZone: .gmt)
        #expect(model.wakeDay == status.date && model.bed == 100 && model.wake == 400)
        #expect(model.quality == 3 && model.freshness == 4 && !model.soreness && !model.canSkip)
    }

    /// Review blocker: a check-in saved in Berlin (+01:00) and edited in New York keeps its times. Answers alone send the
    /// stored instants; a moved handle is composed on the check-in's own clock, never on New York's.
    @Test func editInAnotherTimeZoneKeepsTheTimes() async throws {
        let rig = RecoveryRig(online: false)
        let status = try Fixture.decode(RecoveryStatus.self, "recovery_status_checkin")
        let stored = try #require(status.checkin)
        let newYork = try #require(TimeZone(identifier: "America/New_York"))

        let answersOnly = CheckinSheetModel(store: rig.store, status: status, canSkip: false, timeZone: newYork)
        #expect(answersOnly.bed == 100 && answersOnly.wake == 400)
        answersOnly.quality = 6
        #expect(await answersOnly.save())
        let first = try #require(rig.store.pending.first?.body)
        #expect(first.bedtime == stored.bedtime && first.wakeTime == stored.wakeTime && first.tzOffsetSec == 3600)
        #expect(first.perceivedSleepQuality == 6)

        let moved = CheckinSheetModel(store: rig.store, status: status, canSkip: false, timeZone: newYork)
        moved.wake += 5
        #expect(await moved.save())
        let second = try #require(rig.store.pending.first?.body)
        #expect(second.wakeTime == stored.wakeTime.addingTimeInterval(5 * 60) && second.bedtime == stored.bedtime)
        #expect(second.tzOffsetSec == 3600)
    }

    /// The clock rule: this iPhone's zone when it had the stored offset at the wake (a DST night keeps its bedtime on its
    /// own side of the change), else the fixed offset.
    @Test func checkinClockFollowsTheStoredOffset() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let wake = try #require(ISO8601DateFormatter().date(from: "2026-10-25T06:00:00Z")) // 07:00 CET, after the change
        #expect(SleepDialMath.clock(ofCheckinOffset: 3600, wakeTime: wake, current: berlin) == berlin)
        let bed = try #require(ISO8601DateFormatter().date(from: "2026-10-24T21:00:00Z")) // 23:00 CEST
        #expect(SleepDialMath.minutes(of: bed, timeZone: berlin) == 23 * 60)
        let other = SleepDialMath.clock(ofCheckinOffset: 3600, wakeTime: wake, current: .gmt)
        #expect(other.secondsFromGMT(for: wake) == 3600 && other != .gmt)
    }

    /// A `404` on a save (the flag went off meanwhile) hides the feature but keeps the answer on this iPhone.
    @Test func a404OnSaveKeepsTheAnswer() async throws {
        let rig = RecoveryRig()
        await rig.store.load()
        rig.api.failNext = APIError.http(404, "")
        #expect(try await rig.save() == .unavailable)
        #expect(rig.store.availability == .notLive && rig.diskPending?.map(\.body) == [rig.answer])
    }

    @Test func rejectedSaveStaysInlineAndNeverQueues() async throws {
        let rig = RecoveryRig()
        await rig.store.load()
        rig.api.failNext = APIError.http(422, "Check the wake day.", requestID: "test")
        do {
            _ = try await rig.save()
            Issue.record("The field error should be thrown")
        } catch let error as RecoveryWriteError {
            #expect(error.message == "Check the wake day." && error.details?.contains("test") == true)
        }
        #expect(rig.diskPending == nil && rig.store.card == .due)
    }

    @Test func rejectedPendingAnswerIsDroppedAndCanBeDismissed() async throws {
        let rig = RecoveryRig()
        await rig.store.load()
        rig.env.connectivityMonitor.update(false)
        #expect(try await rig.save() == .waiting)
        rig.env.connectivityMonitor.update(true)
        rig.api.failNext = APIError.http(422, "")
        await rig.store.load()
        #expect(rig.diskPending == nil && rig.store.rejectedDate == rig.store.today)
        rig.store.dismissRejection()
        #expect(rig.store.rejectedDate == nil)
    }

    @Test func aStatus404HidesAndLeavesTheOutboxUnsent() async {
        let rig = RecoveryRig(online: false)
        let pending = [RecoveryCheckinStore.Pending(date: rig.store.today, body: rig.answer)]
        rig.env.persistence.saveDocument(pending, key: RecoveryCheckinStore.pendingKey, at: rig.store.now)
        await rig.store.load()
        #expect(rig.store.card == .waiting)
        rig.env.connectivityMonitor.update(true)
        rig.api.failure = APIError.http(404, "")
        await rig.store.load()
        await rig.store.load()
        #expect(rig.store.card == nil && rig.store.availability == .notLive)
        #expect(rig.diskPending == pending && rig.api.calls == ["recoveryStatus", "recoveryStatus"])
    }

    @Test func consentRefusalKeepsTheAnswerUntilTheGateOpens() async throws {
        let rig = RecoveryRig()
        await rig.store.load()
        rig.api.failNext = APIError.http(403, "", code: .consentRequired)
        #expect(try await rig.save() == .consentRequired)
        #expect(rig.diskPending?.count == 1 && rig.apiStatus.gates.contains(.consentRequired))
        // Online, so not "when you're online": it waits for the consent.
        #expect(rig.store.card == .waitingForConsent)
        await rig.store.load()
        #expect(rig.api.count("putRecoveryCheckin") == 1)
        rig.apiStatus.resolved(.consentRequired)
        await rig.store.load()
        #expect(rig.api.count("putRecoveryCheckin") == 2 && rig.diskPending == nil)
    }

    @Test func theNextAccountNeverShowsOrSendsThePriorAnswers() async throws {
        let harness = WipeHarness()
        let api = try #require(harness.env.liveAPI as? MockPlatformAPI)
        let flags = try #require(harness.env.flags as? StaticFlags)
        flags.overrides[.recoveryCheckin] = true
        let store = RecoveryCheckinStore(state: harness.state, apiStatus: APIStatus())
        await store.load()
        #expect(store.card == .due)
        harness.env.connectivityMonitor.update(false)
        let answer = RecoveryRig.answer(now: store.now)
        let priorOwner = store.owner
        #expect(try await store.save(date: store.today, body: answer, as: priorOwner) == .waiting)
        await harness.auth.signOut()
        await harness.signIn(WipeHarness.b)
        #expect(store.card == nil && store.status == nil && store.pending.isEmpty)
        #expect(harness.persistence.document([RecoveryCheckinStore.Pending].self, key: RecoveryCheckinStore.pendingKey) == nil)
        harness.env.connectivityMonitor.update(true)
        await store.load()
        await #expect(throws: CancellationError.self) { try await store.save(date: store.today, body: answer, as: priorOwner) }
        #expect(api.count("putRecoveryCheckin") == 0 && store.card == .due)
    }

    @Test func yesterdayIsNeverDueOfflineAndExpiredEntriesAreDropped() async {
        let rig = RecoveryRig(online: false)
        let yesterday = DayFormat.string(from: DayFormat.shift(rig.store.now, days: -1))
        let status = RecoveryStatus(date: yesterday, source: .none, confidence: nil, recoveryScore: nil, needsCheckin: true,
                                    checkin: nil, suggestedBedtime: "23:00", suggestedWakeTime: "07:00", suggestionBasis: nil)
        let expired = DayFormat.string(from: DayFormat.shift(rig.store.now, days: -15))
        rig.env.persistence.saveDocument(status, key: RecoveryCheckinStore.statusKey, at: rig.store.now)
        rig.env.persistence.saveDocument([RecoveryCheckinStore.Pending(date: expired, body: rig.answer)],
                                         key: RecoveryCheckinStore.pendingKey, at: rig.store.now)
        await rig.store.load()
        #expect(rig.store.status == status && rig.store.card == nil && rig.api.calls.isEmpty)
        #expect(rig.diskPending == nil)
    }

    @Test func mockScoresFollowTheNoHistoryExamples() async throws {
        let rig = RecoveryRig()
        let short = try await rig.api.putRecoveryCheckin(date: rig.store.today, RecoveryRig.answer(now: rig.store.now, rating: 3, hours: 5))
        let long = try await rig.api.putRecoveryCheckin(date: rig.store.today, RecoveryRig.answer(now: rig.store.now, rating: 9))
        #expect(short.recoveryScore == 29 && long.recoveryScore == 93)
        #expect(try await rig.api.recoveryCheckin(date: rig.store.today) == long)
    }
}
