import Foundation
import Observation

/// The journal (API.md → Journal), shared by Today's card and sheet, Profile →
/// Journal and Insights → Behaviors.
///
/// - **Not live yet:** a `404` on `GET /v1/behaviors` means the platform hasn't
///   deployed M5: everything hides, nothing shows an error.
/// - **Offline-first reads:** the account's catalog, each day and the last impacts are kept in SwiftData
///   (`CachedDocument` "journal.*"). Demo data's journal lives in memory only: it never reads the account's documents and
///   never writes any (`AppEnvironment.accountDocuments`), so neither side shows the other's habits, answers or effects.
/// - **Writes need the network**; offline they fail with `JournalError.offline`
///   and the screens show the Offline pill. A habit's change waits as every settings write does (`SettingsWrite`: one
///   attempt, an answer within 25 s or none, none at once when the network goes); after no answer or a `5xx` the list is
///   asked again (`rereading`).
/// - **The account's**: every read and write is bound to the account and side it began on (`AccountBinding` and
///   `generation`); another account, a sign-out or the Demo data switch forgets what's shown (`accountChanged()`, run with
///   the other account-state forgetters), and an answer for the previous one is dropped, in memory and on disk. Back on
///   the account (Demo data off, or the next account's first load), its own documents come back from its store.
@MainActor
@Observable
final class JournalStore {
    enum Availability: Equatable { case unknown, live, notLive }

    enum JournalError: LocalizedError, Equatable {
        case offline
        /// `409` twice: the generated id was taken even after a new one.
        case idTaken
        var errorDescription: String? {
            switch self {
            case .offline: return String(localized: "You're offline. Save again when you're back online.")
            case .idTaken:
                return String(localized: "That habit couldn't be saved. Try again.",
                              comment: "Add a habit: the platform took the habit's id twice (409), so it wasn't created.")
            }
        }
    }

    private let env: AppEnvironment

    private(set) var availability: Availability = .unknown
    private(set) var behaviors: [Behavior] = []
    private(set) var days: [String: JournalDay] = [:]
    private(set) var impacts: BehaviorImpacts?
    private(set) var error: String?

    /// Writes to the catalog that completed (`PATCH`, `POST`, `DELETE /v1/behaviors`), never reset. A list asked for
    /// before the latest of them may be from before it: `load()` drops it (the page's opening `GET` can't undo a switch),
    /// and a `PATCH` answered after another write brings only its own switch (its list may still hold a habit deleted
    /// meanwhile). A count, not a time: two writes in one tick of the clock still differ. Kept small on purpose: the
    /// durable outbox (O6) takes these writes over.
    private var completedWrites = 0
    #if DEBUG
    /// Tests only: runs once a catalog answer arrived (`"behaviors"`, `"patchBehaviors"`), before it's applied, so a test
    /// can finish another write meanwhile.
    @ObservationIgnored var beforeApplying: (@MainActor (String) async -> Void)?
    #endif
    /// Bumped when the account's state is forgotten (`accountChanged()`): an answer asked for before it is dropped.
    private var generation = 0
    /// The list asked for again after a write that may have saved (no answer, a `5xx`); tests await it.
    private(set) var rereading: Task<Void, Never>?
    /// The side changed since the account's documents were read (`accountChanged()`): the account's next `load()` reads
    /// them again first (`restore()`). Demo data has none to read.
    @ObservationIgnored private var restores = false

    static let behaviorsKey = "journal.behaviors"
    static let impactKey = "journal.impact"
    static func dayKey(_ day: String) -> String { "journal.day.\(day)" }

    init(env: AppEnvironment) {
        self.env = env
        if let disk = env.accountDocuments {
            behaviors = disk.document([Behavior].self, key: Self.behaviorsKey) ?? []
            impacts = disk.document(BehaviorImpacts.self, key: Self.impactKey)
        } else {
            // Launched in demo data: the account's documents are read when it's back (`restore()`).
            restores = true
        }
        if !behaviors.isEmpty { availability = .live }
    }

    /// The app's journal: it forgets the account's state with the others (`AppState.forgetsAccountState`: a sign-out,
    /// another account, a wipe, the Demo data switch).
    convenience init(state: AppState) {
        self.init(env: state.env)
        state.forgetsAccountState { [weak self] in self?.accountChanged() }
    }

    /// The previous account's journal goes: its habits (custom names too), its days and its effects, and whether it was
    /// live. An answer for it that arrives later changes nothing, here or in the store on disk. The next account's comes
    /// with its own `load()`.
    func accountChanged() {
        generation += 1
        rereading?.cancel()
        rereading = nil
        behaviors = []
        days = [:]
        impacts = nil
        error = nil
        availability = .unknown
        // Not read here: a sign-out's wipe may not have run yet. The next account's first load reads its own.
        restores = true
    }

    /// Back on the account: its catalog and effects as kept on this iPhone, before its `GET` answers (offline-first). After a
    /// sign-out's wipe they're gone, so another account finds nothing of the previous one's. Demo data reads nothing.
    private func restore() {
        guard restores, let disk = env.accountDocuments else { return }
        restores = false
        behaviors = disk.document([Behavior].self, key: Self.behaviorsKey) ?? []
        impacts = disk.document(BehaviorImpacts.self, key: Self.impactKey)
        if !behaviors.isEmpty { availability = .live }
    }

    #if DEBUG
    /// Previews and tests: what a demo data graph's journal holds before its load answers (it lives in memory only, so
    /// nothing kept on disk shows there).
    func seedForPreview(behaviors list: [Behavior], days seeded: [JournalDay] = []) {
        behaviors = list
        for day in seeded { days[day.day] = day }
        if !list.isEmpty { availability = .live }
    }
    #endif

    /// Whose a read or write is (or the journal sheet, from when it opened): the account and side then, and no forgetting
    /// since.
    struct Owner: Equatable {
        fileprivate let binding: AccountBinding
        fileprivate let generation: Int
    }

    var owner: Owner { Owner(binding: AccountBinding(env), generation: generation) }
    func owns(_ owner: Owner) -> Bool { owner == self.owner }

    var isLive: Bool { availability == .live }
    /// Whether a write can go and a day is asked for: demo data answers on the phone, with no network to lose (as
    /// Notifications, the editors and the planners). The journal sheet's Offline pill says it.
    var isOnline: Bool { env.isDemo || env.connectivity.isOnline }
    private var now: Date { env.clock.now() }

    var yesterday: String { DayFormat.string(from: DayFormat.shift(now, days: -1)) }

    /// On the sheet, in the platform's order (category, then `sort`).
    var enabledBehaviors: [Behavior] { behaviors.filter(\.enabled) }

    func behavior(_ id: UUID) -> Behavior? { behaviors.first { $0.id == id } }

    /// A day as known now: in memory, else the SwiftData cache (no request).
    func cachedDay(_ day: String) -> JournalDay? {
        if let known = days[day] { return known }
        let cached = env.accountDocuments?.document(JournalDay.self, key: Self.dayKey(day))
        if let cached { days[day] = cached }
        return cached
    }

    // MARK: reads

    /// A journal read through the read pipeline (`ReadKey(.journal)`): coalesced, retried and
    /// recorded with the other reads. `nil` inside means "not deployed" (a `404`, which isn't a
    /// failure); `nil` outside means nothing was sent (offline).
    private func read<T: Sendable>(_ id: String, _ fetch: @escaping @MainActor () async throws -> T) async throws -> T?? {
        try await env.reads.run(ReadKey(.journal, id: id)) { () async throws -> T? in
            do {
                return try await fetch()
            } catch where error.isEndpointMissing {
                return nil
            }
        }
    }

    /// The catalog (and with it, whether the journal is live).
    func load() async {
        guard env.isDemo || env.auth.isSignedIn else { return }
        restore()
        let api = env.api, owner = self.owner
        let asked = completedWrites
        do {
            switch try await read("behaviors", { try await api.behaviors() }) {
            case .some(.some(let list)):
                #if DEBUG
                await beforeApplying?("behaviors")
                #endif
                // Another account's (or the other side of the Demo data switch): not this one's to show or keep.
                guard owns(owner) else { return }
                // A write completed while it was on its way: the list may be from before it, and the page has newer.
                if completedWrites == asked { replace(list, as: owner) }
                availability = .live
                error = nil
            case .some(.none):
                guard owns(owner) else { return }
                availability = .notLive
            case .none:
                break // offline: the cache (and whether it was live) stays
            }
        } catch {
            // A failure: the cache (and whether it was live) stays.
        }
    }

    /// One day: the cache first, then the platform's.
    @discardableResult
    func loadDay(_ day: String) async -> JournalDay? {
        if days[day] == nil, let cached = env.accountDocuments?.document(JournalDay.self, key: Self.dayKey(day)) {
            days[day] = cached
        }
        guard isLive, isOnline else { return days[day] }
        let api = env.api, owner = self.owner
        let answer = try? await read("day.\(day)", { try await api.journal(day: day) })
        guard owns(owner) else { return nil }
        switch answer {
        case .some(.some(let fresh)): store(fresh, as: owner)
        case .some(.none): availability = .notLive
        case .none: break
        }
        return days[day]
    }

    func loadImpacts() async {
        guard isLive, isOnline else { return }
        let api = env.api, owner = self.owner
        let answer = try? await read("impact", { try await api.behaviorImpact() })
        guard owns(owner) else { return }
        switch answer {
        case .some(.some(let fresh)):
            impacts = fresh
            env.accountDocuments?.saveDocument(fresh, key: Self.impactKey, at: now)
        case .some(.none):
            availability = .notLive
        case .none:
            break
        }
    }

    // MARK: writes

    /// `PUT /v1/journal/{day}` with every row the sheet showed. After saving
    /// yesterday, the impacts are refreshed in the background.
    /// The answer for an account that's gone ends like a cancelled save: nothing is kept, nothing is said.
    func save(day: String, entries: [JournalEntry]) async throws {
        guard isOnline else { throw JournalError.offline }
        let api = env.api, owner = self.owner
        let saved = try await api.putJournal(day: day, JournalPut(entries: entries))
        guard owns(owner) else { throw CancellationError() }
        store(saved, as: owner)
        if day == yesterday { Task { await loadImpacts() } }
    }

    /// `PATCH /v1/behaviors {enabled: {id: on}}`; the whole list comes back. Answered after another write completed, only
    /// this habit's switch is taken from it (`completedWrites`). Answered for an account that's gone, it ends like a
    /// cancelled change.
    func setEnabled(_ id: UUID, _ on: Bool) async throws {
        guard isOnline else { throw JournalError.offline }
        let api = env.api, owner = self.owner
        let asked = completedWrites
        let list = try await write { try await api.patchBehaviors(BehaviorsPatch([id: on])) }
        #if DEBUG
        await beforeApplying?("patchBehaviors")
        #endif
        guard owns(owner) else { throw CancellationError() }
        if completedWrites == asked {
            replace(list, as: owner)
        } else if let answered = list.first(where: { $0.id == id }), let index = behaviors.firstIndex(where: { $0.id == id }) {
            var merged = behaviors
            merged[index].enabled = answered.enabled
            replace(merged, as: owner)
        }
        completedWrites += 1
    }

    /// `POST /v1/behaviors` with an app id; `409` once means the id is taken, so a
    /// new one is tried, once. The same `id` again updates the habit (`200`): a sheet sends its own each time it retries.
    @discardableResult
    func create(name: String, nameDe: String?, kind: BehaviorKind, category: BehaviorCategory?,
                id: UUID = UUID(), retryID: UUID = UUID()) async throws -> Behavior {
        guard isOnline else { throw JournalError.offline }
        let german = nameDe?.trimmingCharacters(in: .whitespaces)
        func input(_ id: UUID) -> BehaviorInput {
            BehaviorInput(id: id, name: name.trimmingCharacters(in: .whitespaces),
                          nameDe: german?.isEmpty == false ? german : nil, kind: kind, category: category)
        }
        let api = env.api, owner = self.owner, first = input(id), retry = input(retryID)
        // Both tries, within the one deadline: the sheet hears within 25 s either way.
        let created: Behavior = try await write {
            do {
                return try await api.createBehavior(first)
            } catch let e as APIError where e.isIDTaken {
                do {
                    return try await api.createBehavior(retry)
                } catch let again as APIError where again.isIDTaken {
                    throw JournalError.idTaken
                }
            }
        }
        guard owns(owner) else { throw CancellationError() }
        replace(behaviors.filter { $0.id != created.id } + [created], as: owner)
        completedWrites += 1
        return created
    }

    /// `DELETE /v1/behaviors/{id}`, custom behaviors only (built-ins answer `403`).
    func delete(_ id: UUID) async throws {
        guard behavior(id)?.isCustom == true else { return }
        guard isOnline else { throw JournalError.offline }
        let api = env.api, owner = self.owner
        try await write { try await api.deleteBehavior(id: id) }
        guard owns(owner) else { throw CancellationError() }
        replace(behaviors.filter { $0.id != id }, as: owner)
        completedWrites += 1
    }

    /// One habit write, as every settings write waits (`SettingsWrite`). When it may have saved (no answer, a `5xx`) the
    /// list is asked again, outside the write, so the page's switch is free meanwhile: it then shows what RYFT holds.
    private func write<T: Sendable>(_ send: @escaping @MainActor () async throws -> T) async throws -> T {
        let owner = self.owner
        do {
            return try await SettingsWrite.answer(in: env, send)
        } catch {
            if !error.isCancellation, JournalSettingsFailure.kind(of: error).rereads, owns(owner), isOnline {
                rereading = Task { await self.load() }
            }
            throw error
        }
    }

    // MARK: cache

    /// The list, in memory and (the account's) on disk, while it's still `owner`'s (checked again here: nothing of a previous
    /// account's is written into the next one's store, and demo data's never into the account's).
    private func replace(_ list: [Behavior], as owner: Owner) {
        guard owns(owner) else { return }
        behaviors = list
        env.accountDocuments?.saveDocument(list, key: Self.behaviorsKey, at: now)
    }

    private func store(_ day: JournalDay, as owner: Owner) {
        guard owns(owner) else { return }
        days[day.day] = day
        env.accountDocuments?.saveDocument(day, key: Self.dayKey(day.day), at: now)
    }

    // MARK: Today's card

    /// "Alcohol · 2, Sauna, Last caffeine 4:30 PM" for an answered day (a time as the locale writes it, `Fmt.time`); nil
    /// otherwise.
    func summary(of day: JournalDay, locale: Locale = .autoupdatingCurrent) -> String? {
        guard day.answered else { return nil }
        let yes = day.entries.filter(\.valueBool).compactMap { e -> String? in
            guard let b = behavior(e.behaviorId) else { return nil }
            switch b.kind {
            case .yesNo: return b.name
            case .count: return e.valueNum.map { "\(b.name) · \($0)" } ?? b.name
            case .time: return e.valueTime.map { "\(b.name) \(Self.time($0, now: now, locale: locale))" } ?? b.name
            }
        }
        return yes.isEmpty
            ? String(localized: "None of your habits",
                     comment: "Today's Journal card: yesterday is answered, and none of the habits happened.")
            : yes.formatted(.list(type: .and, width: .narrow).locale(locale))
    }

    /// A habit's "HH:MM" (the platform's 24-hour wall time) as the locale writes a time: "4:30 PM", "16:30".
    static func time(_ hhmm: String, now: Date, locale: Locale) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, let date = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now)
        else { return hhmm }
        return Fmt.time(date, locale: locale)
    }
}
