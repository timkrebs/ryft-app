import Foundation

// The parsed result of a training export (design note 2026-10-23-train-csv-import §2). Pure values: no
// SwiftData, no networking, nothing that holds the file. I3 (mapping) and I5 (ids, upload) build on them.

/// The app a file came from. The raw value is the platform's `source` and part of every derived id
/// (ADR 0007), so it is never renamed.
struct ImportFormatID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    static let alphaProgression = ImportFormatID(rawValue: "alpha_progression")
}

/// How sure a format is that a file is its own (`TrainImportFormat.detect`).
enum ImportConfidence: Int, Comparable, Sendable {
    case none, weak, strong

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A calendar day as written in the file, with no time zone. Only valid Gregorian dates exist.
struct LocalDate: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        guard (1900...2999).contains(year), (1...12).contains(month),
              day >= 1, day <= Self.days(inMonth: month, year: year) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// `YYYY-MM-DD`: part of derived ids (ADR 0007), so its format never changes.
    var key: String { "\(ImportPad.digits(year, 4))-\(ImportPad.digits(month, 2))-\(ImportPad.digits(day, 2))" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func days(inMonth month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}

/// A wall-clock time as written in the file, with no zone: ids use it as is, and `ImportTimeResolver` turns it into
/// an instant in the zone the flow captured (DST rules there).
struct LocalDateTime: Hashable, Comparable, Sendable {
    let date: LocalDate
    let hour: Int
    let minute: Int

    init?(date: LocalDate, hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.date = date
        self.hour = hour
        self.minute = minute
    }

    /// `YYYY-MM-DDTHH:mm`: part of derived ids (ADR 0007), so its format never changes.
    var key: String { "\(date.key)T\(ImportPad.digits(hour, 2)):\(ImportPad.digits(minute, 2))" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.date, lhs.hour, lhs.minute) < (rhs.date, rhs.hour, rhs.minute)
    }
}

/// Where something came from: the index of the picked file and its 1-based line. Never the line's text.
struct SourceLine: Hashable, Comparable, Sendable {
    let file: Int
    let line: Int

    static func < (lhs: Self, rhs: Self) -> Bool { (lhs.file, lhs.line) < (rhs.file, rhs.line) }
}

enum WeightUnit: String, Codable, Sendable {
    case kg, lb

    /// Pounds to kilograms, exactly (international avoirdupois pound).
    static let kilogramsPerPound = 0.45359237
}

struct ImportBundle: Equatable, Sendable {
    var format: ImportFormatID
    /// File order.
    var plans: [ImportedPlan]
    /// File order (newest first in Alpha Progression's exports).
    var sessions: [ImportedSession]
    /// Sorted by file, then line; at most `ImportLimits.maxWarnings`.
    var warnings: [ImportWarning]
    /// Warnings over the cap: counted, not kept.
    var suppressedWarnings: Int
    /// Lines read, summed over merged files.
    var lineCount: Int

    var isEmpty: Bool { plans.isEmpty && sessions.isEmpty }

    /// Another file's bundle added to this one. Plans are appended as they are. A session whose start key is already
    /// here (the same workout in two picked files) is kept once, with `.duplicateInFiles` at the dropped copy's line;
    /// the occurrences are counted, so two workouts that share a start in one file both survive.
    func merging(_ other: ImportBundle) -> ImportBundle {
        var remaining: [String: Int] = [:]
        for session in sessions { remaining[session.start.key, default: 0] += 1 }
        var merged = self
        merged.plans += other.plans
        var dropped: [ImportWarning] = []
        for session in other.sessions {
            let key = session.start.key
            if let left = remaining[key], left > 0 {
                remaining[key] = left - 1
                dropped.append(ImportWarning(at: session.source, kind: .duplicateInFiles))
            } else {
                merged.sessions.append(session)
            }
        }
        merged.warnings = ImportWarning.sorted(warnings + other.warnings + dropped)
        merged.suppressedWarnings += other.suppressedWarnings
        merged.lineCount += other.lineCount
        return merged
    }
}

struct ImportedPlan: Equatable, Sendable {
    var name: String
    /// `N weeks` from the header; nil when the file names none.
    var weeks: Int?
    var startDate: LocalDate?
    var days: [ImportedDay]
    var source: SourceLine
}

struct ImportedDay: Equatable, Sendable {
    /// The file's 1-based day number.
    var number: Int
    var name: String
    var exercises: [ImportedPlanExercise]
}

struct ImportedPlanExercise: Equatable, Sendable {
    /// The file's number before the name (`3.`); the array's order is the file order.
    var order: Int
    var name: String
    var equipment: String?
    var sets: Int
    var targetReps: ClosedRange<Int>?
}

struct ImportedSession: Equatable, Sendable {
    struct PlanRef: Equatable, Sendable {
        var planName: String
        /// 1-based, as in the file.
        var dayNumber: Int
        /// 1-based, as in the file; nil when the header names no week.
        var weekNumber: Int?
    }

    var title: String
    /// nil: a standalone workout.
    var plan: PlanRef?
    var start: LocalDateTime
    var durationMinutes: Int?
    var exercises: [ImportedSessionExercise]
    var source: SourceLine
}

struct ImportedSessionExercise: Equatable, Sendable {
    var order: Int
    var name: String
    var equipment: String?
    var targetReps: ClosedRange<Int>?
    /// The table header's unit; nil when the block had none (loads were read in the assumed unit and are kg now).
    var unit: WeightUnit?
    var sets: [ImportedSet]
}

struct ImportedSet: Equatable, Sendable {
    /// 0-based row in the exercise's table. Every row counts (`-` rows and dropped rows too), so ordinals are stable.
    var ordinal: Int
    /// nil: `-` (not done) or empty.
    var load: ImportedLoad?
    var reps: Int?

    /// Not performed: no reps, or zero. Counted, never imported as zero.
    var isSkipped: Bool { (reps ?? 0) == 0 }
}

/// A set's load in kilograms. `60` is a weight, `+60` an added (bodyweight-style) load, `-20` assistance.
enum ImportedLoad: Equatable, Sendable {
    case weight(kg: Double)
    case plus(kg: Double)
    case minus(kg: Double)

    var kg: Double {
        switch self {
        case let .weight(kg), let .plus(kg), let .minus(kg): kg
        }
    }
}

/// Whole-file refusals. Everything smaller is an `ImportWarning`.
enum ImportError: Error, Equatable, Sendable {
    case tooLarge(bytes: Int)
    case unsupportedEncoding
    case notRecognised
    case mixedFormats
    case empty
}

/// Caps that keep any input bounded. Tests shrink them.
struct ImportLimits: Sendable {
    var maxFileBytes = 8 << 20
    var maxLineBytes = 4_096
    var maxSessions = 10_000
    var maxPlans = 50
    /// Per block: days in a plan, exercises in a plan day, exercises in a session.
    var maxExercisesPerBlock = 200
    var maxSetsPerExercise = 200
    var maxWarnings = 200

    static let standard = ImportLimits()
}

/// A picked file, read into memory (`ImportFileAccess`, I4). `name` is shown in step 2 only: never stored or logged.
struct ImportFile: Sendable {
    let name: String
    let data: Data
}

/// Zero-padded decimal digits for the keys, without `String(format:)`.
enum ImportPad {
    static func digits(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return text.count >= width ? text : String(repeating: "0", count: width - text.count) + text
    }
}
