---
name: today-scenario-shots
description: Capturing Today demo scenarios on the shared simulator — screenshots.sh inherits the sim's text size and shows coach marks; how to get clean shots
metadata:
  type: project
---

`scripts/screenshots.sh "iPhone 17" <scenario…>` (2026-10-29, F3) produced unusable shots: the assigned simulator was left at
`content_size accessibility-extra-extra-extra-large` by an earlier run, and Today's coach-mark overlay covered the gauge.
The script also writes into `docs/screenshots/` (move new PNGs to the scratchpad, don't commit them).

**Why:** the script sets status bar and appearance but neither the text size nor the coach marks.

**How to apply:** `xcrun simctl ui <udid> content_size large`, then launch yourself:
`simctl launch <udid> dev.timkrebs.ryft -demoMode YES -RyftTab today -RyftScenario <name> -appearance dark -coachMarks.today.done YES`,
wait ~4 s, `simctl io <udid> screenshot`; restore the previous content size afterwards. Parallel test runs use clones ("Clone 1 of iPhone 17") that inherit the
original's content size: at AX-XXXL `CalibrationNoteUITests.testTheLinkOpens…` fails (`link.isHittable`); set `large` while
the sim is booted (it can't be set while shut down), then shut it down before `xcodebuild test`. For a scrolled AX3 shot,
a UI test with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXL`, `swipeUp`, and
`XCTAttachment(screenshot:)` kept always; export with `xcresulttool export attachments`. Related: [[simctl-spawn-harness]].
