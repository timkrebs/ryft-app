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

    /// What the sheet asks before it drops answers that aren't saved (PR 6 B §1.2: a sheet that discards confirms first).
    enum Discard: Equatable, Sendable {
        /// Closing the sheet.
        case close
        /// Switching to that day.
        case day(String)
    }

    /// Sends one day's answers (`PUT /v1/journal/{day}`); tests hold it open.
    typealias Saver = @MainActor (_ day: String, _ entries: [JournalEntry]) async throws -> Void

    /// Profile → Journal's page opens on it (the no-habits link).
    let store: JournalStore
    private let saver: Saver
    /// Whose rows these are: the account and side the sheet opened on, before anything was forgotten since.
    private let opened: JournalStore.Owner
    /// Up to 14 days back (`editable`); the sheet opens on yesterday.
    private(set) var day: String
    private(set) var groups: [Group] = []
    private(set) var editable = true
    private(set) var isSaving = false
    private(set) var error: String?
    /// The failed save's status and request ID, for the message's Details (API.md → Errors).
    private(set) var errorDetails: String?
    private(set) var saved = false
    /// Save found the sheet on another account or side than it opened on (a sign-out, another account, the Demo data
    /// switch): nothing was sent, and the sheet closes without a word, as a save whose account went ends.
    private(set) var leftItsSide = false
    /// The day is on this phone (in memory or the SwiftData cache): its rows say what it holds.
    private(set) var hasDay = false
    /// A read of the day is on its way.
    private(set) var isLoading = false
    /// The last read of the day brought nothing back (offline is the caller's to tell apart: `phase(isOnline:)`).
    private(set) var loadFailed = false
    /// Answers changed since the rows were last built from the day or saved: closing or switching days asks first.
    private(set) var isDirty = false
    /// What waits for "Discard" or "Keep editing".
    private(set) var pendingDiscard: Discard?
    /// Every change of a row counts here: a read that answers after one doesn't rebuild over it.
    private var edits = 0
    /// The shown error is "You're offline…": it goes once the iPhone is back online.
    private var errorIsOffline = false

    static let defaultTime = "18:00"
    static let daysBack = 14

    init(store: JournalStore, day: String? = nil, saver: Saver? = nil) {
        self.store = store
        self.saver = saver ?? { [store] day, entries in try await store.save(day: day, entries: entries) }
        opened = store.owner
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

    /// Whether Save can go (the Offline pill when not): demo data answers on the phone, so it's never offline there.
    var isOnline: Bool { store.isOnline }
    /// Answers given offline wait on this iPhone (`JournalStore.keepsOfflineAnswers`): the Offline pill's words.
    var keepsOfflineAnswers: Bool { store.keepsOfflineAnswers }

    var readOnlyReason: String? {
        editable ? nil : String(localized: "This day can't be changed any more.",
                                comment: "Journal sheet: the selected day is too far back to answer or change (lock glyph).")
    }

    /// The rows, or what stands in their place. `isOnline` is the sheet's word for the network (`isOnline`: demo data,
    /// answering on the phone, is never offline).
    func phase(isOnline: Bool) -> Phase {
        if hasDay { return groups.isEmpty ? .noHabits : .ready }
        if !isOnline { return .offline }
        if isLoading { return .loading }
        return loadFailed ? .failed : .loading
    }

    /// Shows `day`, dropping answers not saved (callers that keep them ask first: `requestSelect`). The selected day stays as
    /// it is, with its error.
    func select(_ day: String) async {
        guard day != self.day else { return }
        self.day = day
        saved = false
        clearError()
        rebuild()
        await loadDay()
    }

    /// The strip's tap: switches at once, or asks first while answers aren't saved.
    func requestSelect(_ day: String) async {
        guard day != self.day else { return }
        if isDirty {
            pendingDiscard = .day(day)
            return
        }
        await select(day)
    }

    /// The close circle's tap: true when the sheet may close now; otherwise it asks first.
    func requestClose() -> Bool {
        guard isDirty else { return true }
        pendingDiscard = .close
        return false
    }

    /// "Discard": drops the answers and does what waited. True when the sheet should close.
    func discard(_ pending: Discard) async -> Bool {
        pendingDiscard = nil
        switch pending {
        case .close:
            return true
        case .day(let day):
            await select(day)
            return false
        }
    }

    /// "Keep editing".
    func cancelDiscard() {
        pendingDiscard = nil
    }

    func load() async {
        await load(userInitiated: false)
    }

    /// Try again (offline, or a read that failed): the user asked, so the read goes even while the read pipeline holds the
    /// journal's reads back after a failure (`ReadScheduler.run(userInitiated:)`), as every Try again does.
    func retry() async {
        await load(userInitiated: true)
    }

    private func load(userInitiated: Bool) async {
        if store.behaviors.isEmpty { await store.load(userInitiated: userInitiated) }
        await loadDay(userInitiated: userInitiated)
    }

    /// Back from Profile → Journal: the habits chosen there at once, then the day from the platform.
    func habitsChanged() async {
        if !isDirty { rebuild() }
        await load()
    }

    /// The iPhone's connection changed: back online, "You're offline…" no longer holds.
    func connectionChanged(online: Bool) {
        if online, errorIsOffline { clearError() }
    }

    /// The selected day from the platform (the cache first). A newer `select` while it's on its way owns the state after it,
    /// and an answer given while it was on its way stays: the rows aren't rebuilt over it.
    private func loadDay(userInitiated: Bool = false) async {
        let asked = day
        let editsBefore = edits
        isLoading = true
        loadFailed = false
        let found = await store.loadDay(asked, userInitiated: userInitiated)
        guard asked == day else { return }
        isLoading = false
        loadFailed = found == nil
        if edits == editsBefore { rebuild() }
    }

    private func clearError() {
        error = nil
        errorDetails = nil
        errorIsOffline = false
    }

    /// Enabled behaviors (plus any the saved day answered), grouped by category
    /// in first-seen order, rows in the platform's order; values from the day.
    private func rebuild() {
        let journal = store.cachedDay(day)
        hasDay = journal != nil
        isDirty = false
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

    /// Nothing changes on a read-only day or while a save is out (the sheet doesn't take taps then either).
    private func update(_ id: UUID, _ change: (inout Row) -> Void) {
        guard editable, !isSaving else { return }
        for g in groups.indices {
            if let r = groups[g].rows.firstIndex(where: { $0.id == id }) { change(&groups[g].rows[r]) }
        }
        edits += 1
        isDirty = true
        saved = false
    }

    /// Every row shown, in order.
    var put: JournalPut { JournalPut(entries: groups.flatMap(\.rows).map(\.entry)) }

    /// Sends the day's rows. Only a day that is on this iPhone (an unread one would answer "no" to everything), once at a time;
    /// if the selected day changed while it was out, its outcome isn't shown on the new day. True when the day it was asked
    /// for is saved and still selected: the sheet closes.
    @discardableResult
    func save() async -> Bool {
        guard editable, hasDay, !isSaving else { return false }
        // The rows are another account's (or side's) answers: never sent as this one's.
        guard store.owns(opened) else {
            leftItsSide = true
            return false
        }
        let asked = day
        let entries = put.entries
        isSaving = true
        clearError()
        defer { isSaving = false }
        do {
            try await saver(asked, entries)
            guard asked == day else { return false }
            saved = true
            rebuild()
            return true
        } catch where error.isCancellation {
            // The answer came for an account or side that's gone (`JournalStore.save`): the sheet closes quietly too.
            if !store.owns(opened) { leftItsSide = true }
            return false
        } catch {
            guard asked == day else { return false }
            self.error = Self.message(for: error)
            errorDetails = error.diagnosticDetails
            errorIsOffline = (error as? JournalStore.JournalError) == .offline
            return false
        }
    }

    /// The platform turning the answers down (a `4xx` other than the session, a gate or too many requests) reads as the app's
    /// sentence, never the platform's text (it names behaviors and ids); the status and request ID go to Details.
    static func message(for error: Error) -> String {
        if let api = error as? APIError, let status = api.status, (400..<500).contains(status), ![401, 403, 429].contains(status) {
            return String(localized: "RYFT didn't accept that, so nothing changed.",
                          comment: "A change the platform turned down (422): nothing was saved. Details holds the request ID.")
        }
        return error.localizedDescription
    }

    /// A failed read's status and request ID for Details ("HTTP 503 · Request ID …"), from the read pipeline's record of the
    /// journal (`ReadScheduler.states[.journal]`); nil without a failure or a status.
    static func readDetails(_ state: ResourceState?) -> String? {
        guard let state, state.consecutiveFailures > 0, let error = state.lastError, let status = error.status else { return nil }
        let head = error.code.map { "HTTP \(status) · \($0)" } ?? "HTTP \(status)"
        guard let id = error.requestID else { return head }
        return String(localized: "\(head) · Request ID \(id)")
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
