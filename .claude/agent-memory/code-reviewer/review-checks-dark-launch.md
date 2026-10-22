---
name: review-checks-dark-launch
description: RYFT review checks for features shipped dark behind a remote flag with remote content (tracker setup T2) — flag-off leaks, always-evaluated RootView modifiers, remote enums driving Apple glyphs, content-coupled tests, UI-test hittability under pinned bars
metadata:
  type: feedback
---

Found in the tracker-setup T2 review (2026-10-22); the suite was green on the implementer's machine:
- **Flag-off leaks.** Grep every `if flag … else` in *shared* components (not just onboarding/Profile): T2's
  `SetupCard` flag-off branch silently replaced main's text. A *deleted* key in the xcstrings diff
  (`python3 -I` dict compare vs base) is the quickest signal that a flag-off path changed.
- **Always-evaluated modifiers.** RootView's `.animation(value: x.showsY)` evaluates `showsY` on every body, even
  during the splash. Per-account facts (`isFirstRun`, `…Done`) are defaults until `switchAccount` loads them, so a
  guard that looks first-run-only runs for everyone at launch and can touch a lazy static (catalog decode) on main.
- **Remote enums driving trust decisions.** Glyphs/behaviour keyed on a content field (`form == .phone`) instead of a
  compiled id let a remote copy claim an Apple silhouette; check what the validator actually restricts.
- **Content-coupled tests.** Fixtures that copy the bundled JSON with hard-coded versions/dates and a fixed TestClock
  break on the next content refresh; ask to derive from `bundled.version`.
- **UI tests:** `if !el.isHittable { swipeUp() }` passes `isHittable` for an element under a `safeAreaInset` bar; the
  tap hits the bar. Re-run new UI tests on iPhone 17 (CI is 17 Pro, same 402 pt) after any later layout commit, and
  read the xcresult activity log (`xcresulttool get test-results activities`) to see which branch ran.
- **Merge friction:** `git merge-tree --write-tree --name-only A B` gives exact conflict files/hunks without touching
  worktrees; compare against the §9.3 region table.

**Why:** each was invisible in the PR's own green run. **How to apply:** run these on any "ships dark behind a flag"
or "remote content" ticket. See [[review-checks-merges-and-wiring]], [[review-checks-derived-states]].

Re-review (2026-10-22): a selection filter over candidate sources (`TrackerSelectionStore.worn`) dropped *unmatched*
sources too, breaking T1's "ambiguous Apple source is a candidate" rule. Check filters drop only what is known to be
excluded. A temporary `@Test` that prints T1's table under each selection, in the detached copy, settles it fast.

Debug launch arguments "for one launch / in memory" (combined T3+T2+T1 review, 2026-10-22): look for a *writer* that
persists the merged state. `FlagStore.setOverride` saved the whole `overrides` dict, so `-RyftFlags` flags injected
into it were persisted by any later toggle; `TrackerSelectionStore.stage()` put an unsaved value in `live`, and
`mutate` (Done on a setup card) built from `live` and saved it to the account. Prove it with a temporary
`@Suite(.serialized)` probe that reports via `Issue.record` (prints from the test host don't reach the xcodebuild
log; read messages with `xcresulttool get test-results tests`). Also check that a second key carrying the same ids
(`sync_check` lines hold tracker ids) is gated like the first (`trackers` only with the flag on).
