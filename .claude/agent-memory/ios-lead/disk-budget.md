---
name: disk-budget
description: The shared Mac's disk fills from scratch DerivedData and XCTestDevices clones; check df before each run, delete each run's build folder when done, and tell the user before deleting anything that isn't the session's own
metadata:
  type: project
---

On 2026-11-22 the disk reached 116 MB free mid-afternoon. Every Bash call then failed before it started (Claude Code
couldn't create its output file), so no cleanup command could run either. Two agents' runs died: N3's mutants and the
consent post-merge tests, where the simulator couldn't launch the app. Space came back once a run ended and freed its clones.

**Why it filled:**
- The session's scratchpad held 26 GB. Each ui-validator run left a ~1.5 GB `dd` folder, and there were also old
  post-merge builds and xcresults.
- `~/Library/Developer/XCTestDevices` held 51 GB of parallel-testing clones. CI and every agent's tests share it.

**How to apply:**
- Every brief that builds names a fresh `-derivedDataPath`, uses `-parallel-testing-worker-count 2`, runs
  `df -h /System/Volumes/Data` before each big run (stop under 8 GB), and **deletes its build folder and simulator at the end**.
- Delete a finished ticket's scratch `dd`, DerivedData and xcresults as soon as it merges, not at close-out.
- The session's own scratch is mine to delete. Anything else, such as XCTestDevices, `~/Library/Developer/Xcode/DerivedData`
  or simulators I didn't create, gets a proposal to the user first. `xcrun simctl --set testing delete all` clears the clones,
  but only when `pgrep -x xcodebuild` shows 0, because a CI run would die.
- Keep 1–2 GB of headroom that I can always free, so a cleanup command still has room to start.

See [[shared-mac-hygiene]], [[simulators-one-at-a-time]], [[big-programs-parallel]].
