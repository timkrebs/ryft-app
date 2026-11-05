---
name: visual-check-whole-matrix
description: A visual tweak checked in one shot can regress another size; check the whole matrix by pixel measure, and look at the shots yourself
metadata:
  type: feedback
---

A change to a shared visual value gets checked at every size and scheme it reaches, not in the one shot that prompted it.
Measure pixel rows as well as looking: eyes passed a dimmed label as "sharp".

**Why:** on 2026-11-05 in #99 the keypad fade went from 28 to 22 pt to clear the labels at 320 AX3. That shot looked clean, the
report said so, and the same change brought a line fragment back at 320 AX1. Reading other shots before pushing caught it.
Row profiles then showed the AX3 labels had been dimmed too, so 18 pt at 75% was the real fix. `make focused-shots` has no
`keypad` above default and no light `rest-keypad` above default, so the matrix alone wouldn't have shown it.

**How to apply:** before pushing a visual fix, read shots beyond the agent's named ones. Crop and zoom the edge in question,
and compare with an older render (the other language's set can be the "before"). Check whether a mark comes from the code
that changed: the same fragment at 390 came from `topFade`, which is untouched. Don't say what a cause is before that check.
