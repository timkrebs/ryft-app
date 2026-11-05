---
name: simulators-one-at-a-time
description: Run one simulator at a time and no CPU burners; a wedged CoreSimulatorService can only be restarted by the user
metadata:
  type: feedback
---

One local simulator, one xcodebuild, no `yes` burners and no concurrent sims. CI beside one local simulator has been fine.

**Why:** on 2026-11-04 debugger ran 4 sims and 16 burners on a loaded Mac. CoreSimulatorService wedged: `simctl create`,
`boot` and `shutdown` hung, and the night's work stopped until the user ran
`killall -9 com.apple.CoreSimulator.CoreSimulatorService`. An agent's killall is refused by the permission check, and that
refusal is not worked around.

**How to apply:** put these limits in every brief that touches a simulator. `xcodebuild build-for-testing -destination
'generic/platform=iOS Simulator'` compiles without one. CI's parallel Unit plan is the natural load test. Watch `df`: a
disk at 0 stopped a build, and each derived-data folder is about 2 GB. See [[ci-ui-timeouts]].
