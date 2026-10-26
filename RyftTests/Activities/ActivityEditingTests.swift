import Foundation
import SwiftData
import Testing
@testable import Ryft

// A2's forms and detail on the test graph: what Add activity, Add sleep, Edit and Delete write through the store and
// the uploader, and the rules that keep Save disabled. (test-engineer's suites cover the full tables.)

@MainActor
private struct Graph {
    let clock: TestClock
    let api: MockPlatformAPI
    let env: AppEnvironment
    let state: AppState

    init() {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
        clock = TestClock(now: noon)
        api = MockPlatformAPI(activities: MockActivitiesSource(now: { [clock] in clock.now() }))
        env = .test(api: api, clock: clock, flags: [.todayMyDay: true, .activitiesManual: true])
        state = AppState(env: env)
    }

    var today: Date { Calendar.current.startOfDay(for: clock.now()) }
}

@Suite("Activities: add and edit")
@MainActor
struct AddActivityModelTests {
    @Test func addingTodayDefaultsToTheLastHourAndSavesOnThisIPhone() throws {
        let g = Graph()
        let model = AddActivityModel(env: g.env, day: g.today)
        #expect(model.end <= g.clock.now() && model.end.timeIntervalSince(model.start) == 3_600)
        #expect(model.sport == .running, "no recents yet")
        model.sport = .yoga
        model.effort = 5
        model.notes = "  Flow  "

        #expect(model.save())

        let rows = g.env.activities.snapshots(onDay: DayFormat.string(from: g.today))
        let row = try #require(rows.first)
        #expect(rows.count == 1 && row.sport == .yoga && row.origin == .manual && row.perceivedEffort == 5)
        #expect(row.notes == "Flow" && row.needsUpload)
        #expect(ActivityPreferences(env: g.env).recentSports.first == .yoga)
    }

    @Test func aPastDayDefaultsToNoonAndCanGoBackFourteenDays() {
        let g = Graph()
        let past = DayFormat.shift(g.today, days: -3)
        let model = AddActivityModel(env: g.env, day: past)
        #expect(Calendar.current.component(.hour, from: model.start) == 12)
        #expect(Calendar.current.isDate(model.start, inSameDayAs: past))
        #expect(model.earliest == DayFormat.shift(g.today, days: -AddActivityModel.daysBack))
        #expect(model.canSave)
    }

    @Test func theRulesKeepSaveDisabledWithTheirReasons() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let earliest = now.addingTimeInterval(-14 * 86_400)
        func issues(_ start: TimeInterval, _ end: TimeInterval, distance: String = "", notes: String = "")
            -> [AddActivityModel.Issue] {
            AddActivityModel.issues(start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), now: now,
                                    earliest: earliest, distanceText: distance, notes: notes)
        }
        #expect(issues(-3_600, 0).isEmpty)
        #expect(issues(-3_600, 60) == [.endInFuture])
        #expect(issues(-600, -1_200) == [.endBeforeStart])
        #expect(issues(-90_000, -600) == [.longerThanADay])
        #expect(issues(-15 * 86_400, -15 * 86_400 + 600) == [.startTooEarly])
        #expect(issues(-3_600, 0, distance: "0") == [.distanceInvalid])
        #expect(issues(-3_600, 0, distance: "abc") == [.distanceInvalid])
        #expect(issues(-3_600, 0, notes: String(repeating: "x", count: 501)) == [.notesTooLong])
        // Measured times aren't checked: a recorded activity's notes still are.
        #expect(AddActivityModel.issues(start: now, end: now.addingTimeInterval(-60), now: now, earliest: earliest,
                                        distanceText: "", notes: "", checksTimes: false).isEmpty)
    }

    @Test func tooFastWarnsButNeverBlocks() {
        #expect(AddActivityModel.isTooFast(sport: .running, distanceM: 60_000, duration: 3_600))
        #expect(!AddActivityModel.isTooFast(sport: .running, distanceM: 10_000, duration: 3_600))
        #expect(!AddActivityModel.isTooFast(sport: .yoga, distanceM: 60_000, duration: 3_600), "no ceiling")
        let g = Graph()
        let model = AddActivityModel(env: g.env, day: g.today)
        model.distanceText = "60"
        #expect(model.isTooFast && model.canSave)
    }

    @Test func editingThePlatformsActivityMakesItTheAccountsRowFirst() throws {
        let g = Graph()
        let start = g.today.addingTimeInterval(7 * 3_600)
        let server = SportActivity(id: UUID(), sport: .running, origin: .manual, start: start, end: start.addingTimeInterval(2_400),
                                   movingSec: 2_400, distanceM: 7_000, clientUpdatedAt: start, strain: 9, scoringState: "scored")
        let model = AddActivityModel(env: g.env, editing: server, merged: false)
        #expect(!model.measured && model.sports == Sport.allCases)
        model.notes = "Windy"

        #expect(model.save())

        let row = try #require(g.env.activities.snapshot(id: server.id))
        #expect(row.notes == "Windy" && row.localRevision == 2 && row.confirmedRevision == 1)
    }

    @Test func aRecordedActivityKeepsItsTimesAndOffersItsFamilyOnly() {
        let g = Graph()
        let start = g.today.addingTimeInterval(7 * 3_600)
        let run = SportActivity(id: UUID(), sport: .running, origin: .recorded, start: start, end: start.addingTimeInterval(2_400),
                                movingSec: 2_300, distanceM: 7_000, clientUpdatedAt: start)
        let model = AddActivityModel(env: g.env, editing: run, merged: false)
        #expect(model.measured)
        #expect(Set(model.sports.map(\.family)) == [.foot])
        model.start = start.addingTimeInterval(-600)
        #expect(model.draft.start == run.start, "measured: the recording's times go back")
        #expect(model.draft.distanceM == run.distanceM)
    }
}

@Suite("Activities: detail delete")
@MainActor
struct ActivityDetailDeleteTests {
    @Test func deletingAPlatformOnlyActivityAdoptsItThenTombstonesIt() throws {
        let g = Graph()
        let start = g.today.addingTimeInterval(9 * 3_600)
        let server = SportActivity(id: UUID(), sport: .cycling, origin: .recorded, start: start, end: start.addingTimeInterval(3_600),
                                   movingSec: 3_500, distanceM: 24_000, clientUpdatedAt: start, strain: 11,
                                   strainSource: .heartRate, scoringState: "scored")
        g.state.repository.store(activities: [server], day: DayFormat.string(from: start))
        let model = ActivityDetailViewModel(route: ActivityRoute(id: server.id, day: start), state: g.state)
        #expect(model.activity?.id == server.id && model.isEditable && model.isRecorded)
        #expect(model.strainLine == .heartRate(11, source: nil))

        #expect(model.delete())

        let row = try #require(g.env.activities.snapshot(id: server.id))
        #expect(row.isTombstone, "the platform had it: a tombstone until the DELETE is confirmed")
        #expect(model.activity == nil)
    }

    @Test func aNewRowNeverSentIsGoneAtOnce() throws {
        let g = Graph()
        g.api.activitySource.publishesActivities = false
        let model = AddActivityModel(env: g.env, day: g.today)
        #expect(model.save())
        let id = try #require(g.env.activities.snapshots(onDay: DayFormat.string(from: g.today)).first?.id)
        let detail = ActivityDetailViewModel(route: ActivityRoute(id: id, day: g.today), state: g.state)
        #expect(detail.uploadNote == .notAvailableYet)

        #expect(detail.delete())

        #expect(g.env.activities.snapshot(id: id) == nil)
    }
}

@Suite("Activities: add sleep")
@MainActor
struct AddSleepModelTests {
    @Test func theNightDefaultsToElevenUntilSevenAndSaves() throws {
        let g = Graph()
        let model = AddSleepModel(env: g.env, day: g.today)
        #expect(Calendar.current.component(.hour, from: model.bed) == 23)
        #expect(Calendar.current.component(.hour, from: model.wake) == 7)
        #expect(model.duration == 8 * 3_600 && model.canSave)

        #expect(model.save())

        let night = try #require(g.env.activities.manualSleep(onDay: DayFormat.string(from: g.today)))
        #expect(night.bed == model.bed && night.wake == model.wake && night.needsUpload)
    }

    @Test func theRulesAreOneToSixteenHoursAndNotInTheFuture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let earliest = now.addingTimeInterval(-14 * 86_400)
        func issues(_ bed: TimeInterval, _ wake: TimeInterval) -> [AddSleepModel.Issue] {
            AddSleepModel.issues(bed: now.addingTimeInterval(bed), wake: now.addingTimeInterval(wake), now: now,
                                 earliestWake: earliest)
        }
        #expect(issues(-8 * 3_600, 0).isEmpty)
        #expect(issues(-8 * 3_600, 60) == [.wakeInFuture])
        #expect(issues(-600, -1_200) == [.wakeBeforeBed])
        #expect(issues(-1_800, 0) == [.length])
        #expect(issues(-17 * 3_600, 0) == [.length])
        #expect(issues(-16 * 86_400, -16 * 86_400 + 8 * 3_600) == [.tooFarBack])
    }

    @Test func aTrackersNightLeavesNoFormToSave() {
        let g = Graph()
        #expect(!AddSleepModel(env: g.env, day: g.today, trackerHasNight: true).canSave)
    }
}

@Suite("Activities: unknown origin and parked rows")
@MainActor
struct ActivityOriginAndParkingTests {
    @Test func anOriginThisBuildDoesntKnowHasANeutralBadgeAndIsReadOnly() throws {
        let json = """
        {"id":"00000000-0000-4000-8000-0000000c0001","sport":"running","origin":"imported",
         "start":"2026-10-22T07:00:00Z","end":"2026-10-22T07:40:00Z","moving_sec":2400,
         "client_updated_at":"2026-10-22T07:41:00Z","strain":8.2,"strain_source":"heart_rate","scoring_state":"scored"}
        """
        let imported = try APIClient.jsonDecoder.decode(SportActivity.self, from: Data(json.utf8))
        let day = DayFormat.string(from: imported.start)
        let input = MyDayInput(day: day, server: .dayDetail(nil, activities: [imported]))
        let row = try #require(MyDayAssembler.items(input, catalog: .unnamed, now: imported.end).first)
        #expect(row.sources == [.ryft])
        #expect(MyDayItem.Source.ryft.title == "RYFT" && MyDayItem.Source.ryft.glyph == "ellipsis.circle")
        #expect(!row.editable)
    }

    @Test func welcomeMentionsParkedRowsWithTheFlagOffAndNothingWithoutThem() throws {
        // Signed out the flag reads its default (off): parked rows are mentioned anyway, as only the feature parks them.
        let env = AppEnvironment.test(flags: [.activitiesManual: false])
        #expect(!env.flags.isOn(.activitiesManual))
        #expect(ParkedActivitiesNotice.parkedToMention(in: env) == nil, "nothing parked: no notice")
        let today = Calendar.current.startOfDay(for: env.clock.now())
        let context = env.persistence.context
        let run = LocalActivity(account: "expired", sport: .running, origin: .recorded, start: today,
                                end: today.addingTimeInterval(1_800), movingSec: 1_700, localRevision: 1, createdAt: today)
        run.parkedAt = env.clock.now()
        context.insert(run)
        context.insert(ActivityTrackChunk(activityID: run.id, account: "expired", seq: 0, kind: .profile, data: Data([1]),
                                          count: 1, first: today, last: today))
        let night = LocalManualSleep(day: DayFormat.string(from: today), account: "expired",
                                     bed: today.addingTimeInterval(-28_800), wake: today)
        night.parkedAt = env.clock.now()
        context.insert(night)
        env.persistence.save()

        #expect(ParkedActivitiesNotice.parkedToMention(in: env) == 2)

        // "Delete from this iPhone".
        #expect(env.activities.purgeParked() == 2)
        #expect(ParkedActivitiesNotice.parkedToMention(in: env) == nil)
        #expect(try context.fetchCount(FetchDescriptor<ActivityTrackChunk>()) == 0)
    }
}

@Suite("Activities: deletes and held uploads")
@MainActor
struct ActivityDeleteAndGateTests {
    @Test func aRowWhoseUploadWasCutOffStaysATombstoneShownNowhere() throws {
        let g = Graph()
        let model = AddActivityModel(env: g.env, day: g.today)
        model.sport = .yoga
        #expect(model.save())
        let day = DayFormat.string(from: g.today)
        let id = try #require(g.env.activities.snapshots(onDay: day).first?.id)
        // The uploader's sent marker: a PUT went out and no answer came, so the platform may have it.
        g.env.activities.recordFailure(id, UploadAttempt(at: g.clock.now(), request: .put, status: nil, code: nil,
                                                         requestID: nil, kind: .cancelled))
        let detail = ActivityDetailViewModel(route: ActivityRoute(id: id, day: g.today), state: g.state)

        #expect(detail.delete())

        #expect(g.env.activities.snapshot(id: id)?.isTombstone == true, "a DELETE goes up first")
        #expect(detail.activity == nil, "the detail shows it gone (and closes when deleted there)")
        let input = MyDayInput(day: day, server: .dayDetail(nil, activities: []), local: g.env.activities.snapshots(onDay: day),
                               uploads: [:])
        #expect(MyDayAssembler.items(input, catalog: .unnamed, now: g.clock.now()).isEmpty, "My Day and Strain hide it")
    }

    @Test func theDetailSaysWhyAnUploadWaits() async throws {
        // Consent or the invite isn't done: it uploads once the account is ready.
        let g = Graph()
        g.env.uploader.gate = { .consentRequired }
        let model = AddActivityModel(env: g.env, day: g.today)
        #expect(model.save())
        let id = try #require(g.env.activities.snapshots(onDay: DayFormat.string(from: g.today)).first?.id)
        await g.env.uploader.flush(userInitiated: true)
        #expect(ActivityDetailViewModel(route: ActivityRoute(id: id, day: g.today), state: g.state).uploadNote == .gated)

        // The account is being deleted: the activity goes with it.
        let hold = RequestHold()
        let defaults = UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard
        let auth = AuthService(client: MockAuthClient(session: .preview()), settings: Settings(defaults: defaults),
                               defaults: defaults, wipeLocalData: { _ in },
                               deleteRemoteAccount: {
                                   await hold.wait()
                                   return AccountDeleted(status: "deleted", authUserDeleted: true)
                               })
        let env = AppEnvironment.test(auth: auth, flags: [.activitiesManual: true])
        let state = AppState(env: env)
        let other = try #require(env.activities.save(manual: ActivityDraft(sport: .yoga, start: env.clock.now().addingTimeInterval(-3_600),
                                                                           end: env.clock.now()))?.id)
        let deletion = Task { await auth.deleteAccount() }
        #expect(await eventually { auth.isDeletingAccount })
        let detail = ActivityDetailViewModel(route: ActivityRoute(id: other, day: env.clock.now()), state: state)
        #expect(detail.uploadNote == .accountDeleting)
        hold.release()
        #expect(await deletion.value)
    }
}

@Suite("Activities: split labels")
struct SplitFormatTests {
    @Test func aPartialSplitIsLabelledInKilometresAndEveryRowIsSpoken() {
        let us = Locale(identifier: "en_US"), ireland = Locale(identifier: "en_IE")
        let partial = ActivitySplit(index: 9, distanceM: 420, durationSec: 140, ascentM: nil)
        let third = ActivitySplit(index: 3, distanceM: 1_000, durationSec: 334, ascentM: 8)
        #expect(ActivityFormat.splitLabel(partial, locale: us) == "0.42 km", "splits are per km in every locale")
        #expect(ActivityFormat.splitLabel(third, locale: us) == "3")
        #expect(ActivityFormat.spokenSplit(third, locale: ireland) == "Kilometre 3")
        let pace = ActivityFormat.spokenPace(movingSec: 334, distanceM: 1_000, locale: ireland) ?? ""
        #expect(pace.hasPrefix("5 minutes") && pace.hasSuffix("per kilometre"))
        #expect(ActivityFormat.spokenPace(movingSec: 334, distanceM: 1_000, locale: us)?.hasSuffix("per mile") == true)
        #expect(ActivityFormat.spokenClimb(8, locale: ireland) == "plus 8 metres")
        #expect(ActivityFormat.spokenClimb(nil, locale: ireland) == nil)
    }
}
