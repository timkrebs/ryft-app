---
name: project-state-reset-keeps-store
description: In unit tests, AppState.reset() runs the forgetters and resets reads but does not wipe the account store's cached trends/days; "nothing cached" needs a failed read
metadata:
  type: project
---

Seen 2026-11-20 (F1 item 4, Insights' loaded range): a test loaded Insights through `sidesScreens(state, rig)`, called
`state.reset()` and expected every trend card to show outlines (nothing cached). All 14 cards still had their series:
`Repository.reset()` only drops the demo store and the memo (`invalidate()`); the account store's rows go with the
auth wipe (sign-out, another account) or stay behind the demo store's switch, neither of which `reset()` does.

**Why:** a "the next side has nothing cached" assertion after `state.reset()` passes or fails for the wrong reason.

**How to apply:** for a card or day with nothing cached across a switch, make that read fail on the first side
(`ScriptedTrends.failing`, `api.faults["day"]`), so nothing is stored, then reset. Say in the test's doc that the test
keeps the store. Related: [[project-demo-setting-in-tests]], [[feedback-tests-pin-decisions]].

Also from that session (2026-11-20/21):
- **Ending a turn to wait triggers a forced hand-back** ("[handback-send-enforce]"), twice. Don't end the turn while a
  background run goes: poll with foreground loops that end within ~150 s (a call past ~180 s moves to the background),
  e.g. `for i in $(seq 1 10); do grep -q "^exit" log.wait && break; sleep 10; done` with a 130 s timeout (14 × 10 s
  under a 160 s timeout still went to the background on 2026-11-21). If forced anyway, stop the runner first (SIGTERM;
  it restores in `finally`), check `git status`, report what didn't run.
- **Midnight flake:** `ActivitiesNocturneRuleTests/saveStaysOffUntilTheFormIsValid` failed in the first ~30 min after
  local midnight (end = start + 30 min with start clamped to 00:00). Fixed on `fix/pr6-follow-ups` (2026-11-21, "test:
  the activity form's rule test holds at midnight": a TestClock at 10:00). If it fails on a branch without that commit,
  it's the flake, not a regression.
