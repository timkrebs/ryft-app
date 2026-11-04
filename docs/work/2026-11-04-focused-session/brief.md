# RYFT iOS — the focused session screen: one exercise at a time, one active set, the rest pill — brief for `ios-lead`

> Copy note: a redacted copy of `CLAUDE_FOLLOWUP_FOCUSED_SESSION.md`. This repo is public. The original quoted real
> training data (day name, date, loads); those are replaced with synthetic values, and the third-party reference
> screenshots are not committed.

Run: `claude --agent ios-lead` → "Run `CLAUDE_FOLLOWUP_FOCUSED_SESSION.md`". Owners: **ui-designer** (the screen, its design
note, every "designer decides"), **ios-developer** (views), **ios-architect** (`SessionController` changes: active set,
page order, superset order), **accessibility-reviewer**, **test-engineer**, **localization-editor**; reviewers per fleet.
Reference screenshots: another app's in-workout screen, local only and not in this repo (for the *structure*, never
for its assets, names or copy). Five PRs, in order.

This brief **supersedes §2 (jump to the next exercise) and §3 (pinned rest bar) of `CLAUDE_FOLLOWUP_BETA_FEEDBACK_2.md`**
if that brief hasn't landed; §1 (Replace / Edit targets) still applies and gets its entry points here. The orbit gauge
brief is unaffected.

## What the reference does well (the analysis, so the designer builds the same *effect*, not the same pixels)

1. **One exercise per screen.** The whole screen is the exercise you are doing. A horizontal strip at the top shows every
   exercise of the session as a tile: done ones dimmed with a ✓ badge, the current one full, upcoming ones dimmed. Tap
   a tile to jump. Orientation without scrolling.
2. **Exactly one active set.** Its `#`, kg and reps are raised white fields; a big green ✓ sits on its row. Done sets
   show a grey ✓; upcoming sets are plain grey text, **already filled with the suggested numbers** (plan target or last
   time). Logging a set that went as planned is one tap. Checking a set makes the next one active (screenshot 1 → 2).
3. **Progress is visible per set.** A fourth column shows the set's estimated 10RM (`75 × 10 → 75`, `80 × 6 → 72`): the
   same formula, so a heavier set and a lighter one compare directly. The column header is editable (which RM, or RPE).
4. **Warm-ups are folded away.** "2 warm-up sets" is one pill above the table; the table holds working sets only.
5. **Last time is a table, not a sentence.** "Tue 3 Nov · Upper" with the same four columns under the current table,
   so the eye compares row by row. RYFT today shows "Last time: 75 × 10, 80 × 6 …" in one line.
6. **The rest timer is a pill, not a card.** Idle: a small white pill with a timer glyph. Running: a green pill with
   `1:54`, pinned at the bottom, always visible, taking one line. RYFT's rest card currently takes a third of the
   screen and scrolls away.
7. **Everything editable is marked.** `Barbell ⇄` (swap the variant), `6 reps ✎` (edit the target), `KG ✎` (unit),
   `# 🔧` (set count). No hunting in menus for the common edits.

RYFT keeps what it already does better: the elapsed session time in the header, the plate calculator, the history
sheet, supersets with the bracket, per-exercise rest, the custom number pad with the kg → reps → next-set flow, the
offline notice, Live Activity, haptics, keep-awake, and the confirmation before anything destructive.

Read first: `Features/Train/Session/{SessionView,SessionController,ExerciseCard,RestTimerView,AddExerciseSheet}.swift`
(`SetRow`, `NumberPad`, `SetFocus`, `nextUp`/`nextLabel()`, `startRest`, `toggleCheck`, `ghost(for:in:)`, `lastTime`),
`Train/TrainMath.swift` (Epley e1RM exists), `Train/Model/LocalSession.swift`, `Train/SessionFactory.swift`, the Live
Activity (`RestTimerAttributes`), `Design/Theme.swift`, `docs/CHART_STYLE.md`, and `CLAUDE_FOLLOWUP_BETA_FEEDBACK_2.md` §1.

## PR 1 · `train: focused session layout (paged exercises, exercise strip)`

**Structure.** `SessionView` becomes:

```
header      elapsed time · session title · (…) session menu · Finish            (unchanged)
strip       ExerciseStrip: one tile per exercise, + tile at the end                 (new)
pages       TabView(.page) or a paging ScrollView, one ExercisePage per exercise   (new; replaces exerciseList)
pad         NumberPad when a field is focused                                       (unchanged)
rest pill   RestPill, pinned above the home indicator                               (PR 3)
```

**ExerciseStrip.** Tiles 56 × 56 pt, 8 pt apart, horizontally scrolling, the current tile scrolled into view. A tile shows
the exercise's **glyph and a 2-line short name** (RYFT has no exercise photos; use the muscle-group symbol set the app
already has for the library, on a `Theme.surfaceRaised` tile; designer decides whether a short name under the tile reads
at 56 pt or the name goes into a tooltip-style label on the current tile only). States: done = 60 % opacity + a small
teal ✓ badge bottom-right; current = full, 2 pt teal ring; upcoming = 60 % opacity. Supersets: the partner tiles are
joined by the existing bracket colour as a thin bar under them. Tap = jump to that page (no change to any set). Long
press = the existing reorder sheet. The `+` tile opens `AddExerciseSheet` and jumps to the new exercise. VoiceOver: the
strip is one adjustable element ("Exercise 2 of 6, Incline bench press, in progress"); swipe up/down moves, double-tap
jumps.

**ExercisePage** (per exercise, scrollable vertically if needed):

1. **Title row:** exercise name as a button (opens the history sheet, as today's "History"), the `…` menu (today's items
   plus Replace / Edit targets from BETA_FEEDBACK_2 §1 when that lands).
2. **Chip row:** `Barbell ⇄` (opens the replace sheet filtered to the same movement with other equipment; until §1
   exists, opens `AddExerciseSheet` in replace mode is out of scope, so the chip is display-only with the equipment
   name), `10 reps ✎` (edit the rep target for this session; existing target fields), `Rest 1:15 ✎` (the existing rest
   submenu as a sheet).
3. **Warm-up pill:** "2 warm-up sets" when the exercise has warm-up sets; tap expands them above the table (their rows
   show `W` as today); collapsed by default once all are checked. "Add warm-up set" lives inside the expanded group.
4. **Set table:** header `#` · `KG` · `REPS` · `E1RM` · (✓ column has no header). The fourth column is the set's Epley
   estimate from `TrainMath` for done sets and for the suggested numbers of upcoming sets (grey); header tap switches
   between `E1RM`, `10RM` (Epley back-solved to 10 reps), and `RPE` (today's field), persisted per user. Rows: see PR 2.
   `+ Add set` under the table (today's).
5. **Last time card:** "Tue 3 Nov · Upper" (date, the session's title) and a four-column table of that session's working
   sets for this exercise (`exercise.lastTime`, which already holds the sets), same column choice as above. Hidden when
   empty. Tap → the history sheet.
6. The offline notice moves under the header as a one-line banner (unchanged text).

`SessionController` gains `pageIndex` (the current page, persisted on the session so a relaunch returns to it) and
`jump(to:)`. Nothing about sets, rest or sync changes in this PR; `ExerciseCard` stays in the codebase until PR 2 removes
it. The **list layout stays available** under Profile → Training → Session layout: Focused (default) / List, for one beta
cycle; remove it after the next feedback round if nobody asks for it.

## PR 2 · `train: one active set, prefilled upcoming sets, auto-advance`

- **Active set.** `SessionController.activeSet` = the first unchecked working set of the current page (warm-ups first
  while they're expanded and unchecked). Its row: `#` in a raised white pill with a small teal dot, kg and reps as raised
  white fields (tap → `NumberPad` as today, `SetFocus`), the ✓ button filled teal, 56 pt. Done rows: grey ✓ glyph, values
  in `textSecondary`. Upcoming rows: ghost values rendered as **real-looking grey text**, not placeholders, so the user
  reads them as "what you'll do"; tapping an upcoming row makes it active (out-of-order logging stays possible).
- **Checking the active set** fills empty kg/reps from the ghost (today's `toggleCheck` does this), starts the rest
  (today's `startRest`), and makes the next set active. The number pad closes if open.
- **Last set of the exercise checked:** after 600 ms (let the check animation and the haptic land), the page advances to
  the next exercise with unchecked sets (superset: the partner, as `nextUp` already decides); the strip tile gets its ✓.
  Not if the user swiped or tapped the strip in the last 3 s, not if the number pad is open, not with Reduce Motion
  (then an instant page change), and never past Finish: when every set is done, stay, and show "All sets done" with a
  Finish button in the page's footer (same flow as the header's Finish).
- Unchecking a done set makes it active again. Setting `pageIndex` by hand never changes any set.
- Setting: Profile → Training → "Advance to the next exercise" (default on).
- Remove `ExerciseCard` and the list's scroll-to-focus code once the list layout is gone (not in this PR; the List layout
  still uses them).

## PR 3 · `train: the rest pill replaces the rest card`

- `RestPill` pinned at the bottom (above the number pad when it's up, else above the home indicator): idle = `Theme.
  surface` pill, 56 pt high, a timer glyph; running = `Theme.accent` pill with `m:ss` in the monospaced display font, the
  remaining ring as a thin stroke inside the glyph. Tap idle → a sheet: "Start rest 1:15" (the exercise's rest), −15 s /
  +15 s presets, and "Change this exercise's rest". Tap running → the same sheet with −15 s / +15 s / Skip and the "Next:
  Bench press · set 2 of 4" line (today's `nextLabel()`).
- `RestTimerView` (the card) is removed from the focused layout; it stays in the List layout until that goes. The Live
  Activity and the rest-end haptic are untouched.
- When the rest ends while the pill is visible, the pill flashes once (`Theme.Motion.quick`) and returns to idle;
  Reduce Motion: no flash, the text changes.
- VoiceOver: the pill is a button, value "Rest, 1 minute 54 seconds left, next Bench press set 2 of 4".

## PR 4 · `train: last-time table and the RM column`

Only if the designer splits it out of PR 1 for size; otherwise part of PR 1. Pin the Epley back-solve for `10RM` in
`TrainMath` with tests (`80 × 6 → e1RM 96 → 10RM 72`, `75 × 10 → e1RM 100 → 10RM 75`), and a rule for
bodyweight sets (added load only; a bodyweight set with no load shows `—`).

## PR 5 · `train: focused session polish` (designer's list after a device run)

Dynamic Type XL/AX3 (the table stays four columns to AX2, drops the RM column at AX3+), landscape (strip hidden, pages
side by side with the pad), the `…` menu order, haptics on page change (none; only on check and rest end), empty session
(no exercises → the page is "Add your first exercise" with the `+` tile), one exercise (strip still shown), 12+ exercises
(strip scrolls, the current tile centred).

## Tests (`test-engineer`)

- `SessionController`: `activeSet` after each check; auto-advance to the next exercise and to the superset partner;
  no advance when the user navigated within 3 s (injectable clock); no advance past the last exercise; `pageIndex`
  persists across a controller rebuild; unchecking reactivates; tapping an upcoming set activates it without changing
  others; warm-ups expanded/collapsed don't change which set is active.
- `TrainMath`: e1RM and 10RM for the reference's numbers; bodyweight rule.
- Snapshots: ExercisePage in the three row states, warm-up pill collapsed/expanded, last-time card, the strip with
  done/current/upcoming/superset, the pill idle/running; light/dark; XL and AX3.
- UISmoke: start the demo plan → check all four sets of the first exercise via the ✓ → assert the strip shows the
  first tile done and the second page is on screen → the pill is running → Skip → Finish. Replace the existing
  session smoke step with this one.

## Ship

PR names as the headings. Strings en + de ("2 warm-up sets" / "2 Aufwärmsätze", "Last time" / "Letztes Mal",
"Advance to the next exercise" / "Zur nächsten Übung wechseln", "All sets done" / "Alle Sätze geschafft"). Design note
`docs/work/2026-11-04-focused-session/design.md` with the analysis above, the geometry, the state table, screenshots per
state, and what was rejected. Update `docs/TESTFLIGHT_NOTES.md` ("The workout screen shows one exercise at a time with
the next set ready to check; the rest timer is the pill at the bottom") and the UI test plan.

Done when an Upper A session from the demo plan can be logged start to finish with only ✓ taps and the rest pill, the
strip always shows where you are, nothing from the list layout's feature set is missing (plates, history, rest per
exercise, supersets, warm-ups, reorder, add, remove, offline), and VoiceOver can do the same session.

Needs-you: a device run with your real plan and feedback on tile legibility without photos; whether RYFT should get an
exercise image set later (it would need your own or licensed photos; nothing from other apps).
