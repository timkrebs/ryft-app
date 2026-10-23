import Foundation
import SwiftData

/// The signed-in account's remembered matches (design §4): read when step 4 opens, written once when Import is
/// tapped (never per tap, so an abandoned flow changes nothing), cleared from Profile → Data, exported with the
/// account's data, and wiped with `TrainStore.wipe()` at sign-out. Every read and write is for the current account
/// only; demo mode is its own account (`demo`).
@MainActor
final class ImportMappingStore {
    private let persistence: Persistence
    private let currentAccount: @MainActor () -> String?

    init(persistence: Persistence, account: @escaping @MainActor () -> String?) {
        self.persistence = persistence
        currentAccount = account
    }

    convenience init(env: AppEnvironment) {
        self.init(persistence: env.persistence) { env.isDemo ? "demo" : env.auth.accountID }
    }

    /// The account the store reads and writes now; nil when signed out.
    var account: String? { currentAccount() }

    /// This account's choices for one source, by key (the matcher's `remembered` takes `mapValues(\.exerciseID)`).
    func remembered(source: ImportFormatID) -> [SourceExerciseKey: RememberedMatch] {
        guard let account else { return [:] }
        return Dictionary(rows(account: account, source: source).map { ($0.key, $0.choice) }, uniquingKeysWith: { a, _ in a })
    }

    /// Upserts the choices of a confirmed import. `account` is the one the flow started with: when it is no longer
    /// the signed-in one, nothing is written. Returns whether the choices were saved.
    @discardableResult
    func remember(_ choices: [SourceExerciseKey: RememberedMatch], source: ImportFormatID, account: String,
                  at date: Date) -> Bool {
        guard self.account == account else {
            ImportLog.logger.info("Remembered matches not saved: the account changed")
            return false
        }
        guard !choices.isEmpty else { return true }
        let existing = Dictionary(rows(account: account, source: source).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for (key, choice) in choices.sorted(by: { ($0.key.name, $0.key.equipment) < ($1.key.name, $1.key.equipment) }) {
            if let row = existing[key] {
                row.exerciseId = choice.exerciseID
                row.bodyweightRaw = choice.bodyweight?.rawValue
                row.updatedAt = date
            } else {
                persistence.context.insert(ImportMapping(account: account, source: source, key: key, choice: choice, at: date))
            }
        }
        persistence.save()
        ImportLog.logger.info("Remembered \(choices.count) matches")
        return true
    }

    /// Whether Profile → Data shows "Clear remembered matches".
    var hasEntries: Bool {
        guard let account else { return false }
        var descriptor = FetchDescriptor<ImportMapping>(predicate: #Predicate { $0.account == account })
        descriptor.fetchLimit = 1
        return ((try? persistence.context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// "Clear remembered matches": this account's, every source. The next import asks about every exercise again.
    func clear() {
        guard let account else { return }
        for row in rows(account: account, source: nil) { persistence.context.delete(row) }
        persistence.save()
    }

    /// For "Export my data": this account's choices, every source, in a stable order.
    func records() -> [ImportMappingRecord] {
        guard let account else { return [] }
        return rows(account: account, source: nil).map {
            ImportMappingRecord(source: $0.source, name: $0.keyName, equipment: $0.keyEquipment, exerciseId: $0.exerciseId,
                                bodyweightAnswer: $0.bodyweightRaw.flatMap(BodyweightAnswer.init(rawValue:)),
                                updatedAt: $0.updatedAt)
        }
    }

    private func rows(account: String, source: ImportFormatID?) -> [ImportMapping] {
        let predicate: Predicate<ImportMapping>
        if let raw = source?.rawValue {
            predicate = #Predicate { $0.account == account && $0.source == raw }
        } else {
            predicate = #Predicate { $0.account == account }
        }
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.uid)])
        return (try? persistence.context.fetch(descriptor)) ?? []
    }
}
