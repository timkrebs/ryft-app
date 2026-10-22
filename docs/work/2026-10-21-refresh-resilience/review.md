# Refresh resilience — review log

Reviewers per `docs/AGENT_FLEET.md`. They are read-only. Blockers go back to the owner and are verified again
after the fix. The lead decides on disputed findings, and the reason is written down.

## T3 — `feat/report-a-problem`

### ui-validator (iPhone 17e; dark/light, en/de, AX5) — no blockers
- should-fix: the Details pre-fill state opens with the keyboard up, covering the disclosure → no autofocus.
- should-fix: Send sits below the fold on a 17e. **Lead: accept the scroll** (the form scrolls; a pinned bar is out
  of scope for a stability release).
- nit: the disclosure chevron renders white on iOS 26 (tint ignored). It's app-wide and the same as Sleep's "Why this need".
  → follow-up for ui-designer, not this PR.
- nit: the "What's included" label is smaller than the other row labels → align it.
- nit: de queued copy "Gespeichert. Sie wird gesendet…" has no antecedent → localization-editor.
- nit: the AX5 section header renders very large → cap it at `.accessibility3`.

### security-privacy-reviewer — 2 blockers
- **blocker 1:** the disclosure says "nothing from Apple Health", but `sync_details` (the Copy diagnostics text)
  carries each HealthKit stream's `newest` sample time to the second (sleep end means wake time, workout end), and
  request paths carry `/v1/sleep/plan?wake=06:30`. These also survive a consent withdrawal. → Build the feedback
  diagnostics from structured sources through an **allow-list** (known keys, line templates). Cut sample
  times to the day, and strip query values from paths. Don't reuse the support text as is. *(Lead: this replaces
  design.md §8's seam "T3 sends T1's Copy diagnostics text as is". T1's per-resource state is added to the
  allow-listed renderer at merge, as resource/fetchedAt/status/code/requestID only.)*
- **blocker 2:** account switch. `APIStatus.requests` is never cleared, and the report draft survives
  `auth.accountID` changes, so A's text and requests can be sent as B. → Reset `APIStatus` requests and failures,
  and the report draft, on account change.
- should-fix 3: queued reports aren't bound to an account (an in-flight flush across a switch; queued while signed
  out, then flushed as B). → Store `accountID` in `QueuedFeedback`, flush only matching items, check again per post,
  and don't queue when signed out.
- should-fix 4: the disclosure doesn't match the payload (the install ID, locale and timestamps are sent but not
  listed; duration and per-resource are listed but not sent). → Make them match exactly. Drop the install ID unless it's
  needed (lead: drop it, since the request IDs identify the requests).
- should-fix 5: the "no health values" test is weak (empty engine, ints < 60 skipped, no `?wake=`). → Seed streams
  with sample times, add a `?wake=` request, and assert the structural allow-list.
- should-fix 6: the privacy manifest lacks `NSPrivacyCollectedDataTypeOtherDiagnosticData` (linked, not tracking,
  App Functionality), and the docs disagree. → Fix the manifest, `APP_STORE.md` and `APP_STORE_METADATA.md`.
- nit 7: "Copy message" → a `.localOnly` pasteboard with an expiry.
- nit 8: demo says "reached RYFT" → say "(demo)"; sign-out drops queued reports silently → say so on sign-out, or
  in the queued copy.
- nit 9: "Customer Support" isn't an Apple purpose → App Functionality.
- Needs the user: App Privacy → Diagnostics → Other Diagnostic Data (linked, no tracking, App Functionality);
  ryftapp.de/privacy → a "Problem reports" section.

### code-reviewer — no blockers (zero warnings, `make lint` clean, tests pass)
- should-fix 1: `flush()` iterates a stale snapshot, so a report sent while a flush runs is posted twice (and it re-posts items
  `send()` dropped after 429/422) → re-read the queue before each post; add a concurrent send+flush test.
- should-fix 2: the `requests` key duplicates the requests block in `sync_details` → resolved by security blocker 1's
  allow-listed renderer (one requests list, no raw support text).
- nit 3: category isn't reset after sent/queued → reset to `.other`.
- nit 4: with diagnostics off, the chip still shows the request ID that isn't sent → hide it while the toggle is off.
- nit 5: = security blocker 2.
- nit 6: JSON encode for the size check on the main actor (≤ 32 KiB) → accepted for now (one small encode).
- nit 7: a timeout after the server stored the report re-queues it → idempotency key → `API_REQUESTS.md` (T4).

### Lead: fix batch sent to the T3 owner
Security blockers 1–2, should-fix 3–6; code-review should-fix 1, nits 3–4; ui-validator: no autofocus, label size,
AX header cap, de queued copy ("Deine Meldung ist gespeichert und wird gesendet, sobald du wieder online bist."); security
nit 7 (local-only pasteboard) and nit 8a (the demo send says so). Not taken: security nit 8b (sign-out wiping queued
reports is the privacy-correct behaviour; the privacy policy says so); CR nit 6.

## T2 — `fix/today-consistent-state`

### ui-validator (iPhone 17e; dark/light, en/de, AX3) — no blockers; one decision
- should-fix 1: **row B with `needsVitals`** still shows "Baselines 0 / 7" with an empty ring beside a scored day's
  tiles (7h 17m, 75 %, 0.9), which is too close to the TestFlight bug. **Lead decision (amends plan decision 2):** when
  history isn't short (`prior.count ≥ 7`) but `vitals < 7`, the gauge shows **today's readiness** if the platform
  computed one, with `Note.needsVitals` under it, and the tiles show today's values without the "calibrating" caption (the note
  explains it). Only when there's no readiness does it fall back to the baselines gauge, and then the caption counts
  "nights with heart-rate data", never a bare "nights". Row B with "n of 7" stays for genuinely short histories.
- should-fix 3: the status line truncates at AX3 in German ("Demodaten · Aktuell · gerade…"). The line is T1's → sent to T1.
- should-fix (lead): the raw-night card shows "11:17 PM" under German. This predates the PR (`Fmt.time`, `TodayView.swift:377`),
  but it's on the row C screen this PR touches, so it gets fixed here with locale-aware time.
- nits: row B's "—" tiles with "calibrating" (scenario data, no change); AX3 row C pushes the gauge below the fold
  (acceptable); row D tile captions at different heights (shipped layout); "Bereitschaft vom Di. 20. Okt." plus
  "Gestern" (fine).
- UI-4 resolved: the two sleep figures in row C read as two days (a date caption plus "not scored yet"). Kept.
- UI-6 resolved: the dimmed values are legible in light mode (4.91:1).
- Not verified by the validator: the Trends card render, AX3 tile stacking, Reduce Motion, rows A and E.

### code-reviewer — approve after finding 1
- should-fix 1: row C's sentence always says "Yesterday's readiness…", while the gauge and tiles show the real date of
  `latestPrior` (a gap day after a night without the watch) → "Readiness from %@, until last night is scored." when it
  isn't yesterday; add a gap-day test.
- nit 2: the widget writes `previousReadiness: nil` on `.baselines`/`.readiness(nil)` (main wrote the latest prior) → expose the
  source day's readiness on `TodayPresentation` and write it.
- nit 3: about 40 `facts` builds per body, each with an uncached `detailFetchedAt` SwiftData fetch → memoize it under `.days`, and
  read `model.presentation` once per body. (Lead: take it; it's cheap and the perf profiler isn't on T2.)
- nit 4: `TodaySyncFacts.previous` is unused (T1 doesn't use it either) → delete.
- nit 5: row E's test never reaches the `row != .firstImport` clause → add a case with the backfill done.
- nit 6: deviations 1, 2 and 6 amend design.md/ui.md → errata in T4 (lead).
- The deviations are accepted. The decision table, `vitals`, the unknown-day audit, the widget JSON and the dates are checked and sound.
- The merged result (`0c39e56`) was rebuilt by the lead: Unit plan green on iPhone 17.

### Lead: fix batch for the T2 owner
ui-validator should-fix 1 (the `needsVitals` amendment above) and the `Fmt.time` locale fix; code-review 1–5.

## T3 re-verification (PR #26)

### security-privacy-reviewer — blockers 1 and 2 resolved; should-fix 3, 5 and 6 and nits 7 and 9 resolved
- partly (should-fix 4): the install ID still goes out in `POST /v1/devices/<install-id>/push` (sent after every sign-in). →
  `FeedbackPayload.path` templates UUID segments as `{id}`; the test seeds the push and workout paths. **Taken before merge.**
- new, low: a request of account A still in its 503 retry loop can be recorded into B's list after the switch → an epoch
  in `APIStatus.forgetRequests`. **Taken** (small).
- pre-existing, low: Sync details → Copy diagnostics uses the plain general pasteboard (it has Health times to the second) →
  `.localOnly` plus an expiry, the same as "Copy message". **Taken** (same file, one line).

### code-reviewer re-verification — approve; earlier should-fixes 1 and 2 and nits 3 and 4 resolved; merge resolution clean
- should-fix (low): the same late-response leak as security's new finding → the epoch fix (taken).
- nit: the race test would hang rather than fail on a regression → advance the clock or add `.timeLimit`; add an account switch
  during a flush (taken).
- localization-editor: no edits needed; tone, du-form, "Meldung" and plurals all fine.
- Final batch landed in 0bf1c7d (pushed): `{id}` in report paths, the `APIStatus.epoch` (it moves only when an account is
  *left*, so a first sign-in's own gate responses aren't dropped; lead accepts), `LocalPasteboard` for both copy actions,
  and non-hanging race tests plus a switch-during-flush test. Affected suites: 94/94.

## T1 — `fix/refresh-per-resource` (PR #27)

### security-privacy-reviewer — no blockers; 2 should-fix
- should-fix 1: a read while signed out (a silent push after session expiry → `refreshTrends`/`refreshInsights`) records
  `.signedOut` with `account == nil` and persists it. On the next sign-in (nil → account doesn't reset), Today shows "You're
  signed out", and its Sign in button signs out a valid session. → `ReadScheduler.run` guards `isDemo || isSignedIn`;
  never record with `account == nil`; `reads.reset()` on every account change; store the account ID in `reads.state` and
  ignore a mismatch on load. **Taken.**
- should-fix 2: Copy diagnostics and the Sync details request rows print raw paths (`?wake=06:30`, install ID, UUIDs). T1 also
  records transport and cancel now, and the line links to Sync details. → One shared `redactedPath` (query stripped, UUIDs →
  `{id}`), used by Sync details, Copy diagnostics and (after #26 merges) `FeedbackPayload.path`. **Taken.** The lead unifies
  it with #26's at merge.
- nit 3 (pre-existing): `APIClient` logs `path` with `.public` → log the redacted path. **Taken.**
- nit 4: the 429 hold-back is per resource, but the per-user and edge 429s are global → a shared not-before in `RequestBudget`
  after any 429 (honouring `Retry-After`, capped). **Taken** (the brief: "respect the platform's rate limit").
- nit 5: Supabase refresh errors that don't end the session (5xx, 408, 429, `refreshDiscarded`) are classed `.other` →
  `transient`. **Taken.**
- Sound: 401 semantics, a 503 never signs out, no stale tokens, a single retry layer, the stored state has no body, path or PII,
  the wipe covers sign-out, switch and deletion, signposts are fine, and the fault seam is fully `#if DEBUG` and only in the
  demo API.

### T2 fixes (026cab2…c907f2b, PR #28): Unit plan 603/603, zero warnings
- Row B + `needsVitals`: readiness and note, today's tiles without "calibrating", no delta. Without a readiness: the baselines
  gauge counting heart-rate nights ("n of 7 nights with heart-rate data", German plural on the total). The widget agrees.
- "11:17 PM": the simulator had 12-hour time forced. `Fmt.time(locale:)` now follows the screen's locale; the script shoots
  German with `-AppleICUForce12HourTime NO`.
- The row C gap-day sentence names the date; `previousReadiness` is in every widget kind; `detailFetchedAt` is memoized; one
  `TodayContent` per body; `previous` deleted; row E backfill-done case added.
- The delta only beside a real readiness: the implementer kept it to **row A only** (a calibrating or borrowed number has no
  fair comparison). **Lead accepts.**
- The gauge caption and `DeltaLabel` wrap at AX3 in German.
- Lead looked at `today-row-b-note-light.png` and `today-row-c-dark-de.png`: one story per screen.
- localization-editor (#28): no changes needed; terms (Ausgangswerte, Bereitschaft), dative plurals and du-form are fine.

### code-reviewer (#27) — 3 blockers
- **blocker 1: data loss.** `APIClient` now rethrows `URLError.cancelled` as `CancellationError`. `TrainSyncService` (L138–149) keeps
  only retryable `APIError`s and drops everything else, so a flush cancelled by Finish or a new set dequeues the PUT, the next PUT
  and `.complete`. The workout never completes on the server. → `catch is CancellationError { return }` (keep the op) and a test.
  The lead adds: audit **every** caller of `APIClient`/`PlatformAPI` that classifies errors (Train, journal, push, bedtime,
  onboarding, consent, invite, patchMe, feedback) for the same change in kind.
- **blocker 2: CI Lint is red.** SwiftLint `empty_count` at `RyftTests/SyncCoordinatorTests.swift:1231`. (The lead's PR body said
  "make lint clean", which is true but isn't CI's SwiftLint. Corrected in the PR.)
- **blocker 3: a cancelled caller can't stop waiting.** `ReadScheduler.run` waits on `task.value`, so the onboarding 10 s timeout,
  the silent push's 25 s cut-off (iOS ~30 s) and `windDown` overrun. → Per-flight waiter continuations, resumed with
  `CancellationError` on the caller's cancel, while the flight keeps running for other joiners. Store the result in the flight,
  not in the first caller's closure (`refreshUser` joining onboarding's `.me` flight never stored the user). Add tests.
- should-fix 4: reads go out and are recorded while signed out after a reset. This is the same as security should-fix 1; one fix
  (guard in `run`, `reset()` cancels the pull's tasks, reset on every account change, account-bound state).
- should-fix 5: migrating from nothing makes history look never loaded on the first launch of this build. → History's
  `fetchedAt` comes from the store (newest `scoreFetchedAt`), like today's; add policy-table rows.
- should-fix 6: merge with #26's `APIStatus.epoch`. T1's transport `catch` calls need `epoch:`. The lead does this at merge, plus
  a test that `forgetRequests` then `cancelAll` leaves `requests` empty.
- should-fix 7: tests. A 50 ms real sleep in `SyncCoordinatorTests:979` (flaky) → poll. `ViewModelTests:1404` asserts before
  phase 3 → await `pullPhases`. Missing design §11 `RefreshResilienceUITests` in UISmoke → **the test-engineer writes it**
  after the fixes, together with the card/sheet content tests and the 600 ms debounce.
- nits taken: 8 (`refreshStatus` in a pull is user-initiated), 9 (a decode failure on a 200 keeps status 200 and the request
  ID), 10 (a cancelled request isn't shown as a warning, and isn't counted among the report's 20), 11 (`resendRecent` reloads
  the queue after the upload ends).
- Sound: `RequestBudget` (no leaks or deadlock), retry classification and jitter, `singleAttempt` coverage, `RefreshPolicy`, pull
  phases, persisted state, the fault seam, the xcstrings merge.

### code-reviewer re-verification (#28) — approve; every earlier finding resolved
- Follow-ups (not blocking, carried to STATUS → open):
  - the widget says "Waiting for last night · Last readiness 76" for a scored day without readiness, while Today shows
    "—" (same as main; the widget JSON has no kind for it);
  - `DeltaLabel` now wraps in Trends/detail headers too (probably better; take an AX3 screenshot);
  - `lint-strings.py` doesn't check `%#@token@` substitutions or English plurals;
  - a direct Repository test for re-fetching `detailFetchedAt`.

### CI (#27, run 39695249665) — red
- Lint: SwiftLint `empty_count` at `SyncCoordinatorTests.swift:1231` (= code-review blocker 2).
- UI smoke: `StoreSmokeUITests.testDemoTabsWalkthrough` → "Failed to terminate dev.timkrebs.ryft". The retry passed, but the step
  fails. Not seen on #26. Suspect: code-review blocker 3 (cancellation-blind waits, e.g. `windDown` on background/terminate) keeps
  the app from terminating. → The T1 owner proves or rules it out (reproduce UISmoke locally after the fixes); flake only with
  evidence.
- The unit tests passed in CI.

### ui-validator (#27, iPhone 17e) — no blockers
- should-fix: nothing points to the card when it's 3 screens down (nothing cached) → the line reads "Couldn't load today · Details"
  and tapping it scrolls to the card; the card stays last (lead accepts).
- should-fix: Details sheet: the request-ID row splits across lines; "Time" shows "2:17:12 AM" under German; "Send to RYFT" isn't
  visible at the opening detent → one row, locale-aware time, primary action reachable (hidden until #26 wires it).
- nits: a ~60 pt gap under the card's buttons; the status-line icon should align to the first line at AX3; check 44 pt targets.
- Copy matches ui.md §3.5 in en and de. Loaded data is in the right order.
- Not verifiable in demo: the stale line (needs data older than 2 h), the 3-failure card with cache, warning rows.

### Lead: fix batch sent to the T1 owner
Code review blockers 1–3, the CI UI-smoke terminate failure, should-fixes 4–7 (with security 1), security 2–5, ui-validator 1–4,
and nits 8–11. The merge seams with #26 apply only if it's on main by then. The test-engineer follows with
`RefreshResilienceUITests` (design §11) and the card, sheet and 600 ms tests.

### T1 fixes (cd43ab2..f3403b3, pushed): Unit plan 632/632, zero warnings, SwiftLint clean, Release builds without the seam
- Train: the upload runs in a task the service owns, so Finish or a new set cancels only the debounce; a cancelled PUT keeps its op.
  A caller audit of cancellation handling covers Train, journal, push, sleep plan/bedtime, onboarding, `patchMe`, Profile and
  notification settings.
- Reads: per-caller continuations (a cancelled caller is released at once); the store happens inside the flight; signed out →
  nothing is sent or recorded; the record is account-bound and reset on every account change; history's age comes from the store;
  a global 429 hold (≤ 30 s); `redactedPath`; cancellations are counted, not listed; a decode failure keeps status and request ID;
  Supabase refresh errors are transient.
- UI 11a–g done ("Couldn't load today · Details" scrolls to the card; Details row; locale-aware time; Send to RYFT hidden until
  wired; spacing; icon; 44 pt).
- **CI "Failed to terminate": a flake, with evidence.** XCTest waited on pending crash logs (simulator system processes, PosterBoard)
  in a NotificationsUITests tear-down; the spindump shows the app idle; the same wait happens on a #26 build; UISmoke passes
  locally 3/3. Lead accepts, pending the code reviewer's read of the evidence.
- Re-verification running: code-reviewer, security-privacy-reviewer, performance-profiler (static), and test-engineer
  (`RefreshResilienceUITests`, card/sheet/hold tests).

### performance-profiler (#27, static: no traces, the disk is full) — 5 should-fix
1. Observation granularity: `AppState.isLoading`/`resourceStates` read the scheduler's whole `inFlight`/`states`, so every read (even
   journal/config/Train) invalidates Today 3× (~10–15 body passes per pull) → `@ObservationIgnored` dictionaries, publish
   derived values (`isLoadingToday`, `issue`, `staleSince`) only on change.
2. SwiftData fetches in `body`: `resourceStates` runs `detailFetchedAt` plus a sorted `FetchDescriptor` per call, 3–6× per pass →
   compute once per state change or revision.
3. `persist()` encodes, fetches and saves on main for every final failure and every success > 60 s (~6 per pull, 10–30 ms bunched)
   → coalesce to one save per 1–2 s, encode off main, drop the 60 s trigger where SwiftData rows own `fetchedAt`.
4. Background: the global 429 hold (≤ 30 s) plus background retries of timeouts can push a silent push to ~80 s (iOS ~30 s) →
   in the background cap the hold at the background `retryAfterCap` or skip; don't retry `timedOut` in the background; add a
   ~20 s deadline around the silent-push refresh.
5. Signposts: `pull` ends at the 3 s cap (true by construction) → add `pull-total` (until phases end), `pull-gate`, and a `store`
   interval around `flight.store`.
- nits: `reads.state` loads in the first frame (~1–3 ms; measure); the 600 ms hold is fine.
- Network shape: a typical pull is ~1–3 s, faster than before (the old path waited for scoring, then fetched twice). Keep `me` in
  phase 3, per the brief.
- **Lead: 1–5 taken** for #27 (stability release, and the 25 s and 33 ms budgets are the point). The batch goes to the T1 owner after
  the test-engineer is off the branch. The device Instruments recipe goes to STATUS → Needs you.

### security-privacy-reviewer re-verification (#27) — should-fixes 1, 2 and nits 3, 5 resolved; nit 4 partly; 1 new
- new should-fix: the Train replay task outlives sign-out. A PUT/complete keeps resending A's still-valid JWT through
  429/503 retries (up to ~2.5 min, A's own data only). A late Finish sets A's summary and Health export over B's session, and
  `perform(.complete)` writes to a wiped `LocalSession` → `TrainSyncService.accountChanged()` cancels `replay`/`debounceTask` and
  clears state; check the account (generation) after each await in `drain`, `perform` and `TrainCoordinator.finish`. **Taken.**
- low: on the last try, `await budget.holdBack` sits between the account guard and `failed()` → check the account and cancellation
  again after it. **Taken.**
- low: the hold is set after `budget.release()`, so one parked read can slip through → set the hold before release. **Taken.**
- low: writes and uploads don't honour the global hold. **Follow-up** (`/v1/sync` and session PUTs have their own budgets per API.md).
- At merge with #26 (lead): `LocalPasteboard.copy` for Copy diagnostics *and* the Details sheet's Copy details; one path-redaction
  function; `forgetRequests()` zeroes `cancelledCount`. Copy diagnostics keeps second-precision times (it's support text the user
  sees before pasting, and precise times diagnose sync), now local-only. **Lead decision.**

### code-reviewer re-verification (#27 at f3403b3) — blockers 1–3 and should-fixes 4–7 resolved; nits 8–11 resolved; 3 new should-fix
- new should-fix 1: the audit missed Strain and Sleep. Their `.task(id: lastUpdated)` loads now receive `CancellationError` on
  restart and show "The operation couldn't be completed (CancellationError)" → `catch where error.isCancellation { return }`. **Taken.**
- new should-fix 2: Finish can sit for ~5 min with nothing drawn (round 2 of the replay ignores connectivity; `waitsForConnectivity`
  plus a 300 s resource timeout) → cap Finish's wait (≈10 s, then "will sync"), `while flushAgain && isOnline`, and show `isFinishing`.
  **Taken.**
- new should-fix 3: the global 429 hold ignores the foreground `retryAfterCap`; a pull or Try again waits up to 30 s under "Updating…"
  → if the remaining hold is longer than the policy cap, fail at once with the 429 (existing card and `retryNotBefore`). **Taken**
  (together with perf 4 for the background).
- nits taken: an already-cancelled caller doesn't start a flight; a signed-out `.me` card's line wording; drop the dead `offersRetry`;
  `refreshTrain` on foreground doesn't wait for the whole replay. At merge: `LocalPasteboard` for Copy details (lead).
- Flake verdict accepted with a correction: the stall was `NotificationsUITests` waiting on pending crash logs (ReportCrash blocked
  on CoreAnalytics); StoreSmoke's terminate failure was the previous test's app. The confirmation is UI smoke on f3403b3.

### CI (#27 at f3403b3, run 39704400045) — red again, a different UI test
- `TodayStatesUITests.testPendingNightShowsTheOutlineGaugeAndLastNightUnscored` exceeded its 1-minute allowance. Lint is green now.
- That makes two runs with two different UI tests hanging, only on #27 (#26 and #28 pass UI smoke). **Lead: the flake verdict is
  withdrawn pending evidence.** Hypothesis: T1's Today line (600 ms hold and cross-fade, the pulsing "Updating…") or a read that
  never finishes in demo keeps the app from going idle for XCUITest. → The debugger works from the CI xcresult (no local build
  while the test-engineer holds the branch).
- **debugger (from the CI xcresults, no local build): runner infrastructure, ~85 % confidence; the app is cleared.**
  - In both runs the test body passed (~12 s; `didFinishWithStatus:passed`) and the app was quiescent and idle in its run loop.
  - XCTest's post-test "synchronizing with crash reporter" (timeout 300 s) then stalled. ReportCrash was stuck in
    `OSAStabilityMonitorEvaluateStabilityForBundleID` → Trial (run 2) or CoreAnalytics XPC (run 1), so the 1-min allowance expired.
  - Test durations are no slower than on passing PRs, and the app never crashed.
  - Flake verdict reinstated, with the cause. The lead re-ran the failed job (attempt 2) to confirm.
  - Follow-up (CI, not this PR): UISmoke `-retry-tests-on-failure -test-iterations 2`, and test-plan allowances 180/300 s.

### test-engineer (#27): 2655123, c96596c (not pushed; ride with the final batch)
- Unit: card reason per class, Details rows, Copy details, the line's wording per resource, the line tap scrolling to the card
  (vs. Sync details), and a 503 → card model. UI (UISmoke): `RefreshResilienceUITests` (a) a 429 on `/v1/me` stays silent and the line ends up to
  date; (b) nothing cached plus 503 → line → scroll to card → Details with a request ID. 3/3 local runs.
- Product findings → T1 final batch: the container identifiers on the card and the line hide their buttons from the accessibility
  tree (a VoiceOver reachability risk).
- Not testable without a product change: the 600 ms hold (`@State` plus `Task.sleep`, not `AppClock`). Follow-up.

### Lead: final T1 batch sent
Perf 1–5; Train account change; guard after the hold; hold before release; Strain/Sleep cancellation; Finish wait cap; 429
fail-fast past the cap; nits; card/line accessibility containers.
- CI re-run of f3403b3 (run 39704400045 attempt 2): **green**, so the runner flake is confirmed.

### T1 final batch (f3403b3..763f65e): 652 unit, UISmoke 6/6 local; code-reviewer final re-verification: **approve**
- Items 1–13 are resolved. Perf 3 is partly resolved (no flush of the coalesced save on background or before a silent push's
  completion handler). Today's invalidations per pull went from ~20 to ≤ 4 (tested).
- Low should-fix A: the Train generation moves in `.onChange`, one runloop after `AuthService.apply` wipes the store, so a late
  `/complete` could write into a deleted `LocalSession` (a SwiftData trap risk). → Bump it in the wipe path. **Taken.**
- Low should-fix B: flush pending read-state saves before the silent push completes and on background. **Taken.**
- Tests: `anAccountChangeStopsTheReplay` can't fail as written; `finishWaitsAtMostItsCap` should assert one `/complete`; the
  silent-push deadline test needs `.timeLimit`. **Taken.** The three short real sleeps only bound absence checks; accepted.
- CI on 763f65e (run 39709194784): UI smoke red again (StoreSmoke walkthrough exceeded 1 min); third hit on #27 only. Flake verdict reopened; the debugger is reading the xcresult (which process ReportCrash is reporting on; is any extension crashing on this branch).
- **debugger, third hang: infra, ~80 %.** A starved CI VM ran the walkthrough ~3× slow; there was no crash-reporter stall this time;
  ReportCrash was idle; no Ryft or extension crash; no extra log volume from #27. The T1 owner reports local walkthrough timings
  to rule out added accessibility/main-thread cost.
- **Lead: CI PR #30** `ci: UI smoke tests get 180 s before they count as hung`. UISmoke already retries on failure, but a
  time-allowance kill fails the run even when the retry passes; the allowance goes from 60 s to 180 s. Separate from #27 so it can
  be judged on its own.

## Integration (lead): `feat/refresh-report-seams` = main + #26 + #28 + #27
- Dry run: #28 onto #26 conflicts in xcstrings and `screenshots.sh` (union); #27 onto #26+#28 conflicts in xcstrings and
  `APIClient.exchange` (T1's version plus #26's `epoch:`). All resolved; the epoch is also on T1's transport-failure `record`
  plus a new `APIStatus.cancelled(epoch:)`; `forgetRequests()` zeroes `cancelledCount`. `lint-strings` clean.
- T5 `feat: send a refresh problem to RYFT` (T3 owner): Send to RYFT wiring, `$singleAttempt` for `postFeedback`, one path
  redaction, `LocalPasteboard` for both copy actions, per-resource `resources` and request durations in the report.
- CI after the final T1 batch (96d0421): **green** (unit + UI smoke 23 min). #30 green.

## T5 — `feat/refresh-report-seams` (draft PR #31)

### security-privacy-reviewer — no blockers; should-fixes taken
- The disclosure rows must name the error code (`report_context`) and say "Loaded data, per area (Today, History, Profile …)"
  instead of "per data source" (which reads like Apple Health or Garmin). en + de.
- `PrivacyInfo.xcprivacy` comment and `APP_STORE_METADATA.md`: add the per-area last-load time with status, code and request
  ID, and request durations. **Lead decision:** request durations count as **Other Diagnostic Data** (network-diagnostic timings
  for support), not Performance Data (Apple's examples are launch time, hang rate and energy). The reasoning goes into the
  metadata doc; no new App Privacy type.
- **The epoch doesn't stop a retry.** A request of account A waiting out a 503/429 across sign-out plus sign-in as B could, on a
  401, refresh to B's token and resend A's body as B. → `guard await status.epoch == epoch else { throw CancellationError() }`
  after each retry sleep and before the token refresh in `exchange`. **Taken in T5** (it touches the merged `exchange` anyway).
- CHANGELOG: a line for Send to RYFT from Details.
- Sound: the `resources` lines have exactly 5 fields; `fetchedAt` is the app's load time (disclosed); durations are not a
  side channel; diagnostics off sends neither; the prefill and chip are fine; `LocalPasteboard`; redaction is unchanged.

### code-reviewer (#31) — merges lost nothing; approve after should-fix 1
- should-fix 1: Send to RYFT passes raw transport tokens ("timedOut", "signedOut") as status into the chip and `report_context` →
  `issue.statusText ?? "No response"`; test. **Taken.**
- nits taken: "per data source" wording (same as security); resource error IDs in `request_ids` (dedup, ≤ 20); size-cap tests for
  the new trimming order; `singleAttempt` doc comments; CHANGELOG lines.
- Pre-existing, taken here (same function): a cancelled 503 wait never calls `finishedWaiting()`, so "RYFT is catching up…"
  sticks; `forgetRequests()` clears it too.
- Merge resolutions verified line by line across the 14 multi-branch files; xcstrings keep every tip's value; `screenshots.sh`
  is a correct union.

### T5 fixes (ea6f2bc..60b55de, pushed): affected suites 96/96, `RefreshResilienceUITests` 3/3, lint clean
- `exchange`: every retry step (429/503 wait, 401 refresh, final 401) runs through `retryStep` with epoch checks before and after,
  so A's body is never resent with B's token, and a late final 401 of A can't sign B out. `finishedWaiting()` runs on every throw;
  `forgetRequests()` clears the notice.
- "No response" instead of raw transport names; resource error IDs in `request_ids`; cap-order tests; disclosure wording
  en/de; privacy-manifest comment and `APP_STORE_METADATA.md` (durations count as Other Diagnostic Data, with the reasoning);
  CHANGELOG lines. Screenshots of the disclosure re-captured.
- Auth-critical, so the security-privacy-reviewer re-verifies `20883f0`. CI on 60b55de is running.
- **security re-verification of 20883f0: resolved.** No path resends A's request with B's token; same-account 401 semantics are
  unchanged; a first sign-in is unaffected; `finishedWaiting()` runs on every exit. Durations as Other Diagnostic Data confirmed.
- Follow-ups (low, `AuthService`, pre-existing): `token()` signs out on a session-ending refresh error without checking whose
  session it is (a slow refresh of A across a switch to B); move `forgetRequests()` into `AuthService.apply` to close the one-render
  gap. Plus a test for 401 refresh across `forgetRequests`.
- Lead fix: `LateReplyURLProtocol.reset(_:)`, so a retried test starts from zero (ReportProblemTests green locally).

### CI pattern (lead, honest tally)
- UI smoke went red on the 60 s allowance in **4 of 7** runs of branches that contain #27 (#27: cd43ab2, f3403b3, 763f65e;
  #31: 31b025c), and in **0 of 4** without it (#26 ×2, #28, #30). Re-runs and later commits passed (f3403b3 re-run, 96d0421,
  ea6f2bc).
- Each red run was read from its xcresult: crash-reporter sync stalls (2) and a starved runner running the walkthrough ~3× slow (2).
  App CPU stays low, nothing crashed, and local per-tab timings with and without #27 match within ±0.2 s.
- **Most likely:** #27 adds a little accessibility-tree and background load that only matters on a starved 3-core CI VM. **Not
  proven either way.** Mitigation: **#30 (allowance 180 s), merged first.** If UI smoke still flakes on `main` after #30 and #27,
  run the walkthrough on CI 10× with per-tap timings (`-test-iterations 10`) for a T1 build vs. a main build. That's a follow-up
  in STATUS.
- #31 re-run (attempt 2): **green**. All five code/CI PRs are approved and green.

### Merges (2026-10-22)
- #26 merged (c34bb9a) on the user's go. `main` was then merged into:
  - **#28** (082f927): tree identical to integration 064950f. CI **green**.
  - **#27** (a962b1b): `APIClient` + `APIStatus` from integration 776bb7c, strings per key. Its delta matches the
    integration's line for line; local build clean. CI: unit tests green, UI smoke red, `testDemoTabsWalkthrough` over 60 s,
    and again on the re-run (attempt 2). With #27 that makes 4 of 9 runs.
- **CI tally corrected.** Across the last 35 runs, the walkthrough passes in 30–55 s without #27 (19 runs) and 33–42 s with it
  (5 passing runs); it timed out in 3 of 8 runs with #27 and 0 of 19 without.
  - The nightly Full run on `main` (39726928969, ebad505, without #27) also timed out at 60 s, in
    `TrainSessionUITests.testLogTwoSetsSurviveKillAndFinish`. So "only with #27" is not true.
  - Today's red run was a starved runner: every step from the third tab on took 2–9 s, 91 s in total, and the same runner then
    couldn't resolve GitHub's artifact host (`ENOTFOUND`), so there is no xcresult.
  - `retryOnFailure` doesn't retry a test that timed out: xcodebuild restarts the runner and goes on with the next test.
  - **Decision:** #30 now raises both UISmoke and Full to 180 s. Merge it before #27.
- **Why only the lookups were slow.** In the two red runs on a962b1b, XCUITest's element lookups took 15–30 s per walkthrough
  ("Find" plus "Checking existence"), against about 1 s in passing runs. "Wait for idle" stayed at its usual ~15 s. That pointed
  at the app's main thread or accessibility tree, so the lead asked performance-profiler to prove it or rule it out.
- **performance-profiler: runner-only.** The baseline was c34bb9a (#26 only), which differs from a962b1b by exactly #27. Each
  build ran 5× unloaded and 5× CPU-starved (36 `yes` on 12 cores).

  | Walkthrough | #27 (a962b1b) | baseline (c34bb9a) |
  | --- | --- | --- |
  | unloaded | 23–38 s | 25–32 s |
  | starved | 24.4, 25.7, 43.0, 45.0, 51.1 s | 25.3, 55.1, 56.9, 59.6, 60.7 s |
  | starved, CI order (RefreshResilience first) | 39.7–52.9 s | — |

  - **Idle in demo mode, 10 s per tab:** 0.00–0.01 s of CPU on both builds. Nothing republishes at rest: no spinner, no
    TimelineView tick, no re-pull on tab switches.
  - **Accessibility elements per tab** (Today / Sleep / Strain / Insights / Profile): 128/154/175/468/184 with #27,
    125/154/175/468/184 without. #27 adds 3 elements, the status line.
  - **Leftover state:** `-RyftFault` comes in as a launch argument (volatile domain), and nothing persists.
  - **Why lookups suffer most on a starved VM:** Insights has 468 elements, and a full snapshot takes about 0.65 s unloaded. At a
    15–25× slowdown each lookup costs several seconds. Not caused by #27.
- **Decision:** #27 is not the cause, and it stays as it is. #30 (180 s) goes in first, then `main` goes into #27.
  - The 4-of-9 vs 0-of-19 split isn't reproduced locally. The residual risk is that GitHub's VMs differ from a starved 12-core
    Mac. If walkthroughs still exceed 60 s regularly on `main` after #27, give the Insights charts one combined accessibility
    element (it shrinks the tree) and raise the 5 s `waitForExistence` timeouts in `StoreSmokeUITests`.
- **Merged:** #30 (1864e28). Then `main` went into #27 (2ff5f1c = integration 776bb7c + #30, strings in git's merge order),
  whose CI was green (walkthrough within the limit), and #27 merged (d7996f5, auto-merge on the user's go).
- **#31:** `main` merged in (7de4bdd). Every file #26/#28/#27 touch conflicted as add/add because of the squash merges.
  - Resolution: #31's side for every file, after proving `main` adds nothing else (its string catalog equals 776bb7c's key for
    key; the two keys missing on #31 are strings T5 reworded).
  - The tree is exactly 31b025c + #30's lines. 64a968d puts the catalog back in `main`'s key order (diff 154 → 18 lines).
  - Marked ready.

