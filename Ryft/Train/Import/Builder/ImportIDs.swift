import CryptoKit
import Foundation

/// Derived ids for imported items (ADR 0007, design §6): UUIDv5 (RFC 9562, SHA-1) under a fixed namespace, names
/// UTF-8 with fields joined by U+001F; occurrence counters start at 0. **Changing the namespace, the separator, the
/// field order or the key normalisation is a breaking change:** every earlier import would come back as duplicates.
enum ImportIDs {
    /// `aed18370-8351-4f38-9f14-af711a508076`, as a literal (no parsing, no force unwrap).
    static let namespace = UUID(uuid: (0xAE, 0xD1, 0x83, 0x70, 0x83, 0x51, 0x4F, 0x38,
                                       0x9F, 0x14, 0xAF, 0x71, 0x1A, 0x50, 0x80, 0x76))

    static let separator = "\u{1F}"

    /// RFC 9562 version 5.
    static func v5(namespace: UUID, name: String) -> UUID {
        var hash = Insecure.SHA1()
        withUnsafeBytes(of: namespace.uuid) { hash.update(bufferPointer: $0) }
        hash.update(data: Data(name.utf8))
        // SHA-1 has 20 bytes; the first 16 fill the UUID exactly.
        let digest = Array(hash.finalize()).prefix(16)
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuid) { $0.copyBytes(from: digest) }
        uuid.6 = (uuid.6 & 0x0F) | 0x50 // version 5
        uuid.8 = (uuid.8 & 0x3F) | 0x80 // RFC 9562 variant
        return UUID(uuid: uuid)
    }

    static func v5(namespace: UUID, fields: [String]) -> UUID {
        v5(namespace: namespace, name: fields.joined(separator: separator))
    }

    /// `account␟<id>`: the Supabase user id, lowercased; `demo` in demo mode. The parent of every top-level item.
    static func account(_ accountID: String) -> UUID {
        v5(namespace: namespace, fields: ["account", accountID.lowercased()])
    }

    /// `exercise␟src␟key.name␟key.equipment` under the account: a retried import updates the same custom exercise
    /// (`POST /v1/exercises` with the same id updates it).
    static func customExercise(account: UUID, source: ImportFormatID, key: SourceExerciseKey) -> UUID {
        v5(namespace: account, fields: ["exercise", source.rawValue, key.name, key.equipment])
    }

    /// `plan␟src␟fold(plan name)␟startDate.key or ""` under the account: the plan keeps its id while the file's name
    /// and start date do; a name edited in step 5 changes only `Plan.name`.
    static func plan(account: UUID, source: ImportFormatID, name: String, startDate: LocalDate?) -> UUID {
        v5(namespace: account, fields: ["plan", source.rawValue, SourceExerciseKey.fold(name), startDate?.key ?? ""])
    }

    /// `day␟<dayNumber>` under the plan. A day number the file names a second time (`.duplicateDay`, both kept) adds
    /// `␟<occurrence>` (1, 2, …), so the first keeps the plain recipe.
    static func planDay(plan: UUID, number: Int, occurrence: Int) -> UUID {
        let fields = occurrence == 0 ? ["day", String(number)] : ["day", String(number), String(occurrence)]
        return v5(namespace: plan, fields: fields)
    }

    /// `exercise␟key.name␟key.equipment␟<occurrence of the key in the day, from 0>` under the plan day. No position:
    /// a reorder changes `position`, not ids.
    static func planExercise(day: UUID, key: SourceExerciseKey, occurrence: Int) -> UUID {
        v5(namespace: day, fields: ["exercise", key.name, key.equipment, String(occurrence)])
    }

    /// `session␟src␟start.key␟<occurrence of that start key, oldest first, from 0>` under the account. The wall clock,
    /// not the instant: importing again in another zone finds the same ids. No title or duration.
    static func session(account: UUID, source: ImportFormatID, start: LocalDateTime, occurrence: Int) -> UUID {
        v5(namespace: account, fields: ["session", source.rawValue, start.key, String(occurrence)])
    }

    /// `exercise␟key.name␟key.equipment␟<occurrence of the key in the session, from 0>` under the session.
    static func sessionExercise(session: UUID, key: SourceExerciseKey, occurrence: Int) -> UUID {
        v5(namespace: session, fields: ["exercise", key.name, key.equipment, String(occurrence)])
    }

    /// `set␟<ordinal>` under the session exercise: the 0-based row, `-` rows keep theirs.
    static func set(exercise: UUID, ordinal: Int) -> UUID {
        v5(namespace: exercise, fields: ["set", String(ordinal)])
    }
}
