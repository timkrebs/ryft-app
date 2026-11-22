---
name: Gate G1 sweep and its probes
description: Nocturne gate G1 (2026-11-20): the sweep's decisions (D1 insight tint, D2 prompt, D8 radius 22) and the hosted-probe pitfalls met writing NocturneGateSweepHostedTests
type: project
---
G1 swept 16 files off Theme.accent / PrimaryButton / TealButtonStyle (branch feat/nocturne-gate-g1 from feat/nocturne-gate e04090d).

**Why:** L27 (teal is recovery only); the gate deletes the old tokens in G4, so every site moves first.

**How to apply (decisions now in code):**
- `ImportPrimaryButton` is `ImportStepButton` (a PillButton). `PushAskButtons(identifier:enable:dismiss:)` in
  Push/PushPrePromptCard.swift is the shared Allow pill + "Not now" LaterButton (ids `<id>.allow`, `<id>.notNow`); the
  import card uses `today.importCard.push`.
- The import's current step is the inverse chip (`background` ink on a `textPrimary` capsule).
- `InsightTile.tint(for:)`: readiness/recovery/hrv → recovery, sleep metrics → metricSleep, strain/strengthMin/volumeKg →
  metricStrain, else nil → `NeutralInsightTile` (surface, idea radius/padding/minHeight, 1.5 pt ring textPrimary 16 %).
- `RangeBar.statusColor(_:polarity:)` static; MetricSpec readiness/recovery/hrv are `Theme.recovery`.
- AnalyticsOptInSheet = OnboardingScreen + GroupedCard of 4 OnboardingPoints + footnote; two `.secondary` pills,
  `.pinnedBar` below AX1, inline from AX1. ConsentPoint / AnalyticsPromptFrame are gone.
- RyftTests/NocturneGateTests has the retired-token source scan with a skip list (`definitions`, `otherTickets`) and a
  companion test that fails when an entry is stale: edit it when G2/G4 land.

**Probe pitfalls (each cost a run):**
- A GlowTile never draws its pure colour (metric fill under a `background` radial overlay, corners ~60 %): `near(teal, 24)`
  counts 0. Classify by the share along the background→colour line with a small residual (`share(of:in:)` in the hosted test).
- `.coachMarks` is modal: every sibling drops out of the accessibility tree. Find reference shapes by pixels (`px.box`).
- `.pinnedBar` is a safe-area inset: `pageViewport()` is the whole window; check `scroll.adjustedContentInset.bottom`.
- `#filePath` is `/tmp/…`, FileManager's enumerator answers `/private/tmp/…`: resolve symlinks on both before dropFirst.
- Swift Regex `\b` is Unicode by default ("Theme.accent.opacity" is one word): `.wordBoundaryKind(.simple)`. A long
  literal regex trips line_length: build it from a `[String]` with `Regex(_:)` (output `AnyRegexOutput`).
- `#require(nodes.firstIndex(where: matchParam))` with a non-escaping closure param fails to compile (macro captures it):
  bind to a local first. A `@MainActor` suite's `static let` used as a default argument must be `nonisolated`.
- Radius probe: diagonal inset from the shape's bounding-box corner to its first pixel, against 22 and 18 references
  drawn in the same window (literal 22, not CardSpec.radius, so a spec change is caught).
- Renders: `drawHierarchy` at 3x draws nothing for a window over ~8192 px (3000 pt came out black; 2400 pt was fine), and a
  bare view in the render window starts under the missing safe area (clipped top): render inside a page or pad it.
- The shared Mac's 5-minute load jumps to 400–700 while anyone builds; each gated step waited 5–10 min. Chain mutate →
  build → test → restore in one background script with a `trap … restore EXIT`.
