---
name: Demo side and system effects
description: Demo data never touches the account's schedule, reminders or alarms; one shelf per side; forgetters vs RyftApp; tests that prove it
type: project
---
Demo data's side (6c8 round 3) in BedtimePlanner and anything that schedules on iOS:

- **One shelf.** Per-account things on UserDefaults (`sleep.schedule.<id>`, `sleep.planned.<id>`) go through one
  `Shelf` (`.account(id)` / `.demo` in memory). `env.auth.accountID` alone isn't "the side": Demo keeps the account ID.
- **System effects are the account's only.** Demo sets, moves and removes no notification or alarm (`!env.isDemo`
  gates on schedule/cancel/sync). Teardown is skipped only while `keepsTheAccounts` (demo shown and the system's
  account is still signed in). A sign-out or session expiry with Demo on must still take the account's alarms away,
  because the sign-out wipe itself cancels nothing; only the planner's teardown does.
- **Previews/tests on `AppState.preview()` are demo** (demoOverride true): a preview that needs a refused alarm or a stuck
  Turn off must use an account graph (`.test`).
- **Forgetters run in `state.reset()`**: the Demo switch (Profile's setDemoMode/endDemo, the only writers) and account
  changes. Keep the synchronous forget in ScreenModels' `forgetsAccountState`, and only the async refresh in RyftApp.
  A test proves the wiring through `ScreenModels` + `state.reset()` (deleting the line fails it). Retain ScreenModels
  (`withExtendedLifetime`) when its forgetters hold models weakly.
- **Default arguments are nonisolated**: `auth: AuthService = .preview()` or `= MockWakeAlarms()` in a @MainActor helper
  fails to compile; take an optional and resolve inside.
- **"Nothing sent" vs "answered"**: `ReadScheduler.run` returns nil when nothing was sent. `Repository.readUserBack(since:)`
  exposes that as a Bool. To go offline exactly between a write's answer and its read-back, use a raw
  `withObservationTracking { _ = model.prefs } onChange: { MainActor.assumeIsolated { … update(false) } }`. Its
  onChange fires synchronously in willSet, while ObservationWatch defers to a Task.
- **Mutation check without dead code** (no unused lets) lets mutant builds stay strict and incremental. Split mutants when
  one fix's undo also breaks another fix's test (A vs item 1).
- zsh: never `G="git -C …"; $G add`. It doesn't word-split, and a half-run staging script leaves the file mutated.
