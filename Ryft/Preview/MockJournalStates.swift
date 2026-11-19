// The Journal's states for previews, shots and tests (Nocturne PR 6 B §11, §14.1): Today's card answered, and the sheet answered,
// offline, read-only, without habits, loading, offline with the day not on this iPhone, a failed read, a failed save and
// saving. Each is built through a real `JournalStore` and `JournalSheetModel` on `MockJournal`, so its rows are the ones the
// sheet would build; only the states a running save or read are in (saving, failed) are set on the content afterwards.
import Foundation

@MainActor
enum MockJournalStates {
    enum Sheet: String, CaseIterable, Sendable {
        case answered, offline, readOnly, noHabits, loading, offlineUncached, failed, saveFailed, saving
    }

    /// Yesterday's answers as Today's card shows them.
    static var cardSummary: String {
        let store = store()
        return store.days[store.yesterday].flatMap { store.summary(of: $0) } ?? ""
    }

    /// `days` back from today, as the journal names a day ("2026-11-16").
    static func day(_ back: Int) -> String { DayFormat.string(from: DayFormat.shift(.now, days: -back)) }

    /// A store on its own in-memory environment with the catalog (`behaviors`) and these days cached; yesterday answered as
    /// API.md's example by default.
    static func store(behaviors: [Behavior] = MockJournal.behaviors, days: [JournalDay]? = nil,
                      online: Bool = true) -> JournalStore {
        let env = AppEnvironment.preview(online: online)
        env.persistence.saveDocument(behaviors, key: JournalStore.behaviorsKey, at: .now)
        for journal in days ?? [MockJournal.journal(day: day(1))] {
            env.persistence.saveDocument(journal, key: JournalStore.dayKey(journal.day), at: .now)
        }
        let store = JournalStore(env: env)
        _ = store.cachedDay(store.yesterday)
        return store
    }

    static func content(_ state: Sheet) -> JournalSheetContent {
        switch state {
        case .answered:
            return JournalSheetContent(JournalSheetModel(store: store()), isOnline: true)
        case .offline:
            return JournalSheetContent(JournalSheetModel(store: store(online: false)), isOnline: false)
        case .readOnly:
            // The strip's oldest day, as the platform answers a day that can't change any more.
            let oldest = day(JournalSheetModel.daysBack)
            let answered = JournalDay(day: oldest, answered: true, answeredAt: .now, editable: false,
                                      entries: [JournalEntry(behaviorId: MockJournal.alcohol, valueBool: false),
                                                JournalEntry(behaviorId: MockJournal.drinks, valueBool: false),
                                                JournalEntry(behaviorId: MockJournal.lastCaffeine, valueBool: true, valueTime: "14:15"),
                                                JournalEntry(behaviorId: MockJournal.sauna, valueBool: true),
                                                JournalEntry(behaviorId: MockJournal.stretching, valueBool: true)])
            return JournalSheetContent(JournalSheetModel(store: store(days: [answered]), day: oldest), isOnline: true)
        case .noHabits:
            let unanswered = JournalDay(day: day(1), answered: false, answeredAt: nil, editable: true, entries: [])
            return JournalSheetContent(JournalSheetModel(store: store(behaviors: MockJournal.noneEnabled, days: [unanswered])),
                                       isOnline: true)
        case .loading:
            return JournalSheetContent(JournalSheetModel(store: store(days: []), day: day(3)), isOnline: true)
        case .offlineUncached:
            return JournalSheetContent(JournalSheetModel(store: store(days: [], online: false), day: day(3)), isOnline: false)
        case .failed:
            var content = JournalSheetContent(JournalSheetModel(store: store(days: []), day: day(3)), isOnline: true)
            content.phase = .failed
            return content
        case .saveFailed:
            var content = Self.content(.answered)
            let error = APIError.http(503, "request timed out", requestID: "01JD8K2V9Q7M3X")
            content.error = JournalSheetModel.message(for: error, rows: content.groups.flatMap(\.rows))
            content.errorDetails = error.diagnosticDetails
            return content
        case .saving:
            var content = Self.content(.answered)
            content.isSaving = true
            return content
        }
    }
}
