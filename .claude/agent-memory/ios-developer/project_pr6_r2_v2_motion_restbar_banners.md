---
name: PR 6 R2 V2 — Reduce Motion scan, AX rest bar, banners
description: Source-scan test for Reduce Motion in Train/Journal; AX rest bar is a pill that opens the rest sheet; banner glyph column and text-link pixel probe; Swift Testing #require comment pitfall
type: project
---
- Reduce Motion: `RyftTests/ReduceMotionScanTests.swift` scans Features/Train, Features/Journal and Design/Card.swift
  for `withAnimation`, `.animation(`, `.contentTransition(`; allowed: `Theme.Motion.respecting(`, `reduceMotion ? nil :`,
  `nil`, a local bound to one of those, `.identity` under reduceMotion. ButtonStyles read
  `@Environment(\.accessibilityReduceMotion)` fine. `PressableButtonStyle.pressAnimation` is the shared press curve.
  **Why:** a grep-able rule beats per-view hosted tests. **How:** new animation sites in those folders must use the helper.
- RestBar: from AX1 the running bar is always the pill (ring, time, Skip); tap = `onOpen` → SessionView's
  `.sheet(item: RestSheetRequest)` with RestSheet (±15). VoiceOver actions keep ±15, Skip, "Show rest timer".
- InlineMessage: glyph in a `@ScaledMetric` 24 pt column (widest SF glyphs at 16 pt are 24 wide); retry and plain
  action underlined in ink at 35 % (§2.6). Pixel probe: longest lit run under the text box + its median level.
- Invite step: no autofocus at AX sizes (`InviteCodeView.shouldFocus(…, typeSize:)`) — onboarding has no pinned bar.
- My Day: `.scored` mark's word is "Strain" (`myday.state.strain`).
- Report a problem: the iOS 26+ floating keyboard "Done" sits outside the safe area and touches the Send pill;
  not fixed (needs a design call). AddActivitySheet has the same toolbar.
- Pitfall: `try #require(x, id)` with a String var fails to build (Comment? expected) — use `"\(id)"`.
  Strict build caught it only in the test target; build tests before mutants.
- Pixel-testing an underline: iOS skips descenders ("Try again" breaks at y and g), so don't look for one unbroken run;
  count pixels at the underline's own level (ink 35 % over surface, ±0.1) on the fullest row below the word's middle.
- My Day rows are a LazyVStack: rows below the fold are estimated, so a "scroll to bottom" in a hosted test must loop until
  `contentSize.height` holds (taller rows broke `pinnedAddClearsTheLastRow` by 9 pt).
- Unit plan at base 4857947 already fails 2 tests not in PR 6 R2 lines: SleepNeedEditorsTests ruler labels (50c0b80 made
  them NBSP, test kept plain spaces) and TrainHistoryTests week header ("1 session" when this week has one mock session).
- Preview check without Xcode: a temporary hosted test that rebuilds each #Preview body and writes PNGs (kept a copy at
  scratchpad r2-v2/ZZPreviewRenderTests.swift.keep), deleted before the final build.
