import Foundation
import Testing
@testable import Ryft

/// Remembered matches: per account, upserted at the Import tap, cleared from Profile, wiped at sign-out (design §4, §10).
@MainActor
@Suite("Import mapping store")
struct ImportMappingStoreTests {
    /// The signed-in account, as the store reads it at each call.
    final class Session {
        var account: String?
        init(_ account: String?) { self.account = account }
    }

    let persistence = TrainStore(inMemory: true)
    let session = Session("account-a")
    let date = Date(timeIntervalSince1970: 1_790_000_000)

    var store: ImportMappingStore { ImportMappingStore(persistence: persistence) { [session] in session.account } }

    static let bench = SourceExerciseKey(name: "bench press", equipment: "barbell")
    static let dips = SourceExerciseKey(name: "dip", equipment: "bodyweight")
    static let exerciseA = MappingFixture.id(1)
    static let exerciseB = MappingFixture.id(2)

    @Test func remembersPerSource() {
        let saved = store.remember([Self.bench: RememberedMatch(exerciseID: Self.exerciseA, bodyweight: nil),
                                    Self.dips: RememberedMatch(exerciseID: Self.exerciseB, bodyweight: .bodyWeight)],
                                   source: .alphaProgression, account: "account-a", at: date)
        #expect(saved)
        let remembered = store.remembered(source: .alphaProgression)
        #expect(remembered[Self.bench] == RememberedMatch(exerciseID: Self.exerciseA, bodyweight: nil))
        #expect(remembered[Self.dips] == RememberedMatch(exerciseID: Self.exerciseB, bodyweight: .bodyWeight))
        #expect(store.remembered(source: ImportFormatID(rawValue: "other_app")).isEmpty)
        #expect(store.hasEntries)
    }

    @Test func upsertsByKey() {
        store.remember([Self.bench: RememberedMatch(exerciseID: Self.exerciseA, bodyweight: nil)],
                       source: .alphaProgression, account: "account-a", at: date)
        store.remember([Self.bench: RememberedMatch(exerciseID: Self.exerciseB, bodyweight: .ignore)],
                       source: .alphaProgression, account: "account-a", at: date.addingTimeInterval(60))
        #expect(store.remembered(source: .alphaProgression) == [Self.bench: RememberedMatch(exerciseID: Self.exerciseB,
                                                                                               bodyweight: .ignore)])
        let records = store.records()
        #expect(records.count == 1)
        #expect(records.first?.updatedAt == date.addingTimeInterval(60))
    }

    @Test func accountsAreIsolated() {
        store.remember([Self.bench: RememberedMatch(exerciseID: Self.exerciseA, bodyweight: nil)],
                       source: .alphaProgression, account: "account-a", at: date)
        session.account = "account-b"
        #expect(store.remembered(source: .alphaProgression).isEmpty)
        #expect(!store.hasEntries)
        #expect(store.records().isEmpty)
        store.remember([Self.bench: RememberedMatch(exerciseID: Self.exerciseB, bodyweight: nil)],
                       source: .alphaProgression, account: "account-b", at: date)
        #expect(store.remembered(source: .alphaProgression)[Self.bench]?.exerciseID == Self.exerciseB)
        session.account = "account-a"
        #expect(store.remembered(source: .alphaProgression)[Self.bench]?.exerciseID == Self.exerciseA)
    }

    /// A flow started by another account never writes into this one.
    @Test func neverWritesForAnotherAccount() {
        session.account = "account-b"
        let saved = store.remember([Self.bench: RememberedMatch(exerciseID: Self.exerciseA, bodyweight: nil)],
                                   source: .alphaProgression, account: "account-a", at: date)
        #expect(!saved)
        #expect(!store.hasEntries)
        session.account = "account-a"
        #expect(!store.hasEntries)
        session.account = nil
        #expect(!store.remember([Self.bench: RememberedMatch(exerciseID: Self.exerciseA, bodyweight: nil)],
                                source: .alphaProgression, account: "account-a", at: date))
    }

    @Test func signedOutReadsNothing() {
        store.remember([Self.bench: RememberedMatch(exerciseID: Self.exerciseA, bodyweight: nil)],
                       source: .alphaProgression, account: "account-a", at: date)
        session.account = nil
        #expect(store.remembered(source: .alphaProgression).isEmpty)
        #expect(!store.hasEntries)
        #expect(store.records().isEmpty)
        store.clear()
        session.account = "account-a"
        #expect(store.hasEntries)
    }

    /// Profile → Data → "Clear remembered matches": this account's, every source; another account's stay.
    @Test func clearRemovesOnlyThisAccount() {
        store.remember([Self.bench: RememberedMatch(exerciseID: Self.exerciseA, bodyweight: nil)],
                       source: .alphaProgression, account: "account-a", at: date)
        store.remember([Self.dips: RememberedMatch(exerciseID: Self.exerciseA, bodyweight: nil)],
                       source: ImportFormatID(rawValue: "other_app"), account: "account-a", at: date)
        session.account = "account-b"
        store.remember([Self.bench: RememberedMatch(exerciseID: Self.exerciseB, bodyweight: nil)],
                       source: .alphaProgression, account: "account-b", at: date)
        session.account = "account-a"
        store.clear()
        #expect(!store.hasEntries)
        #expect(store.remembered(source: .alphaProgression).isEmpty)
        session.account = "account-b"
        #expect(store.remembered(source: .alphaProgression)[Self.bench]?.exerciseID == Self.exerciseB)
    }

    /// Sign-out wipes the Train store, remembered matches included.
    @Test func wipeRemovesEverything() {
        store.remember([Self.bench: RememberedMatch(exerciseID: Self.exerciseA, bodyweight: nil)],
                       source: .alphaProgression, account: "account-a", at: date)
        persistence.wipe()
        #expect(!store.hasEntries)
        #expect(store.remembered(source: .alphaProgression).isEmpty)
        // And the store keeps working after it.
        store.remember([Self.dips: RememberedMatch(exerciseID: Self.exerciseB, bodyweight: nil)],
                       source: .alphaProgression, account: "account-a", at: date)
        #expect(store.remembered(source: .alphaProgression).keys.sorted { $0.name < $1.name } == [Self.dips])
    }

    @Test func recordsAreStableAndCarryNoAccount() {
        store.remember([Self.dips: RememberedMatch(exerciseID: Self.exerciseB, bodyweight: .addedWeight),
                        Self.bench: RememberedMatch(exerciseID: Self.exerciseA, bodyweight: nil)],
                       source: .alphaProgression, account: "account-a", at: date)
        let records = store.records()
        #expect(records == [
            ImportMappingRecord(source: "alpha_progression", name: "bench press", equipment: "barbell",
                                exerciseId: Self.exerciseA, bodyweightAnswer: nil, updatedAt: date),
            ImportMappingRecord(source: "alpha_progression", name: "dip", equipment: "bodyweight",
                                exerciseId: Self.exerciseB, bodyweightAnswer: .addedWeight, updatedAt: date),
        ])
    }

    /// The matcher takes what the store remembers.
    @Test func feedsTheMatcher() {
        let library = [MappingFixture.exercise(1, "Bench press", kind: .barbell),
                       MappingFixture.exercise(2, "Floor press", kind: .barbell)]
        let aliases = MappingFixture.vocabulary()
        let key = aliases.normalizer.key(name: "Bench Press", equipment: "Barbell")
        store.remember([key: RememberedMatch(exerciseID: Self.exerciseB, bodyweight: nil)],
                       source: .alphaProgression, account: "account-a", at: date)
        let remembered = store.remembered(source: .alphaProgression).mapValues(\.exerciseID)
        let match = ExerciseMatcher(library: library, aliases: aliases, remembered: remembered)
            .match(name: "Bench Press", equipment: "Barbell")
        #expect(match.tier == .remembered)
        #expect(match.exerciseID == Self.exerciseB)
    }

    /// The app's store: demo mode is its own account.
    @Test func environmentAccount() {
        let env = AppEnvironment.test()
        let mappings = ImportMappingStore(env: env)
        #expect(mappings.account == env.auth.accountID)
    }
}
