# PR: title and body (to open once gitleaks has run)

**Title:** `networking: the App Attest client and X-RYFT-App-Token`

**Body:**

The app's half of App Attest (platform D245, `API.md` → App Attest, changelog row 2026-11-19). The platform ships its
server part in mode `off`, then `warn` for 7 days, then `on`. This build is the one `warn` has to see.

**What it does**
- `AppAttestor` (actor, `Ryft/Networking/`): one key per account and install, kept in the Keychain
  (`AfterFirstUnlockThisDeviceOnly`, not synchronizable).
  - Challenge → `attestKey` → `POST /v1/app-attest/keys`, then challenge → `generateAssertion` →
    `POST /v1/app-attest/token`.
  - `clientDataHash` is SHA-256 of the challenge's UTF-8 bytes in both steps.
  - The token is kept in memory and renewed with under 300 s of `ttl_sec` left, on a monotonic clock.
  - One renewal at a time; refused requests join it.
- `APIClient.exchange` sends `X-RYFT-App-Token` on every api and ingest request, background runs included. The three
  App Attest routes are excluded, and they join `openBehindInviteGate`.
- Once the routes are known to be served, a request without a token waits up to 3 s for the first one (ADR 0023: D245's
  stop rule counts `missing` lines).

**Refusals**
- `403 app_attest_required`: one renewal, one resend. Refused again: thrown with its request ID, no loop.
- `404 app_attest_key_unknown` (from `/token`): the key is dropped, a new one attested, then the token; once.
- `404` without a code, or `501`: not served. No key, no header; probed again at most every 6 h, across launches.
- `422 app_attest_challenge_invalid`: a new challenge, the same step once.
- `422 app_attest_invalid`: a new key once, then no attestation for 24 h.
- `429`: no token until `Retry-After`.
- `isSupported` false (the simulator): nothing at all, no header.

**Writes are never dropped on it:** Train ops stay queued, activities are transient, an import is held, and a sync
page commits no anchor. The wipe deletes the key ID and the token.

**Entitlement:** `com.apple.developer.devicecheck.appattest-environment` = `production`.
- Apple: "After distributing your app through TestFlight, the App Store, or the Apple Developer Enterprise Program, your
  app ignores the entitlement you set and uses the production environment."
- Apple: "You can test your app during development against the App Attest production servers by setting the entitlement
  to `production`."
- The production platform accepts production attestations only.
- `check-entitlements.py` allows the key and fails on any value but `production`. **The key itself isn't in this PR:**
  the repo's edit hook allows it only through Xcode (see Needs you).

**Docs:** ADR 0023; `docs/work/2026-11-19-app-attest/` (plan, design, review); `docs/API_REQUESTS.md` → App Attest
(AA1–AA4).

**Verified:** simulator only (iPhone 18 Pro, iOS 27.2), with `main` merged in (#126, the Train outbox).
- `make build` with 0 warnings in our code; `make lint`.
- The App Attest suites, three runs green.
- The full Unit plan: 5,634 test cases passed, 3 failed. All three fail on `origin/main` too, on this simulator:
  `FocusedPolishHostedTests/theRPELineTakesItsRoom` and one case each of `TodayTwoUpTileTests/noCaptionIsSqueezedBelow80Percent`
  and `thePairsCaptionsSitAlike`.
- Two reviews (code and security-privacy), fixed in round 2: `docs/work/2026-11-19-app-attest/review.md`. Open as a
  follow-up: S2, refusing redirects off the two hosts (bearer and app token alike).

**Not verified:** a real attestation (needs a device, the entitlement and a server that serves the routes).

**Needs you**
1. **Apple Developer portal:** App Attest enabled on `dev.timkrebs.ryft`.
2. **Xcode → Ryft target → Signing & Capabilities → + Capability → App Attest.** Then open `Ryft/Ryft.entitlements` and
   change App Attest Environment from `development` to `production`. Run `make check-entitlements` (it fails on
   `development`), then commit to this branch.
3. **A device test** (App Attest doesn't run on the simulator). With the server still `off`, expect "not served yet":
   one `POST /v1/app-attest/challenge` → `404`, no `X-RYFT-App-Token` on any request, and no second probe within 6 h.
   Once the server serves the routes, expect one key, one token, and the header on every request.
