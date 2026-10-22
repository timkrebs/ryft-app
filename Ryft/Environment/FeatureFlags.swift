import Foundation
import Observation

/// What the screens read: the platform's flags (`GET /v1/config`, evaluated per
/// user) over the compiled defaults, with Debug overrides on top.
///
/// - **Per user.** The last answer is cached in SwiftData per account
///   (`CachedDocument` "config.<account>"), so a cold start offline uses that
///   account's flags, and another account on the phone never sees them.
///   Sign-out wipes the cache with the other read models. Demo data's flags
///   (the in-memory platform's) are cached as "config.demo", never as an account's.
/// - **Due** once `evaluated_at + ttl_sec` has passed.
/// - **Never mid-interaction.** A new answer is cached at once, but the screens
///   switch to it on the next appearance (`applyPending()`: a tab change, the
///   app becoming active). Only the very first answer for an account, with
///   nothing shown yet, applies straight away.
@MainActor
@Observable
final class FlagStore: FeatureFlagProvider {
    static let shared = FlagStore(store: .shared, defaults: .standard, account: AuthService.shared.accountID,
                                  demo: Settings.shared.demoMode)

    static let overridesKey = "flags.overrides"
    /// Debug launch argument: flags turned on for one launch.
    static let launchFlagsKey = "RyftFlags"
    /// Until the platform said otherwise (API.md: `ttl_sec` 21600).
    static let defaultTTL: TimeInterval = 6 * 3600

    static func cacheKey(_ account: String?) -> String { "config.\(account ?? "signed-out")" }

    /// The cached document: the config and when this phone fetched it.
    struct Cached: Codable {
        let config: RemoteConfig
        let fetchedAt: Date
    }

    private let store: TrainStore
    private let defaults: UserDefaults

    private(set) var account: String?
    /// Demo data: the flags shown and cached are demo's own.
    private(set) var demo = false
    /// Bumped by every account or demo switch: an answer asked for before it isn't applied after it.
    @ObservationIgnored private(set) var generation = 0
    private(set) var remote: [String: Bool] = [:]
    private(set) var evaluatedAt: Date?
    private(set) var fetchedAt: Date?
    private(set) var ttl: TimeInterval = FlagStore.defaultTTL
    private(set) var overrides: [FeatureFlag: Bool] = [:]
    /// Arrived while screens were showing; applied on the next appearance.
    @ObservationIgnored private(set) var pending: Cached?

    init(store: TrainStore, defaults: UserDefaults, account: String? = nil, demo: Bool = false) {
        self.store = store
        self.defaults = defaults
        self.account = account
        self.demo = demo
        if let cached = store.document(Cached.self, key: cacheKey) { show(cached) }
        #if DEBUG
        let saved = defaults.dictionary(forKey: Self.overridesKey) as? [String: Bool] ?? [:]
        overrides = Dictionary(uniqueKeysWithValues: saved.compactMap { k, v in FeatureFlag(rawValue: k).map { ($0, v) } })
        // `-RyftFlags devices.setup,sync.gzip`: these on for this launch (device tests), over the saved overrides.
        for name in (defaults.string(forKey: Self.launchFlagsKey) ?? "").split(separator: ",") {
            if let flag = FeatureFlag(rawValue: name.trimmingCharacters(in: .whitespaces)) { overrides[flag] = true }
        }
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

    /// Due once `evaluated_at + ttl_sec` has passed (or never answered). A
    /// pending answer counts: it's the newest the platform gave.
    func isStale(at now: Date) -> Bool {
        let latest = pending.map { ($0.config.evaluatedAt, Self.ttl(of: $0.config)) }
            ?? evaluatedAt.map { ($0, ttl) }
        guard let (evaluated, ttl) = latest else { return true }
        return now.timeIntervalSince(evaluated) >= ttl
    }

    /// The cache this account (or demo data) reads and writes.
    private var cacheKey: String { Self.cacheKey(demo ? "demo" : account) }

    /// Caches the answer; the screens get it now only if they show nothing remote yet. `generation`: when it
    /// was asked for; an answer from before an account or demo switch is dropped.
    func apply(_ config: RemoteConfig, fetchedAt: Date, generation: Int? = nil) {
        if let generation, generation != self.generation { return }
        let cached = Cached(config: config, fetchedAt: fetchedAt)
        store.saveDocument(cached, key: cacheKey, at: fetchedAt)
        if evaluatedAt == nil {
            show(cached)
            pending = nil
        } else {
            pending = cached
        }
    }

    /// A screen is appearing: switch to an answer that arrived meanwhile.
    func applyPending() {
        guard let pending else { return }
        self.pending = nil
        show(pending)
    }

    /// Sign-in, sign-out or another account: that account's cached flags, or the
    /// compiled defaults (overrides stay).
    func switchAccount(_ id: String?) {
        guard id != account else { return }
        account = id
        reload()
    }

    /// Demo data on or off: demo's own flags, or this account's cached ones again (never demo's).
    func setDemo(_ on: Bool) {
        guard on != demo else { return }
        demo = on
        reload()
    }

    /// Forgets the current account's flags (and its cache).
    func reset() {
        store.removeDocument(key: cacheKey)
        clear()
    }

    private func reload() {
        generation += 1
        clear()
        if let cached = store.document(Cached.self, key: cacheKey) { show(cached) }
    }

    private func clear() {
        remote = [:]
        evaluatedAt = nil
        fetchedAt = nil
        ttl = Self.defaultTTL
        pending = nil
    }

    private func show(_ cached: Cached) {
        remote = cached.config.flags
        evaluatedAt = cached.config.evaluatedAt
        fetchedAt = cached.fetchedAt
        ttl = Self.ttl(of: cached.config)
    }

    private static func ttl(of config: RemoteConfig) -> TimeInterval {
        config.ttlSec > 0 ? TimeInterval(config.ttlSec) : defaultTTL
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
            let generation = await flags.generation
            do {
                let config = try await fetch()
                await flags.apply(config, fetchedAt: clock.now(), generation: generation)
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
