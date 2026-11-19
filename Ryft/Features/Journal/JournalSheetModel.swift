import Foundation
import Observation

/// The morning sheet ("How was yesterday?"): one row per enabled behavior,
/// grouped by category in the platform's order. Saving sends **every row shown**
/// (off rows as `value_bool: false`): that is what makes a "no".
@MainActor
@Observable
final class JournalSheetModel {
    /// The control a behavior gets.
    enum Control: Equatable {
        case toggle
        case stepper
        case time

        init(_ kind: BehaviorKind) {
            switch kind {
            case .yesNo: self = .toggle
            case .count: self = .stepper
            case .time: self = .time
            }
        }
    }

    struct Row: Identifiable, Equatable {
        let behavior: Behavior
        var on: Bool
        /// `count`: ≥ 1 while on.
        var count: Int
        /// `time`: local "HH:MM".
        var time: String
        var id: UUID { behavior.id }
        var control: Control { Control(behavior.kind) }

        var entry: JournalEntry {
            switch behavior.kind {
            case .yesNo: return JournalEntry(behaviorId: id, valueBool: on)
            case .count: return JournalEntry(behaviorId: id, valueBool: on, valueNum: on ? max(1, count) : nil)
            case .time: return JournalEntry(behaviorId: id, valueBool: on, valueTime: on ? time : nil)
            }
        }
    }

    struct Group: Identifiable, Equatable {
        let category: BehaviorCategory
        var rows: [Row]
        var id: BehaviorCategory { category }
    }

    /// What the sheet shows under the day strip (Nocturne PR 6 B §11.2). A day on this phone shows its rows (or, without a
    /// habit to ask about, the way to choose some). A day that isn't: outlines while it is read, a line when the iPhone is
    /// offline, and a failed read with Try again. Never the outlines for good (the user's offline-first rule, 2026-11-19).
    enum Phase: Equatable, Sendable {
        case loading, ready, noHabits, offline, failed
    }

    /// Profile → Journal's page opens on it (the no-habits link).
    let store: JournalStore
    /// Up to 14 days back (`editable`); the sheet opens on yesterday.
    private(set) var day: String
    private(set) var groups: [Group] = []
    private(set) var editable = true
    private(set) var isSaving = false
    private(set) var error: String?
    /// The failed save's status and request ID, for the message's Details (API.md → Errors).
    private(set) var errorDetails: String?
    private(set) var saved = false
    /// The day is on this phone (in memory or the SwiftData cache): its rows say what it holds.
    private(set) var hasDay = false
    /// A read of the day is on its way.
    private(set) var isLoading = false
    /// The last read of the day brought nothing back (offline is the caller's to tell apart: `phase(isOnline:)`).
    private(set) var loadFailed = false

    static let defaultTime = "18:00"
    static let daysBack = 14

    init(store: JournalStore, day: String? = nil) {
        self.store = store
        self.day = day ?? store.yesterday
        rebuild()
    }

    var title: String {
        guard let date = DayFormat.date(from: day) else { return day }
        return day == store.yesterday ? String(localized: "Yesterday") : Fmt.dayTitle(date, today: .now)
    }

    /// The days the strip offers: yesterday back 14 days, newest first.
    var stripDays: [String] {
        (1...Self.daysBack).compactMap { offset in
            DayFormat.date(from: store.yesterday).map { DayFormat.string(from: DayFormat.shift($0, days: -(offset - 1))) }
        }
    }

    var readOnlyReason: String? {
        editable ? nil : String(localized: "This day can't be changed any more.",
                                comment: "Journal sheet: the selected day is too far back to answer or change (lock glyph).")
    }

    /// The rows, or what stands in their place. `isOnline` is the iPhone's connection (`ConnectivityMonitor`).
    func phase(isOnline: Bool) -> Phase {
        if hasDay { return groups.isEmpty ? .noHabits : .ready }
        if !isOnline { return .offline }
        if isLoading { return .loading }
        return loadFailed ? .failed : .loading
    }

    func select(_ day: String) async {
        self.day = day
        saved = false
        error = nil
        errorDetails = nil
        rebuild()
        await loadDay()
    }

    func load() async {
        if store.behaviors.isEmpty { await store.load() }
        await loadDay()
    }

    /// The selected day from the platform (the cache first). A newer `select` while it's on its way owns the state after it.
    private func loadDay() async {
        let asked = day
        isLoading = true
        loadFailed = false
        let found = await store.loadDay(asked)
        guard asked == day else { return }
        isLoading = false
        loadFailed = found == nil
        rebuild()
    }

    /// Enabled behaviors (plus any the saved day answered), grouped by category
    /// in first-seen order, rows in the platform's order; values from the day.
    private func rebuild() {
        let journal = store.cachedDay(day)
        hasDay = journal != nil
        editable = journal?.editable ?? Self.isEditable(day, yesterday: store.yesterday)
        let answered = Set(journal?.entries.map(\.behaviorId) ?? [])
        let shown = store.behaviors.filter { $0.enabled || answered.contains($0.id) }
        var out: [Group] = []
        for b in shown {
            let e = journal?.entries.first { $0.behaviorId == b.id }
            let row = Row(behavior: b, on: e?.valueBool ?? false, count: e?.valueNum ?? 1,
                          time: e?.valueTime ?? Self.defaultTime)
            if let i = out.firstIndex(where: { $0.category == b.category }) {
                out[i].rows.append(row)
            } else {
                out.append(Group(category: b.category, rows: [row]))
            }
        }
        groups = out
    }

    static func isEditable(_ day: String, yesterday: String) -> Bool {
        guard let d = DayFormat.date(from: day), let y = DayFormat.date(from: yesterday) else { return false }
        return d <= DayFormat.shift(y, days: 1) && d >= DayFormat.shift(y, days: -(daysBack - 1))
    }

    // MARK: editing

    func set(_ id: UUID, on: Bool) { update(id) { $0.on = on; if on, $0.count < 1 { $0.count = 1 } } }
    func set(_ id: UUID, count: Int) { update(id) { $0.count = max(1, count) } }
    func set(_ id: UUID, time: String) { update(id) { $0.time = time } }

    private func update(_ id: UUID, _ change: (inout Row) -> Void) {
        guard editable else { return }
        for g in groups.indices {
            if let r = groups[g].rows.firstIndex(where: { $0.id == id }) { change(&groups[g].rows[r]) }
        }
        saved = false
    }

    /// Every row shown, in order.
    var put: JournalPut { JournalPut(entries: groups.flatMap(\.rows).map(\.entry)) }

    func save() async {
        guard editable else { return }
        isSaving = true
        error = nil
        errorDetails = nil
        defer { isSaving = false }
        do {
            try await store.save(day: day, entries: put.entries)
            saved = true
            rebuild()
        } catch where error.isCancellation {
            return
        } catch {
            self.error = Self.message(for: error, rows: groups.flatMap(\.rows))
            errorDetails = error.diagnosticDetails
        }
    }

    /// A `422` names what was wrong; the platform's text mentions the behavior.
    static func message(for error: Error, rows: [Row]) -> String {
        guard let api = error as? APIError, api.status == 422, case .http(_, let text, _, _, _) = api else {
            return error.localizedDescription
        }
        if let row = rows.first(where: { text.localizedCaseInsensitiveContains($0.behavior.slug)
                                         || text.localizedCaseInsensitiveContains($0.id.uuidString) }) {
            return String(localized: "\(row.behavior.name) couldn't be saved: \(text)")
        }
        return text.isEmpty ? String(localized: "This day can't be saved.") : text
    }

    static func title(_ category: BehaviorCategory) -> String {
        switch category {
        case .substances: return String(localized: "Substances")
        case .sleep: return String(localized: "Sleep")
        case .recovery: return String(localized: "Recovery")
        case .supplements: return String(localized: "Supplements")
        case .health: return String(localized: "Health")
        case .lifestyle: return String(localized: "Lifestyle")
        case .custom: return String(localized: "Your own")
        }
    }
}
