import Foundation
import Observation

/// What the screens read: the platform's flags (`GET /v1/config`, evaluated per
/// user) over the compiled defaults, with Debug overrides on top. The last
/// config is cached in SwiftData (`CachedDocument` "config"), so a launch
/// offline keeps the flags it had; sign-out wipes it with the other read models.
/// Observable, so a flag that changes remotely updates the UI without a rebuild.
@MainActor
@Observable
final class FlagStore: FeatureFlagProvider {
    static let shared = FlagStore(store: .shared, defaults: .standard)

    static let cacheKey = "config"
    static let overridesKey = "flags.overrides"
    /// Until the platform said otherwise (API.md: `ttl_sec` 21600).
    static let defaultTTL: TimeInterval = 6 * 3600

    /// The cached document: the config and when this phone fetched it.
    struct Cached: Codable {
        let config: RemoteConfig
        let fetchedAt: Date
    }

    private let store: TrainStore
    private let defaults: UserDefaults

    private(set) var remote: [String: Bool] = [:]
    private(set) var evaluatedAt: Date?
    private(set) var fetchedAt: Date?
    private(set) var ttl: TimeInterval = FlagStore.defaultTTL
    private(set) var overrides: [FeatureFlag: Bool] = [:]

    init(store: TrainStore, defaults: UserDefaults) {
        self.store = store
        self.defaults = defaults
        if let cached = store.document(Cached.self, key: Self.cacheKey) { show(cached) }
        #if DEBUG
        let saved = defaults.dictionary(forKey: Self.overridesKey) as? [String: Bool] ?? [:]
        overrides = Dictionary(uniqueKeysWithValues: saved.compactMap { k, v in FeatureFlag(rawValue: k).map { ($0, v) } })
        #endif
    }

    // MARK: FeatureFlagProvider

    func isOn(_ flag: FeatureFlag) -> Bool {
        overrides[flag] ?? remote[flag.rawValue] ?? flag.compiledDefault
    }

    func source(of flag: FeatureFlag) -> FlagSource {
        if overrides[flag] != nil { return .override }
        return remote[flag.rawValue] != nil ? .remote : .compiled
    }

    // MARK: remote

    /// Due again once `ttl_sec` has passed since the last fetch (or never fetched).
    func isStale(at now: Date) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= ttl
    }

    func apply(_ config: RemoteConfig, fetchedAt: Date) {
        let cached = Cached(config: config, fetchedAt: fetchedAt)
        show(cached)
        store.saveDocument(cached, key: Self.cacheKey, at: fetchedAt)
    }

    /// Sign-out or another account: back to the compiled defaults (overrides stay).
    func reset() {
        remote = [:]
        evaluatedAt = nil
        fetchedAt = nil
        ttl = Self.defaultTTL
        store.removeDocument(key: Self.cacheKey)
    }

    private func show(_ cached: Cached) {
        remote = cached.config.flags
        evaluatedAt = cached.config.evaluatedAt
        fetchedAt = cached.fetchedAt
        ttl = cached.config.ttlSec > 0 ? TimeInterval(cached.config.ttlSec) : Self.defaultTTL
    }

    // MARK: overrides (Debug builds only; Release ignores them)

    func setOverride(_ flag: FeatureFlag, _ value: Bool?) {
        #if DEBUG
        overrides[flag] = value
        defaults.set(Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) }),
                     forKey: Self.overridesKey)
        #endif
    }

    func clearOverrides() {
        #if DEBUG
        overrides = [:]
        defaults.removeObject(forKey: Self.overridesKey)
        #endif
    }
}

/// Fetches the config into a `FlagStore`: at launch, then again whenever its
/// `ttl_sec` has passed (6 h), and on return to the app if it's due. One request
/// at a time; a refresh while one runs waits for it instead of starting another.
actor FeatureFlags {
    typealias Fetch = @Sendable @MainActor () async throws -> RemoteConfig

    private let flags: FlagStore
    private let clock: AppClock
    private let fetch: Fetch
    private var inFlight: Task<Bool, Never>?

    init(flags: FlagStore, clock: AppClock, fetch: @escaping Fetch) {
        self.flags = flags
        self.clock = clock
        self.fetch = fetch
    }

    /// `true` when a new config was applied. Not due and not forced: no request.
    /// A failure keeps what's cached (or the compiled defaults).
    @discardableResult
    func refresh(force: Bool = false) async -> Bool {
        if let inFlight { return await inFlight.value }
        let task = Task { [flags, clock, fetch] in
            let due = await flags.isStale(at: clock.now())
            guard force || due else { return false }
            do {
                let config = try await fetch()
                await flags.apply(config, fetchedAt: clock.now())
                return true
            } catch {
                return false
            }
        }
        inFlight = task
        let applied = await task.value
        inFlight = nil
        return applied
    }

    /// While the app runs (RyftApp `.task`): fetch now, then each time the config is due.
    func run() async {
        await refresh(force: true)
        while !Task.isCancelled {
            let ttl = await flags.ttl
            do {
                try await clock.sleep(for: .seconds(ttl))
            } catch {
                return
            }
            await refresh()
        }
    }
}
