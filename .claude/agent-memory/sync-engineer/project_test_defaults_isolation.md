---
name: project-test-defaults-isolation
description: Tests sharing a UserDefaults.standard key race under the Unit plan's parallel suites; inject UserDefaults and give each rig its own suite; mutants that write .standard leave residue on the sim
metadata:
  type: project
---

Code review of F1 (2026-11-21): `train.pausedPlanID` lived in `UserDefaults.standard`, and the Unit plan runs suites in
parallel (`SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=4`), so tests that set, save/restore or read the key raced each
other; a `defer` restore can even put back another test's value. Fix that was asked for: inject the `UserDefaults`
(`.standard` in the app) and have every rig pass `UserDefaults(suiteName: "test-" + UUID().uuidString)!`
(`UserDefaults.isolated(pausedPlan:)` in `RyftTests/TrainLibraryTesting.swift`); no save/restore dances.

**Why:** a shared process-wide key is a hidden coupling between suites that only shows under parallel, random order.

**How to apply:**
- When a type keeps state in `UserDefaults.standard`, give it a `defaults:` init parameter before writing tests that
  set the key. `AnchorScopeTests` (`AccountScope.defaultsKey`, save/restore on `.standard`) still has the old pattern.
- Prove isolation deterministically: two rigs alive in one test, write in one, the other sees nothing; a mutant that
  puts a rig back on `.standard` must fail it.
- A mutant that writes `.standard` leaves the key in the test host's container on the simulator: run those mutants last
  and `xcrun simctl uninstall <udid> dev.timkrebs.ryft` after each.
Related: [[project-mutation-runner]], [[feedback-tests-pin-decisions]].
