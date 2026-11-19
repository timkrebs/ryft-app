---
name: validating the integrated RYFT app
description: How to capture real, navigated screens of the demo app without editing the worktree
type: reference
---
- No idb/axe: tap via an XCUITest driver. Copy the worktree (rsync, no .git) to scratchpad/uiv-*/src and drop a temporary
  `RyftUITests/ZZValUITests.swift` there (script = `cmd:arg;cmd:arg`, env TEST_RUNNER_VAL_*; commands wait/tap/tapbutton/reveal/shot/frames/dump).
  Build once with `build-for-testing -testPlan Full`, then `test-without-building -only-testing:RyftUITests/ZZValUITests/testScript` per scene.
- A failed `tap` of a missing id aborts the script (the later steps don't run); `frames:` on an id with several matches aborts too.
- Launch args: `-RyftTab profile|sleep`, `-RyftSleepMode plan`, `-RyftScreen <DebugScreen>` (bedtime, notifications, syncDetails,
  signInMethods, report-problem, sync-check, ...), `-uiTestImportFiles plans.csv,workouts.csv -RyftResetTrain YES`, `-importUploadsUnavailable YES`.
- Profile row ids are `profile.<case>` (ProfileRows.swift). Journal row only exists after Today has loaded (launch on today, wait, tap tab.profile).
- Bedtime & wake: Turn off row exists only when a schedule is set (set up from Sleep > Bedtime > `sleep.bedtime.setUp`; state persists across launches in the sim).
- `xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large` is device-wide and sticky.
- Shared-Mac gate: `pgrep -f xcodebuild` is inflated by other agents' wait loops (their command lines contain the word); use `pgrep -x xcodebuild` and say so. Load can sit above 200 for 30+ min.
- Don't edit a shell script while it is running (sh reads it incrementally).
- Known integrated-only bug class: hosted tests apply `.toggleStyle(.ryft)` themselves; a fullScreenCover (import) showed system switches in the real app.
