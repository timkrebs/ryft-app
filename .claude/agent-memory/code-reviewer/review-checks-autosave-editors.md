---
name: review-checks-autosave-editors
description: RYFT review checks for "saves as you change it" editors (Bedtime & wake C4, 2026-11-19) - save chains whose links await the network, per-page draft snapshots alive in other tabs, async Turn off on a live page, conditional navigationDestination hosts, tests that pin the bug
metadata:
  type: feedback
---

From the C4 review (Bedtime & wake / Tonight, read-only, 2026-11-19). The suite was green; none of these had a test:
- **A save chain whose link awaits the network.** `BedtimeScheduleEditor.save` chained `await before?.value; await
  planner.update(s)`, and `update` persists first but then awaits `refresh()` -> `GET /v1/sleep/plan` (APIClient: 60 s
  timeout, `waitsForConnectivity`, 503 retries up to 3 x 30 s). So change 2 isn't on the phone until change 1's fetch
  ends; a kill loses it while the footer says "Changes save as you make them". Ask what each chain link awaits; persist
  synchronously, serialise only the side effects (coalescing to the latest).
- **Per-page draft snapshots outlive their tab.** RYFT's `TabView` keeps every tab's stack. Two pushes of one editor
  (Profile, Today, Sleep) hold two drafts; neither rebases when the other saves, and `edited` is never reset, so the stale
  page's `onDisappear` save (fired by a tab switch) reverts the other's change. Grep every host of the page.
- **Async destructive action on a live page** (Turn off awaits the chain): the page stays editable, and an edit made
  during the wait is saved by `leave()` after the dismiss, which re-creates what was turned off.
- **`navigationDestination(isPresented:)` on a conditional card** (Today's `if isEvening()`): when the condition flips
  (the user's own edit can flip it after midnight), the presenter leaves and the page pops. Prefer an always-mounted
  host (TodayHeader's `showsMyDay` pattern).
- **A test that asserts the waiting state** ("the second waits for the first": `planner.schedule` still old) pins the
  defect; ask for it to be rewritten with the fix.
- **One-element tiles hide clipping from hosted AX3 tests**: `nodes()` only sees the tile frame. Ask for a worst-case
  value ("12:08 AM") or a UIView-level check.

Mechanics: the lead can merge and remove a worktree mid-review. Keep reading via `git show <sha>:<path>` from the main
repo, and check `git diff <sha> <merge>` for the files to see if findings still apply.

**Why:** these are the honest-state and data-integrity gaps left after the PR's own editor tests passed.
**How to apply:** any autosaving settings page or editor. See [[review-checks-form-reads-and-saves]],
[[review-checks-undo-windows]], [[review-checks-outbox-queues]]; the fix round's leftovers: [[review-checks-side-effect-passes]].
