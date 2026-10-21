import Foundation
import Testing
@testable import Ryft

/// The fields M4 (sleep), M5 (journal) and M7 (config, push) added to the
/// mirror, decoded from API.md's JSON examples (`Fixtures/`).
struct MirrorDecodingTests {
    @Test func dailyScoreHasTheNeedByTermQualityConsistencyAndNaps() throws {
        let s = try Fixture.decode([DailyScore].self, "days")[0]
        #expect(s.sleepNeedBaseMin == 460 && s.sleepNeedStrainMin == 37)
        #expect(s.sleepNeedDebtMin == 41 && s.sleepNeedNapMin == 0)
        #expect(s.napMin == 25 && s.sleepQuality == 91 && s.sleepConsistency == 81)
        // Older days without the fields stay nil.
        #expect(try Fixture.decode([DailyScore].self, "days")[1].sleepQuality == nil)
    }

    @Test func dayDetailSleepHasNeedAndRestorative() throws {
        let sleep = try #require(try Fixture.decode(DayDetail.self, "day_detail").sleep)
        #expect(sleep.need == SleepNeed(base: 460, strain: 37, debt: 41, napCredit: 0, total: 538))
        #expect(sleep.restorative == 100 && sleep.quality == 91 && sleep.qualityLabel == .good)
    }

    @Test func dayStrainHasMuscularLoadAndSessions() throws {
        let strain = try #require(try Fixture.decode(DayDetail.self, "day_detail").strain)
        #expect(strain.muscularTrimp == 55)
        #expect(strain.sessions?.isEmpty == false)
    }

    @Test func sleepRangeHasConsistencyNapsAndBedtimes() throws {
        let r = try Fixture.decode(SleepRange.self, "sleep_range")
        #expect(r.avgConsistency == 84)
        #expect(r.days[0].consistency == 84 && r.days[0].napMin == 0 && r.days[0].restorative == 96)
        #expect(r.days[1].consistency == nil && r.days[1].napMin == 30)
        #expect(r.bedtimes.map(\.day) == ["2026-10-12", "2026-10-14"])
        #expect(r.bedtimes[0].wake > r.bedtimes[0].bed)
    }

    @Test func sleepPlan() throws {
        let p = try Fixture.decode(SleepPlan.self, "sleep_plan")
        #expect(p.needMin == 512 && p.inBedMin == 569 && p.efficiency == 90)
        #expect(p.bedtime100 < p.bedtime85 && p.bedtime85 < p.bedtime70 && p.bedtime70 < p.wake)
        #expect(p.basis == SleepPlanBasis(base: 460, strainTopup: 36, debtTopup: 16, napCredit: 0, efficiency: 90))
    }

    @Test func userBaselineSourceAndNotifications() throws {
        let u = try Fixture.decode(User.self, "me")
        #expect(u.sleepBaseSource == .learned && u.sleepBaseLearnedMin == 455)
        #expect(u.sleepBaseLearnedAt != nil)
        #expect(u.notifications.isOn(.pr) == false && u.notifications.quietHours?.from == "22:30")
    }

    @Test func userPatchSendsSleepBaseManual() throws {
        let json = try #require(String(data: APIClient.jsonEncoder.encode(UserPatch(sleepBaseManual: false)),
                                       encoding: .utf8))
        #expect(json == #"{"sleep_base_manual":false}"#)
    }

    @Test func remoteConfigTTL() throws {
        let c = try Fixture.decode(RemoteConfig.self, "remote_config")
        #expect(c.ttlSec == 21_600 && c.flags["sleep.planner"] == true)
    }

    @Test func behaviors() throws {
        let list = try Fixture.decode([Behavior].self, "behaviors")
        #expect(list.map(\.kind) == [.yesNo, .time])
        #expect(list[0].category == .substances && list[0].enabled && !list[0].isCustom)
        #expect(list[1].nameDe == "Letztes Koffein" && !list[1].enabled)
    }

    @Test func journalDay() throws {
        let d = try Fixture.decode(JournalDay.self, "journal_day")
        #expect(d.answered && d.editable && d.answeredAt != nil)
        #expect(d.entries.count == 4)
        #expect(d.entries[1].valueNum == 2 && d.entries[2].valueTime == "16:30")
        #expect(d.entries[3].valueBool == false)
    }

    @Test func journalPutSendsEveryRowWithNulls() throws {
        let put = JournalPut(entries: [JournalEntry(behaviorId: MockJournal.alcohol, valueBool: false)])
        let json = try #require(String(data: APIClient.jsonEncoder.encode(put), encoding: .utf8))
        #expect(json.contains(#""behavior_id":"BAD67883"#) || json.contains(#""behavior_id":"bad67883"#))
        #expect(json.contains(#""value_bool":false"#))
        #expect(json.contains(#""value_num":null"#) && json.contains(#""value_time":null"#))
    }

    @Test func behaviorsPatchUsesLowercaseIDs() throws {
        let json = try #require(String(data: APIClient.jsonEncoder.encode(BehaviorsPatch([MockJournal.sauna: true])),
                                       encoding: .utf8))
        #expect(json == #"{"enabled":{"ce48b6cf-43e3-5c6b-baf9-0a13e5d767d9":true}}"#)
    }

    @Test func behaviorImpact() throws {
        let i = try Fixture.decode(BehaviorImpacts.self, "behavior_impact")
        #expect(i.windowDays == 90)
        #expect(i.impacts.map(\.status) == [.unlocked, .locked])
        let alcohol = i.impacts[0]
        #expect(alcohol.recovery?.delta == -14.2 && alcohol.recovery?.significant == true)
        #expect(alcohol.hrvPct?.nNo == 30 && alcohol.sleepPerformance?.significant == false)
        #expect(i.impacts[1].needed == ImpactNeeded(yes: 3, no: 0) && i.impacts[1].recovery == nil)
    }

    @Test func newTrendMetricsMatchTheAPI() {
        for raw in ["sleep_quality", "sleep_consistency", "nap_min", "strength_min", "volume_kg"] {
            #expect(TrendMetric(rawValue: raw) != nil, "\(raw)")
        }
    }

    @Test func insightKindsAreOpen() {
        #expect(InsightKind(rawValue: "nap-credit") == .napCredit)
        #expect(InsightKind(rawValue: "behavior-impact").systemImage != "info.circle")
        #expect(InsightKind(rawValue: "something-new") == .other("something-new"))
        #expect(InsightKind(rawValue: "something-new").systemImage == "info.circle")
    }

    @Test func m4FieldsSurviveTheReadModelCache() throws {
        let d = try Fixture.decode(DayDetail.self, "day_detail")
        let back = try #require(WireCoding.decode(DayDetail.self, WireCoding.encode(d)))
        #expect(back.sleep?.need == d.sleep?.need && back.score.sleepConsistency == 81)
        let r = try Fixture.decode(SleepRange.self, "sleep_range")
        #expect(WireCoding.decode(SleepRange.self, WireCoding.encode(r))?.bedtimes.count == 2)
    }
}

/// The Beta and "Accounts and sync state" shapes (API.md changelog, 2026-10-20),
/// decoded from API.md's examples: fixtures where a file exists, the example inline
/// for the new endpoints.
struct BetaMirrorDecodingTests {
    /// `GET /v1/me/sync`, as API.md shows it.
    static let syncStatusExample = """
    { "gate": null, "last_sync_at": "2026-10-21T06:58:12Z", "last_sync_device": "iPhone",
      "latest": { "hr": "2026-10-21T06:55:00Z", "hrv": "2026-10-21T04:10:00Z", "sleep": "2026-10-21T06:41:00Z",
                  "steps": "2026-10-21T06:50:00Z", "workout": "2026-10-20T18:45:00Z" },
      "today": { "day": "2026-10-21", "state": "pending", "scored_at": null, "model_version": "2026.10.1" },
      "pending_days": ["2026-10-21"], "expected_within_sec": 20, "resync_requested_at": null }
    """

    @Test func userCarriesAccessConsentSourcesAndTheHint() throws {
        let u = try Fixture.decode(User.self, "me")
        #expect(u.betaAccess && u.birthYear == 1990 && u.maxHrSource == .estimated)
        #expect(u.consent?.policyVersion == "2026-10-20" && u.consent?.grantedAt != nil)
        #expect(u.accountHint == nil)
        #expect(u.sources.map(\.name) == ["Tim's Apple Watch", "Tim's iPhone"])
        #expect(u.sources[0].kinds.contains(.hrv) && u.sources[1].kinds == [.steps])
        #expect(u.hasConsented(to: "2026-10-20") && !u.hasConsented(to: "2026-11-01"))
    }

    @Test func accountHintAndUnknownSourceKinds() throws {
        let json = #"""
        {"id":"5f0e8c1a-6c1b-4a4e-9d55-1f1d2f6a3b7c","name":"","tz":"Europe/Berlin","max_hr":190,"sleep_base_min":460,
         "beta_access":false,"consent":null,"max_hr_source":"default",
         "sources":[{"name":"Ring","bundle_id":null,"kinds":["hr","temperature"],"last_seen":"2026-10-20T06:58:00Z"}],
         "account_hint":{"kind":"other_account_on_device","other_provider":"email","other_last_sync":"2026-10-20T06:58:00Z"}}
        """#
        let u = try APIClient.jsonDecoder.decode(User.self, from: Data(json.utf8))
        #expect(!u.betaAccess && u.consent == nil && !u.hasConsented(to: "2026-10-20"))
        #expect(u.accountHint?.otherProvider == "email" && u.accountHint?.kind == "other_account_on_device")
        #expect(u.sources[0].kinds == [.hr]) // a kind this build doesn't know is dropped
    }

    @Test func aCachedUserFromBeforeTheBetaHasAccessAndNoConsent() throws {
        let json = #"{"id":"5f0e8c1a-6c1b-4a4e-9d55-1f1d2f6a3b7c","name":"","tz":"Europe/Berlin","max_hr":190,"sleep_base_min":460}"#
        let u = try APIClient.jsonDecoder.decode(User.self, from: Data(json.utf8))
        #expect(u.betaAccess && u.consent == nil && u.sources.isEmpty && u.maxHrSource == .default)
    }

    @Test func syncResponseCountsWhatWasIgnoredAndQueued() throws {
        let r = try Fixture.decode(SyncResponse.self, "sync_response")
        #expect(r.accepted == SyncCounts(samples: 1380, sleep: 14, workouts: 1))
        #expect(r.ignored.samples == IgnoredCounts(duplicate: 58, outsideWindow: 0, unknownType: 2))
        #expect(r.scoring == SyncScoring(queuedDays: ["2026-10-17", "2026-10-18"], expectedWithinSec: 20))
    }

    @Test func syncStatus() throws {
        let s = try APIClient.jsonDecoder.decode(SyncStatus.self, from: Data(Self.syncStatusExample.utf8))
        #expect(s.gate == nil && s.lastSyncDevice == "iPhone" && s.lastSyncAt != nil)
        #expect(s.latest.keys.sorted() == ["hr", "hrv", "sleep", "steps", "workout"])
        #expect(s.today.state == .pending && s.today.scoredAt == nil && s.today.modelVersion == "2026.10.1")
        #expect(s.pendingDays == ["2026-10-21"] && s.expectedWithinSec == 20 && s.resyncRequestedAt == nil)
    }

    @Test func syncStatusGate() throws {
        func gate(_ value: String) throws -> APIErrorCode? {
            let json = Self.syncStatusExample.replacingOccurrences(of: #""gate": null"#, with: #""gate": \#(value)"#)
            return try APIClient.jsonDecoder.decode(SyncStatus.self, from: Data(json.utf8)).gate
        }
        #expect(try gate(#""invite_required""#) == .inviteRequired)
        #expect(try gate(#""consent_required""#) == .consentRequired)
        #expect(try gate(#""age_required""#) == nil) // unknown: no gate this build could show
    }

    @Test func remoteConfigNamesThePolicyInForce() throws {
        let c = try Fixture.decode(RemoteConfig.self, "remote_config")
        #expect(c.privacyPolicyVersion == "2026-10-20" && c.privacyPolicyUrl == "https://ryftapp.de/privacy")
        // A config cached before the Beta still decodes.
        let old = #"{"flags":{},"evaluated_at":"2026-10-19T06:12:00Z","ttl_sec":21600}"#
        #expect(try APIClient.jsonDecoder.decode(RemoteConfig.self, from: Data(old.utf8)).privacyPolicyVersion == nil)
    }

    @Test func dailyScoreScoringStateAndModel() throws {
        let days = try Fixture.decode([DailyScore].self, "days")
        #expect(days[0].scoringState == .scored && days[0].modelVersion == "2026.10.1")
        #expect(days[1].scoringState == nil && days[1].modelVersion == nil) // cached before the fields
        let pending = #"{"day":"2026-10-21","state":"calibrating","baseline_days":0,"calibrating":false,"scoring_state":"waiting_for_sleep"}"#
        #expect(try APIClient.jsonDecoder.decode(DailyScore.self, from: Data(pending.utf8)).scoringState == .waitingForSleep)
        let back = try #require(WireCoding.decode(DailyScore.self, WireCoding.encode(days[0])))
        #expect(back.scoringState == .scored && back.modelVersion == "2026.10.1")
    }

    @Test func errorBodyCodes() throws {
        let plain = try Fixture.decode(APIErrorBody.self, "error")
        #expect(plain.code == nil && plain.requestId == "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c")
        func code(_ json: String) throws -> APIErrorCode? {
            try APIClient.jsonDecoder.decode(APIErrorBody.self, from: Data(json.utf8)).code
        }
        #expect(try code(#"{ "error": "consent required", "code": "consent_required", "request_id": "01a1" }"#) == .consentRequired)
        #expect(try code(#"{ "error": "invite required", "code": "invite_required" }"#) == .inviteRequired)
        #expect(try code(#"{ "error": "x", "code": "something_new" }"#) == nil)
    }

    @Test func modelInfo() throws {
        let json = #"""
        { "current": "2026.10.1",
          "changelog": [ { "version": "2026.10.1", "date": "2026-10-20",
                           "summary": "The model at the start of the beta: …",
                           "summary_en": "The model at the start of the beta: …",
                           "summary_de": "Das Modell zum Start der Beta: …",
                           "affects": ["readiness", "recovery", "strain", "sleep", "sleep_quality"] } ] }
        """#
        let m = try APIClient.jsonDecoder.decode(ModelInfo.self, from: Data(json.utf8))
        #expect(m.current == "2026.10.1" && m.changelog[0].summaryDe.hasPrefix("Das Modell"))
        #expect(m.changelog[0].affects.count == 5)
    }

    @Test func requestBodies() throws {
        func json<T: Encodable>(_ value: T) throws -> String {
            try #require(String(data: APIClient.jsonEncoder.encode(value), encoding: .utf8))
        }
        #expect(try json(InvitePost(code: "RYFT-7K3M-QX9P")) == #"{"code":"RYFT-7K3M-QX9P"}"#)
        let consent = try json(ConsentPost(policyVersion: "2026-10-20", appVersion: "0.9.0 (41)"))
        #expect(consent.contains(#""policy_version":"2026-10-20""#) && consent.contains(#""app_version":"0.9.0 (41)""#))
        let patch = try json(UserPatch(maxHrManual: false, birthYear: 1990))
        #expect(patch.contains(#""birth_year":1990"#) && patch.contains(#""max_hr_manual":false"#))
        #expect(!patch.contains("tz") && !patch.contains("sleep_base"))
    }

    @Test func syncRequestSendsVersionsAndBundleIDs() throws {
        let sample = Sample(type: .heartRate, start: .now, end: .now, value: 60, unit: "bpm", source: "Watch",
                            sourceBundleId: "com.apple.health.81E2")
        let req = SyncRequest(deviceId: UUID(), deviceName: "iPhone", appVersion: "1.0.0 (1)", osVersion: "iOS 27.1",
                              samples: [sample], sleep: [], workouts: [])
        let json = try #require(String(data: APIClient.jsonEncoder.encode(req), encoding: .utf8))
        #expect(json.contains(#""app_version":"1.0.0 (1)""#) && json.contains(#""os_version":"iOS 27.1""#))
        #expect(json.contains(#""source_bundle_id":"com.apple.health.81E2""#))
    }
}
