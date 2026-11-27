---
name: integration-run-ui-smoke
description: A big PR's final local run must include the whole UISmoke plan; per-area UI test lists in briefs miss tests that touch shared screens
metadata:
  type: feedback
---

The last local integration run before opening a PR that changes shared screens (Welcome, the tab bar, Profile, the
session screen) runs the **whole UISmoke plan**. Running only the UI tests of the areas each agent touched isn't enough.

**Why:** on 2026-11-20 PR 6 (#131) went red in CI's UI smoke. `DemoExitUITests` looked for Welcome's
`app.buttons["Log in"]`. PR 6 A had made "Have an account? Log in" a single button, and updated `StoreSmokeUITests` but
not DemoExit. Every brief listed per-area UI tests (MyDay, TrainHistory, SignedOut…), and none named DemoExit, so the
failure first showed up in CI. That cost a ~35-minute CI cycle. The same run also showed PR 6's Unit plan at 15 of its
15 CI minutes; the limit was raised to 25.

**How to apply:**
- Add `xcodebuild test-without-building -testPlan UISmoke` (about 15 min locally) to the integration script
  (`int*/run.sh`), after the Unit plan.
- When a PR changes a control's label, grep `RyftUITests/` for the old label (`buttons["…"]`, `staticTexts["…"]`), and
  prefer identifiers.
- Compare the Unit and UISmoke step times on CI with the `timeout-minutes` in `ios.yml` when a PR adds many hosted tests.

See [[ci-ui-timeouts]] and [[release-build-check]].
