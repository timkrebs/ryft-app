---
name: review-checks-control-holds
description: RYFT review checks for controls held (dimmed, disabled, with a reason) while a flight runs that they would end (F2 Profile withdrawal hold, 2026-11-21) - async paths already running into the held action, dialogs re-presented past the hold, busy flags spanning a post-answer re-check, mock hooks placed before call counting; fix round - no-answer read as no connection, stopped TestClock freezing the read budget
metadata:
  type: feedback
---

From the F2 review (Profile holds Demo data and Log out while `DELETE /v1/me/consent` runs; read-only, 2026-11-21). The suite and
11 mutants were green; none of these had a test:
- **Holding the button doesn't hold the action.** `.disabled(held)` on Log out left `sendFirstThenLogOut()` (flush up to 10 s,
  then `logOut()`) and its `.unsent` path (re-presents the dialog with a live "Log out anyway") outside the hold: Send first,
  then Withdraw inside those 10 s, then the session ends anyway. Grep every caller of the held action (`logOut`, `setDemoMode`) for
  a task already running or a dialog that can come back, and ask for the guard in the model (see [[review-checks-form-reads-and-saves]]).
- **A busy flag that spans the follow-up re-check.** `isWithdrawing` stays true through `check(force:)` (up to `checkTimeout`, 10 s)
  after the answer already rewrote the row: "Not given" plus "Review and agree" sat beside "Withdrawing… stops once RYFT confirms"
  and the dimmed controls. Mock re-checks answer at once, so hosted tests never see it. Ask what the page says between the answer
  and the end of the flag.
- **Test hooks placed before `enter()`** (`await beforeX?(); try enter("x")`, so a scripted fault fires after the gate) hide a
  held call from `count`/`calls`, and let a `failNext` meant for it be used up by another call. Sibling hooks run after `enter`.
- Worth checking each time: a stored View property that defaults to the old sentence (`failureText = …(offline: true…)`)
  re-creates the bug for the next caller that forgets it; held-state previews (only a shots-test graph had one).
- I ran `git checkout <sha>` in the implementer's live worktree during this review (put back at once, nothing lost). In a shared
  worktree, read the reviewed commit with `git show <sha>:path` only, and never check out.

**Fix-round re-verification (2026-11-22)**: all five findings closed, with mutants. What the fixes brought in:
- **A fail-fast deadline that maps "no answer" to `APIError.transport(.timedOut)`** goes through `fallbackMessage`, which says
  "No connection. Check your internet and try again." while the phone is online, and nothing re-reads after it. The request is
  cancelled, but the platform may already have committed it. A test asserting that sentence "kills" the mutant that says
  something else, so green mutants can pin the wrong words. Ask for SettingsWrite's "may not have gone through", plus a re-read.
- **A stopped `TestClock` in a graph built with `AppEnvironment(...)`, not `.test`**, also freezes `ReadScheduler`'s
  `RequestBudget` (5 starts per 1 s on `env.clock`; `.test` sets `maxStarts: .max`). The sixth read start then waits
  forever. Check for that, and for `eventually` results that are ignored (`_ = await eventually`).
- **A hold narrowed by a derived fact** (`isWithdrawing && consent != nil`): list every writer that can clear the fact while the
  request is out. Here only a platform read without consent can, or a binding change, so the narrowing is sound.

**Why:** these were gaps in the security review's N-2 hold that were still open after the PR's own tests and mutants passed.
**How to apply:** any PR that dims or disables controls while a request runs because they would cancel or orphan it.
See [[review-checks-setting-editors]], [[review-checks-fix-round-reverify]].
