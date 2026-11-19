---
name: project-minimum-ios18
description: RYFT's minimum is iOS 18.6 (user decision 2026-11-18; first relayed as 18.0, corrected in the PR #121 review); target moves in its own PR; no iOS 17-only SwiftData workarounds
metadata:
  type: project
---

Decided by the user on 2026-11-18, relayed by the lead during P1b: **minimum iOS 18.6** (first relayed as 18.0; the
PR #121 review corrected it, so docs say 18.6 and runs on 18.0 stay described as runs on 18.0). The deployment-target change
lands in its own PR; until it merges the target is still 17.0, so branches must still build (and CI on 27.2 pass) with
17.0 as the target.

**Why:** the iOS 17.0 gates kept finding SwiftData save refusals of the T0.6 family (only the newest container takes
inserts: My Day missing the night in the demo, Strain days losing detail, the account's store after the demo). Every
iPhone that runs iOS 17 also runs iOS 18.

**How to apply:**
- Don't build or debug iOS 17.0-only workarounds (reopens, per-OS gates, 17.0 runs) unless the lead asks; the P1b reopen
  was dropped for this (see [[project-swiftdata-two-containers-ios17]]).
- Installed runtimes here: 17.0, 18.0, 26.0, 27.x, no 18.6 (2026-11-18). CI runs 27.2. iOS 18.0 has its own SwiftData
  traps: a held row after a Train wipe ends the process ("Context is missing", `TrainStoreWipeTests/aRowStillHeld…`,
  pre-existing, STATUS); whether 18.6 has it is unmeasured.
- `#unavailable(iOS 18)` branches in tests and code become dead once the target moves; the target PR should remove them.
