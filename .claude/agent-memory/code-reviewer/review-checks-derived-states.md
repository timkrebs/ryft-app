---
name: review-checks-derived-states
description: RYFT review checks for time-derived states (Today night hint, slow scoring, Check sync) — server aggregates undoing local exclusions, hero-derived flags, kept timestamps, "last night" after midnight, inputs derived once on first run
metadata:
  type: feedback
---

Found in the tracker-setup T1 review (2026-10-22); every one passed the implementer's tests because the tests
encoded the same assumption:
- **Local exclusion, server aggregate.** A rule excludes a source locally (the iPhone's in-bed sleep isn't "the night")
  but also consults a server aggregate (`SyncStatus.latest["sleep"]` = max end over *all* sources, incl. that iPhone,
  `plattform/backend/internal/store/sources.go`). Read the platform (read-only) to see what an aggregate includes.
- **Labels from `hero == .pending`.** `TodayStates.line`'s `night` flag ignores `waitingForSleep`, so "Scoring your
  night" sits under "Waiting for last night's sleep" outside a new state's time window. Check every branch outside the
  window, not just inside it.
- **Kept timestamps.** A start kept "until the platform says otherwise" (`scoringWaitStart`) must be checked on every
  exit transition (cancel → `.idle` on background, relaunch with no start, another device's pending day) and against
  re-render cadence (a `TimelineView` whose period depends on the current line can't flip to a state the current line
  doesn't predict).
- **A timer needs evidence** (T1 re-review): a "slow" clock started at first sight of server state (`receive()` seeing
  pending days) with no follow-up read turns "we stopped asking" into "the platform is slow" — RYFT users without
  notification permission get no silent push (`PushRegistrar.refresh` registers only when allowed). Ask for a one-shot
  read at the threshold, or call it slow only when a read after start + threshold still lists the days.
- Test tables written by the implementer often assert the questionable branch (`== .scoring(night: true)` at 15:30);
  read the expectations, not just the pass count.

Found in the T3 sync-check review (2026-10-22), both confirmed with a scratch test:
- **"Last night" after midnight.** `RawNight.window(before: now)` is 18:00 the evening *before* `now`, so from 00:00 until
  the night is written it points at tonight: a Check sync at 00:30 calls the previous night "not since last night".
  Today's `nightGap` only runs 08:00–15:00 and skips the iPhone; any rule claiming "the same fact" must share the gate.
- **Derived once, never again.** `if trackers.isEmpty { trackers = seen(...) }` fills an empty input from the first
  result; "Check again" then can't see what synced since. Look for this on every re-run/refresh path.

**Why:** these are logic defects a green suite hides. **How to apply:** for any new Today state, enumerate the hours
outside its window and every SyncPhase exit. See [[review-checks-today-state]].

Absence from a nil field (My Day A1 part 2, 2026-10-23): "No sleep recorded" was derived from `DayDetail.sleep == nil`
with `detail != nil` as the "loaded" guard. API.md → `GET /v1/days/{day}`: a day not scored yet answers 200 with a
placeholder (`sleep: null`, `workouts: []`), so 00:00 until the night is scored, during `pending`, the first import and
offline it claimed no sleep beside Today's "Scoring your night" / RawNightCard. `nightGap` only suppresses 08–15,
online, `waitingForSleep`. Before deriving "missing" from nil, check `score.standing` / `score.scoringState`.

Recurred in Nocturne PR 4 (Sleep → Day board, 2026-11-17): `SleepBoard` maps `sleep == nil` to `.noSleep` ahead of
`isPending`, and design.md's own "Pending score" row says "numeral and ruler from the raw night" while the code only
reads the server `SleepDetail`. Every pending test passed a non-nil `sleep` with `isPending: true`, a pair the API never
sends for a first scoring. Check first for any `guard let sleep else` in a board/VM, and ask for a test built from
the API placeholder JSON (`scoring_state: pending`, `sleep: null`).

Recurred again in the PR 4 fix round (2026-11-17): the CR1 fix keyed Sleep's new pending look on `DayMarker.kind == .pending`,
which also maps `.waitingForSleep`, so a day scored without a night (Watch on the charger) says "Your night is being scored."
all day. Today's rule (`TodayPresentation.pick`) is "scoring only on the platform's word": `pending` -> being scored + raw
night; `waiting_for_sleep`/`stale` -> "Last night hasn't reached RYFT yet.", no raw night. Any new board copy for an unscored
night: switch on `score.scoringState`, never on `DayMarker`, and test each of `pending`, `waiting_for_sleep`, `stale`.

Third pass (PR 4 round 3, 2026-11-17): the R2-F1 fix switched on the *cached row's* `scoringState`, but today's state has
one owner, `ScoringWord.state(day:word:status:row:)` (phone ledger `SyncService.scoringLedger` > `GET /v1/me/sync`
`today.state` > row), used by Today and `Repository.widgetFacts`. Today's detail is re-read only in `refreshDays` after
the scoring wait, and `.ifStale` serves it for 300 s, so after an upload Today says "being scored" while a row-only
screen says "hasn't reached RYFT". For any screen that words today's scoring: grep for `ScoringWord.state`; a bare
`.scoringState` on today's row is the bug. Also check `nil` (unknown values decode via `try?`): Today's `pick` reads
no word on an unscored row as waiting, never as scored.
"Agrees with Today" test tables (PR 4 round 4): Today's `pick` rule 1 (E, firstImport) fires only with no prior scored
day and no `pending`/`waiting` word, so `scored`/`stale`/nil over an unscored row reads differently for a first-night
user. Check that each case runs with `prior: false` too, and that the cached row lagging a newer status/word is covered.
Fifth time (T5.2 Strain, 2026-11-18): "No strain recorded for this day." and "Your watch didn't record heart-rate zones" from
`strain == nil` with no `scoringState`/`isToday` check, because design.md's state table said so. Flag it even when the spec asks for it.
Tonight's bedtime has one owner (T5.5, 2026-11-18): `BedtimePlanner` plans for `schedule.nextWake(after:)` and feeds Today's
Tonight card, the Wind-down reminder and the widget. `SleepPlannerViewModel` (the "Wake up at" picker) seeds its wake from last
night's *actual* wake time, so a screen that labels the picker's plan "Tonight" disagrees with all three. When a screen words
"tonight", check which planner's plan it reads.
