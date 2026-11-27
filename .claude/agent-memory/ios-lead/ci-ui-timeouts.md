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

**The self-hosted runner is this Mac**, the same machine the local agents build and test on. On
2026-10-29, main's UI smoke after #72 took 9 minutes before its first test started, while several agent simulators were busy,
and hit the 15-minute step limit with all 21 cases passing. A timed-out step can leave its `.xcresult` in the kept
workspace; the next run then fails with "Existing file at -resultBundlePath" before any test runs. #74 removes the bundle
first. Before calling a red step a regression, compare when the step started with when its first test started.

**"pending 0" can still mean running (2026-11-15).** On #109, `gh pr checks` and `gh run list` showed the iOS jobs as
`pending 0` / `queued` for all 17 minutes of a job that went on to pass. To see whether it really runs:
- `xcrun simctl list devices`: a booted `RYFT CI <run>-<attempt>` means the job is running;
- `pgrep -fl Runner`: shows a `Runner.Worker`.

Don't call that a stuck runner.

**Wedged CI simulator (2026-10-30).** Symptom: every branch fails the Unit step before any test runs, with "test runner hung before establishing connection" (after about 6 min) or "Simulator device failed to launch … did not return a process handle", while `main` was green on the same runner shortly before. Load alone doesn't explain it: it persisted at load 5.
- **Prove it first:** run the branch on a fresh `simctl create` simulator. Both branches passed there.
- **Fix:** with no job in progress, `simctl delete` the "RYFT CI" device. `scripts/ci-simulator.sh` recreates it on the next run, and the user's own simulators are untouched.
- **Don't** just keep rerunning, and don't `shutdown all` or restart CoreSimulatorService without the user.
- **Root fix: #80** (opened 2026-10-30). It gives every CI job its own simulator, "RYFT CI <run>-<attempt>", and an `if: always()` cleanup step deletes it and its clones. The hang recurred 8+ times while it waited. A PR branched before #80 still runs the old reusing script, so the delete-and-rerun fix applies to it until it merges `main`.

**Jobs stay "queued" for an hour: the runner is offline (2026-11-19).** The listener log
(`~/actions-runners/ryft-app/_diag/Runner_*.log`) ended with `TaskAgentSessionExpiredException: Runner session is invalid`
at 04:00Z. The listener then exits with code 0, and the launch agent (`actions.runner.<owner>-ryft-app.<runner name>`,
no KeepAlive) doesn't restart it. Its exact label: `ls ~/Library/LaunchAgents | grep actions.runner`.
- **Check:** `gh api repos/<owner>/ryft-app/actions/runners` shows `offline`.
- **Fix:** `launchctl kickstart gui/$(id -u)/<that label>`. Twenty seconds later it was
  online and took the queued job.
- Check this first whenever a run sits in `queued` and no `Runner.Worker` process exists.

**"Unable to boot device because it cannot be located on disk" (2026-11-18).** A storage-cleanup task of the user's had
recreated `~/Library/Developer/CoreSimulator` mid-run, so every older simulator, Xcode's defaults included, stayed listed
by `simctl` but had no data folder. Check `ls -ld ~/Library/Developer/CoreSimulator` (a fresh date gives it away) and
`[ -d …/Devices/<udid> ]` for each device. Delete our stale "RYFT …" devices, rerun the failed job, and tell the agents
their simulators are gone. It isn't the PR.
