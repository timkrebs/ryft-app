import Foundation
import Testing
@testable import Ryft

@Suite("Alpha Progression parser")
struct AlphaProgressionParserTests {
    private typealias PlanRef = ImportedSession.PlanRef

    // MARK: Plans

    @Test func plansFile() throws {
        let bundle = try ImportFixture.parse("ap-plans")
        #expect(bundle.format == .alphaProgression)
        #expect(bundle.lineCount == 10)
        #expect(bundle.warnings.isEmpty)
        #expect(bundle.sessions.isEmpty)
        #expect(bundle.plans.count == 1)
        let plan = try #require(bundle.plans.first)
        #expect(plan.name == "Strength Base")
        #expect(plan.weeks == 6)
        #expect(plan.startDate?.key == "2026-02-02")
        #expect(plan.source == SourceLine(file: 0, line: 1))
        #expect(plan.days.map(\.number) == [1, 2])
        #expect(plan.days.map(\.name) == ["Push", "Pull"])
        let push = try #require(plan.days.first)
        #expect(push.exercises == [
            ImportedPlanExercise(order: 1, name: "Overhead Press", equipment: "Barbell", sets: 4, targetReps: 6...6),
            ImportedPlanExercise(order: 2, name: "Push-Ups", equipment: "Bodyweight", sets: 3, targetReps: 8...12),
            ImportedPlanExercise(order: 3, name: "Cable Fly", equipment: "Cable", sets: 3, targetReps: 12...15),
        ])
        let pull = try #require(plan.days.last)
        #expect(pull.exercises.map(\.name) == ["Deadlift", "Pull-Ups", "Seated Cable Row", "Walking Lunges"])
        #expect(pull.exercises.map(\.order) == [1, 2, 3, 4])
        #expect(pull.exercises.last?.sets == 1) // "1 set"
    }

    @Test func planHeaderWithoutDateOrWithAnUnreadableOne() throws {
        let bundle = try ImportFixture.parse(text: """
        "Hypertrophy · Block · 8 weeks"
        "Day 1 · Full Body"
        "1. Front Squat · Barbell";"3 sets"
        "Plan B · 5 weeks";someday
        "Day 1"
        "1. Plank · Bodyweight";"3 sets";"AMRAP"
        """)
        #expect(bundle.plans.map(\.name) == ["Hypertrophy · Block", "Plan B"])
        #expect(bundle.plans.map(\.weeks) == [8, 5])
        #expect(bundle.plans.map(\.startDate) == [nil, nil])
        #expect(bundle.plans.first?.days.first?.exercises.first?.targetReps == nil) // no reps column: no warning
        #expect(bundle.plans.last?.days.first?.name == "")
        #expect(bundle.plans.last?.days.first?.exercises.first?.targetReps == nil)
        #expect(bundle.warningList == ["4 unreadableDate", "6 unreadableNumber"])
    }

    @Test func planLinesOutOfPlaceAreWarnedNotGuessed() throws {
        let bundle = try ImportFixture.parse(text: """
        "Day 1 · Push"
        "Base · 5 weeks";2026-01-05
        "1. Deadlift · Barbell";"3 sets";"5 reps"
        "Day 1 · Pull"
        "1. Deadlift · Barbell";"9999 sets";"5 reps"
        "2. Deadlift · Barbell";"3 sets";"5000 reps"
        """)
        #expect(bundle.warningList == ["1 outsideBlock", "3 outsideBlock", "5 implausibleValue", "6 implausibleValue"])
        let day = try #require(bundle.plans.first?.days.first)
        #expect(day.exercises.map(\.order) == [2])
        #expect(day.exercises.first?.targetReps == nil)
    }

    // MARK: Workouts

    @Test func workoutsFile() throws {
        let bundle = try ImportFixture.parse("ap-workouts")
        #expect(bundle.warnings.isEmpty)
        #expect(bundle.lineCount == 85)
        #expect(bundle.plans.isEmpty)
        #expect(bundle.sessions.map(\.title) == ["Push", "Pull", "Legs", "Pull", "Push", "Shoulders"])
        #expect(bundle.sessions.map(\.start.key) == ["2026-03-14T17:45", "2026-03-10T07:05", "2026-03-01T12:10",
                                                     "2026-02-05T00:05", "2026-02-03T06:30", "2026-02-01T21:15"])
        #expect(bundle.sessions.map(\.durationMinutes) == [42, 72, 53, 81, 48, 35])
        #expect(bundle.sessions.map(\.plan) == [nil, PlanRef(planName: "Strength Base", dayNumber: 2, weekNumber: 4), nil,
                                                PlanRef(planName: "Strength Base", dayNumber: 2, weekNumber: 1),
                                                PlanRef(planName: "Strength Base", dayNumber: 1, weekNumber: 1), nil])
        #expect(bundle.sessions.map(\.source.line) == [1, 17, 34, 45, 65, 81])
        #expect(bundle.sessions.map(\.exercises.count) == [3, 3, 2, 4, 3, 1])
        #expect(bundle.setCount == 42)
        #expect(bundle.skippedSetCount == 4)
    }

    @Test func setsKeepTheirRowsUnitsAndLoads() throws {
        let session = try #require(try ImportFixture.parse("ap-workouts").sessions.first)
        #expect(session.exercise(0) == ImportedSessionExercise(
            order: 1, name: "Overhead Press", equipment: "Barbell", targetReps: 6...6, unit: .kg,
            sets: [.kg(0, 40, 8), .kg(1, 50, 6), .kg(2, 52.5, 6)]))
        // `+N` on a bodyweight exercise.
        #expect(session.exercise(1)?.sets == [ImportedSet(ordinal: 0, load: .plus(kg: 10), reps: 12),
                                              ImportedSet(ordinal: 1, load: .plus(kg: 10), reps: 10)])
        // Every set `-`: kept as rows, skipped, never zero.
        let fly = try #require(session.exercise(2))
        #expect(fly.sets == [ImportedSet(ordinal: 0, load: nil, reps: nil), ImportedSet(ordinal: 1, load: nil, reps: nil),
                             ImportedSet(ordinal: 2, load: nil, reps: nil)])
        let allSkipped = fly.sets.allSatisfy(\.isSkipped)
        #expect(allSkipped)
    }

    @Test func aSetWithoutLoadButWithRepsWasDone() throws {
        let bundle = try ImportFixture.parse("ap-workouts")
        let pushUps = try #require(bundle.sessions.dropFirst(4).first?.exercise(1))
        #expect(pushUps.targetReps == 8...12)
        #expect(pushUps.sets == [ImportedSet(ordinal: 0, load: nil, reps: 12), ImportedSet(ordinal: 1, load: nil, reps: 10)])
        let anySkipped = pushUps.sets.contains(where: \.isSkipped)
        #expect(!anySkipped)
        #expect(ImportedSet(ordinal: 0, load: .weight(kg: 60), reps: 0).isSkipped)
    }

    @Test func exercisesMayDifferBetweenWeeks() throws {
        let bundle = try ImportFixture.parse("ap-workouts")
        let week4 = try #require(bundle.sessions.dropFirst(1).first)
        let week1 = try #require(bundle.sessions.dropFirst(3).first)
        #expect(week4.plan?.weekNumber == 4)
        #expect(week1.plan?.weekNumber == 1)
        #expect(week1.exercises.map(\.name) == ["Deadlift", "Pull-Ups", "Seated Cable Row", "Walking Lunges"])
        #expect(week4.exercises.map(\.name) == ["Deadlift", "Pull-Ups", "Seated Cable Row"])
        // A `-` row keeps its place in the table.
        #expect(week4.exercise(2)?.sets.map(\.ordinal) == [0, 1, 2])
        #expect(week4.exercise(2)?.sets.last?.isSkipped == true)
    }

    @Test func germanExport() throws {
        let bundle = try ImportFixture.parse("ap-workouts-de")
        #expect(bundle.warnings.isEmpty)
        #expect(bundle.lineCount == 28) // LF, no BOM, no line end after the last line
        #expect(bundle.sessions.map(\.title) == ["Oberkörper", "Unterkörper", "Arme"])
        #expect(bundle.sessions.map(\.plan) == [nil, PlanRef(planName: "Grundplan", dayNumber: 2, weekNumber: 3), nil])
        #expect(bundle.sessions.map(\.start.key) == ["2026-03-14T17:45", "2026-03-10T07:05", "2026-03-01T18:30"])
        #expect(bundle.sessions.map(\.durationMinutes) == [42, 65, 70])
        #expect(bundle.sessions.first?.exercise(0)?.sets == [.kg(0, 40, 8), .kg(1, 52.5, 6), .kg(2, 52.5, 6)])
        #expect(bundle.sessions.dropFirst().first?.exercise(1)?.sets.first?.load == .plus(kg: 7.5))
        #expect(bundle.sessions.dropFirst().first?.exercise(1)?.targetReps == 6...8)
        let plan = try #require(bundle.plans.first)
        #expect(plan.name == "Grundplan")
        #expect(plan.weeks == 6)
        #expect(plan.startDate?.key == "2026-02-02")
        #expect(plan.days.map(\.name) == ["Oberkörper", "Unterkörper"])
        #expect(plan.days.last?.exercises.map(\.sets) == [3, 1])
        #expect(plan.days.last?.exercises.last?.targetReps == 6...8) // "Wiederholungen"
    }

    @Test func poundsBecomeKilograms() throws {
        let bundle = try ImportFixture.parse("ap-workouts-lbs")
        let session = try #require(bundle.sessions.first)
        #expect(session.exercise(0)?.unit == .lb)
        #expect(session.exercise(0)?.sets == [.kg(0, 61.23, 5), .kg(1, 84.14, 5)])
        #expect(session.exercise(1)?.sets.first?.load == .plus(kg: 11.34))
        // No header after a pounds table: the file's last unit, said once.
        #expect(session.exercise(2)?.unit == nil)
        #expect(session.exercise(2)?.sets.first?.load == .plus(kg: 4.54))
        #expect(bundle.warnings == [ImportWarning(at: SourceLine(file: 0, line: 10), kind: .missingTableHeader(assumed: .lb))])
    }

    @Test func edgeCases() throws {
        let bundle = try ImportFixture.parse("ap-workouts-edge")
        #expect(bundle.lineCount == 39)
        #expect(bundle.warningList == [
            "1 unrecognisedLine", "2 outsideBlock", "3 outsideBlock", "6 missingTableHeader.kg", "13 unsupportedColumns",
            "17 unsupportedColumns", "21 unreadableNumber", "22 implausibleValue", "23 unreadableNumber",
            "25 implausibleValue", "26 unrecognisedLine", "27 meridiemConflict", "27 unreadableDuration",
            "31 outsideBlock", "32 unreadableDate", "36 implausibleValue",
        ])
        // The block with the impossible date is skipped whole; blocks need no blank lines between them.
        #expect(bundle.sessions.map(\.title) == ["Upper", "Lower", "Evening", "Late"])
        #expect(bundle.sessions.map(\.start.key) == ["2026-03-29T02:30", "2026-10-25T02:30", "2026-04-02T16:41",
                                                     "2026-04-03T23:59"])
        #expect(bundle.sessions.map(\.durationMinutes) == [30, 45, nil, nil])
        let upper = try #require(bundle.sessions.first)
        #expect(upper.exercises == [
            // A quoted `;` stays in the name; no table header: kg assumed, the unit stays nil.
            ImportedSessionExercise(order: 1, name: "Floor Press; Close Grip", equipment: "Barbell", targetReps: 8...8,
                                    unit: nil, sets: [.kg(0, 60, 8), .kg(1, 62.5, 8)]),
            ImportedSessionExercise(order: 2, name: "Chin-Ups", equipment: "Bodyweight", targetReps: 8...8, unit: .kg,
                                    sets: [ImportedSet(ordinal: 0, load: .minus(kg: 20), reps: 8),
                                           ImportedSet(ordinal: 1, load: .minus(kg: 15), reps: 6)]),
            // Unsupported columns: the exercise stays, its rows don't.
            ImportedSessionExercise(order: 3, name: "Plank", equipment: "Bodyweight", targetReps: nil, unit: nil, sets: []),
        ])
        let lower = try #require(bundle.sessions.dropFirst().first)
        #expect(lower.exercise(0)?.sets == [])
        // Dropped rows keep their ordinals out of the way of the next ones.
        #expect(lower.exercise(1)?.sets == [.kg(3, 40, 12)])
        // An unclosed quote takes the rest of its line.
        #expect(bundle.sessions.dropFirst(2).first?.exercise(0)?.name == "Face Pull")
        // Lone CR and CRLF line ends.
        #expect(bundle.sessions.last?.exercise(0)?.sets == [.kg(0, 100, 15)])
    }

    @Test func sessionHeaderShapes() throws {
        let bundle = try ImportFixture.parse(text: """
        "A · B · Day 3 · Week 2 · My · Plan";"2026-01-05 10:00";"30 min"
        "Name · Day 2 · Plan X";"2026-01-06 10:00";"30 min"
        "Morning";"2026-01-07 10:00"
        "Day 1 · Week 1 · Plan";"2026-01-08 10:00";"30 min"
        "Free · Standalone workout · extra";"2026-01-09 10:00";"30 min"
        """)
        #expect(bundle.warnings.isEmpty)
        #expect(bundle.sessions.map(\.title) == ["A · B", "Name", "Morning", "Day 1 · Week 1 · Plan", "Free · Standalone workout · extra"])
        #expect(bundle.sessions.map(\.plan) == [PlanRef(planName: "My · Plan", dayNumber: 3, weekNumber: 2),
                                                PlanRef(planName: "Plan X", dayNumber: 2, weekNumber: nil), nil, nil, nil])
        #expect(bundle.sessions.map(\.durationMinutes) == [30, 30, nil, 30, 30])
    }

    @Test func sessionLinesOutOfPlace() throws {
        let bundle = try ImportFixture.parse(text: """
        "1. Floor Press · Barbell · 5 reps"
        "Plan · 5 weeks";2026-01-05
        1;60;5
        "1. Floor Press · Barbell"
        "Upper · Standalone workout";"2026-01-06 10:00";"30 min"
        1;60;5
        "1. Plank"
        1;60
        """)
        #expect(bundle.warningList == ["1 outsideBlock", "3 outsideBlock", "4 outsideBlock", "6 outsideBlock",
                                       "8 unrecognisedLine"])
        let plank = try #require(bundle.sessions.first?.exercise(0))
        #expect(plank.name == "Plank")
        #expect(plank.equipment == nil)
        #expect(plank.sets.isEmpty)
    }

    @Test func theFirstFullPlanRunWins() throws {
        let bundle = try ImportFixture.parse(text: """
        "Legs · Day 2 · Day 1 · Week 3 · Base block";"2026-01-05 10:00";"30 min"
        "A · Day 1 · Week 2 · Day 3 · Week 4 · P";"2026-01-06 10:00";"30 min"
        "Arms · Day 3 · Standalone workout";"2026-01-07 10:00";"30 min"
        "B · Day 1 · Week 2";"2026-01-08 10:00";"30 min"
        "C · Day 4 · Week 1 · Standalone workout";"2026-01-09 10:00";"30 min"
        """)
        #expect(bundle.warnings.isEmpty)
        // A full `Day · Week · plan` run beats an earlier day without a week.
        #expect(bundle.sessions.first?.plan == PlanRef(planName: "Base block", dayNumber: 1, weekNumber: 3))
        #expect(bundle.sessions.first?.title == "Legs · Day 2")
        // The first full run, not the last.
        #expect(bundle.sessions.dropFirst().first?.plan == PlanRef(planName: "Day 3 · Week 4 · P", dayNumber: 1, weekNumber: 2))
        // A standalone workout stays standalone, whatever days it names.
        #expect(bundle.sessions.map(\.plan) == [PlanRef(planName: "Base block", dayNumber: 1, weekNumber: 3),
                                                PlanRef(planName: "Day 3 · Week 4 · P", dayNumber: 1, weekNumber: 2),
                                                nil, nil, nil])
        #expect(bundle.sessions.map(\.title) == ["Legs · Day 2", "A", "Arms · Day 3", "B · Day 1 · Week 2", "C · Day 4 · Week 1"])
    }

    @Test func aWorkoutTitledWithANumberIsNotASetRow() throws {
        let bundle = try ImportFixture.parse(text: """
        "Push · Standalone workout";"2026-02-14 5:10 pm";"42 min"
        "1. Floor Press · Barbell · 8 reps"
        #;KG;REPS
        1;60;8
        "5";"2026-02-13 5:10 pm";"42 min"
        "1. Hammer Curl · Dumbbells · 10 reps"
        #;KG;REPS
        1;10;10
        6;2026-02-12 7:00;30 min
        """)
        #expect(bundle.warnings.isEmpty)
        #expect(bundle.sessions.map(\.title) == ["Push", "5", "6"])
        #expect(bundle.sessions.map(\.exercises.count) == [1, 1, 0])
    }

    @Test func wideRowsKeepTheirOrdinalAndAreNotSets() throws {
        let bundle = try ImportFixture.parse(text: """
        "A · Standalone workout";"2026-01-05 10:00";"30 min"
        "1. Floor Press · Barbell · 8 reps"
        #;KG;REPS
        1;60;8;9
        2;62,5;8
        3;65
        4;65;6
        """)
        // A row with another number of columns is no set; its place still counts, because ordinals feed set ids.
        #expect(bundle.sessions.first?.exercise(0)?.sets == [.kg(1, 62.5, 8), .kg(3, 65, 6)])
        #expect(bundle.warningList == ["4 unrecognisedLine", "6 unrecognisedLine"])
    }

    @Test func aDateWithoutATimeButWithADurationIsAWorkout() throws {
        let bundle = try ImportFixture.parse(text: """
        "Push";"2026-01-05";"30 min"
        "1. Floor Press · Barbell · 8 reps"
        #;KG;REPS
        1;60;8
        "Base · 6 weeks";2026-01-05
        """)
        // Its time can't be read, so the block is skipped; it never becomes a plan.
        #expect(bundle.sessions.isEmpty)
        #expect(bundle.plans.map(\.name) == ["Base"])
        #expect(bundle.warningList == ["1 unreadableDate"])
    }

    @Test func noBreakSpacesSeparateLikeSpaces() throws {
        let text = "\"H\u{00A0}·\u{00A0}Standalone workout\";\"2026-02-14\u{00A0}5:10\u{202F}pm\";\"42\u{00A0}min\"\n"
            + "\"1.\u{00A0}Floor Press · Barbell · 8\u{00A0}reps\"\n#;KG;REPS\n1;60;8"
        let bundle = try ImportFixture.parse(text: text)
        #expect(bundle.warnings.isEmpty)
        let session = try #require(bundle.sessions.first)
        #expect(session.title == "H")
        #expect(session.plan == nil)
        #expect(session.start.key == "2026-02-14T17:10")
        #expect(session.durationMinutes == 42)
        #expect(session.exercise(0)?.name == "Floor Press")
        #expect(session.exercise(0)?.targetReps == 8...8)
    }

    @Test func controlAndFormatCharactersNeverReachNames() throws {
        let text = "\"Up\u{202E}per\u{200B} · Standalone workout\";\"2026-01-05 10:00\";\"30 min\"\n"
            + "\"1. Floor\u{001F} Press · Bar\u{2066}bell\u{2069} · 8 reps\"\n#;KG;REPS\n1;60;8\n"
            + "\"Base\u{00AD} · 6 weeks\";2026-01-05\n\"Day 1 · Up\u{0007}per\"\n\"1. Front\tSquat · Barbell\";\"3 sets\";\"5 reps\""
        let bundle = try ImportFixture.parse(text: text)
        let session = try #require(bundle.sessions.first)
        #expect(session.title == "Upper")
        #expect(session.exercise(0)?.name == "Floor Press")
        #expect(session.exercise(0)?.equipment == "Barbell")
        #expect(bundle.plans.first?.name == "Base")
        #expect(bundle.plans.first?.days.first?.name == "Upper")
        #expect(bundle.plans.first?.days.first?.exercises.first?.name == "Front\tSquat") // a tab stays
        let names = bundle.sessions.flatMap { [$0.title] + $0.exercises.map(\.name) }
        let hasControl = names.contains { $0.unicodeScalars.contains { $0.properties.generalCategory == .format } }
        #expect(!hasControl)
    }

    @Test func aDayNumberTwiceInOnePlanIsKeptAndWarned() throws {
        let bundle = try ImportFixture.parse(text: """
        "Base · 6 weeks";2026-01-05
        "Day 1 · Upper"
        "1. Overhead Press · Barbell";"3 sets";"8 reps"
        "Day 1 · Lower"
        "1. Front Squat · Barbell";"3 sets";"5 reps"
        "Day 2 · Pull"
        """)
        #expect(bundle.plans.first?.days.map(\.number) == [1, 1, 2])
        #expect(bundle.warningList == ["4 duplicateDay"])
    }

    @Test func aWindows1252ExportReadsLikeItsUTF8Twin() throws {
        let utf8 = try ImportFixture.data("ap-workouts-de")
        let text = try #require(String(bytes: utf8, encoding: .utf8))
        let legacy = try #require(text.data(using: .windowsCP1252))
        #expect(String(bytes: legacy, encoding: .utf8) == nil) // the umlauts are single bytes now
        let expected = try AlphaProgressionFormat().parse(utf8, limits: .standard)
        let parsed = try AlphaProgressionFormat().parse(legacy, limits: .standard)
        #expect(parsed.plans == expected.plans)
        #expect(parsed.sessions == expected.sessions)
        #expect(parsed.warnings == [ImportWarning(at: SourceLine(file: 0, line: 1), kind: .legacyEncoding)])
        #expect(parsed.sessions.first?.title == "Oberkörper")
        // With a UTF-8 BOM the file says what it is: bad bytes then decode lossily, line by line.
        let marked = try AlphaProgressionFormat().parse(Data([0xEF, 0xBB, 0xBF]) + legacy, limits: .standard)
        let kinds = Set(marked.warnings.map(\.kind))
        #expect(kinds.contains(.invalidText))
        #expect(!kinds.contains(.legacyEncoding))
    }

    // MARK: Invariance

    @Test func newerExportAddsOneSession() throws {
        let older = try ImportFixture.parse("ap-workouts")
        let newer = try ImportFixture.parse("ap-workouts-plus1")
        #expect(newer.sessions.count == older.sessions.count + 1)
        #expect(Array(newer.sessionsIgnoringLines.dropFirst()) == older.sessionsIgnoringLines)
        #expect(newer.sessions.first?.start.key == "2026-03-18T18:00")
    }

    @Test func lineEndsAndBOMDontChangeTheResult() throws {
        let original = try ImportFixture.data("ap-workouts")
        let bundle = try AlphaProgressionFormat().parse(original, limits: .standard)
        let text = try #require(String(bytes: original.dropFirst(3), encoding: .utf8))
        #expect(original.starts(with: [0xEF, 0xBB, 0xBF]))
        for variant in [text, text.replacingOccurrences(of: "\r\n", with: "\n"),
                        text.replacingOccurrences(of: "\r\n", with: "\r")] {
            let parsed = try AlphaProgressionFormat().parse(Data(variant.utf8), limits: .standard)
            #expect(parsed == bundle)
        }
    }

    @Test func blankLinesDontMatter() throws {
        let original = try ImportFixture.data("ap-workouts")
        let text = try #require(String(bytes: original, encoding: .utf8))
        let packed = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }.joined(separator: "\r\n")
        let parsed = try AlphaProgressionFormat().parse(Data(packed.utf8), limits: .standard)
        let spaced = try AlphaProgressionFormat().parse(original, limits: .standard)
        #expect(parsed.sessionsIgnoringLines == spaced.sessionsIgnoringLines)
        #expect(parsed.lineCount == 80)
    }

    @Test func sameBytesSameBundle() throws {
        for name in ImportFixture.alphaProgression {
            let first = try ImportFixture.parse(name)
            let second = try ImportFixture.parse(name)
            #expect(first == second, "\(name)")
        }
    }

    @Test func emptyAndBlankFilesGiveEmptyBundles() throws {
        for text in ["", "\u{FEFF}", "\r\n\r\n", "  \n\t\n"] {
            let bundle = try ImportFixture.parse(text: text)
            #expect(bundle.isEmpty)
            #expect(bundle.warnings.isEmpty)
        }
    }
}
