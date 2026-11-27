---
name: review-checks-form-reads-and-saves
description: RYFT review checks for an editable form that reads its record and saves it whole (Journal sheet T6B.8, 2026-11-19) - error-banner retry bypassing the commit gate, post-await writes after a selector change, rows built for an unknown day as a PUT body, reads that rebuild over edits, notices contradicting read-only, dead Try again during read holds
metadata:
  type: feedback
---

From the T6B.8 review (Journal sheet, read-only review, no build, 2026-11-19). The suite was green; none of these had a test:
- **An error banner's "Try again" wired to the commit action** (`InlineMessage(retry: actions.save)`) skips the commit
  button's gate (`canSave` = phase ready). If the banner can show in another phase, retry sends whatever the model holds.
  Gate the model (`save()` guards `hasDay`), not only the button.
- **A save that writes model state after its await** (`saved = true`, `rebuild()`, `error = …`) while the day strip stays
  enabled: switching days mid-save puts day A's error (and its Try again) on day B. Look for an `asked == day` guard,
  or a selector disabled while busy. Main-actor reentrancy, no probe needed.
- **Rows built for a day that isn't known** (every enabled habit "off") are a valid whole-day `PUT` = "no" to all. API.md
  says an unsent day is unknown, not "no". Ask: which path can still send them?
- **A refresh that rebuilds rows when it answers** reverts edits made while it was out. It also reverts on a failed read
  when the loader returns the cache. `URLSession` `waitsForConnectivity = true` + a 60 s timeout makes "rare" windows long
  on weak networks. Fix: an edit counter snapshot; skip the rebuild if it moved.
- **Re-selecting the selected chip** calls `select` → rebuild → edits gone. Unsaved edits also go on close or swipe
  without a confirmation (`SheetHeader onClose`, `interactiveDismissDisabled`).
- **An "offline, you can save later" notice shown on a read-only day** contradicts the lock notice. Check every notice
  against `editable`.
- **Try again on a scheduled read is not `userInitiated`**: during the resource's `retryNotBefore` hold `ReadScheduler`
  sends nothing, so the button is dead. Failed reads through `try?` also lose the request ID for Details (hard rule 6).
- A generic-named component (`OfflinePill`) moved into a feature with feature copy: grep all branches for other callers.
- Platform 422 text shown verbatim (`message(for:)`) can carry old words ("behavior …" plus a UUID) past an F1-style rename.

**Why:** these were the honest-state and data-integrity gaps left after the PR's own state tests passed.
**How to apply:** any sheet or form that loads a record, lets the user edit it, and saves it whole. See
[[review-checks-screen-loads]], [[review-checks-settings-subpages]], [[review-checks-multistep-flows]].
