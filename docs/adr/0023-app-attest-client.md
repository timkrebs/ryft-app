# 0023 — The app token has one owner and rides on `APIClient.exchange`

- Status: proposed (2026-11-19, T0 of `docs/work/2026-11-19-app-attest/`); amended 2026-11-20 (decisions 5, 7, 8;
  `docs/work/2026-11-20-app-attest-mode/`)
- Deciders: Tim Krebs; recorded by ios-architect
- Applies to: `Ryft/Networking/APIClient.swift` (`exchange`, `perform`), the new `AppAttestor`, every api and ingest
  request, every queued writer that reads `APIError.code`; since the amendment also `RemoteConfig`, `FlagStore` and
  `AppInfo`

## Context

- Platform D245 (`API.md` → App Attest) wants an app token, `X-RYFT-App-Token`, on every request to both hosts. The
  token comes from three routes that themselves need the bearer. Under `on`, a request without a valid token gets
  `403 app_attest_required`. The rule is to renew once and send again, keep refused writes, and run one renewal per
  account and key at a time.
- Every api and ingest request already goes through one function, `APIClient.exchange`. It owns the bearer and its
  401 refresh-once, the request ID, `APIStatus` records, the background session, and `APIStatus.epoch`, which stops a
  retry from outliving its account.
- Before `on`, D245 waits for 7 days of `warn` with no `missing` line from an app build.
- D247 (platform PR #227, 2026-11-20) answers the app's AA1–AA4. AA1: an optional `X-RYFT-App-Build` header, which
  goes into the warn line. AA2: `GET /v1/config` → `app_attest` (`off`/`warn`/`on`, closed, absent before D247). A
  `501` or a `404` without a code from the challenge stays authoritative. AA3: `ttl_sec` is never below 600. AA4: the
  routes' error texts never echo a value. Production runs `off`, and its routes answer `501`.

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
5. **Requests wait for a first token, briefly**: up to 3 s, only once this install has seen the routes served, and
   never while the mode is `off` (decision 7). A refused request waits up to 20 s for the shared renewal. Since AA1,
   the warn lines say which build sent a request without a token, so the stop rule no longer depends on the wait. It
   stays under `warn`, `on` and no mode, because under `on` it spares the first request a `403` and a second round
   trip. (Amended 2026-11-20.)
6. **`app_attest_required` is never a gate and never "drop the edit".** It isn't in `isGate`. `FailureKind.of` keeps it
   `.other`, so there is no second retry layer for reads (ADR 0001). Queued writers keep the refused write: Train and
   the sync page as they already do, activities as `.transient`, the import as `.held`.
7. **The mode comes from the cached config, and `FlagStore` is its one writer.** `RemoteConfig.appAttest` decodes as
   an optional string, so an unknown value can't fail the config. It is read through `AppAttestMode?`, where unknown
   means absent. `FlagStore` publishes the newest answer's mode into a lock on the attestor (`configure`): at init
   from the account's cache, on every `apply` (pending included), and on account or demo switches. The attestor reads
   it synchronously, with no hop.
   - `off`: no challenge, no key, no wait, no renewal. A token already held goes out until it expires.
   - `warn`, `on` and absent: as before. No mode lifts a not-served pause.
   - A cached `off` counts for 24 h after its fetch, then as absent.
   - A `403 app_attest_required` lifts `off` until the next published answer.
8. **`X-RYFT-App-Build` rides beside `X-RYFT-Device-ID`** in `exchange`, so it is on every attempt, on both hosts
   and on the App Attest and exempt routes. Its value is `CFBundleVersion`, validated once at the client's init
   against `^[0-9]+(\.[0-9]+){0,3}$` and 24 characters, and omitted when it fails. It is not a credential, so unlike
   the token it also goes to a caller's `base`.

## Consequences

- **A new route** gets both headers and the retry for free. Only a route that mints the token itself joins
  `appAttestRoutes`.
- **Tests.** Every existing `APIClient` test stays token-free, since `appAttest` defaults to nil. Those tests now send
  the test host's build, which none of them checks. App Attest tests use the real `exchange` behind StubURLProtocol, a
  fake `AppAttestService`, an in-memory key store and `TestClock`, whose `uptime()` is the monotonic clock. They set
  the mode with `configure` and the build with `APIClient(build:)`.
- **A new account changes nothing here.** Its first request starts its attestation; the wipe deletes the old key, and
  the epoch makes the old token unusable. Its mode is its own cached config's, or absent.
- **Cost.** One renewal per fresh process under `warn` or `on`: two requests and one Secure Enclave signature. Under
  `off` there is none, and production (`off`, routes `501`) stops its 6-hourly probe once a config is cached. Under
  `warn` or `on` with the routes served, the first request of a launch may wait up to 3 s.
- **A stale `off`** sends requests without a token until the next config: at most 6 h in the foreground and 24 h in a
  background-only process. Their warn lines now name this build.
- **Answered** (2026-11-20, D247): the `docs/API_REQUESTS.md` entries AA1–AA4 resolved what this ADR left to revisit.
  AA3 confirms the `min(300 s, ttl_sec / 2)` lead. AA4 lets the app show the routes' texts, though it still branches
  only on status and code. Revisit decision 5 if the platform's stop rule for `on` comes to count `missing` per build.
