import Foundation
import Observation
import Testing
@testable import Ryft

@MainActor
final class ConfigServer {
    var flags: [String: Bool] = [:]
    var ttl = 21_600
    var failure: Error?
    var requests = 0
    /// Holds each request until `release()` (to overlap refreshes).
    var gate: CheckedContinuation<Void, Never>?
    var holds = false

    func fetch() async throws -> RemoteConfig {
        requests += 1
        if holds { await withCheckedContinuation { gate = $0 } }
        if let failure { throw failure }
        return RemoteConfig(flags: flags, evaluatedAt: Date(timeIntervalSince1970: 1_792_400_000), ttlSec: ttl)
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

/// Set from `onChange`, which may run on any thread.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    var value: Bool { lock.withLock { on } }
    func set() { lock.withLock { on = true } }
}

@MainActor
struct FlagStoreTests {
    let store = TrainStore(inMemory: true)
    let defaults = UserDefaults(suiteName: "ryft.test.flags.\(UUID().uuidString)") ?? .standard
    private let config = RemoteConfig(flags: ["today.redesign": true, "train.enabled": false, "unknown.key": true],
                                      evaluatedAt: .now, ttlSec: 3600)

    @Test func compiledDefaultsUntilThePlatformAnswers() {
        let flags = FlagStore(store: store, defaults: defaults)
        for flag in FeatureFlag.allCases {
            #expect(flags.isOn(flag) == flag.compiledDefault)
            #expect(flags.source(of: flag) == .compiled)
        }
    }

    @Test func remoteValuesWinOverDefaults() {
        let flags = FlagStore(store: store, defaults: defaults)
        flags.apply(config, fetchedAt: .now)
        #expect(flags.isOn(.todayRedesign) && flags.source(of: .todayRedesign) == .remote)
        #expect(!flags.isOn(.trainEnabled))
        // Keys the platform didn't send keep the compiled default.
        #expect(flags.source(of: .pushEnabled) == .compiled)
        #expect(flags.ttl == 3600)
    }

    @Test func anOverrideWinsAndIsRemembered() {
        let flags = FlagStore(store: store, defaults: defaults)
        flags.apply(config, fetchedAt: .now)
        flags.setOverride(.todayRedesign, false)
        #expect(!flags.isOn(.todayRedesign) && flags.source(of: .todayRedesign) == .override)
        #expect(FlagStore(store: store, defaults: defaults).source(of: .todayRedesign) == .override)
        flags.setOverride(.todayRedesign, nil)
        #expect(flags.isOn(.todayRedesign) && flags.source(of: .todayRedesign) == .remote)
        flags.setOverride(.coachEnabled, true)
        flags.clearOverrides()
        #expect(flags.overrides.isEmpty && !flags.isOn(.coachEnabled))
    }

    /// `-RyftFlags devices.setup` is on for its launch only: toggling another flag saves the overrides without it, and
    /// the next launch without the argument has it off.
    @Test func aLaunchFlagIsNeverSaved() {
        defaults.set("devices.setup, nonsense", forKey: FlagStore.launchFlagsKey) // the argument domain, in a test
        let launched = FlagStore(store: store, defaults: defaults)
        #expect(launched.isOn(.devicesSetup) && launched.source(of: .devicesSetup) == .override)
        launched.setOverride(.syncGzip, true)
        #expect((defaults.dictionary(forKey: FlagStore.overridesKey) as? [String: Bool]) == ["sync.gzip": true])
        defaults.removeObject(forKey: FlagStore.launchFlagsKey)
        let next = FlagStore(store: store, defaults: defaults)
        #expect(!next.isOn(.devicesSetup) && next.source(of: .devicesSetup) == .compiled)
        #expect(next.isOn(.syncGzip))
    }

    @Test func theConfigIsCachedForTheNextLaunch() {
        FlagStore(store: store, defaults: defaults).apply(config, fetchedAt: .now)
        let relaunched = FlagStore(store: store, defaults: defaults)
        #expect(relaunched.isOn(.todayRedesign) && relaunched.source(of: .todayRedesign) == .remote)
        #expect(relaunched.fetchedAt != nil)
    }

    @Test func resetAndWipeForgetTheAccountsFlags() {
        let flags = FlagStore(store: store, defaults: defaults)
        flags.apply(config, fetchedAt: .now)
        flags.reset()
        #expect(flags.source(of: .todayRedesign) == .compiled && flags.fetchedAt == nil)
        #expect(FlagStore(store: store, defaults: defaults).source(of: .todayRedesign) == .compiled)

        flags.apply(config, fetchedAt: .now)
        store.wipe() // sign-out
        #expect(FlagStore(store: store, defaults: defaults).source(of: .todayRedesign) == .compiled)
    }

    @Test func staleOnceEvaluatedAtPlusTTLHasPassed() {
        let flags = FlagStore(store: store, defaults: defaults)
        let t0 = Date(timeIntervalSince1970: 1_792_400_000)
        #expect(flags.isStale(at: t0))
        // Fetched later than it was evaluated: the TTL still counts from evaluated_at.
        flags.apply(RemoteConfig(flags: [:], evaluatedAt: t0, ttlSec: 3600), fetchedAt: t0.addingTimeInterval(600))
        #expect(!flags.isStale(at: t0.addingTimeInterval(3599)))
        #expect(flags.isStale(at: t0.addingTimeInterval(3600)))
    }

    @Test func unknownKeysAreKeptButUnread() {
        let flags = FlagStore(store: store, defaults: defaults)
        flags.apply(config, fetchedAt: .now)
        #expect(flags.remote["unknown.key"] == true)
        #expect(FeatureFlag(rawValue: "unknown.key") == nil)
    }

    @Test func aFlipWaitsForTheNextScreenAppearance() {
        let flags = FlagStore(store: store, defaults: defaults)
        flags.apply(config, fetchedAt: .now) // first answer: nothing remote shown yet, applies now
        #expect(flags.isOn(.todayRedesign))
        flags.apply(RemoteConfig(flags: ["today.redesign": false], evaluatedAt: .now, ttlSec: 3600), fetchedAt: .now)
        #expect(flags.isOn(.todayRedesign)) // mid-interaction: unchanged
        flags.applyPending()
        #expect(!flags.isOn(.todayRedesign))
        // Cached already: a relaunch starts with the new answer.
        #expect(!FlagStore(store: store, defaults: defaults).isOn(.todayRedesign))
    }

    @Test func eachAccountHasItsOwnCacheForAnOfflineColdStart() {
        let a = FlagStore(store: store, defaults: defaults, account: "a")
        a.apply(config, fetchedAt: .now)
        // Cold start offline as "a": its flags; as "b": the compiled defaults.
        #expect(FlagStore(store: store, defaults: defaults, account: "a").isOn(.todayRedesign))
        let b = FlagStore(store: store, defaults: defaults, account: "b")
        #expect(b.source(of: .todayRedesign) == .compiled)
        // Switching accounts in place does the same.
        a.switchAccount("b")
        #expect(a.source(of: .todayRedesign) == .compiled)
        a.switchAccount("a")
        #expect(a.isOn(.todayRedesign) && a.source(of: .todayRedesign) == .remote)
    }

    @Test func fallbackOrderIsOverrideRemoteCompiled() {
        let flags = FlagStore(store: store, defaults: defaults)
        #expect(flags.isOn(.trainEnabled) && flags.source(of: .trainEnabled) == .compiled)
        flags.apply(config, fetchedAt: .now) // remote: train.enabled false
        #expect(!flags.isOn(.trainEnabled) && flags.source(of: .trainEnabled) == .remote)
        flags.setOverride(.trainEnabled, true)
        #expect(flags.isOn(.trainEnabled) && flags.source(of: .trainEnabled) == .override)
    }

    /// "Flags toggle without a rebuild": a view reading a flag is invalidated by a new config.
    @Test func aRemoteChangeNotifiesObservers() {
        let flags = FlagStore(store: store, defaults: defaults)
        let changed = Flag()
        withObservationTracking { _ = flags.isOn(.todayRedesign) } onChange: { changed.set() }
        flags.apply(config, fetchedAt: .now)
        #expect(changed.value)
    }
}

@MainActor
struct FeatureFlagsFetchTests {
    let clock = TestClock()
    let server = ConfigServer()
    let flags = FlagStore(store: TrainStore(inMemory: true),
                          defaults: UserDefaults(suiteName: "ryft.test.flags.\(UUID().uuidString)") ?? .standard)

    private func makeFetcher() -> FeatureFlags {
        FeatureFlags(flags: flags, clock: clock) { [server] in try await server.fetch() }
    }

    @Test func fetchesWhenDueAndNotBefore() async {
        server.flags = ["today.redesign": true]
        let fetcher = makeFetcher()
        #expect(await fetcher.refresh())
        #expect(flags.isOn(.todayRedesign))
        #expect(await !fetcher.refresh())
        #expect(server.requests == 1)

        clock.advance(by: .seconds(21_600))
        #expect(await fetcher.refresh())
        #expect(server.requests == 2)
    }

    @Test func forceAlwaysAsks() async {
        let fetcher = makeFetcher()
        await fetcher.refresh()
        await fetcher.refresh(force: true)
        #expect(server.requests == 2)
    }

    @Test func aFailureKeepsWhatWasCached() async {
        server.flags = ["today.redesign": true]
        let fetcher = makeFetcher()
        await fetcher.refresh()
        server.failure = APIError.http(503, "")
        #expect(await !fetcher.refresh(force: true))
        #expect(flags.isOn(.todayRedesign) && flags.source(of: .todayRedesign) == .remote)
    }

    @Test func overlappingRefreshesShareOneRequest() async {
        server.holds = true
        let fetcher = makeFetcher()
        let first = Task { await fetcher.refresh(force: true) }
        let second = Task { await fetcher.refresh(force: true) }
        #expect(await eventually { server.gate != nil })
        // Let the second caller reach the actor and join the first request.
        for _ in 0..<50 { await Task.yield() }
        server.release()
        let a = await first.value, b = await second.value
        #expect(a && b)
        #expect(server.requests == 1)
    }

    @Test func runFetchesAtLaunchThenEveryTTL() async {
        server.ttl = 600
        let fetcher = makeFetcher()
        let loop = Task { await fetcher.run() }
        #expect(await eventually { server.requests == 1 && clock.pendingSleeps == 1 })
        clock.advance(by: .seconds(600))
        #expect(await eventually { server.requests == 2 && clock.pendingSleeps == 1 })
        loop.cancel()
        #expect(await eventually { clock.pendingSleeps == 0 })
    }
}

@MainActor
struct FlagGateTests {
    private func state(_ flags: [FeatureFlag: Bool]) -> AppState {
        AppState(env: .test(flags: flags))
    }

    @Test func trainIsGatedOnTodayAndStrain() {
        let off = state([.trainEnabled: false])
        let on = state([:])
        let today = { (s: AppState) in
            TodayViewModel(state: s, sync: SyncService.ungated(env: s.env),
                           coordinator: SyncCoordinator(steps: LiveSyncSteps(state: s, sync: SyncService.ungated(env: s.env)),
                                                        clock: s.env.clock))
        }
        #expect(!today(off).showsTrain && today(on).showsTrain)
        #expect(!StrainViewModel(state: off, store: TrainStore(inMemory: true)).showsTrain)
        #expect(StrainViewModel(state: on, store: TrainStore(inMemory: true)).showsTrain)
    }

    @Test func theRedesignShipsDark() {
        let s = state([:])
        let model = TodayViewModel(state: s, sync: SyncService.ungated(env: s.env),
                                   coordinator: SyncCoordinator(steps: LiveSyncSteps(state: s, sync: SyncService.ungated(env: s.env)),
                                                                clock: s.env.clock))
        #expect(!model.showsRedesign)
        let lit = state([.todayRedesign: true])
        lit.user = MockData.user
        let litModel = TodayViewModel(state: lit, sync: SyncService.ungated(env: lit.env),
                                      coordinator: SyncCoordinator(steps: LiveSyncSteps(state: lit, sync: SyncService.ungated(env: lit.env)),
                                                                   clock: lit.env.clock))
        #expect(litModel.showsRedesign)
    }

    @Test func notificationSettingsExplainTheRolloutWithoutThePushFlag() {
        let off = state([:])
        #expect(!NotificationSettingsViewModel(state: off, push: PushRegistrar(env: off.env)).isRolledOut)
        let on = state([.pushEnabled: true])
        #expect(NotificationSettingsViewModel(state: on, push: PushRegistrar(env: on.env)).isRolledOut)
    }

    @Test func notificationsRowShowsWhenSignedIn() {
        let s = state([:])
        let sync = SyncService.ungated(env: s.env)
        let coordinator = SyncCoordinator(steps: LiveSyncSteps(state: s, sync: sync), clock: s.env.clock)
        #expect(ProfileViewModel(state: s, sync: sync, coordinator: coordinator).showsNotifications)
    }

}
