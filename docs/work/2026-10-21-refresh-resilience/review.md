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
