---
name: project-sync-machine-silent-edges
description: SyncService.advance(to:) silently ignores edges SyncMachine doesn't list (idle → failed, idle/done → awaitingScores) — assert phase in tests; daysChanged waits never show awaitingScores
metadata:
  type: project
---

`GKTableMachine.enter` returns false for an edge the table doesn't list, and `SyncService.advance(to:)` ignores the
result. `SyncMachine` has no `idle → failed` (nor `done/offline → failed`): a run that fails *before* it reads
HealthKit stays in its old phase unless it enters `.reading` first. Found in P2 (2026-10-26) when the consent
revalidation's failure left `sync.phase == .idle`; the fix entered `.reading` for the config read, then `.failed`
(or `.idle` when it then held).

**Why:** the "paused" line and Details on Today read `phase == .failed` with `lastError`; a silently rejected edge
shows nothing and no test fails unless it asserts the phase.

**How to apply:** any new step at the start of `SyncService.run()` that can fail or hold: check the edge in
`Ryft/StateMachines/Machines.swift`, and assert `sync.phase` in its test. Related: [[feedback-tests-pin-decisions]].

**Also `idle/done → awaitingScores` is missing (found 2026-10-31, D3b).** A `.daysChanged` run (activity, night edit,
training import) reports `.awaitingScores` straight from idle, so `sync.phase` never shows the wait: no
`scoringWaitStart`, no "Scoring…" line from the phase. Today still shows the day as being scored through
`SyncService.scoringLedger` (`awaiting`). Test harnesses that wait for `phase == .awaitingScores` hang on that path;
wait on `clock.pendingSleeps` instead. Not fixed (StateMachines/ was out of scope).
