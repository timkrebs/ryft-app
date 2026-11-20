# App Attest client: design (T0)

Contract: platform `API.md` → App Attest, Conventions and Errors (PR #220, D245). AC 1–12: `plan.md`. Record: ADR 0023.

**Problem.** Every api and ingest request carries `X-RYFT-App-Token` once the app has one. The token comes from three
routes that go through `exchange` (bearer, 401, request IDs) but must never ask for a token. One renewal per account at
a time; a refusal never drops a write; nothing changes while the server answers `404`. Swift 5.10, approachable
concurrency, iOS 18.6, DeviceCheck and CryptoKit (system frameworks). One UI string.

| | Option | For | Against |
| --- | --- | --- | --- |
| **A** | An actor `AppAttestor`; `exchange` asks it for the header and holds the 403-once beside the 401 refresh-once | every request (background too), the epoch guard, request IDs and `APIStatus` for free; single-flight in an actor | `exchange` grows by about 15 lines |
| B | A `URLProtocol` or session wrapper | `exchange` untouched | can't see the epoch or request IDs; its own calls need the bearer, so it recurses or duplicates `exchange` |
| C | Each caller handles the 403 | explicit | five copies, no single-flight, a second retry layer for reads (ADR 0001) |

**Choice: A**, token in memory only. The Keychain would be a secret at rest; a suspended process keeps the token anyway.

## 1. Shape (`Networking/AppAttestor.swift`, `AppAttestSeams.swift`, `APIClient+AppAttest.swift`)
```swift
actor AppAttestor {
    static let live = AppAttestor(service: DeviceAppAttestService(), keys: KeychainAppAttestKeys(), clock: SystemClock(),
        defaults: .standard, stamp: { AuthService.shared.accountID.map { .init(account: $0, epoch: APIStatus.shared.epoch) } })
    init(service: AppAttestService, keys: AppAttestKeyStore, clock: AppClock, defaults: UserDefaults,
         stamp: @escaping @MainActor @Sendable () -> AttestStamp?)
    func token(epoch: Int, via client: APIClient) async -> String?   // nil: go without; may start a renewal (§3)
    func renewed(after refused: String?, epoch: Int, via client: APIClient) async throws -> String?   // after the 403
    nonisolated func wipe()   // the Keychain item now, on the caller; then token, renewal, attestPausedUntil
}
struct AttestStamp: Equatable, Sendable { let account: String; let epoch: Int }
struct StoredAppAttestKey: Codable, Equatable, Sendable { let account: String; let keyId: String; var attested: Bool }
protocol AppAttestService: Sendable {   // live: DCAppAttestService.shared, read per call
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}
protocol AppAttestKeyStore: Sendable {   // live: one item "ryft.appAttest.key", JSON
    func load() throws -> StoredAppAttestKey?   // throws before the first unlock, which is not "no key"
    func save(_ key: StoredAppAttestKey) throws
    func remove()
}
protocol AppClock { …; func uptime() -> Duration }   // new requirement
```
- **Clock.** `SystemClock.uptime()` is `ContinuousClock.now - origin` (not `SuspendingClock`, which stops in sleep and
  makes a token look fresh). `TestClock.uptime()` moves only on `advance(by:)`, not on `set(_:)`. No other conformers.
- **Keychain.** `Keychain.set` gains `accessible:` (default: today's value); the key uses `AfterFirstUnlockThisDeviceOnly`.
  A new `Keychain.read(_:) throws` returns nil only for `errSecItemNotFound`. Never `kSecAttrSynchronizable`.
  `clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))`, both steps.
- **Network.** The three routes are `APIClient` methods on `exchange`, run under `$singleAttempt.withValue(true)` (the
  fail-fast session, no 503 or 429 loop), listed in `appAttestRoutes` (no header, no 403 handling: no recursion) and in
  `openBehindInviteGate`. The HTTP seam is the client's `URLSession` (StubURLProtocol), not a protocol over the routes:
  they must be tested through the real `exchange`. No GameplayKit: a run is one bounded function (§8).

## 2. Single-flight and account binding
- **State:** `issued: (token, epoch, expiresAt on uptime)?`, `renewal: (epoch, task)?`, and waiters parked as in
  `RequestBudget.park` (continuations, a cancellation handler, a timeout on `clock.sleep`).
- **Reentrancy:** `renewal` is set before any `await`. The task reads `stamp()` first. A nil stamp, or one with another
  epoch than the caller's, means a stale request: nothing starts.
- **`renewed(after:)`**, in order: a valid `issued` other than `refused` is returned; a renewal in flight is joined; one
  started under 60 s ago, or a §4 rule, gives nil; otherwise one starts and is joined. A refused request never starts a
  renewal of its own.
- **Account change, three guards:**
  1. A request uses `issued` only when the epochs match. Every way out of an account wipes, and every wipe bumps the
     epoch (`onWipe` → `forgetRequests`), so no epoch spans two accounts.
  2. The run checks `await stamp() == started` before saving the key and before publishing. The Keychain write is in
     that same `MainActor.run`, so it can't land after the wipe's delete, which is main-actor too.
  3. `load()` drops a key whose account isn't the stamp's.
  `wipe()` also cancels the task and releases the waiters; `retryStep` turns a changed epoch into `CancellationError`.

## 3. Header and 403 retry (inside `exchange`: confirmed)
```swift
let attests = appAttest != nil && !Self.appAttestRoutes.contains("\(method) \(Self.route(path))")
var appToken = attests ? await appAttest?.token(epoch: epoch, via: self) : nil   // after the bearer; set in perform()
case 403 where attests && !renewedToken && Self.errorCode(in: data) == .appAttestRequired:
    renewedToken = true   // safe for any method: the check runs before routing and the body
    guard let fresh = try await retryStep({ try await appAttest?.renewed(after: appToken, epoch: epoch, via: self) })
    else { break }        // none to be had: thrown below with its request ID
    appToken = fresh; continue
```
- Same budget style as the 401, and it applies under `singleAttempt` too. `init(…, appAttest: AppAttestor? = nil)`:
  existing tests stay header-free. `APIClient.shared` passes `.live`.
- **Waits: I'm overruling "no wait".** Under `warn`, a request without a token is logged `missing`. D245 goes `on` only
  after 7 days with zero `missing` from app builds, and with a memory-only token every launch's first requests would be
  `missing`. So, once this install has seen the challenge route answer `200` (`servedSeen`), a request without a valid
  token waits **≤ 3 s** for the renewal it starts. Today nothing waits. A `403` waits **≤ 20 s**. The renewal outlives
  any waiter.
- **Background cost:** two requests and one Secure Enclave signature (about 0.5 s) per fresh process; a suspended
  process keeps its token. Renew once `expiresAt − uptime < min(300 s, ttl_sec / 2)`, still sending the current token;
  never send one past `expiresAt`. Nothing secret persists.

## 4. Backoffs (`defaults` key `appAttest.backoff`: dates and one flag, nothing identifying)
| After | Effect | Kept | Length |
| --- | --- | --- | --- |
| `404` without a code, or `501`, from a route | no renewal, no header, `servedSeen = false` | `notServedUntil` | **6 h** (the config TTL): at most 4 probes a day, whatever HealthKit wakes |
| the second `app_attest_invalid` in a run; a `400` from `/keys` or `/token` | no attestation | `attestPausedUntil` | **24 h**: a try costs keys (10 a day) |
| `429` on `/keys` | no attestation; `/token` with an attested key still works | `attestPausedUntil` | `Retry-After` (1 h without) |
| `429` on challenge or token, transport, `5xx`, `serverUnavailable`, a locked Keychain | no renewal | memory | `Retry-After`, else 1, 2 … 30 min; reset by a token |
| `isSupported` false or `featureUnsupported` | nothing; one log line per process, no values | memory | the process |

The wipe clears `attestPausedUntil` (the keys budget is per account) and keeps `notServedUntil` and `servedSeen`.

## 5. When it starts. 6. The wipe
- **No hook.** The account's first request calls `token(epoch:)`, which starts the renewal. That covers the moment
  after `publish` (onboarding's `GET /v1/me`), a launch with a session, a background launch (`POST /v1/sync`) and the
  foreground. The sign-in path is untouched; an idle app does nothing.
- **The wipe.** `AuthService.wipeSharedLocalData` → `before:` gains `AppAttestor.live.wipe()`, next to
  `clearPerUserState()`. It runs on sign-out, deletion, expiry and switches; a `storeOnly` retry skips it, as the first
  pass already ran it. Tests inject `wipeLocalData`. A key bound to another account is dropped on read (§2): a kill
  mid-wipe, or an item that survived a reinstall. `onAccountWillChange` and `clearPerUserState` stay as they are.

## 7. Writers (once T1 adds the four codes)
| Writer | Today | Change |
| --- | --- | --- |
| Train, `TrainSyncService.isRetryable` | a `403` with any known code is retryable: the op stays | **none**; a T3 test pins it against `fix/train-refusals-kept` |
| HealthKit page, `SyncEngine.upload` | thrown before `commit`; the coordinator doesn't retry 4xx | none |
| `ActivityUploader.failed` | `.other`: the row is failed until Retry | `403 app_attest_required` → `.transient` plus `nothingStored()`: 3 lines |
| `TrainImportUploader.failed` (l. 1045) | **bug:** `.gated(.gate(.appAttestRequired))`, "RYFT needs your answer" | `code.flatMap { $0.isGate ? .gated(.gate($0)) : nil } ?? .held`: 1 line |
| Plans (`TrainLibrary`), `JournalStore.save` | not queued; the editor keeps the edit and shows the error | none |
| Reads, `FailureKind.of` | `.other`: no ReadScheduler retry (`exchange` already renewed); the card shows code and request ID | none |

`APIError.errorDescription` gains `.http(403, _, _, .appAttestRequired?, _)`: "RYFT couldn't verify this app on this
iPhone. Try again later." The same string covers `isSupported` false. `isGate` stays false for the new codes.

## 8. One run (each "once" is per run; a test counts the requests)
| Step | Outcome |
| --- | --- |
| `load()` | the account's key; another account's is dropped; a throw is a locked Keychain (memory backoff) |
| challenge (no key, or not attested) | `200` sets `servedSeen`; `404` without a code or `501` is not served (§4) |
| `generateKey` | saved at once with `attested: false`, so a kill orphans nothing |
| `attestKey` | `invalidKey`: drop the key, step 1, once. `serverUnavailable`: keep the key, memory backoff. Other: drop the key, memory backoff |
| `POST keys` | `201` sets `attested`. `422 …challenge_invalid`: new challenge, same step, once. `422 app_attest_invalid`: new key, once, then the 24 h pause. `429`: §4 |
| challenge, `generateAssertion` | `invalidKey`: drop the key, step 1, once. Other: memory backoff |
| `POST token` | `200` publishes after the stamp check. `404 app_attest_key_unknown`: drop the key, step 1, once. `422`s and `429` as for keys |

Logs: step, status, `code`, request ID and DCError code; never the key ID, token, challenge or assertion.

## Migration and tests
1. **T1:** models, the four codes and fixture tests; the existing `isGate` test stays green.
2. **T2:** `uptime`, the `Keychain` changes, the seams and the actor, the `APIClient` changes (init, `perform`, the 403
   case, the route sets, the string), the wipe line, the two writer lines, the entitlement, and an ARCHITECTURE §1 row.
3. **T3:** `APIClient(stub, appAttest: AppAttestor(fake service, memory keys, TestClock, suite, stamp))`.
   - AC1: call order, both hashes, the header on api, ingest and under `$runsInBackground`, and the key's query attributes.
   - AC2: +3 301 s gives one renewal and no `generateKey`; `set(_:)` changes nothing.
   - AC3 and AC4: five concurrent 403s make one renewal; refused again, it throws with its `request_id`.
   - AC5: counts across two attestors on one defaults suite, then +6 h. AC6: no request, no header.
   - AC7: Train op kept, no anchor commit, uploader `.transient`, import `.held`.
   - AC8: suspend the fake mid-run, wipe, move the stamp to B, resume; no header for B, no key of A's left.
   - AC9: the 422 matrix. AC10: the fake values appear in no `APIStatus` record or error text.

## What could go wrong
- **Re-attestation.** A good `attestKey` whose `POST keys` is lost gets attested again; if Apple says `invalidKey`, a new
  key follows. Background attest calls are unverified too (D245); on failure the page stays queued. Device test.
- **The 3 s wait.** It still lets `missing` through for a slow renewal or a sign-in's first attestation.
- **`via client:`** sends the non-Sendable `APIClient` into the actor, as `SyncEngine` does with `PlatformAPI`.
- **`fix/train-refusals-kept`.** If it narrows `isRetryable`, AC7 fails. Old builds still lose Train writes under `on`.

## Contract gaps (candidates for `docs/API_REQUESTS.md`)
1. **Warn lines can't tell builds apart.** A `missing` from this build (first request, sign-in, no App Attest) reads as
   an old build's. Ask: record the app build (User-Agent `Ryft/<build>`); then the 3 s wait can go.
2. **No mode or "served" signal** except probing. Ask: a `GET /v1/config` field or flag, which also gives a kill switch.
3. **`ttl_sec` has no stated minimum**; the app renews at `min(300, ttl_sec / 2)`.
4. **Echoed values.** Ask: confirm the routes' `error` text never echoes `challenge`, `key_id` or `assertion` (the app
   shows that text for unknown statuses).
