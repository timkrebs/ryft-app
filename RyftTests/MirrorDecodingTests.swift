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
