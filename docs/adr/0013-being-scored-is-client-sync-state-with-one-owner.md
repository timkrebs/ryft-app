# 0013 — "This day is being scored" is client sync state with one owner

- Status: Accepted (2026-10-31, data quality D3b / T2, `docs/work/2026-10-31-data-quality/architecture.md` §D3b,
  `docs/work/2026-10-31-data-quality/review-t2.md` F1–F7)
- Deciders: ios-lead; recorded by ios-architect
- Applies to: `Ryft/Sync/ScoringWord.swift`, `Ryft/Sync/SyncService.swift` (`scoringLedger`, `awaiting`, `scored`,
  `receive(_:requestedAt:)`, `accountChanged`, `forgetScoringWords`), `Ryft/Sync/SyncCoordinator.swift` (`SyncSteps`,
  the pipeline, `awaitScoring`, `stillScoring`, `ScoringSignal`, `LiveSyncSteps`), `Ryft/Persistence/Repository.swift`
  (`scoringLedger`, `widgetFacts`), `Ryft/Features/Today/TodayViewModel.swift` (`TodayStates.todayState`), and every
  future path that writes data the platform scores

## Context

- **The platform scores, the phone waits.** After it accepts a write, the platform needs a few seconds to score the
  days it touched. `GET /v1/me/sync` reports them in `pending_days` and `today.state`, and a silent push names them
  when they are done.
- **The status read lags the write.** `API.md` says `GET /v1/me/sync` is "cached 10 s per user". An answer asked for
  right after an upload or a push can therefore be from before it.
- **The audit found three gaps** (`d3b-audit.md`):
  - G1: between the upload and the first poll, Today and the widget show the state from before the upload;
  - G2: a foreground run that sent nothing never waits for days the platform is still scoring (a background upload,
    another device, a relaunch);
  - G3: a silent push lands the row but leaves a stale `pending` from the last status read.
- **Each local fix put the same fact somewhere else.** G1 added a set in `SyncService`, G3 rewrote
  `AppState.syncStatus`, and Today and the widget each merged both. Review round 1 of #88 then found that state kept
  in two places really does diverge:
  - The Repository held its own copy of the ledger. The demo switch cleared that copy only, and an account change
    cleared `SyncService`'s only (F4).
  - A wait could end on an answer the cache served from before the write, so a calibrating day stayed on "Scoring
    your night…" (F1, reproduced with `expected_within_sec` = 3).
- **More write paths are coming.** T4 sends deletions on `POST /v1/sync` (ADR 0011). Activities and the Train import
  already ask for rescoring through `.daysChanged`. Each of them must make Today say "being scored" without its own
  merge.
- **The truth stays on the server.** The client may own sync state, caches and UI state, not scores. The fact "I
  wrote d at t and haven't heard back since" is sync state. The platform's answer is not, and it must not be edited.

## Decision

1. **`SyncService.scoringLedger` is the only holder.**
   - It is `[day: ScoringWord]`. A word is `.pending` (the platform accepted a write that touches the day) or
     `.scored` (a silent push named the day), with the time it was said on the phone's clock.
   - `Repository` reads it through the `scoringLedger` closure, which `LiveSyncSteps` connects. `SyncService` calls
     `ledgerChanged` on every change, and that republishes the widget. Today reads `sync.scoringLedger[today]` into its
     facts.
   - Today and the widget both decide with the same pure function, `ScoringWord.state(day:word:status:row:)`. No other
     type keeps a copy, a set of awaited days or a merged state.
   - `AppState.syncStatus` (and `Repository.todayStatus`, which is derived from it) stays the platform's raw last
     answer. Only the status read's store closure writes it, and nothing patches it with the phone's word.
2. **Only `SyncCoordinator` steps write it.**
   - The writers are `SyncSteps.awaiting(_:)` and `SyncSteps.scored(_:)`, implemented by `LiveSyncSteps`. Besides them,
     only `receive(_:requestedAt:)` may drop answered words, and only the clears in rule 6 may empty the ledger.
   - Every write path reaches the ledger through the coordinator. It does so either through the days its upload
     touched (`POST /v1/sync`'s `days_touched`, including T4's deletions) or through `.daysChanged(days:)` (activities,
     the Train import, any future recompute). No path calls `SyncService.awaiting` or `scored` directly, and no view
     model or uploader writes the ledger.
   - **Partial writes count.** If an upload fails or is cancelled after the platform accepted pages, the coordinator
     still says the days those pages touched. That includes pages accepted by an attempt that a transient failure
     ended before a retry (`touchedSoFar`, `acceptedBefore`).
   - Words are said in the background too, so the foreground return and the widget already show "being scored".
   - A word that arrives after a sign-out is dropped (`LiveSyncSteps.awaiting` checks `isSignedIn`).
3. **A word is answered by a status read requested at least the server's status cache time after it, on the phone's
   clock.**
   - The threshold is `ScoringWord.statusCacheTime`, 10 s from `API.md`. It is defined once.
   - The request time is when the `ReadScheduler` flight was asked for, not when a later caller joined it. Both times
     come from `AppClock`. The phone's clock is never compared with a server timestamp.
   - A read that doesn't know when it was asked (`receive` with `requestedAt: nil`, as in onboarding) answers no word.
   - Once a read has answered a word, the platform's state for that day rules, whatever it says.
   - Until then the word adjusts the platform's state. `.pending` wins over anything. `.scored` wins over everything
     except `waiting_for_sleep`: a day without last night's sleep stays waiting, and a cached `stale` becomes scored,
     because the push means new data arrived.
4. **No status read sent sooner than the cache time after a write may end a wait.**
   - `awaitScoring` sends its first read after `max(minimumPollDelay, expected_within_sec, statusCacheTime)`.
   - The ledger decides when a wait ends, not the poll's own timing. A poll can join a `ReadScheduler` flight that was
     asked earlier, so each answer is given to the ledger with the days it still holds as pending
     (`status.pendingDays ∪ awaitedDays`), and the wait goes on while the phone's word holds a day. An answer that names
     a gate still ends it (nothing is scored behind a gate).
   - A run that sent nothing may reuse a status read that is under 10 s old (`stillScoring`). It uses that read only to
     choose which days to wait for, and adds the ledger's unanswered pending days to them. A cached "nothing pending"
     therefore can't drop the phone's word.
5. **In the foreground, every pending word has a wait that will answer it.**
   - Each foreground path ends in a wait:
     - an upload that touched days waits for them;
     - a `.daysChanged` waits for its days;
     - a run that sent nothing waits for the platform's pending days plus the ledger's pending days (F3).
   - That wait sends at least one read late enough to answer the word, unless a push answers it first or the wait is
     cancelled.
   - A day that an earlier wait gave up on at the 300 s cut-off isn't waited for again until a write touches it
     (`ScoringSignal.waitedOut`). That wait's late polls already answered its word.
   - **In the background, only a push or the next foreground run answers a word.** Background runs skip the wait,
     which is the system's time budget. Until then, Today and the widget say "being scored". The follow-up is a
     `BGAppRefresh` that asks `GET /v1/me/sync` once when old pending words exist (review-t2, architect S4).
6. **The account change and the demo switch clear it.**
   - `SyncService.accountChanged()` runs on every `auth.accountID` change, sign-out included, and goes through
     `forgetScoringWords()`.
   - `forgetScoringWords()` bumps `ledgerGeneration`; the days a wait gave up on (`waitedOut`) belong to one generation,
     so they are forgotten too.
   - An upload that ends after the account changed keeps none of its days, on success, failure or cancel.
   - A run says only the days of an upload it actually started; a cancel before the first upload says none.
   - `SyncService.forgetScoringWords()` runs on the demo switch, from `RyftApp` and from
     `ProfileViewModel.demoModeChanged`.
   - The ledger is in memory only and never persisted. A relaunch starts from the platform's word: the launch read,
     then the run that sent nothing.
7. **Tests pin these rules.** They use `FakeSteps`, `TestClock` and the real `LiveSyncSteps`:
   - `TodayPendingPathTests`: `theWordWinsUntilAStatusRequestedAfterTheCacheTimeAnswers`,
     `aStatusRequestedBeforeThePushCannotMakeTheDayPendingAgain`, `aFastScorerLandsACalibratingDayWithoutAPush`,
     `aPushOnANightlessDayLeavesItWaitingForSleep`, `openingTheAppRightAfterABackgroundUploadWaitsForItsWord`,
     `aReadJoiningAnEarlierFlightLeavesTheWordsThatFlightCouldNotAnswer`,
     `theLedgerIsEmptyAfterAnAccountChangeAndTheWidgetSaysSo`, `switchingDemoDataOnOrOffForgetsTheWords`,
     `aPollThatJoinsAnEarlierFlightKeepsWaitingUntilALateReadAnswers`;
   - `SyncCoordinatorTests`: `anUploadThatEndsEarlySaysTheDaysItsAcceptedPagesTouched`,
     `aSilentPushMarksItsDaysScoredBeforeTheRefresh`, `aStatusReadUnderTheCacheTimeAgoIsUsedAsItIsWithItsOwnEstimate`,
     `anAnswerTheWordOutlivesDoesNotEndTheWait`, `aCancelRightAfterTheUploadSaysOnlyThatUploadsDays`,
     `aDayAWaitGaveUpOnIsWaitedForAgainOnceTheWordsAreForgotten`;
   - `ScoringLedgerTests`: `aPushOverAStaleDayIsScored`, `aWordForManyDaysRepublishesTheWidgetOnce`,
     `aWordSaidAfterASignOutIsDropped`, `anUploadThatEndsAfterTheAccountWentKeepsNoneOfItsDays`,
     `anUploadThatDidNotStartReportsNoDaysTouched`.

   A new write path adds a test that its days reach `FakeSteps.awaiting` through the coordinator.

## Consequences

**Good:**
- Today and the widget can't disagree, because they read one store through one function. The widget is republished
  when the store changes, in the foreground and in the background.
- The server stays the truth. `AppState.syncStatus` is exactly what the platform said, so Copy diagnostics and the
  scoring row show a real answer, and the phone's word is listed beside it (`scoring words …`).
- A new write path costs one line: it hands its days to the coordinator. T4, the Train import and activities get
  "being scored" and the wait without touching Today.
- Everything time-dependent goes through `AppClock` and the coordinator's steps, so each rule is a `TestClock` test
  with no wall-clock sleeps.

**Costs:**
- The 10 s floor delays the first poll by up to 10 s for a platform that scores faster. A silent push still ends the
  wait at once.
- The run that sent nothing now reads `/v1/me/sync`, or reuses a read under 10 s old, on every foreground run of a
  signed-in, configured account outside demo. The read is cheap by `API.md`, and the scheduler coalesces it with a
  pull's read.
- `writtenSinceStart` remains a flag next to the ledger, not something derived from it, because a late status read
  drops the pending words before the wait starts (`SyncService.swift`, N2). It times "Taking longer than usual" and
  decides nothing about the state.

**What could go wrong:**
- **The platform's status cache changes.** If it gets longer than 10 s, an answer can again be from before the word.
  In the foreground, the wait's later polls correct it. In the background, the push or the next foreground run does.
  The fix is one constant. The app has asked the platform to confirm the value or invalidate the cache on ingest
  and scoring (`API_REQUESTS.md` → Sync and performance §2, "Also"; architecture.md open question 6). If the cache
  gets shorter, nothing breaks, and the floor only waits longer than it needs to.
- **The phone's clock jumps.** Word times are wall-clock `Date` from `AppClock` (N8). A jump forward lets an early read
  answer a word. A jump back holds a word until a read 10 s past its time. Both are bounded by the next foreground
  wait, and the ledger is in memory only.
- **The process dies within 10 s of a background upload.** The relaunch starts with an empty ledger, and the launch
  read may come from the cache. Today then shows the state from before the upload until the next read or push. This
  is the price of rule 6. Revisit it only if diagnostics show it happening.
- **No push arrives** (notifications off, or not registered). A word said in the background keeps the widget on
  "being scored" until the app is opened. The `BGAppRefresh` follow-up bounds this.
- **A write path that bypasses the coordinator.**
  - Profile → Rescore (`state.source.recompute`) predates this ADR. It writes outside the pipeline and shows its own
    "Rescoring" line, so Today doesn't say "being scored" for those days.
  - It moves to `.daysChanged` (or the platform's `pending_days` covers it) in a follow-up, not here.
  - Review check: no `awaiting(`/`scored(` calls outside `SyncCoordinator.swift`, and no writes to
    `AppState.syncStatus` outside the status read.

**Rejected alternatives:**
- **Rewrite `AppState.syncStatus`** (the audit's G3 fix: after a push, remove the day from `pending_days` and set
  `today.state`).
  - The edit is local and needs no new type.
  - But the field would get two writers, and the platform's last answer would be partly made up. Diagnostics would
    show answers the platform never gave.
  - The next read overwrites the edit, and a read the cache served from before the push brings `pending` back. That is
    the bug G3 set out to fix.
  - The field can't say when an answer was requested, so it can't tell a late answer from an early one.
- **Per-path fixes** (G1's `awaitingDays`, G2's poll and G3's patch, each where its path is).
  - Each fix is small and correct on its own path.
  - But one fact ends up in three places, merged twice (Today and widget). Review round 1 showed the copies drifting
    apart (F4: two ledgers, each cleared by a different event).
  - Every new write path (T4, the Train import, activities) would need its own fix and its own merge.
  - Nothing would say which answer may end which word, so the cache rule (F1) would have to be repeated on each path.
- **A persisted ledger** (SwiftData or `UserDefaults`, scoped per account).
  - It would survive a relaunch and close the process-death gap above.
  - But a persisted `pending` can outlive its truth for days when no read answers it, which is exactly the stale state
    G3 removed.
  - It would need per-account and per-demo scoping, a wipe in the sign-out path and a schema, for a fact that lives
    seconds to minutes.
  - Its times would be compared across reboots and clock changes.
  - The launch read and the run that sent nothing already rebuild the state from the platform's word.
