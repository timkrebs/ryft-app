# RYFT iOS — sync engine, performance and the "processing your data" experience — for Claude Code in VS Code (app/)

You are working on the RYFT iOS app from **VS Code**, not Xcode. That changes the tooling, not the rules
in `CLAUDE.md`:
- Build and test from the terminal: `xcodebuild -scheme Ryft -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
  / `test -testPlan Unit` / `-testPlan UISmoke` (use `scripts/ci-simulator.sh` for the destination). If a
  simulator launch fails in your sandbox, say so and rely on CI for that step.
- Visual checks without Xcode Previews: `make screenshots` (`scripts/screenshots.sh`) and
  `xcrun simctl io booted screenshot` of the app in demo mode; attach before/after images to the PR.
- `Ryft/`, `RyftTests/`, `RyftUITests/` are **synchronized folders** in the project — new Swift files are
  picked up without touching `project.pbxproj`. Never hand-edit the pbxproj; capabilities, entitlements
  and background modes go through the user in Xcode (print the exact steps). `Info.plist` and
  `.xcstrings` are plain files you may edit.
- Branch + PR flow (`CLAUDE.md`, `docs/CI.md`): one branch per section below, `gh pr create`, CI green,
  squash merge. Never commit to `main`.

Read first: `CLAUDE.md`, `docs/STATUS.md`, `docs/ARCHITECTURE.md`, `../plattform/docs/API.md` (Errors,
the changelog entries **Beta** and **Accounts and sync state** of 2026-10-21, `POST /v1/sync`,
`GET /v1/me/sync`, `SyncResponse`), `../plattform/docs/SCORING.md` (how samples are used: one source per
hour for HR and steps, sleep per night), then `CLAUDE_FOLLOWUP_SYNC_403.md` and
`CLAUDE_FOLLOWUP_BETA.md`. Code: `Health/HealthKitManager.swift`, `Environment/HealthStore.swift`,
`Sync/SyncService.swift`, `Sync/SyncCoordinator.swift`, `Sync/ScheduledWork.swift`, `App/RyftApp.swift`,
`App/AppState.swift`, `Persistence/Repository.swift`, `Networking/APIClient.swift`,
`Features/Today/TodayView*.swift`, `Design/StatusViews.swift`, `StateMachines/Machines.swift`.

## What an analysis of the code found (verify each before changing it)

**Blocking, still open**
1. `CLAUDE_FOLLOWUP_SYNC_403.md` was never executed: no `inviteRequired`/`consentRequired`, no
   `GET /v1/me/sync`, no `X-RYFT-Device-ID`, and `APIError.errorDescription` still maps every `401`
   **and** `403` to "RYFT didn't accept your sign-in. Log in again." (`Networking/APIClient.swift:21`).
   The user is stuck behind that message today.

**Sync correctness and background behaviour**
2. **Sleep uploads last.** `HealthStore.streams` = all quantities (heart rate first, then HRV … steps)
   then `.sleep`, `.workouts`. In the morning the app drains a night of heart rate, steps and energy
   before it sends the one thing scoring is waiting for. During the first import that's tens of
   thousands of HR samples before any night.
3. **Going to background cancels the sync.** `RyftApp` `.onChange(of: scenePhase)` → `.background` →
   `coordinator.cancel()`. A user who switches apps during the first import stops it; nothing finishes
   it except a later `BGAppRefreshTask` (≈30 s budget, earliest 2 h later).
4. **HealthKit observers are registered late.** `startObserving` runs inside `bootstrap()` after auth,
   user load and the Health intro. When iOS launches the app in the background for a HealthKit delivery,
   the observer must be registered during launch (`App.init` / `application(_:didFinishLaunching…)`),
   otherwise the wake is wasted; and SwiftUI may not run the scene's `.task` in a background launch.
5. **Observer completion waits for the whole pipeline.** The observer calls `completion()` after
   `coordinator.run(.healthKit)` returns — that includes the upload, up to 3 scoring polls (3 + 6 + 12 s)
   and all refreshes. HealthKit background time is short; a late or missing completion makes HealthKit
   back off deliveries. Complete as soon as the upload is accepted.
6. **Background delivery frequencies.** `enableBackgroundDelivery` registers *every* read type at
   `.hourly`. Sleep, workouts and HRV — the score-changing types — should be `.immediate`; types without an
   observer shouldn't be registered at all.
7. **Locked phone.** HealthKit data is unreadable while the device is locked; a delivery or BG task that
   fires then throws `errorDatabaseInaccessible`, which today becomes a sync failure. No handling exists
   (`grep protectedData` → nothing).
8. **Scored-or-not is guessed with the wrong clock.** `LiveSyncSteps.isScored` compares the server's
   `computed_at` with the *phone's* `started` time; clock skew makes it wrong either way. After three polls
   it gives up silently. The platform now answers this directly (`GET /v1/me/sync` → `today.state`,
   `pending_days`, `expected_within_sec`; `SyncResponse.scoring`) and sends a silent push per scored day.
9. **Deletions are ignored.** Anchored queries return `deletedObjects`; the app drops them, so data a user
   deletes in Apple Health (or a watch app rewrites) stays on the platform. Samples are sent without the
   HealthKit UUID, so the platform couldn't match a deletion anyway (platform request, §5).
10. `URLSessionConfiguration.default` with `waitsForConnectivity = true` and a 300 s resource timeout is
    used for background work too — a background run can sit waiting until iOS kills it.

**Performance**
11. **Sync work likely runs on the main actor.** `SyncService` is `@MainActor`; the target builds with
    `SWIFT_APPROACHABLE_CONCURRENCY = YES`, under which nonisolated async functions run on the *caller's*
    actor. Mapping 20 000 `HKQuantitySample`s and JSON-encoding the page (several MB) then happen on the
    main thread → scroll hitches during a sync. Prove it (Instruments Time Profiler or
    `dispatchPrecondition`/`MainActor.assertIsolated` probes in a Debug build), then fix.
12. **Uncompressed uploads.** A 20 000-sample page repeats `"type"`, `"unit"`, `"source"` in every
    element; gzip shrinks that ~10×. The platform's ingest doesn't accept `Content-Encoding: gzip` yet
    (platform request, §5).
13. **Pages are sized by count, not bytes**, and read → upload is strictly sequential: the next HealthKit
    read could run while the previous page uploads.
14. **High-frequency types are uploaded raw.** Apple Watch writes active energy and steps in tiny samples;
    the platform uses one source per hour for steps and sums energy per day. Per-source hourly buckets
    would cut the payload by orders of magnitude (platform must confirm, §5).

**What the user sees while data is in flight**
15. Today knows only `isRefreshing` and three error states (`TodayViewModel.Status`). There is no first-
    import progress, no "your night is being scored", no "your watch hasn't synced to Apple Health",
    no per-day pending marker. `SyncService.progress` strings are English-only debug text
    ("Reading heartRate…").
16. No home/lock-screen widget (`RyftWidgets` only has the rest-timer Live Activity) — the score can't be
    seen without opening the app.

## 1. Land the account gates and honest errors (unblocks the user)

Do `CLAUDE_FOLLOWUP_SYNC_403.md` §1–§3 now, including its addendum, on branch `fix/account-gates-sync`:
decode `APIErrorBody.code`; `invite_required` / `consent_required` route to the gates, the `X-RYFT-Gate`
response header too (warn mode); a code-less `403` is a permission message; `401` only after refresh;
`OnboardingCoordinator` with invite → consent → about you, decided from `GET /v1/me` + `GET /v1/config`
on every sign-in and app start; `X-RYFT-Device-ID` on every request; `User.account_hint` drives the
"this is a new account" sheet; Profile → Sign-in methods with Apple linking. Mirror the Beta and
"Accounts and sync state" shapes (`SyncStatus`, `ScoringState`, `AccountHint`, `TodayState`,
`SyncResponse.accepted/ignored/scoring`, `DailyScore.scoringState`, `User.accountHint`), fixtures from
`API.md`, tests for the full status matrix. Ship this PR before anything below.

## 2. A sync engine that finishes, in the right order, off the main thread

- **Move the pipeline off the main actor:** a `SyncEngine` actor (or `nonisolated` + `@concurrent` work
  functions) owns reading, mapping, encoding and uploading; `SyncService` stays `@MainActor` only as the
  observable status for the UI. HealthKit mapping and JSON encoding must not run on main — add a Debug
  assertion and a test that fails if they do.
- **Priority order:** streams become `[.sleep, .quantity(.hrvSDNN), .quantity(.restingHR),
  .quantity(.respiratoryRate), .quantity(.spo2), .workouts, .quantity(.heartRate), .quantity(.steps),
  .quantity(.activeEnergy), .quantity(.vo2max)]`. Scoring is triggered per accepted page, so the night
  scores while heart rate still uploads.
- **Fast first score (two-phase backfill):** on a fresh account, phase 1 uploads the **last 3 days** of
  every stream with plain date-bounded queries (no anchor saved — the platform counts identical
  re-sends as `ignored.duplicate`, so overlap is safe); then phase 2 runs the normal anchored 90-day
  backfill. Goal: first Today numbers within a minute of granting Health access.
- **Pipelining:** read page *n+1* while page *n* uploads (bounded to one page ahead), and size pages by
  encoded bytes (target ≤ 2 MB uncompressed / ≤ 300 KB gzipped), keeping the 413 halving as a fallback.
- **Finish when backgrounded:** on `.background`, don't cancel — wrap the in-flight page in
  `UIApplication.beginBackgroundTask`, finish it, commit the anchor, then stop cleanly; schedule a
  **`BGProcessingTask` "backfill"** (`requiresNetworkConnectivity = true`, no power requirement while the
  backlog is < 10 MB, power required above) when a backlog remains. Add the identifier to
  `BGTaskSchedulerPermittedIdentifiers` (`Info.plist`) — the `processing` mode is already there. Cancel
  only on sign-out.
- **HealthKit background delivery done right:** register the observer queries **during launch**
  (`RyftApp.init`, guarded by "signed in and Health access asked"), not in `bootstrap()`; call each
  observer's `completion()` right after the upload step (not after scoring polls and refreshes);
  `enableBackgroundDelivery` with `.immediate` for sleep, workouts and HRV and only for observed types;
  re-enable on every launch (idempotent).
- **Locked device:** catch `HKError.errorDatabaseInaccessible` → state `waitingForUnlock` (not failed),
  resume on `UIApplication.protectedDataDidBecomeAvailableNotification` and on next active. Test with a
  `MockHealthStore` that throws it.
- **Background-appropriate networking:** a second `URLSession` for background runs —
  `waitsForConnectivity = false`, request timeout 20 s, resource timeout 25 s — so a BG task ends before
  iOS kills it; the foreground session keeps today's settings.
- **Server truth instead of guessing:** delete `isScored(_:since:)`'s client-clock comparison; after an
  upload, the coordinator reads `SyncResponse.scoring` and `GET /v1/me/sync`: wait for the silent push
  for the touched days or poll `/v1/me/sync` at `expected_within_sec` (then 2×, cap 60 s, stop after
  5 min) until `pending_days` no longer contains them, then refresh those days. Respect `gate`.
- **Deletions:** collect `deletedObjects` UUIDs per stream and send them once the platform supports it
  (§5); until then, store them per user (bounded) so nothing is lost.
- Persist the engine's state (`stream`, phase 1/2, bytes left estimate, last error with request ID) in
  the user's store so the UI and a relaunch see the same truth.
- Tests on the coordinator/engine with the fake clock and `MockHealthStore`: order, two-phase backfill,
  pipelining bound, background finish, BG processing resume, locked device, observer completion timing,
  silent-push vs polling stop conditions, gate pause/resume, account switch (from the 403 brief).

## 3. Make it feel fast

- **Instruments pass on the user's real data** (ask him to run it on his iPhone, or use the Debug
  scenario seeder from `CLAUDE_FOLLOWUP_BETA.md` §3 in the simulator): Time Profiler during the first
  import and during scrolling Today while a sync runs; record before/after in `docs/STATUS.md`. Add
  `OSSignposter` intervals for read, map, encode, upload, score-wait, refresh, and for cold launch →
  first frame with cached data.
- **Cold start:** Today must render from the SwiftData cache before any network call; move
  `requestAuthorization`, flag refresh, push refresh and Train refresh after the first frame
  (`Task(priority: .utility)`), and run them concurrently. Target: first meaningful frame < 400 ms on the
  user's iPhone (iPhone 17 class) from a warm cache.
- **Read models:** check `Repository`'s memoization is invalidated per key (not globally) on writes, that
  big `DayDetail` blobs decode once per change, and that `AppState.history` isn't re-fetched per view body
  evaluation (Instruments → SwiftUI view body counts). Fix only what measurements show.
- **Gzip uploads** behind a capability check: send `Content-Encoding: gzip` only when the platform
  advertises it (§5, e.g. a `RemoteConfig` field or response header); keep a plain fallback.
- **Hourly buckets for steps and active energy** (and, if the platform agrees, 1-minute averages for
  resting-time heart rate) via `HKStatisticsCollectionQuery` with `.separateBySource`, re-reading the last
  48 h on each sync — only after the platform confirms the contract (§5). Until then, leave raw samples.

## 4. "Your data is on its way" — the in-between states

RYFT's principle is *numbers first, honest uncertainty*: never a blank screen, never a spinner that blocks,
never a number that pretends to be final. Build these states from the engine state (§2) and
`GET /v1/me/sync`, each with previews in dark + light, en + de, and an accessibility label:

1. **First import** (fresh account, from Health access granted until the first scored day): Today shows a
   "Setting up RYFT" card instead of the gauge:
   - a three-step pipeline — *Reading Apple Health → Uploading → Scoring* — with the current step
     highlighted and real counts per category ("Sleep · 87 nights", "Heart rate · 84 213 readings",
     "Workouts · 41"), coverage as days ("Imported through 14 Sep · 61 of 90 days"), not a fake percent;
   - "You can leave the app — RYFT keeps going in the background." and, when push isn't decided yet, the
     push pre-prompt here: "Tell me when my first scores are ready" (this is the moment it makes sense);
   - the phase-1 fast score appears in place as soon as today's day is scored, with the card collapsing
     into a slim progress row under the header until phase 2 finishes.
2. **Calibrating** (after import, < 7 nights of baseline): the gauge with a ring segment per baseline
   night ("Baselines · night 4 of 7") and the sentence the API gives; never an empty gauge.
3. **Morning, night not scored yet** (`today.state` = `waiting_for_sleep` or `pending`): the readiness gauge
   in a **pending** style — outline only, yesterday's value dimmed with its date, label "Scoring your
   night…" with the expected wait from `expected_within_sec`. Next to it, **last night from Apple Health,
   unscored**: asleep time and bed/wake from HealthKit directly, labelled "From Apple Health · not scored
   yet" (raw totals are not a score — the phone still computes no scores). When the score lands: one
   subtle transition, one success haptic, the dimmed value replaced.
4. **Your watch hasn't synced to Apple Health** (newest heart-rate / sleep sample in HealthKit older than
   6 h in the morning or 12 h in the day, from the newest sample date per source): a quiet hint with the
   source's name — "Nothing new from Garmin Connect since 23:40. Open the Garmin Connect app to sync it to
   Apple Health." (Garmin only pushes to Health while its app runs — the most common real-world delay.)
   Generic wording for other sources; the source name comes from HealthKit, never hard-coded brands other
   than as data sources.
5. **One sync status line** under the Today header, replacing `UpdatedLabel`'s role: "Up to date · 2 min
   ago", "Syncing · sleep", "Uploading 12 400 readings", "Scoring your night", "Waiting for you to unlock
   your iPhone", "Offline — will sync when back", "Action needed: agree to the privacy policy" (tappable →
   gate). Localised, short, never a modal.
6. **Per-day markers** in the `DateStrip` and Sleep/Strain day pickers: scored · pending (hollow dot) ·
   no data (none), from `DailyScore.scoringState`.
7. **Sync details** (Profile → Data sources → Sync): engine state, per-stream anchor date and last upload
   counts (`accepted` / `ignored` with reasons), the last 20 requests with status/code/request ID, queue
   and backlog, "Sync last 3 days again", "Full resync", "Copy diagnostics".
8. **Lock-screen and home-screen widget** (new widget in `RyftWidgets`, App Group shared container for a
   small JSON snapshot written by the Repository after each refresh): readiness with state word, or
   "Scoring your night…" in pending state; `WidgetCenter.shared.reloadTimelines` after a new score.
   Capabilities (App Group on both targets) are a user step in Xcode — print it.

## 5. Platform requests (`docs/API_REQUESTS.md`, don't invent fields)

Write these as numbered requests with the motivation and the exact shape you'd like, then tell the user to
paste them into the VS Code platform session:
1. `Content-Encoding: gzip` on `POST /v1/sync` (and how the app learns it's supported).
2. `Sample.id` / `SleepSegment.id` / workout UUID as the HealthKit UUID, plus `deleted: [{kind, id}]` in
   `SyncRequest`, so deletions in Apple Health reach the platform.
3. Pre-aggregated samples: per-source hourly sums for steps and active energy (fields such as
   `agg: "sum"`, `bucket: "PT1H"`), and whether 1-minute HR averages outside workouts are acceptable for
   TRIMP; the platform decides and documents it in `SCORING.md`.
4. Anything the new UI states need that `GET /v1/me/sync` lacks (e.g. per-category counts the server
   holds for the import card) — only if HealthKit-side counts aren't enough.

## 6. Verify and document

On the user's iPhone (ask him to do the steps and report), recorded in `docs/STATUS.md` with screenshots:
1. Fresh account → Health access → Today shows the import card → first score within ~1 minute → leave the
   app mid-import → it continues (BG processing) → push/notice when done.
2. Lock the phone overnight → morning open → "Scoring your night…" with last night's raw sleep → score
   lands within seconds (silent push or poll).
3. Don't open Garmin Connect for a day → the watch-sync hint appears with the source name.
4. Airplane mode during an upload → status line offline → resumes by itself.
5. Instruments numbers before/after (main-thread time during sync, cold start, first-import duration,
   bytes uploaded).

Tests: everything listed in §2, plus view-model tests for each state in §4 (which state wins in which
order), snapshot-free UI tests for the import card and the pending gauge in demo mode.

PRs, in order: `fix: account gates, honest errors` (§1) · `sync: engine off main, priority order,
two-phase backfill` · `sync: background finish, BG processing, HealthKit delivery, locked device` ·
`sync: server scoring state instead of polling guesses` · `perf: launch, read models, signposts` ·
`today: import, pending, watch-sync and status states` · `widgets: readiness widget` ·
`docs: sync and performance status`. Each with before/after screenshots and numbers.

## Done when

- The user's 403 message is gone for good; gates prompt instead of failing.
- First scores appear within about a minute of granting Health access; the 90-day import finishes even if
  the app is left; the night is uploaded before heart-rate backlog; observer wakes complete promptly;
  locked-phone wakes resume after unlock.
- No sync work on the main thread (proved by assertion and Instruments); cold start renders cached Today
  without waiting for the network.
- Every in-between state in §4 exists, is honest about what is scored and what isn't, and is localised.
- `docs/API_REQUESTS.md` holds the platform requests; `docs/STATUS.md` has the measurements.
