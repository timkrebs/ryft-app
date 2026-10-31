# D3b audit: is Today's `.pending` reached on every path that syncs?

Ticket C of the data-quality plan. A read-only audit of `origin/main` 69ca9ad by sync-engineer. No source was changed.
The findings come from reading the code. The existing tests named below pin their premises, but no new code was run.

## What drives `.pending`

- **The hero** is `TodayStates.hero(_:presentation:)` (`Features/Today/TodayViewModel.swift:871`):
  - The import card wins while `isImporting && !hasScoredDay`.
  - Otherwise `TodayPresentation.decide` picks. It takes row C (`.pending`) when today has no readiness and either
    today has no scored row or the scoring state is `pending` / `waiting_for_sleep` (`:1113`, `:1120`).
- **The scoring state** is `TodayStates.todayState` (`:859`). It is `GET /v1/me/sync` → `today.state` when that
  answer is about today, else the cached row's `scoring_state`. The widget decides the same way
  (`Persistence/Repository.swift:515`, through `AppState.syncStatus.didSet` → `repository.todayStatus`).
- **Two variants.** `PendingNight.waitingForSleep` splits row C:
  - "Scoring your night…" when `today.state == pending`, or `scored` before the row is here;
  - "Waiting for last night's sleep" otherwise, including when there is no status at all.

  Both draw the dimmed orbit and both breathe, but only the first one is right after a sync that touched today.
- **So the question is narrower than it looks.** It isn't whether the hero is `.pending`. It is whether, after the
  upload, `AppState.syncStatus` holds a fresh `GET /v1/me/sync` that lists today. Only three places write it:
  - the coordinator's `syncStatus` step (`Sync/SyncCoordinator.swift:599`): the scoring wait's polls (`:460`),
    pull-to-refresh phase 2 (`App/AppState.swift:182`) and Today's one slow check (`TodayViewModel.swift:255`);
  - `OnboardingCoordinator.check()` (`Features/Onboarding/HealthPermissionView.swift:303`, write at `:325`): at launch
    and sign-in, and on every scene-active, throttled to once per 60 s;
  - nothing else. Neither a silent push nor `AppState.refresh` / `refreshDays` reads the status.
- **By design: a day that already has a readiness is never pending again.** Row A wins even while `pending_days`
  lists today (`ARCHITECTURE.md`, test `aScoreThatLandedIsNeverPendingAgain`). A sync during the day touches today
  (HR, steps) on almost every run, so this keeps the gauge from flickering. D2's provisional state covers the
  morning half-night case. This audit treats it as intended. The lead should confirm.

## Paths

"Reached" means the hero shows the scoring variant ("Scoring your night…") while the platform lists today as pending.

| Path | Entry point | Reached? | Existing test that proves it |
| --- | --- | --- | --- |
| Pull-to-refresh, Try again, Profile → Sync now | `AppState.pullToRefresh` `App/AppState.swift:157` (run at `:166`, phase-2 status at `:182`). `TodayViewModel.refresh` `:292` and `ProfileViewModel.syncNow` `:237` call it | **Only after the first poll.** Phase 2 reads the status at t≈0, while the upload is still running, so the answer is from before the upload. The wait's first poll comes at max(2 s, `expected_within_sec`), usually 20–30 s. Until then the hero keeps the earlier state (gap **G1**). | Partly. `PullToRefreshTests.todayAndTheStatusFirstTheRestAfterTwoSeconds` covers the read order and `SyncCoordinatorTests.asksTheServerWithDoublingWaitsForFiveMinutesAtMost` the polls (`FakeSteps`). `TodayStatesTests.aNightBeingScoredShowsThePendingGaugeWithTheDayBefore` builds the facts by hand. No end-to-end hero test. |
| HealthKit delivery, app in the foreground | `RyftApp.observeHealthKit` `App/RyftApp.swift:383` → `run(.healthKit)` | **Only after the first poll**, like pull-to-refresh (**G1**). | `SyncCoordinatorLifecycleTests.aDeliveryWhileTheUserLooksStillRefreshesToday` checks the wait and refresh, not the hero. |
| HealthKit delivery, app in the background | same, with `inBackground` true | No status read, by design: the run returns after the upload (`SyncCoordinator.swift:370`) and the silent push is meant to refresh. What the user sees next is the foreground-return row. | `backgroundRunsUseTheBackgroundSessionAndSkipTheScoringWait` |
| `BGAppRefreshTask` | `Sync/ScheduledWork.swift:34` → `run(.background)` | Same as background delivery. | same |
| `BGProcessingTask` (backfill) | `ScheduledWork.swift:110` → `run(.processing)` | Same: it always runs as a background run (`SyncCoordinator.swift:249`). | `theBackfillTaskRunsUntilTheBacklogIsGone` |
| Foreground return (scene → active) | `RyftApp.swift:275-276` → `run(.appActive)`, plus `onboarding.check()` after the first frame | **New data uploaded now:** yes, after the first poll (**G1**). **Nothing new**, because the background run or another device already uploaded it: **only if** `check()` wasn't throttled (more than 60 s since the last check). In that case the hero shows the scoring variant, but nothing polls before the slow threshold (Today's one check, `confirmSlowScoring`). When that read or any later one says "scored", **nothing fetches today's row again**, so the hero stays on "Scoring your night…" until a silent push arrives or the user pulls (gap **G2**). The pipeline's `touched.isEmpty` branch (`SyncCoordinator.swift:376`) refreshes only what's stale and asks nothing. | `SyncCoordinatorTests.nothingUploadedOnlyRefreshesWhatsStale` pins the no-wait branch. `TodayNightAndScoringTests.aFirstSightStartScoredMeanwhileIsClearedByTheOneReadAndNeverSlow` and `…StillPendingAfterTheOneReadIsSlow` check the slow logic only, not the landing. |
| First morning (first open after the night) | Cold launch: `bootstrap` `RyftApp.swift:375` (`check()`, then `run(.appActive)`), plus the scene-active run, which coalesces with it | **Only after the first poll.** `check()` reads the status before the night is uploaded and gets `waiting_for_sleep`. For about 20–30 s after the upload the hero says "Waiting for last night's sleep / It's scored as soon as Apple Health has it", while the status line already says "Scoring your latest data" (**G1**). | none |
| First-run import (the import card) | The same runs; `TodayStates.hero` `TodayViewModel.swift:872` | **Yes, by design.** The card replaces the gauge until a day is scored, and its step reads `.scoring` from the phase or from `pending_days` (`:891-893`). After the first score the hero goes through `decide`, so row C is reachable as on the paths above. The guard has been `isImporting && !hasScoredDay` since #14, and no repo history records the earlier bypass. Untested: the hand-off from the import card to `.pending` when yesterday is scored and today is not. | `TodayStatesTests.theImportCardShowsUntilADayIsScored` (hands off to `.score` only), `importStepsFollowThePipeline` |
| Silent push (`refresh`) | `Push/AppDelegate.swift:78` → `run(.silentPush(days:))`. It ends a wait (`SyncCoordinator.swift:162`) or runs its own refresh (`:344`) | **Leaves `pending` behind.** The push fetches the scored row but never reads the status again, so `syncStatus.today.state` stays at the last poll's `pending`. With a readiness, row A wins and all is well. **Without a readiness** (every account's calibrating first week, row B), row C holds "Scoring your night…". `scoringSince` was cleared when the wait ended early, so neither Today's 15 s tick nor `confirmSlowScoring` asks again. It stays stuck until the next pull or a foreground return more than 60 s later. The widget shows the same (gap **G3**). | `aScoreThatLandedIsNeverPendingAgain` covers the readiness case only. `pendingWinsOverCalibratingThenTheBaselineShows` pins G3's premise: a stale `pending` status beats a calibrating row. |
| Training import, activity or night edits | `TrainImportUploader.swift:1143`, `ActivityUploader.swift:659-668` → `run(.daysChanged)` | In the foreground, yes after the first poll (**G1**). In the background there is no wait, by design. | `SleepUpgradeTests.rescoringWaitsForScoringOnTheClock` (the wait); no hero test |
| Reconnect, unlock, gate released, consent agreed, "sync stale" notification | `RyftApp.swift:246`, `ScheduledWork.swift:150`, `ScreenModels.swift:124` and `:61`, `AppDelegate.swift:101` | Same as the foreground or background row they run in. | none specific |

## Gaps and the smallest fixes

### G3: a silent push leaves a stale `pending` (highest: it sticks, and every new tester calibrates)

- **Fix:** take the push as the platform's word that its day is scored. Add a `SyncSteps.scored(_ days: [String])`
  step and call it from `SyncCoordinator.run` before the refresh, both when the push ends a waiting run (`:162`) and
  in the push's own pipeline (`:344`).
- **What `LiveSyncSteps` does with it:** it rewrites `state.syncStatus` with those days removed from `pending_days`,
  and with `today.state` set to `scored` when today is among them and was `pending`. `didSet` carries this to the
  widget.
- **What it doesn't do:** it reads no clocks and adds no request. A status re-read wouldn't help here: the platform
  caches `GET /v1/me/sync` for 10 s per user, so an ask right after the push can return the same `pending`.
- **Owner:** sync-engineer (`Sync/SyncCoordinator.swift`, `LiveSyncSteps` in the same file).
- **Not chosen:** `todayState` could ignore a status whose `today.scored_at` is older than the cached row's
  `computed_at`. That compares two server values, so it is allowed, but it relies on the platform writing both from
  the same scoring run. Ask the platform before taking that route.

### G2: foreground return with nothing to upload never waits for days the platform still scores

- **Fix:** in the pipeline's `guard !touched.isEmpty` branch (`SyncCoordinator.swift:376`), in the foreground and
  outside demo mode, ask `steps.syncStatus()`. The ask joins `check()`'s read when one is in flight.
- **If the answer lists pending days and has no `gate`:** continue as `.daysChanged(days: pendingDays)` already
  does: report `.awaitingScores`, run `awaitScoring(pendingDays)`, then refresh those days, trends and insights.
- **Otherwise:** refresh what's stale, as now.
- **Keep the first-sighting start:** `SyncService.entered(.awaitingScores)` must keep a `scoringWaitStart` that
  `receive` already set. Otherwise "Taking longer than usual" restarts its clock.
- **Cost:** one `GET /v1/me/sync` per foreground run that sent nothing. The server caches the answer and
  `ReadScheduler` joins concurrent reads.
- **What it covers:** a background-delivered upload, BGAppRefresh, a relaunch, another device's upload, and the 60 s
  throttle on `check()`.
- **Owner:** sync-engineer.

### G1: between the upload and the first poll, the hero shows the pre-upload state (low; it heals itself in 20–30 s)

- **Fix, sync-engineer:** `SyncService` gains `awaitingDays: Set<String>`. The coordinator sets it with a new
  `SyncSteps.awaiting(_:)` just before `report(.awaitingScores)` (`:357`, `:383`), and `entered` clears it when the
  phase leaves `.awaitingScores`. It is the server's `days_touched`, not a guess.
- **Fix, ios-developer:** `TodayStates.todayState` returns `.pending` while `phase == .awaitingScores`,
  `awaitingDays` contains today, and no status has been read since the wait began (`statusReadAt` earlier than
  `scoringSince`; both are on the phone's clock).
- **Unchanged:** a readiness still wins (row A).
- **Owners:** sync-engineer for the fact, ios-developer for `todayState` (`TodayViewModel.swift:859`). Use the same
  helper in `Repository.swift:515` if the widget should agree.

### By design, not gaps

- No status read in background runs.
- The import card in place of the gauge before the first score.
- A day with a readiness stays row A.

## View-model tests to add

Add a new suite, `TodayPendingPathTests`, in `RyftTests/ViewModelTests.swift` so it reuses `makeState`, `coordinator`
and `at`.

**Setup:**
- `TodayViewModel` with `LiveSyncSteps` over `SyncService.ungated`, `MockHealthStore` holding last night,
  `MockPlatformAPI` and `TestClock` at 07:30.
- The mock: `syncResponse.daysTouched = [today]`, `scoringToday = pending`, `pendingDays = [today]`; yesterday
  scored at 76.
- Each test asserts the hero (`.pending`, `waitingForSleep == false`), then flips the mock to scored and adds the
  row, advances the clock, and asserts that the hero lands (`.score`, or `.calibrating` for G3).

**Waits:** poll actor state with `eventually { clock.pendingSleeps == n }` before each `advance`, never a fixed sleep.

**Tests (✗ marks the ones expected to fail on main):**

1. `pullToRefreshShowsTheNightBeingScoredUntilItLands` (✗ before the first poll: G1)
2. `aDeliveryWhileTheUserLooksShowsTheNightBeingScored` (✗ G1)
3. `aBackgroundDeliveryThenOpeningTheAppShowsTheNightBeingScoredAndItLands`: `inBackground: true`, then
   `run(.healthKit)` with no status read, then `enterForeground` and `run(.appActive)` with nothing new.
   ✗ G2: the hero never lands without a push.
4. `aBackgroundRefreshTaskThenOpeningTheAppShowsTheNightBeingScoredAndItLands`: `run(.background)`, then the same
   as 3. ✗ G2.
5. `theFirstMorningSaysScoringRightAfterTheUploadNotWaitingForSleep`: `check()` answers `waiting_for_sleep` before
   the upload. ✗ G1.
6. `theImportCardHandsOverToThePendingGaugeAfterTheFirstScore`: the backfill isn't done, yesterday is scored and
   today is pending.
7. `aSilentPushThatEndsTheWaitLandsACalibratingDayOnTheBaselines`: today's row is `readiness nil, calibrating`.
   ✗ G3.
8. `aSilentPushWhileNobodyWaitsClearsTodayFromPending`: the push arrives after the 300 s cut-off. ✗ G3.
9. `aDaysChangedRunShowsTheDayBeingScoredUntilItLands`: the training import path.
10. `aRelaunchWithTodayStillPendingPollsUntilItLands`: the first-sight start, scored after 10 s, with no push.
    ✗ G2.

**Coordinator tests for the fixes (`SyncCoordinatorTests`, `FakeSteps`):**
- `aForegroundRunThatSentNothingWaitsForDaysThePlatformStillScores`
- `aBackgroundRunThatSentNothingAsksNothing`
- `aGatedRunThatSentNothingDoesNotWait`
- `aSilentPushMarksItsDaysScoredBeforeTheRefresh`
- `theAwaitedDaysAreKnownDuringTheWaitAndClearedAfter`
