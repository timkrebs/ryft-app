# App Attest client (2026-11-19)

Brief: the head architect's "the App Attest client" (2026-11-19). Contract: platform `docs/API.md` → Conventions →
App Attest, Errors → App Attest, the Swift mirror and the changelog row "2026-11-19 | App Attest: the contract, not served
yet (D245)" (platform PR #220, merged). Branch `feat/app-attest` from `origin/main` (305346d). One PR.

**Goal:** the app proves itself to api and ingest with App Attest, so the platform can watch `warn` for 7 days before
`on`. With the server `off` (today: the challenge route is `404`), nothing changes for the user and no header goes out.

## Tickets (one PR, in this order)

| # | Ticket | Owner | Depends on |
| --- | --- | --- | --- |
| T0 | Design note: the attestor's shape, single-flight renewal, account binding, where the header and the 403 retry live, the "not served" backoff, the wipe hook, test seams | ios-architect | — |
| T1 | Wire models + `APIErrorCode` cases + fixture decode tests (from the contract's examples) | sync-engineer | T0 |
| T2 | `AppAttestor` (Networking/), Keychain key store, header in `APIClient.exchange`, the 403-once retry, refusals per code, wipe/sign-out, entitlement + `check-entitlements.py`, one error string | sync-engineer | T0 |
| T3 | Tests from the acceptance criteria (fake attest service, stub URLProtocol) | test-engineer | T2's interfaces |
| T4 | Review: attestation + retry code | code-reviewer (one) | T2, T3 |
| T5 | Review: Keychain, token, logging, entitlement | security-privacy-reviewer | T2 |

`api-contract-keeper` is folded into T1: five structs and four enum cases, all from one changelog row.

## Acceptance criteria (testable)

1. **Happy path:** signed in, `isSupported`, no key → `challenge` → `generateKey` → `attestKey(keyId, SHA-256(challenge
   UTF-8))` → `POST keys` → `challenge` → `generateAssertion(keyId, SHA-256(challenge UTF-8))` → `POST token`; the next
   api and ingest requests (the sync too, in a background run) carry `X-RYFT-App-Token: <token>`. The `keyId` is in the
   Keychain (`AfterFirstUnlockThisDeviceOnly`, not synchronizable) with its account.
2. **Refresh:** with under 300 s of `ttl_sec` left on the app's own monotonic clock, the next request starts a renewal
   (challenge → assertion → token, no new key); never two renewals at once.
3. **403 `app_attest_required`:** one renewal, the request sent once more with the new token; refused again → thrown
   with its `request_id`, no loop. Concurrent refusals wait for the one renewal.
4. **404 `app_attest_key_unknown`** (from `/token`): the `keyId` is dropped, a new key attested, then a token; once.
5. **Not served yet:** `404` without a code, or `501`, from `challenge` → no `generateKey`, no header, no retry before
   the backoff (the next launch at the earliest); a test counts the requests.
6. **Unsupported** (`isSupported` false): no attest request at all, no header, one log line without identifiers.
7. **Refused writes stay queued:** a Train `PUT` / `complete` refused with `403 app_attest_required` stays in the outbox
   (also after the retry is refused); a sync page refused with it commits no anchor.
8. **Wipe and sign-out:** the `keyId` and the token are gone; the next account attests its own key. A renewal in flight
   for the old account never publishes its token for the new one.
9. **422s:** `app_attest_challenge_invalid` → a new challenge, the same step once; `app_attest_invalid` → drop the key,
   attest a new one once; refused again → no attestation for 24 h, across launches (design §4; the contract's "until
   the next launch" made stricter, since a try costs one of the 10 keys a day). `429` → carry on without a token until
   `Retry-After`.
10. **Privacy:** no log line, `APIStatus` record or error text carries the `keyId`, token, challenge or assertion.
11. **Entitlement:** `com.apple.developer.devicecheck.appattest-environment` = `production` in `Ryft/Ryft.entitlements`;
    `make check-entitlements` passes; the widget's entitlements unchanged.
12. Build with zero warnings in our code; unit tests green; UI smoke unaffected (the simulator is `isSupported` false).

## Decisions

- **Entitlement `production`**, in Debug and Release. Apple ("Preparing to use the App Attest service", the entitlement
  page, read through Apple's documentation JSON on 2026-11-19): Xcode's capability writes `development`; "After
  distributing your app through TestFlight, the App Store, or the Apple Developer Enterprise Program, your app ignores
  the entitlement you set and uses the production environment"; "You can test your app during development against the
  App Attest production servers by setting the entitlement to `production`." The production platform accepts
  production attestations only (D245, `APP_ATTEST_ENVIRONMENTS=production`), so a debug build from Xcode must attest
  in production too.
- **The entitlement goes in through Xcode, by the user.** The brief asked for the line in `Ryft.entitlements`, but the
  repo's `pre-edit-guard.sh` hook blocks every edit of that file ("entitlements change only via Xcode → Signing &
  Capabilities → + Capability"), as `CLAUDE.md` says. So this PR only teaches `check-entitlements.py` the key; the user
  adds the capability and sets it to `production` (steps in the PR body). Until then nothing calls Apple: the client
  makes no key before the challenge route answers `200`, and today it answers `404`. What `generateKey` does without the
  entitlement is unverified; the device test after the capability is added covers it.
- **The three App Attest routes join `APIClient.openBehindInviteGate`**: the contract puts them outside the beta gate,
  and under `on` an invite-gated client needs a token to send its invite code.

## Risks

- `fix/train-refusals-kept` (another session, no PR yet) rewrites `TrainSyncService.swift` (+471): keep this PR's
  change there to `isRetryable` only, so the later merge is small.
- Signing: if the portal hasn't enabled App Attest yet, a device build fails at the profile; the simulator build doesn't.
- Apple behaviour the contract marks unverified (DCError cases, background assertions): device test, Needs you.

## Environment (this run)

Refused: `gh api …` (the contract was read from `gh pr diff 220 -R timkrebs/ryft-platform`), reads of `../plattform`,
`git worktree add`, `WebSearch`, `gitleaks version`. So the work is on a branch in the main checkout, and the code-reviewer's
uncommitted memory files there are left untouched and uncommitted. **No push without gitleaks** (the brief).
