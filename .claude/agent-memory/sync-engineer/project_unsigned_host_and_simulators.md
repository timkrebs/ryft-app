---
name: project-unsigned-host-and-simulators
description: HKSource.default() throws an uncatchable ObjC exception in unsigned builds (test host, CI); shared simulators can lose their data dirs mid-session
metadata:
  type: project
---

1. `HKSource.default()` raises NSGenericException ("bundle identifier of the client is nil") in builds made with
   `CODE_SIGNING_ALLOWED=NO`: the unit-test host and CI simulators. Swift can't catch it, so a unit test that touches
   it crashes the run. Shipped code that uses it (strength-workout export) only runs signed on device.
   **How to apply:** in new HealthKit code that must also run in tests/simulator, exclude RYFT's own records by
   `Bundle.main.bundleIdentifier` (as `HealthProbe.isRYFT` does since T3, 2026-10-22), never `.default()`.
2. On 2026-10-22 the default CoreSimulator device set lost every device's data directory except one booted device
   while several agents worked in parallel; xcodebuild then failed with "Failed to clone device" / "cannot be located
   on disk". `xcrun simctl erase <udid>` recreated it. A freshly erased simulator shows 12-hour times in German, so
   screenshots need `-AppleICUForce12HourTime NO` (as `scripts/screenshots.sh` passes).
   Later the same day the shared iPhone 17 was shut down mid-run by someone else: every UI test then failed at
   launch ("Launchd job spawn failed", FBSOpenApplicationServiceErrorDomain 3) while unit tests had passed.
   **How to apply:** on those errors check `~/Library/Developer/CoreSimulator/Devices/<udid>` and
   `simctl list` (Shutdown?) first; boot it and rerun before suspecting code. Related:
   [[project-dev-machine-disk]].
