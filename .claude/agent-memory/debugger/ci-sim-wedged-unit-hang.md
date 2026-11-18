---
name: ci-sim-wedged-unit-hang
description: Unit step "test runner hung before establishing connection" / "did not return a process handle" on every PR while main passed = the persistent "RYFT CI" simulator is wedged, not code
metadata:
  type: project
---
2026-10-30: PRs #76/#77 failed at Unit on the self-hosted runner's reused "RYFT CI" sim (77B50D3F, iOS 27.0, listed under both 27.0 and 27.1). Both branches passed Unit (2663 cases, ~66 s) on a freshly created iPhone 17 Pro iOS 27.0 sim, same flags. So the sim, not code.
**How to apply:** first reproduce on a fresh `simctl create` sim; if green, recommend deleting the CI sim (scripts/ci-simulator.sh recreates it) when no job is running.

**Recurrence (2026-10-30, later):** a fresh "RYFT CI" passes its first job; the next job on the reused device hangs (57243E57: #78 passed 09:50Z, main c8dcf2a 10:13Z and PR #79 13:20Z hung). Not load. Deleting the device fixes only one job, so the reuse itself is the pattern. Also seen: a device whose data dir vanished.
**Related find:** parallel-testing clones go to `~/Library/Developer/XCTestDevices` (`simctl --set` that path), named "Clone N of <source>"; 277 had leaked since 2026-10-21 (never deleted), disk at 90%. Whether that causes the hang is unproven.
**Fix (branch ci/fresh-ci-simulator):** ci-simulator.sh creates "RYFT CI <run id>-<attempt>" every job (CI_SIM_NAME overrides); `scripts/ci-simulator-cleanup.sh` as an `if: always()` step deletes it, its clones, and "RYFT CI*" devices >1 day old. If hangs persist on a fresh device, look at the leaked XCTestDevices / disk next.
