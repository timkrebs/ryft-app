import Foundation
import SwiftData

/// A remembered choice (design §4, §10): for one account and source, the normalised source exercise and the library
/// exercise the user matched it to, with the bodyweight answer if one was given. Holds no file text, only the key.
/// In `TrainStore`, so `wipe()` removes it at sign-out; read and written through `ImportMappingStore`.
@Model
final class ImportMapping {
    /// `account␟source␟name␟equipment`: one row per source exercise and account.
    @Attribute(.unique) var uid: String
    var account: String
    var source: String
    var keyName: String
    var keyEquipment: String
    var exerciseId: UUID
    /// `BodyweightAnswer.rawValue`.
    var bodyweightRaw: String?
    var updatedAt: Date

    init(account: String, source: ImportFormatID, key: SourceExerciseKey, choice: RememberedMatch, at date: Date) {
        uid = Self.uid(account: account, source: source, key: key)
        self.account = account
        self.source = source.rawValue
        keyName = key.name
        keyEquipment = key.equipment
        exerciseId = choice.exerciseID
        bodyweightRaw = choice.bodyweight?.rawValue
        updatedAt = date
    }

    static func uid(account: String, source: ImportFormatID, key: SourceExerciseKey) -> String {
        [account, source.rawValue, key.name, key.equipment].joined(separator: ImportIDs.separator)
    }

    var key: SourceExerciseKey { SourceExerciseKey(name: keyName, equipment: keyEquipment) }

    var choice: RememberedMatch {
        RememberedMatch(exerciseID: exerciseId, bodyweight: bodyweightRaw.flatMap(BodyweightAnswer.init(rawValue:)))
    }
}

/// What the user chose for one source exercise.
struct RememberedMatch: Equatable, Sendable {
    var exerciseID: UUID
    var bodyweight: BodyweightAnswer?
}

/// One remembered choice in "Export my data" (plan.md → Decisions).
struct ImportMappingRecord: Codable, Equatable, Sendable {
    /// The app the file came from (`alpha_progression`).
    let source: String
    /// The normalised source name and equipment (`SourceExerciseKey`).
    let name: String
    let equipment: String
    let exerciseId: UUID
    let bodyweightAnswer: BodyweightAnswer?
    let updatedAt: Date
}
