import Foundation
import Testing
@testable import Ryft

// My Day's assembler is one pure function (design.md §2.5, ADR 0006): every rule has a test that fails for
// that rule alone. Days are fixed strings and times are built on them; nothing reads `.now`. `DayFormat` uses
// the process's time zone (it takes no injected one), so the midnight and DST tests build their instants in
// that zone and the DST ones run only where it has a transition (CI runs UTC, a developer's Mac does not).

// MARK: - fixtures

private let day = "2026-10-22"
private let nextDay = "2026-10-23"
private let previousDay = "2026-10-21"
private let catalog = TrackerCatalog.bundled

/// `hour:minute` local on `day`.
private func at(_ hour: Int, _ minute: Int = 0, on day: String = day) -> Date {
    let start = DayFormat.date(from: day) ?? .distantPast
    return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
}

/// The time the list is made: 18:00.
private let now = at(18)

private func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n)) ?? UUID()
}

private func workout(_ n: Int, _ activity: String = "running", from start: Date, minutes: Int = 40,
                     strain: Double? = 9.5, source: String = "Connect", bundle: String? = "com.garmin.connect.mobile",
                     session: UUID? = nil, distanceM: Double? = 8_000, load: Double? = nil) -> Workout {
    Workout(id: uuid(n), activity: activity, start: start, end: start.addingTimeInterval(Double(minutes) * 60),
            avgHr: 150, maxHr: 175, energyKcal: 500, distanceM: distanceM, source: source, strain: strain,
            muscularLoad: load, sessionId: session, sourceBundleId: bundle)
}

private func activity(_ n: Int, _ sport: Sport = .running, origin: ActivityOrigin = .recorded, from start: Date,
                      minutes: Int = 40, strain: Double? = nil, source: StrainSource? = nil, hrSource: String? = nil,
                      mergedWith: UUID? = nil, scoring: String? = nil, distanceM: Double? = 8_000) -> SportActivity {
    SportActivity(id: uuid(n), sport: sport, origin: origin, start: start,
                  end: start.addingTimeInterval(Double(minutes) * 60), movingSec: Double(minutes - 2) * 60,
                  distanceM: distanceM, clientUpdatedAt: start.addingTimeInterval(Double(minutes) * 60 + 60),
                  strain: strain, strainSource: source, hrSource: hrSource, mergedWith: mergedWith,
                  scoringState: scoring)
}

/// What `LocalActivity.snapshot` gives for a saved document, edited (`revision` > `confirmed`) or not.
private func local(_ n: Int, _ sport: Sport = .yoga, origin: ActivityOrigin = .manual, from start: Date,
                   minutes: Int = 30, revision: Int = 1, confirmed: Int = 0, deleted: Bool = false,
                   phase: String = LocalActivity.savedPhase, notes: String = "") -> LocalActivitySnapshot {
    LocalActivitySnapshot(id: uuid(n), account: "account-a", sport: sport, origin: origin, phase: phase,
                          start: start, end: phase == LocalActivity.savedPhase ? start.addingTimeInterval(Double(minutes) * 60) : nil,
                          movingSec: Double(minutes) * 60, distanceM: nil, ascentM: nil, descentM: nil,
                          perceivedEffort: 4, notes: notes, recordRoute: false, routeWithheld: false,
                          routeDroppedAt: nil, splits: [], localRevision: revision, confirmedRevision: confirmed,
                          deletedAt: deleted ? now : nil, lastAttempt: nil, createdAt: start, updatedAt: start)
}

private let isoWithFractions: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

/// `SessionSummary` has no memberwise init: it is decoded from the wire shape, as the app gets it.
private func session(_ n: Int, title: String = "Upper A", from start: Date, minutes: Int = 50, workoutID: UUID? = nil,
                     strain: Double? = 6.5, trimp: Double? = 40, status: String = "completed") throws -> SessionSummary {
    var json: [String: Any] = [
        "id": uuid(n).uuidString, "title": title, "started_at": isoWithFractions.string(from: start),
        "ended_at": isoWithFractions.string(from: start.addingTimeInterval(Double(minutes) * 60)),
        "status": status, "duration_min": minutes, "exercise_count": 5, "set_count": 18, "pr_count": 0,
    ]
    if let workoutID { json["workout_id"] = workoutID.uuidString }
    if let strain { json["strain"] = strain }
    if let trimp { json["muscular_trimp"] = trimp }
    return try APIClient.jsonDecoder.decode(SessionSummary.self, from: JSONSerialization.data(withJSONObject: json))
}

private func night(from bed: Date, to wake: Date, totalMin: Int? = nil) -> SleepDetail {
    SleepDetail(start: bed, end: wake, totalMin: totalMin ?? Int(wake.timeIntervalSince(bed) / 60) - 20,
                inBedMin: Int(wake.timeIntervalSince(bed) / 60))
}

/// A scored day by default; `scored: false` is the platform's placeholder for a day it hasn't scored (no readiness,
/// `computed_at` unset), and `scoring` its `scoring_state`.
private func detail(sleep: SleepDetail? = nil, workouts: [Workout] = [], sessions: [SessionSummary]? = nil,
                    on day: String = day, scored: Bool = true, scoring: ScoringState? = nil) -> DayDetail {
    let score = DailyScore(day: day, readiness: scored ? 80 : nil, computedAt: scored ? at(8, on: day) : nil,
                           scoringState: scoring)
    return DayDetail(score: score, sleep: sleep,
                     strain: sessions.map { DayStrain(trimp: 80, hrMin: 600, zoneMin: [10, 10, 10, 5, 0], sessions: $0) },
                     workouts: workouts)
}

private func input(_ detail: DayDetail?, activities: [SportActivity] = [], local: [LocalActivitySnapshot] = [],
                   uploads: [UUID: UploadState] = [:], sessions: [SessionSummary] = [],
                   sleep: ManualSleepSnapshot? = nil, nightGap: Bool = false, day: String = day) -> MyDayInput {
    MyDayInput(day: day, server: .dayDetail(detail, activities: activities), local: local, uploads: uploads,
               localSessions: sessions, localSleep: sleep, nightGap: nightGap)
}

private func manualSleep(bed: Date, wake: Date, revision: Int = 1, confirmed: Int = 0, deleted: Bool = false,
                         on day: String = day) -> ManualSleepSnapshot {
    ManualSleepSnapshot(day: day, bed: bed, wake: wake, localRevision: revision, confirmedRevision: confirmed,
                        deletedAt: deleted ? now : nil, lastAttempt: nil)
}

private func rows(_ input: MyDayInput, includingSleep: Bool = true) -> [MyDayItem] {
    MyDayAssembler.items(input, catalog: catalog, now: now, includingSleep: includingSleep)
}

private func ids(_ items: [MyDayItem]) -> [String] { items.map(\.id) }
/// The rows but the night (a loaded day without one has its "No sleep recorded" row).
private func others(_ items: [MyDayItem]) -> [String] { items.filter { !$0.kind.isSleep }.map(\.id) }

private func item(_ id: String, in items: [MyDayItem]) throws -> MyDayItem {
    try #require(items.first { $0.id == id }, "no row \(id) in \(ids(items))")
}

private func activityID(_ n: Int) -> String { "activity.\(uuid(n).uuidString)" }
private func workoutID(_ n: Int) -> String { "workout.\(uuid(n).uuidString)" }
private func sessionID(_ n: Int) -> String { "session.\(uuid(n).uuidString)" }

private let garmin = MyDayItem.Source.tracker(name: "Garmin Connect",
                                              symbol: catalog.tracker("garmin")?.symbol ?? "?")

// MARK: - rule 1: the server layer

@Suite("My Day assembler: server layer (rule 1)")
struct MyDayServerLayerTests {
    @Test func theDaysSleepWorkoutSessionAndActivityAreRowsInOrder() throws {
        let s = try session(1, from: at(17))
        let d = detail(sleep: night(from: at(23, on: previousDay), to: at(6, 50)),
                       workouts: [workout(1, from: at(7))], sessions: [s])
        let list = rows(input(d, activities: [activity(2, .yoga, origin: .manual, from: at(12), strain: 3)]))

        #expect(ids(list) == ["sleep.\(day)", workoutID(1), activityID(2), sessionID(1)])
        #expect(list.map(\.kind) == [.sleep(day: day), .workout(uuid(1)), .activity(uuid(2)), .session(uuid(1))])
    }

    @Test func aDayThatIsNotCachedHasOnlyWhatTheActivitiesSay() throws {
        let list = rows(input(nil, activities: [activity(2, .yoga, origin: .manual, from: at(12))]))
        #expect(ids(list) == [activityID(2)])      // no "No sleep recorded": the day isn't loaded
    }

    @Test func aWorkoutShowsTheTrackersStrainAndDistance() throws {
        let list = rows(input(detail(workouts: [workout(1, from: at(7), minutes: 52, strain: 10.6, distanceM: 8_420)])))
        let w = try item(workoutID(1), in: list)
        #expect(w.strain == .scored(10.6))
        #expect(w.distanceM == 8_420)
        #expect(w.duration == 52 * 60)
        #expect(!w.editable)
        #expect(w.upload == nil)
    }

    @Test func aServerActivityIsConfirmedAndEditableOnAnyDay() throws {
        let list = rows(input(detail(), activities: [activity(2, .padel, origin: .manual, from: at(19, 30), strain: 9.1)]))
        let a = try item(activityID(2), in: list)
        #expect(a.upload == .confirmed)
        #expect(a.editable)
    }
}

// MARK: - rule 2: merged rows

@Suite("My Day assembler: merged rows (rule 2)")
struct MyDayMergedRowTests {
    @Test func aMergedActivityHidesItsWorkoutAndCarriesBothBadgesTrackerFirst() throws {
        let merged = activity(1, .running, from: at(7), strain: 10.6, source: .heartRate, hrSource: "Connect",
                              mergedWith: uuid(10), scoring: "scored")
        let list = rows(input(detail(workouts: [workout(10, from: at(7), strain: 10.1)]), activities: [merged]))

        #expect(others(list) == [activityID(1)])                       // the workout row is gone
        let row = try item(activityID(1), in: list)
        #expect(row.sources == [garmin, .ryftRecorded(indoor: false)])
        #expect(row.isMerged)
        #expect(row.strain == .scored(10.6))                        // the activity's, not the workout's 10.1
    }

    @Test func aMergedRowOpensItsWorkoutAndAnUnmergedActivityOpensNothingYet() throws {
        let w = workout(10, from: at(7))
        let merged = activity(1, .running, from: at(7), strain: 10.6, mergedWith: w.id)
        let alone = activity(2, .yoga, origin: .manual, from: at(13), strain: 4)
        let list = rows(input(detail(workouts: [w]), activities: [merged, alone]))
        let row = try item(activityID(1), in: list)
        #expect(row.mergedWorkout == w.id)
        #expect(row.opensDetail)
        let other = try item(activityID(2), in: list)
        #expect(other.mergedWorkout == nil)
        #expect(!other.opensDetail)
        // A merge whose workout isn't cached for the day has nothing to open.
        let uncached = try item(activityID(1), in: rows(input(detail(), activities: [merged])))
        #expect(uncached.mergedWorkout == nil && !uncached.opensDetail)
    }

    @Test func aMergeIsOnlyWhatThePlatformSaidNeverPredicted() throws {
        // Same window, same sport; no `merged_with`: both rows stay (ADR 0006, the client never predicts a merge).
        let a = activity(1, .running, from: at(7), minutes: 40)
        let list = rows(input(detail(workouts: [workout(10, from: at(7), minutes: 40)]), activities: [a]))
        #expect(others(list) == [activityID(1), workoutID(10)].sorted())
        #expect(try item(activityID(1), in: list).sources.count == 1)
        #expect(try !item(activityID(1), in: list).isMerged)
    }

    @Test func aMergeWhoseWorkoutIsNotCachedIsASingleBadgeRow() throws {
        let a = activity(1, .running, from: at(7), strain: 9, mergedWith: uuid(10))
        let row = try item(activityID(1), in: rows(input(detail(), activities: [a])))
        #expect(row.sources == [.ryftRecorded(indoor: false)])
        #expect(!row.isMerged)
    }

    @Test func onlyTheMergedWorkoutIsHidden() {
        let a = activity(1, .running, from: at(7), mergedWith: uuid(10))
        let other = workout(11, "cycling", from: at(12))
        let list = rows(input(detail(workouts: [workout(10, from: at(7)), other]), activities: [a]))
        #expect(others(list) == [activityID(1), workoutID(11)])
    }

    struct OwnBadge: Sendable, CustomTestStringConvertible {
        let sport: Sport
        let origin: ActivityOrigin
        let expected: MyDayItem.Source
        var testDescription: String { "\(sport.rawValue) \(origin.rawValue)" }
    }

    @Test(arguments: [
        OwnBadge(sport: .running, origin: .recorded, expected: .ryftRecorded(indoor: false)),
        OwnBadge(sport: .indoorRunning, origin: .recorded, expected: .ryftRecorded(indoor: true)),
        OwnBadge(sport: .yoga, origin: .recorded, expected: .ryftRecorded(indoor: true)),
        OwnBadge(sport: .running, origin: .manual, expected: .ryftManual),
        OwnBadge(sport: .yoga, origin: .manual, expected: .ryftManual),
    ])
    func theOwnBadgeFollowsTheOriginAndGPS(_ c: OwnBadge) throws {
        let list = rows(input(detail(), activities: [activity(1, c.sport, origin: c.origin, from: at(8))]))
        #expect(try item(activityID(1), in: list).sources == [c.expected])
    }

    @Test func aRecordingWithoutGPSHasANeutralRYFTGlyphNotARunner() {
        #expect(MyDayItem.Source.ryftRecorded(indoor: true).glyph == "record.circle")
        #expect(MyDayItem.Source.ryftRecorded(indoor: false).glyph == "location.fill")
    }
}

// MARK: - rule 3: workout and session are one row

@Suite("My Day assembler: workouts and sessions (rule 3)")
struct MyDayWorkoutSessionTests {
    @Test func aWorkoutWithItsSessionIdIsOneRowWithTheSessionsTitleAndBothBadges() throws {
        let s = try session(1, title: "Upper A", from: at(17), trimp: 42)
        let w = workout(10, "traditionalStrengthTraining", from: at(17), strain: nil, session: uuid(1))
        let list = rows(input(detail(workouts: [w], sessions: [s])))

        #expect(others(list) == [workoutID(10)])                       // no second "session." row
        let row = try item(workoutID(10), in: list)
        #expect(row.title == "Upper A")
        #expect(row.symbol == "dumbbell.fill")
        #expect(row.sources == [garmin, .train])
        #expect(row.load == 42)
        #expect(row.strain == .scored(6.5))                         // the workout has none yet: the session's
    }

    @Test func theSessionPointingAtTheWorkoutLinksWithoutASessionIdOnTheWorkout() throws {
        let s = try session(1, from: at(17), workoutID: uuid(10))
        let list = rows(input(detail(workouts: [workout(10, from: at(17))], sessions: [s])))
        #expect(others(list) == [workoutID(10)])
        #expect(try item(workoutID(10), in: list).sources.last == .train)
    }

    @Test func theWorkoutsOwnStrainWinsOverTheSessions() throws {
        let s = try session(1, from: at(17), strain: 6.5)
        let w = workout(10, from: at(17), strain: 8.0, session: uuid(1))
        #expect(try item(workoutID(10), in: rows(input(detail(workouts: [w], sessions: [s])))).strain == .scored(8.0))
    }

    @Test func aSessionNoWorkoutPointsAtIsItsOwnRowAfterTheWorkouts() throws {
        let s = try session(1, title: "Legs", from: at(18), strain: nil)
        let list = rows(input(detail(workouts: [workout(10, from: at(7))], sessions: [s])))
        #expect(others(list) == [workoutID(10), sessionID(1)])
        let row = try item(sessionID(1), in: list)
        #expect(row.sources == [.train])
        #expect(row.title == "Legs")
        #expect(row.strain == .pending)
        #expect(row.duration == 50 * 60)
    }

    @Test func aLocalSessionNotOnTheServerYetIsAdded() throws {
        let s = try session(1, title: "Pull", from: at(9))
        let list = rows(input(detail(), sessions: [s]))
        #expect(others(list) == [sessionID(1)])
    }

    @Test func aSessionThatIsLocalAndRemoteIsOneRow() throws {
        let s = try session(1, from: at(9))
        let list = rows(input(detail(sessions: [s]), sessions: [s]))
        #expect(others(list) == [sessionID(1)])
    }

    @Test func aRemoteSessionStillInProgressIsNoRow() throws {
        let s = try session(1, from: at(9), status: "in_progress")
        #expect(ids(rows(input(detail(sessions: [s])))) == ["nosleep.\(day)"])
    }
}

// MARK: - rule 4: the local overlay

@Suite("My Day assembler: local overlay (rule 4)")
struct MyDayOverlayTests {
    @Test func anUnconfirmedEditReplacesTheServerItemAndKeepsThePlatformsLastWord() throws {
        let hidden = workout(10, from: at(7))
        let server = activity(1, .running, origin: .recorded, from: at(7), strain: 10.6, source: .heartRate,
                              hrSource: "Connect", mergedWith: hidden.id, scoring: "scored")
        // The user changed the notes and the sport (same family) on this iPhone; revision 2 is unsent.
        let edit = local(1, .trailRunning, origin: .recorded, from: at(7), minutes: 40, revision: 2, confirmed: 1,
                         notes: "Muddy")
        let list = rows(input(detail(workouts: [hidden]), activities: [server], local: [edit]))

        #expect(others(list) == [activityID(1)])                       // replaced, not doubled; workout still hidden
        let row = try item(activityID(1), in: list)
        #expect(row.title == Sport.trailRunning.name)               // the edit wins
        #expect(row.strain == .scored(10.6))                        // the server's strain stays
        #expect(row.sources == [garmin, .ryftRecorded(indoor: false)])   // its merge stays: two badges
        #expect(row.upload == .pending(.queued))
    }

    @Test func anEditNotOnTheServerHasPendingStrainAndAQueuedUpload() throws {
        let list = rows(input(detail(), local: [local(1, from: at(13))]))
        let row = try item(activityID(1), in: list)
        #expect(row.strain == .pending)
        #expect(row.upload == .pending(.queued))
        #expect(row.sources == [.ryftManual])
        #expect(row.editable)
    }

    @Test func theUploadersWordWinsOverTheRowsOwn() throws {
        let edit = local(1, from: at(13))
        let list = rows(input(detail(), local: [edit], uploads: [uuid(1): .pending(.offline)]))
        #expect(try item(activityID(1), in: list).upload == .pending(.offline))
    }

    @Test func aTombstoneHidesTheServerItem() {
        let server = activity(1, .yoga, origin: .manual, from: at(13), strain: 4)
        let gone = local(1, from: at(13), revision: 2, confirmed: 1, deleted: true)
        #expect(rows(input(detail(), activities: [server], local: [gone])).filter { !$0.kind.isSleep }.isEmpty)
    }

    @Test func aTombstoneOfAMergedActivityBringsBackItsWorkout() {
        let w = workout(10, from: at(7))
        let server = activity(1, .running, from: at(7), strain: 10.6, mergedWith: w.id)
        let gone = local(1, .running, origin: .recorded, from: at(7), revision: 2, confirmed: 1, deleted: true)
        let list = rows(input(detail(workouts: [w]), activities: [server], local: [gone]))
        #expect(ids(list.filter { !$0.kind.isSleep }) == [workoutID(10)])
    }

    @Test func aTombstoneWithoutAServerCopyShowsNothing() {
        let gone = local(1, from: at(13), revision: 1, confirmed: 0, deleted: true)
        #expect(rows(input(detail(), local: [gone])).filter { !$0.kind.isSleep }.isEmpty)
    }

    @Test func aConfirmedLocalRowIsAddedOnlyWhenTheServerCopyIsMissing() throws {
        let confirmed = local(1, from: at(13), revision: 1, confirmed: 1)
        let added = rows(input(detail(), local: [confirmed]))
        #expect(try item(activityID(1), in: added).upload == .confirmed)

        // With the server's copy, the server's copy shows, not the local row's fields.
        let server = activity(1, .padel, origin: .manual, from: at(13), strain: 8)
        let list = rows(input(detail(), activities: [server], local: [confirmed]))
        let row = try item(activityID(1), in: list)
        #expect(ids(list.filter { !$0.kind.isSleep }) == [activityID(1)])
        #expect(row.title == Sport.padel.name)
        #expect(row.strain == .scored(8))
    }

    @Test func anEditThatMovedTheActivityToAnotherDayHidesTheServerCopyOnTheOldDay() throws {
        let server = activity(1, .yoga, origin: .manual, from: at(13), strain: 4)
        let moved = local(1, from: at(13, on: nextDay), revision: 2, confirmed: 1)
        // The old day: the platform still lists it, the unconfirmed edit hides it.
        let old = rows(input(detail(), activities: [server], local: [moved]))
        #expect(old.filter { !$0.kind.isSleep }.isEmpty)
        // The new day: the edit shows, with the pending strain.
        let new = rows(input(detail(on: nextDay), local: [moved], day: nextDay))
        #expect(try item(activityID(1), in: new).strain == .pending)
    }

    @Test func aConfirmedRowOnAnotherDayHidesTheServerCopyOnTheOldDayToo() throws {
        // The platform confirmed the move; this day's cached list is older than that and still has it.
        let server = activity(1, .yoga, origin: .manual, from: at(13), strain: 4)
        let moved = local(1, from: at(13, on: nextDay), revision: 2, confirmed: 2)
        #expect(rows(input(detail(), activities: [server], local: [moved])).filter { !$0.kind.isSleep }.isEmpty)
        // On its new day it shows (the platform's list there doesn't have it yet).
        let new = rows(input(detail(on: nextDay), local: [moved], day: nextDay))
        #expect(try item(activityID(1), in: new).upload == .confirmed)
    }

    @Test func anEditOfAScoredActivityKeepsItsStrainBesideTheUploadMark() throws {
        let server = activity(1, .yoga, origin: .manual, from: at(13), strain: 6.2, source: .heartRate, scoring: "scored")
        let edit = local(1, from: at(13), revision: 2, confirmed: 1, notes: "Longer")
        let row = try item(activityID(1), in: rows(input(detail(), activities: [server], local: [edit])))
        #expect(ActivityStateMark.State(row) == .uploading(lastStrain: 6.2))
        // Not on the platform yet: the upload mark alone.
        let fresh = try item(activityID(2), in: rows(input(detail(), local: [local(2, from: at(15))])))
        #expect(ActivityStateMark.State(fresh) == .uploading(lastStrain: nil))
    }

    @Test func aRecordingInProgressIsARowWithNoStrainEndingNow() throws {
        let recording = local(1, .running, origin: .recorded, from: at(17, 30), revision: 0, phase: "recording")
        let row = try item(activityID(1), in: rows(input(detail(), local: [recording])))
        #expect(row.isRecording)
        #expect(row.strain == .notApplicable)
        #expect(row.end == now)
        #expect(row.duration == 30 * 60)
        #expect(row.upload == nil)
        #expect(!row.editable)
        #expect(row.sources == [.ryftRecorded(indoor: false)])
    }

    @Test func aRecordingOnAnotherDayIsNotShown() {
        let recording = local(1, .running, origin: .recorded, from: at(17, 30, on: previousDay), revision: 0, phase: "recording")
        #expect(rows(input(detail(), local: [recording])).filter { !$0.kind.isSleep }.isEmpty)
    }
}

// MARK: - rule 5: the night

@Suite("My Day assembler: the night (rule 5)")
struct MyDaySleepTests {
    private let bed = at(23, on: previousDay)
    private let wake = at(6, 50)

    @Test func theTrackersNightIsTheFirstRowWithAppleHealthAsItsSource() throws {
        let list = rows(input(detail(sleep: night(from: bed, to: wake, totalMin: 400), workouts: [workout(1, from: at(7))])))
        let sleep = try #require(list.first)
        #expect(sleep.id == "sleep.\(day)")
        #expect(sleep.sources == [.tracker(name: "Apple Health", symbol: MyDayAssembler.appleHealthSymbol)])
        #expect(sleep.duration == 400 * 60)                        // time asleep, not in bed
        #expect(sleep.start == bed && sleep.end == wake)
        #expect(sleep.strain == .notApplicable)
        #expect(!sleep.editable)
        #expect(sleep.upload == nil)
    }

    @Test func aNightWithoutTotalsFallsBackToTheSpan() throws {
        let s = SleepDetail(start: bed, end: wake)
        let sleep = try item("sleep.\(day)", in: rows(input(detail(sleep: s))))
        #expect(sleep.duration == wake.timeIntervalSince(bed))
    }

    @Test func noNightAndNoGapIsANoSleepRow() throws {
        let list = rows(input(detail(workouts: [workout(1, from: at(7))])))
        #expect(ids(list) == ["nosleep.\(day)", workoutID(1)])
        let row = try #require(list.first)
        #expect(row.kind == .missingSleep(day: day))
        #expect(row.sources.isEmpty)
        #expect(row.strain == .notApplicable)
        #expect(!row.editable)
        #expect(row.start == DayFormat.date(from: day))
    }

    @Test func noNightWhileTheTrackersNightIsOnlyLateIsNoRow() {
        #expect(ids(rows(input(detail(workouts: [workout(1, from: at(7))]), nightGap: true))) == [workoutID(1)])
    }

    // The missing night is only for a day the platform scored (review): not its placeholder for an unscored day,
    // nor one it is still scoring or waiting for the night of.
    @Test func anUnscoredDayHasNoNoSleepRow() {
        #expect(rows(input(detail(scored: false))).isEmpty)
    }

    @Test(arguments: [ScoringState.pending, .waitingForSleep])
    func aDayThePlatformIsStillScoringHasNoNoSleepRow(_ state: ScoringState) {
        #expect(rows(input(detail(scoring: state))).isEmpty)
    }

    @Test(arguments: [ScoringState.scored, .stale])
    func aScoredDayWithoutANightHasTheRow(_ state: ScoringState) {
        #expect(ids(rows(input(detail(scoring: state)))) == ["nosleep.\(day)"])
    }

    @Test func aScoredDayWithTheNightGapHasNoRow() {
        #expect(rows(input(detail(), nightGap: true)).isEmpty)
    }

    @Test func aDayThatIsNotLoadedHasNoNoSleepRow() {
        #expect(rows(input(nil)).isEmpty)
        #expect(rows(input(nil, nightGap: false)).isEmpty)
    }

    @Test func aNightTheServerHasWithoutTimesIsNotAMissingOne() {
        let timeless = SleepDetail(totalMin: 400)
        #expect(rows(input(detail(sleep: timeless))).isEmpty)
    }

    @Test func aPendingManualNightWinsOverTheTrackersAndIsAddedByYou() throws {
        let typed = manualSleep(bed: at(22, 30, on: previousDay), wake: at(6, 15))
        let list = rows(input(detail(sleep: night(from: bed, to: wake)), sleep: typed))
        let sleep = try item("sleep.\(day)", in: list)
        #expect(list.filter { $0.kind.isSleep }.count == 1)
        #expect(sleep.sources == [.addedByYou])
        #expect(sleep.start == typed.bed && sleep.end == typed.wake)
        #expect(sleep.upload == .pending(.queued))
        #expect(sleep.editable)
    }

    @Test(arguments: [false, true])
    func aManualNightWithoutAnyOtherShowsWhateverTheGapSays(_ nightGap: Bool) throws {
        let typed = manualSleep(bed: bed, wake: wake)
        let sleep = try item("sleep.\(day)", in: rows(input(detail(), sleep: typed, nightGap: nightGap)))
        #expect(sleep.sources == [.addedByYou])
        #expect(rows(input(detail(), sleep: typed, nightGap: nightGap)).filter(\.kind.isMissingSleep).isEmpty)
    }

    @Test func aConfirmedManualNightThePlatformEchoesStaysAddedByYou() throws {
        let typed = manualSleep(bed: bed, wake: wake, revision: 1, confirmed: 1)
        let list = rows(input(detail(sleep: night(from: bed, to: wake)), sleep: typed))
        let sleep = try item("sleep.\(day)", in: list)
        #expect(sleep.sources == [.addedByYou])
        #expect(sleep.upload == .confirmed)
        #expect(sleep.editable)
    }

    @Test func aConfirmedManualNightTheTrackerHasReplacedIsTheTrackers() throws {
        let typed = manualSleep(bed: at(22, 30, on: previousDay), wake: at(6, 15), revision: 1, confirmed: 1)
        let sleep = try item("sleep.\(day)", in: rows(input(detail(sleep: night(from: bed, to: wake)), sleep: typed)))
        #expect(sleep.sources == [.tracker(name: "Apple Health", symbol: MyDayAssembler.appleHealthSymbol)])
        #expect(!sleep.editable)
    }

    @Test func aConfirmedManualNightMatchesThePlatformsWithinAMinute() throws {
        // ISO 8601 on the wire drops sub-seconds: the platform's copy is off by a fraction.
        let typed = manualSleep(bed: at(22, 30, on: previousDay).addingTimeInterval(0.4), wake: at(6, 15).addingTimeInterval(59),
                                revision: 1, confirmed: 1)
        let echo = night(from: at(22, 30, on: previousDay), to: at(6, 15))
        let sleep = try item("sleep.\(day)", in: rows(input(detail(sleep: echo), sleep: typed)))
        #expect(sleep.sources == [.addedByYou])
        // Two minutes off is another night: the tracker's.
        let other = manualSleep(bed: at(22, 30, on: previousDay), wake: at(6, 17), revision: 1, confirmed: 1)
        let trackers = try item("sleep.\(day)", in: rows(input(detail(sleep: echo), sleep: other)))
        #expect(trackers.sources == [.tracker(name: "Apple Health", symbol: MyDayAssembler.appleHealthSymbol)])
    }

    @Test func aDeletedManualNightHidesThePlatformsCopyOfIt() {
        let typed = manualSleep(bed: bed, wake: wake, revision: 2, confirmed: 1, deleted: true)
        #expect(rows(input(detail(sleep: night(from: bed, to: wake)), sleep: typed)).isEmpty)
    }

    @Test func aDeletedManualNightLeavesTheTrackersDifferentNight() throws {
        let typed = manualSleep(bed: at(22, 30, on: previousDay), wake: at(6, 15), revision: 2, confirmed: 1, deleted: true)
        let sleep = try item("sleep.\(day)", in: rows(input(detail(sleep: night(from: bed, to: wake)), sleep: typed)))
        #expect(sleep.sources == [.tracker(name: "Apple Health", symbol: MyDayAssembler.appleHealthSymbol)])
    }

    @Test func aDeletedManualNightAloneLeavesNoSleepOnALoadedDay() {
        let typed = manualSleep(bed: bed, wake: wake, revision: 2, confirmed: 1, deleted: true)
        #expect(ids(rows(input(detail(), sleep: typed))) == ["nosleep.\(day)"])
    }
}

// MARK: - rule 6: order, names, Strain's list

@Suite("My Day assembler: order and names (rule 6)")
struct MyDayOrderTests {
    @Test func sleepIsFirstThenByStart() throws {
        // The night ends after the 06:00 mobility starts and the run is earlier than the yoga.
        let d = detail(sleep: night(from: at(23, on: previousDay), to: at(7)), workouts: [workout(1, from: at(7, 30))])
        let list = rows(input(d, activities: [
            activity(3, .yoga, origin: .manual, from: at(13, 5)),
            activity(2, .mobility, origin: .manual, from: at(6)),
        ]))
        #expect(ids(list) == ["sleep.\(day)", activityID(2), workoutID(1), activityID(3)])
    }

    @Test func theNoSleepRowIsFirstToo() {
        let list = rows(input(detail(workouts: [workout(1, from: at(0, 10))])))
        #expect(ids(list) == ["nosleep.\(day)", workoutID(1)])
    }

    @Test func equalStartsKeepAStableOrderById() {
        let a = activity(5, .yoga, origin: .manual, from: at(9))
        let b = activity(4, .yoga, origin: .manual, from: at(9))
        let first = ids(rows(input(detail(), activities: [a, b])).filter { !$0.kind.isSleep })
        let second = ids(rows(input(detail(), activities: [b, a])).filter { !$0.kind.isSleep })
        #expect(first == [activityID(4), activityID(5)])
        #expect(second == first)
    }

    @Test func strainsListLeavesTheNightOutAndKeepsEverythingElse() throws {
        let s = try session(1, from: at(18, 30))
        let d = detail(sleep: night(from: at(23, on: previousDay), to: at(7)), workouts: [workout(1, from: at(7, 30))],
                       sessions: [s])
        let activities = [activity(2, .yoga, origin: .manual, from: at(13))]
        let withSleep = rows(input(d, activities: activities))
        let without = rows(input(d, activities: activities), includingSleep: false)
        #expect(ids(withSleep).first == "sleep.\(day)")
        #expect(ids(without) == ids(withSleep).filter { $0 != "sleep.\(day)" })
        #expect(ids(without) == [workoutID(1), activityID(2), sessionID(1)])
    }

    @Test func strainsListHasNoNoSleepRowEither() {
        #expect(ids(rows(input(detail(workouts: [workout(1, from: at(7))])), includingSleep: false)) == [workoutID(1)])
    }

    struct TrackerName: Sendable, CustomTestStringConvertible {
        let source: String
        let bundle: String?
        let name: String
        /// The glyph is the tracker's form factor; nil = the unknown source's fallback.
        let trackerID: String?
        /// False where the glyph can't be known from a workout (no device model: see the Apple Watch row).
        var checksGlyph = true
        var testDescription: String { "\(source) / \(bundle ?? "-")" }
    }

    @Test(arguments: [
        TrackerName(source: "Connect", bundle: "com.garmin.connect.mobile", name: "Garmin Connect", trackerID: "garmin"),
        TrackerName(source: "Connect", bundle: nil, name: "Garmin Connect", trackerID: "garmin"),
        TrackerName(source: "Garmin Connect", bundle: nil, name: "Garmin Connect", trackerID: "garmin"),
        TrackerName(source: "Tim's Apple Watch", bundle: "com.apple.health.9F2C1A", name: "Tim's Apple Watch",
                    trackerID: "apple_watch", checksGlyph: false),
        TrackerName(source: "Strava", bundle: nil, name: "Strava", trackerID: nil),
        TrackerName(source: "", bundle: nil, name: MyDayAssembler.appleHealth, trackerID: nil),
    ])
    func aWorkoutsSourceIsNamedByTheCatalog(_ c: TrackerName) throws {
        let list = rows(input(detail(workouts: [workout(1, from: at(7), source: c.source, bundle: c.bundle)])))
        let source = try #require(try item(workoutID(1), in: list).sources.first)
        let expectedSymbol: String
        if let id = c.trackerID { expectedSymbol = try #require(catalog.tracker(id)).symbol }
        else { expectedSymbol = c.source.isEmpty ? MyDayAssembler.appleHealthSymbol : "ellipsis.circle" }
        if c.checksGlyph {
            #expect(source == .tracker(name: c.name, symbol: expectedSymbol))
        } else {
            guard case .tracker(let name, _) = source else { Issue.record("not a tracker badge: \(source)"); return }
            #expect(name == c.name)
        }
    }

    @Test func onlyAVendorAppsExactNameBorrowsItsTrackersGlyph() throws {
        // An Apple device's tracker has no app of its own: a source named like it keeps the unknown glyph.
        let apple = try #require(catalog.trackers.first { $0.integration == .appleBuiltin })
        let list = rows(input(detail(workouts: [workout(1, from: at(7), source: apple.appTitle, bundle: nil)])))
        let source = try #require(try item(workoutID(1), in: list).sources.first)
        guard case .tracker(_, let symbol) = source else { Issue.record("not a tracker badge: \(source)"); return }
        try #require(catalog.match(SourceRef(name: apple.appTitle, bundleID: nil, deviceModel: nil)) == nil)
        #expect(symbol == "ellipsis.circle")
    }

    @Test func theCatalogNamesTheTrackerOnAMergedRowToo() throws {
        let a = activity(1, .running, from: at(7), strain: 9, mergedWith: uuid(10))
        let w = workout(10, from: at(7), source: "Tim's Apple Watch", bundle: "com.apple.health.9F2C1A")
        let row = try item(activityID(1), in: rows(input(detail(workouts: [w]), activities: [a])))
        guard case .tracker(let name, _) = row.sources.first else {
            Issue.record("the tracker's badge isn't first: \(row.sources)")
            return
        }
        #expect(name == "Tim's Apple Watch")
    }
}

// MARK: - strain per item

@Suite("My Day assembler: strain states")
struct MyDayStrainStateTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let strain: Double?
        let source: StrainSource?
        let scoring: String?
        let expected: MyDayItem.Strain
        var testDescription: String { "\(strain.map { "\($0)" } ?? "nil") / \(source?.rawValue ?? "nil") / \(scoring ?? "nil")" }
    }

    @Test(arguments: [
        Case(strain: 10.6, source: .heartRate, scoring: "scored", expected: .scored(10.6)),
        Case(strain: 9.1, source: .perceivedEffort, scoring: "scored", expected: .scored(9.1)),
        Case(strain: 0, source: .heartRate, scoring: "scored", expected: .scored(0)),
        Case(strain: 4, source: .noSource, scoring: nil, expected: .scored(4)),            // a value is a value
        Case(strain: nil, source: .noSource, scoring: "scored", expected: .noHeartRate),
        Case(strain: nil, source: nil, scoring: "pending", expected: .pending),
        Case(strain: nil, source: nil, scoring: nil, expected: .pending),
        Case(strain: nil, source: .heartRate, scoring: "pending", expected: .pending),
        Case(strain: nil, source: .perceivedEffort, scoring: nil, expected: .pending),
    ])
    func anActivitysStrainState(_ c: Case) throws {
        let a = activity(1, .yoga, origin: .manual, from: at(13), strain: c.strain, source: c.source, scoring: c.scoring)
        #expect(MyDayAssembler.strain(a) == c.expected)
        #expect(try item(activityID(1), in: rows(input(detail(), activities: [a]))).strain == c.expected)
    }

    @Test func nightsAndRecordingsHaveNoStrain() throws {
        let recording = local(2, .running, origin: .recorded, from: at(17, 30), revision: 0, phase: "recording")
        let d = detail(sleep: night(from: at(23, on: previousDay), to: at(7)))
        let list = rows(input(d, local: [recording]))
        #expect(try item("sleep.\(day)", in: list).strain == .notApplicable)
        #expect(try item(activityID(2), in: list).strain == .notApplicable)
        #expect(try item("nosleep.\(day)", in: rows(input(detail()))).strain == .notApplicable)
    }

    @Test func aWorkoutAndASessionWithoutStrainArePending() throws {
        let s = try session(1, from: at(18, 30), strain: nil)
        let list = rows(input(detail(workouts: [workout(10, from: at(7), strain: nil)], sessions: [s])))
        #expect(try item(workoutID(10), in: list).strain == .pending)
        #expect(try item(sessionID(1), in: list).strain == .pending)
    }
}

// MARK: - time: midnight, DST, duplicates

@Suite("My Day assembler: days and duplicates")
struct MyDayDayTests {
    @Test func anActivityAcrossMidnightBelongsToTheDayItStartedOn() throws {
        let late = local(1, .running, origin: .manual, from: at(23, 40), minutes: 40)
        let started = rows(input(detail(), local: [late]))
        let row = try item(activityID(1), in: started)
        #expect(row.end == at(0, 20, on: nextDay))
        #expect(row.duration == 40 * 60)
        #expect(row.start < DayFormat.date(from: nextDay) ?? .distantPast)
        // The next day: the same local row isn't there, confirmed or not.
        #expect(rows(input(detail(on: nextDay), local: [late], day: nextDay)).filter { !$0.kind.isSleep }.isEmpty)
        let confirmed = local(1, .running, origin: .manual, from: at(23, 40), minutes: 40, revision: 1, confirmed: 1)
        #expect(rows(input(detail(on: nextDay), local: [confirmed], day: nextDay)).filter { !$0.kind.isSleep }.isEmpty)
    }

    @Test func aNightAcrossMidnightIsTheWakeDaysAndIsFirst() throws {
        let d = detail(sleep: night(from: at(23, 10, on: day), to: at(6, 50, on: nextDay)), workouts: [workout(1, from: at(6, 0, on: nextDay))], on: nextDay)
        let list = rows(input(d, day: nextDay))
        #expect(ids(list) == ["sleep.\(nextDay)", workoutID(1)])
        #expect(list[0].start < list[1].start)
    }

    @Test func aWorkoutAcrossMidnightIsOneRowOnTheDayTheServerListsItOn() throws {
        let w = workout(1, from: at(23, 50), minutes: 40)
        let list = rows(input(detail(workouts: [w])))
        #expect(ids(list.filter { !$0.kind.isSleep }) == [workoutID(1)])
        #expect(try item(workoutID(1), in: list).end == at(0, 30, on: nextDay))
    }

    @Test func theNoSleepRowStartsAtTheLocalMidnightOfItsDay() throws {
        let row = try item("nosleep.\(nextDay)", in: rows(input(detail(on: nextDay), day: nextDay)))
        #expect(row.start == Calendar.current.startOfDay(for: at(12, on: nextDay)))
    }

    /// The first DST change of 2026 in the process's zone, if it has one.
    private static var transition: Date? {
        TimeZone.current.nextDaylightSavingTimeTransition(after: DayFormat.date(from: "2026-01-01") ?? .distantPast)
    }

    @Test(.enabled(if: MyDayDayTests.transition != nil, "the process's time zone has no DST (CI runs UTC)"))
    func aDayWithADSTChangeKeepsRealDurationsAndOrder() throws {
        let change = try #require(Self.transition)
        let dstDay = DayFormat.string(from: change)
        let before = local(1, .yoga, from: change.addingTimeInterval(-3_600), minutes: 30)
        let after = local(2, .yoga, from: change.addingTimeInterval(3_600), minutes: 30)
        let list = rows(input(detail(on: dstDay), local: [after, before], day: dstDay))

        #expect(ids(list.filter { !$0.kind.isSleep }) == [activityID(1), activityID(2)])
        // Durations are the activity's own seconds, not wall-clock differences across the change.
        #expect(try item(activityID(1), in: list).duration == 30 * 60)
        #expect(try item(activityID(2), in: list).duration == 30 * 60)
        // The missing night starts at the day's local midnight, 23 or 25 hours before the next one.
        let midnight = try item("nosleep.\(dstDay)", in: list)
        #expect(midnight.start == DayFormat.date(from: dstDay))
        let span = (DayFormat.date(from: DayFormat.string(from: change.addingTimeInterval(86_400))) ?? .distantPast)
            .timeIntervalSince(midnight.start)
        #expect(span == 23 * 3_600 || span == 25 * 3_600)
    }

    @Test func anActivityIsNeverDoubledAcrossTheServerListTheLocalRowAndAnEdit() {
        let server = activity(1, .yoga, origin: .manual, from: at(13), strain: 4)
        let confirmed = local(1, from: at(13), revision: 1, confirmed: 1)
        let edit = local(1, from: at(13), revision: 2, confirmed: 1)
        for locals in [[], [confirmed], [edit], [confirmed, edit], [edit, edit]] {
            let list = rows(input(detail(), activities: [server, server], local: locals))
            #expect(ids(list.filter { !$0.kind.isSleep }) == [activityID(1)], "locals: \(locals.count)")
        }
    }

    @Test func aWorkoutIdListedTwiceIsOneRow() {
        // Distinct ids stay distinct rows (the platform decides duplicates); one id never makes two rows.
        let w = workout(10, from: at(7))
        let twin = workout(11, from: at(7))
        let list = rows(input(detail(workouts: [w, w, twin])))
        #expect(ids(list.filter { !$0.kind.isSleep }) == [workoutID(10), workoutID(11)])
    }

    @Test func aRowsFactsBreakOnlyBetweenPartsAndTheBulletTrailsItsLine() throws {
        let w = workout(10, from: at(7), minutes: 68, distanceM: 11_700)
        let facts = MyDayRow.detail(try item(workoutID(10), in: rows(input(detail(workouts: [w])))))
        let parts = facts.components(separatedBy: "\u{00A0}· ")
        #expect(parts.count == 3, "\(facts)")
        // The only breakable space is the one after each bullet.
        #expect(parts.allSatisfy { !$0.contains(" ") }, "\(facts)")
        #expect(MyDayText.join(["1h 08m", "11.7 km"]) == "1h\u{00A0}08m\u{00A0}· 11.7\u{00A0}km")
    }

    @Test func aMergedActivityListedTwiceStillHidesItsWorkoutOnce() {
        let a = activity(1, .running, from: at(7), mergedWith: uuid(10))
        let list = rows(input(detail(workouts: [workout(10, from: at(7))]), activities: [a, a]))
        #expect(ids(list.filter { !$0.kind.isSleep }) == [activityID(1)])
    }

    @Test func aSessionAndItsWorkoutAreNeverTwoRowsWhereverTheSessionComesFrom() throws {
        let s = try session(1, from: at(17), workoutID: uuid(10))
        let w = workout(10, from: at(17))
        for sessions in [([s], [SessionSummary]()), ([], [s]), ([s], [s])] {
            let list = rows(input(detail(workouts: [w], sessions: sessions.1), sessions: sessions.0))
            #expect(ids(list.filter { !$0.kind.isSleep }) == [workoutID(10)])
        }
    }
}
