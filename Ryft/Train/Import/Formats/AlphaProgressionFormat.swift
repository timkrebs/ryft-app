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
            switch classify(line) {
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
        return dottedQuotedFields >= 2 && sawSetRow ? .weak : .none
    }

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

    /// `parse` with a count of its work (lines visited plus fields split), so tests can bound it without a clock.
    func parse(_ data: Data, limits: ImportLimits, stats: inout ParseStats) throws -> ImportBundle {
        guard data.count <= limits.maxFileBytes else { throw ImportError.tooLarge(bytes: data.count) }
        guard !ImportHygiene.isUnsupportedEncoding(data) else { throw ImportError.unsupportedEncoding }
        var folder = AlphaProgressionFolder(limits: limits)
        let reader = LineReader(data, maxLineBytes: limits.maxLineBytes)
        for raw in reader {
            if raw.number % 1_024 == 0 { try Task.checkCancellation() }
            stats.steps += 1
            folder.lineCount = raw.number
            let at = SourceLine(file: 0, line: raw.number)
            if raw.isTooLong {
                folder.warn(.lineTooLong, at)
                continue
            }
            let (text, isInvalid) = reader.text(of: raw)
            if isInvalid { folder.warn(.invalidText, at) }
            let line = CSVFields.split(text)
            stats.steps += line.count
            folder.take(classify(line), at: at)
        }
        return folder.finish(format: id)
    }

    // MARK: Classification

    /// What a line is, from its fields alone (design §3's table). Numbers in set rows are scanned later, when the
    /// table's unit is known.
    func classify(_ line: CSVLine) -> AlphaProgressionLine {
        guard let first = line.field(0) else { return .blank }
        if first == "#" {
            guard line.count == 3, !line.hasMore, let unitText = line.field(1), let repsText = line.field(2),
                  let unit = tokens.units[unitText.lowercased()],
                  tokens.repsHeader.contains(repsText.lowercased()) else { return .tableHeader(nil) }
            return .tableHeader(unit)
        }
        if ImportScan.integer(first) != nil {
            guard line.count == 3, !line.hasMore, let load = line.field(1), let reps = line.field(2) else { return .wideSetRow }
            return .setRow(load: load, reps: reps)
        }
        if line.count == 1 { return classifySingle(first) }
        let second = line.field(1) ?? ""
        let third = line.field(2)
        if let (order, rest) = tokens.ordered(first), let sets = tokens.count(second, tokens.sets) {
            let (name, equipment) = Self.nameAndEquipment(CSVFields.parts(rest))
            guard !name.isEmpty else { return .unrecognised }
            let reps: ImportScanResult<ClosedRange<Int>> = third.map { tokens.targetReps($0) ?? .unreadable } ?? .absent
            return .planExercise(order: order, name: name, equipment: equipment, sets: sets, reps: reps)
        }
        let duration = third.map { ImportScan.duration($0, tokens: tokens) } ?? .absent
        switch ImportScan.dateTime(second, tokens: tokens) {
        case let .dateTime(start, conflict):
            return sessionHeader(first, start: start, meridiemConflict: conflict, duration: duration)
        case let .dateOnly(date):
            if case .value = duration { return sessionHeader(first, start: nil, meridiemConflict: false, duration: duration) }
            return planHeader(first, start: date, dateUnreadable: false)
        case .unreadable:
            if case .value = duration { return sessionHeader(first, start: nil, meridiemConflict: false, duration: duration) }
            if line.count == 2, let header = planHeaderWithWeeks(first, dateUnreadable: true) { return header }
            return .unrecognised
        }
    }

    /// One field: a plan day, a session exercise, or a plan header without a date.
    private func classifySingle(_ field: String) -> AlphaProgressionLine {
        let parts = CSVFields.parts(field)
        if let head = parts.first, let number = tokens.numbered(head, tokens.day) {
            return .planDay(number: number, name: parts.dropFirst().joined(separator: " \u{00B7} "))
        }
        if let (order, rest) = tokens.ordered(field) {
            var parts = CSVFields.parts(rest)
            var reps: ImportScanResult<ClosedRange<Int>> = .absent
            if parts.count >= 2, let last = parts.last, let target = tokens.targetReps(last) {
                reps = target
                parts.removeLast()
            }
            let (name, equipment) = Self.nameAndEquipment(parts)
            guard !name.isEmpty else { return .unrecognised }
            return .sessionExercise(order: order, name: name, equipment: equipment, reps: reps)
        }
        if let header = planHeaderWithWeeks(field, dateUnreadable: false) {
            return header
        }
        return .unrecognised
    }

    /// `Name · N weeks` without a readable date: a plan header only when the weeks part is there.
    private func planHeaderWithWeeks(_ field: String, dateUnreadable: Bool) -> AlphaProgressionLine? {
        let parts = CSVFields.parts(field)
        guard parts.count >= 2, let last = parts.last, tokens.count(last, tokens.weeks) != nil else { return nil }
        return planHeader(field, start: nil, dateUnreadable: dateUnreadable)
    }

    private func planHeader(_ field: String, start: LocalDate?, dateUnreadable: Bool) -> AlphaProgressionLine {
        let parts = CSVFields.parts(field)
        if parts.count >= 2, let last = parts.last, let weeks = tokens.count(last, tokens.weeks) {
            return .planHeader(name: parts.dropLast().joined(separator: " \u{00B7} "), weeks: weeks, start: start,
                               dateUnreadable: dateUnreadable)
        }
        return .planHeader(name: field, weeks: nil, start: start, dateUnreadable: dateUnreadable)
    }

    /// `name · <day> N · <week> W · plan` (anchored on the first such run, since names may contain ` · `),
    /// `name · <day> N · plan`, `title · <standalone>`, or a plain title.
    private func sessionHeader(_ field: String, start: LocalDateTime?, meridiemConflict: Bool,
                               duration: ImportScanResult<Int>) -> AlphaProgressionLine {
        let parts = CSVFields.parts(field)
        let separator = " \u{00B7} "
        var title = field
        var plan: ImportedSession.PlanRef?
        for (index, part) in parts.enumerated().dropFirst() {
            guard let dayNumber = tokens.numbered(part, tokens.day) else { continue }
            let after = parts.dropFirst(index + 1)
            if let weekPart = after.first, let week = tokens.numbered(weekPart, tokens.week) {
                guard after.count >= 2 else { continue }
                plan = .init(planName: after.dropFirst().joined(separator: separator), dayNumber: dayNumber, weekNumber: week)
            } else {
                guard !after.isEmpty else { continue }
                plan = .init(planName: after.joined(separator: separator), dayNumber: dayNumber, weekNumber: nil)
            }
            title = parts.prefix(index).joined(separator: separator)
            break
        }
        if plan == nil, parts.count >= 2, let last = parts.last, tokens.isStandalone(last) {
            title = parts.dropLast().joined(separator: separator)
        }
        return .sessionHeader(title: title, plan: plan, start: start, meridiemConflict: meridiemConflict, duration: duration)
    }

    /// The last part is the equipment when there are two or more; the rest is the name.
    private static func nameAndEquipment(_ parts: [String]) -> (name: String, equipment: String?) {
        guard parts.count >= 2, let last = parts.last else { return (parts.joined(separator: " \u{00B7} "), nil) }
        return (parts.dropLast().joined(separator: " \u{00B7} "), last.isEmpty ? nil : last)
    }
}

/// Work done by one parse: lines visited plus fields split. Linear parsing keeps it at most 4 × lines.
struct ParseStats: Sendable {
    var steps = 0
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
    /// Each cap warns once per scope: plans and sessions per file, days per plan, exercises per day or session, sets
    /// per exercise.
    private enum Cap: Hashable { case plans, sessions, days, exercises, sets }

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
            capsWarned.remove(.exercises)
            day = ImportedDay(number: number, name: name, exercises: [])
        case let .planExercise(order, name, equipment, sets, reps):
            guard mode != .skipping, !dropDay else { return }
            guard mode == .plan, day != nil else { return warn(.outsideBlock, at) }
            guard (day?.exercises.count ?? 0) < limits.maxExercisesPerBlock else { return warnCap(.exercises, at) }
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
                return warnCap(.exercises, at)
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
        warn(.limitReached, at)
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
        capsWarned.subtract([.days, .exercises])
    }
}
