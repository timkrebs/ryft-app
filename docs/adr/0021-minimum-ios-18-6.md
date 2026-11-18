# 0021 — The minimum iOS is 18.6

- Status: accepted (2026-11-18, the user's decision, for the beta and onward)
- Deciders: Tim Krebs; recorded by ios-architect
- Applies to: `IPHONEOS_DEPLOYMENT_TARGET` of `Ryft`, `RyftWidgetsExtension`, `RyftTests` and `RyftUITests`, and of any
  target added later (the Notification Service Extension); every `#available`, `#unavailable` and `@available` check;
  the deployment-target constants in `RyftTests/ExerciseStripSymbolTests.swift` and
  `RyftTests/Activities/SportCatalogTests.swift`; `CLAUDE.md`, `README.md`, `docs/APP_STORE.md`, `docs/STATUS.md`; every
  gate that asks for a run on an older iOS

## Context

- **Until now everything declared iOS 17.0.** CI and the user's iPhone run iOS 27. Older runtimes were run by hand.
- **Today's gates on 17.0 and 18.0 found SwiftData faults that only iOS 17 has:**
  - only the newest container of a schema takes inserts (T0.6). After demo data the account's store refuses saves, and
    on 17.0 demo data itself breaks (T0.8);
  - a `@ModelActor` runs its jobs on the thread that made it (T0.1);
  - a rollback of a refused change to existing rows traps (ADR 0018, decision 6).
- **They cost machinery:**
  - P1b's reopen of the account's store (ADR 0019 as first written; amended, not built);
  - `#unavailable(iOS 18)` branches and `withKnownIssue` wrappers in the tests;
  - iOS 17 notes in `ReadModelDrain`, `ConsentState` and `TrainStore`.
- **iOS 18.0 has one known trap of its own.** Reading a relationship of a deleted `LocalSession` that a screen still
  holds fails with "Context is missing". #107 (ADR 0020) fixes it. Nobody has measured it on 18.6 yet.
- **iOS 18 runs on every iPhone that runs iOS 17:** iPhone XS, XS Max, XR, SE (2nd generation) and later. The 17.0 and
  18.6 simulator runtimes list the same iPhones. iOS 26 drops the XS, XS Max and XR.
- **Few users are affected.** The App Store 1.0 hasn't shipped, and STATUS records the TestFlight testers on iOS 27.
- **The iOS 18.6 simulator runtime is installed on this Mac.**

## Decision

1. **The minimum is iOS 18.6** (`IPHONEOS_DEPLOYMENT_TARGET = 18.6`) for the app, the widget extension and both test
   targets.
   - The project level says the same.
   - A target added later is set to 18.6 when it is added. Xcode's default for a new target is the newest SDK.
2. **Why 18.6 rather than 18.0:** every device that runs iOS 18 can update to it, and one iOS 18 runtime is cheaper to
   test than two.
3. **No code branches on iOS 17.**
   - New code adds no check for iOS 18.6 or older.
   - Checks for iOS 26, 26.1 and 27 stay.
4. **Simulators:**
   - CI keeps the newest runtime (`scripts/ci-simulator.sh`, 27.2 today).
   - **18.6 is the oldest-runtime gate.** Where a design, STATUS or a review asks for a run on iOS 17, 18 or "an older
     iOS", that means one run on 18.6. The destination is `platform=iOS Simulator,OS=18.6,name=iPhone 16 Pro`, because
     the 18.6 runtime has no iPhone 17 Pro.
   - Runs on 17.0 and 18.0 stop.
   - The first 18.6 run measures T0.1, T0.6 and the 18.0 trap. Its results go into the facts suites and STATUS.

## Consequences

**App Store reach.** No iPhone is lost. Only people who haven't updated from iOS 17, or from 18.0–18.5, are left out
until they update, which is free on the same phone. On iPad (compatibility mode) the app needs iPadOS 18.6, which the
oldest iPads that stopped at iPadOS 17 don't get. Choosing 26 instead would drop the XS, XS Max and XR.

**TestFlight testers on iOS 17** can't install a build from this change on.
- The build they have keeps working until it expires, 90 days after its upload. The platform has no minimum-version
  check: the `426 app_update_required` proposal in `API_REQUESTS.md` isn't built.
- That build keeps iOS 17's faults: after demo data, the account's new rows aren't saved until a relaunch.
- Updating iOS is the way forward. The CHANGELOG line says so.

**What goes.** Each item below can only run below iOS 18. A test bundle that targets 18.6 doesn't install there.
- P1b's reopen of the account's store (ADR 0019, never built).
- `SessionView`'s drag fallback for `ManualScrollReporter`. The scroll phase stays.
- `@available(iOS 18.0, *)` on `StartWorkoutControl`, and the `if #available(iOSApplicationExtension 18.0, *)` around it
  in `RyftWidgetsBundle`.
- In the tests:
  - every `#unavailable(iOS 18)` branch;
  - the `withKnownIssue` wrappers those branches switch on;
  - the last, iOS 17 arm of the `#available` chain that #107 adds.
- In STATUS, the iOS 17 known issue goes. Each "run on iOS 17/18" gate becomes an 18.6 run.

**What stays**, because it still guards 18.x or is right on its own:
- **`ReadModelDrain` makes and awaits its writer on its own executor** (ADR 0018, decision 1). iOS 18 is reported to
  follow the maker, as 17.0 does. 18.6 isn't measured. Made and awaited off main is right under either rule.
- **A refused save is never rolled back** (ADR 0018, decision 6). Saves can still be refused (a full disk, a wipe), and
  nobody has measured the rollback on 18.
- **The consent withdrawal is also kept in defaults.** It holds in a background launch and against any refused save.
- **`TrainStore.wipe` deletes `PendingImport` object by object.** The batch delete removed the external file on the 27
  simulator, and that's the only place it was checked.
- **#107's guards for the 18.0 trap** (`TrainCoordinator.releaseRows`, and tests that count later 18 releases as 18.0)
  stay until 18.6 is measured.

**The strict build doesn't flag the redundant checks.** Measured with Xcode 27.2 (Swift 6.4.2) at an 18.6 target:
none of today's 18.0 checks warns. `UselessAvailabilityCheck` fires only inside an enclosing `@available` scope,
never because of the deployment target. So removing them is cleanup, and review keeps new ones out. SwiftLint's
`deployment_target` rule could report them (as warnings) if `.swiftlint.yml` set its iOS and iOS-extension targets to
18.6.

**APIs that need no check now:**
- SF Symbols up to iOS 18.5, which is all of SF Symbols 6 (`figure.run.treadmill` is one). The symbol tests' threshold
  moves to 18.6.
- HealthKit's iOS 18 distance types: rowing, paddle sports, cross-country skiing and skating.
- `onScrollPhaseChange` and `ControlWidget`.

Adopting any of them is a change of its own.

**Tooling.** The project builds with Xcode 26 or newer. App Store builds need the iOS 26 SDK anyway
(`docs/APP_STORE.md`).

**The first 18.6 run** (2026-11-18, the iPhone 16 Pro simulator, Xcode 27.2): 243 of 244 tests pass in the suites this
change touches, `DateParsingTests` and the consent suites; the touched suites (155 tests) pass on 27.2 too.
- **T0.6 doesn't reproduce.** An insert lands in the older and the newer container, and the account's writes after the
  demo save (the `TwoContainers` probes; `ReadModelDrainTests`' expectations that no longer have a `withKnownIssue`).
- **T0.1 isn't settled.** The invariant `ReadModelDrain` relies on holds: made and awaited off main, a model actor's
  jobs run off main (`ReadModelContextFactsTests`, `ReadModelOffMainTests`). Which thread decides is still unmeasured,
  because the observations assert only on 27.
- **#107's trap shows in another form.** `TrainStoreWipeTests/aRowStillHeldStaysUsableAndNothingComesBack` traps with
  "Never access a full future backing data" (`BackingData.swift:739`, on a `LocalSessionExercise`), where 18.0 said
  "Context is missing". It does the same on `main`, and #107 fixes the test and the production path.

**What could go wrong:**
- **18.6's SwiftData behaves like 18.0's, or worse.** That covers #107's trap, T0.1 and T0.6. Until the first 18.6 run,
  code and tests treat 18.6 as 18.0.
- **A regression that shows only on 18.x.** CI runs 27.2 only. The 18.6 gate before each External and App Store build is
  the net. A scheduled 18.6 job in CI is a possible follow-up.
- **A target added later keeps Xcode's default** and doesn't load on 18.6–27.1. Decision 1 and review cover it.
- **A guard removed that 18.x still needs.** Only guards that can't run on 18.6 go now: `#unavailable(iOS 18)`, and the
  `else` of `#available(iOS 18, *)`. The rest wait for a measurement.

## Alternatives

- **Stay on 17.0.** That keeps the people who haven't updated from iOS 17, and no extra hardware. It costs:
  - P1b's reopen;
  - demo data that is broken on 17.0;
  - the rollback trap;
  - a second thread rule for model actors;
  - a 17.0 run for every persistence change.
- **18.0.** It removes the iOS 17 faults too. But it leaves 18.0–18.5 to test, 18.0 has its known trap, and covering
  18.0 and 18.6 doubles the gate. Every device that runs 18.0 can run 18.6.
