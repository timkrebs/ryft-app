import Foundation
@testable import Ryft

private final class ImportFixtureToken {}

/// The synthetic Alpha Progression exports in `Fixtures/Import/` (invented plans, exercises, dates and weights).
enum ImportFixture {
    static let alphaProgression = ["ap-plans", "ap-workouts", "ap-workouts-plus1", "ap-workouts-de", "ap-workouts-lbs",
                                   "ap-workouts-edge"]

    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: ImportFixtureToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "csv") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).csv"])
        }
        return try Data(contentsOf: url)
    }

    static func file(_ name: String) throws -> ImportFile {
        try ImportFile(name: "\(name).csv", data: data(name))
    }

    static func parse(_ name: String, limits: ImportLimits = .standard) throws -> ImportBundle {
        try AlphaProgressionFormat().parse(data(name), limits: limits)
    }

    static func parse(text: String, limits: ImportLimits = .standard) throws -> ImportBundle {
        try AlphaProgressionFormat().parse(Data(text.utf8), limits: limits)
    }

    /// Every kind, for tables over all of them.
    static let allKinds: [ImportWarning.Kind] = [
        .unrecognisedLine, .lineTooLong, .invalidText, .outsideBlock, .missingTableHeader(assumed: .kg),
        .missingTableHeader(assumed: .lb), .unsupportedColumns, .unreadableNumber, .implausibleValue, .unreadableDate,
        .unreadableDuration, .meridiemConflict, .duplicateInFiles, .limitReached, .nonexistentLocalTime,
        .repeatedLocalTime, .durationAssumed, .overPlatformLimit, .assistedLoad,
    ]
}

extension ImportBundle {
    var setCount: Int { sessions.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } } }
    var skippedSetCount: Int { sessions.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.filter(\.isSkipped).count } } }

    /// `"<line> <kind>"` per warning: compact to compare.
    var warningList: [String] { warnings.map { "\($0.at.line) \($0.kind.name)" } }

    /// Sessions without their source lines, to compare files whose lines moved.
    var sessionsIgnoringLines: [ImportedSession] {
        sessions.map { session in
            var session = session
            session.source = SourceLine(file: 0, line: 0)
            return session
        }
    }
}

extension ImportedSession {
    func exercise(_ index: Int) -> ImportedSessionExercise? {
        exercises.indices.contains(index) ? exercises[index] : nil
    }
}

extension ImportedSet {
    static func kg(_ ordinal: Int, _ kg: Double, _ reps: Int?) -> ImportedSet {
        ImportedSet(ordinal: ordinal, load: .weight(kg: kg), reps: reps)
    }
}
