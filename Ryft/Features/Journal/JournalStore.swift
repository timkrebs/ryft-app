import Foundation
import Observation

/// The journal (API.md → Journal), shared by Today's card and sheet, Profile →
/// Journal and Insights → Behaviors.
///
/// - **Not live yet:** a `404` on `GET /v1/behaviors` means the platform hasn't
///   deployed M5: everything hides, nothing shows an error.
/// - **Offline-first reads:** the catalog, each day and the last impacts are
///   kept in SwiftData (`CachedDocument` "journal.*").
/// - **Writes need the network**; offline they fail with `JournalError.offline`
///   and the screens show the Offline pill.
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
            case .idTaken: return String(localized: "That behavior couldn't be saved. Try again.")
            }
        }
    }

    private let env: AppEnvironment

    private(set) var availability: Availability = .unknown
    private(set) var behaviors: [Behavior] = []
    private(set) var days: [String: JournalDay] = [:]
    private(set) var impacts: BehaviorImpacts?
    private(set) var error: String?

    static let behaviorsKey = "journal.behaviors"
    static let impactKey = "journal.impact"
    static func dayKey(_ day: String) -> String { "journal.day.\(day)" }

    init(env: AppEnvironment) {
        self.env = env
        behaviors = env.persistence.document([Behavior].self, key: Self.behaviorsKey) ?? []
        impacts = env.persistence.document(BehaviorImpacts.self, key: Self.impactKey)
        if !behaviors.isEmpty { availability = .live }
    }

    var isLive: Bool { availability == .live }
    private var isOnline: Bool { env.connectivity.isOnline }
    private var now: Date { env.clock.now() }

    var yesterday: String { DayFormat.string(from: DayFormat.shift(now, days: -1)) }

    /// On the sheet, in the platform's order (category, then `sort`).
    var enabledBehaviors: [Behavior] { behaviors.filter(\.enabled) }

    func behavior(_ id: UUID) -> Behavior? { behaviors.first { $0.id == id } }

    /// A day as known now: in memory, else the SwiftData cache (no request).
    func cachedDay(_ day: String) -> JournalDay? {
        if let known = days[day] { return known }
        let cached = env.persistence.document(JournalDay.self, key: Self.dayKey(day))
        if let cached { days[day] = cached }
        return cached
    }

    // MARK: reads

    /// The catalog (and with it, whether the journal is live).
    func load() async {
        guard env.isDemo || env.auth.isSignedIn else { return }
        do {
            let list = try await env.api.behaviors()
            replace(list)
            availability = .live
            error = nil
        } catch where error.isEndpointMissing {
            availability = .notLive
        } catch {
            // Offline or a failure: the cache (and whether it was live) stays.
        }
    }

    /// One day: the cache first, then the platform's.
    @discardableResult
    func loadDay(_ day: String) async -> JournalDay? {
        if days[day] == nil, let cached = env.persistence.document(JournalDay.self, key: Self.dayKey(day)) {
            days[day] = cached
        }
        guard isLive, isOnline else { return days[day] }
        do {
            let fresh = try await env.api.journal(day: day)
            store(fresh)
        } catch where error.isEndpointMissing {
            availability = .notLive
        } catch {}
        return days[day]
    }

    func loadImpacts() async {
        guard isLive, isOnline else { return }
        do {
            let fresh = try await env.api.behaviorImpact()
            impacts = fresh
            env.persistence.saveDocument(fresh, key: Self.impactKey, at: now)
        } catch where error.isEndpointMissing {
            availability = .notLive
        } catch {}
    }

    // MARK: writes

    /// `PUT /v1/journal/{day}` with every row the sheet showed. After saving
    /// yesterday, the impacts are refreshed in the background.
    func save(day: String, entries: [JournalEntry]) async throws {
        guard isOnline else { throw JournalError.offline }
        let saved = try await env.api.putJournal(day: day, JournalPut(entries: entries))
        store(saved)
        if day == yesterday { Task { await loadImpacts() } }
    }

    /// `PATCH /v1/behaviors {enabled: {id: on}}`; the whole list comes back.
    func setEnabled(_ id: UUID, _ on: Bool) async throws {
        guard isOnline else { throw JournalError.offline }
        replace(try await env.api.patchBehaviors(BehaviorsPatch([id: on])))
    }

    /// `POST /v1/behaviors` with an app id; `409` once means the id is taken, so a
    /// new one is tried, once.
    @discardableResult
    func create(name: String, nameDe: String?, kind: BehaviorKind, category: BehaviorCategory?,
                id: UUID = UUID(), retryID: UUID = UUID()) async throws -> Behavior {
        guard isOnline else { throw JournalError.offline }
        let german = nameDe?.trimmingCharacters(in: .whitespaces)
        func input(_ id: UUID) -> BehaviorInput {
            BehaviorInput(id: id, name: name.trimmingCharacters(in: .whitespaces),
                          nameDe: german?.isEmpty == false ? german : nil, kind: kind, category: category)
        }
        let created: Behavior
        do {
            created = try await env.api.createBehavior(input(id))
        } catch let e as APIError where e.status == 409 {
            do {
                created = try await env.api.createBehavior(input(retryID))
            } catch let again as APIError where again.status == 409 {
                throw JournalError.idTaken
            }
        }
        replace(behaviors.filter { $0.id != created.id } + [created])
        return created
    }

    /// `DELETE /v1/behaviors/{id}`, custom behaviors only (built-ins answer `403`).
    func delete(_ id: UUID) async throws {
        guard behavior(id)?.isCustom == true else { return }
        guard isOnline else { throw JournalError.offline }
        try await env.api.deleteBehavior(id: id)
        replace(behaviors.filter { $0.id != id })
    }

    // MARK: cache

    private func replace(_ list: [Behavior]) {
        behaviors = list
        env.persistence.saveDocument(list, key: Self.behaviorsKey, at: now)
    }

    private func store(_ day: JournalDay) {
        days[day.day] = day
        env.persistence.saveDocument(day, key: Self.dayKey(day.day), at: now)
    }

    // MARK: Today's card

    /// "Alcohol · 2, Sauna, Last caffeine 16:30" for an answered day; nil otherwise.
    func summary(of day: JournalDay) -> String? {
        guard day.answered else { return nil }
        let yes = day.entries.filter(\.valueBool).compactMap { e -> String? in
            guard let b = behavior(e.behaviorId) else { return nil }
            switch b.kind {
            case .yesNo: return b.name
            case .count: return e.valueNum.map { "\(b.name) · \($0)" } ?? b.name
            case .time: return e.valueTime.map { "\(b.name) \($0)" } ?? b.name
            }
        }
        return yes.isEmpty ? String(localized: "None of your behaviors") : yes.formatted(.list(type: .and, width: .narrow))
    }
}
