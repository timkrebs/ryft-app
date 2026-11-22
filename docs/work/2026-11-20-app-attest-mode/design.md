# App Attest mode and app build: design (PR 1)

Contract: platform `API.md` → Conventions (App build, App token), App Attest → The mode in the config, `GET /v1/config`
(PR #227, D247: AA1–AA4). Record: ADR 0023, decisions 5, 7 and 8. Builds on `docs/work/2026-11-19-app-attest/design.md`.

**Problem.** D247 asks for `X-RYFT-App-Build` on every request to api and ingest. It also tells the app the server's
mode, so the app can stop probing a server that says `off`. Production runs `off` with the routes answering `501`, so
today every install probes once every 6 h for nothing. Constraints: one owner per piece of state; the mode must be
known at a cold or background launch (from the cache) and must belong to the current account; the newest answer counts
at once; `token()` gains no new suspension point; tests stay injectable; no new dependencies.

## 1. Model (`Networking/Models.swift`)
```swift
struct RemoteConfig: Codable, Hashable {   // …existing fields
    /// API.md → `app_attest` (AA2, D247): "off" | "warn" | "on", absent before D247. A string, so an unknown
    /// value can't fail the whole config; read it through `appAttestMode`.
    var appAttest: String? = nil
    var appAttestMode: AppAttestMode? { appAttest.flatMap(AppAttestMode.init(rawValue:)) }
}
enum AppAttestMode: String, Equatable, Sendable { case off, warn, on }   // closed; exact match ("OFF" is unknown)
```
- The fixture `remote_config.json` becomes API.md's first `RemoteConfig` example, copied exactly. It has `analytics`
  (ignored until PR 2) and `"app_attest": "off"`. Two expectations move with it: `DecodingTests.remoteConfig`
  (`flags.count` 6 → 8) and `MirrorDecodingTests.remoteConfigNamesThePolicyInForce` (`2026-10-20` → `2026-10-26`).
- `FlagStore.Cached` stores the whole `RemoteConfig`. An older cached document has no key, so it decodes to nil
  (absent), as `privacyPolicyVersion` did. `MockPlatformAPI.remoteConfig` stays without the field, so demo mode
  reads it as absent.

## 2. Where the attestor learns the mode
| | Feed | For | Against |
| --- | --- | --- | --- |
| **A** | `FlagStore` publishes the newest mode into a lock on `AppAttestor` | it owns the per-account cache, loads it at init (cold and background launches), and its `apply`, `switchAccount`, `setDemo` and `reset` already mark every change; synchronous read, no hop | one projected copy (one writer) |
| B | the attestor pulls through a `@MainActor` closure, like `stamp` | no copy | a main-actor hop and a suspension inside `token()` on every request without a token, which is every request under `off` (all of production) |
| C | `ConsentState.received` pushes | hears every answer, background `revalidate` included | no cold-launch value unless its record also stores the mode (state in two places); it drops answers without a policy version |

**Choice: A.** Feeding from both A and C would give the mode two writers. C's one advantage is answers fetched in the
background, and a time limit on `off` (§3) covers that.

```swift
// AppAttestor
static let offTrust: TimeInterval = 24 * 3600            // a cached `off` counts this long after its fetch
private struct Configured: Sendable { var mode: AppAttestMode?; var fetchedAt: Date?; var revision = 0 }
private nonisolated let configured = OSAllocatedUnfairLock(initialState: Configured())
private var offLiftedAt: Int?                            // the `revision` a refusal lifted `off` for (actor state)
nonisolated func configure(_ mode: AppAttestMode?, fetchedAt: Date?)   // sets both, revision += 1
nonisolated var configuredMode: AppAttestMode? { configured.withLock { $0.mode } }   // tests
private var isOff: Bool   // mode == .off && inForce(fetchedAt + offTrust, now: clock.now(), longest: offTrust)
                          //   && offLiftedAt != revision; a nil fetchedAt is not in force
// FlagStore
init(store:defaults:account:demo:appAttest: AppAttestor? = nil)          // shared: `appAttest: .live`
@ObservationIgnored private var shownAppAttest: AppAttestMode?           // set in show(), nil in clear()
private func publishAppAttest()   // newest: pending's mode and fetchedAt, even nil, else (shownAppAttest, fetchedAt)
```
- `publishAppAttest()` runs at the end of `init` (after the cache is shown), at the end of `apply` (after the
  generation guard, in both branches: a pending answer counts at once), and at the end of `reload` and `reset`.
  `applyPending` doesn't call it, because the newest answer hasn't changed. Publishing once per call means nobody can
  read the `nil` between `clear()` and `show()`.
- **The account's.** `switchAccount` and `setDemo` → `reload` publishes the new side's cached mode, or nil (absent:
  today's probe). Sign-out shows `config.signed-out`, which is never fetched (`FeatureFlags` throws `signedOut`).
  The server says the mode is the same for every account, so a background process that misses the scene's
  `switchAccount` leaks nothing; with no account the stamp is nil and nothing runs.
- **Cold or background launch.** `RyftApp.init` → `AppEnvironment.live` → `FlagStore.shared` loads the cache before
  any request. If the mode isn't there (a request earlier than that, or `TrainStore`'s fallback before the first
  unlock), it counts as absent: one probe, today's behaviour. No init cycle: `AppAttestor.live` touches no `FlagStore`.

## 3. Semantics (`AppAttestor`)
```swift
func token(epoch: Int, via client: APIClient) async -> String? {
    catchUpWipes()
    let now = clock.uptime()
    if let issued, issued.epoch == epoch, now < issued.expiresAt {
        if now >= issued.renewAt, !isOff { startRenewal(epoch: epoch, via: client) }
        return issued.token
    }
    guard !isOff, let id = startRenewal(epoch: epoch, via: client), backoff.servedSeen else { return nil }
    …                                                     // unchanged: the 3 s wait
}
// renewed(after:…), right after the liftedNotServed block, before any await:
if isOff { offLiftedAt = configured.withLock { $0.revision } }   // the server is `on`, whatever the cache says
```
- **`off`:** no challenge, no key and no wait. A run already in flight is not cancelled, and a token held for the
  epoch goes out until it expires, with no renewal. `heldToken` is unchanged.
- **`403 app_attest_required` under a cached `off`:** the cache is stale (the server went `warn` → `on`).
  `renewed` renews as before, because `mayStart` doesn't look at the mode. The lift keeps renewals going until the
  next published answer. Under `on` that answer can only arrive with a token, so it says `on`, or `off` after a
  rollback, which then counts. It works like `liftedNotServed`, but ends with new evidence instead of with the process.
- **`warn`, `on`, absent:** exactly today's behaviour. No mode lifts `notServedUntil` and none sets `servedSeen`: a
  `501` or a `404` without a code from the challenge route stays authoritative in every mode.
- **A stale `off`:** more than 24 h after its fetch (or a fetch dated in the future: the clock was set back) it counts
  as absent, so a background-only process returns to the 6 h probe. A foreground app refetches every 6 h.
- AA3 (a `ttl_sec` floor of 600) and AA4 (fixed error texts) need no code: `min(300, ttl/2)` already holds, and the
  text may be shown.

## 4. Header `X-RYFT-App-Build` (`APIClient`, `App/PlatformConfig.swift` → `AppInfo`)
```swift
static var bundleBuild: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }   // no fallback
static func headerBuild(_ raw: String?) -> String?   // 1–4 dot-separated runs of ASCII 0-9, ≤ 24 chars; else nil
init(…, appAttest: AppAttestor? = nil, build: String? = AppInfo.bundleBuild)   // stores headerBuild(build), once
req.setValue(appBuild, forHTTPHeaderField: "X-RYFT-App-Build")   // in exchange, after X-RYFT-Device-ID
```
- Validate by hand: split on `.`, check each part is non-empty and every character is in `"0"..."9"`. Don't use `\d`
  (it matches Unicode digits) or a bare `/regex/` literal (Swift 5.10 needs a flag). The init takes the raw value, so
  a test can pass `1.0b3` and prove the client omits it. Settings would be the wrong home: it holds user settings.
- `exchange` builds `req` once and sends every attempt from it. So the 401, 403, 429 and 503 retries, the background
  and `singleAttempt` sessions, ingest, the three App Attest routes and the exempt routes all carry the header, with
  or without `appAttest`. It also goes to a caller's `base`, as `X-RYFT-Device-ID` does: the build is not a
  credential, and `base` has no production caller. Update the header comment at the top of the file.
- No other path reaches api or ingest: `WebContentSource` fetches ryftlab.de and the Supabase SDK talks to Supabase.
  Archive builds are `YYYYMMDD.HHMMSS` (15 chars) and local builds are `1`; both pass.

## 5. Tests (Swift Testing; `AttestRig` gains `build: String? = "20261120.091500"`, passed as `APIClient(build:)`)
`MirrorDecodingTests`:
- `remoteConfigAppAttestModes(_:)`, with arguments `"off"`/`"warn"`/`"on"` → that mode; absent, `null`, `"strict"`
  and `"OFF"` → nil. `appAttest` keeps the raw string. Proves the field is optional and the enum is closed.
- `remoteConfigFixtureIsAPIMdsExample`: `appAttestMode == .off`, 8 flags, `analytics` ignored. API.md's second
  example (`analytics: null`, `"warn"`) is decoded inline.
- `cachedConfigWithoutTheFieldDecodes`: a `FlagStore.Cached` written before this PR decodes to nil.

`AppAttestAvailabilityTests`, new suite "App Attest: the mode from the config (AA2)":
- `offSendsNoChallengeAndNeverWaits`: `served: true`, `configure(.off)`; `getMe` ×2 and `postSync` complete without
  the clock moving. Expect zero App Attest requests, no device calls, no token headers, `waiting == 0`.
- `offKeepsAHeldTokenAndDoesNotRenew`: get tok-1, then `.off`. At +3 301 s tok-1 goes out and nothing renews; at
  +3 601 s the request goes without a token and without a challenge.
- `absentProbesAsToday(_:)`, with arguments nil and the unknown mode: a `501` gives one challenge and sets
  `notServedUntil` (as in AC5).
- `warnAndOnAttest(_:)`, with arguments `.warn` and `.on`: the AC1 event order, then tok-1 on `GET /v1/me`.
- `a501UnderWarnIsNotServed`: `.warn`, challenge `501`. Expect `notServedUntil` set and `servedSeen` false; at
  +6 h − 60 s, no second probe. `warnDoesNotLiftANotServedPause`: a stored `notServedUntil` plus `.warn`, no probe.
- `aRefusalUnderCachedOffRenewsAndRetriesOnce`: `.off`, `GET /v1/me` answers 403 `app_attest_required` and then
  200. The call succeeds, the `me` tokens are `[nil, "tok-1"]`, and there's one `POST token`.
- `theRefusalLiftsOffUntilTheNextAnswer`: after that, +3 301 s renews (tok-2). Then `configure(.off)` again, and
  past expiry there's no challenge.
- `aStaleOffCountsAsAbsent`: `fetchedAt` 24 h + 1 s ago probes, and so does a `fetchedAt` 25 h ahead.
- `flagStorePublishesTheNewestMode`: a `FlagStore` over `TrainStore(inMemory: true)` with A's cached `off` and
  `appAttest: rig.attestor`. At init → `.off`. `apply("warn")` while one is shown → `.warn` before `applyPending`.
  `switchAccount(B)` with no cache → nil; back to A → `.off`; `setDemo(true)` → nil. An `apply` with an old
  `generation` changes nothing.

`AppAttestHeaderTests`, new suite "X-RYFT-App-Build (AA1)":
- `everyRequestKindCarriesTheBuild`: foreground `GET /v1/me`; `postSync`, whose host is the ingest host; both again
  under `$runsInBackground`; `GET /v1/me` under `$singleAttempt`; the three App Attest routes of the first run; the
  five exempt routes. Every request in `server.requests` carries the same value.
- `everyAttemptCarriesIt`: 401→200, 403 `app_attest_required`→200 and 503→200. Both attempts carry it.
- `aClientWithoutAppAttestAndACallersBaseSendIt`: `appAttest: nil`, then `base:` the rig's host.
- `headerBuildValidation(_:)`: passes for `1`, `20261120.091500`, `1.2.3.4` and 24 chars. Fails for nil, `""`,
  `1.0b3`, `1.`, `.1`, `1..2`, `1.2.3.4.5`, 25 chars (`2026112009150012345.12345`), ` 1`, `١٢` and `1,2`.
- `aBuildThatFailsThePatternIsOmitted(_:)`, with arguments `1.0b3` and the 25-char value: no request has the header.

## 6. Migration
1. **T1.** Model, fixture, the two moved expectations, decode tests.
2. **T2.** `AppInfo`, the `APIClient` init and its one line, the rig's `build:`, the header suite.
3. **T3.** `AppAttestor` (`configure`, `isOff`, the two `token` guards, the lift), `FlagStore` (init parameter,
   `shownAppAttest`, four publish points, `shared` passes `.live`), the mode suite. No CHANGELOG line (nothing a user
   sees).

## What could go wrong
- **A stale `off` under `warn`.** Requests go without a token, and so produce `missing` lines, until the next config
  (launch, then every 6 h; background-only: up to 24 h). AA1 makes those lines attributable to this build. D245 never
  goes `off` → `on`, so the 403 lift is only needed for a cache that went stale across a whole `warn` period.
- **Reentrancy.** `token()` gains no `await`. `configure` is a lock write on the main actor. `offLiftedAt` is set
  before `renewed`'s first suspension. A request that reads `off` just before `warn` lands goes without a token; the
  next request attests.
- **Exact headers.** Only `AttestRig` reads `allHTTPHeaderFields`, and no test pins the full header set.
