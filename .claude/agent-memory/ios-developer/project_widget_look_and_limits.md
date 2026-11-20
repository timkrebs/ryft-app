---
name: project-widget-look-and-limits
description: How RYFT's widget and Live Activities are tested and sized (Shared/WidgetLook.swift), and the WidgetKit traps the W review found (placeholder redaction, slot sizes, 160 pt)
metadata:
  type: project
---

RyftTests can't import the widget extension, so the widget's wordless decisions (ink per state, centre value,
redaction, ageing, fold/condense rules, Dynamic Type caps) live in `Shared/WidgetLook.swift` (Shared/ is a synchronized
folder in both targets: a new file there needs no project change). Views must call every helper there; the reviewer
rejects test-only models in production code (keep height models in the test file).

**Why:** W review, 2026-11-19 (PR 6 C): a readable "00" in the placeholder, a circle losing its number on the SE, caps
instead of less content.

**How to apply:**
- `.privacySensitive()` exempts its subtree from `.placeholder` redaction: the placeholder must show no number by
  itself (`WidgetConcealment`: placeholder → dash, locked → boxed "00").
- Lock screen slots: circle 76 / 72 / 68 (SE), rectangle 172×76 / 160×72 / 153×68. Live Activity on the lock screen:
  160 pt max. Measure real heights with `UIHostingController.sizeThatFits` in a scratch harness, not only font models.
- Dynamic Type: drop content first (fold the rectangle's bedtime into the status line, drop the activity's session
  title, one Next line), then cap where even that no longer fits. Rest card since 6c9 S3 (`WorkoutActivityLook`):
  `condenses` (no title) only from AX1; `nextLineLimit` 2 at `.large`, 1 above; Next truncates at the **tail**; when the
  title isn't drawn `spokenTitle` keeps it in the label, unless `WidgetConcealment.hidesValues`. xLarge with the title
  and two Next lines is > 160 pt, so the steps are: one line from xLarge, no title from AX1.
- Rendering widget views in RyftTests needs a temporary copy (scratchpad `w/harness/gen.py`); copied type names can
  clash with app types (the app has `RestBar`), so widget types get distinct names.
- "As of" ageing: one Gregorian calendar in the device zone for day and age (`WidgetAge.calendar`), nil for days <= 0.

- `minimumScaleFactor` is a linear guess: SwiftUI picks scale ≈ proposed/ideal width, and SF tracks looser at smaller
  sizes, so a one-line Text can still truncate the last glyph above its floor (SE rectangle at xxLarge, "Bed by 10:41 P…"
  at 0.75). `.allowsTightening(true)` beside it closes the gap; check the SE 153×68 shot, not only 160×72.
