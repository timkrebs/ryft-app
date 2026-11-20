---
name: review-checks-fix-round-reverify
description: RYFT checks when re-verifying a multi-round fix PR (PR 6 R1+R2, 2026-11-20) - binding guards that check the caller's binding while ReadScheduler joins flights by key across Demo/account, read chains holding one client past a reset, merged-in vetted error sentences missing from a PR-side allowlist, scan tests narrower than their names, shared library error fields driving a page's failure state
metadata:
  type: feedback
---

From the PR 6 re-verification (a0bd5c2, read-only, no build, 2026-11-20). Every "fix" item held. These were what the fixes left or what the merge brought:
- **A binding guard after the await guards the caller, not the flight.** `ReadScheduler.enter` joins any in-flight flight with the same
  `ReadKey`, and it admits reads while `env.isDemo` (one `env.reads` for both sides). Profile's switch does `state.reset()`, which
  cancels the flights, but `TrainLibrary.refresh()` holds one `Client` for three reads: its next read starts a flight *after* the reset
  with the account's source. The demo refresh's read of the same key joins it, and its own binding is current, so it writes the
  account's answer. Look for: (a) chains of reads that capture one client, (b) a `reads.run` called without checking `isCurrent`
  first, (c) keys without the owner. Fix: guard before starting, and/or put the owner in the key. A JournalStore-style method that
  re-captures `env.api` on every call doesn't have the problem.
- **Tests without the scheduler.** Binding tests built on a rig with `reads == nil` prove the after-await guard only. Ask for one with
  `AppEnvironment.test` and a real `env.reads`.
- **Merging main's new vetted sentences.** #128 added `APIError` text for `403 app_attest_required`, while the PR side's onboarding
  `hasOwnWords` allowlist predates it, so onboarding says "Something went wrong" instead. After a main merge, grep the new
  `errorDescription` cases against every "own words" allowlist or message table on the PR side.
- **Source-scan tests: port the scan to `python3 -I` and run it over the whole repo.** That shows what the folder scope excludes. Then
  list the forms the regex can't see (`withTransaction`, `.transaction`, `phaseAnimator`, `keyframeAnimator`, `symbolEffect`,
  `TimelineView(.animation)`). Here nothing bare reached Train or Journal, so this was a nit.
- **A page's failure from a shared library field** (`PlanDetailViewModel.failure` reads `library.error`): a later unrelated
  `refresh()` success clears it, and the page falls back to outlines with no task pending. Grep `library.error` readers.

**Why:** the fix authors' tests and the per-round reviews were green; these needed the scheduler's join rule, the merge's other side,
or a repo-wide run of the scan. **How to apply:** any re-verification of fix rounds that touch reads, side and account guards, or a
main merge. See [[review-checks-side-split-rounds]], [[review-checks-combine-guards-and-lints]], [[review-checks-area-integration]].

Added after the R4 re-check (145c91a, 2026-11-20). All R4 items held; what the fixes left:
- **Continuation waiters on an @MainActor coordinator** (`OnboardingCoordinator.perform(waitsForTurn:)`): list every resume site (the
  step's `defer` under the same `turn`, and the account switch), and check that the busy flag can only be true while a perform of
  the current turn is running. A suspended waiter's frame keeps `self` alive, so "resumed on deinit" can't happen. Check what
  guards the switch's bump (`self.account != nil`), and that `switchAccount` is called both from `check()` and from RyftApp's
  `onChange` (the same id twice still bumps).
- **A page that now keeps its own failure** (`PlanDetailViewModel.loadFailure`): grep whether the library still writes the
  shared `error` in that path. If it does, the failure now only leaks to sibling pages (the Plans list, another plan's actions).
- **Forgetters without a generation** (My Day's `forget()`): an `async let` pair whose first child already failed still inserts
  after the side ended, when the second child is cancelled. Ask for Strain's pattern: bump in forget(), check before the write.
