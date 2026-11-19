---
name: review-checks-async-write-queues
description: RYFT review checks when synchronous store writes become an async queue (ADR 0018 read-model writer, P1 2026-11-17) - unawaited clears read as fresh, one lock for value and save, continuation waits don't raise priority, as-of tokens without order, bounded waits vs 0xdead10cc, unpinned retry bounds, harness gaps, load caveat
metadata:
  type: feedback
---

From the P1 "read-model writes off the main actor" review (2026-11-17), each confirmed with a probe test:
- **An unawaited write followed by a freshness check.** `AppState.reset()` in demo submits `repository.clear()` and
  `setDemoMode` then runs `refresh()` with `.ifStale`: the checks read the pre-clear rows as fresh and skip, then the clear
  commits and Today, history, user and trends are empty (20/20 on P1, 0/20 on main). Grep every caller that writes, then
  calls something that *decides* from the store (TTL checks, `cachedDay`, gates), not only callers that *display* it.
- **One lock for a hot read and a long critical section.** `StoreEpoch.current` and `ifCurrent { save() }` shared one
  `OSAllocatedUnfairLock`, so every main-thread `submit` (and `TrainSyncService.generation`) waited for the writer's save.
  Probe: hold the save inside the hook, release it from `DispatchQueue.global().asyncAfter`, time a submit on main
  (324 ms against a 300 ms hold). Real on-disk saves of 90 scores took 1–16 ms on the simulator.
- **Awaiting a `CheckedContinuation` doesn't escalate the task that resumes it.** The drain `Task` inherits its first
  submitter's priority and stays there while busy: a `.userInitiated` waiter's batch ran at `.low` (utility) in the probe.
  Check any doc that says "awaiting the ticket raises it".
- `settled()`-style waits before BG completions are unbounded and not cancellation-aware: ask what happens at expiry.

Probe recipe as in [[review-checks-local-overrides]], plus: a second `git archive origin/main` copy with the same probe
proves "regression vs pre-existing". The shared Mac ran at load average 500–900 during this review (other agents and the
new simulator's boot), and a `.background` drain starved for over 60 s. Run `uptime` before calling a hang a deadlock.
The iOS 17.0 simulator runtime is installed locally (`xcrun simctl list runtimes`), whatever a design note says.

Fix-round re-review (523e34d..53d7c48, 2026-11-17), by reading:
- **An "as of" token that checks identity but not order.** `UserChange` held account, store and epoch, but no start
  time. A `PATCH /v1/me` sent before the withdrawal and answered after it (still with consent) passed every check and
  overwrote the withdrawn user. Its arrival also moved `lastUserChange`, so the re-check's correct `/me` was dropped.
  For every "drop older answers" rule, ask whether *writes* begun before the last local change are ordered too.
- **A bounded wait before a completion on an App Group SQLite store.** Completing at the 2 s bound while the drain is
  mid-save, or still starting batches, risks 0xdead10cc (a lock held at suspension). Ask for: stop new batches, then
  wait for the batch in progress.
- **A retry bound that no mutant targets.** The implementer's mutant list (`scratchpad/p1fix-mutants.py`) had none for
  `!resubmittedUser`. Read the list and look for the bound itself.
- **Test harness versus doc.** `WipeHarness` wires `bindAccountHooks` but not RyftApp's `accountChanged(from:)`, so
  `AppState.reset()` (and `Repository.reset()`) never runs in it, whatever a test's comment says.
- Positive waits of 2 s were chosen to stay under `WriterHold`'s 10 s auto-release (mutant power). Suggest about 5 s,
  not the 30 s default. Load average was about 400 again, so I read the code and ran no probes.

**Why:** none of these were covered by the PR's 86 passing tests or its stress test. **How to apply:** any PR that moves
writes behind a queue, actor or ticket. See [[review-checks-outbox-queues]] (epoch timing), [[review-checks-shared-transport]].
