import Foundation

/// "Looks like a session you already logged" (design §6): an imported session on the same local day as a session the
/// user logged in RYFT, sharing at least 70 % of its exercises. Pure.
///
/// The overlap is `|I ∩ E| / max(|I|, |E|)` over distinct exercise ids with at least one performed set: with `max`, a
/// short session logged in RYFT can't hide a longer import, and a long one can't swallow a short import.
enum DuplicateDetector {
    static let threshold = 0.7

    /// An imported session as the detector sees it.
    struct Candidate: Equatable, Sendable {
        let id: UUID
        /// Its local day in the flow's zone (`LocalDate.key`, the file's wall clock).
        let day: String
        /// Distinct mapped exercises with at least one performed set.
        let exerciseIDs: Set<UUID>
    }

    /// `|a ∩ b| / max(|a|, |b|)`; 0 when both are empty.
    static func overlap(_ a: Set<UUID>, _ b: Set<UUID>) -> Double {
        let larger = max(a.count, b.count)
        guard larger > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(larger)
    }

    static func isDuplicate(_ a: Set<UUID>, _ b: Set<UUID>) -> Bool {
        !a.isEmpty && !b.isEmpty && overlap(a, b) >= threshold
    }

    /// For each candidate that duplicates a logged session: the logged session it matches best (the highest overlap,
    /// then the earliest start, then the smaller id). Logged sessions are put on their local day in `zone`.
    static func duplicates(of candidates: [Candidate], against logged: [LoggedSession], zone: TimeZone) -> [UUID: UUID] {
        guard !candidates.isEmpty, !logged.isEmpty else { return [:] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var byDay: [String: [LoggedSession]] = [:]
        for session in logged {
            let parts = calendar.dateComponents([.year, .month, .day], from: session.startedAt)
            guard let year = parts.year, let month = parts.month, let day = parts.day,
                  let date = LocalDate(year: year, month: month, day: day) else { continue }
            byDay[date.key, default: []].append(session)
        }
        var found: [UUID: UUID] = [:]
        for candidate in candidates {
            var best: (score: Double, session: LoggedSession)?
            for session in byDay[candidate.day] ?? [] where isDuplicate(candidate.exerciseIDs, session.exerciseIDs) {
                let score = overlap(candidate.exerciseIDs, session.exerciseIDs)
                if let current = best {
                    let better = score > current.score
                        || (score == current.score && (session.startedAt, session.id.uuidString)
                            < (current.session.startedAt, current.session.id.uuidString))
                    if !better { continue }
                }
                best = (score, session)
            }
            if let best { found[candidate.id] = best.session.id }
        }
        return found
    }
}
