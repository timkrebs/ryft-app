---
name: project-ci-runner-shares-the-mac
description: The self-hosted CI runner is this dev Mac; under swap/disk exhaustion xcodebuild exits 70 "Unable to find a device" locally and in CI — rerun, don't debug
metadata:
  type: project
---

Seen 2026-11-18 (D1, #109 merge of main): from about 09:00 to 09:34 local the Mac had 5 GB disk free, 38–44 GB swap
used and load 700–1000 (about ten booted simulators from parallel sessions plus CI). Then:
- `xcodebuild test-without-building` exited **70**: "Unable to find a device matching the provided destination
  specifier", although `simctl list` showed the device Booted. `ps -ax` and `top -l 1` hung for minutes.
- CI's "Build, unit tests, UI smoke" failed the same way (exit 70 in the Unit step). The runner lives at
  `~/actions-runners/ryft-app` on this Mac, so CI shares its CoreSimulator, disk and swap.
- Hosted render tests fail under that load: `GlowTileKindTests.labelInkIsDrawn` got a blank pixel, with the log line
  "image provider … timed out while waiting for phase 6". UI tests overran their 3-min allowance in Tear Down.

- The load lasted past 11:00. The 1-min average swung between 14 and 1000 within minutes, so a single low reading
  means nothing. CI's UI smoke step then hit its 15-min cap twice (tests at 30–126 s each, 23 of 48 done).
- UI signatures that don't mean a code bug: "Critical process Ryft crashed in (null)" with no `Ryft-*.ips` in
  `~/Library/Logs/DiagnosticReports` (a killed process); "main thread busy for 30.0s" (CPU starvation);
  "Simulator device failed to launch … No such process"; and "CoreSimulatorService connection interrupted", after
  which the run hangs and booted simulators, CI's included, show Shutdown.
- `simctl bootstatus -b` hung 8+ min twice on my device. `simctl erase` followed by a fresh boot finished in 1:36.

**Why:** these failures come from the infrastructure, not the code. The lead confirmed the window and the rule: check
the run's start time, then `gh run rerun --failed <id>` before debugging.

**How to apply:** before any long run, check `sysctl -n vm.loadavg`, `sysctl vm.swapusage` and `df -m`. Launch with a
retry loop that sleeps and tries again on "Unable to find a device". Rerun a render or layout failure on its own. For
a red CI job, compare its start time with the load window. Related: [[project-dev-machine-disk]],
[[project-simulator-and-tools]], [[project-ui-smoke-crashlog-wait]].

**UI smoke has little slack** (2026-11-18, #107): green runs of the step took 652–782 s against its 900 s cap. A rerun
with 31 passed and 0 failed still timed out, while my local build-for-testing ran alongside. So a smoke timeout with no
failed case is load. Keep builds off the Mac while CI's smoke step runs.

**`pgrep -f "<cmd>"` in an until-loop matches its own shell** (its command line contains the string), so the wait
never ends. Match on a PID or use `pgrep -f "^gh run download"`.

**Lead's rule, 2026-11-18 (P1b): one simulator at a time.** With three of mine booted and load near 1000, CI's UI smoke
steps timed out and no PR could merge. Boot one, run there (`-parallel-testing-enabled NO`, `-only-testing`), shut it
down, then the next OS. A runner script should `simctl shutdown` its simulator at the end; zsh reads a script once, so
editing it doesn't change a run already going.
