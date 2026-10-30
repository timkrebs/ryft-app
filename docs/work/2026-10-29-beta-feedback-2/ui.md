# Session screen: replace / edit, jump to next, pinned rest bar (ui spec, D1)

Scope: F1 (replace, edit targets) and F2 (jump to next, pinned rest bar). Feature views are the ios-developer's;
this spec adds no colours and no new tokens. Examples are synthetic (day "Upper", 70 x 8 / 80 x 6).

Sources read: `SessionView`, `ExerciseCard`, `AddExerciseSheet`, `RestTimerView`, `Theme`, `Typography`, `StatusViews`.
There is **no toast or undo pattern in the app today** (grep: only `InlineMessage`, a static inline row), so section 4
defines one new primitive, `UndoToast` (`Design/UndoToast.swift`, token-only, previews dark/light/AX3).

What the eye sees first on the session screen: the clock and the **current set** (the one the user does next), then
the rest bar, then the cards. Everything here serves that: the rest bar and the jump put the next set where the
thumb already is; replace and edit are one tap away but never in the way.

---

## 1. Exercise `...` menu and context menu

The card's `Menu` (the `ellipsis` button, 44 x 44, label "Options for Incline bench press") and the card's
`.contextMenu` (long-press on the card header; same items, same order, built from one shared `@ViewBuilder`) show:

| # | Item | SF Symbol | Shown when |
| --- | --- | --- | --- |
| 1 | Replace exercise... | `arrow.triangle.2.circlepath` | always |
| 2 | Edit targets... | `slider.horizontal.3` | always |
| 3 | Notes | `note.text` | only if the card has no visible notes entry yet (today none exists, so: shown; hidden once a card-level notes field ships) |
| 4 | Plate calculator | `circle.grid.cross` (unchanged) | `kind == .barbell` (today the code uses `usesWeight`; the brief says barbell only, use `exercise.kind`) |
| 5 | History | `chart.xyaxis.line` | always |
| 6 | Rest 1:15 > | `timer` (new; the submenu title carries the value) | always |
| 7 | Superset with next / Remove from superset | `link` / `link.badge.plus` (unchanged) | next exercise exists and is linkable / already in a group |
| - | divider (Menu's built-in section break: wrap 1-7 and 8 in separate `Section`s) | | |
| 8 | Remove exercise | `trash`, role `.destructive` | always |

Notes:
- Replace and Edit targets stay enabled when the exercise is fully done (a user may fix a wrong exercise afterwards).
  Replace on a fully done exercise opens the sheet in split mode with 0 remaining sets: the pick is **inserted after
  it with the planned count** minus done = 0; there is nothing to continue, so Replace is **disabled** (greyed, no
  subtitle needed) when the card has no open sets *and* no planned sets left. Edit targets is never disabled.
- Remove exercise keeps today's confirmation dialog.
- Menu labels are sentence case and end with "..." only where a sheet follows (Replace, Edit targets).
- VoiceOver: the menu button keeps the label "Options for <name>"; items read as their titles.

---

## 2. Replace sheet (`AddExerciseSheet` in replace mode)

**Purpose:** pick the exercise that takes the old one's place, with the least typing, and be told exactly what
happens to sets already done.

Presentation: same sheet as Add exercise (`.large`), plus `.presentationDetents([.large])`; the keypad closes first
(the controller drops `focus` when the menu item is chosen).

### Layout

```
+--------------------------------------------------+
| Cancel      Replace Incline bench press          |  title: LocalizedStringKey "Replace \(name)"
| [ Search exercises                              ]|  .searchable, always
+--------------------------------------------------+
| SPLIT NOTE (only when done sets > 0)             |  Theme.surface card, accent hairline
|  Your 2 done sets stay as Incline bench press.   |
|  Bench press continues with 2 sets.              |  (second line appears once a pick is highlighted;
+--------------------------------------------------+   before: "Your 2 done sets stay as Incline bench press.
| SIMILAR                                          |   The new exercise continues with 2 sets.")
|  [icon] Bench press           barbell . Chest  + |  ExerciseRow (unchanged), max 6 rows
|  [icon] Dumbbell bench press  dumbbell . Chest + |
|  [icon] Chest press machine   machine . Chest  + |
| ------------------------------------------------ |  thin rule (Theme.separator)
| ALL EXERCISES                                    |  header only while "Similar" is shown
|  [chips: All muscles | All kinds]                 |
|  ...normal results...                            |
|  [ + Custom exercise ]                           |
+--------------------------------------------------+
| ALSO CHANGE THE PLAN        (plan sessions only) |  pinned below the list, Theme.surface bar
|  [ off ]  Also change the plan                   |  Toggle, tint Theme.accent
|  Applies from the next Upper day.                |  caption, textSecondary
+--------------------------------------------------+
```

- Section labels use `ryftLabelStyle()` (tracked caps), like other sections.
- Tap on a row = pick = immediate (as in Add). No separate confirm button: the split note and the toggle are read
  *before* the tap, and Undo (section 4) is the safety net. The toggle is the only thing that can have a lasting
  effect, hence it sits in view and is off by default.
- Selecting highlights nothing; the sheet dismisses on pick and the toast appears on the session screen.

### "Similar": ranking, without a movement-pattern field

The API's `Exercise` has `kind`, `primary_muscles`, `secondary_muscles`, `equipment`, `load_type`, `is_unilateral`.
**It has no movement-pattern field** (press / row / curl ...). The brief's "same movement pattern" cannot be computed.
What Similar uses instead, in this order, all from the cached library, on device, offline-capable:

1. **Candidates:** not the exercise itself, not `archived`, same `loadType` as the old one (so ghost values and the
   kg column keep working), and `primaryMuscles.first == old.primaryMuscles.first` (the **first primary muscle**).
2. **Sort keys, in this order:**
   1. same `kind` as the old exercise first (the "same equipment" rule);
   2. then by kind order **barbell -> dumbbell -> machine -> cable** (others after: kettlebell, bodyweight, cardio;
      the old exercise's own kind is already first);
   3. more shared muscles (count of `primary + secondary` overlap with the old exercise), descending;
   4. same `isUnilateral` first;
   5. non-custom before custom;
   6. name, localized, ascending (stable).
3. **Cap:** 6 rows. If only 1 or 2 exist, show them; if 0, the section is omitted (no empty header).
4. A pure muscle match is a weaker promise than "same movement", so the section title is **"Similar"** and the row
   subtitle shows kind and muscles as today; the section never claims the movement is the same.
5. Search or a muscle/kind filter active: the Similar section hides (the user is steering), the normal list shows.

File in `docs/API_REQUESTS.md` (C1, optional, not blocking): `movement_pattern` on exercises (enum) so Similar can
require it. Until then rule 1 above stands; the PR says so.

### The split note (done sets exist)

Trigger: the old exercise has >= 1 completed *working* set (warm-ups don't count: they don't make it "history").
Copy (en): "Your 2 done sets stay as Incline bench press. Bench press continues with 2 sets."
- Before any row is tapped there is no name yet, so the sheet shows the first sentence plus "The new exercise
  continues with 2 sets." The two-line form with the real name is only reachable after a pick, so in practice the
  sheet shows the generic form and **the toast carries the specific one**: "Replaced with Bench press . Your 2 done
  sets stay as Incline bench press" (section 4). The brief's one-liner with the name is therefore used in the toast
  and in VoiceOver after the pick; the sheet uses the generic form. (Decision: no live-updating note, nothing is
  highlighted before the tap.)
- Plural rules (xcstrings variations): 1 / other for done sets and remaining sets. Remaining = planned - done, min 0.
  If remaining is 0 Replace is disabled (section 1).
- No done sets: no note at all (nothing to explain: a plain swap).

### "Also change the plan"

- Row shown only when the session comes from a plan (`session.planDayID != nil`); in a free session it is absent
  (no disabled row, no explanation).
- Off by default, and **reset to off every time the sheet opens** (never remembered).
- Caption (en): "Applies from the next Upper day." (day name from the plan; fallback "next session of this day").
- If the user is offline: the toggle stays usable, the change is queued like other plan edits; caption becomes
  "Applies from the next Upper day. Saved when you're back online."
- **Confirmation** after the pick, on the session screen, inside the toast, not a dialog (a dialog mid-set is
  hostile): "Replaced with Bench press . Also changed in your plan from the next Upper day" with Undo.
  Undo reverts the session **and** the plan change if it has not been saved to the server yet; if it has, Undo
  reverts the plan with a second update (the controller's concern, D2); the toast copy is the same.
- Toggle VoiceOver: "Also change the plan, switch button, off. Applies from the next Upper day."

### States

| State | Trigger | What shows | Action |
| --- | --- | --- | --- |
| Normal | library loaded | Similar + list | tap a row |
| No similar | no candidates | Similar section omitted | use search |
| Library empty / not loaded | `library.exercises.isEmpty` | `InlineMessage` "The exercise library hasn't loaded yet. Create a custom exercise to log it now." | Custom exercise |
| No search match | filter excludes all | existing `InlineMessage` "No exercise matches. Create it as a custom exercise." | Custom exercise |
| Offline | `!sync.isOnline` | works from the cached library; one caption under the search: "Offline. Showing your saved exercise library." Ghosts: new exercise starts without "Last time" (see below) | none needed |
| Custom pick | Custom exercise form saved | treated as a pick (no history, no ghost) | |

Ghost and "Last time" after the swap: from the new exercise's history if cached; offline or none: the card shows
**no "Last time" line** and the set rows show the em-dash placeholder, not stale values from the old exercise. No
spinner: when the history arrives the line appears (animation `Theme.Motion.quick`, none with Reduce Motion).

Dynamic Type: rows are `minHeight: 56` and grow; subtitle wraps to 2 lines at AX sizes (drop `.lineLimit(1)` in
replace mode); the pinned toggle bar becomes a vertical stack (label above caption) at AX1 and up.

---

## 3. Edit targets sheet

**Purpose:** correct this session's plan for one exercise without leaving the workout. Session only; says so.

Presentation: `.medium` detent (`.large` at AX sizes), title "Edit targets", Cancel / Done in the toolbar. Done is
the only confirm; Cancel discards. Drag-to-dismiss counts as Cancel.

```
+--------------------------------------------------+
| Cancel          Edit targets              Done   |
| Incline bench press                              |  headline, textPrimary
+--------------------------------------------------+
| SETS                                             |
|  [ - ]        4        [ + ]                     |  big number ryftNumber(34), tabular; 56 pt keys
|  2 sets are done and stay.                       |  caption textSecondary (only if done > 0)
| REPS                                             |
|  [ - ]  8 - 12  [ + ]   min / max steppers       |  two compact steppers: "From" 8, "To" 12
| TARGET WEIGHT (kg)                               |  unit follows the kg/lb setting
|  [ -2.5 ]     70        [ +2.5 ]    (kg)         |  empty = "None": shows em-dash + "Clear" button
| REST                                             |
|  [ - ]      1:15       [ + ]        (+-15 s)     |  step 15 s, range 0:15 - 10:00
+--------------------------------------------------+
| Changes apply to this workout only. To change     |  caption, textTertiary
| your plan, use Replace or the plan editor.        |
+--------------------------------------------------+
```

- Steppers are custom 56 pt `PressableButtonStyle` keys like the keypad's (accent text on `Theme.accent.opacity(0.14)`),
  not the system `Stepper`; the value between them is `.monospacedDigit`. Long-press repeats.
- **Sets stepper** lower bound = the number of **checked or non-empty sets** (min 1 working set... see below).
  - Reducing removes sets from the **end, only those that are empty and unchecked**. If the target count is below
    that bound, the "-" key is disabled (not hidden); the caption under it explains: "2 sets are done and stay." or,
    when the blocker is values without a check: "Sets with values can't be removed here. Delete them in the list."
  - A checked set is **never** deleted by this sheet (acceptance criterion). Adding sets appends empty ones.
  - A "-" press that would remove a set in the middle never happens: removal is end-first; if the last open sets
    are before a checked one (out-of-order), the key disables at that boundary.
- Rep range: min <= max enforced (moving min above max moves max with it). Range 1-100. Equal values show "8" not
  "8 - 8" on the card (existing `targetText` logic).
- Target weight: hidden for `loadType` time/distance; for bodyweight it is "added weight". Steps follow the
  existing keypad steps (2.5 kg / 5 lb). Clearing is allowed; the card then shows no target.
- Rest: the same value the "Rest" submenu edits (the submenu stays as a fast path).
- Done writes once (one `sessionChanged`), updates the card's target line and, if a rest is running for this
  exercise, does **not** change the running rest.
- VoiceOver: each stepper is one element with `accessibilityAdjustableAction` (swipe up/down), label "Sets",
  value "4"; hint for the disabled case is read as value suffix ("4, minimum, 2 sets are done").
- Dynamic Type: the stepper rows stack (label above, keys below) at AX1+; value font scales via `ryftNumber` size
  relative to metrics, min 56 pt keys stay.

---

## 4. Undo toast (`UndoToast`)

New primitive. Used by Replace now; designed so remove-exercise / delete-set could use it later.

```
          ...scroll content...
 +---------------------------------------------+
 | Replaced with Bench press            [ Undo ]|  Theme.surfaceRaised, hairline Theme.separator,
 +---------------------------------------------+  radius Theme.Metrics.tileRadius, padding 14
 [ ring 1:37  Next: Bench press . set 1 of 4  -15 +15 Skip ]   <- pinned rest bar (when resting)
 [ number pad (when a field is focused)                    ]
```

- **Placement:** an overlay at the bottom of the scroll area, in a `VStack` *above* whichever fixed element is at the
  bottom: above the number pad if it is open, above the pinned rest bar if it is showing and the pad is closed;
  the rest bar is **below the header**, not at the bottom (section 6), so the toast sits at the bottom of the screen
  above the safe area, or above the pad. Result: it never covers the rest bar's buttons or the pad's keys, and it
  moves with the pad (animation `Theme.Motion.quick`, none under Reduce Motion).
- Width: screen padding 16 each side; height >= 56. Text: `ryft(.callout)`, `textPrimary`, up to 2 lines (3 at AX).
  The "Undo" button is a text button, `Theme.accent`, min 44 x 44 hit area, trailing.
- **One accent:** the toast has no accent fill; only the Undo word is teal.
- **Timing:** visible 5 s, appears with a 0.25 s ease-out fade + 12 pt rise; leaves with a 0.25 s fade. Reduce Motion:
  opacity only, no rise. The countdown is not drawn (no bar): 5 s is short and a moving bar competes with the rest
  ring. A second replace within 5 s replaces the toast and its undo (undo history is one level deep).
- **Pause:** the 5 s timer pauses while VoiceOver is focused on the toast or Voice Control/Switch Control is on
  (if `UIAccessibility.isVoiceOverRunning`, the toast stays **10 s** instead of 5; the brief's 5 s is the sighted
  default). Open question 2 for the lead if a fixed 5 s is required.
- **VoiceOver:** on appearance post `UIAccessibility.post(.announcement, "Replaced with Bench press. Undo available.")`
  (no focus steal, so the user's reading position is kept). The toast is one container; the Undo button is
  reachable by swiping and also exposed as a custom action "Undo" on the **replaced card** (so it survives focus
  moving) until it expires. After Undo: announce "Restored Incline bench press."
- Undo restores the exact previous state (sets, values, positions, superset groups, focus); the toast then
  shows nothing (no "Undone" toast); the card briefly takes the existing `quick` highlight (accent 0.06 -> clear).
- Dismissal: expiry, tap on Undo, a new toast, or leaving the session screen. Swipe down dismisses early.
- Copy (en) - replace: "Replaced with Bench press"; with split: "Replaced with Bench press. Your 2 done sets stay as
  Incline bench press."; with plan: "Replaced with Bench press. Changed in your plan from the next Upper day." The
  string "Replaced with Bench press . Undo" in the brief is the visual (name, then the Undo button), not one string.

---

## 5. Collapsed card, current set, all-done prompt

### Collapsed exercise row

Trigger: 0.6 s after the last open working set of an exercise is checked, in order (T2 rules; supersets alternate
and do not collapse until both are done). Tap or VoiceOver activate expands; it never re-collapses while expanded;
unchecking a set on it expands it.

```
+--------------------------------------------------+
| [v] Incline bench press        4 sets . best 80 x 6 |  Theme.surface, same radius as Card
+--------------------------------------------------+     height 56 (min), padding 14
```

- Left: a teal `checkmark.circle.fill` (the accent is allowed here: it marks "done"), then the name
  (`ryft(.headline)`, textPrimary). Right: "4 sets . best 80 x 6" in `ryftNumber`, `monospacedDigit`, textSecondary;
  trailing `chevron.down` (textTertiary) as the expand cue.
- "best" = highest `weight x reps` e1RM-free rule: the working set with the highest load, ties by reps. Bodyweight:
  "best 12 reps"; time/distance: the best value with unit; no sets with values: "4 sets" only.
- The header string reads as the brief says: "checkmark Incline bench press . 4 sets . best 80 x 6" (separators are
  visual; the `Text` uses a space-dot-space).
- Dynamic Type: at AX1+ the row becomes two lines: name on line 1, "4 sets . best 80 x 6" on line 2; the chevron stays
  trailing. Name never truncates to one line.
- VoiceOver: one element, label "Incline bench press, completed. 4 sets, best 80 kilograms for 6 reps." trait
  `.isButton`, hint "Expands the sets", `accessibilityAddTraits(.isHeader)` is kept for the name only when expanded.
- Motion: collapse `Theme.Motion.quick` (height + opacity); Reduce Motion: immediate swap.
- Superset bracket: collapsing is per card; a bracket with one collapsed card keeps its bracket.

### "Current set" highlight

The next open set row (the jump target, and also what the rest bar names) gets:
- background `Theme.accent.opacity(0.10)` (the checked row uses 0.06; this one is a touch stronger), and a leading
  2 pt `Theme.accent` bar (the same bracket vocabulary the superset uses). No border, no pulse, no keypad.
- It tracks `nextUp`: the highlight moves when the user checks a set or taps another set's field (focus overrides:
  a focused field already has its 2 pt accent border; the row highlight stays under it).
- It is cleared when the workout has no open set.
- VoiceOver: the set's label gains a prefix "Next set." (the row stays one element). When the jump happens, post
  `.layoutChanged` focused on that row only if VoiceOver is running; otherwise nothing is announced.
- Not colour-only: the leading bar is a shape; contrast of the bar on `Theme.background` >= 3:1 in both schemes.

### All-done prompt

Trigger: no open working set remains. The list scrolls to the bottom (animated `quick`; none under Reduce Motion)
and shows, above "Add exercise":

```
+--------------------------------------------------+
|  All sets done                                   |  headline
|  8 exercises . 32 sets                           |  caption, tabular
|  [      Finish workout?                         ]|  TealButtonStyle (prominent) = same flow as the header
+--------------------------------------------------+     Finish (confirmationDialog "Finish workout?")
```

- Copy: "All sets done. Finish workout?" in the card title (period vs. dash: the brief's "All sets done - Finish
  workout?" is one line; use the question as the button: title "All sets done", button "Finish workout"). The button
  opens the existing `confirmFinish` dialog (no new flow).
- Appears once per "all done" state; it hides when a set is unchecked or an exercise added. Dismiss: none needed;
  it is content, not a modal. No haptic beyond the set-check one.
- VoiceOver: on appearance, announcement "All sets done. Finish workout available at the bottom." (no focus move).

---

## 6. Pinned rest bar

### Decision: drop the large card; always the compact bar

I recommend **dropping the large `RestTimerView` card from the scroll content** and showing only the compact pinned
bar. Reasons:
1. One home for the timer. With "large when at top, compact otherwise" the same data lives in two places that swap at
   a scroll threshold: the layout jumps under the thumb at exactly the moment the auto-scroll fires.
2. The large card takes about a third of the screen (the feedback screenshot) and pushes the current set down; the
   whole point of F2 is that the next set sits near the top.
3. The compact bar keeps every function (time, next, -15 / +15 / Skip). The only loss is the 46 pt numeral; a 28 pt
   tabular numeral in a bar that never moves is readable at arm's length mid-set.
4. The finished state ("Rest over") also lives in the bar, so there is no second banner to scroll away.

The variant B for the PR screenshot (large card at scroll top, bar elsewhere) is specified for comparison only:
the existing card, shown when `scrollOffset <= 8 pt` and hidden (with the bar fading in over 0.25 s) beyond. The PR
shows A (decided) and B (rejected) side by side, light/dark, XL.

### Layout (bar, running)

```
header (clock)
+--------------------------------------------------+  Theme.surface, hairline Theme.accent.opacity(0.35)
| (ring)  1:37    Next: Bench press . set 1 of 4   |  radius Theme.Metrics.tileRadius, padding 12 x 14
| 36 pt           [ -15 ]  [ +15 ]  [ Skip ]       |
+--------------------------------------------------+
```

- Placed directly below `header` (not in the `ScrollView`), full width minus 16 pt padding, 8 pt top spacing,
  8 pt bottom, then the scroll area. Appears only while `rest.phase != .idle`.
- Ring: 36 pt, 4 pt stroke, `Theme.accent` on `Theme.accent.opacity(0.14)`, `trim` from `fraction(at:)`, no icon in
  the centre (too small). Time: `ryftNumber(size: 28)`, `monospacedDigit`, `textPrimary`, `.numericText(countsDown: true)`.
- "Next:" line: `ryft(.caption)`, `textSecondary`, 1 line, tail truncation, on the right of the time. At XL it wraps.
- Buttons: -15 / +15 are secondary (`Theme.surfaceRaised` capsule), Skip prominent (`Theme.accent` capsule, `onAccent`
  text) = the only filled teal in the bar. Button height 44 (compact; the large card's 56 was for thumbs on the big
  card; here the hit target is >= 44 and `.contentShape` is padded to 48). Labels "-15", "+15" (with true minus U+2212),
  "Skip"; the "s" is dropped in the compact bar (VoiceOver says seconds).
- Total height ~ 96 pt at default size (vs. ~ 190 for the card). One line of buttons.
- Finished state: the bar becomes `Theme.accent` filled (same as today's banner colour), bell icon, "Rest over .
  Next: Bench press . set 1 of 4", trailing `xmark`; tap dismisses. Height 56.
- Light/dark: colours only from tokens; the finished fill uses `onAccent` text, 4.5:1.

### Dynamic Type

- Up to XXL: layout as above, "Next" truncates (1 line).
- XL and larger (`dynamicTypeSize >= .xLarge`, use `ViewThatFits`): two rows: row 1 = ring + time + (Next wraps to 2
  lines); row 2 = the three buttons, equal widths (`frame(maxWidth: .infinity)`), 44 pt min. "Ueberspringen" ("Skip" in
  German) uses `minimumScaleFactor(0.7)`.
- AX1 and larger: the ring shrinks to 28 pt, the time stays `ryftNumber(size: 28)` scaled with metrics; "Next" gets
  up to 3 lines; the three buttons stack vertically at AX3 (each full width, 48 pt). The bar's height may reach 1/3 of
  the screen at AX3; to protect the list it **collapses to a one-line pill** (ring + time + Skip) when the list is
  scrolled (any manual scroll after 1 s) at AX sizes; tapping the pill expands it for 4 s. (Only at AX sizes.)

### Behaviour

- Bar and auto-scroll: the scroll anchor `.top` uses `scrollPosition`/`proxy.scrollTo` with a top safe-area inset equal
  to the bar's height (`safeAreaInset(edge: .top)` on the `ScrollView` content, so "under the bar" is automatic and the
  highlighted row is not hidden by it).
- Adjust: -15 floors at 0:00 (then rest ends); +15 caps at 10:00. The numeral animates `numericText`; ring uses
  `Theme.ringAnimation`; Reduce Motion: no animation, value swaps.
- The bar and the number pad together: the bar stays (it's above the list), the pad is below; the list area between
  shrinks. At AX sizes with the pad open the bar collapses to the pill automatically.
- Offline: no change (the timer is local). The Offline label stays at the top of the scroll content.

### VoiceOver

One element for the bar: `.accessibilityElement(children: .ignore)`.
- Label: "Rest timer"
- Value: "1 minute 37 seconds left. Next: Bench press, set 1 of 4." (updated each 5 s, not each 0.5 s, to avoid
  chatter; `.updatesFrequently` trait)
- Traits: `.updatesFrequently`
- Actions (`accessibilityAction(named:)`): "Fifteen seconds less", "Fifteen seconds more", "Skip rest". (These are
  *actions*, not separate focus stops, per the brief. `accessibilityAdjustableAction` is also set: swipe up = +15,
  swipe down = -15, so the bar behaves like a slider.)
- The buttons are `accessibilityHidden(true)` for VO; they stay for Voice Control with their visible names via
  `accessibilityInputLabels(["Minus 15", "Plus 15", "Skip"])`.
- Rest over: one element "Rest over. Next: Bench press, set 1 of 4", hint "Dismisses the banner" (unchanged).
- Reading order: header (clock, menu, Finish) -> rest bar -> (Offline) -> exercise cards. `accessibilitySortPriority`
  not needed as the bar precedes the list in the tree.
- Announcement when the rest ends while VO is on: handled by the existing `heavy` haptic plus the finished bar being
  the focus-visible element; no extra spoken announcement (the user is mid-exercise).

---

## 7. State inventory

| State | Trigger | Rest bar | Cards | Menu / sheets | Toast |
| --- | --- | --- | --- | --- | --- |
| Not resting | idle | hidden; list starts under header | normal | all menu items | per action |
| Resting | `rest.phase == .running` | compact bar | current set highlighted | same | above pad/bottom |
| Rest over | `.finished` | filled "Rest over" bar | same | same | |
| Superset | `supersetGroup != nil` | "Next: <partner> . set 2 of 3" | partner's set highlighted, no collapse until both done | Replace keeps the group; menu shows "Remove from superset" | |
| One exercise done | last working set checked in order | next set named | that card collapsed after 0.6 s; list jumps | | |
| Out-of-order check | checked set 4 while 2 open | unchanged | no collapse, no jump | | |
| Manual scroll < 3 s / pad open | | unchanged | no jump (silent) | | |
| All done | no open set | hidden (or "Rest over" until dismissed) | all collapsed; prompt at the bottom | | |
| Plan session | from a plan day | | | Also-change-the-plan row visible | plan sentence |
| Free session | no plan | | | row absent | |
| Replace, no done sets | | | in place, no split note | note hidden | "Replaced with X" |
| Replace, done sets | | | old stays, new inserted after | split note | split sentence |
| Offline | `!sync.isOnline` | unchanged | no "Last time" for the new exercise | caption; plan change queued | |
| Reduce Motion | system | no ring/numeric animation | collapse and scroll without animation | | opacity only |
| AX sizes | `>= .accessibility1` | stacked / pill | two-line collapsed row | steppers stack | up to 3 lines |

Every state has a reason; the only silent no-op is "no auto-scroll while the user is scrolling", which is the
intended behaviour (brief) and needs no copy.

---

## 8. New user-facing strings

(Existing strings are not repeated: "Plate calculator", "History", "Remove exercise", "Superset with next", "Skip",
"Rest over", "Add set".) German = du-form; items marked * are given in the brief.

| Key (en) | de |
| --- | --- |
| Replace exercise... * | Übung ersetzen... |
| Edit targets... * | Ziele bearbeiten... |
| Notes | Notizen |
| Replace %@ (sheet title) | %@ ersetzen |
| Similar | Ähnlich |
| All exercises | Alle Übungen |
| Your %lld done sets stay as %@. | Deine %lld erledigten Sätze bleiben bei %@. (1: "Dein erledigter Satz bleibt bei %@.") |
| The new exercise continues with %lld sets. | Die neue Übung geht mit %lld Sätzen weiter. (1: "... mit 1 Satz weiter.") |
| %@ continues with %lld sets. | %@ geht mit %lld Sätzen weiter. |
| Also change the plan * | Auch im Plan ändern |
| Applies from the next %@ day. | Gilt ab dem nächsten %@-Tag. |
| Applies from the next %@ day. Saved when you're back online. | Gilt ab dem nächsten %@-Tag. Wird gespeichert, sobald du wieder online bist. |
| Offline. Showing your saved exercise library. | Offline. Das ist deine gespeicherte Übungsbibliothek. |
| Replaced with %@ | Durch %@ ersetzt |
| Replaced with %@. Changed in your plan from the next %@ day. | Durch %@ ersetzt. Im Plan ab dem nächsten %@-Tag geändert. |
| Undo | Rückgängig |
| Replaced with %@. Undo available. (VO) | Durch %@ ersetzt. Rückgängig möglich. |
| Restored %@. (VO) | %@ wiederhergestellt. |
| Edit targets (sheet title) | Ziele bearbeiten |
| Sets | Sätze |
| Reps from / to | Wiederholungen von / bis |
| Target weight (%@) | Zielgewicht (%@) |
| Rest | Pause |
| Clear | Entfernen |
| %lld sets are done and stay. | %lld Sätze sind erledigt und bleiben. |
| Sets with values can't be removed here. Delete them in the list. | Sätze mit Werten kannst du hier nicht entfernen. Lösche sie in der Liste. |
| Changes apply to this workout only. To change your plan, use Replace or the plan editor. | Änderungen gelten nur für dieses Training. Um deinen Plan zu ändern, nutze Ersetzen oder den Plan-Editor. |
| %@, completed. %lld sets, best %@. (VO, collapsed row) | %@, erledigt. %lld Sätze, Bestwert %@. |
| %lld sets . best %@ | %lld Sätze . Bestwert %@ |
| best %lld reps | Bestwert %lld Wdh. |
| Expands the sets | Zeigt die Sätze |
| Next set. (VO prefix) | Nächster Satz. |
| All sets done | Alle Sätze erledigt |
| %lld exercises . %lld sets | %lld Übungen . %lld Sätze |
| Finish workout (button; exists as dialog title) | Training beenden (match the existing de) |
| All sets done. Finish workout available at the bottom. (VO) | Alle Sätze erledigt. Training beenden findest du unten. |
| Rest timer; %lld seconds left. Next: %@. (VO; existing) | Pausentimer; noch %lld Sekunden. Als Nächstes: %@. |
| Jump to next exercise (Profile -> Training) * | Zur nächsten Übung springen |
| Jumps to the next set when you finish an exercise. (footer) | Springt zum nächsten Satz, wenn du eine Übung abschließt. |
| -15 / +15 | -15 / +15 (no change; true minus U+2212) |

Notes for the localization-editor: use plural variations for sets/exercises; "Skip" in the compact bar stays
"Überspringen" in the existing de (scale-to-fit stays on).

---

## 9. Previews and screenshots the PR must show

- `UndoToast`: dark, light, AX3 (token-only primitive).
- Rest bar: running, finished, XL, AX3 (pill), dark and light; pinned over a list, with and without the number pad.
- Collapsed row: default, AX3, dark/light.
- Replace sheet: free session, plan session with split note and toggle on; Edit targets sheet default and AX3.
- Rest-card decision: bar-only (A, chosen) vs card-at-top (B), side by side, light/dark, XL.

## Open questions for the lead
1. Rest card: confirm "drop the large card" (A). B is spec'd above only for the PR comparison.
2. Toast duration under VoiceOver: spec stays visible 10 s (5 s for sighted). Acceptable, or must it be 5 s everywhere?
3. Similar is muscle + equipment only (no movement pattern in the API). Do we file `movement_pattern` in
   `API_REQUESTS.md` now (C1), or wait to see if beta users miss it?
4. "Plan change on Undo after the server saved it": D2 must decide (second update vs. only session undo). The copy here
   assumes Undo reverts both.
