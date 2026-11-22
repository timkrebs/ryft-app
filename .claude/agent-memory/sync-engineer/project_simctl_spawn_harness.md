---
name: project-simctl-spawn-harness
description: Release-optimised numbers and fast mutant runs for pure-Foundation app code without an app build — swiftc for the iOS simulator + simctl spawn; xcodebuild test leaves the sim shut down
metadata:
  type: project
---

Used for P1 (fast RFC 3339 parsing, 2026-10-23, `perf/fast-date-parsing`):

- **Release numbers in seconds.** Code that compiles standalone (the contract set: `Networking/Models.swift`,
  `DateParsing.swift`, `SleepMath.swift`, `App/Formatting.swift`) builds for the simulator with
  `xcrun swiftc -swift-version 5 -O -wmo -parse-as-library -target arm64-apple-ios18.6-simulator -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" …`
  and runs with `xcrun simctl spawn <udid> <binary> <args>` (host paths readable; the "incompatible sysroot" clang
  warning is harmless). "Before" = `git show origin/main:<file>` compiled the same way. Same -O/WMO as Release, the
  simulator's own Foundation. Add `setvbuf(stdout, nil, _IOLBF, 0)`: a trap loses buffered output.
- **The shared Mac is loaded**: formatter-heavy "before" numbers had p90 ≈ 2× median; run each side 3× and report
  medians.
- **Mutants in seconds.** For pure code, a python script that extracts the test's case tables and generator from the
  Swift Testing file into a macOS `swiftc` harness ran 36 mutants in ~2 min (vs ~4 min per mutant through
  xcodebuild). Check the formatter/Foundation behaviour it relies on matches the simulator first (probe both).
- **Real Swift Testing suites in SwiftPM (2026-11-22, SyncScreen).**
  - Target `Ryft` = copies of `Models.swift`, `DateParsing.swift`, `App/Formatting.swift`, `SleepMath.swift` and the file under test, plus stubs (`HealthDelta`, `APIClient` with its two coders).
  - Test target = the test file cut at the first suite that needs mocks. `@testable import Ryft` works as-is.
  - `swift test --filter <Suite>`: about 60 s the first time, then about 30 s per mutant. 18 mutants ran without one xcodebuild.
  - Engine-level mutants still need xcodebuild. Group them so each targeted test fails for one known reason, and read the reasons from the result bundle (see [[project-simulator-and-tools]]).
- **xcodebuild test shuts the device down** when it finishes (seen 3× that day): `simctl spawn` then fails with
  "device is not booted". `simctl boot` + `bootstatus -b` again.

**Why:** the ticket asked for Release simulator numbers; a Release app build plus a scratch launch hook (the
profiler's way) costs minutes and disk ([[project-dev-machine-disk]]).

**How to apply:** perf work on parsers, mappers, encoders and other Foundation-only code; mutation checks per
[[feedback-tests-pin-decisions]]. Related: [[project-simulator-and-tools]].
