---
name: review-checks-activity-sheets
description: RYFT review checks for restyled entry sheets and an entity detail (Nocturne T6B.7 Add activity, Add sleep, activity detail, 2026-11-19) - "waiting for X" sentences on never-uploaded rows, units hidden from VoiceOver, fixed circles in flexible grid columns at 320, two fixedSize trailers beside a flexible label, chip rows squeezing the label mid-word, XCUITest DatePicker value vs label per OS
metadata:
  type: feedback
---

Found in the T6B.7 review (read-only, 2026-11-19); the suite, the shots and the UI tests were green:
- **"Waiting for heart rate" on a row RYFT has never seen.** A strain line keyed only on `strain == nil && source != none`
  says "waiting for heart rate" for local-only rows (offline, gated, refused, account deleting): they wait for the upload
  or for the user. Branch on "is it at RYFT" (`serverCopy == nil`) first. A new test that pins the sentence is a smell.
- **A unit moved into a field's trailing slot and `.accessibilityHidden(true)`**: VoiceOver reads "Distance, 5.2" with no
  km/mi. Diff the base: was the unit its own element? Put it in the field's label instead.
- **Fixed-diameter circles in `.flexible()` grid columns** (EffortScale: 54 cap, 5 columns): at 320 the card leaves
  248 / 5 = 49.6 per column, so from XL the rings overlap. Compute column width at 320/375/390 for each capped size.
- **Two `fixedSize` trailers beside a flexible label** ("(next day)" + "1h 00m" 20 Light scaled like title3): the label
  breaks mid-word from AX2 at 390, XXXL at 320. Script: scratchpad `review-6b7/measure.swift` (callout x size/16,
  caption x size/12, title3 x size/20; Apple tables callout L16 XL18 XXL20 XXXL22 AX1 26 AX2 32 AX3 38).
- **`ValueChipRow` (chips at layoutPriority 1)**: the bad band is where the chips *just* fit in a row: the label is left
  with less than its longest word (390 XXL/XXXL, 375 XL/XXL); at 320 L the chips stack and it's fine. Script
  `review-6b7/chips.swift`; calibrated against the after-shot ("Went to bed" wrapped at 390 L as predicted).
- **XCUITest compact `DatePicker`**: on the 27.2 sim the button label is "Date Picker"/"Time Picker" and the shown
  text is `.value`; the base test read `.label`. CI runs only the newest runtime (`scripts/ci-simulator.sh`), so 18.6
  (the minimum) is never exercised: ask for a value-or-label helper.
- Catalog single-writer tickets (T6B.10): list the new keys and the keys whose last caller left ("Duration %@").

**Why:** none of these showed in green tests or default/AX3 shots at 390. **How to apply:** any sheet/form restyle with
chips, units, effort-like grids, or a detail page with sync/strain states. See [[review-checks-form-restyles]],
[[review-checks-large-text]], [[review-checks-list-and-sheets]], [[review-checks-detail-pages]].
