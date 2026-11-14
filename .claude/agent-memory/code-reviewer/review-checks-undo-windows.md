---
name: review-checks-undo-windows
description: RYFT review checks for undo windows that hold an upload, and for follow-up tasks (plan saves) that outlive Finish; probing tips for shared worktrees
metadata:
  type: feedback
---

Found in the T1 "replace exercise" review (2026-10-29), each confirmed with a probe test in a private copy:
- **A held upload leaks through an op that is already queued.** `TrainSyncService.put` reads `s.wire` when it sends,
  so a `put` queued by an edit just before (2 s debounce), a reconnect or an app-active `flush()` sends the state the
  undo window was meant to hold back. Check every flush trigger, not only the window's own `sessionChanged`.
- **Follow-up tasks outlive Finish.** A plan save/revert `Task` that ends in `edited()` runs after `finish()`: it queues
  a `put` after `complete`, and `refreshActivity()` -> `showWorkout()` -> `Activity.request` brings back a Live Activity
  that Finish ended. `endUndo()` cancelled the window timer only. Grep every `Task` a feature starts and ask what it
  writes after finish, discard and account change (`TrainCoordinator.accountChanged` only calls `stop()`).
- **Whole-document PUT built from a cache while an earlier save is still in flight** loses the first change (two quick
  "Also change the plan"). Look for chaining on the previous task. See [[review-checks-wire-drafts-and-flags]].

Probing: other agents push test commits during a review, and HEAD's tests may not compile. Build a private copy
(`git archive HEAD | tar -x` plus the git-ignored `Config/*.xcconfig`). If xcodebuild hangs after the run, it is often
its own `simctl diagnose` (600 s) after a clone worker error: kill that PID (yours), and the results are in the xcresult.
Better: `-parallel-testing-enabled NO -collect-test-diagnostics never` (no clones, no diagnose, Swift Testing output
in the log). In zsh pass `-only-testing:` flags literally, not via an unquoted `$S` (no word splitting).
`TrainStore.wipe()` logs "Batch delete failed … mandatory OTO nullify inverse" in tests: benign, counts end at 0
(probed 2026-10-29).

Re-verify (c1940dc, 2026-10-29): the fix was an in-memory per-session upload hold (`TrainSyncService.hold/release`,
skipped in `drain`, a 409 while held throws `CancellationError` so the op stays). Checked: no persisted state (a kill
clears it), `accountChanged` empties it, every undo exit releases. Pattern to look for next time: an `await` between a
generation guard and the write it guards (`changePlan`: guard → `await lastTime` → `savePlan`).

**Why:** none of these were covered by the branch's tests. **How to apply:** any feature with an undo window, a
deferred upload or a fire-and-forget save. See [[review-checks-outbox-queues]], [[review-checks-shared-transport]].
