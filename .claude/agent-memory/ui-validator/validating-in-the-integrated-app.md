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
- Hosted-state renders (states the demo can't reach: offline, failed, pending): drop a temp `RyftTests/ZZValHostedTests.swift` into the rsync'd copy,
  use `HostedWindow.run(width:402,height:874,bottomInset:0,...)` + the previews' own builders (`InsightsPreview.content(...)`, `StrainPreview.content(...)`),
  `drawHierarchy` to PNG, run `test-without-building -only-testing:RyftTests/ZZValHostedTests` with `TEST_RUNNER_VAL_DIR=...`. Use height 874: a 2600 tall window rendered the page scrolled to its middle.
  The hosted host runs in a German region (decimal comma, "19. Nov"): useful as the de_DE capture, not a bug.
- `-RyftFault days=503,...` in demo mode did NOT produce a visible error/offline state in 6 s (Strain/Insights/Today unchanged); `isOffline` is false in demo by design. Use hosted renders instead.
- `-RyftOpenWorkout YES` re-pushes the workout whenever the Strain stack is rebuilt (autoOpen re-reads UserDefaults), so it can't test tab reselect; push a row by tap instead (`strain.row.workout.<uuid>`).
- `-RyftScreen refresh-details-send` is the real presented sheet (RefreshDetailsSheet, `refreshDetails.send` -> Report a problem pushed inside it).
- macOS `sips -c H W` crops from the centre; add `--cropOffset 0 0` for the top. `sed -i ''` on macOS.
- Frames inside sheets are scaled (0.96), so 44 pt controls read 42.2 there; not a defect.
- PR 5 (feat/nocturne-tabs a815d1b) known remaining Theme.accent users (PR 6 / gate PR owns them): AddActivitySheet, SleepPlannerView, Journal, Notifications, StatusViews RefreshDetailsSheet "Send to RYFT".
