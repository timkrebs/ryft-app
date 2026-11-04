# D1: the focused session screen (design note)

> Lead resolutions L5 and L15–L21 in `plan.md` override this note where they differ (flag instead of a compiled default,
> no swipe to delete in Focused, ✓ on an empty row, German copy, T4's cut).

Owner: ui-designer. Inputs: `brief.md` (redacted), `plan.md` (L1 to L14 override the brief), `SessionView`, `ExerciseCard`
(`SetRow`), `RestBar`, `EditTargetsSheet`, `AllSetsDoneCard`, `SessionAdvance`, `Theme`, `Typography`,
`docs/work/2026-10-29-beta-feedback-2/`. Every value in this note is synthetic (day "Upper", loads such as 75 x 10,
80 x 6, 102.5). No screenshot of another app is in the repo; the shots per state come from the PR's previews.

What the eye sees first on this screen: the **active set's check** and its two raised fields, then the strip (where am
I), then the rest pill. Everything else is quieter. Numbers first: the value, then its unit in the column header, then
the sentence.

---

## 1. The brief's analysis in RYFT terms, and what was rejected

| Reference effect | RYFT version | Why |
| --- | --- | --- |
| One exercise per screen, a strip of tiles | Same. Tiles carry a kind glyph and the exercise's position, never a name (section 4a). | Orientation without scrolling; the page title already names the current one. |
| Exactly one active set, raised fields, big check | Same. The active row is the only one with raised fields and a filled check. | One thing to do. Logging a set that went as planned is one tap. |
| Upcoming sets prefilled | Same, as real-looking `textSecondary` text, not placeholders. | Reads as "what you will do". Contrast stays at 4.5:1 or better (section 2.8). |
| Fourth column with an estimated RM | Same, but **PR 4** (section 7). PR 1 ships the fourth column as RPE, today's field. | RPE has an entry path today; a read-only column would remove it. |
| Warm-ups folded into one pill | Same, L6 decides the active-set rule. | |
| Last time as a table | Same, heading with the date only (L7). In PR 1. | One table in the codebase, not a sentence first and a table later. |
| Rest as a pill | Same (`RestPill`, replaces `RestBar` in Focused, L2). Idle pill is hidden while the number pad is open. | The pad has Done; the pill row would cost 64 pt on a short screen. |
| Everything editable is marked | Chips (`Barbell`, target, `Rest 1:15`), each with a trailing glyph, each opening an existing sheet (L3). | |

Rejected, with the reason:

- **Photos or illustrations on tiles.** RYFT has none and may not borrow any. A tile that pretends to be a photo with a
  symbol in it is worse than an honest glyph tile.
- **Exercise names on tiles** (one, two or three lines). Rendered at 56 pt in Satoshi Medium 10 pt: English fits
  ("Bench press"), German breaks inside words ("Bankdrücke / n", "Schulterdrü / cken Lang..."). Truncating to the first
  word collides ("Bankdrücken" for flat and incline). Section 4a.
- **A two-letter monogram.** Collides within one day ("Latzug eng" becomes `LE`, "Lat pulldown" `LP`) and means
  nothing in German.
- **`TabView(.page)` page dots.** The strip is the page indicator; dots would be a second one.
- **A fourth-column header that is a bare text field.** The header is a menu-like button (PR 4), 44 pt high.
- **Pinning the idle pill while the pad is open.** Costs 64 pt on 693 pt Display Zoom screens for a rarely used
  action.
- **A second "advance" toggle** (plan L4): the existing `train.jumpToNext` gets the new label.
- **Landscape strip and side-by-side pages** stay out of PR 1; PR 5 decides after a device run.

---

## 2. Geometry

Reference sizes: **390 x 844 pt** (iPhone 18 Pro class, portrait) and **320 x 693 pt** (Display Zoom, the width stress
case; iOS 17 has no narrower device). Safe area top 59, bottom 34. Page padding: **16 at 390, 12 at 320** (content
width 358 / 296). Gaps in a row: 6 at 390, 4 at 320. All fonts are Satoshi from `Typography`; all colours are tokens
from `Theme`; numerals use `.monospacedDigit()`. No new colour, no new font.

Vertical budget at 390 x 844, no pad, no rest: 59 top + 64 header + 76 strip + **551 page** + 64 pill row + 34 home.
Above the fold of a page: title 44, chips 44, warm-up pill 36 (when present), table header 24, four rows of 60 =
240, Add set 44: 432 pt. The last-time card scrolls in below. At 320 x 693: page 400 pt, so title, chips, header and
four rows (352 pt) still fit.

### 2.1 Header (unchanged structure)

Chevron 48 circle, title over elapsed clock (callout over number 30), `...` 48 circle, Finish capsule 48 high.
- 390: padding 16, spacing 8. Unchanged.
- **320: padding 12, spacing 6, the three buttons 44, the clock 26 pt (`minimumScaleFactor` 0.8).** The middle
  column is then 116 pt; "1:02:15" at 26 pt needs about 100. Today's header (middle 92 pt) cannot hold an hour
  clock at 30 pt; ui-validator checks it.
- Offline banner: one line under the header, `caption`, `textSecondary`, `wifi.slash`, existing text. Height 28.

### 2.2 Exercise strip

```
 16 |[ 1 ][ 2 ][ 3 ][ 4 ][ 5 ][ + ]  ...scrolls...           (tile 56 x 56, gap 8)
    |  v    o                                                  v done  o current
    |      ====== (superset bar: 3 pt, under tiles 3 and 4)
```

- Strip height **76**: 8 top, 56 tile, 3 bar slot + 9 bottom. It never grows with Dynamic Type except at AX3
  (section 5). Leading inset = page padding; tiles scroll edge to edge and clip at the screen edge. The current tile
  scrolls to the centre (`.center` anchor, `Theme.Motion.quick`; instant under Reduce Motion). With 12+ exercises the
  strip scrolls; with 1 exercise it is still shown (PR 5 list).
- **Tile**: 56 x 56, corner 14 continuous (matches `SetRow`), fill `surfaceRaised`. Content, top to bottom, centred:
  kind glyph in a fixed 22 x 22 box (system symbol, 20 pt medium, so the numbers line up), then the position number
  ("1" to "99", `ryftNumber` 11, tabular). Gap 3.

| State | Fill | Content colour | Ring | Badge | Reads as |
| --- | --- | --- | --- | --- | --- |
| upcoming | `surfaceRaised` | `textSecondary` | none | none | not started |
| current | `surfaceRaised` | `textPrimary` | 2 pt `accent` inside the edge | none | in progress |
| done | `surfaceRaised` | `textSecondary` | none | 16 pt circle, `accent` fill, `onAccent` check 9 pt bold, bottom-right, offset (+4, +4) | all working sets checked |
| superset | any of the above | same | same | 3 pt `accent` capsule under the group, from first leading to last trailing edge, 3 pt below the tiles | partners |
| add (`+`) | clear | `textSecondary` glyph 20 pt | 1 pt `separator` dashed outline (an outline is "not yet", as for pending elsewhere) | none | opens `AddExerciseSheet`, then jumps to the new page |

  **Dimming is by token, not by opacity.** The brief's 60 % opacity was rendered: in light mode `surfaceRaised`
  (#DAD9D4) on `background` (#E8E7E3) is already 1.1:1, and at 60 % the tile edge, and the done badge, disappear. So
  done and upcoming tiles keep full-opacity fill and badge and dim only glyph and number (`textSecondary`, 6:1 or
  better on the tile in both schemes). The current tile is distinguished by ring and brighter content, so not by colour
  alone: it is the only tile with a ring and the only one whose number is `textPrimary`.
- A done tile whose set was unchecked loses its badge at once (state is derived, never stored).
- The **ring and the superset bar are both teal**: ring is a rounded rectangle around the tile, the bar is a capsule
  below; one hue, two shapes.
- Hit areas: the tile is 56 x 56, so it clears 44. Tap jumps (changes no set). Long press opens the existing
  `ReorderSheet`. Tiles are separate hit regions in the strip; the strip as a whole is one VoiceOver element
  (section 5).

### 2.3 Page title row, chip row, notes

```
Incline dumbbell press  v                       [ ... ]     title row: 44 high
(link) Superset with Cable row                              only in a superset, caption, 20 high
[ (arrows) Dumbbell ] [ 3 x 8-10 @ 30 kg (pencil) ] [ (timer) Rest 1:15 (pencil) ]    chip row
(note) Slow on the way down                                 notes, 1 line, only if not empty
```

- **Title row**: exercise name, `headline` 18, `textPrimary`, a small `chevron.right` 11 pt `textTertiary` after it to
  say it opens the history sheet (hit area: the whole name, min 44 high). Trailing `...` menu 44 x 44, same items and
  order as today's `menuItems` (Replace, Edit targets, Notes, Plate calculator for barbell, History, Rest, Superset,
  then Remove). Name wraps to two lines at 320 and at XL or larger; never truncates (a page has the room).
- **Position** "2/6" sits at the end of the strip's accessible value, not as visible text (the strip shows it).
- **Superset line**: `link` glyph + "Superset" + the partner's name, caption, `textSecondary`. A tap does nothing; the
  controls stay in the `...` menu.
- **Chips**: 32 pt high visual, 44 pt hit area (the row is 44 with 6 pt padding), capsule, fill `surface`, 1 pt
  `separator` stroke, text `callout` 14 `textPrimary`, glyph 12 pt `textTertiary`. Row scrolls horizontally with a 16 pt
  fade on the trailing edge when it overflows (320: it does, by about 40 pt). Never accent: three accent chips
  would outweigh the check.
  1. **Equipment**: `arrow.triangle.2.circlepath` + `ExerciseKind.title` ("Dumbbell"). Opens the Replace sheet
     (`controller.beginReplace()`, as the menu does). Disabled look (text `textTertiary`) when
     `!canReplace(exercise)`; VoiceOver says "dimmed".
  2. **Target**: `exercise.targetText` ("3 x 8-10 @ 30 kg") + `pencil`. Opens `EditTargetsSheet`. No target:
     "Set target" + `pencil`. This replaces the accent target line of today's card; the text is no longer accent.
  3. **Rest**: `timer` + "Rest 1:15" + `pencil`. Opens the **rest sheet** (section 2.7), medium detent.
- **Notes line**: `note.text` + the note, caption, `textSecondary`, min 44 high, one line (full text in the sheet);
  tap opens `ExerciseNotesSheet`. Hidden when empty (the `...` menu keeps "Notes").

### 2.4 Warm-up pill and expanded group

- **Pill**: capsule 36 high (hit area 44), fill `surface`, 1 pt `separator` stroke, `flame` 12 pt `warning`,
  text `callout` "2 warm-up sets" `textSecondary`, trailing `chevron.down` 11 pt `textTertiary` (rotates 180 degrees
  when open, `Theme.Motion.quick`, none under Reduce Motion). Left-aligned at page padding, 8 pt above the table header.
  Shown only when the exercise has at least one warm-up set.
- **Collapsed** (default, L6): nothing else shows; the table lists working sets only; numbering of working sets starts at 1.
- **Expanded**: the warm-up rows (same row geometry as section 2.5, number slot shows `W` in `warning`) sit above
  the working table, inside the same table header; below them an **"Add warm-up set"** text button (`plus`,
  `callout`, `textSecondary`, because the active check keeps the screen's accent), min 44 high. The group folds by itself when its last warm-up is checked (L6); the pill
  then reads "2 warm-up sets, done" in VoiceOver only (visible text unchanged).
- Warm-up row states follow section 3 with the same rules; an open warm-up is active only while the group is open (L6).
- Creating the **first** warm-up: tap a set's number (today's toggle), or the new `...` item "Add warm-up set" (shown
  when the exercise has none; needs `controller.addSet` + `toggleWarmup`, no new model). Without it the feature is
  undiscoverable once the pill is hidden for exercises with none.

### 2.5 Set table (weight and bodyweight exercises)

Header row 24 high, then rows **56 high, 4 pt apart** (60 pitch), then Add set 44.

| Column | 390 (pad 16, gap 6) | 320 (pad 12, gap 4) | Content |
| --- | --- | --- | --- |
| `#` | 36 | 28 | number, `ryftNumber` 17; hit area 44 wide x 56 high, extended left into the page padding (28 + 4 + 12 = 44 at 320) |
| `KG` | flex = 93 | flex = 74 | field |
| `REPS` | flex = 93 | flex = 74 | field |
| 4th (`RPE` in PR 1, `E1RM`/`10RM`/`RPE` in PR 4) | 56 | 48 | field (RPE) or read-only text (RM) |
| check | 56 | 56 | 56 x 56 button |

Check: 390: 36 + 93 + 93 + 56 + 56 = 334, plus 4 gaps x 6 = 358. 320: 28 + 74 + 74 + 48 + 56 = 280, plus 4 gaps x 4 = 296.
Both exact; the two fields share the remainder equally (`maxWidth: .infinity`).

- **Numerals** use `ryftNumber`: 22 pt at 390, **20 pt at 320**, medium. "102.5" is five characters; at 20 pt Satoshi
  digits are about 11.5 pt, so 5 x 11.5 = 58, plus 8 pt inner padding = 66, inside the 74 pt field. "12" reps and
  "1000" fit trivially. Fields use `lineLimit(1)` and `minimumScaleFactor(0.75)` as a safety, never as the plan.
  Header labels: `label` style capped at `.xxxLarge` (the row is read by VoiceOver as one element, headers are
  `accessibilityHidden`, as today), tracking 2 at 390, **tracking 1 at 320**, so "E1RM" (about 44 pt) fits the 48 pt column.
- **Field**: 48 high, corner 12, `Theme.surfaceRaised`. Focused (number pad open on it): 2 pt `accent` ring (today).
- **4th column in RPE mode**: a field like the others, 48 high, but `surfaceRaised` at 0.55 on the active row too (it
  is optional). Value "8.5" in 17 pt. Empty: nothing (no placeholder dash), so a table without RPE is quiet.
- **Check button**: 56 x 56, corner 14. Active: `accent` fill, `onAccent` check 20 pt bold. Done: no fill, a `checkmark`
  20 pt bold in `textSecondary` (the brief's grey check), still a 56 pt button that unchecks. Upcoming: no fill,
  `surfaceRaised` rounded outline 1 pt, `checkmark` in `textTertiary` at its normal opacity (the same glyph, so a
  tap target is visible; this is today's idle look).
- **Active row**: row tint `accent` at 0.10, 2 pt `accent` bar on the leading edge (today's `CurrentSetHighlight`,
  reused so a non-colour cue exists), `#` in a raised pill (fill `surfaceRaised`, 32 x 32 at 390, 28 x 28 at 320)
  with a 5 pt `accent` dot top-right, kg and reps fields raised (`surfaceRaised` at 1.0) with `textPrimary`.
- **Swipe to delete** stays on the row (unchecked rows only, 88 pt reveal, `Theme.alert`), see section 8 for the
  conflict with paging.
- **Add set**: `plus` + "Add set", `callout`, `accent`, full width, 48 high. (Today's colour; it sits under the table,
  far from the check, so the screen still has one dominant accent control.)
- **Footer when all sets of the whole session are done**: `AllSetsDoneCard` (existing) on every page while
  `isAllDone`, because the user may be on any page when the last set is checked and L1 says "stay". It sits below Add set, above the last-time card. Content unchanged
  ("All sets done", "5 exercises . 17 sets", **Finish workout** `TealButtonStyle(prominent: true)`). Rest pill row
  disappears while `isAllDone` (as `RestBar` hides today).

### 2.6 Last-time card

`Card(padding: 14)` under Add set (and under the done card), title row then a table with the same column widths as 2.5,
so a row in the card sits under the same column of the table above.

```
LAST TIME . TUE 3 NOV                                     label style, textTertiary
  #      KG     REPS    RPE                               header, 24
  1      75      10                                       rows 36 high, ryftNumber 17, textSecondary
  2      80       6
```

- Heading `label` style: "Last time", then " . Tue 3 Nov" when `completed_at` is known (L7). No session title (not on the
  wire). Date format `.dateTime.weekday(.abbreviated).day().month(.abbreviated)`, in the user's locale.
- Rows list the working sets of `exercise.lastTime` (`!isWarmup`) up to **6**; more: a last line "+2 more"
  (`caption`, `textTertiary`, existing key "+%lld more"). The 4th column shows last time's RPE when recorded,
  otherwise empty (PR 4: the same RM mode as the table).
- Warm-up rows of last time are not listed (as today's sentence).
- The whole card is one button (min 44 high per row region) that opens the history sheet.
- Hidden when `lastTime` is empty; nothing in its place (no "no history" text: the empty ghost state of the table
  already shows dashes).
- Time and distance: section 3.

### 2.7 Rest pill, rest sheet

**Pill row**: a `safeAreaInset(edge: .bottom)` on the page area, 64 high (8 above, 48 pill, 8 below), pill centred.
Stack order from the bottom: home indicator / number pad, pill row, undo toast (`SessionToastOverlay`), page.
So the pill sits **above the home indicator** (the inset sits above the bottom safe area) and **above the pad** while the pad
is up. The page gets 64 pt of extra bottom content margin so Add set and the last row can scroll clear of it.

| State | Look | Visible |
| --- | --- | --- |
| **idle** | capsule 48 high, min width 112, fill `surface`, 1 pt `separator` stroke; `timer` 18 pt `textSecondary`, then the exercise's rest "1:15" in `ryftNumber` 20 `textPrimary` | no pad open, not `isAllDone` |
| **running** | capsule 48 high, min width 144, fill `accent`; 24 pt ring (3 pt stroke, track `onAccent` at 0.25, progress `onAccent`) then remaining "1:54" `ryftNumber` 24 `onAccent`, `contentTransition(.numericText(countsDown:))` (identity under Reduce Motion) | whenever a rest runs, also with the pad open |
| **finished** | like idle for 1 s, with a one-time flash: fill goes `accent` at 0.25 for 250 ms (`Theme.Motion.quick`) and back; "Rest over" replaces the time for that second; then idle. Reduce Motion: no flash, the text only changes. | after the rest ends |

- The pill is a single button, 48 high. **Tap opens the rest sheet** (medium detent, large at AX).
- "Pending is an outline" applies: idle is an outline (stroke, no fill), running is the only filled pill.
- 320: widths above hold (idle 112, running 144 of 296).

**Rest sheet** (`.presentationDetents([.medium])`, large at AX), `NavigationStack`, title "Rest", Done button:

```
            1:15                       value ryftNumber 56, tabular
      [ - 15 s ]   [ + 15 s ]          two 56 pt keys (like TargetStepper)
     [        Start rest 1:15      ]   idle: prominent teal button; running: [ Skip ] prominent
   Next: Incline dumbbell press . set 2 of 4 . 8 x 30 kg           (running and idle), caption
   Set as rest for this exercise                                    text button, only when the value differs
```

- **What -15 s / +15 s mean before a rest has started** (designer decides): they change **the length of the rest
  that "Start rest" will begin**, nothing else. The value starts at this exercise's rest (`restSec`), steps in 15 s,
  floor 15 s, ceiling 15:00 (same limits as `SessionTargets.rest`). They do not touch the exercise until the user
  taps **"Set as rest for this exercise"**, which appears only when the value differs and writes `setRest`.
  While running, -15 s / +15 s adjust the running countdown (today's `RestBar`), "Skip" ends it. The "Next:" line is
  `nextLabel()` (Risks in `plan.md`: it must name the row the user will see).
- Starting a rest without a check is a controller change (D2). Starting it does not queue an upload and does not
  change the active set.
- **Rest chip sheet** (section 2.3, chip 3): the same sheet, title "Rest for this exercise", without Start; it lists
  the presets from today's menu (1:00, 1:30, 2:00, 2:30, 3:00, 4:00, 5:00) as 56 pt rows with a check on the current
  one and a Done button. One tap picks and closes.

### 2.8 Row states, colours and contrast

| Role | Dark | Light | On | Contrast |
| --- | --- | --- | --- | --- |
| Active value | `textPrimary` | `textPrimary` | `surfaceRaised` | 9:1 and better |
| Done and upcoming value | `textSecondary` | `textSecondary` | `background` / `surface` | 5.5:1 (dark), 4.9:1 (light) |
| Upcoming ghost value | `textSecondary` (**not** `textTertiary` at 0.7, which is today's placeholder and is below 4.5:1) | same | same | as above |
| Empty "-" placeholder | `textTertiary` | `textTertiary` | field | decorative; the row's label says "empty" |
| Check glyph on accent | `onAccent` | `onAccent` | `accent` | 8:1 / 5.9:1 |
| Rest "1:54" on pill | `onAccent` | `onAccent` | `accent` | same |

A ghost and a done value are told apart by the check column (grey `checkmark` vs outline) and by the row's
VoiceOver value, not by a colour difference.

---

## 3. The state table

A row's state is derived: `isActive` (the controller's `activeSet`, L6), `isCompleted`, `hasValue`
(`reps`, `weightKg` or the ghost). Never stored.

### 3.1 Row states (weight exercise, columns `#` `KG` `REPS` `RPE` check)

| # | State | Trigger | `#` | KG / REPS | RPE | Check | Row | VoiceOver value |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **active** | first open set (L6), or the set the user tapped | raised pill + dot | raised fields, `textPrimary`; real value, else the ghost in `textSecondary`, else "-" | field, 0.55 | filled `accent` | tint + bar | "Next set." |
| 2 | **done** | `isCompleted` | plain, `textSecondary` | values `textSecondary`, no field chrome | value or empty | grey `checkmark` | no tint | "completed" |
| 3 | **upcoming, prefilled ghost** | open, not active, ghost exists (last time, target) | plain | ghost values `textSecondary` (looks real) | empty | outline | none | "not done, planned 10 reps at 75 kilograms" |
| 4 | **upcoming with typed value** | open, not active, user typed | plain | value `textPrimary` | value | outline | none | "not done" |
| 5 | **warm-up** (group open) | `isWarmup` | `W` in `warning` | as 1 to 4 | as 1 to 4 | as 1 to 4 | as 1 to 4 | "warm-up" prefix |
| 6 | **unchecked after done** | the user unchecks a done set | as 1 if now the first open set, else as 3 or 4 | the typed values stay (a done set has real values), shown as in 1 or 4 | kept | as 1 or outline | | The set that was active before returns to state 3 or 4 with its values; **no data changes** |
| 7 | **empty ghost, no history** | no `lastTime`, no target | plain / pill | "-" (`textTertiary`), both columns | empty | outline / filled | | "empty" |

State 7, the active row's check: today `toggleCheck` completes a set with nothing in it. Focused keeps that
(parity, nothing is invented); the design proposes, as an **open question for ios-architect**, that the check on an
**empty** active row opens the number pad on the first empty field instead, because a set without numbers is rarely
what the tap meant. Not decided here, since it changes `toggleCheck`.

The first set of an exercise with **no history and no target** (first time doing it) is the case that most needs
the pad: the active row is empty, so the page shows no ghost; the check opens the pad if the question above is accepted.

### 3.2 By `LoadType`

A fact first (read in the code, not in the brief): **today's live session cannot enter time or distance.**
`SetFocus.Field` is `kg | reps | rpe`; `SetRow` shows `kg` only for `weight` and `bodyweight`, so a time or distance
exercise gets **reps and RPE** fields. `durationSec` and `distanceM` exist on `LocalSet` and the wire, and
`CollapsedExerciseRow` and the history sheet read them (data from imports or other clients shows). So "parity" is
smaller than the brief assumes. The note specifies both: **what PR 1 must do (parity)**, and **the target** for a
later ticket (T6, section 7).

| `LoadType` | Columns in PR 1 (parity, as today) | 4th column | Ghost | Header | Target (T6, needs `SetFocus.Field` + pad modes) |
| --- | --- | --- | --- | --- | --- |
| **weight** | `#` `KG` `REPS` 4th check | RPE (PR 1), E1RM / 10RM / RPE (PR 4) | `ghost(for:in:)` as today | `#` `KG` `REPS` `RPE` | same |
| **bodyweight** | `#` `+KG` `REPS` 4th check. `+KG` = added load (T3). | RPE; RM column shows "-" with no added load (L13, `E1RM.estimate` needs weight above 0) | reps ghost; empty `+KG` shows a `figure.stand` glyph (16 pt, `textSecondary`) meaning "bodyweight", VoiceOver "bodyweight" | `+KG` | same |
| **time** | `#` `REPS`, **spanning the KG slot too** (one wide field, 2 x 74 + 4 = 152 at 320) 4th check | RPE | none (as today) | `REPS` | `#` `TIME` (m:ss, wide field) 4th check; the 4th column is RPE |
| **distance** | as time | RPE | none | `REPS` | `#` `DIST` `TIME` check; 4th column dropped (the two fields take it) |

Rules for **display only**, in PR 1 (so an imported or synced time/distance set is not blank): if
`durationSec != nil` and `reps == nil`, the value field shows `m:ss` read-only (`Fmt.clock`); if `distanceM != nil`,
it shows `Fmt.distance(meters:)`. Read-only fields are not buttons (no pad); the row's label says "time 0:45" or
"distance 5.0 km". The **last-time table** applies the same rule per set. The e1RM / 10RM modes (PR 4) are **not
offered** for time and distance: the header menu lists RPE only, and the header is plain text.

**lb**: the app has no kg/lb setting (`beta-feedback-2/design.md`); no column, label or conversion is added. Every
header says KG. If a lb setting ships, the header unit is the only text that changes (`KG` becomes `LB`).

**Cardio kind with `weight` load type** or an `ExerciseKind.cardio` exercise whose `loadType` is `time`: column set by
`loadType`, never by `kind`.

---

## 4. Designer decides

### 4a. Tile content: a short name, or a name on the current tile only

**Decision: neither. The tile shows the kind glyph over the exercise's position number. Names live in the page title
(current) and in VoiceOver (every tile).** Rendered with the real Satoshi files at 56 pt, dark and light, six
exercises, English and German (throwaway render, not in the repo):

| Candidate | English | German | Verdict |
| --- | --- | --- | --- |
| glyph + 2-line name, 10 pt | "Incline dumbbell..." truncates | "Bankdrücke / n", "Schulterdrü / cken Lang..." split mid-word | rejected |
| name only, 3 lines | readable | "Bankdrück / en / Kurzhant...", "Schulterdr / ücken..." | rejected |
| 2-letter monogram + glyph | `BP` `ID` `CR` `LP` | `B` `BK` `RA` `LE` (for "Latzug eng") | rejected: collides, means nothing in German |
| **glyph over position number** | clean | identical (language-neutral) | **chosen** |
| name on the current tile only | the page title already says it | same | rejected: 56 pt cannot hold "Bankdrücken Kurzhantel schräg"; duplicates the title |

Why the number: a day has 4 to 8 exercises, the position is the one property that is unique, tiny and language-free,
and it matches "Exercise 3 of 6". The cost is honest: a sighted user cannot read "where is the pulldown" from the
strip; they tap (a jump changes no set, the title confirms in 250 ms, a second tap on the strip goes back). This is
the item for the device run (brief "Needs-you"): if it is not enough, the next step is a **name caption under the
strip that follows the finger while it scrubs** (never on tiles), not truncated names.

### 4b. Tile glyph source

L8 says `ExerciseKind`. Checked: `Muscle` has titles only and `LocalSessionExercise` has no muscles, so a
muscle glyph needs a wire change; `kind` is on the row, offline, custom and replaced exercises included. **Keep L8.**
Honest limit: kind is low-information (a day has at most 3 or 4 distinct kinds), which is another reason the position
number carries identity, not the glyph. Proposed symbols (all in the SF Symbols iOS 17 set; ios-developer adds a test
that `UIImage(systemName:)` is non-nil for every case):

| `ExerciseKind` | SF Symbol | Why |
| --- | --- | --- |
| barbell | `figure.strengthtraining.traditional` | a person under a barbell; reads at 20 pt |
| dumbbell | `dumbbell.fill` | |
| kettlebell | `figure.strengthtraining.functional` | |
| bodyweight | `figure.arms.open` | |
| machine | `gearshape.2.fill` | |
| cable | `figure.rower` | a seated pull; the closest available |
| cardio | `figure.run` | |

The glyph is 20 pt, `.medium` weight, in a **fixed 22 x 22 box**, so the numbers below it share one baseline (a
render without the box shifted them by up to 6 pt). Unknown kinds decode to `machine` (`ExerciseKind.init(from:)`), so
there is always a glyph.

### 4c. What -15 / +15 mean on the idle rest sheet

Section 2.7: they set the length of the rest that Start will begin; they never change the exercise until "Set as rest
for this exercise" is tapped.

---

## 5. Dynamic Type, VoiceOver, Reduced Motion

### 5.1 Dynamic Type

Numerals in rows are `ryftNumber` (fixed point sizes, as today: a 56 pt row with a number that does not push the
row's width). So Dynamic Type acts on **labels, chips, pill text, headings and sheets**, and the rules below keep every
number readable while the layout changes.

| Size | Rules |
| --- | --- |
| **L (default)** | everything as in section 2 |
| **XL and XXL** | chips: still one row (horizontal scroll); title wraps to 2 lines; table unchanged (header labels capped at `.xxxLarge`); numerals 22 (390) / 20 (320); pill 48 high |
| **AX1, AX2** | chips become **a vertical stack**, each full width, 44 high, text wraps up to 2 lines; warm-up pill wraps text to 2 lines (min 44 high); numerals 26 at 390; **at 320 the 4th column is dropped from AX1** (field would be under 66 pt); table keeps 4 columns at 390 through AX2; last-time card rows 44 high; rest sheet at `.large` |
| **AX3 and larger** | **4th column dropped everywhere** (390: fields become 124, 320: 100; "102.5" at numeral 30 is about 86 pt, fits); numerals 30; row height grows to 64; **RPE** (when in use) becomes a second line inside the row ("RPE 8.5", `callout`, 44 high, full width, tappable); tiles 64 x 64, strip height 84; pill 56 high, "1:54" `ryftNumber` 30; chip row stacked; rest sheet keys 64; header: title above clock, `...` and Finish keep 48; `AllSetsDoneCard` unchanged (already has an AX3 preview) |

Rules for all sizes: no text truncates except the notes line (one line, full text in the sheet) and the strip
(no text); nothing overlaps the pill (the page's bottom margin is the pill row's height at that size); the pad and the
pill never cover the active row (the focused row is scrolled `.center` into the remaining height; at 320 with the pad
open and fewer than 220 pt left, the **strip hides** until Done, instantly under Reduce Motion, 250 ms fade
otherwise).

### 5.2 VoiceOver checklist (for ui-validator)

Only the **current page** is in the accessibility tree; other pages are `accessibilityHidden`. Reading order:

1. **Header**: Minimise (button, hint "The workout keeps running"), "Upper, elapsed time" (value updates), More, Finish.
2. **Offline banner** if shown.
3. **Strip: one adjustable element.** Label "Exercises". Value "Exercise 2 of 6, Incline dumbbell press, in progress"
   (statuses: "done", "in progress", "not started"; a superset adds ", superset with Cable row"). Swipe up or down
   **changes the page** (no set changes; the value updates; focus stays on the strip). Double tap moves VoiceOver focus
   to the page title. Custom actions: "Add exercise", "Reorder exercises". Tiles are not individually focusable.
4. **Page title** (header trait, button: "Incline dumbbell press, history"), then the **Options** menu ("Options for
   Incline dumbbell press"; the toast's "Undo" action stays on the title as today).
5. Superset line (if any), then the **three chips** as buttons: "Replace exercise, Dumbbell", "Edit targets, 3 x 8 to
   10 at 30 kilograms", "Rest, 1 minute 15 seconds" (each with hint "Opens a sheet"). A disabled chip says "dimmed".
6. Notes button (if any): "Notes: ..." with hint "Edits the notes".
7. **Warm-up pill**: button, "2 warm-up sets", value "collapsed" or "expanded"; hint "Shows the warm-up sets".
8. **Table**: header row hidden. Then **each row one element** (children ignored), in order warm-ups (if open),
   working sets: "Set 2 of 4, 10 reps at 75 kilograms, not done" (existing `accessibilityText` form), traits
   button, plus `selected` when done; **value "Next set." on the active row**; default action = check or uncheck; actions
   "Edit weight", "Edit reps", "Edit RPE", "Mark as warm-up / working set", "Delete set" (unchanged). Ghost values are
   read as "planned 10 reps at 75 kilograms". In PR 4 the label adds "estimated one-rep max 100 kilograms".
9. **Add set** button. For an open group, "Add warm-up set".
10. If `isAllDone`: "All sets done" (header), "5 exercises, 17 sets", **Finish workout** (the existing card).
11. **Last-time card**: one button, label "Last time, Tue 3 November: set 1, 10 reps at 75 kilograms; set 2, 6 reps at
    80 kilograms", hint "Opens history".
12. **Toast** (if present), then the **rest pill**: button, label "Rest timer", value idle "Not running. Starts at 1:15",
    running "1 minute 54 seconds left. Next: Incline dumbbell press, set 2 of 4" (spoken in 5 s steps, existing
    `train.rest.value`), adjustable (up or down = plus or minus 15 s, running only), actions "Skip rest",
    "Open rest sheet".
13. **Number pad** (when open): unchanged. Opening it moves focus to the pad's value; Done returns focus to the row.

Focus moves: after a check, VoiceOver focus stays on the row (it announces "completed"); when auto-advance changes the
page (L1), focus goes to the new page's **active row** (existing `sessionVoiceOverFocus`) and one announcement is
posted: "Incline dumbbell press, set 1 of 4". After the last set: "All sets done. Finish workout available at the
bottom." (existing).

Further checks: contrast of every state in both schemes (section 2.8), 44 pt hit areas (chips, pill, `#`), tiles name the
state without colour, the ring is not the only cue (number brightness), Voice Control names work ("Show history",
"Check off", "Rest timer"), Switch Control reaches every row action through the actions rotor, undo window longer with
VoiceOver or Switch Control on (`SessionController.undoWindow`).

### 5.3 Reduced motion

- Page change: with the setting off, a horizontal slide of at most 250 ms (`Theme.Motion.quick`, ease-out, never a
  spring); **on: instant swap**, no fade. The same holds for auto-advance (the 0.6 s delay stays, the move is instant).
- Strip scroll to the current tile, ring move, badge appear: animated 250 ms, **off: instant**.
- Warm-up chevron and group expand: 250 ms, **off: instant**.
- Rest pill: idle to running swap 250 ms cross-fade, **off: instant**; flash at the end **off**, the text changes only;
  the countdown number does not roll (`.identity`).
- Haptics are not motion: unchanged (check: success; rest end: heavy impact; nothing on page change, as the brief says).
- Delete-swipe reveal keeps its 250 ms (`SetRow`), instant when reduced.

---

## 6. Copy (new strings, en and de, du-form)

Existing keys are reused wherever the text fits, so the catalog diff stays small. German reuses the app's terms:
**Pause** (rest), **Supersatz**, **Aufwärmsatz**, **erledigt**. (The brief's "geschafft" for "All sets done" is dropped:
the shipped string is "Alle Sätze erledigt"; one phrase for one thing.) Not written to the catalog by this ticket.

| Where | English | German |
| --- | --- | --- |
| **Profile toggle (L4)**, label | Advance to the next exercise | Zur nächsten Übung wechseln |
| Profile toggle, footer (replaces "Jumps to the next set when you finish an exercise.") | Moves on to the next exercise after your last set. | Wechselt nach deinem letzten Satz zur nächsten Übung. |
| Strip, VoiceOver label | Exercises | Übungen |
| Strip, value | Exercise %lld of %lld, %@, %@ | Übung %1$lld von %2$lld, %3$@, %4$@ |
| Strip status, done | done | erledigt |
| Strip status, in progress | in progress | aktiv |
| Strip status, not started | not started | noch offen |
| Strip status suffix (superset) | superset with %@ | Supersatz mit %@ |
| Add tile (VoiceOver) | Add exercise | Übung hinzufügen (existing) |
| Title, VoiceOver | %@, history | %@, Verlauf |
| Superset line | Superset with %@ | Supersatz mit %@ |
| Equipment chip, VoiceOver label | Replace exercise, %@ | Übung ersetzen, %@ |
| Target chip, VoiceOver label | Edit targets, %@ | Ziele bearbeiten, %@ |
| Target chip, no target | Set target | Ziel festlegen |
| Rest chip, visible | Rest %@ | Pause %@ (existing) |
| Chip hint | Opens a sheet | Öffnet ein Fenster |
| Warm-up pill, 1 | 1 warm-up set | 1 Aufwärmsatz |
| Warm-up pill, many | %lld warm-up sets | %lld Aufwärmsätze |
| Warm-up pill, VoiceOver value | collapsed / expanded | eingeklappt / ausgeklappt |
| Warm-up pill, hint | Shows or hides the warm-up sets | Zeigt oder verbirgt die Aufwärmsätze |
| Warm-up, add | Add warm-up set | Aufwärmsatz hinzufügen |
| Column header, set | # | Nr. (VoiceOver only; visible is "#") |
| Column header, bodyweight load | +KG | +KG |
| Column headers | KG, REPS, RPE | KG, WDH, RPE (existing "Reps" / "RPE" keys) |
| Bodyweight, empty load (VoiceOver) | bodyweight | Körpergewicht |
| Ghost value (VoiceOver) | planned %@ | geplant: %@ |
| Last-time heading | Last time . %@ (date) / Last time | Letztes Mal . %@ / Letztes Mal |
| Last-time card, VoiceOver | Last time, %@: %@ | Letztes Mal, %@: %@ |
| Last-time card, hint | Opens history | Öffnet den Verlauf |
| All sets done | All sets done | Alle Sätze erledigt (existing) |
| Rest pill, VoiceOver label | Rest timer | Pausentimer (existing) |
| Rest pill, idle value | Not running. Starts at %@ | Läuft nicht. Startet bei %@ |
| Rest pill, ending (visible, 1 s) | Rest over | Pause vorbei (existing) |
| Rest sheet, title | Rest | Pause |
| Rest sheet, start | Start rest %@ | Pause %@ starten |
| Rest sheet, adjust | -15 s / +15 s | -15 s / +15 s (existing) |
| Rest sheet, skip | Skip rest | Pause überspringen (existing) |
| Rest sheet, save | Set as rest for this exercise | Als Pause für diese Übung festlegen |
| Rest sheet, footer (idle) | Changes the length of this rest only. | Ändert nur die Länge dieser Pause. |
| Rest chip sheet, title | Rest for this exercise | Pause für diese Übung |
| `...` menu, new item | Add warm-up set | Aufwärmsatz hinzufügen |
| Page announcement | %@, set %lld of %lld | %@, Satz %lld von %lld |
| PR 4 only: column menu | Estimated 1RM / Estimated 10RM / RPE | Geschätztes 1RM / Geschätztes 10RM / RPE |
| PR 4 only: header | E1RM / 10RM | E1RM / 10RM |
| T6 only (time, distance) | TIME / DIST | ZEIT / DIST. |

No other app's vocabulary; no brand names.

---

## 7. The PR 4 call: split, with a different cut

Default is split, and I see no reason to keep the RM column in PR 1. **The cut moves, though:**

- **PR 1 keeps the last-time card as a table** (`#`, `KG`, `REPS`, RPE when present). The card replaces the "Last
  time: ..." sentence that PR 1 removes with `ExerciseCard`'s header; shipping the sentence in PR 1 and a table in PR 4
  would build the reading twice, and L7's date heading is part of the same view.
- **PR 1's fourth column is RPE**, today's field, same 48 to 56 pt width, same keypad flow. Behaviour parity.
- **PR 4 = the RM column**: `E1RM` / `10RM` / `RPE` header menu with persistence, `TrainMath` 10RM (L13:
  `e1RM x 30 / 40`, so 80 x 6 gives e1RM 96, 10RM 72; 75 x 10 gives 100 and 75; 15 reps read as 12), the bodyweight rule
  ("-" without added load), the RM column in the last-time table, and the AX rules for the column (section 5.1).
  Header cycling is a plain text button; it is never the only way to enter RPE: the row's context menu and
  VoiceOver actions get "Edit RPE" in PR 1 (the existing accessibility action stays, a context menu item is added).
- **Default of the fourth column in PR 4**: E1RM, except an exercise whose `targetKind` is `.rpe`, or any set of the
  session with a value in RPE, where RPE is shown. This avoids hiding RPE from users who log it.
- **T6 (new, optional)**: time and distance entry (`SetFocus.Field` cases, pad modes `m:ss` and decimal km, `KG`
  becomes `TIME` or `DIST`), because section 3.2 found it missing today. Not on the path of this brief.

Reasons to split: PR 1 is already the page container, strip, chips, warm-up group, table, last-time card and
accessibility; PR 4 adds a persisted setting, `TrainMath` tests and a menu, none of which blocks the layout.

---

## 8. Existing behaviours the Focused layout keeps, and where they live

| Behaviour | Where in the Focused layout |
| --- | --- |
| **Plate calculator** | `...` menu item (barbell only) and the number pad's "Plates" button on the KG field (unchanged `NumberPad`); `PlateCalculatorSheet` presented by `SessionView`. |
| **History** | The page title is a button (chevron), the `...` item "History", and the last-time card. All open the same `ExerciseDetailView` sheet. |
| **Swipe to delete a set** | On unchecked rows, left swipe reveals Delete (88 pt, `alert`); confirmation if the set has values; context menu "Delete set"; VoiceOver action. **Conflict with paging**: a left swipe on an unchecked row belongs to the row (the existing 1.5:1 axis test); the pager takes horizontal drags that start outside the table, and a right swipe anywhere. To go forward from the table: swipe on the title, chips or last-time card, or tap the strip. Checked rows have no row gesture, so paging passes through. ios-architect confirms the container allows this (D2). |
| **Number tap = warm-up toggle** | The `#` slot, as today (44 x 56 hit area), plus context menu and VoiceOver action. |
| **Add set** | Button under the table. "Add warm-up set" in the open group and the `...` menu. |
| **Superset controls** | `...` menu: "Superset with next" / "Remove from superset"; shown on the page as the superset line and in the strip as the bar; `nextUp` decides the partner and L1's advance changes the page to it. |
| **Notes** | Notes line under the chips (tap edits), `...` item "Notes". |
| **Remove exercise** | `...` menu, with today's confirmation dialog; the strip loses the tile, the page moves to the neighbour (architect: no `updatedAt` for the page change, L10). |
| **Reorder** | Long press on a tile and the header `...` menu "Reorder exercises" open `ReorderSheet`; the strip follows the order. |
| **Replace / Edit targets** | Equipment chip, target chip and the `...` menu. |
| **Rest per exercise** | Rest chip (sheet), rest sheet's "Set as rest for this exercise", `...` item "Rest" submenu stays. |
| **Rest timer** | `RestPill` and its sheet; `RestBar` remains in List only (L2). Live Activity, rest-end haptic untouched. |
| **Number pad** | `NumberPad` under the pill row, kg to reps to next-set flow (`nextField()` crossing to the next set of the same page; at the end of a page the pad closes). Page change with the pad open closes it (focus nil); typed digits are committed as with Done. |
| **Undo toast** | `SessionToastOverlay` stays an inset above the pill row; the title's "Undo" action stays. |
| **Offline notice** | One-line banner under the header, same text; every set still saved locally. |
| **All sets done / Finish** | `AllSetsDoneCard` below Add set on every page while `isAllDone`; header Finish unchanged. |
| **Add exercise** | The `+` tile at the end of the strip; the page jumps to the new exercise. With no exercises: the page says "An empty session. Add your first exercise." with the `+` tile. |
| **Jump to next, 3 s window, 0.6 s delay** | `SessionAdvance` (L1); `.advance` becomes a page change; a swipe or strip tap in the last 3 s prevents it. |
| **Collapsed finished cards** | Not used in Focused (L1 ignores `collapse`): a finished exercise is a done tile and a page the user can still open. |
| **Haptics, keep-awake, Live Activity, pause on background** | `SessionView`'s modifiers, unchanged. |
| **Identifiers** | `set.<position>.<number>`, `session.finish`, `session.restBar` (kept on the pill), `session.allDone`, `session.replace`, `session.editTargets`, `profile.jumpToNext` stay (plan: UI tests run under either layout). New: `session.strip`, `session.strip.<n>`, `session.page.title`, `session.warmups`, `session.restPill`. |

---

## 9. Handoff notes

- **Components in `Design/`** the spec needs pinned (token-only, previews dark, light, AX3): none in this ticket. If
  ios-developer wants them, the two worth pinning are `ExerciseTile` and `RestPill` (both pure views, input = state
  enum), so geometry tests and `ImageRenderer` render tests (L9) can pin 56 x 56 and 48 pt.
- **Screenshots per state** (strip with done/current/upcoming/superset, page in the seven row states, warm-up pill
  collapsed and expanded, last-time card, pill idle and running, at 390 and 320, dark and light, XL and AX3) are made
  from `Preview/MockData.swift` in PR 1 and committed under this folder by the PR, not before.
- **Open questions** (for the lead): (1) empty active row's check, section 3.1; (2) time and distance entry (T6);
  (3) Finish capsule demotion: with an accent check, an accent Finish and an accent running pill, the screen has three
  filled teal controls. Recommend, for PR 5, that Finish is `surface` + accent text until `isAllDone` (the
  identifier stays); not in PR 1, the header is shared with List.
