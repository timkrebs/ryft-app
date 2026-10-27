import Foundation
import Testing
@testable import Ryft

private typealias F = ImportBuildFixture

/// ADR 0007's recipe for plans, days and sessions: vectors computed independently (Python's `uuid.uuid5`), and the
/// properties a re-import relies on.
@Suite("Import ids: plans and sessions")
struct ImportSessionIDsTests {
    @Test func recipeVectors() throws {
        let account = ImportIDs.account("demo")
        let start = try #require(F.date("2026-02-02"))
        let plan = ImportIDs.plan(account: account, source: .alphaProgression, name: "Strength Base", startDate: start)
        #expect(plan.uuidString.lowercased() == "cee2eda2-3346-5bc9-93d0-3706d7728d66")
        #expect(ImportIDs.plan(account: account, source: .alphaProgression, name: "Strength Base", startDate: nil)
            .uuidString.lowercased() == "96ea9e62-5392-5d8a-9ac9-6c310a7d5f62")
        let day = ImportIDs.planDay(plan: plan, number: 2, occurrence: 0)
        #expect(day.uuidString.lowercased() == "ecd409df-a096-51b7-9d87-062cdf3186bd")
        #expect(ImportIDs.planDay(plan: plan, number: 2, occurrence: 1).uuidString.lowercased()
            == "53ef9370-0141-563a-a8f3-4ac4a5ce9032")
        let deadlift = SourceExerciseKey(name: "deadlift", equipment: "barbell")
        #expect(ImportIDs.planExercise(day: day, key: deadlift, occurrence: 0).uuidString.lowercased()
            == "2dcb4066-5b26-528b-9da3-eec794e6faf5")
        let time = try #require(F.time("2026-03-10", 7, 5))
        let session = ImportIDs.session(account: account, source: .alphaProgression, start: time, occurrence: 0)
        #expect(session.uuidString.lowercased() == "f5bc537f-55e7-5dd2-8483-1015d5a844a6")
        #expect(ImportIDs.session(account: account, source: .alphaProgression, start: time, occurrence: 1)
            .uuidString.lowercased() == "b9ccf233-e802-53db-9417-e9e7903bb332")
        let exercise = ImportIDs.sessionExercise(session: session, key: deadlift, occurrence: 0)
        #expect(exercise.uuidString.lowercased() == "42d129de-c89a-5a31-a173-caa7b56022a1")
        #expect(ImportIDs.set(exercise: exercise, ordinal: 2).uuidString.lowercased() == "b57fdf18-7830-5374-9c6d-3503950ce1a2")
    }

    /// The fixture's own ids are the recipe's: the plan's name and start date, the session's wall clock.
    /// Plans whose names fold the same and that share a start date (or have none): the second adds its occurrence.
    @Test func plansOfOneNameGetTheirOccurrence() throws {
        let account = ImportIDs.account("demo")
        #expect(ImportIDs.plan(account: account, source: .alphaProgression, name: "My Plan", startDate: nil)
            .uuidString.lowercased() == "aad631e5-e5ae-5438-8338-c12655a90d85")
        #expect(ImportIDs.plan(account: account, source: .alphaProgression, name: "my plan", startDate: nil, occurrence: 1)
            .uuidString.lowercased() == "438f2882-5138-568e-9cc5-9fb0033ccb3e")
        func plan(_ name: String, _ exercise: String, start: String? = nil, line: Int) -> ImportedPlan {
            let row = ImportedPlanExercise(order: 1, name: exercise, equipment: "Barbell", sets: 3, targetReps: 5...5)
            return ImportedPlan(name: name, weeks: nil, startDate: start.flatMap(F.date),
                                days: [ImportedDay(number: 1, name: "A", exercises: [row])], source: SourceLine(file: 0, line: line))
        }
        let bundle = F.bundle([], plans: [plan("My Plan", "Deadlift", line: 1), plan("MY  PLAN", "Hip Thrust", line: 10),
                                          plan("My Plan", "Deadlift", start: "2026-02-02", line: 20)])
        let ids = ImportBuilder.planIDs(of: bundle, account: account)
        #expect(ids.map { $0.uuidString.lowercased() }.prefix(2) == ["aad631e5-e5ae-5438-8338-c12655a90d85",
                                                                      "438f2882-5138-568e-9cc5-9fb0033ccb3e"])
        // Another start date is another plan: its own first occurrence.
        #expect(ids[2] == ImportIDs.plan(account: account, source: .alphaProgression, name: "My Plan", startDate: F.date("2026-02-02")))
        let build = try F.build(bundle, F.decisions())
        let upload = build.uploadPlan(including: build.defaultIncluded)
        #expect(upload.plans.map(\.id) == ids)
        #expect(Set(upload.plans.flatMap(\.days).map(\.id)).count == 3)
        #expect(ImportBuilder.query(for: bundle, decisions: F.decisions()).planIDs == ids)
    }

    @Test func theFixtureBuildsTheRecipesIDs() throws {
        let build = try F.build(F.bundle(), F.decisions())
        let plan = try #require(build.plans.first)
        #expect(plan.id.uuidString.lowercased() == "cee2eda2-3346-5bc9-93d0-3706d7728d66")
        let pull = try #require(build.plans.first?.plan?.days.first { $0.dayIndex == 1 })
        #expect(pull.id.uuidString.lowercased() == "ecd409df-a096-51b7-9d87-062cdf3186bd")
        #expect(pull.exercises.first?.id.uuidString.lowercased() == "2dcb4066-5b26-528b-9da3-eec794e6faf5")
        let session = try #require(build.sessions.first { $0.id.uuidString.lowercased() == "f5bc537f-55e7-5dd2-8483-1015d5a844a6" })
        let deadlift = try #require(session.session?.exercises.first)
        #expect(deadlift.id.uuidString.lowercased() == "42d129de-c89a-5a31-a173-caa7b56022a1")
        #expect(deadlift.sets.last?.id.uuidString.lowercased() == "b57fdf18-7830-5374-9c6d-3503950ce1a2")
    }

    @Test func theSameInputGivesTheSameBuild() throws {
        let first = try F.build(F.bundle(), F.decisions())
        let second = try F.build(F.bundle(), F.decisions())
        #expect(first == second)
        #expect(Set(first.sessions.map(\.id)).count == 6)
    }

    @Test func oneExtraWorkoutGivesExactlyOneNewID() throws {
        let before = Set(try F.build(F.bundle(), F.decisions()).sessions.map(\.id))
        let after = Set(try F.build(F.bundle(workouts: "ap-workouts-plus1"), F.decisions()).sessions.map(\.id))
        #expect(before.isSubset(of: after))
        #expect(after.subtracting(before).count == 1)
    }

    /// Everything already on the account: the upload is empty and the preview says so.
    @Test func aReimportSendsNothing() throws {
        let bundle = try F.bundle()
        let first = try F.build(bundle, F.decisions())
        let existing = ImportExisting(checked: true, plans: Dictionary(uniqueKeysWithValues: first.plans.map { ($0.id, $0.plan) }),
                                      sessionIDs: Set(first.sessions.map(\.id)), logged: [])
        let again = try F.build(bundle, F.decisions(), existing: existing)
        let verdicts = again.sessions.map(\.verdict)
        #expect(verdicts == Array(repeating: .alreadyImported, count: 6))
        #expect(again.plans.map(\.state) == [.alreadyInRYFT])
        let upload = again.uploadPlan(including: again.defaultIncluded)
        #expect(upload.plans.isEmpty && upload.sessions.isEmpty && upload.exercises.isEmpty)
        #expect(upload.skipped.alreadyImported == 6 && upload.skipped.plans == 1)
        #expect(again.totals(including: again.defaultIncluded).isNothing)
    }

    @Test func anotherZoneOrAnotherOrderKeepsTheIDs() throws {
        let berlin = try F.build(F.bundle(), F.decisions())
        let newYork = try F.build(F.bundle(), F.decisions(zone: TimeZone(identifier: "America/New_York") ?? .gmt))
        #expect(berlin.sessions.map(\.id) == newYork.sessions.map(\.id))
        #expect(berlin.sessions.map(\.startedAt) != newYork.sessions.map(\.startedAt))
        let rows: [(String, [(ImportedLoad?, Int?)])] = [("Deadlift", [(.weight(kg: 100), 5)]), ("Hip Thrust", [(.weight(kg: 80), 8)])]
        let one = try F.build(F.bundle([F.session(exercises: rows)]), F.decisions())
        let other = try F.build(F.bundle([F.session(exercises: Array(rows.reversed()))]), F.decisions())
        let a = try #require(one.sessions.first?.session), b = try #require(other.sessions.first?.session)
        #expect(a.id == b.id)
        #expect(Set(a.exercises.map(\.id)) == Set(b.exercises.map(\.id)))
        #expect(a.exercises.map(\.position) == [0, 1] && a.exercises.first?.id == b.exercises.last?.id)
    }

    @Test func twoAccountsNeverShareAnID() throws {
        let demo = try F.build(F.bundle(), F.decisions(account: "demo"))
        let other = try F.build(F.bundle(), F.decisions(account: "8f7c2a1e-3b4d-4c5e-9f60-1a2b3c4d5e6f"))
        let ids = Set(demo.sessions.map(\.id) + demo.plans.map(\.id))
        #expect(ids.isDisjoint(with: other.sessions.map(\.id) + other.plans.map(\.id)))
    }

    /// Two workouts that start in the same minute: told apart by their occurrence, counted from the oldest (the
    /// file's end), so a newer export that adds one at the top keeps the older ids.
    @Test func workoutsAtTheSameMinuteKeepTheirIDsWhenANewerOneIsAdded() throws {
        let older = F.session(title: "A", exercises: [("Deadlift", [(.weight(kg: 100), 5)])])
        let newer = F.session(title: "B", exercises: [("Hip Thrust", [(.weight(kg: 80), 8)])])
        let two = try F.build(F.bundle([newer, older]), F.decisions())
        let three = try F.build(F.bundle([newer, newer, older]), F.decisions())
        #expect(Set(two.sessions.map(\.id)).count == 2)
        #expect(three.sessions.last?.id == two.sessions.last?.id)
        #expect(three.sessions[1].id == two.sessions[0].id)
    }
}

@Suite("Import builder: sessions")
struct ImportBuilderSessionTests {
    @Test func theFixtureBecomesSixCompletedSessions() throws {
        let build = try F.build(F.bundle(), F.decisions())
        #expect(build.sessions.count == 6)
        #expect(build.sessions.map(\.verdict) == Array(repeating: .new, count: 6))
        #expect(build.sessions.compactMap(\.session?.status) == Array(repeating: .completed, count: 6))
        let totals = build.totals(including: build.defaultIncluded)
        #expect(totals.sessions == 6 && totals.sets == 38 && totals.skippedSets == 4 && totals.plans == 1)
        let upload = build.uploadPlan(including: build.defaultIncluded)
        // Oldest first.
        #expect(upload.sessions.map(\.startedAt) == upload.sessions.map(\.startedAt).sorted())
        #expect(upload.sessions.map(\.title) == ["Shoulders", "Push", "Pull", "Legs", "Pull", "Push"])
        #expect(upload.skipped.skippedSets == 4)
        // Never a skipped set, never a warm-up, every set completed.
        let sets = upload.sessions.flatMap(\.exercises).flatMap(\.sets)
        #expect(sets.count == 38)
        #expect(sets.filter { ($0.reps ?? 0) > 0 && !$0.isWarmup && $0.completedAt != nil }.count == 38)
    }

    /// The k-th of n performed sets completes at start + duration × (k + 1) / n, in whole seconds; `updated_at` equals
    /// it, so a re-send is identical (T10).
    @Test func setsCompleteEvenlyOverTheDuration() throws {
        let build = try F.build(F.bundle(), F.decisions())
        let pull = try #require(build.sessions.first { $0.session?.startedAt == $0.startedAt && $0.day.key == "2026-03-10" }?.session)
        let times = pull.exercises.flatMap(\.sets).compactMap(\.completedAt)
        #expect(times.count == 8)
        // 72 min over 8 sets: every 540 s, the last at the end.
        #expect(times.map { $0.timeIntervalSince(pull.startedAt) } == [540, 1_080, 1_620, 2_160, 2_700, 3_240, 3_780, 4_320])
        #expect(pull.endedAt == pull.startedAt.addingTimeInterval(4_320))
        #expect(pull.exercises.flatMap(\.sets).filter { $0.updatedAt != $0.completedAt }.isEmpty)
        // Whole seconds: the encoder keeps them, so a decoded copy is equal.
        let data = try APIClient.jsonEncoder.encode(pull)
        let decoded = try APIClient.jsonDecoder.decode(TrainSession.self, from: data)
        #expect(decoded == pull)
    }

    @Test func uneventSplitsRoundDown() throws {
        let three = F.session(minutes: 1, exercises: [("Deadlift", [(.weight(kg: 100), 5), (.weight(kg: 100), 5), (.weight(kg: 100), 5)])])
        let built = try F.build(F.bundle([three]), F.decisions())
        let session = try #require(built.sessions.first?.session)
        #expect(session.exercises.flatMap(\.sets).compactMap(\.completedAt).map { $0.timeIntervalSince(session.startedAt) } == [20, 40, 60])
        let seven = F.session(minutes: 1, exercises: [("Deadlift", Array(repeating: (.weight(kg: 100), 5), count: 7))])
        let builtSeven = try F.build(F.bundle([seven]), F.decisions())
        let other = try #require(builtSeven.sessions.first?.session)
        #expect(other.exercises.flatMap(\.sets).compactMap(\.completedAt).map { $0.timeIntervalSince(other.startedAt) }
            == [8, 17, 25, 34, 42, 51, 60])
    }

    @Test func aMissingDurationIsAnHour() throws {
        let file = F.session(minutes: nil, exercises: [("Deadlift", [(.weight(kg: 100), 5)])])
        let build = try F.build(F.bundle([file]), F.decisions())
        let session = try #require(build.sessions.first?.session)
        #expect(session.endedAt == session.startedAt.addingTimeInterval(3_600))
        #expect(build.warnings.map(\.kind) == [.durationAssumed])
    }

    /// `+N` per the answer (design §5): body weight leaves the set without load and tells the session; added weight is
    /// the set's load; ignore drops it; a +10 is never offered as a body weight.
    @Test(arguments: [BodyweightAnswer.bodyWeight, .addedWeight, .ignore])
    func plusLoadsFollowTheAnswer(_ answer: BodyweightAnswer) throws {
        let build = try F.build(F.bundle(), F.decisions(answers: ["Pull-Ups": answer]))
        let pull = try #require(build.sessions.first { $0.day.key == "2026-03-10" }?.session)
        let pullUps = try #require(pull.exercises.first { $0.exerciseId == F.exercise("Pull-Ups").id })
        switch answer {
        case .bodyWeight:
            #expect(pullUps.sets.map(\.weightKg) == [nil, nil, nil] && pull.bodyweightKg == 80)
        case .addedWeight:
            #expect(pullUps.sets.map(\.weightKg) == [80, 80, 80] && pull.bodyweightKg == nil)
        case .ignore:
            #expect(pullUps.sets.map(\.weightKg) == [nil, nil, nil] && pull.bodyweightKg == nil)
        }
        let push = try #require(build.sessions.first { $0.day.key == "2026-03-14" }?.session)
        #expect(push.exercises.first { $0.exerciseId == F.exercise("Push-Ups").id }?.sets.map(\.weightKg) == [10, 10])
        #expect(push.bodyweightKg == nil)
    }

    /// With no answer: the default per design §5 (the same N on every set within 30–300 kg: body weight).
    @Test func theDefaultAnswerIsBodyWeightForAUniformPlausibleN() throws {
        let build = try F.build(F.bundle(), F.decisions())
        let pull = try #require(build.sessions.first { $0.day.key == "2026-03-10" }?.session)
        #expect(pull.bodyweightKg == 80)
    }

    /// The session's body weight is the most common N; on a tie the first.
    @Test func severalBodyWeightsTakeTheMostCommon() throws {
        let sets: [(ImportedLoad?, Int?)] = [(.plus(kg: 81), 5), (.plus(kg: 80), 5), (.plus(kg: 80), 5)]
        let file = F.session(exercises: [("Pull-Ups", sets)])
        let built = try F.build(F.bundle([file]), F.decisions(answers: ["Pull-Ups": .bodyWeight]))
        let session = try #require(built.sessions.first?.session)
        #expect(session.bodyweightKg == 80)
        let tie = F.session(exercises: [("Pull-Ups", [(.plus(kg: 81), 5), (.plus(kg: 80), 5)])])
        let builtTie = try F.build(F.bundle([tie]), F.decisions(answers: ["Pull-Ups": .bodyWeight]))
        let other = try #require(builtTie.sessions.first?.session)
        #expect(other.bodyweightKg == 81)
    }

    @Test func thePlatformsLimitsAreAppliedHere() throws {
        let sets: [(ImportedLoad?, Int?)] = [(.weight(kg: 600), 5), (.weight(kg: 100), 150), (.minus(kg: 20), 8), (.weight(kg: 500), 100)]
        let file = F.session(exercises: [("Deadlift", sets)])
        let build = try F.build(F.bundle([file]), F.decisions())
        let session = try #require(build.sessions.first?.session)
        #expect(session.exercises.first?.sets.map(\.weightKg) == [500, 100, nil, 500])
        #expect(session.exercises.first?.sets.map(\.reps) == [5, 100, 8, 100])
        #expect(build.warnings.map(\.kind) == [.overPlatformLimit, .assistedLoad])
    }

    @Test func moreThanFiftyExercisesOrSetsAreCut() throws {
        let many = (0..<51).map { _ in (ImportedLoad?.some(.weight(kg: 50)), Int?.some(5)) }
        let wide = F.session(exercises: [("Deadlift", many)])
        let build = try F.build(F.bundle([wide]), F.decisions())
        #expect(build.sessions.first?.session?.exercises.first?.sets.count == 50)
        #expect(build.warnings.map(\.kind) == [.overPlatformLimit])
        let rows = (0..<51).map { _ in ("Deadlift", [(ImportedLoad?.some(.weight(kg: 50)), Int?.some(5))]) }
        let long = F.session(exercises: rows)
        let other = try F.build(F.bundle([long]), F.decisions())
        #expect(other.sessions.first?.session?.exercises.count == 50)
        #expect(Set(other.sessions.first?.session?.exercises.map(\.id) ?? []).count == 50)
    }

    /// A `time` or `distance` exercise records no weight: reps stay.
    @Test func timeExercisesDropTheLoad() throws {
        var decisions = F.decisions()
        let plank = Exercise(id: F.id(50), slug: "plank", name: "Plank", kind: .bodyweight, primaryMuscles: [.abs], loadType: .time)
        decisions.exercises[F.key("Deadlift")] = ImportExerciseChoice(.library(plank))
        let file = F.session(exercises: [("Deadlift", [(.weight(kg: 100), 5), (.plus(kg: 10), 6)])])
        let built = try F.build(F.bundle([file]), decisions)
        let session = try #require(built.sessions.first?.session)
        #expect(session.exercises.first?.sets.map(\.weightKg) == [nil, nil])
        #expect(session.exercises.first?.sets.map(\.reps) == [5, 6])
    }

    @Test func titlesAreCleanedAndCutTo120() throws {
        let long = String(repeating: "Ü", count: 130)
        let file = F.session(title: "\u{200B}" + long, exercises: [("Deadlift", [(.weight(kg: 100), 5)])])
        let built = try F.build(F.bundle([file]), F.decisions())
        let title = try #require(built.sessions.first?.session?.title)
        #expect(title == String(repeating: "Ü", count: 120))
    }

    /// Spring forward in Berlin: 02:30 doesn't exist and moves to 03:30, noted on the session and in its warning.
    @Test func aClockChangeIsNoted() throws {
        let gap = F.session(day: "2026-03-29", hour: 2, minute: 30, exercises: [("Deadlift", [(.weight(kg: 100), 5)])])
        let build = try F.build(F.bundle([gap]), F.decisions())
        let session = try #require(build.sessions.first)
        #expect(session.clockChange == .nonexistentLocalTime)
        #expect(build.warnings.map(\.kind) == [.nonexistentLocalTime])
        #expect(build.totals(including: build.defaultIncluded).clockChanges == 1)
        #expect(session.startedAt == Date(timeIntervalSince1970: 1_774_747_800)) // 2026-03-29T01:30Z = 03:30 CEST
    }
}

@Suite("Import builder: verdicts")
struct ImportBuilderVerdictTests {
    @Test func historyOffBuildsNoSession() throws {
        let build = try F.build(F.bundle(), F.decisions(history: ImportHistoryChoice(included: false)))
        #expect(build.sessions.map(\.verdict) == Array(repeating: .historyOff, count: 6))
        #expect(build.sessions.compactMap(\.session).isEmpty)
        #expect(build.uploadPlan(including: Set(build.sessions.map(\.id))).sessions.isEmpty)
        #expect(build.warnings.isEmpty)
    }

    @Test func theRangeIsInclusiveOnBothEnds() throws {
        let range = ImportHistoryChoice(included: true, from: F.date("2026-02-03"), to: F.date("2026-03-10"))
        let build = try F.build(F.bundle(), F.decisions(history: range))
        let kept = build.sessions.filter { $0.verdict == .new }.map(\.day.key).sorted()
        #expect(kept == ["2026-02-03", "2026-02-05", "2026-03-01", "2026-03-10"])
        #expect(build.totals(including: build.defaultIncluded).outsideRange == 2)
        #expect(build.uploadPlan(including: build.defaultIncluded).skipped.outsideRange == 2)
    }

    @Test func aWorkoutAfterNowIsLeftOut() throws {
        let now = Date(timeIntervalSince1970: 1_773_500_000) // 2026-03-14T14:53Z, before Push at 17:45 Berlin
        let build = try F.build(F.bundle(), F.decisions(), now: now)
        #expect(build.sessions.filter { $0.verdict == .inFuture }.map(\.day.key) == ["2026-03-14"])
    }

    @Test func aWorkoutWithNothingPerformedIsEmpty() throws {
        let file = F.session(exercises: [("Cable Fly", [(nil, nil), (nil, 0)]), ("Deadlift", [(.weight(kg: 100), 5)])])
        let build = try F.build(F.bundle([file]), F.decisions(skipping: ["Deadlift"]))
        #expect(build.sessions.first?.verdict == .empty)
        #expect(build.uploadPlan(including: build.defaultIncluded).skipped.empty == 1)
    }

    /// A session the user logged in RYFT on the same day with ≥ 70 % of the exercises: off by default, and a toggle sends it.
    @Test func aDuplicateIsOffByDefaultAndCanBeTurnedOn() throws {
        let bundle = try F.bundle()
        let first = try F.build(bundle, F.decisions())
        let pull = try #require(first.sessions.first { $0.day.key == "2026-03-10" })
        let logged = LoggedSession(id: F.id(900), startedAt: pull.startedAt.addingTimeInterval(3_600),
                                   exerciseIDs: [F.exercise("Deadlift").id, F.exercise("Pull-Ups").id, F.exercise("Seated Cable Row").id])
        let build = try F.build(bundle, F.decisions(), existing: ImportExisting(checked: true, plans: [:], sessionIDs: [], logged: [logged]))
        let flagged = try #require(build.sessions.first { $0.id == pull.id })
        #expect(flagged.verdict == .duplicate(of: F.id(900)))
        #expect(!build.defaultIncluded.contains(pull.id))
        #expect(build.uploadPlan(including: build.defaultIncluded).sessions.map(\.id).contains(pull.id) == false)
        #expect(build.uploadPlan(including: build.defaultIncluded).skipped.duplicates == 1)
        #expect(build.uploadPlan(including: build.defaultIncluded.union([pull.id])).sessions.map(\.id).contains(pull.id))
        #expect(build.totals(including: build.defaultIncluded).duplicatesOff == 1)
    }

    /// The account's copy of an earlier import is "already imported", never a duplicate of itself.
    @Test func anEarlierImportIsNeverItsOwnDuplicate() throws {
        let bundle = try F.bundle()
        let first = try F.build(bundle, F.decisions())
        let pull = try #require(first.sessions.first { $0.day.key == "2026-03-10" })
        let copy = LoggedSession(id: pull.id, startedAt: pull.startedAt, exerciseIDs: Set(pull.session?.exercises.map(\.exerciseId) ?? []))
        let build = try F.build(bundle, F.decisions(), existing: ImportExisting(checked: true, plans: [:], sessionIDs: [], logged: [copy]))
        #expect(build.sessions.map(\.verdict) == Array(repeating: .new, count: 6))
    }

    @Test func deselectedSessionsAreCountedAsSuch() throws {
        let build = try F.build(F.bundle(), F.decisions())
        let off = try #require(build.sessions.first?.id)
        let upload = build.uploadPlan(including: build.defaultIncluded.subtracting([off]))
        #expect(upload.sessions.count == 5 && upload.skipped.deselected == 1 && upload.skipped.duplicates == 0)
    }
}

@Suite("Import builder: plans")
struct ImportBuilderPlanTests {
    @Test func theFilesPlanIsAValidRYFTPlan() throws {
        let build = try F.build(F.bundle(), F.decisions())
        let preview = try #require(build.plans.first)
        let plan = try #require(preview.plan)
        #expect(preview.state == .new && preview.willBeSent)
        #expect(PlanValidation.issues(in: plan).isEmpty)
        #expect(plan.name == "Strength Base" && plan.weeks == 6 && plan.daysPerWeek == 2 && plan.goal == .general)
        #expect(plan.progression == .linear && !plan.isBuiltin)
        #expect(plan.days.map(\.dayIndex) == [0, 1] && plan.days.map(\.name) == ["Push", "Pull"])
        let push = try #require(plan.days.first)
        #expect(push.exercises.map(\.position) == [0, 1, 2])
        #expect(push.exercises.map(\.sets) == [4, 3, 3])
        #expect(push.exercises.map(\.repsMin) == [6, 8, 12] && push.exercises.map(\.repsMax) == [6, 12, 15])
        #expect(push.exercises.map(\.restSec) == [180, 90, 75])
    }

    /// "Last time": the heaviest set of the most recent imported session with the exercise, the same plan day first.
    @Test func targetsComeFromTheLatestSessionOfTheSamePlanDay() throws {
        let build = try F.build(F.bundle(), F.decisions())
        let preview = try #require(build.plans.first)
        let plan = try #require(preview.plan)
        func row(_ name: String) -> PlanExercise? { plan.days.flatMap(\.exercises).first { $0.exercise.name == name } }
        // Overhead press: the plan's Push (47.5 on 3 Feb), not the newer standalone Push (52.5 on 14 Mar).
        let press = try #require(row("Overhead Press"))
        #expect(press.targetKind == .kg && press.targetValue == 47.5)
        let pushDay = try #require(F.date("2026-02-03"))
        let pushID = try #require(build.sessions.first { $0.day.key == "2026-02-03" }?.id)
        #expect(preview.lastTime[press.id] == ImportLastTime(kg: 47.5, day: pushDay, sessionID: pushID))
        // Deadlift: the newer of the two Pull sessions (130 on 10 Mar, not 110 on 5 Feb).
        #expect(row("Deadlift")?.targetValue == 130)
        // Cable fly: the plan's Push (17.5); the newer standalone Push has only skipped sets anyway.
        #expect(row("Cable Fly")?.targetValue == 17.5)
        #expect(row("Walking Lunges")?.targetValue == 16)
        // Bodyweight exercises: no value (T11).
        #expect(row("Pull-Ups")?.targetKind == .bodyweight && row("Pull-Ups")?.targetValue == nil)
    }

    @Test func withoutHistoryTargetsAreRPE8() throws {
        let build = try F.build(F.bundle(), F.decisions(history: ImportHistoryChoice(included: false)))
        let plan = try #require(build.plans.first?.plan)
        let weighted = plan.days.flatMap(\.exercises).filter { $0.exercise.loadType == .weight }
        #expect(!weighted.isEmpty)
        #expect(weighted.filter { $0.targetKind != .rpe || $0.targetValue != 8 }.isEmpty)
        #expect(build.plans.first?.lastTime.isEmpty == true)
        #expect(PlanValidation.issues(in: plan).isEmpty)
    }

    @Test func skippedRowsGoAndAnEmptyDayWithThem() throws {
        let build = try F.build(F.bundle(), F.decisions(skipping: ["Overhead Press", "Push-Ups", "Cable Fly", "Walking Lunges"]))
        let preview = try #require(build.plans.first)
        #expect(preview.skippedExerciseNames == ["Overhead Press", "Push-Ups", "Cable Fly", "Walking Lunges"])
        #expect(preview.plan?.days.map(\.name) == ["Pull"] && preview.plan?.daysPerWeek == 1)
        #expect(preview.plan?.days.first?.dayIndex == 0)
        let none = try F.build(F.bundle(), F.decisions(skipping: Set(F.sources.map { $0.name })))
        #expect(none.plans.first?.state == .cannotImport(.noExercises) && none.plans.first?.plan == nil)
        #expect(none.plans.first?.willBeSent == false)
    }

    @Test func moreThanSevenDaysCantBeImported() throws {
        let exercise = ImportedPlanExercise(order: 1, name: "Deadlift", equipment: "Barbell", sets: 3, targetReps: 5...5)
        let days = (1...8).map { ImportedDay(number: $0, name: "Day \($0)", exercises: [exercise]) }
        let plan = ImportedPlan(name: "Eight", weeks: 4, startDate: nil, days: days, source: SourceLine(file: 0, line: 1))
        let build = try F.build(F.bundle([], plans: [plan]), F.decisions())
        #expect(build.plans.first?.state == .cannotImport(.tooManyDays(8)))
        let seven = ImportedPlan(name: "Seven", weeks: 4, startDate: nil, days: Array(days.prefix(7)), source: SourceLine(file: 0, line: 1))
        let sevenDays = try F.build(F.bundle([], plans: [seven]), F.decisions())
        #expect(sevenDays.plans.first?.state == .new)
    }

    /// A day number written twice: both days stay, with different ids; sets and reps are clamped to the builder's limits.
    @Test func duplicateDaysAndOutOfRangeValues() throws {
        let wild = ImportedPlanExercise(order: 1, name: "Deadlift", equipment: "Barbell", sets: 40, targetReps: 0...300)
        let days = [ImportedDay(number: 1, name: "A", exercises: [wild]), ImportedDay(number: 1, name: "B", exercises: [wild])]
        let plan = ImportedPlan(name: "Twice", weeks: 60, startDate: nil, days: days, source: SourceLine(file: 0, line: 1))
        let build = try F.build(F.bundle([], plans: [plan]), F.decisions())
        let built = try #require(build.plans.first?.plan)
        #expect(built.days.count == 2 && Set(built.days.map(\.id)).count == 2)
        #expect(built.weeks == nil)
        #expect(built.days.first?.exercises.first.map { [$0.sets, $0.repsMin, $0.repsMax] } == [20, 1, 100])
        #expect(PlanValidation.issues(in: built).isEmpty)
    }

    /// Sessions point into a plan that's sent, or one already in RYFT whose copy still has the day; never into one that
    /// isn't there.
    @Test func sessionsLinkOnlyToAPlanThatWillBeThere() throws {
        let bundle = try F.bundle()
        let sent = try F.build(bundle, F.decisions())
        let plan = try #require(sent.plans.first?.plan)
        let pullDay = try #require(plan.days.last)
        func pull(_ build: ImportBuild) -> TrainSession? { build.sessions.first { $0.day.key == "2026-03-10" }?.session }
        #expect(pull(sent)?.planDayId == pullDay.id)
        #expect(pull(sent)?.exercises.first?.planExerciseId == pullDay.exercises.first?.id)
        // Standalone workouts never link.
        #expect(sent.sessions.first { $0.day.key == "2026-03-14" }?.session?.planDayId == nil)

        let off = try F.build(bundle, F.decisions(plans: [ImportPlanChoice(included: false)]))
        #expect(pull(off)?.planDayId == nil)
        #expect(pull(off)?.exercises.compactMap(\.planExerciseId) == [])
        #expect(off.uploadPlan(including: off.defaultIncluded).skipped.plans == 1)

        let kept = ImportExisting(checked: true, plans: [plan.id: plan], sessionIDs: [], logged: [])
        let inRYFT = try F.build(bundle, F.decisions(), existing: kept)
        #expect(inRYFT.plans.first?.state == .alreadyInRYFT && inRYFT.plans.first?.willBeSent == false)
        #expect(pull(inRYFT)?.planDayId == pullDay.id)

        var edited = plan
        edited.days.removeLast()
        let gone = try F.build(bundle, F.decisions(), existing: ImportExisting(checked: true, plans: [plan.id: edited], sessionIDs: [], logged: []))
        #expect(pull(gone)?.planDayId == nil)
        let unread = try F.build(bundle, F.decisions(), existing: ImportExisting(checked: true, plans: [plan.id: nil], sessionIDs: [], logged: []))
        #expect(pull(unread)?.planDayId == nil)

        let replaced = try F.build(bundle, F.decisions(plans: [ImportPlanChoice(included: true, replaceExisting: true)]), existing: kept)
        #expect(replaced.plans.first?.willBeSent == true)
        #expect(replaced.uploadPlan(including: replaced.defaultIncluded).plans.map(\.id) == [plan.id])
    }

    @Test func theEnrolmentNeedsAPlanThatWillBeThere() throws {
        let bundle = try F.bundle()
        let sent = try F.build(bundle, F.decisions(enrol: 0))
        #expect(sent.enrolPlanID == sent.plans.first?.id && sent.enrolPlanID != nil)
        let off = try F.build(bundle, F.decisions(plans: [ImportPlanChoice(included: false)], enrol: 0))
        #expect(off.enrolPlanID == nil)
        let refused = try F.build(bundle, F.decisions(skipping: Set(F.sources.map { $0.name }), enrol: 0))
        #expect(refused.enrolPlanID == nil)
        let missing = try F.build(bundle, F.decisions(enrol: 3))
        #expect(missing.enrolPlanID == nil)
        // Already in RYFT: its copy is enrolled in.
        let plan = try #require(sent.plans.first?.plan)
        let kept = try F.build(bundle, F.decisions(enrol: 0), existing: ImportExisting(checked: true, plans: [plan.id: plan], sessionIDs: [], logged: []))
        #expect(kept.enrolPlanID == plan.id)
    }

    @Test func aRenamedPlanKeepsItsID() throws {
        let build = try F.build(F.bundle(), F.decisions())
        let id = try #require(build.plans.first?.id)
        #expect(build.uploadPlan(including: [], planNames: [id: "  My Plan  "]).plans.map(\.name) == ["My Plan"])
        #expect(build.uploadPlan(including: [], planNames: [id: String(repeating: "x", count: 90)]).plans.first?.name.count == 80)
        #expect(build.uploadPlan(including: [], planNames: [id: " \u{200B} "]).plans.map(\.name) == ["Strength Base"])
        #expect(build.uploadPlan(including: [], planNames: [id: "My Plan"]).plans.map(\.id) == [id])
    }

    /// A new exercise from step 4 goes up only when something sent uses it.
    @Test func customExercisesGoOnlyWhenUsed() throws {
        var decisions = F.decisions()
        let custom = Exercise(id: F.id(77), slug: "hip-thrust", name: "Hip Thrust", kind: .barbell, primaryMuscles: [.glutes], isCustom: true)
        decisions.exercises[F.key("Hip Thrust")] = ImportExerciseChoice(.custom(custom))
        let build = try F.build(F.bundle(), decisions)
        #expect(build.customExercises.map(\.id) == [custom.id])
        #expect(build.uploadPlan(including: build.defaultIncluded).exercises.map(\.id) == [custom.id])
        let legs = try #require(build.sessions.first { $0.day.key == "2026-03-01" }?.id)
        #expect(build.uploadPlan(including: build.defaultIncluded.subtracting([legs])).exercises.isEmpty)
        #expect(build.totals(including: build.defaultIncluded).customExercises == 1)
    }

    /// Several plans of one name: a session goes to the one whose weeks cover its day.
    @Test func aSessionFindsItsPlanByDate() throws {
        let row = ImportedPlanExercise(order: 1, name: "Deadlift", equipment: "Barbell", sets: 3, targetReps: 5...5)
        let day = ImportedDay(number: 1, name: "A", exercises: [row])
        let early = ImportedPlan(name: "Base", weeks: 4, startDate: F.date("2026-01-05"), days: [day], source: SourceLine(file: 0, line: 1))
        let late = ImportedPlan(name: "Base", weeks: 4, startDate: F.date("2026-03-02"), days: [day], source: SourceLine(file: 0, line: 5))
        let ref = ImportedSession.PlanRef(planName: "base", dayNumber: 1, weekNumber: 1)
        let plans = [early, late]
        func index(_ ref: ImportedSession.PlanRef, _ day: String) -> Int? {
            F.date(day).flatMap { ImportPlanAssembly.planIndex(for: ref, on: $0, plans: plans) }
        }
        #expect(index(ref, "2026-01-20") == 0)
        #expect(index(ref, "2026-03-10") == 1)
        // The last day of the first plan's 4 weeks, then the day after.
        #expect(index(ref, "2026-02-01") == 0)
        #expect(index(ref, "2026-02-02") == 0) // latest started
        #expect(index(ref, "2026-05-01") == 1)
        #expect(index(ref, "2025-12-01") == 0) // none started
        let other = ImportedSession.PlanRef(planName: "Other", dayNumber: 1, weekNumber: nil)
        #expect(index(other, "2026-01-20") == nil)
    }
}

@Suite("Import builder: the query")
struct ImportExistingQueryTests {
    @Test func theQueryCoversTheImportsDays() throws {
        let bundle = try F.bundle()
        let query = ImportBuilder.query(for: bundle, decisions: F.decisions())
        #expect(query.planIDs.count == 1 && query.sessionIDs.count == 6)
        #expect(query.sessionIDs == ImportBuilder.sessionIDs(of: bundle, account: ImportIDs.account("demo")))
        #expect(query.days == ["2026-02-01", "2026-02-03", "2026-02-05", "2026-03-01", "2026-03-10", "2026-03-14"])
        let range = try #require(query.range)
        // Berlin midnight on 1 Feb (UTC+1) to the last second of 14 Mar, two days wider on each side: imported again
        // in a zone up to 26 hours away, the edge days' sessions are still read (`existingPadding`).
        #expect(ImportBuilder.existingPadding == 2 * 86_400)
        #expect(range.lowerBound == Date(timeIntervalSince1970: 1_769_900_400 - 172_800))
        #expect(range.upperBound == Date(timeIntervalSince1970: 1_773_529_199 + 172_800))
        #expect(ImportBuilder.query(for: F.bundle([]), decisions: F.decisions()).range == nil)
    }
}
