---
name: review-checks-launch-overlays
description: RYFT review checks for root overlays that cover the app at launch (Nocturne PR 3 launch sequence, 2026-11-16) - side effects under the cover, XCUITest a11y dumps that prove nothing, Button-typed overlays, idle-wait timing, capture-free closure equality probe
metadata:
  type: feedback
---

Found in the Nocturne PR 3 launch-sequence review (2026-11-16); the state machine, signposts and geometry were right:
- **"Covered counts as unseen" applied to one consumer only.** The ADR says anything that acts once when first seen
  waits for the hand-off, but only Today's gauge did. Grep every root screen (Welcome, onboarding flow, Health intro,
  tracker setup, Today) for `.onAppear`/`.task` side effects: `InviteCodeView` sets `@FocusState` on appear, so the
  keyboard (its own window) slides over the playing overlay on a cold reopen at the invite step.
- **XCUITest dumps don't prove VoiceOver hiding.** XCUITest lists children of `.accessibilityElement(children: .ignore)`
  and of `.accessibilityHidden(true)` subtrees (the gauge caption under `today.readinessGauge`, the stage's "RYFT" and
  tagline under the overlay), and listed the whole covered root. Say "needs Accessibility Inspector / VoiceOver", not
  "hidden" or "leaks".
- **`onTapGesture` + `accessibilityAction` makes the overlay a Button for XCUITest** (type 9): an
  `app.otherElements["id"].exists == false` assertion is vacuous. Ask for `descendants(matching: .any)["id"]`.
- **XCUITest with a running `TimelineView`:** tap-to-gone measured 1.56 s for a 0.25 s fade (idle wait). "Gone within
  1 s" UI tests will flake.
- **Probed (macOS swiftc + NSHostingView):** a generic host storing a capture-free `@ViewBuilder` closure
  (`Host(model:) { Root() }`) compares equal; its body does not re-run when the parent re-renders. No need to re-probe.
- **Evidence without running:** the ui-validator leaves `log stream` output for the `launch` category and an
  XCUITest `debugDescription` dump in the session scratchpad; read them before claiming a phase order or an a11y tree.
- Doc drift again: design.md (visual spec) and launch-design.md (lifecycle) disagreed on LPM, identifier, traits,
  catalog Play and the `LaunchFrame` API; the code followed the later ADR. Ask for P3-10 rows, and check CHANGELOG.

Nocturne PR 4 matched move (2026-11-17), lands correctly (checked on the validator's frame PNGs, not by running):
- **Geometry reporting outlives the launch.** `LaunchHost` installs `launchHandOffRegistrar` unconditionally (its doc
  says "while on screen"); the header lock-up's `onGeometryChange(.launch)` sits in Today's ScrollView, so every scroll
  frame for the process lifetime calls `model.register`, which only early-returns. Gate the modifier on an env flag.
- **A decision that ignores the ending.** `movesMark` checks variant/target/progress only, so an interruption
  (presentation, system UI) at >= 0.86 also flies the mark. Ask whether interruptions belong in the move's list.
- Real-clock flake check: the model tests use `TestClock` + 100 `Task.yield()`s; deterministic, no wall time.

PR 4 fix round (VB1, 2026-11-17): a `.named` space set on `LaunchHost` is not found inside the `TabView`'s own hosting, so
Today's target fell back to window space while the overlay converted it again (62 pt low). Fixed by measuring target and
stage both in `.global` and subtracting the stage's own origin. Evidence that counts: `LaunchLandingHostedTests` (real
window, LaunchHost over TabView over TodayView, ink boxes within 0.5 pt at 390/402). Any matched move or overlay that draws
at another view's frame: both sides in one space that crosses hosting boundaries; ask for a pixel test, not a pure one.

**Why:** each was invisible in the state-machine tests and the green build. **How to apply:** any PR that puts a view
over the root at launch, or plays something "once when seen". See [[review-checks-shared-widget-gauges]],
[[review-checks-design-components]], [[review-checks-dark-launch]].
