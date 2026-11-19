// The Journal's states for previews, shots and tests (Nocturne PR 6 B §11, §14.1): Today's card answered, and the sheet answered,
// offline, read-only, without habits, loading, offline with the day not on this iPhone, a failed read, a failed save and
// saving. Each is built through a real `JournalStore` and `JournalSheetModel` on `MockJournal`, so its rows are the ones the
// sheet would build; only the states a running save or read are in (saving, failed) are set on the content afterwards.
//
// Every day is counted from one clock (`clock`, read once per run), never from `.now`: a state built just before midnight and
// one built just after still agree on "yesterday".
import Foundation

@MainActor
enum MockJournalStates {
    enum Sheet: String, CaseIterable, Sendable {
        case answered, offline, readOnly, noHabits, loading, offlineUncached, failed, saveFailed, saving
    }

    /// The instant the states are built around. It never moves; a test that needs another passes its own.
    nonisolated static let clock = TestClock(now: Date())

    /// Yesterday's answers as Today's card shows them.
    static var cardSummary: String {
        let store = store()
        return store.days[store.yesterday].flatMap { store.summary(of: $0) } ?? ""
    }

    /// `back` days before `clock`'s today, as the journal names a day ("2026-11-16").
    static func day(_ back: Int, clock: AppClock = clock) -> String {
        DayFormat.string(from: DayFormat.shift(clock.now(), days: -back))
    }

    /// A store on its own in-memory environment and `clock`, with the catalog (`behaviors`) and these days cached; yesterday
    /// answered as API.md's example by default.
    static func store(behaviors: [Behavior] = MockJournal.behaviors, days: [JournalDay]? = nil,
                      online: Bool = true, clock: AppClock = clock) -> JournalStore {
        let env = AppEnvironment.test(api: MockPlatformAPI(), clock: testClock(clock), online: online)
        env.persistence.saveDocument(behaviors, key: JournalStore.behaviorsKey, at: clock.now())
        for journal in days ?? [MockJournal.journal(day: day(1, clock: clock), today: clock.now())] {
            env.persistence.saveDocument(journal, key: JournalStore.dayKey(journal.day), at: clock.now())
        }
        let store = JournalStore(env: env)
        _ = store.cachedDay(store.yesterday)
        return store
    }

    /// `AppEnvironment.test` takes a `TestClock`: `clock` itself, or one standing at its time.
    private static func testClock(_ clock: AppClock) -> TestClock {
        (clock as? TestClock) ?? TestClock(now: clock.now())
    }

    static func content(_ state: Sheet, clock: AppClock = clock) -> JournalSheetContent {
        switch state {
        case .answered:
            return JournalSheetContent(JournalSheetModel(store: store(clock: clock)), isOnline: true)
        case .offline:
            return JournalSheetContent(JournalSheetModel(store: store(online: false, clock: clock)), isOnline: false)
        case .readOnly:
            // The strip's oldest day, as the platform answers a day that can't change any more.
            let oldest = day(JournalSheetModel.daysBack, clock: clock)
            let answered = JournalDay(day: oldest, answered: true, answeredAt: clock.now(), editable: false,
                                      entries: [JournalEntry(behaviorId: MockJournal.alcohol, valueBool: false),
                                                JournalEntry(behaviorId: MockJournal.drinks, valueBool: false),
                                                JournalEntry(behaviorId: MockJournal.lastCaffeine, valueBool: true, valueTime: "14:15"),
                                                JournalEntry(behaviorId: MockJournal.sauna, valueBool: true),
                                                JournalEntry(behaviorId: MockJournal.stretching, valueBool: true)])
            return JournalSheetContent(JournalSheetModel(store: store(days: [answered], clock: clock), day: oldest), isOnline: true)
        case .noHabits:
            let unanswered = JournalDay(day: day(1, clock: clock), answered: false, answeredAt: nil, editable: true, entries: [])
            let none = store(behaviors: MockJournal.noneEnabled, days: [unanswered], clock: clock)
            return JournalSheetContent(JournalSheetModel(store: none), isOnline: true)
        case .loading:
            return JournalSheetContent(JournalSheetModel(store: store(days: [], clock: clock), day: day(3, clock: clock)),
                                       isOnline: true)
        case .offlineUncached:
            return JournalSheetContent(JournalSheetModel(store: store(days: [], online: false, clock: clock), day: day(3, clock: clock)),
                                       isOnline: false)
        case .failed:
            var content = JournalSheetContent(JournalSheetModel(store: store(days: [], clock: clock), day: day(3, clock: clock)),
                                              isOnline: true)
            content.phase = .failed
            content.failedDetails = JournalSheetModel.readDetails(
                ResourceState(lastError: ResourceError(kind: .transient, status: 503, code: nil, requestID: "01JD8K2V9Q7M3X",
                                                       transport: nil, attempts: 3, at: clock.now()),
                              consecutiveFailures: 1))
            return content
        case .saveFailed:
            var content = Self.content(.answered, clock: clock)
            let error = APIError.http(503, "request timed out", requestID: "01JD8K2V9Q7M3X")
            content.error = JournalSheetModel.message(for: error)
            content.errorDetails = error.diagnosticDetails
            return content
        case .saving:
            var content = Self.content(.answered, clock: clock)
            content.isSaving = true
            return content
        }
    }
}
