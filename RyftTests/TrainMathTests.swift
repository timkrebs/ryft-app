import Foundation
import Testing
@testable import Ryft

@Suite("e1RM and volume")
struct E1RMTests {
    @Test func epleyMatchesThePlatform() throws {
        #expect(E1RM.estimate(weightKg: 100, reps: 5) == 100 * (1 + 5.0 / 30))
        let e = try #require(E1RM.estimate(weightKg: 100, reps: 5))
        #expect(E1RM.rounded(e) == 116.5) // 116.67 → nearest 0.5 kg
        #expect(E1RM.estimate(weightKg: 80, reps: 1) == 80 * (1 + 1.0 / 30))
    }

    @Test func repsAboveTwelveAreCapped() {
        #expect(E1RM.estimate(weightKg: 60, reps: 20) == E1RM.estimate(weightKg: 60, reps: 12))
    }

    @Test func missingOrZeroValuesHaveNoEstimate() {
        #expect(E1RM.estimate(weightKg: nil, reps: 5) == nil)
        #expect(E1RM.estimate(weightKg: 100, reps: nil) == nil)
        #expect(E1RM.estimate(weightKg: 0, reps: 5) == nil)
        #expect(E1RM.estimate(weightKg: 100, reps: 0) == nil)
    }

    @Test func bestIgnoresWarmups() {
        let sets = [SessionSet(setIndex: 0, reps: 12, weightKg: 140, isWarmup: true),
                    SessionSet(setIndex: 1, reps: 5, weightKg: 100),
                    SessionSet(setIndex: 2, reps: 8, weightKg: 90)]
        #expect(E1RM.best(of: sets) == 100 * (1 + 5.0 / 30)) // 116.7 beats 90 × 1.267 = 114
    }

    @Test func volumeCountsCompletedWorkingSets() {
        let done = Date.now
        let sets = [SessionSet(setIndex: 0, reps: 5, weightKg: 60, isWarmup: true, completedAt: done),
                    SessionSet(setIndex: 1, reps: 5, weightKg: 100, completedAt: done),
                    SessionSet(setIndex: 2, reps: 5, weightKg: 100, completedAt: done),
                    SessionSet(setIndex: 3, reps: 5, weightKg: 100)] // not checked off
        #expect(Volume.of(sets) == 1000)
    }

    @Test func displayStrings() {
        // Locale-formatted ("82,5" in German), never rounded to whole kilos.
        #expect(Fmt.kgNumber(82.5) == 82.5.formatted(.number.precision(.fractionLength(1))))
        #expect(Fmt.kgNumber(100) == "100")
        #expect(Fmt.prescription(sets: 3, repsMin: 5, repsMax: 5) == "3 × 5")
        #expect(Fmt.prescription(sets: 3, repsMin: 8, repsMax: 12) == "3 × 8–12")
        #expect(Fmt.clock(23 * 60 + 5) == "23:05")
        #expect(Fmt.clock(3730) == "1:02:10")
    }
}

@Suite("Plate calculator")
struct PlateCalculatorTests {
    @Test func loadsEachSideHeaviestFirst() {
        let l = PlateCalculator.load(for: 100)
        #expect(l.perSide == [25, 15])
        #expect(l.total == 100)
    }

    @Test func smallestIncrementIsFiveKilos() {
        #expect(PlateCalculator.load(for: 105).perSide == [25, 15, 2.5])
        #expect(PlateCalculator.load(for: 102.5).total == 100) // one 2.5 per side adds 5 kg
        // 147.5 needs 1.25 kg plates, which the gym set doesn't have: 145 is the closest below.
        let l = PlateCalculator.load(for: 147.5)
        #expect(l.perSide == [25, 25, 10, 2.5])
        #expect(l.total == 145)
    }

    @Test func unloadableTargetsRoundDown() {
        let l = PlateCalculator.load(for: 101)
        #expect(l.perSide == [25, 15])
        #expect(l.total == 100)
    }

    @Test func emptyBarAtOrBelowTwentyKilos() {
        #expect(PlateCalculator.load(for: 20).perSide.isEmpty)
        #expect(PlateCalculator.load(for: 12).total == 20)
    }

    @Test func heavyLoadsUseMultipleTwentyFives() {
        let l = PlateCalculator.load(for: 220)
        #expect(l.perSide == [25, 25, 25, 25])
        #expect(l.total == 220)
    }
}

@Suite("Rest timer")
struct RestTimerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func startsRunningAndCountsDown() {
        var r = RestTimer()
        #expect(r.phase == .idle)
        r.start(seconds: 90, now: t0)
        #expect(r.isRunning)
        #expect(r.remaining(at: t0.addingTimeInterval(30)) == 60)
        #expect(r.fraction(at: t0.addingTimeInterval(45)) == 0.5)
    }

    @Test func finishesExactlyOnce() {
        var r = RestTimer()
        r.start(seconds: 60, now: t0)
        let early = r.tick(now: t0.addingTimeInterval(59))
        let due = r.tick(now: t0.addingTimeInterval(60))
        #expect(!early && due)
        #expect(r.phase == .finished)
        let again = r.tick(now: t0.addingTimeInterval(61))
        #expect(!again)
        r.dismiss()
        #expect(r.phase == .idle)
    }

    @Test func plusAndMinusFifteen() {
        var r = RestTimer()
        r.start(seconds: 60, now: t0)
        r.adjust(by: RestTimer.step, now: t0)
        #expect(r.remaining(at: t0) == 75)
        #expect(r.total == 75) // the ring grows with it
        r.adjust(by: -RestTimer.step, now: t0.addingTimeInterval(10))
        #expect(r.remaining(at: t0.addingTimeInterval(10)) == 50)
        #expect(r.total == 75)
    }

    @Test func minusFifteenPastZeroFinishes() {
        var r = RestTimer()
        r.start(seconds: 60, now: t0)
        let ranOut = r.adjust(by: -RestTimer.step, now: t0.addingTimeInterval(50))
        #expect(ranOut)
        #expect(r.phase == .finished)
    }

    @Test func plusIsCappedAtFifteenMinutes() {
        var r = RestTimer()
        r.start(seconds: 890, now: t0)
        r.adjust(by: 15, now: t0)
        r.adjust(by: 15, now: t0)
        #expect(r.remaining(at: t0) == RestTimer.maxRest)
    }

    @Test func skipAndRestartFromFinished() {
        var r = RestTimer()
        r.start(seconds: 60, now: t0)
        r.skip()
        #expect(r.phase == .idle)
        let adjusted = r.adjust(by: 15, now: t0) // nothing to adjust
        #expect(!adjusted)
        r.start(seconds: 30, now: t0)
        r.tick(now: t0.addingTimeInterval(31))
        r.start(seconds: 30, now: t0.addingTimeInterval(40))
        #expect(r.isRunning)
    }

    @Test func zeroRestStaysIdle() {
        var r = RestTimer()
        r.start(seconds: 0, now: t0)
        #expect(r.phase == .idle)
    }

    @Test func restoresARunningTimerOnly() {
        let running = RestTimer(endsAt: t0.addingTimeInterval(40), total: 90, now: t0)
        #expect(running.remaining(at: t0) == 40)
        let expired = RestTimer(endsAt: t0.addingTimeInterval(-5), total: 90, now: t0)
        #expect(expired.phase == .idle)
        #expect(RestTimer(endsAt: nil, total: 0, now: t0).phase == .idle)
    }
}

@Suite("Plan builder validation")
struct PlanValidationTests {
    private func plan(_ edit: (inout Plan) -> Void = { _ in }) -> Plan {
        var p = MockTrain.upperLower
        p.isBuiltin = false
        edit(&p)
        return p
    }

    @Test func builtInTemplatesAreValid() {
        for p in MockTrain.plans {
            #expect(PlanValidation.issues(in: p).isEmpty, "\(p.name)")
        }
    }

    @Test func nameDaysAndWeeks() {
        let issues = PlanValidation.issues(in: plan {
            $0.name = "  "
            $0.daysPerWeek = 8
            $0.weeks = 0
        })
        #expect(issues.contains(.missingName))
        #expect(issues.contains(.daysPerWeek))
        #expect(issues.contains(.weeks))
        #expect(PlanValidation.issues(in: plan { $0.weeks = nil }).isEmpty) // repeating
    }

    @Test func emptyPlanAndEmptyDay() {
        #expect(PlanValidation.issues(in: plan { $0.days = [] }).contains(.noDays))
        let p = plan { $0.days[1].exercises = [] }
        #expect(PlanValidation.issues(in: p).contains(.emptyDay(dayID: p.days[1].id)))
    }

    @Test func setsRepsRest() {
        let p = plan {
            $0.days[0].exercises[0].sets = 0
            $0.days[0].exercises[1].repsMin = 12
            $0.days[0].exercises[1].repsMax = 8
            $0.days[0].exercises[2].restSec = 1200
        }
        let ids = p.days[0].exercises.map(\.id)
        let issues = PlanValidation.issues(in: p)
        #expect(issues.contains(.sets(exerciseID: ids[0])))
        #expect(issues.contains(.reps(exerciseID: ids[1])))
        #expect(issues.contains(.rest(exerciseID: ids[2])))
    }

    @Test func targetsPerKind() {
        #expect(PlanValidation.targetIsValid(.pct1rm, 80))
        #expect(!PlanValidation.targetIsValid(.pct1rm, 150))
        #expect(!PlanValidation.targetIsValid(.pct1rm, nil))
        #expect(PlanValidation.targetIsValid(.rpe, 8.5))
        #expect(!PlanValidation.targetIsValid(.rpe, 11))
        #expect(PlanValidation.targetIsValid(.kg, 100))
        #expect(!PlanValidation.targetIsValid(.kg, 0))
        #expect(!PlanValidation.targetIsValid(.kg, 600))
        #expect(PlanValidation.targetIsValid(.bodyweight, nil))
        #expect(PlanValidation.targetIsValid(.bodyweight, 10)) // added load
    }

    @Test func supersetNeedsTwo() {
        let p = plan { $0.days[0].exercises[4].supersetGroup = nil } // pulldown alone in group 1
        #expect(PlanValidation.issues(in: p) == [.lonelySuperset(dayID: p.days[0].id, group: 1)])
    }
}
