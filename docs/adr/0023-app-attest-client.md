# 0023 — The app token has one owner and rides on `APIClient.exchange`

- Status: proposed (2026-11-19, T0 of `docs/work/2026-11-19-app-attest/`)
- Deciders: Tim Krebs; recorded by ios-architect
- Applies to: `Ryft/Networking/APIClient.swift` (`exchange`, `perform`), the new `AppAttestor`, every api and ingest
  request, every queued writer that reads `APIError.code`

## Context

- Platform D245 (`API.md` → App Attest) wants an app token, `X-RYFT-App-Token`, on every request to both hosts. The
  token comes from three routes that themselves need the bearer. Under `on`, a request without a valid token gets
  `403 app_attest_required`. The rule is to renew once and send again, keep refused writes, and run one renewal per
  account and key at a time.
- Every api and ingest request already goes through one function, `APIClient.exchange`. It owns the bearer and its
  401 refresh-once, the request ID, `APIStatus` records, the background session, and `APIStatus.epoch`, which stops a
  retry from outliving its account.
- Before `on`, D245 waits for 7 days of `warn` with no `missing` line from an app build.

## Decision

1. **One owner.** A single actor, `AppAttestor`, owns the token (in memory only), the attested key ID (in the Keychain,
   `AfterFirstUnlockThisDeviceOnly`, bound to its account) and the backoffs. Nothing else stores or derives any of them.
2. **The header and the retry live in `exchange`.** `perform` sets the header on each attempt. The 403-once retry
   sits next to the 401 refresh-once, with the same `retryStep` epoch guard. Callers never see a token, and they never
   retry an `app_attest_required` themselves.
3. **The three App Attest routes are exempt by route** (`APIClient.appAttestRoutes`): no header and no 403 handling.
   So the attestor's own calls go through `exchange`, bearer and 401 included, and cannot recurse.
4. **Tokens are bound to `APIStatus.epoch`, keys to the account.** A request uses only a token issued in its own epoch.
   A renewal checks the account and the epoch on the main actor before it writes the Keychain or publishes.
5. **Requests wait for a first token, briefly**: up to 3 s, and only once this install has seen the routes served. A
   refused request waits up to 20 s for the shared renewal. This is the price of a memory-only token under D245's stop
   rule; it goes away if the platform's warn lines learn to tell builds apart.
6. **`app_attest_required` is never a gate and never "drop the edit".** It isn't in `isGate`. `FailureKind.of` keeps it
   `.other`, so there is no second retry layer for reads (ADR 0001). Queued writers keep the refused write: Train and
   the sync page as they already do, activities as `.transient`, the import as `.held`.

## Consequences

- **A new route** gets the header and the retry for free. Only a route that mints the token itself joins
  `appAttestRoutes`.
- **Tests.** Every existing `APIClient` test stays header-free, since `appAttest` defaults to nil. App Attest tests use
  the real `exchange` behind StubURLProtocol, a fake `AppAttestService`, an in-memory key store and `TestClock`, whose
  new `uptime()` is the monotonic clock.
- **A new account changes nothing here.** Its first request starts its attestation; the wipe deletes the old key, and
  the epoch makes the old token unusable.
- **Cost.** One renewal per fresh process: two requests and one Secure Enclave signature. Under `off` with the routes
  served, the first request of a launch may wait up to 3 s.
- **Revisit** decision 5 when the platform answers the `docs/API_REQUESTS.md` entries: build-aware warn lines, and a
  mode or "served" signal in `GET /v1/config`.
