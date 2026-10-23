import Foundation

/// Alpha Progression's CSV export (design §3): `;`-separated, text in double quotes, ` · ` inside fields. A plans
/// file holds plan headers, days and exercises; a workouts file holds session blocks (header, exercises, set tables),
/// newest first. Both can be in one file; classification never depends on blank lines.
struct AlphaProgressionFormat: TrainImportFormat {
    var tokens: AlphaProgressionTokens = .standard

    var id: ImportFormatID { .alphaProgression }

    var displayName: LocalizedStringResource {
        LocalizedStringResource("Alpha Progression", comment: "The app an imported file came from (a data source, named factually).")
    }

    // MARK: Detection

    /// `.strong`: a `#;<unit>;<reps>` table header, or a plan header followed by a plan exercise. `.weak`: at least two
    /// quoted fields with ` · ` and a set-row-shaped line, but no header. `.none` otherwise, and always when the
    /// first line is a comma-separated header row (another app's format).
    func detect(_ head: Data) -> ImportConfidence {
        let head = ImportHygiene.head(of: head)
        guard !ImportHygiene.isUnsupportedEncoding(head) else { return .none }
        let reader = LineReader(head, maxLineBytes: ImportLimits.standard.maxLineBytes)
        var classifier = AlphaProgressionClassifier(tokens: tokens)
        var sawText = false
        var sawPlanHeader = false
        var sawSetRow = false
        var dottedQuotedFields = 0
        for raw in reader where !raw.isTooLong {
            let text = reader.text(of: raw).text
            if !sawText, !text.allSatisfy(\.isWhitespace) {
                sawText = true
                if Self.isHeaderRow(text) { return .none }
            }
            let line = CSVFields.split(text)
            for (field, isQuoted) in zip(line.fields, line.quoted) where isQuoted && field.contains(" \u{00B7} ") {
                dottedQuotedFields += 1
            }
            switch classifier.classify(line) {
            case .tableHeader(.some):
                return .strong
            case .planHeader:
                sawPlanHeader = true
            case .planExercise:
                if sawPlanHeader { return .strong }
            case .setRow:
                sawSetRow = true
            default:
                break
            }
        }
        return dottedQuotedFields >= Self.weakDottedFields && sawSetRow ? .weak : .none
    }

    /// Quoted fields with ` · ` that, with a set row and no table header, make a file `.weak`.
    static let weakDottedFields = 2

    /// A first line like `Date,Workout Name,Exercise Name`: at least three alphabetic comma-separated fields, no `;`.
    static func isHeaderRow(_ text: String) -> Bool {
        guard !text.contains(";") else { return false }
        return text.split(separator: ",").filter { $0.contains(where: \.isLetter) }.count >= 3
    }

    // MARK: Parsing

    func parse(_ data: Data, limits: ImportLimits) throws -> ImportBundle {
        var stats = ParseStats()
        return try parse(data, limits: limits, stats: &stats)
    }

    /// `parse` with a measure of its work (`ParseStats`), so tests can bound it without a clock.
    func parse(_ data: Data, limits: ImportLimits, stats: inout ParseStats) throws -> ImportBundle {
        guard data.count <= limits.maxFileBytes else { throw ImportError.tooLarge(bytes: data.count) }
        guard !ImportHygiene.isUnsupportedEncoding(data) else { throw ImportError.unsupportedEncoding }
        var folder = AlphaProgressionFolder(limits: limits)
        let legacy = ImportHygiene.legacyText(data)
        if legacy != nil { folder.warn(.legacyEncoding, SourceLine(file: 0, line: 1)) }
        let text = legacy ?? data
        stats.visited += data.count + (legacy?.count ?? 0) // the UTF-8 check, and the transcoded copy
        var classifier = AlphaProgressionClassifier(tokens: tokens)
        let reader = LineReader(text, maxLineBytes: limits.maxLineBytes)
        for raw in reader {
            if raw.number % 1_024 == 0 { try Task.checkCancellation() }
            stats.lines += 1
            stats.visited += raw.bytes.count + 1
            folder.lineCount = raw.number
            let at = SourceLine(file: 0, line: raw.number)
            if raw.isTooLong {
                folder.warn(.lineTooLong, at)
                continue
            }
            let (lineText, isInvalid) = reader.text(of: raw)
            stats.visited += raw.bytes.count
            if isInvalid { folder.warn(.invalidText, at) }
            let line = CSVFields.split(lineText)
            stats.visited += line.visited
            let kind = classifier.classify(line)
            if case let .setRow(load, reps) = kind { stats.visited += load.utf8.count + reps.utf8.count }
            folder.take(kind, at: at)
        }
        stats.visited += classifier.visited
        return folder.finish(format: id)
    }

    /// What a line is (`AlphaProgressionClassifier`).
    func classify(_ line: CSVLine) -> AlphaProgressionLine {
        var classifier = AlphaProgressionClassifier(tokens: tokens)
        return classifier.classify(line)
    }
}

/// The work of one parse, counted instead of timed.
struct ParseStats: Sendable {
    var lines = 0
    /// Bytes and characters visited: the line scan, the UTF-8 decode, the field split, and every part split, scanner
    /// or token match over a field (charged with the field's whole length). Linear parsing keeps it under a small
    /// multiple of the file's bytes plus its lines; anything quadratic breaks that bound in the fuzz test.
    var visited = 0
}

/// What a line is, from its fields alone (design §3's table). Numbers in set rows are scanned later, when the table's
/// unit is known. Counts the characters its part splits, scanners and token matches pass over (`visited`).
struct AlphaProgressionClassifier {
    let tokens: AlphaProgressionTokens
    private(set) var visited = 0

    private static let separator = " \u{00B7} "

    init(tokens: AlphaProgressionTokens) {
        self.tokens = tokens
    }

    mutating func classify(_ line: CSVLine) -> AlphaProgressionLine {
        guard let first = line.field(0) else { return .blank }
        if first == "#" {
            let unitText = line.field(1) ?? ""
            let repsText = line.field(2) ?? ""
            charge(unitText)
            charge(repsText)
            guard line.count == 3, !line.hasMore, let unit = tokens.units[unitText.lowercased()],
                  tokens.repsHeader.contains(repsText.lowercased()) else { return .tableHeader(nil) }
            return .tableHeader(unit)
        }
        // A set row's index is unquoted, and a workout titled with a number (`"5";"2026-02-13 5:10 pm";…`) isn't one.
        if !line.isQuoted(0), isSetIndex(first), !isDateTime(line.field(1)) {
            guard line.count == 3, !line.hasMore, let load = line.field(1), let reps = line.field(2) else { return .wideSetRow }
            return .setRow(load: load, reps: reps)
        }
        if line.count == 1 { return classifySingle(first) }
        let second = line.field(1) ?? ""
        let third = line.field(2)
        if let (order, rest) = ordered(first), let sets = count(second, tokens.sets) {
            let (name, equipment) = Self.nameAndEquipment(parts(rest))
            guard !name.isEmpty else { return .unrecognised }
            var reps: ImportScanResult<ClosedRange<Int>> = .absent
            if let third { reps = targetReps(third) ?? .unreadable }
            return .planExercise(order: order, name: name, equipment: equipment, sets: sets, reps: reps)
        }
        var duration: ImportScanResult<Int> = .absent
        if let third { duration = scanDuration(third) }
        switch dateTime(second) {
        case let .dateTime(start, conflict):
            return sessionHeader(first, start: start, meridiemConflict: conflict, duration: duration)
        case let .dateOnly(date):
            // A date without a time but with a duration is a workout whose time can't be read, not a plan.
            if case .value = duration { return sessionHeader(first, start: nil, meridiemConflict: false, duration: duration) }
            return planHeader(parts(first), field: first, start: date, dateUnreadable: false)
        case .unreadable:
            if case .value = duration { return sessionHeader(first, start: nil, meridiemConflict: false, duration: duration) }
            if line.count == 2, let header = planHeaderWithWeeks(parts(first), dateUnreadable: true) { return header }
            return .unrecognised
        }
    }

    // MARK: Line shapes

    /// One field: a plan day, a session exercise, or a plan header without a date.
    private mutating func classifySingle(_ field: String) -> AlphaProgressionLine {
        let fieldParts = parts(field)
        if let head = fieldParts.first, let number = numbered(head, tokens.day) {
            return .planDay(number: number, name: fieldParts.dropFirst().joined(separator: Self.separator))
        }
        if let (order, rest) = ordered(field) {
            var restParts = parts(rest)
            var reps: ImportScanResult<ClosedRange<Int>> = .absent
            if restParts.count >= 2, let last = restParts.last, let target = targetReps(last) {
                reps = target
                restParts.removeLast()
            }
            let (name, equipment) = Self.nameAndEquipment(restParts)
            guard !name.isEmpty else { return .unrecognised }
            return .sessionExercise(order: order, name: name, equipment: equipment, reps: reps)
        }
        return planHeaderWithWeeks(fieldParts, dateUnreadable: false) ?? .unrecognised
    }

    /// `Name · N weeks` without a readable date: a plan header only when the weeks part is there.
    private mutating func planHeaderWithWeeks(_ parts: [String], dateUnreadable: Bool) -> AlphaProgressionLine? {
        guard parts.count >= 2, let last = parts.last, let weeks = count(last, tokens.weeks) else { return nil }
        return .planHeader(name: parts.dropLast().joined(separator: Self.separator), weeks: weeks, start: nil,
                           dateUnreadable: dateUnreadable)
    }

    private mutating func planHeader(_ parts: [String], field: String, start: LocalDate?,
                                     dateUnreadable: Bool) -> AlphaProgressionLine {
        if parts.count >= 2, let last = parts.last, let weeks = count(last, tokens.weeks) {
            return .planHeader(name: parts.dropLast().joined(separator: Self.separator), weeks: weeks, start: start,
                               dateUnreadable: dateUnreadable)
        }
        return .planHeader(name: field, weeks: nil, start: start, dateUnreadable: dateUnreadable)
    }

    /// A workout's title field, in this order:
    /// 1. `name · <day> N · <week> W · plan`, at the first such run (names may contain ` · `);
    /// 2. without such a run, `name · <day> N · plan`, at the first day not followed by a week;
    /// 3. `title · <standalone>`, which is never a plan workout, whatever days it names;
    /// 4. a plain title.
    private mutating func sessionHeader(_ field: String, start: LocalDateTime?, meridiemConflict: Bool,
                                        duration: ImportScanResult<Int>) -> AlphaProgressionLine {
        let fieldParts = parts(field)
        var dayNumbers: [Int?] = []
        var weekNumbers: [Int?] = []
        for part in fieldParts {
            dayNumbers.append(numbered(part, tokens.day))
            weekNumbers.append(numbered(part, tokens.week))
        }
        let isStandalone = fieldParts.count >= 2 && fieldParts.last.map { isStandaloneToken($0) } == true
        var title = field
        var plan: ImportedSession.PlanRef?
        if !isStandalone {
            for index in fieldParts.indices.dropFirst() where index + 2 < fieldParts.count {
                guard let day = dayNumbers[index], let week = weekNumbers[index + 1] else { continue }
                plan = .init(planName: fieldParts.dropFirst(index + 2).joined(separator: Self.separator), dayNumber: day,
                             weekNumber: week)
                title = fieldParts.prefix(index).joined(separator: Self.separator)
                break
            }
        }
        if !isStandalone, plan == nil {
            for index in fieldParts.indices.dropFirst() where index + 1 < fieldParts.count {
                guard let day = dayNumbers[index], weekNumbers[index + 1] == nil else { continue }
                plan = .init(planName: fieldParts.dropFirst(index + 1).joined(separator: Self.separator), dayNumber: day,
                             weekNumber: nil)
                title = fieldParts.prefix(index).joined(separator: Self.separator)
                break
            }
        }
        if isStandalone {
            title = fieldParts.dropLast().joined(separator: Self.separator)
        }
        return .sessionHeader(title: title, plan: plan, start: start, meridiemConflict: meridiemConflict, duration: duration)
    }

    /// The last part is the equipment when there are two or more; the rest is the name.
    private static func nameAndEquipment(_ parts: [String]) -> (name: String, equipment: String?) {
        guard parts.count >= 2, let last = parts.last else { return (parts.joined(separator: separator), nil) }
        return (parts.dropLast().joined(separator: separator), last.isEmpty ? nil : last)
    }

    // MARK: Metered scans

    private mutating func charge(_ text: some StringProtocol) {
        visited += text.utf8.count
    }

    private mutating func parts(_ field: String) -> [String] {
        charge(field)
        return CSVFields.parts(field)
    }

    private mutating func ordered(_ field: String) -> (order: Int, rest: String)? {
        charge(field)
        return tokens.ordered(field)
    }

    private mutating func count(_ part: String, _ set: Set<String>) -> Int? {
        charge(part)
        return tokens.count(part, set)
    }

    private mutating func numbered(_ part: String, _ set: Set<String>) -> Int? {
        charge(part)
        return tokens.numbered(part, set)
    }

    private mutating func targetReps(_ part: String) -> ImportScanResult<ClosedRange<Int>>? {
        charge(part)
        return tokens.targetReps(part)
    }

    private mutating func isStandaloneToken(_ part: String) -> Bool {
        charge(part)
        return tokens.isStandalone(part)
    }

    private mutating func scanDuration(_ field: String) -> ImportScanResult<Int> {
        charge(field)
        return ImportScan.duration(field, tokens: tokens)
    }

    private mutating func dateTime(_ field: String) -> ImportScan.DateTime {
        charge(field)
        return ImportScan.dateTime(field, tokens: tokens)
    }

    private mutating func isSetIndex(_ field: String) -> Bool {
        charge(field)
        return ImportScan.integer(field) != nil
    }

    /// Field 1 reads as a date and a time (only a field with a `:` is scanned).
    private mutating func isDateTime(_ field: String?) -> Bool {
        guard let field else { return false }
        charge(field)
        guard field.contains(":") else { return false }
        if case .dateTime = dateTime(field) { return true }
        return false
    }
}

/// A classified line of an Alpha Progression file.
enum AlphaProgressionLine: Equatable, Sendable {
    case blank
    case planHeader(name: String, weeks: Int?, start: LocalDate?, dateUnreadable: Bool)
    case planDay(number: Int, name: String)
    case planExercise(order: Int, name: String, equipment: String?, sets: Int, reps: ImportScanResult<ClosedRange<Int>>)
    /// `start` nil: the date or time couldn't be read, so the block is skipped.
    case sessionHeader(title: String, plan: ImportedSession.PlanRef?, start: LocalDateTime?, meridiemConflict: Bool,
                       duration: ImportScanResult<Int>)
    case sessionExercise(order: Int, name: String, equipment: String?, reps: ImportScanResult<ClosedRange<Int>>)
    /// nil: other columns than `#;<unit>;<reps>`.
    case tableHeader(WeightUnit?)
    case setRow(load: String, reps: String)
    /// Starts like a set row but has another number of columns: skipped with an unsupported table, else unrecognised.
    case wideSetRow
    case unrecognised
}

/// The block state machine (design §3): `top`, `plan(day?)`, `session(exercise?, table?)`, and `skipping` for a
/// block whose header was refused. Open blocks live in their own variables and are appended when they close, so
/// nothing indexes into the arrays.
struct AlphaProgressionFolder {
    let limits: ImportLimits
    var lineCount = 0

    private(set) var plans: [ImportedPlan] = []
    private(set) var sessions: [ImportedSession] = []
    private(set) var warnings: [ImportWarning] = []
    private(set) var suppressedWarnings = 0

    private enum Mode { case top, plan, session, skipping }
    private enum Table { case none, header(WeightUnit), assumed(WeightUnit) }
    /// Each cap warns once per scope: plans and sessions per file, days per plan, exercises per day or per session,
    /// sets per exercise. A session's caps are the platform's (`.overPlatformLimit`); the rest are the parser's own
    /// (`.limitReached`).
    private enum Cap: Hashable {
        case plans, sessions, days, planExercises, sessionExercises, sets

        var kind: ImportWarning.Kind {
            switch self {
            case .sessionExercises, .sets: .overPlatformLimit
            case .plans, .sessions, .days, .planExercises: .limitReached
            }
        }
    }

    private var mode = Mode.top
    private var plan: ImportedPlan?
    private var day: ImportedDay?
    /// The open day is over the cap: its exercises are dropped.
    private var dropDay = false
    private var session: ImportedSession?
    private var exercise: ImportedSessionExercise?
    /// The open exercise's rows are dropped (unsupported columns, or the exercise is over the cap).
    private var dropRows = false
    private var table = Table.none
    /// The open exercise's next row ordinal; every row counts.
    private var row = 0
    private var lastUnit: WeightUnit?
    private var capsWarned: Set<Cap> = []

    init(limits: ImportLimits) {
        self.limits = limits
    }

    mutating func warn(_ kind: ImportWarning.Kind, _ at: SourceLine) {
        if warnings.count < limits.maxWarnings {
            warnings.append(ImportWarning(at: at, kind: kind))
        } else {
            suppressedWarnings += 1
        }
    }

    mutating func take(_ line: AlphaProgressionLine, at: SourceLine) {
        switch line {
        case .blank:
            break
        case .unrecognised:
            warn(.unrecognisedLine, at)
        case let .planHeader(name, weeks, start, dateUnreadable):
            closeBlock()
            guard plans.count < limits.maxPlans else { return refuseBlock(.plans, at) }
            if dateUnreadable { warn(.unreadableDate, at) }
            plan = ImportedPlan(name: name, weeks: weeks, startDate: start, days: [], source: at)
            mode = .plan
        case let .sessionHeader(title, ref, start, conflict, duration):
            closeBlock()
            guard let start else {
                warn(.unreadableDate, at)
                mode = .skipping
                return
            }
            guard sessions.count < limits.maxSessions else { return refuseBlock(.sessions, at) }
            if conflict { warn(.meridiemConflict, at) }
            var minutes: Int?
            switch duration {
            case let .value(value): minutes = value
            case .absent: minutes = nil
            case .unreadable: warn(.unreadableDuration, at)
            case .implausible: warn(.implausibleValue, at)
            }
            session = ImportedSession(title: title, plan: ref, start: start, durationMinutes: minutes, exercises: [], source: at)
            mode = .session
        case let .planDay(number, name):
            guard mode != .skipping else { return }
            guard mode == .plan else { return warn(.outsideBlock, at) }
            closeDay()
            guard (plan?.days.count ?? 0) < limits.maxExercisesPerBlock else {
                dropDay = true
                return warnCap(.days, at)
            }
            // Both days are kept (nothing the user wrote is lost); ids keyed on the day number must tell them apart.
            if plan?.days.contains(where: { $0.number == number }) == true { warn(.duplicateDay, at) }
            capsWarned.remove(.planExercises)
            day = ImportedDay(number: number, name: name, exercises: [])
        case let .planExercise(order, name, equipment, sets, reps):
            guard mode != .skipping, !dropDay else { return }
            guard mode == .plan, day != nil else { return warn(.outsideBlock, at) }
            guard (day?.exercises.count ?? 0) < limits.maxExercisesPerBlock else { return warnCap(.planExercises, at) }
            guard sets <= ImportScan.maxReps else { return warn(.implausibleValue, at) }
            let targetReps = target(reps, at)
            day?.exercises.append(ImportedPlanExercise(order: order, name: name, equipment: equipment, sets: sets,
                                                       targetReps: targetReps))
        case let .sessionExercise(order, name, equipment, reps):
            guard mode != .skipping else { return }
            guard mode == .session else { return warn(.outsideBlock, at) }
            closeExercise()
            guard (session?.exercises.count ?? 0) < limits.maxExercisesPerBlock else {
                dropRows = true
                return warnCap(.sessionExercises, at)
            }
            exercise = ImportedSessionExercise(order: order, name: name, equipment: equipment, targetReps: target(reps, at),
                                               unit: nil, sets: [])
        case let .tableHeader(unit):
            guard mode != .skipping, !dropRows else { return }
            guard mode == .session, exercise != nil else { return warn(.outsideBlock, at) }
            guard let unit else {
                dropRows = true
                return warn(.unsupportedColumns, at)
            }
            table = .header(unit)
            lastUnit = unit
            exercise?.unit = unit
        case let .setRow(loadText, repsText):
            guard mode != .skipping, !dropRows else { return }
            guard mode == .session, exercise != nil else { return warn(.outsideBlock, at) }
            takeSet(load: loadText, reps: repsText, at: at)
        case .wideSetRow:
            guard mode != .skipping, !dropRows else { return }
            if mode == .session, exercise != nil { row += 1 }
            warn(.unrecognisedLine, at)
        }
    }

    mutating func finish(format: ImportFormatID) -> ImportBundle {
        closeBlock()
        return ImportBundle(format: format, plans: plans, sessions: sessions, warnings: warnings,
                            suppressedWarnings: suppressedWarnings, lineCount: lineCount)
    }

    // MARK: Private

    private mutating func takeSet(load loadText: String, reps repsText: String, at: SourceLine) {
        let ordinal = row
        row += 1
        guard (exercise?.sets.count ?? 0) < limits.maxSetsPerExercise else { return warnCap(.sets, at) }
        let unit: WeightUnit
        switch table {
        case let .header(header): unit = header
        case let .assumed(assumed): unit = assumed
        case .none:
            unit = lastUnit ?? .kg
            table = .assumed(unit)
            warn(.missingTableHeader(assumed: unit), at)
        }
        var load: ImportedLoad?
        switch ImportScan.load(loadText, unit: unit) {
        case let .value(value): load = value
        case .absent: load = nil
        case .unreadable: return warn(.unreadableNumber, at)
        case .implausible: return warn(.implausibleValue, at)
        }
        var reps: Int?
        switch ImportScan.reps(repsText) {
        case let .value(value): reps = value
        case .absent: reps = nil
        case .unreadable: return warn(.unreadableNumber, at)
        case .implausible: return warn(.implausibleValue, at)
        }
        exercise?.sets.append(ImportedSet(ordinal: ordinal, load: load, reps: reps))
    }

    private mutating func target(_ reps: ImportScanResult<ClosedRange<Int>>, _ at: SourceLine) -> ClosedRange<Int>? {
        switch reps {
        case let .value(range): return range
        case .absent: return nil
        case .unreadable: warn(.unreadableNumber, at)
        case .implausible: warn(.implausibleValue, at)
        }
        return nil
    }

    /// Over a whole-file cap: the block is skipped, with one warning for the file.
    private mutating func refuseBlock(_ cap: Cap, _ at: SourceLine) {
        mode = .skipping
        warnCap(cap, at)
    }

    private mutating func warnCap(_ cap: Cap, _ at: SourceLine) {
        guard !capsWarned.contains(cap) else { return }
        capsWarned.insert(cap)
        warn(cap.kind, at)
    }

    private mutating func closeExercise() {
        if let exercise { session?.exercises.append(exercise) }
        exercise = nil
        dropRows = false
        table = .none
        row = 0
        capsWarned.remove(.sets)
    }

    private mutating func closeDay() {
        if let day { plan?.days.append(day) }
        day = nil
        dropDay = false
    }

    private mutating func closeBlock() {
        closeExercise()
        if let session { sessions.append(session) }
        session = nil
        closeDay()
        if let plan { plans.append(plan) }
        plan = nil
        mode = .top
        capsWarned.subtract([.days, .planExercises, .sessionExercises])
    }
}
