---
name: project-simctl-spawn-harness
description: Release-optimised numbers and fast mutant runs for pure-Foundation app code without an app build — swiftc for the iOS simulator + simctl spawn; xcodebuild test leaves the sim shut down
metadata:
  type: project
---

Used for P1 (fast RFC 3339 parsing, 2026-10-23, `perf/fast-date-parsing`):

- **Release numbers in seconds.** Code that compiles standalone (the contract set: `Networking/Models.swift`,
  `DateParsing.swift`, `SleepMath.swift`, `App/Formatting.swift`) builds for the simulator with
  `xcrun swiftc -swift-version 5 -O -wmo -parse-as-library -target arm64-apple-ios17.0-simulator -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" …`
  and runs with `xcrun simctl spawn <udid> <binary> <args>` (host paths readable; the "incompatible sysroot" clang
  warning is harmless). "Before" = `git show origin/main:<file>` compiled the same way. Same -O/WMO as Release, the
  simulator's own Foundation. Add `setvbuf(stdout, nil, _IOLBF, 0)`: a trap loses buffered output.
- **The shared Mac is loaded**: formatter-heavy "before" numbers had p90 ≈ 2× median; run each side 3× and report
  medians.
- **Mutants in seconds.** For pure code, a python script that extracts the test's case tables and generator from the
  Swift Testing file into a macOS `swiftc` harness ran 36 mutants in ~2 min (vs ~4 min per mutant through
  xcodebuild). Check the formatter/Foundation behaviour it relies on matches the simulator first (probe both).
- **xcodebuild test shuts the device down** when it finishes (seen 3× that day): `simctl spawn` then fails with
  "device is not booted". `simctl boot` + `bootstatus -b` again.

**Why:** the ticket asked for Release simulator numbers; a Release app build plus a scratch launch hook (the
profiler's way) costs minutes and disk ([[project-dev-machine-disk]]).

**How to apply:** perf work on parsers, mappers, encoders and other Foundation-only code; mutation checks per
[[feedback-tests-pin-decisions]]. Related: [[project-simulator-and-tools]].
