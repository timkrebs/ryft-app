---
name: review-checks-list-rewrites
description: RYFT review checks for whole-screen rewrites into grouped lists (Nocturne T5.4 Profile, 2026-11-19) - status words fed by the wrong timestamp, identifiers on wrapper composites, rows moved into flag-gated groups, dead leftovers, implementer test-count claims vs logs
metadata:
  type: feedback
---

Found in the T5.4 review (Profile main list, 2026-11-19); behaviour inventory was complete, these were not visible in the green runs:
- **A status word composed with a source** ("Apple Health · updated now") took its age from the platform *read*
  (`state.lastUpdated`) for `.paused`, where the failure is the *upload*: the after-shot `sync-issue` showed "updated now"
  beside "Last sync: Never" and the failure notice. For every word, ask which timestamp it means (`settings.lastSync` =
  last good upload; `lastUpdated` = today's detail read) and look at the failure-state shot, not the happy one.
- **Identifiers applied around a composite** (`GroupedRow` + hairline overlay, or a row that sets its own id and gets a
  second from the list loop) land on two elements; `descendants(matching: .any)[id]` then fails "Multiple matching
  elements". The implementer's ui logs showed it and the tests were switched to typed queries instead. Hosted id checks
  that collect into a `Set` can't see duplicates: ask for counts.
- **Rows moved into a gated group change their gating** (Save strength workouts moved under `showsTraining` /
  `train.enabled`). Diff each row's old condition against its new group's guard.
- **Leftovers:** a VM method whose only caller was a removed button (`ProfileViewModel.fullResync`), old row views kept
  alive only by previews and a test (AX3 test still hosting the dead `HeroNumeralsRow`), catalog keys of removed titles.
- **"N tests passing" claims:** read the scratchpad logs and file mtimes. Here the 116-test run had failed (11 issues),
  only the two new suites were re-run, and a production file changed after the big run and after the shots.
- UI tests edited in the PR may be outside UISmoke (Full only, nightly): check the plan before counting them as PR coverage.

**Why:** each needed the shots, the implementer's logs or a gating diff, not the hunk. **How to apply:** any screen
rewrite that re-homes rows into cards/groups or adds a summary/status line. See [[review-checks-form-restyles]],
[[review-checks-merges-and-wiring]], [[review-checks-dark-launch]].
