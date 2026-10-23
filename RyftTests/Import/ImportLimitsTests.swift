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
        #expect(standard.maxFiles == 6)
        #expect(standard.maxTotalBytes == 6 * 8 * 1_024 * 1_024)
        #expect(standard.maxLineBytes == 4_096)
        #expect(standard.maxSessions == 10_000)
        #expect(standard.maxPlans == 50)
        // The platform's session limits (API.md → Sessions): nothing kept is refused there.
        #expect(standard.maxExercisesPerBlock == 50)
        #expect(standard.maxSetsPerExercise == 50)
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
        #expect(bundle.warningList == ["11 overPlatformLimit", "28 overPlatformLimit", "56 overPlatformLimit",
                                       "76 overPlatformLimit"])
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

    @Test func aSessionKeepsThePlatformLimits() throws {
        var lines = ["\"Big · Standalone workout\";\"2026-01-05 10:00\";\"90 min\""]
        for exercise in 1...51 {
            lines.append("\"\(exercise). Exercise \(exercise) · Cable · 10 reps\"")
            lines.append("#;KG;REPS")
            for set in 1...(exercise == 1 ? 51 : 1) { lines.append("\(set);20;10") }
        }
        let bundle = try ImportFixture.parse(text: lines.joined(separator: "\n"))
        let session = try #require(bundle.sessions.first)
        #expect(session.exercises.count == 50)
        #expect(session.exercise(0)?.sets.count == 50)
        #expect(bundle.warnings.map(\.kind) == [.overPlatformLimit, .overPlatformLimit])
    }

    @Test func setsOverTheCapAreDropped() throws {
        let bundle = try ImportFixture.parse("ap-workouts", limits: limits { $0.maxSetsPerExercise = 2 })
        let ordinals = bundle.sessions.flatMap { $0.exercises.map { $0.sets.map(\.ordinal) } }
        let firstTwoRows = ordinals.allSatisfy { $0 == [0, 1] || $0 == [0] }
        #expect(firstTwoRows)
        #expect(bundle.warnings.map(\.at.line) == [6, 15, 22, 27, 32, 39, 50, 55, 60, 70])
        #expect(Set(bundle.warnings.map(\.kind)) == [.overPlatformLimit])
    }

    // MARK: Work, counted

    /// Inputs built to make a parser work hard per byte: long names of digits, many ` · ` parts and day tokens,
    /// separators and quotes. Each is 64 KiB; the work stays linear (`ParseStats.visited`), with no clock involved.
    @Test(arguments: ImportLimitsTests.adversarial)
    func adversarialInputsStayLinear(_ input: Adversarial) throws {
        let data = input.data
        var stats = ParseStats()
        let bundle = try AlphaProgressionFormat().parse(data, limits: .standard, stats: &stats)
        #expect(stats.lines > 0)
        let skippedAsTooLong = bundle.warnings.contains { $0.kind == .lineTooLong }
        #expect(!skippedAsTooLong) // every line is read and classified
        #expect(stats.visited <= ImportLimitsTests.workBound(bytes: data.count, lines: stats.lines),
                "\(stats.visited) visited for \(data.count) bytes, \(stats.lines) lines")
    }

    /// The fuzz test's bound too: every byte and line visited a small, fixed number of times.
    static func workBound(bytes: Int, lines: Int) -> Int { 24 * bytes + 24 * lines + 64 }

    struct Adversarial: CustomTestStringConvertible, Sendable {
        let name: String
        let line: String

        var testDescription: String { name }

        var data: Data {
            let unit = Array((line + "\n").utf8)
            var bytes: [UInt8] = []
            while bytes.count + unit.count <= 64 << 10 { bytes += unit }
            return Data(bytes)
        }
    }

    static let adversarial: [Adversarial] = {
        let dot = " \u{00B7} "
        let days = Array(repeating: "Day 1", count: 400).joined(separator: dot)
        return [
            Adversarial(name: "a workout title of 400 day parts", line: "\"A\(dot)\(days)\";\"2026-01-05 10:00\";\"30 min\""),
            Adversarial(name: "day and week runs", line: "\"A\(dot)" + Array(repeating: "Day 1\(dot)Week 2", count: 200)
                .joined(separator: dot) + "\";\"2026-01-05 10:00\";\"30 min\""),
            Adversarial(name: "an exercise of 800 parts", line: "\"1. " + Array(repeating: "a", count: 800).joined(separator: dot) + "\""),
            Adversarial(name: "a name of 4 000 digits", line: "\"" + String(repeating: "1", count: 4_000) + "\""),
            Adversarial(name: "4 000 separators", line: String(repeating: ";", count: 4_000)),
            Adversarial(name: "4 000 quotes", line: String(repeating: "\"", count: 4_000)),
            Adversarial(name: "a duration of 2 000 words", line: "\"A\";\"2026-01-05 10:00\";\"" + String(repeating: "1 ", count: 1_990) + "\""),
            Adversarial(name: "short set rows", line: "1;60;10"),
        ]
    }()
}
