import Foundation
import Testing
@testable import Ryft

@Suite("Import limits")
struct ImportLimitsTests {
    private func limits(_ change: (inout ImportLimits) -> Void) -> ImportLimits {
        var limits = ImportLimits.standard
        change(&limits)
        return limits
    }

    @Test func standardLimits() {
        let standard = ImportLimits.standard
        #expect(standard.maxFileBytes == 8 * 1_024 * 1_024)
        #expect(standard.maxLineBytes == 4_096)
        #expect(standard.maxSessions == 10_000)
        #expect(standard.maxPlans == 50)
        #expect(standard.maxExercisesPerBlock == 200)
        #expect(standard.maxSetsPerExercise == 200)
        #expect(standard.maxWarnings == 200)
    }

    @Test func filesOverEightMebibytesAreRefusedBeforeAnyLineIsRead() {
        let over = Data(count: ImportLimits.standard.maxFileBytes + 1) // NUL bytes: the size check comes first
        #expect(throws: ImportError.tooLarge(bytes: 8_388_609)) {
            try AlphaProgressionFormat().parse(over, limits: .standard)
        }
    }

    @Test func theCapIsInclusive() throws {
        let small = limits { $0.maxFileBytes = 100 }
        let exactly = Data(String(repeating: "#;KG;REPS\n", count: 10).utf8)
        #expect(exactly.count == 100)
        let read = try AlphaProgressionFormat().parse(exactly, limits: small)
        #expect(read.lineCount == 10)
        #expect(throws: ImportError.tooLarge(bytes: 101)) {
            try AlphaProgressionFormat().parse(exactly + Data([0x0A]), limits: small)
        }
    }

    @Test func longLinesAreSkippedAndTheRestIsRead() throws {
        let fits = "1;60;10" + String(repeating: " ", count: 4_096 - 7)
        let tooLong = "2;60;10" + String(repeating: " ", count: 4_097 - 7)
        let huge = String(repeating: "x", count: 1 << 20)
        let text = """
        "Upper · Standalone workout";"2026-01-05 9:00 am";"30 min"
        "1. Floor Press · Barbell · 10 reps"
        #;KG;REPS
        \(fits)
        \(tooLong)
        \(huge)
        3;60;8
        """
        let bundle = try ImportFixture.parse(text: text)
        #expect(bundle.warningList == ["5 lineTooLong", "6 lineTooLong"])
        // A skipped line isn't known to be a set row, so it takes no ordinal.
        #expect(bundle.sessions.first?.exercise(0)?.sets == [.kg(0, 60, 10), .kg(1, 60, 8)])
    }

    @Test func warningsAreCappedAndCounted() throws {
        let text = (1...12).map { "junk \($0)" }.joined(separator: "\n")
        let bundle = try ImportFixture.parse(text: text, limits: limits { $0.maxWarnings = 5 })
        #expect(bundle.warnings.map(\.at.line) == [1, 2, 3, 4, 5])
        #expect(bundle.suppressedWarnings == 7)
        let none = try ImportFixture.parse(text: text, limits: limits { $0.maxWarnings = 0 })
        #expect(none.warnings.isEmpty)
        #expect(none.suppressedWarnings == 12)
    }

    @Test func sessionsOverTheCapAreSkippedWithOneWarning() throws {
        let bundle = try ImportFixture.parse("ap-workouts", limits: limits { $0.maxSessions = 2 })
        #expect(bundle.sessions.map(\.source.line) == [1, 17])
        #expect(bundle.warningList == ["34 limitReached"])
    }

    @Test func plansOverTheCapAreSkippedWithOneWarning() throws {
        let text = """
        "A · 5 weeks";2026-01-05
        "Day 1 · X"
        "1. Front Squat · Barbell";"3 sets";"5 reps"
        "B · 5 weeks";2026-02-05
        "Day 1 · Y"
        "1. Face Pull · Cable";"3 sets";"5 reps"
        "C · 5 weeks";2026-03-05
        """
        let bundle = try ImportFixture.parse(text: text, limits: limits { $0.maxPlans = 1 })
        #expect(bundle.plans.map(\.name) == ["A"])
        #expect(bundle.plans.first?.days.first?.exercises.count == 1)
        #expect(bundle.warningList == ["4 limitReached"])
    }

    @Test func exercisesOverTheBlockCapAreDroppedWithTheirSets() throws {
        let bundle = try ImportFixture.parse("ap-workouts", limits: limits { $0.maxExercisesPerBlock = 2 })
        #expect(bundle.sessions.map(\.exercises.count) == [2, 2, 2, 2, 2, 1])
        #expect(bundle.warningList == ["11 limitReached", "28 limitReached", "56 limitReached", "76 limitReached"])
        #expect(bundle.setCount == 30)
    }

    @Test func daysAndPlanExercisesOverTheBlockCap() throws {
        let two = try ImportFixture.parse("ap-plans", limits: limits { $0.maxExercisesPerBlock = 2 })
        #expect(two.plans.first?.days.map(\.exercises.count) == [2, 2])
        #expect(two.warningList == ["5 limitReached", "9 limitReached"])
        // One day per plan: the second day and its exercises go, with their own warning.
        let one = try ImportFixture.parse("ap-plans", limits: limits { $0.maxExercisesPerBlock = 1 })
        #expect(one.plans.first?.days.map(\.exercises.count) == [1])
        #expect(one.warningList == ["4 limitReached", "6 limitReached"])
    }

    @Test func setsOverTheCapAreDropped() throws {
        let bundle = try ImportFixture.parse("ap-workouts", limits: limits { $0.maxSetsPerExercise = 2 })
        let ordinals = bundle.sessions.flatMap { $0.exercises.map { $0.sets.map(\.ordinal) } }
        let firstTwoRows = ordinals.allSatisfy { $0 == [0, 1] || $0 == [0] }
        #expect(firstTwoRows)
        #expect(bundle.warnings.map(\.at.line) == [6, 15, 22, 27, 32, 39, 50, 55, 60, 70])
        #expect(Set(bundle.warnings.map(\.kind)) == [.limitReached])
    }
}
