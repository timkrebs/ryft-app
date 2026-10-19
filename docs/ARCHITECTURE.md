# RYFT iOS architecture

How the app is put together, following the technologies WHOOP's iOS team describes
(engineering.prod.whoop.com/ios-technologies), minus BLE and GPS. Each section names the
code that implements it.

## 1. Seams: every external dependency behind a protocol

Nothing reaches HealthKit, the network, Supabase, the store, the clock, notifications,
flags or the network path directly. Each sits behind a protocol with a live and a mock
implementation:

| Seam | Protocol | Live | Mock |
| --- | --- | --- | --- |
| HealthKit | `HealthStore` | `HealthKitManager` | `MockHealthStore` (scripted pages per stream) |
| Platform API | `PlatformAPI` (= `RyftDataSource` + `TrainDataSource` + sync, Apple code, config, push, notification prefs) | `APIClient` | `MockPlatformAPI` (mock data, records calls, scripted failures) |
| Supabase Auth | `AuthClientProtocol` (Supabase's own type is `AuthClient`) | `SupabaseAuthClient` | `MockAuthClient` |
| SwiftData | `Persistence` | `TrainStore` (on disk) | `TrainStore(inMemory: true)` |
| Time | `AppClock` (`now()`, `sleep(for:)`); not `Clock`, which would shadow Swift's | `SystemClock` | `TestClock` (moves only on `advance(by:)`) |
| Notifications | `Notifier` (local + APNs registration) | `SystemNotifier` | `MockNotifier` |
| Feature flags | `FeatureFlagProvider` | remote flags (§8) | `StaticFlags` |
| Network path | `Connectivity` | `ConnectivityMonitor` | `ConnectivityMonitor.preview(online:)` |

`HealthStore` hides HealthKit's types:
- A sync drains `HealthStream`s (each quantity type, sleep, workouts) page by page.
- A `HealthPage` carries an opaque anchor that is only `commit`ted after the upload was
  accepted.
- The mock behaves like HealthKit: an uncommitted page comes back again, which is what
  the 413 retry relies on.

### One environment, three graphs

`AppEnvironment` (`Ryft/Environment/AppEnvironment.swift`) holds every dependency and is
built once:

- `AppEnvironment.live` is created at launch by `RyftApp`. It is passed into services
  (`SyncService(env:)`, `AppState(env:)`) and into views via `@Environment(\.appEnvironment)`.
- `.preview(online:flags:)`: signed in with a fake session, mock data, an in-memory store,
  nothing leaves the process. `previewEnvironment()` injects it.
- `.test(api:health:clock:notifier:auth:flags:online:)`: the same mocks with a `TestClock`.
  Tests keep handles to script and inspect them (`EnvironmentTests`).

Demo mode is the same seam at runtime:
- `env.api` returns `demoAPI` (a `MockPlatformAPI`) when Demo data is on, `liveAPI`
  otherwise.
- Previews force it on and tests force it off (`demoOverride`), independent of the
  simulator's default.

### Migrating without a big bang

WHOOP's pattern is to run the old and the new implementation side by side, select one
with a flag, and remove the old one once the new one has proven itself. RYFT applies it
twice:

1. **Singletons → environment.** The old `.shared` singletons still exist, but they are
   *the members of `AppEnvironment.live`*. `SyncService.shared` is `SyncService(env: .live)`,
   and `TrainSource.current` is `AppEnvironment.live.api`.
   - Old call sites and migrated ones see the same instances.
   - A call site moves by taking `env` (or the protocol) instead of `.shared`.
   - When the last caller of a `.shared` is gone, the static goes too.
2. **Behaviour behind a flag.** A new implementation of a seam (or a redesigned screen)
   ships next to the old one, and a `FeatureFlag` picks between them per user:
   - for example `today.redesign`;
   - flags come from `GET /v1/config` with compiled defaults, plus local overrides in
     Debug (§8);
   - rolled out by percentage on the platform;
   - the old path is deleted after the flag has been at 100 % for a release.

Rules for new code:
- Take dependencies in the initializer (protocols, or `AppEnvironment`), never `.shared`.
- No `Date()` / `.now` in logic that tests need to control: use `env.clock.now()`.
- No `Task.sleep` for timing a feature: use `env.clock.sleep(for:)`.
- Tests wait with the bounded `eventually { … }` helper, never with an unbounded loop. A
  broken expectation must fail, not hang the run.
