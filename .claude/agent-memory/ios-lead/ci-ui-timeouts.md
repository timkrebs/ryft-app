---
name: ci-ui-timeouts
description: How to tell a slow GitHub runner from an app regression when a RYFT UI test exceeds its execution-time allowance on CI
metadata:
  type: project
---

When a UI test such as `StoreSmokeUITests.testDemoTabsWalkthrough` exceeds its allowance on CI:
1. **Tally first.** Collect the test's duration from every recent run (`gh run view <id> --log`, grep `' passed (`), with and
   without the suspect PR. Include nightly runs on `main`.
2. **Break down the steps.** Sum the time per XCUITest activity from the `t = …s` lines: wait for idle, find, checking existence,
   synthesize. Only lookups slow → main thread or accessibility tree. Everything slow → runner.
3. **If it still points at the app,** have performance-profiler run a baseline build that differs by exactly that PR, CPU-starved
   (`yes` × 3 per core).

A test that times out is **not** retried by `retryOnFailure`; xcodebuild moves on to the next test.

**Why:** on 2026-10-22, #27 timed out in 4 of 9 CI runs and other branches in 0 of 19. That looked like #27, but the nightly run
on `main` timed out too, and the starved baseline reached 60.7 s. Verdict: runner. #30 raised UISmoke and Full to 180 s.

**How to apply:** before blaming a PR for a red UI smoke, or before calling it "infra", do steps 1–2. See [[integration-branch]].

**Check the device first.** On 2026-10-22 the runner image's final Xcode 27.1 brought an iOS 27.1 runtime with only
"iPhone Duo". `scripts/ci-simulator.sh` silently picked it, the tabs became a side strip, and UI smoke failed on every
PR. Look at the xcresult's UI hierarchy (window size) and at the `ci-simulator:` log line (#35 added it) before blaming
code or timing.

**Timing asserts in unit tests:** 45 ms locally became more than 1 s on a CI runner (2026-10-22, the hostile-catalog test on
#33). Bound against the algorithmic failure you're guarding (e.g. quadratic → seconds), never against "fast" on this Mac.
Don't brief implementers with "well under 100 ms".
