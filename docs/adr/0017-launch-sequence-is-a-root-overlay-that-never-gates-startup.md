# 0017 — The launch sequence is a root overlay that never gates startup

- Status: accepted by the lead with the recency rule L9 (2026-11-16, Nocturne PR 3 `design: orbit gauge v3 and launch`; `docs/work/2026-11-16-nocturne/brief.md`
  §5, `plan.md` PR 3 L1 and L2, `launch-design.md`)
- Deciders: ios-lead (L1, L2); recorded by ios-architect
- Applies to: `Ryft/App/LaunchSequence.swift`, `Ryft/App/LaunchSequenceModel.swift`, `Ryft/App/LaunchHost.swift`,
  `Ryft/App/RyftApp.swift` (`init`, the `WindowGroup` root, `RootView.presentsSomething`, `LaunchSignpost`),
  `Ryft/Features/Today/TodayView.swift` (`GaugeEntranceConsumer`), `Ryft/Features/Train/TrainCoordinator.swift`
  (`QuickActionSceneDelegate`), every future root presentation, and anything that plays "once, when first seen"

## Context

- **§5 adds a 5.2 s animation to the cold-start path.** It turns the gauge into the orbit mark, then hands off to Today.
  Under Reduce Motion it is a static mark and a cross-fade.
- **L1: it never blocks the app, and a tap skips it.** L2: it plays only on a cold start into the foreground, never in
  UI tests, screenshot runs or `-RyftScreen`. Demo mode plays it.
- **Startup hangs on view lifecycle hooks.** These are:
  - the `afterFirstFrame()` barrier, opened by `LaunchSignpost.screenAppeared`;
  - `WorkoutLauncher.tabsAppeared`;
  - `OnboardingCoordinator.reachedTabs`;
  - Today's tasks;
  - the "launch" signpost.

  Anything that delays building `RootView` delays them all.
- **"Cold start" has no system API.** The app already tells a background launch apart by `applicationState` in
  `RyftApp.init`, and its views can be built in the background (`TodayGaugeEntrance`).
- **UI tests have no shared base.** Each class builds its own launch arguments, and `UITestSupport.launchDemo` serves
  only some of them.

## Decision

1. **The launch is an overlay over `RootView`, owned by the app root.**
   - `LaunchHost(model:) { RootView() }` is the `WindowGroup`'s view, and `LaunchOverlay` sits in its `.overlay`.
   - The model, `LaunchSequenceModel`, is `@State` on `RyftApp`, so it lives for the process.
   - It is not a root state and not a window.
2. **It never gates startup, and startup never waits for it.**
   - `RootView`, Today and every lifecycle hook are built and fire beneath the overlay, exactly as without it.
   - No code awaits the sequence, and the sequence awaits nothing but the scene's first `.active`.
3. **Before the first frame it adds a few property reads and one background-coloured fill.** The fill equals the system
   launch screen (`Graphite` = `Background`, pinned by a test). Nothing else is built until `.active`.
4. **It plays once per process, on a cold start into the foreground.** A cold start means two things:
   - `RyftApp.init` did not see `applicationState == .background`;
   - the scene's first `.active` arrives within 5 s of `init`.

   Its phases (`armed → playing → handingOff → done`, or `skipped`) end in terminal states. A return from the
   background, scene re-creation and a second scene never replay it.
5. **Harnessed launches skip it.** Any launch argument skips it unless `-RyftLaunchSequence play` is passed (which
   also overrides the recency skip L9, so harnessed runs are deterministic);
   `-RyftLaunchSequence skip` forces a skip. Real launches never carry arguments, and every UI test and screenshot run
   does.
6. **It yields to anything that wants attention.** Each of these skips it, or hands off at once:
   - a purpose launch: URL, user activity, shortcut item or notification response in `UIScene.ConnectionOptions`;
   - a root presentation (`RootView.presentsSomething`);
   - system UI (the scene going `.inactive`);
   - the background;
   - an open workout.

   A tap hands off at once.
7. **Covered counts as unseen.** `launchCoversRoot` is true in `armed` and `playing`. Anything that plays once when
   first seen treats it like the background and plays at the hand-off. Today's gauge entrance does this through its
   consumer; `OrbitGauge` is unchanged.
8. **Timing is a pure value.**
   - `LaunchSequence` stores the decision, `createdAt`, `startedAt`, `handOffAt` and the ending.
   - Phase, progress and hand-off are functions of a date.
   - The model refreshes `phase` on events and at `nextChange` deadlines on `AppClock`.
   - The view only renders `frame(at:)` inside a `TimelineView`, and leaves the hierarchy at the end.
9. **Accessibility.**
   - Reduce Motion, Low Power Mode and VoiceOver get the reduced variant (1.0 s plus a 0.25 s fade). VoiceOver also
     gets a "Skip" action.
   - The root is hidden from VoiceOver while covered. Focus goes to the root with `ScreenChanged` at the hand-off,
     unless an interrupting UI owns it.
   - The overlay reads "Loading RYFT".

## Consequences

**Good:**
- Cold-start behaviour and timings, and every startup hook, are the same with and without the sequence. Only the time
  until the user can touch the root moves: by 5.2 s, by 1.25 s reduced, or to the moment of a tap.
- Today's first build happens while the sequence plays, not on the hand-off frame.
- One process-scoped model makes a double play structurally impossible.
- Every play rule is a row in a pure table, tested without UIKit, and every moment of the animation can be sampled.
- UI tests and screenshot runs need no new flag, and a forgotten flag cannot make them flaky.

**Costs:**
- Root presentations must be listed in `presentsSomething`. That is a review check: a missed one only lets a sheet
  slide over a playing launch.
- Today's gauge is built twice at a played launch: static while covered, then rebuilt to play its entrance.
- A plain Xcode run plays the sequence, because the shared scheme passes no arguments.
- System UI (Control Center, an alert) ends the sequence early, and it does not replay.

**What could go wrong:**
- **Main-thread contention in the arcs' first second.** Today's first build and the `afterFirstFrame` work run while
  the arcs draw. performance-profiler measures hitches per segment (`launch-design.md` §9.3). If they appear, the jobs
  move off main or the clock starts one frame after `first-screen`; the sequence is not shortened.
- **A future background launch path that `applicationState` misses.** It is caught by the 5 s window.
- **A real launch that carries arguments.** None is known. If one appears, the sequence would silently skip, which is
  the safe direction.
- **An evicted process reopened from the app switcher replays the sequence** (`launch-design.md` O1, pending the lead).

**Rejected alternatives:**
- **A root state** (`RootView` shows the launch, then its content). It delays every lifecycle hook and the first build
  of Today by up to 5.2 s, and puts Today's first build on the hand-off frame.
- **A separate `UIWindow`.** It would cover our sheets, but it brings UIKit window management and VoiceOver focus across
  windows. System alerts still go above it, so the yield rule is needed anyway.
- **A stored `StateMachine` (`TransitionTable` / GameplayKit).** The phases change with time as well as events, so a
  stored machine would need timers to call `enter(_:)` and would duplicate `phase(at:)`.
- **Core Animation layers.** They cost no main thread per frame, but need a second geometry for §5's moving dots and
  cannot be sampled in a unit test.
- **A per-test `-skipLaunchSequence` flag.** With no shared UI-test base, a forgotten flag swallows the first tap.
