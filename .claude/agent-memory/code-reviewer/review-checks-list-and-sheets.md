---
name: review-checks-list-and-sheets
description: RYFT review checks for Nocturne List-layout and session-sheet restyles (T6B.2, 2026-11-19) - fixed compact pills that only stack at AX3, trailing pills eating a label column, vacuous save tests, Cancel during an awaited commit, children:.ignore buttons that can't be activated in hosted tests
metadata:
  type: feedback
---

Found in the T6B.2 review (List cards, rest bar, Add/Replace/Custom/Edit targets/Notes/Reorder sheets; read-only, no build):
- **Rows of `PillButton(.compact)`** are `fixedSize` and never wrap. A layout that stacks them only at AX3 overflows at AX1/AX2
  and at 320 from XL. Measure with CoreText *with `tnum`* (`.ryft()` adds `monospacedDigit`, "15" gets ~6 pt wider) and count
  a `Spacer` as a child (one more `spacing` gap). Script: scratchpad `review-6b2/measure2.swift`. Check 390, 375 and 320.
- **A trailing pill beside text at AX sizes** (a compact "Dismiss" next to "Rest over / Next: …") leaves the text ~125 pt at AX3:
  the line truncates where the old full-width banner read whole. Compare the AX3 before/after shots of every state, not only
  the running one.
- **Vacuous save tests:** a test that seeds the model with the same value the sheet then saves (`notes = X`, Save, expect X)
  passes with the write deleted. Change the model after the sheet captured its state, then expect the sheet's value back.
- **Cancel during an awaited commit:** a busy `PillButton { await save() }` leaves the `SheetHeader` close and the drag active;
  the continuation still calls `onSave` → the parent adds/replaces after the user cancelled (or after Finish). Check every
  `await` in a sheet's commit for a "still presented" guard. The custom exercise form had this since before Nocturne.
- **`background` vs `surface` is 0.035 per channel**; the hosted helpers' default tolerance is 0.06 (recurred from T6B.1):
  "this pixel is the screen, not the card" proves nothing at that tolerance.
- **`.accessibilityElement(children: .ignore)` on a Button**: `accessibilityActivate()` returns false, so hosted tests skip
  activating it. On a device VoiceOver falls back to a tap at the centre (works); flag it as a nit plus a missing test, not a
  VoiceOver regression, unless the centre lands on another control.
- `.serialized` is the convention for every hosted suite (and `HostedWindow.run` already serializes windows via `busy`), so it
  is not a smell by itself; a "crash it hid" needs the faulting frame before calling it a production bug.

**Why:** the suite and the default-size shots were green; only width maths, AX3 shots and mutation thinking showed these.
**How to apply:** any restyle that swaps buttons for compact pills, moves commits into custom headers, or adds hosted tests
for sheets. See [[review-checks-screen-restyles]], [[review-checks-form-restyles]], [[review-checks-large-text]].
