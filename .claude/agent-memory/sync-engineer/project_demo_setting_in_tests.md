---
name: project-demo-setting-in-tests
description: Unit tests must never write Settings.shared.demoMode (e.g. via ProfileViewModel.setDemoMode); the simulator host app runs in demo and other code reads the singleton
metadata:
  type: project
---

`Settings` is a singleton with a private init, and `AppEnvironment.test()` uses `settings: .shared`. In the simulator
`demoMode` defaults to true and persists in the host app's `UserDefaults.standard`. Several readers bypass the
environment's `demoOverride`:
- `TrainCoordinator` (`isDemo ?? { Settings.shared.demoMode }`);
- `FeatureFlags` (`demo: Settings.shared.demoMode`);
- `WorkoutLauncher.hasAccount`;
- `RyftApp`'s `.onChange(of: settings.demoMode)` in the running host app.

So a test that calls `ProfileViewModel.setDemoMode(false)` flips the host app out of demo mid-run, can break parallel
suites, and leaves the value persisted for later runs.

**Why:** found on 2026-10-23 while testing I3's "forget demo matches when demo ends". I split the side effects into
`ProfileViewModel.demoModeChanged(_:)` and tested that instead; `setDemoMode` only writes the setting and calls it.

**How to apply:** for any behaviour tied to toggling demo or another `Settings.shared` value, put the effect behind a
method the test can call without writing the setting. Related: [[feedback-test-waits-on-actors]].
