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
