# App Attest client: review (2026-11-19)

Reviewed: `origin/main..0214dea` (T1, T2). Reviewers: security-privacy-reviewer, code-reviewer (one, on the attestation
and retry code, as the brief allows). Read-only; nothing built by them.

## Security and privacy

Nothing blocking. Sound: every `Logger` call and signpost, `APIStatus` records, error text and `diagnosticDetails` are
free of the key ID, token, challenge and assertion. Existing Keychain items keep their accessibility, and a locked
Keychain isn't read as "no key". The token is memory-only. `appAttest.backoff` holds two dates and a flag. The wipe and its
guards hold, and the header never reaches the App Attest routes, web content or Supabase.

| # | Sev | Finding | Decision |
| --- | --- | --- | --- |
| S1 | should-fix | `APIClient`'s two session configurations keep `URLCache.shared`: a cached response's request, headers included (bearer, app token), could land in `Cache.db`, which no wipe clears. The platform sends `Cache-Control: no-store` on every answer, so nothing should be stored, but the client shouldn't depend on it (N-6). | **Fix here:** `urlCache = nil` on both. One line each; it makes "memory only" hold without the server's help. |
| S2 | should-fix | No redirect handler: a 3xx from api or ingest to another host would carry `X-RYFT-App-Token`, `X-RYFT-Device-ID` (and the bearer, as today). | **Follow-up**: the bearer has had the same exposure since the start, and the platform never redirects. Separate PR with the bearer: refuse redirects off the two hosts, like `WebContentSource.SameHostRedirects`. In STATUS → Open. |
| S3 | should-fix | Tests: nothing pins the key item's Keychain attributes; AC8 and AC10 had no tests yet. | Sent to test-engineer (T3). |
| S4 | nit | A future `exchange(base:)` caller would get the token. | **Fix here:** the header only when `base == nil`. |
| S5 | nit | Debug only: an API URL override while signed in sends the token, key ID and assertion to that host. | Accepted: Debug builds, the developer's own host. |
| S6 | nit | `AppAttestToken`, `StoredAppAttestKey` and the two posts print their secrets if interpolated. | **Fix here:** redacted `description`/`debugDescription`. |
| S7 | nit | `check-entitlements.py` doesn't check the value. | **Fix here:** when the key is present, its value must be `production` (Xcode's + Capability writes `development`). |

Privacy texts (out of scope here, listed for the user): `PrivacyInfo.xcprivacy` (the key ID under the declared device
ID; no new data type or required-reason API), `docs/APP_STORE.md` → App Privacy, and the privacy policy on ryftlab.de
(D245's text, C2).

## Code review

Covered all seven focus areas. Sound:
- **Single-flight:** the renewal is set before any suspension. Waiters are released at the end, on replacement, on a wipe,
  on timeout and on cancel, each one removed before it's resumed: no double resume, no leak.
- **Account binding:** the epoch moves in the wipe's main-actor turn. Publishing and the Keychain write re-check the
  account and the wipe count, and another account's stored key is dropped.
- **Retry bounds:** the 403 retry is once per request, beside the 401. Every code (422 ×2, 404 with and without its code,
  501, 429, 400) has a bounded number of tries. No recursion, and no header on the three routes.
- **Byte-exactness:** `clientDataHash`, `key_id` unchanged, standard base64, a fresh challenge per attempt.
- **Refused writes kept:** Train, activities (`.transient`), import (`.held`), the sync anchor.
- **Concurrency:** no `@unchecked` / `nonisolated(unsafe)` in app code.

| # | Sev | Finding | Decision |
| --- | --- | --- | --- |
| C1 | should-fix | A run a wipe already ended still sets a backoff for the next account (`AppAttestor.swift:355-361`, `:383-386`). `check()`'s `CancellationError`, `serverUnavailable`, 5xx/429/`.signedOut`, and `/keys` 429/400 (persisted, hours) reach `ended()` unguarded. Scenario: A signs out mid-`attestKey`, then B signs in. Under `on`, B gets "couldn't verify" for 60 s, or for hours. | **Fix here:** in `renew`'s catch, return before `ended` when cancelled or the wipe count moved; `check` throws `Stop.quietly` when cancelled. Regression test: hold `attestKey`, wipe, throw `serverUnavailable`, and B's renewal still starts. |
| C2 | nit | Exempt routes (`DELETE /v1/devices/{id}/push` in `beforeSignOut`, `DELETE /v1/me`, `POST /v1/feedback`) start a renewal and wait up to 3 s (`APIClient.swift:514-516`): sign-out stalls, and the leaving account gets a renewal. | **Fix here:** an exempt set that sends a held token but never starts or waits for one. The contract lets the app send it there. |
| C3 | nit | A `403 app_attest_required` can't lift the 6 h "not served" pause (`AppAttestor.swift:611`, `:212`). Under `on`, one stray 404/501 (or a 404 with a code this build doesn't know) locks the install out for 6 h. | **Fix here:** a `403 app_attest_required` proves the routes are live, so `renewed()` clears `notServedUntil` once. |
| C4 | nit | No epoch check after the ≤ 3 s token wait (`APIClient.swift:516`): A's request can go out after A's wipe. | **Fix here:** `guard await status.epoch == epoch else { throw CancellationError() }` after the wait. |

Round 2 (sync-engineer): S1, S4, S6, S7, C1–C4, after T3 lands (one writer at a time in this checkout).
