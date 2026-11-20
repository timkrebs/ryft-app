---
name: project-parts-line-and-ax-headers
description: R2 V1 (PR 6) fixes for AX sizes — PartsLine for "a · b · c" lines, PushedHeader stacking, sheet detents, and test techniques that proved them
metadata:
  type: project
---

R2 V1 (2026-11-20, branch feat/nocturne-pr6-fix-v1):
- `Design/PartsLine.swift`: a line of parts ("1 session · 7,500 kg · load 85"). Below AX1 joined (`MyDayText.join`, or the
  caller's `joined:`); from AX1 one part per line, no "·". VoiceOver: one element, the joined line (or `spoken:`).
  `PartsLine.text(_:joined:stacked:)` is the pure rule. Sites: History week + subtitle, session/plan subtitles
  (`PushedHeader(subtitleParts:)`), My Day card + screen summary (`MyDayContent.summaryParts`), import counts, Profile's
  source rows (`GroupedRow.detailParts(_:)`, drawing only; speech keeps `detail`; passed via an environment entry so
  factory-built labels (push to a route, menu) get it too).
- `PushedHeader` stacks from AX1 like `SubpageHeader`: Back + trailing on a 40 pt row, then title/subtitle leading.
- `View.sheetDetents()` (SheetFrame.swift) applies `SheetFrameSpec.detents` for a sheet view that doesn't read typeSize.
- Plan builder name: `TextField(axis: .vertical)` + `.lineLimit(1...4)`; Return becomes Done via
  `PlanBuilderRules.nameOnOneLine` in `onChange`. Plans have no name cap (only import's 80).

**Why:** the validator saw dangling "·" and squeezed headers at AX3; these are the shared fixes.

**How to apply:**
- Sheet detents test: present via `SheetHost`, read
  `w.host.presentedViewController?.sheetPresentationController?.detents.map(\.identifier)`; SwiftUI's `.medium`/`.large`
  are UIKit's `com.apple.UIKit.medium/large`.
- A vertical `TextField` is a UIKit text view, not an `AccessibilityNode`: find it by walking `w.window` subviews for
  `UITextField`/`UITextView` whose text matches; a one-line one is `UIKitTextField`.
- "No dangling ·" by pixels: ink box of the summary region below the title, no wider than the widest part (+2), or the
  first detail line's ink no wider than its first word. Height alone can't tell (2 parts wrap to 2 lines either way).
- Grouped mutation runs: one build with several mutants, each in a different code path and each breaking only its own
  test (`r2-v1/mut/mutate.py` groups A/B); a second group for second checks of the same test. Swift Testing ids in
  `-only-testing` need `()` and quoting in sh; hosted tests often live in a separate `…HostedTests` suite in the file.
- Profile source texts are now parts joined with " · " (`sleepBaseSourceParts`, `maxHRSourceParts`): new keys
  "learned %@", "add your birth year for an estimate"; old sentence keys go stale on the next catalog sync.
