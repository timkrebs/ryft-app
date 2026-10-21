# RYFT iOS — fix the 403 after switching accounts, make sync effortless — follow-up for the Xcode session

## What the user saw

On his iPhone (Debug build against production): log out → sign in with email + password →
log out → **Continue with Apple** → the app shows

> RYFT didn't accept your sign-in. Log in again. · HTTP 403 · Request ID 01a15a69-71427a8b-aba2-c099a5fcd1e4

and nothing syncs.

## What is already known (verify, don't assume)

- The platform's **Beta milestone is deployed** (`../plattform` at `21eb0fa`, `docs/STATUS.md` →
  Beta): the invite gate and the consent gate are live. Read `../plattform/docs/API.md` → Errors:
  `403` with `code: "invite_required"` on every `/v1/*` route except `GET /v1/me`,
  `GET /v1/config`, `GET /v1/model`, `POST /v1/me/invite`, `POST`/`DELETE /v1/me/consent`,
  `POST /v1/feedback`, `DELETE /v1/me`; `403` with `code: "consent_required"` on `POST /v1/sync`
  only (reads keep working). Accounts that existed before the gate were backfilled with
  `beta_access`; nobody has a consent yet.
- **The app has none of the Beta client work** (`CLAUDE_FOLLOWUP_BETA.md` §1–§2 never started; no
  `inviteRequired`/`consentRequired` anywhere in `Ryft/`), and `APIError.errorDescription` maps
  **every** `403` — and `401` — to "RYFT didn't accept your sign-in. Log in again." So a gate is
  being shown as an auth failure, and telling the user to log in again can never fix it.
- Most likely sequence: the email account predates the gate (has access, no consent → every sync
  `403 consent_required`). **Sign in with Apple created a second, separate Supabase user** (Apple
  "Hide My Email" gives a relay address, so Supabase doesn't link it to the email account) with no
  `beta_access` → every read `403 invite_required`. Two accounts, two data sets, one person.
- Confirm before fixing: ask the user to run, and paste the output of,
  ```bash
  kubectl -n ryft-api logs deploy/api --since=6h | grep 01a15a69-71427a8b-aba2-c099a5fcd1e4
  kubectl -n ryft-ingest logs deploy/ingest --since=6h | grep 01a15a69-71427a8b-aba2-c099a5fcd1e4
  cd ../plattform && scripts/beta_report.sh          # how many users, which provider, access, consent
  ```
  and record the root cause in `docs/STATUS.md`. If it is something else, fix that instead and say
  so.

Read `CLAUDE.md` (branch + PR flow: work on `fix/account-gates-sync`, never on `main`; the current
branch `test/plans-coverage-contract` has its own PR — don't mix), `docs/STATUS.md`,
`CLAUDE_FOLLOWUP_BETA.md`, `../plattform/docs/API.md` (Errors, Authentication, `GET /v1/me`,
`POST /v1/sync`, the Beta changelog), `../plattform/docs/SUPABASE.md`, then
`Networking/APIClient.swift`, `APIStatus.swift`, `Auth/AuthService.swift`, `Sync/*`,
`Health/HealthKitManager.swift`.

Goal: **the user never sees an error that his own action can't fix, and data reaches the platform
without him thinking about it** — the bar set by the best wearable apps: open the app in the
morning and the night is already there or visibly "being scored", no spinners that block, no
modal errors, account switches that just work.

## 1. Errors that say what is actually wrong

- Decode `APIErrorBody.code` (`APIErrorCode`, unknown → `nil`) into `APIError` and give every case
  its own meaning, in `APIStatus` + tests for the full matrix:
  - `401` → refresh once, retry once, then sign out with reason "session expired" (exists — keep).
  - `403 invite_required` → **not an error**: route to the invite gate (§2). Stop all other calls
    until resolved (one gate, not twenty failed requests).
  - `403 consent_required` → **not an error**: route to the consent gate (§2); reads continue,
    sync pauses.
  - `403` without a code → a permission message for that action ("Built-in plans can't be
    changed"), inline, never "log in again".
  - `429`, `503`, offline → the quiet sync status (§4), never a blocking alert.
- Delete the shared `401, 403` string. Every user-facing error has: one sentence, one action button
  if an action exists, "Details" with status, code and request ID. Strings en + de.

## 2. The gates (pull these forward from `CLAUDE_FOLLOWUP_BETA.md`)

Do `CLAUDE_FOLLOWUP_BETA.md` §1 (mirror the Beta contract) and §2 (invite code → consent → about
you → Health → first import, `OnboardingCoordinator`, resumable, steps skipped when the server
already has them) **now** — they are the fix. Additions:
- The coordinator decides from `GET /v1/me` (`beta_access`, `consent`, `birth_year`) +
  `GET /v1/config` (`privacy_policy_version`) **on every sign-in and every app start**, not only
  on first install — a user who signs in to a different account lands in the right step.
- A gate that appears mid-session (policy version bumped, access revoked) presents as a sheet over
  the current screen, not a reset to Welcome.
- After consent is given: kick a sync immediately and show the first-import progress.

## 3. One person, one account: Apple + email

- After any sign-in, compare `User.provider` and the account's data (`GET /v1/days` last 7 days
  empty, `created_at` within the last minute — add `created_at` to the mirror if the API has it;
  otherwise request it in `docs/API_REQUESTS.md`). If this is a brand-new account **and** this
  install has synced a different user before, show once: "This is a new RYFT account. If you
  already have one with email, log out and sign in with email — then you can add Sign in with Apple
  to it in Profile." with "Use the other account" (signs out) and "Continue with this one".
- **Profile → Account → Sign-in methods:** list the identities (`supabase.auth.user().identities`),
  and "Add Sign in with Apple" for email accounts via Supabase identity linking with the native
  Apple ID token (check the installed `supabase-swift` version for `linkIdentityWithIdToken` or
  the equivalent; if it doesn't exist, use the web OAuth `linkIdentity` flow with the
  `ryft://auth/callback` redirect). Handle "identity already linked to another user" with a clear
  message. Requires **Manual Linking** enabled in the Supabase dashboard (Authentication →
  Settings) — a user step: put it in `docs/STATUS.md` and ask the user.
- Never merge data client-side between accounts.

## 4. Sync that the user doesn't have to think about

Audit `SyncCoordinator`, `SyncService`, `HealthKitManager` against this list and fix what's
missing, with tests on the coordinator (fake clock, fake HealthKit, fake API):

- **Account switches are clean:** on sign-out and on sign-in of a different user — cancel the
  in-flight sync, clear the per-user anchors, caches and SwiftData store of the old user (exists in
  part — verify for both Apple and email paths), re-register push for the new user, reload flags
  and config, then run the gates and a **full 90-day backfill** for the new user. The `device_id`
  stays per install. Test: email → logout → Apple → logout → email leaves no data of one account
  visible in the other, and each ends up with its full history uploaded.
- **Triggers:** app becomes active; HealthKit background delivery (sleep analysis and workouts with
  `.immediate`, heart rate/HRV/steps at the most frequent allowed rate); `BGAppRefreshTask`;
  `BGProcessingTask` for large backfills (requires power, no network cost limit); pull-to-refresh;
  silent push `kind: refresh`; connectivity returning. All coalesce in the coordinator (exists —
  verify priorities: user-initiated beats background).
- **Locked device:** HealthKit is unreadable while the phone is locked (protected data). Background
  delivery that fires while locked must not fail and drop the trigger — catch
  `errorDatabaseInaccessible`, mark "pending", run on `protectedDataDidBecomeAvailable` /
  next active. Test with a fake that throws it.
- **Resilience:** exponential backoff with jitter (cap 15 min) for transport/5xx, `Retry-After`
  for 429/503, page halving on 413 (exists), a persisted upload state so a killed app resumes at the
  last accepted page; anchors persist only after the page is accepted (exists — keep). A gate (§1)
  pauses the queue instead of failing it, and resumes on its own when resolved.
- **Morning flow:** on first open after a night, sync immediately; if the night was uploaded but
  `computed_at` of today isn't newer than the upload, show Today's ring in a "Scoring your
  night…" state (no spinner overlay, numbers of yesterday dimmed with the date) and refresh on the
  silent push or by polling `GET /v1/days/{today}` with backoff (2, 4, 8 … s, max 60 s, stop after
  5 min). The transition to the new score animates once.
- **Status, not alerts:** one small sync status line on Today under the header — "Up to date ·
  2 min ago", "Syncing · 34 %", "Waiting for Apple Health", "Offline — will sync when back",
  "Action needed: agree to the privacy policy" (tappable → gate). Never a modal for sync.
- **Profile → Data sources → Sync details:** last successful upload, records per type in the last
  upload, anchor date per HealthKit type, queue state, the last 20 requests (status, code, request
  ID) from the `APIClient` ring buffer, user id + provider + beta access + consent version (for
  support), "Sync last 7 days again" and "Full resync" (exists — move here), "Copy diagnostics"
  for a bug report.
- **Speed:** the first 90-day import on the user's real data in under 2 minutes on Wi-Fi with the
  app in the foreground; measure page count, records and time once with signposts
  (`OSSignposter`) and write the numbers into `docs/STATUS.md`.

## 5. Verify on the device, then ship through a PR

On the user's iPhone, Debug build against production, in this order — ask the user to perform the
steps and report what he sees; record each in `docs/STATUS.md`:
1. Email account: consent gate appears once → agree → sync resumes → Today shows data.
2. Log out → Apple: either the invite gate (if it's the separate account) with the "new account"
   hint, or straight in (if linked). No "log in again" anywhere.
3. Log out → email → Profile → Sign-in methods → Add Sign in with Apple (after the user enabled
   Manual Linking) → log out → Apple → lands in the **email account's** data.
4. Lock the phone overnight; morning open shows the night or "Scoring your night…" within seconds.
5. Airplane mode → status line says offline → off → sync resumes by itself.

Tests: the status matrix incl. both codes and a code-less 403; coordinator gate decisions for every
combination of `beta_access` / `consent` / policy version; account switch cleanup; locked-device
deferral; resume after kill; backoff timings; morning polling stop conditions. Ask the user to run
the test plan in Xcode (and CI runs it on the PR).

PR `fix: account gates, honest errors, effortless sync` (or split: `fix: 403 codes route to gates`,
`onboarding: invite and consent gates`, `account: Apple linking`, `sync: account switches, locked
device, morning flow, status line, sync details`), with screenshots dark + light, en + de.
