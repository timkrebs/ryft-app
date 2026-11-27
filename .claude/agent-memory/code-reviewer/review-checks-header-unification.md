---
name: review-checks-header-unification
description: RYFT review checks for header/scaffold moves and component deletions (Nocturne gate parts 1 and 2, 2026-11-21) - ids and dismiss paths, pinned vs scrolled sheet headers, pinned-header edges vs scrollTo (probed), shared-mock resets, comment-stripping scans, vacuous keyboard asserts
metadata:
  type: feedback
---

Found in the Nocturne gate part 1 review (2026-11-21, `feat/nocturne-gate`); no blockers:
- **Header moves (SubpageScaffold .close/.back/.backAndClose/.none).** Diff every id (`subpage.close/back/header`,
  `<prefix>.back/.header`), the `.perform` handler vs the header's own `dismiss`, presentationBackground and the drag
  indicator on the outer view, `.keepsBackSwipe()` with hidesBackButton (import's result step), header traits and the
  VO sort order (SheetHeader: title, close, trailing). UI tests that fell back to `app.buttons["Done"]` must now find ids.
- **Pinned vs scrolled.** A `SheetHeader` placed inside a ScrollView (import steps 1 and 6) scrolls away; D4 says
  sheet roots pin it (SheetFrame / scaffold `.close` pin it). Check where each new header sits, not just which one.
- **Shared mocks across parallel suites.** Unit.xctestplan is `parallelizable: true`. A test that calls
  `MockTrainSource.shared.reset()` to prove its own platform is isolated is itself a flake source for every suite on
  the shared source (`MockPlatformAPI()` default, `TrainLibrary(remote: { .shared })`). Grep `.shared.reset()` in tests.
- **Source scans.** When a PR adds several scan tests, check they all strip comments the same way; one did
  (`code(_:)`), two did not, so the next doc comment naming a retired symbol fails them.
- **Hosted keyboard asserts.** "Send clear of the keyboard" in a hosted window is vacuous: no software keyboard,
  frame `.zero`. The real proof is the XCUITest; check it is in a plan CI runs (it was not in UISmoke).
- **Deletions.** Grep README's Design/ list, `ReduceMotionScanTests` guarded entries and the `seen >=` floor, lint
  self-test strings, the DEBUG catalog. Fractional origins under AX titles give 43.99999 for 44 pt boxes: slack ok.

**Why:** each was invisible in its own hunk. **How to apply:** any PR moving headers/scaffolds or deleting shared
components. See [[review-checks-presented-styles]], [[review-checks-action-patches]], [[review-checks-fix-round-reverify]].

Pinned-header edges (part 2, `.underPinnedHeader`: an opaque strip + rule while `contentOffset.y + insets.top > 0.5`),
both probed with macOS swiftc + NSHostingView, no need to re-probe:
- `proxy.scrollTo(firstItem, anchor: .top)` lands at offset = the content's own top padding (10), not 0, so the edge turns on
  and covers the very item scrolled to (Add activity's save error). Grep `scrollTo(` in every view that gets the edge.
- `onScrollGeometryChange` on an outer vertical ScrollView does not fire for a nested horizontal ScrollView (journal strip);
  it fires once at first with old == new.
- Grep every `SheetHeader(` for ones still inside a ScrollView or over a List without the edge (exercise history sheet,
  Start workout, Reorder were missed).
