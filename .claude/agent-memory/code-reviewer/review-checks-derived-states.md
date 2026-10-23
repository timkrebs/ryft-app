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
