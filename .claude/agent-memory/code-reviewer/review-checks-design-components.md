---
name: review-checks-design-components
description: RYFT review checks for new Design/ components (Nocturne PR 2, 2026-11-16) - text colours hard-coded in glow tiles, doc drift from deviations, warning check without building, fixedSize labels in HStacks, recomputing doc examples, FP tie rules, probed layout facts
metadata:
  type: feedback
---

Found in the Nocturne PR 2 review and its fix-round re-review (2026-11-16, DotNumeral/RulerScale/GlowTile/DotRow/TickRow/buttons):
- **Text colour baked into a component that a board puts in a glow tile.** `textTertiary` (48 %) is under 4.5:1 almost
  everywhere in a glow tile (3.7-3.9 strain, 3.1-3.4 recovery at the lower edge). For every text style a component fixes,
  list the boards that put it in a tile and compute it (`python3 -I` composite: bg@overlay(t) over metric, then ink@o).
  Check which tile colour each quoted ratio is for: the fix round quoted recovery numbers against a strain-only finding.
- **Accepted deviations and lead decisions are not in design.md.** Ask for a deviation-table row each; then re-read the
  doc's test list (§Tests) too: test texts kept old parameter names after the API changed.
- **"Let the ideal width decide" via `.fixedSize()` + `.frame(minWidth:)` in an HStack row inside `ViewThatFits`:** the
  ideal check passes, but HStack then offers the label only (remaining)/2, the frame shrinks to max(min, share) and the
  fixed text draws over its neighbour (TickRow: 75-120 pt labels over the ticks at 361 pt). `.layoutPriority(1)` fixes the
  overlap. Probe recipe: macOS swiftc + ImageRenderer in the scratchpad, red bar on the label's top edge, green on the
  ticks' bottom edge, scan pixels (no occlusion).
- **Recompute every worked example in a doc** (`(61, 0...100, 50.5...51)` was documented `[31]`, the code gives `[30]`),
  and **don't trust "a tie goes to the higher" with `.rounded()` on computed doubles** (25.499999999999996 on 43 ticks).
- **Zero warnings without building:** `build/DerivedData/.../Objects-normal/arm64/<File>.dia` at 268 bytes = no
  diagnostics for that file; compare with the source files' mtimes (`ls -T`), not the commit times (batched commits).
- **Concurrency in this target:** Swift 5.10 mode, minimal checking. View/Shape conformers are MainActor-inferred; plain
  enums and nested structs are nonisolated.
- **Strings:** `scripts/sync-strings.py` skips `#if DEBUG` code and `#Preview` blocks (stringsdata reports preview strings
  at the `#Preview` line), so catalog/preview `Text("...")` add no keys.
- **Probed, no need to re-probe:** `.frame(maxWidth: .infinity, minHeight: 124)` proposes 124 to its child under a nil
  height proposal. "Presets, never literals" with an internal memberwise init still allows literals: ask for `private init`.
- **Regression-test guards:** a "the case only means something while…" bound must clear the old behaviour's threshold
  plus the assertion's tolerance (TickRow: old label share exactly 80, test tolerance 1, guard `> 80` lets 80-81 pass
  without the fix). **FP rounding fixes:** check them against an exact integer/rational sweep (swiftc), not one case.
  Colour-rect layout probes: use `Color(red:green:blue:)`; macOS `Color.green`/`.blue` fail pure-channel thresholds.
- API checks for screen PRs: `ClosedRange` from server numbers traps if lo > hi; zones narrower than the tick pitch.

**Why:** each was only visible by reading the boards or probing layout against the component's fixed choices. **How to
apply:** any PR adding `Design/` components ahead of the screens. See [[review-checks-tokens-dark-only]],
[[review-checks-shared-widget-gauges]].
