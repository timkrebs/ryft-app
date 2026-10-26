// Synthetic training-import data for previews, demo mode and tests (ui.md §12). Every name, weight and date here is
// invented: nothing comes from anyone's export (the repo is public). The files are written in the export format and
// read by the real parser, so previews show what the flow would.
import Foundation

/// Writes text in the Alpha Progression export format: quoted ` · ` headers, `#;KG;REPS` set tables, 12-hour times.
struct ImportCSVWriter {
    private(set) var lines: [String] = []

    mutating func plan(_ name: String, weeks: Int, start: LocalDate) {
        lines.append("\"\(name) · \(weeks) weeks\";\(start.key)")
    }

    mutating func day(_ number: Int, _ name: String) {
        lines.append("\"Day \(number) · \(name)\"")
    }

    mutating func planExercise(_ order: Int, _ name: String, _ equipment: String, sets: Int, reps: String) {
        lines.append("\"\(order). \(name) · \(equipment)\";\"\(sets) \(sets == 1 ? "set" : "sets")\";\"\(reps) reps\"")
    }

    /// A workout header: `plan` names the plan, its day and week; nil is a standalone workout.
    mutating func session(_ title: String, plan: (name: String, day: Int, week: Int)?, start: LocalDateTime, minutes: Int) {
        if !lines.isEmpty { lines.append("") }
        let header = plan.map { "\(title) · Day \($0.day) · Week \($0.week) · \($0.name)" } ?? "\(title) · Standalone workout"
        let hour12 = start.hour % 12 == 0 ? 12 : start.hour % 12
        let time = "\(hour12):\(ImportPad.digits(start.minute, 2)) \(start.hour < 12 ? "am" : "pm")"
        let duration = minutes < 60 ? "\(minutes) min" : "\(minutes / 60):\(ImportPad.digits(minutes % 60, 2)) hr"
        lines.append("\"\(header)\";\"\(start.date.key) \(time)\";\"\(duration)\"")
    }

    /// An exercise and its set table; each set is a load (`60`, `+20`, `-`) and reps (`8`, `-`).
    mutating func exercise(_ order: Int, _ name: String, _ equipment: String, reps: Int, sets: [(String, String)]) {
        lines.append("\"\(order). \(name) · \(equipment) · \(reps) reps\"")
        lines.append("#;KG;REPS")
        for (index, set) in sets.enumerated() {
            lines.append("\(index + 1);\(set.0);\(set.1)")
        }
    }

    /// With a BOM and CRLF, as the app's exports are.
    var data: Data { Data(("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n").utf8) }
}

enum ImportMockData {
    /// Previews show times in this zone, whatever the Mac's.
    static let zone = TimeZone(identifier: "Europe/Berlin") ?? .current
    /// 2026-04-28 10:00 in Berlin: "today" in the previews.
    static let now = Date(timeIntervalSince1970: 1_777_363_200)
    static let planName = "Upper/Lower"

    static func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: day) ?? .fallback
    }

    static func time(_ date: LocalDate, _ hour: Int, _ minute: Int) -> LocalDateTime? {
        LocalDateTime(date: date, hour: hour, minute: minute)
    }

    // MARK: Files

    /// 1 plan · 2 days · 12 exercises: exact, alias, likely and possible matches, and one the library doesn't have.
    static let plans: Data = {
        var w = ImportCSVWriter()
        w.plan(planName, weeks: 6, start: day(2026, 3, 2))
        w.day(1, "Upper")
        w.planExercise(1, "Bench Press", "Barbell", sets: 4, reps: "6-8")
        w.planExercise(2, "Bent Over Row", "Barbell", sets: 4, reps: "8")
        w.planExercise(3, "Overhead Press", "Barbell", sets: 3, reps: "8")
        w.planExercise(4, "Lat Pulldown", "Cable", sets: 3, reps: "10-12")
        w.planExercise(5, "Dips", "Bodyweight", sets: 3, reps: "8")
        w.planExercise(6, "Hammer Curl", "Dumbbell", sets: 3, reps: "12")
        w.day(2, "Lower")
        w.planExercise(1, "Squat", "Barbell", sets: 4, reps: "5")
        w.planExercise(2, "Romanian Deadlift", "Barbell", sets: 3, reps: "8")
        w.planExercise(3, "Leg Press Wide", "Machine", sets: 3, reps: "10")
        w.planExercise(4, "Seated Leg Curl", "Machine", sets: 3, reps: "12")
        w.planExercise(5, "Standing Calf Raise", "Machine", sets: 4, reps: "15")
        w.planExercise(6, "Nordic Curl", "Bodyweight", sets: 3, reps: "6")
        return w.data
    }()

    /// 10 workouts, 2 Mar to 27 Apr 2026, newest first: `+20` dips, skipped sets, one standalone workout.
    static let workouts: Data = {
        var w = ImportCSVWriter()
        let kg = ImportCSVWriter.number
        let dates: [(LocalDate, Int)] = [
            (day(2026, 4, 27), 1), (day(2026, 4, 20), 2), (day(2026, 4, 13), 1), (day(2026, 4, 6), 2),
            (day(2026, 3, 30), 1), (day(2026, 3, 23), 2), (day(2026, 3, 16), 1), (day(2026, 3, 9), 2),
            (day(2026, 3, 5), 0), (day(2026, 3, 2), 1),
        ]
        for (index, (date, planDay)) in dates.enumerated() {
            let week = 6 - index / 2
            let step = Double(dates.count - index) * 2.5
            guard let start = time(date, planDay == 2 ? 7 : 18, planDay == 2 ? 5 : 30) else { continue }
            switch planDay {
            case 1:
                w.session("Upper", plan: (planName, 1, max(1, week)), start: start, minutes: 62)
                w.exercise(1, "Bench Press", "Barbell", reps: 8,
                           sets: [(kg(55 + step), "8"), (kg(57.5 + step), "8"), (kg(57.5 + step), index == 0 ? "-" : "7")])
                w.exercise(2, "Lat Pulldown", "Cable", reps: 10, sets: [("50", "10"), ("52.5", "10"), ("52.5", "9")])
                w.exercise(3, "Dips", "Bodyweight", reps: 8, sets: [("+20", "8"), ("+20", "8"), ("+20", "6")])
            case 2:
                w.session("Lower", plan: (planName, 2, max(1, week)), start: start, minutes: 71)
                w.exercise(1, "Squat", "Barbell", reps: 5, sets: [(kg(75 + step), "5"), (kg(80 + step), "5"), ("-", "-")])
                w.exercise(2, "Leg Press Wide", "Machine", reps: 10, sets: [("120", "10"), ("120", "10")])
                w.exercise(3, "Nordic Curl", "Bodyweight", reps: 6, sets: [("-", "6"), ("-", "5")])
            default:
                w.session("Arms", plan: nil, start: start, minutes: 35)
                w.exercise(1, "Hammer Curl", "Dumbbell", reps: 12, sets: [("12", "12"), ("12", "11")])
            }
        }
        return w.data
    }()

    /// Not an export: lines another app might write.
    static let garbage = Data("Shopping list;eggs;milk\nNotes from Monday\n".utf8)

    static func bundle(_ data: Data, file: Int = 0) -> ImportBundle {
        let parsed = try? AlphaProgressionFormat().parse(data, limits: .standard)
        return (parsed ?? ImportBundle(format: .alphaProgression, plans: [], sessions: [], warnings: [], suppressedWarnings: 0,
                                       lineCount: 0)).inFile(file)
    }

    static func file(_ id: Int, _ name: String, _ data: Data, confidence: ImportConfidence = .strong) -> ImportPickedFile {
        ImportPickedFile(id: id, name: name, status: .read(bundle(data, file: id), confidence: confidence))
    }

    static var bothFiles: [ImportPickedFile] {
        [file(0, "Upper-Lower_Plans.csv", plans), file(1, "Upper-Lower_Workouts.csv", workouts)]
    }

    /// A few warnings of each sort, with line numbers and kinds only (no file text exists to show).
    static func withWarnings(_ files: [ImportPickedFile]) -> [ImportPickedFile] {
        files.map { file in
            guard case .read(var bundle, let confidence) = file.status else { return file }
            bundle.warnings += [
                ImportWarning(at: SourceLine(file: file.id, line: 41), kind: .unrecognisedLine),
                ImportWarning(at: SourceLine(file: file.id, line: 57), kind: .unreadableNumber),
                ImportWarning(at: SourceLine(file: file.id, line: 88), kind: .missingTableHeader(assumed: .kg)),
                ImportWarning(at: SourceLine(file: file.id, line: 90), kind: .durationAssumed),
            ]
            bundle.warnings = ImportWarning.sorted(bundle.warnings)
            var copy = file
            copy.status = .read(bundle, confidence: confidence)
            return copy
        }
    }

    // MARK: Flows

    /// A flow seeded to a step, on the preview library (MockTrain), "today" 28 Apr 2026 in Berlin.
    @MainActor
    static func flow(_ step: ImportFlowModel.Step = .pick, files: [ImportPickedFile]? = nil, enrolled: Bool = true,
                     library: TrainLibrary? = nil, uploader: TrainImportUploader? = nil,
                     configure: (ImportFlowModel) -> Void = { _ in }) -> ImportFlowModel {
        let store = TrainStore(inMemory: true)
        let library = library ?? TrainLibrary.preview(store: store, enrolled: enrolled)
        let deps = ImportFlowModel.Dependencies(
            library: library, mappings: ImportMappingStore(persistence: store) { "preview" },
            uploader: uploader ?? Self.uploader(nil), clock: TestClock(now: now), zone: zone, account: { "preview" }, isOnline: { true },
            readURLs: { _ in [] }, aliases: { ExerciseAliases.fallback }, scriptedFiles: nil, announce: { _ in })
        let flow = ImportFlowModel(deps: deps)
        let all = ImportFlowModel.Step.allCases
        flow.path = Array(all.filter { $0.rawValue > 1 && $0.rawValue <= step.rawValue })
        if step.rawValue >= ImportFlowModel.Step.detected.rawValue {
            flow.files = files ?? bothFiles
        } else if let files {
            flow.files = files
        }
        if step.rawValue >= ImportFlowModel.Step.choose.rawValue, let bundle = flow.detection.bundle {
            flow.selection = ImportSelection(bundle: bundle, today: flow.today, hasEnrollment: flow.hasEnrollment)
        }
        if step.rawValue >= ImportFlowModel.Step.map.rawValue, let chosen = flow.chosenBundle {
            flow.aliases = ExerciseAliases.bundled
            flow.mapping = mapping(for: chosen, library: library.exercises)
            flow.libraryState = .ready
        }
        configure(flow)
        return flow
    }

    /// The matcher on the preview library, synchronously (previews only; the flow matches off the main actor).
    static func mapping(for bundle: ImportBundle, library: [Exercise]) -> ImportMappingState {
        let aliases = ExerciseAliases.bundled
        let sources = aliases.normalizer.sources(in: bundle)
        let matcher = ExerciseMatcher(library: library, aliases: aliases, remembered: [:])
        return ImportMappingState(sources: sources, matches: matcher.match(sources.map(\.key)), library: library,
                                  remembered: [:], aliases: aliases)
    }

    /// An uploader showing `status`; `available` false: uploads aren't available yet (V5).
    @MainActor
    static func uploader(_ status: ImportJobStatus?, available: Bool = true) -> TrainImportUploader {
        TrainImportUploader.preview(status, env: .preview(flags: [.trainImport: available]))
    }

    // MARK: Step 5

    /// A preview build for step 5 and its components, made by hand from the preview files (so previews don't depend
    /// on the builder): one duplicate, one workout already imported, one on a clock change, a skipped exercise, and
    /// "last time" lines on the plan.
    static func build(alreadyImportedAll: Bool = false, duplicatesChecked: Bool = true, sendsPlan: Bool = true) -> ImportBuild {
        let sessions = bundle(workouts, file: 1).sessions
        let byName: [String: Exercise] = [
            "Bench Press": MockTrain.bench, "Lat Pulldown": MockTrain.pulldown, "Dips": MockTrain.dip,
            "Squat": MockTrain.squat, "Leg Press Wide": MockTrain.legPress, "Hammer Curl": MockTrain.curl,
        ]
        var previews: [ImportSessionPreview] = []
        for (index, imported) in sessions.enumerated() {
            let resolver = ImportTimeResolver(zone: zone)
            let start = resolver.resolve(imported.start).instant
            var exercises: [SessionExercise] = []
            var setCount = 0
            var skipped = 0
            var volume = 0.0
            for (position, exercise) in imported.exercises.enumerated() {
                guard let library = byName[exercise.name] else { continue }
                var sets: [SessionSet] = []
                for set in exercise.sets {
                    guard !set.isSkipped else {
                        skipped += 1
                        continue
                    }
                    let kg: Double? = if case let .weight(kg) = set.load { kg } else if case let .plus(kg) = set.load { kg } else { nil }
                    sets.append(SessionSet(setIndex: sets.count, reps: set.reps, weightKg: kg, completedAt: start, updatedAt: start))
                    volume += (kg ?? 0) * Double(set.reps ?? 0)
                }
                setCount += sets.count
                exercises.append(SessionExercise(exerciseId: library.id, position: position, sets: sets))
            }
            let verdict: ImportSessionPreview.Verdict = alreadyImportedAll ? .alreadyImported
                : index == 1 && duplicatesChecked ? .duplicate(of: MockTrain.uuid(5, 1))
                : index == 2 ? .alreadyImported : .new
            let session = TrainSession(id: MockTrain.uuid(30, index), title: imported.title, startedAt: start,
                                       endedAt: start.addingTimeInterval(3_600), status: .completed, exercises: exercises)
            previews.append(ImportSessionPreview(index: index, id: session.id, verdict: verdict, session: session,
                                                 startedAt: start, day: imported.start.date, exerciseCount: exercises.count,
                                                 setCount: setCount, skippedSetCount: skipped, volumeKg: volume,
                                                 clockChange: index == 5 ? .repeatedLocalTime : nil))
        }
        func pe(_ n: Int, _ e: Exercise, _ position: Int, _ sets: Int, _ lo: Int, _ hi: Int, kg: Double?) -> PlanExercise {
            let kind: TargetKind = e.loadType == .bodyweight ? .bodyweight : kg == nil ? .rpe : .kg
            return PlanExercise(id: MockTrain.uuid(31, n), exercise: e, position: position, sets: sets, repsMin: lo, repsMax: hi,
                                targetKind: kind, targetValue: kind == .bodyweight ? nil : kg ?? 8,
                                restSec: e.kind == .barbell ? 180 : 90)
        }
        let upper = PlanDay(id: MockTrain.uuid(32, 1), dayIndex: 0, name: "Upper", exercises: [
            pe(1, MockTrain.bench, 0, 4, 6, 8, kg: 60), pe(2, MockTrain.row, 1, 4, 8, 8, kg: nil),
            pe(3, MockTrain.ohp, 2, 3, 8, 8, kg: nil), pe(4, MockTrain.pulldown, 3, 3, 10, 12, kg: 52.5),
            pe(5, MockTrain.dip, 4, 3, 8, 8, kg: nil),
        ])
        let lower = PlanDay(id: MockTrain.uuid(32, 2), dayIndex: 1, name: "Lower", exercises: [
            pe(6, MockTrain.squat, 0, 4, 5, 5, kg: 87.5), pe(7, MockTrain.rdl, 1, 3, 8, 8, kg: nil),
            pe(8, MockTrain.legPress, 2, 3, 10, 10, kg: 120), pe(9, MockTrain.legCurl, 3, 3, 12, 12, kg: nil),
            pe(10, MockTrain.calfRaise, 4, 4, 15, 15, kg: nil),
        ])
        let plan = Plan(id: MockTrain.uuid(33, 1), name: planName, goal: .general, weeks: 6, daysPerWeek: 2,
                        description: "", progression: .linear, isBuiltin: false, days: [upper, lower])
        let last = day(2026, 4, 27)
        let lastTime: [UUID: ImportLastTime] = [
            MockTrain.uuid(31, 1): ImportLastTime(kg: 60, day: last, sessionID: MockTrain.uuid(30, 0)),
            MockTrain.uuid(31, 4): ImportLastTime(kg: 52.5, day: last, sessionID: MockTrain.uuid(30, 0)),
            MockTrain.uuid(31, 6): ImportLastTime(kg: 87.5, day: day(2026, 4, 20), sessionID: MockTrain.uuid(30, 1)),
            MockTrain.uuid(31, 8): ImportLastTime(kg: 120, day: day(2026, 4, 20), sessionID: MockTrain.uuid(30, 1)),
        ]
        let planPreview = ImportPlanPreview(index: 0, id: plan.id, state: alreadyImportedAll ? .alreadyInRYFT : .new,
                                            plan: plan, willBeSent: sendsPlan && !alreadyImportedAll, lastTime: lastTime,
                                            skippedExerciseNames: ["Hammer Curl · Dumbbell"])
        return ImportBuild(account: "preview", source: .alphaProgression, zone: zone, plans: [planPreview],
                           sessions: previews, customExercises: [], warnings: [], duplicatesChecked: duplicatesChecked,
                           enrolPlanID: nil)
    }

    /// A flow on step 5 with `build` in place.
    @MainActor
    static func previewFlow(_ build: ImportBuild = ImportMockData.build(), uploader: TrainImportUploader? = nil,
                            configure: (ImportFlowModel) -> Void = { _ in }) -> ImportFlowModel {
        flow(.preview, uploader: uploader) { flow in
            flow.build = build
            flow.included = build.defaultIncluded
            flow.buildState = .ready
            configure(flow)
        }
    }

    /// 60 exercises: the library's own names (matched) and invented ones (new), for the filter and search.
    static var manyExercises: Data {
        var w = ImportCSVWriter()
        w.plan("Big Library", weeks: 8, start: day(2026, 3, 2))
        let library = MockTrain.exercises.filter { $0.kind != .cardio }
        for dayNumber in 1...6 {
            w.day(dayNumber, "Day \(dayNumber)")
            for order in 1...10 {
                let n = (dayNumber - 1) * 10 + order
                if n <= library.count {
                    let e = library[n - 1]
                    w.planExercise(order, e.name, e.kind.title, sets: 3, reps: "10")
                } else {
                    w.planExercise(order, "Station \(n) Drill", "Machine", sets: 3, reps: "10")
                }
            }
        }
        return w.data
    }
}

#if DEBUG
/// Demo mode's import files (ui.md §12.2), chosen with `-uiTestImportFiles plans.csv,workouts.csv` in place of the
/// system picker, which UI tests can't drive. Dates follow the clock, so the workouts are recent and one falls on a
/// day demo data already has a workout (a duplicate for step 5).
enum ImportDemoFiles {
    static let argument = "uiTestImportFiles"
    static let planName = "Upper/Lower Base"

    /// The names asked for at launch; nil without the argument.
    static var requested: [String]? {
        guard let raw = UserDefaults.standard.string(forKey: argument), !raw.isEmpty else { return nil }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func load(_ names: [String], now: Date) -> [ImportFileAccess.Loaded] {
        names.map { name in
            switch name {
            case "plans.csv": ImportFileAccess.Loaded(name: name, result: .success(plans(now: now)))
            case "workouts.csv": ImportFileAccess.Loaded(name: name, result: .success(workouts(now: now)))
            case "garbage.txt": ImportFileAccess.Loaded(name: name, result: .success(ImportMockData.garbage))
            case "empty.csv": ImportFileAccess.Loaded(name: name, result: .failure(.empty))
            default: ImportFileAccess.Loaded(name: name, result: .failure(.unreadable))
            }
        }
    }

    private static func localDay(_ now: Date, minus days: Int) -> LocalDate {
        let date = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return LocalDate(date, in: .current) ?? .fallback
    }

    /// 1 plan · 2 days · 6 exercises: one likely match to check (Leg Press Wide) and one the library lacks (Nordic Curl).
    static func plans(now: Date) -> Data {
        var w = ImportCSVWriter()
        w.plan(planName, weeks: 6, start: localDay(now, minus: 21))
        w.day(1, "Upper")
        w.planExercise(1, "Bench Press", "Barbell", sets: 3, reps: "6-8")
        w.planExercise(2, "Lat Pulldown", "Cable", sets: 3, reps: "10-12")
        w.planExercise(3, "Dips", "Bodyweight", sets: 3, reps: "8")
        w.day(2, "Lower")
        w.planExercise(1, "Squat", "Barbell", sets: 3, reps: "5")
        w.planExercise(2, "Leg Press Wide", "Machine", sets: 3, reps: "10")
        w.planExercise(3, "Nordic Curl", "Bodyweight", sets: 3, reps: "6")
        return w.data
    }

    /// 4 workouts, newest first: the duplicate of demo data's latest Upper A or Lower A workout (same day, the same
    /// exercises), then three plan workouts with `+20` dips and one skipped squat set.
    static func workouts(now: Date) -> Data {
        var w = ImportCSVWriter()
        let names = Dictionary(MockTrain.exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let weighted: Set<UUID> = [MockTrain.upperA.id, MockTrain.lowerA.id]
        if let twin = MockTrain.history.last(where: { $0.planDayId.map(weighted.contains) ?? false }),
           let date = LocalDate(twin.startedAt, in: .current), let start = LocalDateTime(date: date, hour: 7, minute: 30) {
            w.session(twin.title, plan: nil, start: start, minutes: 55)
            for (order, exercise) in twin.exercises.enumerated() {
                guard let library = names[exercise.exerciseId] else { continue }
                let sets = exercise.sets.filter { !$0.isWarmup }.map { set in
                    (set.weightKg.map { ImportCSVWriter.number($0) } ?? "-", set.reps.map(String.init) ?? "-")
                }
                w.exercise(order + 1, library.nameEn, library.kind.rawValue.capitalized, reps: 8, sets: sets)
            }
        }
        let plan = planName
        if let start = LocalDateTime(date: localDay(now, minus: 13), hour: 7, minute: 5) {
            w.session("Upper", plan: (plan, 1, 2), start: start, minutes: 58)
            w.exercise(1, "Bench Press", "Barbell", reps: 8, sets: [("62.5", "8"), ("65", "7"), ("65", "6")])
            w.exercise(2, "Lat Pulldown", "Cable", reps: 10, sets: [("52.5", "10"), ("55", "9")])
            w.exercise(3, "Dips", "Bodyweight", reps: 8, sets: [("+20", "8"), ("+20", "7")])
        }
        if let start = LocalDateTime(date: localDay(now, minus: 18), hour: 18, minute: 45) {
            w.session("Lower", plan: (plan, 2, 1), start: start, minutes: 64)
            w.exercise(1, "Squat", "Barbell", reps: 5, sets: [("80", "5"), ("85", "5"), ("-", "-")])
            w.exercise(2, "Leg Press Wide", "Machine", reps: 10, sets: [("120", "10"), ("120", "10")])
            w.exercise(3, "Nordic Curl", "Bodyweight", reps: 6, sets: [("-", "6"), ("-", "5")])
        }
        if let start = LocalDateTime(date: localDay(now, minus: 20), hour: 18, minute: 30) {
            w.session("Upper", plan: (plan, 1, 1), start: start, minutes: 61)
            w.exercise(1, "Bench Press", "Barbell", reps: 8, sets: [("60", "8"), ("62.5", "8"), ("62.5", "7")])
            w.exercise(2, "Lat Pulldown", "Cable", reps: 10, sets: [("50", "10"), ("52.5", "10")])
            w.exercise(3, "Dips", "Bodyweight", reps: 8, sets: [("+20", "8"), ("+20", "6")])
        }
        return w.data
    }
}
#endif

extension ImportCSVWriter {
    /// `62.5`, `60`: a point and no trailing zeros, as the exports write weights.
    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
