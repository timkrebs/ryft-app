# Nocturne PR 6, area B — Train, My Day and the Journal (T6B.1)

Status: spec and draft renders for the user's approval (L28). Nothing here is built. Owner: ui-designer. Inputs: `brief.md`,
`plan.md` (L27–L30), `design.md` (PR 1–4: tokens, `CircleButton`, `PillButton`, `GlowTile`, `DotNumeral`, `RulerScale`, `DotRow`, `TickRow`,
P2-8 form tokens, the PR 4 conventions), `audit.md`, `docs/work/2026-11-04-focused-session/` (`design.md`, `voiceover-checklist.md`),
#115's AX layouts, and the PR 5 board numbers (Strain, Insights, Profile). The other PR 5/6 designers work in parallel; where this spec
needs something they may also define, it is in §2 "Shared primitives requested" and marked "to reconcile".

Conventions as in PR 4: boards and renders are 390 × 844; content is 350 pt (20 pt sides) except the live workout (§4: 16 pt sides, 358 pt,
because the set table's columns are pinned to it); "ink" is `Theme.textPrimary`; ink alphas map to tokens as in P4 (0.62 = `textSecondary`,
0.55 and 0.45 = `textTertiary` 48 %, but on a row's value text the board's 0.55 is written `textPrimary.opacity(0.55)` and passes 4.5:1 on `surface`
at 15 pt, see §1.6). Gaps are from the bottom of the element above. Layout constants are `nonisolated static let`s on a `…Layout` type
so tests assert numbers (P2-D9). Draft renders: `the lead's session scratchpad, `pr6-drafts/b/` (not in the repo)`.

## 0. Scope

### 0.1 Covered (the ticket's list)

| # | Screen | Code today | Render |
|---|---|---|---|
| 1 | Start workout sheet | `TrainSection.swift` `StartWorkoutSheet` | `b-01` |
| 2 | Live workout, List layout | `SessionView.swift`, `ExerciseCard.swift` | `b-02`, `b-03` (AX3) |
| 3 | Live workout, Focused layout | `FocusedSessionView`, `ExercisePage`, `ExerciseStrip`, `SetRow`, `LastTimeCard` | `b-04`, `b-05` (AX3), `b-06` (keypad), `b-08` (all done) |
| 4 | Rest pill, rest sheet, List's rest bar | `RestPill`, `RestSheet`, `RestBar` | `b-04` (pill), `b-07` |
| 5 | Keypad and plate calculator | `RestTimerView.swift` (`NumberPad`, `PlateCalculatorSheet`) | `b-06` |
| 6 | Finish: confirmation, all-done card, summary | `SessionView`, `AllSetsDoneCard`, `SessionSummarySheet` | `b-08`, `b-09` |
| 7 | Plans, plan detail, plan builder | `PlansView.swift`, `PlanBuilderView.swift` | `b-10`, `b-25` (paused), `b-11`, `b-12` |
| 8 | History, session detail, exercise page | `TrainHistoryView.swift`, `ExerciseDetailView.swift` | `b-13`, `b-14`, `b-15` |
| 9 | Workout Live Activity (look only) | `RyftWidgets/RyftWidgets.swift` | `b-16` (a replica: the system draws the real one) |
| 10 | My Day on Today, My Day full screen | `MyDayCard.swift`, `MyDayView.swift`, `MyDayRow.swift`, `DateStrip.swift` | `b-17`, `b-18`, `b-26` |
| 11 | Add activity, sport picker, Add sleep, activity detail | `Features/Activities/*` | `b-19`, `b-20`, `b-21` |
| 12 | Journal sheet and Today's Journal card | `JournalViews.swift` | `b-22`, `b-17` |

### 0.2 Found beyond the list (all specified below)

| Screen | Why it is in |
|---|---|
| **Add exercise / Replace sheet**, custom exercise form (`AddExerciseSheet.swift`) | Opened from the live workout (the `+` tile, "Add exercise", the Replace chip). `b-24` |
| **Edit targets**, **Exercise notes**, **Reorder**, **Plate calculator** sheets | Opened from the live workout; all carry teal toggles/steppers/buttons today |
| **Undo toast** and the session's notice (`SessionToastOverlay`, `UndoToast`) | In the live workout |
| **Collapsed exercise row** (List) and **Superset bracket** | In the List layout; teal check and bracket |
| **Today's Train card** (`TrainTodayCard`) and **Strain's Train section** (`TrainSection`, `TrainLinkRow`) with the **resume banner** (`WorkoutInProgressBanner`) | Entry points to every screen above. Strain's screen is PR 5's: this spec gives the components, PR 5 places them. `b-17`, `b-23` |
| **Splits table** and the **pace chart** in `ActivityDetailView` | Teal bars (`SplitsTable`: fastest split) |
| **Sport picker** (`SportPicker.swift`) | Part of Add activity |
| **Confirmation dialogs** (Finish, Discard, Delete activity, Delete sleep entry, Remove exercise, Delete set) | System dialogs: not restyled, copy and roles listed in §6 |
| **`StrainPill`, `LoadChip`, `PRBadge`, `MetricTile`** usage in Train | Teal and sage tints; restyled once in `TrainComponents.swift` |
| **Date strip** (`DateStrip`, shared by My Day and Strain) and **`JournalDateStrip`** | Old rings, teal selection |
| **CSV import entry rows in Plans** (`ImportResumeRow`, `ImportWaitingFileRow`) | They sit on Plans; the import flow itself (`Features/Train/Import/*`, 20 files) is **area C's** ("CSV import"). Plans only hosts the rows: it restyles nothing inside them and keeps their slot |

### 0.3 Not in this spec

The Profile "Session layout" picker (area C, Profile subpages). Strain's own screen, tab bar, Workout detail (PR 5). The import flow (area C). The
Tonight card and Sleep sheets (area C). The `train.focused_session` flag is a remote-config change, not code: the user wants Focused on for the beta,
which is `/v1/config` and the platform's; the app already follows it (`SessionLayout.effective(flagOn:stored:)`, stored default Focused). **List stays**
as the flag-off fallback and the Profile choice, so both layouts are specified and both ship Nocturne.

## 1. Grammar for area B (what every screen below inherits)

### 1.1 Colour roles: what teal, sage, amber and red become (L27)

| Role | Today | Nocturne |
|---|---|---|
| Primary action | filled teal capsule (`TealButtonStyle`, `PrimaryButton`) | `PillButton(.primary)`, 52 high, light fill, dark icon circle. In headers and rows too small for 52: `PillButton` `.compact` (§2) |
| Secondary action | tinted teal capsule | `PillButton(.secondary)` (outline). Compact in headers |
| Links, text buttons ("Add set", "Plates", "Show all") | teal text | `textPrimary` text (78 % for quiet ones such as "Add set"); a 1 pt underline at ink 35 % where the word alone could pass for a label |
| Toggles, checkmarks, stepper glyphs, icon tints | teal | `textPrimary`. Toggle: see `RyftToggleStyle` in §2 |
| The selected chip / segment | teal fill | ink fill with `background` text (the Insights board's segmented control) |
| The active set, the running rest (the marked things) | teal | **Volt, as small marks only**: the active row's 5 pt dot and 2 pt leading bar; the running rest's progress ring. Never a fill, never text |
| Training metrics (strain, load, e1RM, volume) | teal / sage | Strain family: **blue in marks** (ruler zone, tick rows, the e1RM line, the glow tile, delta text); **numbers stay ink**. Muscular load is no longer sage (`accentSecondary` leaves Train): `LoadChip` is ink text with a dumbbell glyph |
| Sleep | teal icon | `metricSleep` violet glyph (My Day's sleep row), the legend |
| Warm-up "W", PR trophy | `warning` amber | `textSecondary` "W" (the letter is the cue already); trophy glyph ink in a 36 pt outline circle. Amber stays a band colour |
| Destructive | `alert` red text / fill | **Proposed (shared, to reconcile with T5.0):** outline pill with `alert` text and a 1 pt `alert` at 40 % border; inline "Delete" rows `alert` text. Confirmation dialogs are the system's |
| Busy | `ProgressView` in the button | **Proposed (shared, to reconcile with T5.0):** the pill keeps its fill, the title changes to the gerund ("Saving…", "Finishing…") and the icon circle holds a 14 pt `ProgressView` in place of the arrow. No blocking spinner anywhere |
| Offline / pending / error text | secondary text with icons | unchanged: calm text on the screen, never a banner colour; the icon is ink at 62 % |

The brief's Volt list (§1) names five marks; the user's L27 adds "the active set" and "the running rest" for Train. Both are small marks and are the
only Volt on the live workout. **A rest running while a set is active therefore shows two Volt marks** (the row's dot and the pill's ring); question Q1.

### 1.2 Headers

| Kind | Used by | Spec |
|---|---|---|
| **Pushed** | Plans, plan detail, History, session detail, exercise page, My Day, activity detail | `ScreenHeader` three slots (as Sleep and PR 5's Workout detail): `CircleButton` back · centre title `callout` (15) with, 2 below, a subtitle `caption` (12) `textTertiary` · trailing `CircleButton` or empty. 40 high. `toolbar(.hidden, for: .navigationBar)`; the system back gesture stays. The title carries the header trait |
| **Sheet** | Start, rest, summary excepted, plan builder, Add activity, Add sleep, Add exercise, Journal, edit targets, notes, reorder, plate calculator | New `SheetHeader` (§2): leading `CircleButton("xmark")` (VoiceOver "Close", or "Cancel" when it discards), centre title `callout`, trailing either a `CircleButton("xmark")`-free empty slot, a `CircleButton` (a menu), or a **compact primary pill** for the commit ("Save", "Add", "Done"). 40 high, 20 pt sides, 14 below the grabber. The system toolbar (the glass "Cancel" / "Save" capsules, teal) is not used |
| **Live workout** | both layouts | §4.1 |

A commit pill is `disabled` at 35 % while the form is invalid (the existing rule); its VoiceOver hint says why when it can ("Choose an end after the start").

### 1.3 Lists and forms

Grouped card: `surface`, radius 22, rows min 46 (56 when a row holds a stepper or two chips), hairline ink 6 % between rows, values at ink 55 %, group titles
13 pt at ink 55 %, 18 between groups, 8 between a title and its card. Chips in a row (`DValueChip`): `surfaceRaised`, capsule, 36 high, `callout` `textPrimary`
(they pass: `textPrimary` on `surfaceRaised` is 11.6:1). Steppers: `CircleButton("minus")`, value `ryftNumber` 22, `CircleButton("plus")`: no tinted discs.
Fields: a `surface` card, radius 22, label `label` 13 `textSecondary` above, value `ryftNumber` 22 Light below, placeholder `textTertiary`.
Neutral tiles: 80 high, radius 22, label 13 at 0.62 top-left, value 24 Light bottom-left with a 12 pt unit at `textTertiary` (the PR 5 tile).
Activity rows: the Strain board's (60 high, radius 20, 36 pt circle with a 1 pt ink 16 % border and a 16 pt glyph, title 15, meta 12 at 0.55, value 20 Light right,
chevron 12 pt at 0.35); they grow with their content and with type.

### 1.4 Numbers first

A screen that is about a number leads with it: `DotNumeral` for the one hero number (strain on the summary and on session detail, e1RM on the exercise page,
duration on activity detail), the ruler where a range exists (strain 0–21, target 10–14), then the sentence. The hero numeral obeys L19 (Profile's "Hero numbers":
Dots or Thin) and falls back to Light digits from AX1, like Sleep's. Live-workout numbers are `ryftNumber` Light, fixed sizes (as today: a 56 pt row must not change width).

### 1.5 Honest states, as everywhere

No spinner blocks anything. Loading = outline rows (1 pt `separator`, the row's size) with "–" values; an empty list says why and what to do; pending strain is an unlit numeral
and a ruler without a needle; offline is a line of text ("Offline — every set is saved on this phone and syncs later."); sync pending is "Saved on this phone. Will sync when you're back online."
(`WillSyncNote`, ink 62 %, `icloud.and.arrow.up` glyph).

### 1.6 Contrast numbers used below (sRGB composites, `background` `#0A0C0B`, `surface` `#121514`)

`textPrimary` 17.35 / 16.24; `textSecondary` (62 %) 6.95 / 6.78; ink 55 % (`#F2F1EC`@55) about 5.6 on `surface`: passes 4.5 for text at every size used; `textTertiary` (48 %) 4.54 / 4.54, so
**no `textTertiary` text on `surfaceRaised`** (3.94, PR 1 T4). `surfaceRaised` `#2F312F` fields carry `textPrimary` or `textSecondary` only. Volt marks 17.1:1 on `background`;
strain blue marks 5.94 / 5.56. A filled ink check (`background` glyph on `textPrimary`) is 17.35:1.

## 2. Shared primitives requested

Everything else on every screen below is built from the PR 2–4 components and `ScreenHeader`. These are the gaps. "T6B.0" is the first ticket (§9); a primitive
another PR 5/6 designer also asks for is marked "to reconcile": whoever's ticket starts first builds it, the others import it, and the names and numbers here
are the proposal. Draft renders use throwaway copies named `D…` (test-only, not committed).

| # | Primitive (file) | Proposal | Used by in area B | Status |
|---|---|---|---|---|
| S1 | **`PillButton` `.compact`** (`Design/PillButton.swift`, additive `size:` parameter) | 40 high visual in a 44 pt box (as `CircleButton`), content width, no icon circle, `Font.ryft(.button)`, 18 pt sides. Primary: `textPrimary` fill, `background` text. Secondary: 1 pt ink 20 % outline, `textPrimary` text. Disabled 35 % like the full pill. Never wraps: one line, `fixedSize`, and where it sits beside other header items the caller caps its type at `.xxLarge` (the live workout's Finish does today) and adds `accessibilityShowsLargeContentViewer` | Finish (live header), sheet commit ("Save", "Add", "Done"), Resume, "Start Day A" in a card is the full pill | T6B.0; to reconcile with T5.0 and areas A/C (auth and Profile sheets need the same) |
| S2 | **`PillButton` destructive** and **busy** (same file) | `.secondary` with `alert` title and a 1 pt `alert` at 40 % border (a `role:` parameter). Busy: title becomes the caller's gerund, the icon circle holds a 14 pt `ProgressView` tinted `background`, the pill keeps its fill and stays enabled-looking but ignores taps | Delete activity, Delete sleep entry, Finish workout, Save | **shared, to reconcile with T5.0** |
| S3 | **`SheetHeader`** (`Design/SheetHeader.swift`) | §1.2: `ScreenHeader` three-slot with a leading `CircleButton("xmark")`, centre title (`callout`, header trait), trailing slot: empty, a `CircleButton`, or a compact primary pill. `onClose` is the caller's (a sheet that discards confirms first) | 11 sheets | T6B.0; to reconcile with areas A/C (every sheet and form) |
| S4 | **Grouped list** (`Design/GroupedList.swift`): `GroupedCard`, `GroupRow`, `GroupTitle`, `Hairline` | §1.3 numbers: radius 22, rows min 46, hairline ink 6 %, value at 0.55, titles 13 at 0.55. `GroupRow` takes title, optional value, `chevron`, `trailing` view; one accessibility element per row | Plan builder, Add activity, Add sleep, Journal, exercise page | to reconcile: PR 5's Profile list is the same component |
| S5 | **`NeutralTile`** (restyle of `MetricTile`) | The PR 5 tile: 80 high, radius 22, label 13 at 0.62, value 24 Light bottom-left, unit 12 `textTertiary`, optional note. Drops the icon and tint | Summary, session detail, activity detail | to reconcile with PR 5 (Workout detail's tiles are the same) |
| S6 | **`ActivityRow`** (Strain board row) | As §1.3. Extensions area B needs: a second meta line of **source badges**, a **state mark** slot (`ActivityStateMark`), a **dashed outline variant** (missing night), a value caption ("load"), and `style: .card` without its own surface (My Day's card does not nest surfaces) | History, Plans, My Day (card and screen), Train entry rows | PR 5 builds the base for Strain; **T6B.5 owns the extensions**; `MyDayRow` becomes a thin adapter |
| S7 | **`RyftToggleStyle`** | On: `textPrimary` track, `background` thumb; off: `surfaceRaised` track, ink 62 % thumb; 51 × 31, thumb 25; no animation under Reduce Motion. Applied once through `.toggleStyle` in the app root so every `Toggle` follows | Plan builder, Journal | **T5.0** (L27 names toggles); drawn here as `DToggle` |
| S8 | **`RyftStepper`** (`− value +`) | Two `CircleButton`s (`minus`, `plus`) around a `ryftNumber` 22 value (min 28 wide); the value is an `accessibilityAdjustableAction`; repeat on hold as `TargetStepper` does today. Replaces `TargetStepper`'s tinted discs and the system `Stepper` | Plan builder, edit targets, Journal drinks | T6B.0; reconcile with area C (Profile steppers) |
| S9 | **`FormField` and `ValueChip`** | Field: §1.3. Chip: capsule on `surfaceRaised`, 36 high; a `DatePicker` is shown through it (`compact` style, the system sheet it opens is dark) | Add activity, Add sleep, plan builder, Journal | T6B.0; reconcile with areas A/C |
| S10 | **`Card` radius and padding** (`Design/Card.swift`) | `cardRadius` 18 → 22 (`neutralTileRadius`), `cardPadding` 18 → 16, once, so Today's cards, the summary and every `Card` follow. `tileRadius` 16 callers (rows) move to the activity row | Everything on `Card` | T5.0 / PR 5 (central); area B does not edit `Card.swift` |
| S11 | **`DateStrip` Nocturne** (`Design/DateStrip.swift`) | §8.4: strain-blue 2.5 pt ring (track ink 7 %), selected day on `surface` radius 16, a Volt 4 pt dot under today. `JournalDateStrip` adopts the chip look (§10) | My Day; Strain if PR 5 keeps a strip | T6B.5 |
| S12 | **Outline placeholder rows** | Loading and "–" state = a 1 pt `separator` outline in the row's own size (Sleep's pattern in PR 4 §P4-5) as `PlaceholderRow(height:)` | History, Plans, session detail, My Day | T6B.0; reuse Sleep's if it is already a component |

Not requested: no new colour, no new type role (the live workout's numerals stay `ryftNumber`), no new `GlowTile.Kind` (Plans uses the existing `radius: .hero` initialiser at 176 high;
if PR 5 adds `.hero`, switch to it).

## 3. Entry points and the start sheet

**What the eye sees:** one light pill, "Start workout" (or the resume banner while a session runs), then three quiet rows.

### 3.1 Train section (Strain, PR 5 places it) — `b-23`

`TrainSection` is the group "Train" (title 13 at 0.55, 10 below) with 12 between items:
1. **Not running:** `PillButton(.primary, "Start workout", systemImage: "play.fill")`, id `train.start`. **Running:** the resume banner (below), id `train.resume`.
2. `ActivityRow` "Today's plan: Upper A" · "5 exercises · ~55 min", glyph `calendar`, chevron (only when a plan day exists).
3. `ActivityRow` "My plans" · "Upper/Lower 4× · week 6", glyph `list.bullet.rectangle`, id `train.plans`. 4. `ActivityRow` "History" · "Last: Upper A · Fri, Nov 13", glyph `clock.arrow.circlepath`.
The plan and history links keep their destinations (`TrainRoute`); PR 5's Strain screen only places the group. `TrainLinkRow` is replaced by `ActivityRow`.

**Resume banner** (`WorkoutInProgressBanner`, also on Today): 68 high, radius 22, `surface`, 1 pt ink 20 % border (the one outlined row: it is the live thing). An 8 pt `textPrimary` dot that
pulses 1 s (`opacity` 1 → 0.35; none under Reduce Motion), title "Workout in progress" 15, meta "Upper A · 23 min · 6 sets done" 12 at 0.55 (minutes update every 30 s; the title no longer carries the time, so it stays on one line beside "Resume" at 390 pt), trailing compact primary "Resume".
One element for VoiceOver: "Workout in progress. Upper A, 23 minutes, 6 sets done." with the action "Resume" and hint "Opens the workout". Not Volt: Strain's screen already has its needle.

### 3.2 Today's Train card (`TrainTodayCard`, on Today below My Day) — `b-17`

`Card` (radius 22): header row "Train" 13 at 0.62 with `dumbbell.fill` 13 pt at 0.62 trailing; then (plan today) "Today: Upper A · 5 exercises · ~55 min" `callout`, and `PillButton(.primary, "Start strength workout", play.fill)`, id `today.train.start`.
No plan: "Quick start", **"Empty workout"** primary and **"Repeat last"** secondary side by side (each 52 high; at AX1 they stack), the last session line under them (`caption`, `textTertiary`).
Done today: `checkmark.seal` 20 pt in `textPrimary`, "Upper A" label, "Done · load 84.6 · 2 PRs" `callout` (tabular), the will-sync note when pending. In progress: the banner above.

### 3.3 Start sheet — `b-01`

`SheetHeader("Start workout")` (close at leading, nothing trailing). Detents `[.medium, .large]` as today; the render is the medium one. Options 12 apart, 20 pt sides, 8 below the header:

| Option | Look |
|---|---|
| **From today's plan** (only with a plan day) | The prominent option: `textPrimary` fill, radius 22, min 68; a 40 pt `background` circle holding the glyph, title `headline` in `background`, detail `caption` in `background` at 62 %, a trailing 40 pt `background` circle with `arrow.right`. It is the primary action in the grammar of `PillButton(.primary)` at card size. id `train.start.today` |
| **Repeat last session** | `surface` row, radius 22, min 68: 36 pt outline circle glyph, title `headline`, detail `caption` at 0.55 (up to 2 lines; all lines from AX1, the #115 fix stays) |
| **A day from <plan>** | same row; trailing `chevron.down`/`up` at 0.35. Expands inline: day rows 56 high, `surface` at 60 %, 24 pt inset, "Week 6 · Upper A" and "5 · ~55 min" at 0.55 |
| **Empty session** | same row, glyph `plus`. id `train.start.empty` |

States: loading the options (`loadStartOptions`): the rows that depend on it ("Repeat last", "A day from") show as outline rows with "–", never a spinner; no plan: the first option is absent
and "Empty session" is the first row (it takes the prominent look so the sheet always has one primary); offline: all four work (start is local), the footer says nothing. Starting while a session runs:
the sheet is not offered (the banner is). VoiceOver: the sheet title, then options in order, each one element "From today's plan, Upper A, 5 exercises, about 55 minutes", hint "Starts the workout". Large type: `.large` detent, rows grow, nothing truncates.

## 4. The live workout (both layouts)

**What the eye sees first** (unchanged from the Focused design, now in ink and one Volt mark): the active set's ✓ (the only filled ink square on the page), then the strip (where am I), then the rest
pill. Numbers first: the kg and reps, then the column header, then the sentence. Layout constants are on `SessionLayout` (new, `nonisolated static`); the geometry that the existing tests pin
(`SetTableColumns` widths 36 / flex / flex / 56 / 56, gap 6; 28 / … / 48 / 56, gap 4 at 320; row 56, 64 at AX3; strip 76, tile 56 / 64; pill 48 / 56; page fade 16) **does not change**: only inks, fills, radii of
cards and the header's buttons do. Page sides stay **16 pt (358 content), 12 at 320** (D6B-2).

### 4.1 Header, shared by both layouts — `b-04`, `b-02`

One row, padding 14 + the circle's 2 pt overhang = the circle's edge on the 16 pt inset, 6 above and below (56 high; was 64):
`CircleButton("chevron.down", icon 16, "Minimise", hint "The workout keeps running")` · the middle: session title `callout` 15 `textSecondary` over the clock `ryftNumber` 30 Light `textPrimary` (one element, "Upper A, elapsed time", updates each second) ·
`CircleButton("ellipsis", 16, "More")` (Reorder exercises, Discard workout) · **Finish**: `PillButton` `.compact`, secondary (outline) until every set is done, then primary; id `session.finish`. 8 between items.
The three buttons are 40 / 44 pt (were 48): D6B-3. Finish is one line at every size: `lineLimit(1)`, `fixedSize`, type capped at `.xxLarge` (`.large` at 320), `accessibilityShowsLargeContentViewer` (kept from #115).
Busy (`isFinishing`): the title reads "Finishing…" with no spinner and the pill ignores taps; failure to finish keeps the session open and says so in the toast ("Couldn't finish. Your sets are saved on this phone.") with the action "Try again".
At **320 pt**: padding 12, gap 6, clock 26 pt (`minimumScaleFactor` 0.8), the compact pill's side padding 14; the middle column is then about 108 pt (the hour clock needs about 100).
**AX layouts (#115, kept):** Focused keeps the one row with the title capped at `.accessibility1` at 320 and Finish capped (render `b-05`); **List stacks**: row 1 minimise, spacer, More, Finish; row 2 the title above the clock, centred (render `b-03`); VoiceOver
order stays minimise, title and clock, More, Finish (sort priorities as today). Offline banner under the header: one line, `wifi.slash` 12 pt + "Offline — every set is saved on this phone and syncs later." `caption` `textSecondary`, 28 high.

### 4.2 Focused page, top to bottom — `b-04` (390), `b-05` (AX3)

| # | Element | Spec |
|---|---|---|
| 1 | **Strip** (76) | Tiles 56 × 56 (64 at AX3, strip 84), radius 14, fill `surface`, 1 pt ink 10 % edge. Glyph 20 pt (`ExerciseKind.tileSymbol`) in a 22 box over the position number (`ryftNumber` 11). **Upcoming:** `textSecondary` content. **Current:** 2 pt `textPrimary` ring, `textPrimary` content. **Done:** `textSecondary` content and a 16 pt `textPrimary` badge with a 9 pt bold `background` check, offset (4, 4). **Superset:** a 3 pt capsule in ink 55 % under the group. **Add (+):** dashed 1 pt ink 16 % outline, glyph `textSecondary`. State is the ring, the number's brightness and the badge: never colour. Gap 8; current scrolls to the centre (250 ms, instant under Reduce Motion) |
| 2 | **Title row** (44) | Exercise name `headline` 17 Medium `textPrimary` + `chevron.right` 11 `textTertiary` (it opens the history sheet); trailing `…` menu 44 × 44, `textSecondary`. Wraps to 2 lines at 320 and at XL+. Unchanged type: the name is a row title, not a screen title (D6B-4) |
| 3 | **Chip row** (44) | Capsule `surface`, 1 pt ink 12 % edge, `callout` `textPrimary`, 12 pt glyph `textTertiary`, 32 visual / 44 touch: equipment, target ("4 × 8 @ 62.5 kg" + `pencil`), rest ("Rest 2:30" + `pencil`). Scrolls horizontally with a 16 pt fade; **stacked, full width, 44 high from AX1**. Never filled: the check must stay the only filled thing |
| 4 | **Notes line** (44) | `note.text` 13 + the note `caption` `textSecondary`, one line |
| 5 | **Warm-up pill** (when any) | Capsule 36 (44 touch) `surface`, 1 pt edge; `flame` 12 pt in `textSecondary` (was amber); "2 warm-up sets" `callout` `textSecondary`; `chevron.down` 11 `textTertiary`. Expanded group: "W" in `textSecondary`, "Add warm-up set" text button in `textPrimary` at 78 % |
| 6 | **Table header** (24) | `#`, `kg`, `Reps`, and the fourth ("E1RM", "10RM", "RPE") with its dotted underline in `textTertiary`; labels 13 `textTertiary`, hidden from VoiceOver except the fourth (a button) |
| 7 | **Set rows** (56 / 64, 4 apart) | §4.3 |
| 8 | **Add set** (48) | `plus` 14 + "Add set" `callout`, `textPrimary` at 78 %, centred |
| 9 | **All-done card** (when every set of the session is done) | `Card` (radius 22, padding 16): "All sets done" `headline` + "5 exercises · 17 sets" `caption` `textSecondary`, 12 below `PillButton(.primary, "Finish workout", systemImage: "checkmark")`, id `session.allDone.finish`. The header's Finish turns primary at the same moment: two primaries on the page at that point, intended (render `b-08`); the rest pill row is gone |
| 10 | **Last-time card** | `Card` padding 14: "Last time · Tue, Nov 10" `label` `textTertiary`; header row; rows 36 high, `ryftNumber` 17 `textSecondary`, the same columns. One button → history |
| 11 | **Rest pill row** | §4.5 |

The 16 pt top fade (`background` → clear) stays. Everything below the strip scrolls; the strip, header and pill row do not.

### 4.3 Row states (replaces design.md §2.5 and §2.8 inks; same geometry)

| State | `#` | kg / reps | Fourth column | ✓ (56 × row) | Row |
|---|---|---|---|---|---|
| **Active** (the first open set, or the one tapped) | `textPrimary` in a 32 pt `surfaceRaised` circle with a **5 pt Volt dot** top-right | on `surfaceRaised` (radius 12, row − 8 high), `textPrimary` (a ghost or "–" in `textSecondary`: `textTertiary` on `surfaceRaised` is 3.94) | `textSecondary`; an RPE field at 55 % raised | **`textPrimary` fill, `background` glyph** (20 pt bold), radius 14 | tint `textPrimary` at 5 %, radius 14, and a **2 pt Volt bar** at the leading edge, 10 pt outside the row, row − 16 high |
| **Done** | `textSecondary` | `textSecondary`, no chrome | `textSecondary` | glyph `textSecondary`, no fill | none |
| **Upcoming with a ghost** | `textSecondary` | ghost in `textSecondary` | `textSecondary` | 1 pt `surfaceRaised` outline, glyph `textTertiary` | none |
| **Upcoming with a typed value** | `textSecondary` | `textPrimary` | as typed | as upcoming | none |
| **Warm-up** | "W" in `textSecondary` | as the state | | | |
| **Unchecked after done** | derived as before: never stored | | | | |
| **Empty, no history** | | "–" `textTertiary` | | | |

The active row's non-colour cues are unchanged: raised fields, the filled ✓, the bar and the dot. Contrast: ✓ glyph 17.35:1; active values 11.6:1 on `surfaceRaised`; a ghost on it 5.5:1 (`textSecondary`);
done and upcoming grey 6.95:1 on `background`; the upcoming outline is a graphic at 1.5:1 beside a glyph that carries the meaning (as today). `FocusedRowInk` changes values, not structure. Check haptics and the 0.6 s auto-advance are unchanged.

### 4.4 AX3 (Focused) — `b-05`

Unchanged rules from design.md §5.1 and #115: the fourth column goes at AX3 (RPE becomes a line of its row), numerals 30, rows 64, tiles and strip 64 / 84, chips stack, the pill is 56 with a 30 pt clock, Finish capped, the title above the
clock in the middle column. What changes is only look. **Check at AX3 that Finish and the set table stay reachable:** Finish is in the header, never inside the scrolling page; the table scrolls under the pinned strip; the keypad
open hides the strip below 138 pt of page (as built). The all-done card's pill grows to 3 lines without clipping (`PillButton` P2-D6).

### 4.5 Rest pill and sheet — `b-04`, `b-07`

**Pill** (Focused only; 8 above and below, 48 high, 56 at AX3): **idle** capsule `surface`, 1 pt ink 12 % edge, `timer` 18 `textSecondary` + the exercise's rest `ryftNumber` 20 `textPrimary`, min 112. **Running**: the same capsule with a 1 pt
ink 20 % edge, min 144: a 24 pt ring (3 pt, track ink 16 %, **progress Volt**, round cap) and the remaining time `ryftNumber` 24 Light `textPrimary` (`numericText` counting down; identity under Reduce Motion). **Over** (1 s): "Rest over" `headline` on an ink 12 % fill, then idle; no flash under Reduce Motion
(the text alone changes). It is no longer the only filled pill; running is told from idle by the ring, the live number and the wider capsule, and VoiceOver by its value ("1 minute 54 seconds left. Next: …"). VoiceOver, actions (Skip, adjust ±15 s, open the sheet) unchanged.

**Rest sheet** (`RestSheetFrame`, detents 426 pt / large; large only from XL): `SheetHeader("Rest")` with a trailing `CircleButton("xmark", "Done")`. 20 pt sides, 16 between: the clock `ryftNumber` 56 Light; two keys "−15 s" and "+15 s" (56 high, 64 at AX3, radius 14, 1 pt ink 20 %
outline, `ryftNumber` 17 `textPrimary`; disabled `textTertiary` outline at 10 %); the primary `PillButton` ("Start rest 3:00" with `play.fill`, or while running "Skip rest" with `forward.end`); the "Next: Bench press · set 2 of 4 · 5 × 80 kg"
line `caption` `textSecondary`, centred; when idle and changed, "Set as rest for this exercise" as an underlined text button (44 high, `textPrimary`). The rest-length chooser (chip sheet) is rows 56 high with a trailing `checkmark` in `textPrimary` on the current one.

**List's `RestBar`** (pinned under the header, `session.restBar`): running = `surface`, radius 22 (was 16), 1 pt ink 20 % edge (was teal 35 %), a 36 pt ring (4 pt; Volt progress, track ink 16 %) and the time `ryftNumber` 28, the Next line `caption`, and three compact secondary pills "−15 s", "+15 s", "Skip" (one per line where the line can't hold them). From AX1 the bar is always the pill form, the capsule with ring, time and "Skip"; a tap on it opens the rest sheet, which has −15 s and +15 s (lead decision after the PR 6 ui-validator's S8: at AX3 the stacked buttons took 42 % of the screen). Over: "Rest over" with a "Dismiss" compact secondary.

### 4.6 Keypad and plate calculator — `b-06`

Container `surface`, 1 pt ink 8 % top edge, padding 14 / 12 / 14 / 8. Header: the field title `label` `textSecondary` over "Barbell row · set 2" `caption` `textSecondary`; the value `ryftNumber` 30 Light (`textTertiary` while empty); **Plates** = `circle.grid.cross` + "Plates" `callout` in `textPrimary`, 44 high (barbell kg only).
Keys 56 high, radius 14, 8 apart: digits on `surfaceRaised`, `ryftNumber` 26 `textPrimary`; **±2.5 / ±1 / ±0.5** as outlined keys (1 pt ink 20 %, `ryftNumber` 19 `textPrimary`; was teal tint); Next and Delete on `surfaceRaised` with 20 pt glyphs; **Done = `textPrimary` fill, `background` "Done" `headline`** (was teal). Text caps at `.xxLarge` at 320 as built.
`PlateCalculatorSheet` (today a rainbow: red, blue, amber, teal, sage plates): `SheetHeader("Plate calculator")` with a trailing close; the target `ryftNumber` 48 Light between two outlined step keys "−2.5" / "+2.5" (72 × 56, radius 14, 1 pt ink 20 %, `textPrimary`; were teal capsules); "kg target" `label`; the bar drawn as today (bar ends `textTertiary`, collar `textSecondary`) with **every plate `textPrimary`**, told apart by height as now and by its weight label in `background` (the colour per weight carried nothing the label and height did not); a `GroupedCard` of rows Each side, Bar, Loaded (a `Loaded` total that differs from the target is `textPrimary` with the sentence "102.5 kg can't be loaded with 2.5–25 kg plates; this is the closest below." `caption` `textSecondary`: no amber); "Use 100 kg" `PillButton(.primary)` pinned when opened from the keypad. VoiceOver unchanged ("Plates per side", the list of plates).

### 4.7 List layout — `b-02`, `b-03`

`ExerciseCard`: `Card` radius 22, padding 14. Header: name `headline`; target `callout` **`textSecondary`** (was teal); "Last time: 80 × 5, …" `caption` `textTertiary`; the notes line; `…` 44 × 44. Column titles `Set | kg | Reps | RPE` as today (one line, capped at `.xxxLarge`).
Rows are 56 high with List's own columns (40 / flex / flex / ≤ 64 / 56); they use **the three Focused states** (§4.3) with two List-only rules: upcoming rows' kg, reps and RPE fields stay raised at 55 % (List has no pager to read as a table; done rows have no chrome, as in Focused), and the **active row is the controller's current set** (`CurrentSetHighlight`: the Volt bar and dot, the ✓ filled ink).
No "all green" wall of filled checks: done sets are grey checks. "Add set" `callout` `textPrimary` at 78 %. `CollapsedExerciseRow`: radius 22, `checkmark.circle` 20 pt `textSecondary` (was a filled teal), name `headline`, summary `callout` `textSecondary`, `chevron.down` `textTertiary`.
`SupersetBracket`: the bracket stroke 3 pt `textPrimary` at 55 %, the label "Superset" 13 `textSecondary` with `link`. "Add exercise" `PillButton(.secondary)`; "Reorder exercises" a text button `textSecondary`, 44 high. **Finish in List** follows Focused (outline until all done): D6B-5, question Q2.
AX3 (`b-03`): the header stacks (§4.1), column titles stay one line, the card's rows are 64 and the numerals 30 (as #115).

### 4.8 Sheets and small views opened from the session

| View | Nocturne |
|---|---|
| **Add exercise / Replace** (`b-24`) | `SheetHeader("Add exercise" / "Replace Bench press")`, search field (`surface` capsule 46 high, `magnifyingglass` `textTertiary`), filter chips (`FilterChip`: 34 high; selected = ink fill + `background` text, others 1 pt ink 16 % outline; "All muscles" first), "Similar" / "All exercises" `GroupTitle`s, rows 56 in a `GroupedCard` with the name `callout`, "Barbell · Chest" `caption` at 0.55 and a trailing `plus` 14 pt at 0.62; "Custom exercise" a text row (46) with `plus`. The "Also change the plan" toggle is a `GroupRow` with `RyftToggleStyle`. Offline: "Offline. Showing your saved exercise library." `caption` above the list |
| **Custom exercise form** | `SheetHeader("Custom exercise", commit "Add")`, `FormField` name, three `GroupRow` pickers (Kind, Main muscle, Logged as) as menus with the value at 0.55 |
| **Edit targets** | `SheetHeader("Edit targets", commit "Done")`; a `GroupedCard` of `RyftStepper` rows (Sets, Reps from, Reps to, Target weight with "Clear" as a trailing text button, Rest); footer `caption` "Changes apply to this workout only. To change your plan, use Replace exercise or the plan editor." |
| **Notes** | `SheetHeader("Notes", commit "Save")`, a `FormField`-style multi-line card |
| **Reorder** | `SheetHeader("Reorder", commit "Done")`, `List` in edit mode on `surface` rows 56 high, a superset shows `link` at `textSecondary` (was teal) |
| **Undo toast / notice** | `surfaceRaised` capsule-ish card, radius 22, `callout` `textPrimary`, "Undo" a text button `textPrimary` with a 1 pt underline at 35 %; 8 above the rest pill row |
| **Confirmation dialogs** | System. Copy unchanged: "Finish workout?" / "5 sets checked off. Empty rows are dropped." (button "Finish workout"); "Discard this workout?" / "All 17 logged sets are deleted. This can't be undone." (destructive "Discard workout"); "Remove Bench press?" / "Its sets in this workout are deleted."; "Delete set" |

### 4.9 States of the live workout

| State | Trigger | Look and words |
|---|---|---|
| In progress | a session exists | §4.1–4.7 |
| Empty session | no exercises | An outlined card (1 pt `separator`, radius 22): "An empty session. Add your first exercise." with the `+` tile (Focused) or "Add exercise" (List) |
| Paused (backgrounded) | `scenePhase == .background` | Internal: the clock stops, nothing is shown. On return the clock resumes; the header does not say "paused" (it never did) |
| Offline | no connection | The one-line banner (§4.1); every set is saved locally |
| Sync pending | a finished session waits | Summary and Today's card: `WillSyncNote` "Saved on this phone. Will sync when you're back online." |
| Finishing | `isFinishing` | Finish reads "Finishing…" |
| Error | finish or upload fails | A toast with "Try again"; the details (request ID) behind the toast's "Details" (existing rule); never "log in again" unless `401` final |
| Loading last time / ghosts | not ready | Fields show "–" in `textTertiary`; no spinner |
| Rest running / over / idle | §4.5 | |
| All done | every set checked | §4.2 row 9 |
| Superset | `supersetGroup` | the bar in the strip, the "Superset with Cable row" line `caption` `textSecondary` with `link` under the title |

### 4.10 Accessibility, live workout

VoiceOver reading order is design.md §5.2 **unchanged** (header, offline, strip as one adjustable element, title, superset line, chips, notes, warm-up pill, table, add set, all-done card, last-time card, toast, rest pill, keypad), with these
additions: the Volt dot, the Volt bar and the ring are `accessibilityHidden` (the row says "next set"; the pill says its value); header traits: the exercise title and "All sets done" keep `isHeader`; every `CircleButton` has a label and, where it
opens something, the hint "Opens a sheet"; the compact Finish pill is a `Button` labelled "Finish" with identifier `session.finish`. Focus rules after a check, an auto-advance, the last set and the keypad are unchanged (`voiceover-checklist.md` stays the device checklist; add one line:
"Finish is reachable from the header at AX3 without scrolling the page"). Large content viewer: Finish, the header circles, the strip's tiles, the pill. Reduce Motion: page changes instant, strip scroll instant, ring still draws but jumps (no easing), the pulsing banner dot is static, the "Rest over"
state has no flash, `numericText` becomes identity (as built). Reduce Transparency: nothing here uses a glow tile on the live workout. Dynamic Type: §4.4 and design.md §5.1; the strip, rows, keypad and pill use fixed numerals as today.

## 5. Finish and the summary

**Finish** is a system confirmation dialog from the header (or the all-done card): copy and roles in §4.8. It does not change.

### 5.1 Workout summary (`SessionSummarySheet`) — `b-09`

A full-height sheet, `interactiveDismissDisabled` as today. **What the eye sees:** the strain numeral, then the four neutral tiles, then Done. Top to bottom, 20 pt sides:

| # | Element | Spec |
|---|---|---|
| 1 | Header (40) | No buttons. Centre: the session title `callout` and, 2 below, "Workout done · Wed, Nov 18" `caption` `textTertiary` (header trait on the pair). With records: "2 new records · Upper A" |
| 2 | Hero | 22 below: `DotNumeral("10.7", glyphGap: 7)`, label 12 below "Strain · of 21 · moderate" `label` `textSecondary`, 14 below `RulerScale(0…21, zone target 10–14, .strain, ticks 64, labels "0" "target 10–14" "21")` with its Volt needle. Light digits from AX1 and with L19's "Thin" |
| 3 | Tiles | 26 below the ruler: 2 × 2 `NeutralTile`s, 12 apart: **Duration** "52 min", **Volume** "7,500 kg", **Muscular load** "85.0", **Sets** "17" (was Duration, Volume, Load, Strain; strain moved to the hero). Stack to one column from AX1 |
| 4 | Records card (when any) | `Card`: "Personal records" `label`; rows 52: a 36 pt outline circle with `trophy` 14 pt ink, the exercise `callout`, the kind `caption` `textSecondary` ("Est. 1RM", "Most reps"), the value `ryftNumber` 20 right ("93.5 kg") (`PRBadge` restyled: no amber) |
| 5 | Heart-rate line | `caption`-sized `Label` with `heart` in `textSecondary`: "Heart rate from Garmin Connect", or "No heart rate yet. With a strength workout on your watch too, it arrives once the watch syncs." |
| 6 | Apple Health ask (once, after the first workout) | `Card`: "Save workouts to Apple Health?" `headline`, the existing sentence `callout` `textSecondary`, then two compact pills side by side: primary "Save", secondary "Not now" (stack from AX1); the write-access hint stays below. Not in the render (it shows once) |
| 7 | Notes | `Card` with a multi-line field, placeholder "How did it feel?" `textTertiary`; editing never moves the Done pill |
| 8 | Done | `PillButton(.primary, "Done", systemImage: "checkmark")` pinned in a bottom inset on `background` with a 24 pt fade above it; 20 sides, 16 above the home indicator. The content scrolls under it |

**States.** *Strain scored:* as above. *Strain pending* (the platform's answer is not there: offline, or not scored yet): the numeral is unlit (`placeholder "0.0"`), the ruler has no needle, the label says "Strain · arrives once your workout is scored", and `WillSyncNote` shows
when `pendingCompletion`. Honest: the phone computes no strain. *No heart rate:* numeral unlit, label "Strain · no heart rate for this workout", the heart-rate line says why. *Done offline:* tiles from the local session (volume, sets, duration), "–" for load. *No records:* the card is absent.
**No celebration motion**: the bouncing seal, the scale-in and the success haptic of today go; one `.success` haptic stays (it is not motion); Reduce Motion needs no variant. The title no longer says "Workout done" 26 pt (the header does).
VoiceOver order: header, the numeral ("Strain 10.7 of 21", from `DotNumeral`'s label), the ruler sentence, the four tiles (each one element "Duration, 52 minutes"), records, heart-rate line, notes, Done. Focus lands on the header on appear.
AX3: tiles one column, the numeral Light 52 → about 78 pt, the Done pill grows and stays pinned; the content scrolls above it, never under the keyboard (notes field scrolls into view).

## 6. Plans

### 6.1 Plans list — `b-10`, paused `b-25`

Pushed header "Plans". **What the eye sees:** the active plan as the screen's one glow tile.
1. **Active plan** (when enrolled): `GlowTile(Theme.metricStrain, radius: .hero)`, min 176, radius 28 (the Strain-family glow, a training object). Head row: "Active" `label` glow ink, "Week 6" `caption` right (all in the dark core, ink at the glow label opacity). 8 below: the plan name `title` 26 Light `textPrimary`. 2 below: "Next: Upper A" glow label. 14 below: `PillButton(.secondary, "Pause")`.
   The whole tile except the pill opens the plan (`NavigationLink`); the pill pauses (disabled while `working`, title "Pausing…").
   **Paused:** no glow (an outline is "not now"): the same layout in a 1 pt ink 16 % outline, radius 28, "Paused" `label` `textSecondary` and "since Nov 3" right, "Next: Upper A · week 6 waits", `PillButton(.primary, "Resume", play.fill)`.
2. **Import rows** (area C's, `train.import`): `ImportResumeRow` / `ImportWaitingFileRow` stay in their slot above the active plan, restyled by area C.
3. **Error:** `InlineMessage` (calm line, "Try again", Details) under the active tile.
4. `GroupTitle` "Built-in", then `ActivityRow`s 8 apart (title = plan name, meta "Hypertrophy · 4 days/week · repeating", chevron). The enrolled plan's icon is a filled ink circle with a `background` check (the only filled icon on the screen: "this one").
5. `GroupTitle` "My plans", the rows; then `PillButton(.secondary, "New plan")` (a menu when `train.import` is on: "Start from scratch", "Import from file"). 18 between sections. Bottom padding clears the 76 pt tab bar.
**States:** loading = three outline rows; empty "My plans" = no section and the sentence "Plans you make or copy appear here." under the button; offline = the list from the cache with no banner; error as above. VoiceOver: "Upper/Lower 4×, active, week 6, next Upper A" for the tile; rows "Full Body 3×, Strength, 3 days a week, 12 weeks"; the header trait on the group titles.

### 6.2 Plan detail — `b-11`

Pushed header: the plan name, subtitle "Strength · 3 days/week · 12 weeks". 20 below: the description `callout` `textSecondary`, "Progression · Linear +2.5 kg" `caption` `textTertiary` 6 below. 16 below: `PillButton(.primary, "Switch to this plan")` (an enrolled plan: "Pause plan" secondary and "Active · week 6" label instead), 12 below `PillButton(.secondary, "Copy and edit")` (built-in) or "Edit" (mine) — both 52.
Then day cards, 20 above the first, 12 apart: radius 22 `surface`, rows between hairlines: header "Day A" `headline` + "~55 min" `caption` at 0.55 (min 40); exercise rows `callout` name + `caption` "5 × 5 @ 100 kg · rest 3:00" at 0.55 (no bullets); the first day card ends with `PillButton(.secondary, "Start Day A")`
inside the card (every day card has its own). Superset members show `link` at 0.62 before the name. Delete (mine): an outline destructive pill at the end, with a system confirmation. VoiceOver: each card is a container labelled "Day A, about 55 minutes"; rows "Back squat, 5 sets of 5 at 100 kilograms, rest 3 minutes".

### 6.3 Plan builder (sheet) — `b-12`

`SheetHeader("Edit plan" / "New plan", commit "Save")` (the commit disabled until the name is not empty and each day has an exercise; Cancel with unsaved changes asks "Discard changes?"). Content (20 sides):
`FormField` "Name"; `GroupTitle` "Plan" and a `GroupedCard`: **Goal** (menu row: "Hypertrophy" at 0.55 with a chevron pair), **Days per week** (`RyftStepper`, row 56), **Repeats every week** (`RyftToggleStyle`), **Progression** (menu row; footer `caption` at 0.55 explains the choice: "+2.5 kg after every set is done…").
"Description" a multi-line `FormField`. Then per day: the day name `headline` with `CircleButton("trash", "Delete day")` trailing (a day with exercises confirms), a `GroupedCard` per exercise: name row with a `…` menu (Replace, Superset, Remove), `RyftStepper` rows Sets, Reps from, Reps to, `GroupRow`s Target ("80 kg" or "RPE 8", an inline kind picker), Rest ("3:00", the existing presets as a menu); "Add exercise" a text row with `plus`; "Add day" `PillButton(.secondary)`.
Goal was a segmented control of four wide words that scrolled; it is a menu row (D6B-6). States: validation shows a line `caption` in `textPrimary` under the invalid field ("Give the plan a name.") plus the disabled Save with the hint; saving: "Saving…"; failure: calm `InlineMessage` on top of the sheet with "Try again".
Dynamic Type: rows grow, steppers keep their 40 pt circles and wrap the label above the control from AX1.

## 7. History, session detail, exercise page

### 7.1 History — `b-13`

Pushed header "History", subtitle "8 workouts" (omitted while loading). Per week: `GroupTitle` "Week of Nov 8" with the right text "2 sessions · 12.2 t · load 126" (`caption`, ink 55 %, one `isHeader` element), 10 below the rows. Session rows are `ActivityRow`s: glyph `dumbbell.fill`, title (`Upper A`, or "Workout"), meta "Fri, Nov 13 · 55m · 7,500 kg", value = muscular load `ryftNumber` 20 with "load" `axis` 11 `textTertiary` under it (`LoadChip` is gone from rows; a session without load shows "–"), chevron. Weeks 18 apart, rows 8.
States: loading = three outline rows (was a teal spinner); empty "No workouts logged yet. Finished sessions appear here." as a calm outlined card with `dumbbell`; pull to refresh unchanged; offline cached; "Load" gains the sentence "Muscular load" in VoiceOver ("Upper A, Friday 13 November, 55 minutes, 7,500 kilograms, muscular load 85").

### 7.2 Session detail — `b-14`

Pushed header: the title, subtitle "Fri, Nov 13 · 55 min · 17 sets". Hero as the summary's (numeral, label, ruler: "Strain · of 21 · moderate"), then **Volume** and **Muscular load** `NeutralTile`s (strain is the hero), a notes card when notes exist (`Card`, `callout`), then one `Card` per exercise: name `headline` with a trailing `chevron.right` (opens the exercise page), set rows 34 high: position or "W" `ryftNumber` 14 `textSecondary` (28 wide), "80 kg × 5" `callout`, trailing "RPE 8.5" `caption` `textSecondary`; time and distance sets show "0:45" or "5.0 km".
Strain absent (imported or not yet scored): unlit numeral, "No strain for this workout." States: loading = hero outline and two outline cards; failure "This workout couldn't be loaded. Try again when you're online." with "Try again". VoiceOver: each exercise card is one container with a combined label per set; the chevron's hint "Opens the exercise's history".

### 7.3 Exercise page — `b-15`

Pushed header: the name, subtitle "Barbell · Chest". Hero: `DotNumeral("93.5", glyphGap: 7)`, "Estimated 1RM · kg" `label` `textSecondary`, "▲ 11.6 kg in 90 days" `label` in `metricStrain` (the delta in its metric colour; ▼ and "same" in `textSecondary`: no red). 22 below: the chart card, radius 24 `surface`, padding 16: "Estimated 1RM" `label` at 0.62 and "90 d" `caption` `textTertiary`; value `ryftNumber` 26 + "kg" + the delta `caption` in strain blue; the line chart 150 high:
1.4 pt `metricStrain` round-joined line, a dashed 1 pt ink 30 % rule at the PR with its label "PR 93.5 kg" `axis`, the last point a **Volt** r 3 dot (the "today" mark of a series, L17), y labels `axis` `textTertiary` at the trailing edge, x labels as today. No gradient fill. `E1RMChart` is restyled in place; `MetricSpec.e1rm.color` → `metricStrain`.
Then `GroupTitle` "Personal records" and a `GroupedCard`: rows 56 with the 36 pt outline `trophy` circle, kind `callout`, "Nov 13" `caption` at 0.55, value `ryftNumber` 20 right; the sentence ("Estimated one-rep max 93.5 kg.") moves to VoiceOver. `GroupTitle` "Recent sets" and a `GroupedCard`: rows with the date (`callout` `textSecondary`, 58 wide), the sets (`callout`, wraps), and the best e1RM `callout` right in `textPrimary` (was teal).
States: no trend yet ("Log this exercise a few more times to see a trend." in the chart card, 120 high, `callout` `textSecondary`); no records: the card is absent; no sets: the empty line; loading: outline card. VoiceOver: the chart is one element, "Estimated 1RM over 90 days, from 81.5 to 93.3 kilograms, ending at its highest", with the data table as the chart's audio graph (`ChartAccessibility`, as the other charts).
Reached from the session detail, from the live workout's title and last-time card (as a sheet there: `SheetHeader` with a close, same content).

## 8. The workout Live Activity (look only) — `b-16`

The renders are replicas drawn in SwiftUI: the system draws the real one in `RestTimerLiveActivity` (`RyftWidgets/RyftWidgets.swift`), which was not renderable here. The extension has **no Satoshi** (`WidgetOrbitGauge.swift` says so), so it uses the system font in **Light** for numbers
(`.system(size:, weight: .light)`, tabular) and Regular for text; no rounded design. Colours come from `Brand`: `mist` ink, `graphite` background, and a new **`Brand.signal`** (`#D8FF4F`, the same hex as `Theme.signal`; `check-shared-types.py` keeps both in step). Teal leaves the Live Activity.

| Part | Spec |
|---|---|
| Lock screen card | `activityBackgroundTint` `graphite`, 24 pt corners (the system's), 1 pt ink 10 % edge, padding 16, `widgetURL` unchanged. Row 1: leading a 6 pt Volt dot (**only while resting**) + "Rest" / "Workout" 11 Medium at ink 62 %, under it the session title 12 at 62 % (`privacySensitive`, as today); trailing the clock, 40 pt Light `mist` (counts down while resting, else the elapsed time, as today) |
| Rest progress | 12 below: a 4 pt capsule, track ink 16 %, **fill Volt**, only while resting and not stale (`ProgressView(timerInterval:)` tinted `Brand.signal`) |
| Next line | 12 below: "Next: Bench press · set 2 of 4 · 5 × 80 kg" 15 `mist`, up to **2 lines** (was 1: the line truncates at the set's load), `privacySensitive` (hidden when the user asks iOS to hide sensitive content). Trailing "Open": a 30 high outline capsule (1 pt ink 20 %), 13 Medium `mist`, a `Link` to the deep link |
| Dynamic Island, expanded | Leading: `timer` / `dumbbell.fill` 12 pt + "Rest" / "Workout" 12 Medium, **`mist`** (was teal). Trailing: the clock 28 Light. Bottom: the progress capsule (resting), the Next line 14 (1 line), "Open". Keyline tint: Volt while resting, none otherwise |
| Compact | Leading the glyph in `mist`; trailing the clock 15 Light (max 56 wide). Minimal: the glyph in `mist` |
| Stale | After a rest runs out with the app not running: the clock shows the elapsed time and the progress capsule is gone (as built); no colour change |
| Reduce Motion | The system animates `ProgressView(timerInterval:)`; nothing of ours moves |
| Accessibility | One element per presentation: "Rest, 1 minute 54 seconds left. Next: Bench press, set 2 of 4." The Volt dot is hidden; the state is the word "Rest" |

`RestTimerAttributes` (the shared Codable shape) does not change. Brand colours only; the `RyftWidgets.swift` file is shared with area C's widget ticket (`Brand` is theirs too): the `Brand.signal` line is additive (D6B-11).

## 9. My Day

### 9.1 On Today — `b-17`

PR 4 left "My Day follows below on `surface`, unchanged in content", and it did not restyle it (`MyDayCard.swift` was last touched in #54). So everything below is still to do. The card is `Card` (radius 22, padding 16, S10), 12 below the cards above it:
- **Header** (40): the title block (tap opens the full screen) "My Day" `headline` over "3 activities · 2h 13m · 6.8 mi" `caption` at 0.55; trailing `CircleButton("plus", "Add")` is a `Menu` (Add activity, Add sleep when the night is missing, Start strength workout), shown only if `hasAddEntries`.
- **Rows** (up to five): the activity row in `style: .card` (no surface; 12 vertical padding, hairline ink 6 % between): a 36 pt outline circle with a 16 pt glyph in ink (the sleep row's glyph is `metricSleep`), title `callout`, meta `caption` at 0.55 ("6:40 AM–7:32 AM · 48m · 5.2 mi"), then source badges, then the value: sleep "7:48" + "h", an activity's strain `ryftNumber` 20. Badges: outline capsule 22 high, 1 pt ink 12 %, `axis` 11 `textTertiary`, 8 pt sides ("Apple Health", "Garmin Connect", "Added by you", "RYFT"; the merged pair shows both).
- Under the rows: "Show all" (46, `callout`, chevron at 0.35); `PillButton(.secondary, "Add activity")` (`canAdd`); the stale caption "Showing data from 14:05 · Try again" (`caption` `textSecondary`, "Try again" a text button, 44 high).
- **Row state marks** (`ActivityStateMark`, in the value slot; they go under the text from AX1, with their word): scored = the value over "Strain" in the pending word's `caption` at 0.55 (PR 6 ui-validator: a bare "3.1" didn't say what it was); *uploading* = `arrow.up.circle` 12 + "Uploading" `caption` at 0.55 (no spinner); *strain pending* = "–" in `textTertiary` and "Strain pending" `caption`; *not uploaded* = "Not uploaded" `caption` and a 44 pt-high text button "Retry"; *no heart rate* = "No heart rate" `caption`; none = nothing.
- **States:** loading = three outline rows; nothing today = "Nothing logged yet today." `callout` `textSecondary` and the Add activity pill; missing night = the dashed row of §9.2; offline = the cached rows and the stale line; error = `InlineMessage` with "Try again".
VoiceOver: the card is a container; each row one element as `MyDayRow.spoken` composes it today ("Running, 6:40 AM to 7:32 AM, 48 minutes, 5.2 miles, Strain 10.6, Sources: Garmin Connect and RYFT, merged"); the header's block is a button "My Day, 3 activities, opens the day". Large type: the value and the state mark go under the text (36 pt circle at AX).

### 9.2 Full screen — `b-18`, missing night `b-26`

Pushed header: "My Day" with the subtitle "Today · Wed, Nov 18" (a past day: "Sat, Nov 14", "Yesterday · Tue, Nov 17"), trailing `CircleButton("plus")` menu (Add activity, Add sleep). 8 below: the **date strip** (S11, below). 18 below: the summary line "4 activities · 2h 13m · 6.8 mi" `label` `textSecondary`, trailing "Strain" `axis` `textTertiary` + the day's strain `ryftNumber` 20 (absent when unscored: "Strain –"). 12 below: `ActivityRow`s (tile style, 8 apart, a chevron on rows that open a detail, the value as above, the badges on a second meta line).
**Add activity** = `PillButton(.primary, "Add activity", "plus")` pinned above the tab bar on a 24 pt fade (the last 14 days); on a past day outside the window it is absent. The page scrolls under it with bottom padding 96.
*Missing night* (`b-26`): a dashed-outline row (1 pt ink 12 %, dash 4 4, radius 20, 60 high): a dashed 36 pt circle with `bed.double.fill` in `textTertiary`, "No sleep recorded" `callout` `textSecondary`, trailing "Add sleep" `callout` `textPrimary` underlined (44 high; at AX the word goes under, never broken). The row is `.contain` for VoiceOver ("No sleep recorded" then the "Add sleep" button).
Edit and Delete exist on manual and recorded rows: a long press and the VoiceOver actions "Edit" / "Delete" (as today); Delete asks "Delete this activity?" (system dialog, "Delete" destructive / "Keep"). A day switch cross-fades in 250 ms (instant under Reduce Motion). Pull to refresh unchanged.

**Date strip (S11)** — `DateStrip.swift`, shared with Strain if PR 5 keeps it: seven chips, `maxWidth: .infinity` (50 at 350), 64 high: the weekday initial `caption` (selected `textPrimary`, others `textTertiary`), 6 below a 32 pt ring (stroke 2.5, track `textPrimary` 7 %, arc `metricStrain` round cap from 12 o'clock over strain / 21) holding the whole-number strain `ryftNumber` 11 in ink (unscored: an empty ring and "–"), then a 4 pt dot: **Volt under today**, an outline dot (1 pt ink 35 %) under a day whose score is pending (`DayMarker`). The selected chip has a `surface` fill, radius 16 (was a grey pill). VoiceOver per chip: "Wednesday, Strain 15" + "today" / "selected"; the strip is `.contain`; ids `datestrip.day.<date>` stay. At AX1+ the strip becomes a horizontal scroll with 64 pt chips and the selected one centred.

## 10. Add activity, Add sleep, activity detail

### 10.1 Add activity — `b-19`

`SheetHeader("Add activity", commit "Save")` (the commit is disabled until the form is valid; an edit says "Edit activity"). 20 sides, 12 between blocks, 10 below the header: (1) the **sport row** (`surface`, radius 22, min 60: 36 pt outline glyph circle, name `callout`, `chevron.up.chevron.down` at 0.35; opens the sport picker; locked when editing a recorded one: no chevron, "Measured by RYFT. Times and distance can't be changed." `caption` at 0.55 under the card);
(2) a `GroupedCard`: **Start** and **End** rows (56): the label at 0.62 and two `ValueChip`s (date, time; the system compact pickers behind them); **Duration** "1h 00m" `ryftNumber` 20 right (46; "(next day)" `caption` when the end is on the next day); (3) `FormField` "Distance (optional)" with the unit right ("mi" / "km", the app's setting) and the decimal pad; an `IssueLine` under it when pace is implausible: `exclamationmark.circle` + "That's faster than expected for this sport. Check the distance." `caption` in `textPrimary`;
(4) **Perceived effort (optional)**: a card, `EffortScale` as five circles per row (46 pt, 1 pt ink 16 % outline, `ryftNumber` 17 ink; **selected = `textPrimary` fill, `background` number**; three columns at AX1+); under it, once picked, "7 · Hard" `callout`. The scale keeps its single adjustable VoiceOver element ("Perceived effort, 7 of 10, Hard") with the Clear action. (5) a **Notes** card (multi-line, min 44, placeholder `textTertiary`); (6) the footnote "Strain comes from the heart rate your tracker syncs for this time. Without it, your effort rating is used." `caption` at 0.55 (or, without heart rate for the sport: "Without heart rate there is no strain for this activity.").
**Strength suggestion** (sport Strength): a `Card` under the sport row: "Strength is best logged in Train. Your sets, reps and load count toward muscular load." `callout` `textSecondary`, `PillButton(.secondary, "Log in Train")` and a text button "Add here anyway" (44 high); collapsed afterwards to one line "Strength is best logged in Train." with the same two actions in a menu.
**Sport picker** (`SportPicker`, pushed inside the sheet or presented): pushed header "Sport", a search field (`surface` capsule 46, "Search sports"), `GroupTitle` "Recent" and "All sports", rows 52 in a `GroupedCard` (36 outline circle + glyph, name `callout`, a trailing `checkmark` in ink on the current one); no match: "No sport matches “curling”" `callout` `textSecondary` and `PillButton(.secondary, "Use Other")`.
States: *saving* = the commit reads "Saving…" and ignores taps; *offline* = saves locally with "Saved on this iPhone. It will upload when you're online." in the day (the detail's sync rows, §10.3); *error* = `InlineMessage` on top with "Try again"; *validation* = the commit disabled and its hint ("Choose an end after the start"). Dynamic Type: chips wrap under their label from AX1 (label above, two chips below, full width); Duration stays one line.

### 10.2 Add sleep — `b-20`

`SheetHeader("Add sleep", commit "Save")` (an edit: "Edit sleep"). A medium detent sheet. "For a night no tracker recorded." `callout` `textSecondary`; a `GroupedCard` with **Went to bed** and **Woke up** (label at 0.62 on the left, may wrap to two lines as the system label does; two `ValueChip`s); 14 below: "Time asleep" `label` + "8h 00m" `ryftNumber` 24, and "Time in bed. RYFT can't see your sleep stages for this entry." `caption` `textTertiary`; then "It's marked “added by you”. If your tracker records this night later, RYFT uses the tracker's data instead." `caption` at 0.55. The Apple Health case ("Sleep was already recorded by Apple Health.") is an `InlineMessage` at the top and the form is read-only.
Editing an entry adds "Delete this entry" as the destructive outline pill at the end (confirmation "Delete this sleep entry?" / "Your scores for that night are recalculated."). Same states as §10.1.

### 10.3 Activity detail — `b-21`

Pushed header: the activity name, the subtitle "Tue, Nov 17 · 6:00–6:20 AM", trailing `CircleButton("ellipsis")` (Edit, Delete). **What the eye sees:** the duration numeral, then the strain block.
1. `DotNumeral("0:20", glyphGap: 7)` (h:mm), 20 below the header; "Duration · h:mm" `label` `textSecondary`; the source badge ("Added by you", "Garmin Connect") 8 below.
2. 24 below: two `NeutralTile`s: **Duration** "20 min" and **Effort** "3 / 10" (or **Distance** "5.2 mi", **Pace** and the measured ones when recorded).
3. **Strain block**, 12 below. *Scored* (heart rate present): the Today strain tile, `GlowTile(metricStrain, kind: .strain)` 96 high: "Strain" label, "10.6" `ryftNumber` 30, "of 21 · moderate", a compact `RulerScale` 0–21 (target 10–14) with the needle; "Heart rate from Garmin Connect" `caption` under it. *No heart rate:* an outline card (the render): "Strain" `label`, `minus.circle` + "No heart rate for this time." `callout`, and the reason `caption` `textSecondary` ("From your effort rating. Strain becomes more precise when heart rate arrives."). *Waiting:* "Waiting for heart rate" with the same outline card. *Merged:* the explanatory sentence `caption` `textSecondary` ("Merged from two sources: heart rate from Garmin Connect, route and distance from RYFT. RYFT counts this activity once.").
4. A recorded run adds "Heart rate and zones" as an `ActivityRow` (link to the Workout detail, PR 5), the route map card (`surface`, radius 22, as today; the polyline in ink), and the **splits table** (`SplitsTable`: header `axis` `textTertiary`, rows 40, the bars `metricStrain` at 60 % with the **fastest** split's bar `textPrimary` and the word "Fastest" kept; "Show all 12" a text button).
5. Notes: the note `callout` in a card, or "Add a note" (`square.and.pencil` + `callout`, 52 high, `textPrimary`, id `activity.addNote`).
6. 12 below: `PillButton(.secondary, "Edit")` (when editable) and a destructive outline pill "Delete" (12 apart). A strength activity adds `PillButton(.secondary, "Log this in Train")` under the explanation "Strength is best logged in Train. Your sets, reps and load count toward muscular load."
**Sync states** (the existing `InlineMessage` lines, one at a time, above the numeral, calm `surface` rows with `icloud.and.arrow.up` 14 pt in ink at 0.62): "Saved on this iPhone. Uploading to RYFT." · "…It will upload when you're online." · "…It uploads once your account is ready." · "Your account is being deleted. This activity is deleted with it." · "…RYFT will try again, or tap Retry." (with a "Retry" text button) · "RYFT couldn't accept this activity. It is still saved on this iPhone." (with "Edit") · "Couldn't upload. It is still saved on this iPhone." · gone from this iPhone: "This activity isn't on this iPhone any more." with a back button as the only action; offline cache: "Showing what's saved on this iPhone."
VoiceOver: header, the numeral ("20 minutes"), the tiles (one element each), the strain block (one sentence: "Strain 10.6 of 21, moderate. Heart rate from Garmin Connect"), actions in order. The destructive pill says "Delete activity". Large type: tiles stack, the numeral Light, pills grow.

## 11. The Journal

### 11.1 Today's card — `b-17`

`Card`: a 36 pt outline circle with `list.bullet.clipboard` in ink (was teal), the title "How was yesterday?" `callout` and "A few taps, and RYFT shows how your habits change the morning after." `caption` at 0.55; once answered: "Yesterday" `label` and the summary `callout` ("Alcohol · 2 drinks · Sauna", wraps). Trailing "Answer" / "Edit" `callout` `textPrimary` with a 1 pt underline at ink 35 % (was teal text; it is a text button, 44 high). The whole card is the button; hint "Opens the journal".

### 11.2 The sheet — `b-22`

`SheetHeader(<day title: "Yesterday" | "Mon, Nov 16">, commit "Save")`; the commit reads "Saved" (disabled) after a save and is disabled while the day is read-only, saving, or without behaviours. 20 sides. 8 below the header: the **day strip** (`JournalDateStrip`: a horizontal scroll of chips 48 × 56, radius 16, 8 apart; weekday `caption`, day `ryftNumber` 17; **selected = `textPrimary` fill with `background` text**, others `surface` with ink text; today is not marked: the journal is for past days). 20 below: per category `GroupTitle` ("Substances", "Sleep", "Recovery", "Lifestyle") and a `GroupedCard`; each behaviour a 52 pt row with its name `callout` and `RyftToggleStyle`; an enabled behaviour opens a sub-row (56): **Count** a `RyftStepper` (1–50), **Time** a `ValueChip`. Hairlines between; `allowsHitTesting(false)` and 55 % ink for a read-only day (not `.disabled`, which drew every switch off).
States: *offline* — a one-line outlined pill "Offline. Your answers are saved on this phone." above the groups (`OfflinePill` restyled: 1 pt outline, `wifi.slash` 12, `caption` `textSecondary`); *read-only* — `InlineMessage` with `lock` ("This day can't be changed any more."); *no behaviours chosen* — "Choose behaviors in Profile → Journal." with a `PillButton(.secondary)` link to it (copy question Q5); *loading* — the groups as outline cards; *error* — `InlineMessage` with "Try again"; *saving* — "Saving…". Profile → Journal (behaviour settings, `JournalSettingsView`, `BehaviorsSection`) is area C's.
VoiceOver: the header, the strip (each chip "Monday 16 November", selected), then groups in order, each toggle "Alcohol, switch, on"; a sub-row reads its value ("Drinks, 2", adjustable). The impact bar in `BehaviorsSection` is area C's.

## 12. Motion, accessibility and Dynamic Type across the area

- **Motion:** every transition ≤ 250 ms (`Theme.Motion.quick`), ease-out, no springs. Kept as built: page change slide (instant under Reduce Motion), strip scroll, warm-up chevron, pill cross-fade, `numericText`. Removed: the summary's seal bounce and scale-in (§5.1). New: none. The resume banner's pulse and the rest ring's progress follow Reduce Motion as above. Pushed and sheet transitions are the system's.
- **VoiceOver:** each screen has a header trait on its title (the pushed and sheet headers' centre title, "All sets done", group titles); every icon-only control is a `CircleButton` with a label; decorative glyphs inside rows are hidden; one element per row; values are spoken with units ("62.5 kilograms", "1 minute 54 seconds"). The live workout's order is §4.10; the others read top to bottom as drawn.
- **Dynamic Type to AX3:** numerals in rows are fixed; everything else scales. Rules per screen above. Common ones: activity rows grow (title up to 3 lines at AX, value and mark under the text); `PillButton` wraps; `GroupRow`s with a value stack the value under the title from AX1; steppers and chip pairs wrap under their label; two-up tiles go one column from AX1; sheets open at `.large` from XL; the pinned pills (Done, Add activity, Start) keep 16 pt above the home indicator and the content scrolls above them.
- **Reduce Transparency:** the glow tiles (Plans' active plan, the activity strain tile) draw flat `surface` with the 2 pt metric border (as built).
- **Contrast:** §1.6; Volt is never text; strain blue is never body text (the deltas "▲ 11.6 kg in 90 days" are 5.94:1 on `background` at 13 pt, which passes).

## 13. Strings (English only; the localization-editor finalises)

Existing keys are reused wherever the words stay; only the changed or new ones are listed. `String(localized:)` with the English text as the key; no German (CLAUDE.md: RYFT is English only).

| Where | String |
|---|---|
| Live header | "Finishing…" (Finish while busy); toast "Couldn't finish. Your sets are saved on this phone." with the action "Try again" |
| Resume banner | "Workout in progress"; meta "%@ · %lld min · %lld sets done" (replaces "Workout in progress · %lld min" and "%@ · %lld sets done") |
| Today's Train card | existing ("Today: %@", "Start strength workout", "Quick start", "Empty workout", "Repeat last") |
| Start sheet | existing; no plan: the first row is "Empty session" |
| Summary | "Workout done · %@" (the date); "%lld new records · %@"; "Strain · of 21 · %@" (the band word from the Strain family strings); "Strain · arrives once your workout is scored"; "Strain · no heart rate for this workout"; tile "Sets"; Done, Duration, Volume, Muscular load, Personal records existing. Removed: "Workout done" as a 26 pt title, "%lld new PRs" |
| Plans | "Active", "Paused", "since %@", "Next: %@", "Next: %@ · week %lld waits", "Pausing…", "Plans you make or copy appear here.", "Progression · %@" (plan detail), "Start %@" (day pill), "Delete day", "Add day", "Name", "Plan", "Goal", "Give the plan a name.", "Discard changes?" |
| History | week summary "%lld sessions · %@ · load %@"; subtitle "%lld workouts"; value caption "load"; the VoiceOver row label (see §7.1) |
| Session detail | "Strain · of 21 · %@"; "No strain for this workout."; subtitle "%@ · %lld min · %lld sets" |
| Exercise page | "Estimated 1RM · kg"; "%@ in 90 days" (the delta sentence); "PR %@" existing |
| My Day | "Nothing logged yet today."; "Today · %@" (subtitle); "Strain" (summary axis label), "Strain –"; "Add" (VoiceOver of the plus menu) |
| Add activity / sleep | "Saving…", "Edit activity", "Edit sleep", "Close", "Cancel" (VoiceOver of the sheet's close), "Choose an end after the start" (commit hint) |
| Journal | "Saved", "Offline. Your answers are saved on this phone.", "This day can't be changed any more.", "Count" (stepper row); copy question Q5 ("Choose behaviors in Profile → Journal.") |
| Live Activity | existing ("Rest", "Workout", "Next: %@", "Open") |
| Retry | "Retry" (existing) |

Strings that name another wearable brand: none. Data sources are named factually ("Apple Health", "Garmin Connect").

## 14. Previews and tests

### 14.1 Previews (dark only; AX3 where it changes the layout)

Every changed view keeps or gets `#Preview`s with mock data, dark only: the live workout in both layouts, default and AX3, with keypad, with rest running, all done; the rest sheet; start sheet; summary (scored, pending strain, no heart rate, with and without records); plans (active, paused, empty, loading); plan detail; builder (valid, invalid);
history (populated, empty, loading); session detail (with and without strain); exercise page (trend, no trend, no records); My Day card and screen (gallery rows, missing night, stale, uploading, failed); Add activity (new, strength suggestion, measured, implausible pace); Add sleep; activity detail (recorded with heart rate, manual without, merged, each sync line); Journal (answered, read-only, offline, empty);
the Live Activity previews (`#Preview(as:)`, existing) with the new colours. New primitives get catalog entries in `DebugComponentCatalog` (T6B.0). Each preview is the same file's, so the old light previews of a touched file go (D3).

### 14.2 Tests to write

| Area | Test |
|---|---|
| **Keep (the Focused guarantees)** | `SetTableColumns` widths and rows (`FocusedPolishTests` "table follows §5.1", "quiet RPE line", "width class", "tiles and strip grow at AX3", "−15/+15 at AX3", "320 pt strip with keypad"); `RestPillHostedTests` (pill row 8 / 48 / 8, 112 idle, 144 running, over the keypad); `LargeTextHostedTests` (Finish and the set table reachable at AX3, the List header stacked); the VoiceOver order and identifiers (`session.finish`, `session.restPill`, `session.restBar`, `set.<position>.<n>`, `session.allDone`, `session.allDone.finish`, `train.start`, `train.start.today`, `train.start.empty`, `train.resume`, `train.plans`, `plans.import`, `plans.newPlan`, `summary.done`, `summary.heartRate`, `summary.saveToHealth`, `myday.addSleep`, `myday.confirmDelete`, `datestrip.day.<date>`, `addActivity.start`/`.end`, `addSleep.*`, `activity.addNote`, `profile.jumpToNext`). The UI tests run under either layout |
| **Re-pin (colour maths, each listed in the PR)** | `FocusedPolishTests` 246–292: the estimate on the active row's tint (ink 5 % instead of accent 10 %); the upcoming outline stays `surfaceRaised`; grey on the active field 4.5:1; the warm-up "W" is `textSecondary` on a plain row and on the raised pill (was amber); "an unfilled Finish reads 4.5:1 on its capsule" becomes the label on `background` (17.35) and the outline is the system's 20 % secondary edge; "List's Finish is filled from the start" becomes "outline until every set is done" in both layouts (D6B-5, Q2); `SessionActiveSetTests`/`FocusedRowInViewTests` colours of the ✓ |
| **New: layout constants** | `SessionLayout`: header 56 high, circle 40 in a 44 box, compact pill 40 in 44, strip 76/84, page fade 16, the pill row; the compact pill's hit target ≥ 44; Finish stays one line at every size (hosted) |
| **New: components** | `PillButton.compact` (heights, disabled 35 %, no wrap), destructive and busy looks; `SheetHeader` (slots, header trait, labels); `RyftStepper` (adjustable action, bounds, repeat); `RyftToggleStyle` (contrast of thumb on track ≥ 3:1 in both states); `GroupedList` row min 46; `DateStrip` (arc fraction, today's dot is the only Volt, ids, `.contain`); `EffortScale` (selected is ink-filled and bold, one adjustable element); `PlaceholderRow` |
| **New: colour hygiene** | A lint (`scripts/check-accent-use.py`, in `make lint`) that fails if `Theme.accent`, `TealButtonStyle`, `PrimaryButton`, `Theme.accentSecondary`, `Theme.warning`, `Theme.sage`, `Theme.stageLight` or (outside destructive controls) `Theme.alert` appear in `Features/Train/**` (except `Import/**`, area C's), `Features/MyDay/**`, `Features/Activities/**`, `Features/Journal/JournalViews.swift`, and that `Theme.signal` appears only in the allowed marks (the active row, the rest ring, the date strip's today dot, the ruler needle, the series' last point). `check-shared-types.py` also compares `Brand.signal` with `Theme.signal` |
| **New: screens (hosted)** | Summary: scored, pending strain (unlit numeral, no needle, the will-sync note), no records; History: row value "load", empty and loading are outline rows; Plans: paused has no glow and a Resume pill; Plan builder: Save disabled until valid, discard asks; My Day: missing-night row is `.contain` with "Add sleep" reachable, the pinned Add activity clears the last row at AX3; Add activity: effort three columns at AX1+; Journal: read-only day blocks taps and keeps switches' look; a VoiceOver-tree test of the live header order |
| **Previews as tests** | The existing `FocusedSessionShotsTests` (`make focused-shots`) stays; add `make b-shots` only if the lead wants frozen renders (not a golden-file test) |
| **Live Activity** | `RestTimerAttributes` Codable shape unchanged (existing test); the `#Preview(as:)` states render |

## 15. Files and the split

### 15.1 What each change touches

| Change | Files (all under `Ryft/` unless noted) |
|---|---|
| Shared primitives | `Design/PillButton.swift`, new `Design/SheetHeader.swift`, `Design/GroupedList.swift`, `Design/RyftStepper.swift`, `Design/FormField.swift`, `Design/PlaceholderRow.swift`, `DebugComponentCatalog.swift`; (T5.0: `RyftToggleStyle`, `Card.swift`) |
| File split (mechanical, no behaviour) | `Features/Train/Session/SessionView.swift` → `ReorderSheet.swift`, `SessionSummarySheet.swift`; `ExerciseCard.swift` → `SetRow.swift` (+ `SetTableColumns` stays with it) |
| Live shell: header, Focused, strip, rows, rest pill and sheet, keypad | `SessionView.swift`, `FocusedSessionView.swift`, `ExercisePage.swift`, `ExerciseStrip.swift`, `SetRow.swift`, `FocusedRowInk.swift`, `RestPill.swift`, `RestSheet.swift`, `RestTimerView.swift`, `AllSetsDoneCard.swift`, `SessionToastOverlay.swift`, `Design/UndoToast.swift` |
| List and session sheets | `ExerciseCard.swift`, `CollapsedExerciseRow.swift`, `RestBar.swift`, `AddExerciseSheet.swift`, `EditTargetsSheet.swift`, `ExerciseNotesSheet.swift`, `ReorderSheet.swift`, `ExerciseMenuItems.swift` |
| Entry, start, summary | `Features/Train/TrainSection.swift`, `TrainComponents.swift` (`TrainLinkRow`, banner, `LoadChip`, `PRBadge`, `TealButtonStyle` call sites), `SessionSummarySheet.swift` |
| Plans | `Features/Train/Plans/PlansView.swift`, `PlanBuilderView.swift` |
| History | `Features/Train/History/TrainHistoryView.swift`, `ExerciseDetailView.swift`, `Design/MetricSpec.swift` (`e1rm` colour), `Design/ChartStyle.swift` only if it names the accent |
| My Day | `Features/MyDay/MyDayCard.swift`, `MyDayView.swift`, `MyDayRow.swift`, `Design/DateStrip.swift`, `Design/SourceBadge.swift`, `Design/ActivityStateMark.swift`, `Design/ActivityRow.swift` (the extensions) |
| Activities | `Features/Activities/AddActivitySheet.swift`, `AddSleepSheet.swift`, `SportPicker.swift`, `ActivityDetailView.swift`, `SplitsTable.swift`, `Design/EffortScale.swift` |
| Journal | `Features/Journal/JournalViews.swift` |
| Live Activity | `RyftWidgets/RyftWidgets.swift` (`Brand.signal`, the views), `Shared/` only if the colour is shared |
| Strings | `Resources/Localizable.xcstrings` (single writer) |
| Mocks | `Preview/MockTrain.swift`, `MockActivities.swift`, `MockData.swift`, `FocusedPreview.swift`, `MockJournal.swift` |

### 15.2 Tickets (parallel worktrees)

| Ticket | Owner | Files | Depends on | Parallel-safe with |
|---|---|---|---|---|
| **T6B.0** Shared primitives, file split, mocks | ios-developer | the "Shared primitives", "File split" and "Mocks" rows above; catalog entries for the new primitives | T5.0 (L27: buttons, toggles, `Card`) merged into the PR 6 base; reconcile S1–S4 with areas A/C | none (it goes first; ≈ the shared base for T6B.1–T6B.9) |
| **T6B.1** Live shell (Focused first) | ios-developer | "Live shell" row | T6B.0 | T6B.3–T6B.9 (not T6B.2: `SetRow.swift` is T6B.1's, `ExerciseCard.swift` T6B.2's) |
| **T6B.2** List layout and session sheets | ios-developer | "List and session sheets" row | T6B.0 | T6B.3–T6B.9; T6B.1 once the split has landed |
| **T6B.3** Entry points, start sheet, summary | ios-developer | "Entry, start, summary" row | T6B.0, PR 5's `ActivityRow` base | all others |
| **T6B.4** Plans, plan detail, builder | ios-developer | "Plans" row | T6B.0, `ActivityRow` base | all others |
| **T6B.5** History, session detail, exercise page | ios-developer | "History" row | T6B.0, `ActivityRow` base | all others (`MetricSpec.swift` is touched only here: Insights' e1RM trend card, if PR 5 has one, must follow the same blue) |
| **T6B.6** My Day, date strip, row extensions | ios-developer | "My Day" row | T6B.0, `ActivityRow` base (PR 5) | all others; **T6B.7 shares no file** |
| **T6B.7** Add activity, Add sleep, sport picker, activity detail, splits | ios-developer | "Activities" row | T6B.0 | all others |
| **T6B.8** Journal sheet and card | ios-developer | "Journal" row | T6B.0 | all others (Profile → Journal is area C's) |
| **T6B.9** Live Activity | ios-developer | "Live Activity" row | area C's widget ticket if it also edits `Brand` | all others |
| **T6B.10** Strings | localization-editor | the catalog | T6B.1–T6B.9 | none (after them) |
| **T6B.11** Tests and the accent lint | test-engineer | `RyftTests/`, `scripts/check-accent-use.py`, `Makefile` (`lint`) | each ticket's code (one test ticket per code ticket may run in its worktree) | after its ticket |
| **T6B.12** Validation | ui-validator, code-reviewer | renders against this spec at 390, 320 and AX3 | all | none |

Shared files, assigned: the string catalog → T6B.10 only; `MockTrain` / `MockActivities` / `MockData` / `FocusedPreview` → T6B.0 only (every state a later ticket previews is added there first); `TrainComponents.swift` → T6B.3 only; `DebugComponentCatalog.swift` → T6B.0 only; `Design/ActivityRow.swift` → PR 5 (base) then T6B.6 (extensions); `RyftWidgets.swift` → T6B.9, shared with area C's widget ticket (sequence the two or accept an additive merge).
Order that works: T5.0 → T6B.0 → { T6B.1, T6B.2, T6B.3, T6B.4, T6B.5, T6B.6, T6B.7, T6B.8, T6B.9 } in parallel → T6B.10 → T6B.11 → T6B.12. The `train.focused_session` switch is a remote-config change for the user or the platform, not a ticket here.

## 16. Deviations

| # | From | To | Reason |
|---|---|---|---|
| D6B-1 | Brief §1: Volt for five marks | + the active set (dot and bar) and the running rest (ring) | L27 names them; both are small marks, never a fill or text. Two at once while resting (Q1) |
| D6B-2 | Shared grammar: 20 pt sides, 350 content | The live workout keeps 16 (358), 12 at 320 | The set table's columns, tests and the AX3 rules are pinned to it (`SetTableColumns`, 36/flex/flex/56/56) |
| D6B-3 | #115/design.md: header buttons 48 (44 at 320) | `CircleButton` 40 in a 44 box, compact Finish 40 in 44; header 56 high (was 64) | The shared grammar's circle is 40; the 44 pt touch box is kept; the saved 8 pt go to the page |
| D6B-4 | Titles 26 Light | The exercise name stays `headline` 17 Medium | It is a row title: at 26 a two-line name at 320 costs the fourth visible set row |
| D6B-5 | List's Finish filled from the start | Outline until every set is done, as Focused | One primary at a time; a filled ink pill in the corner of every list session would outweigh the numbers. Changes a pinned test (Q2) |
| D6B-6 | Plan builder: a segmented Goal | A menu row | Four wide words do not fit the segmented control; it scrolled |
| D6B-7 | Summary: a bouncing seal, Strain in a tile | The strain numeral is the hero; no celebration motion | Numbers first; the PR badge list stays |
| D6B-8 | `accentSecondary` (sage) for muscular load, `LoadChip` | Ink text with a dumbbell glyph | "No hue off the legend"; the sage had no meaning beyond "not teal" |
| D6B-9 | Amber warm-up "W" and trophy | `textSecondary` "W", ink trophy in an outline circle | Amber is a band colour (moderate) |
| D6B-10 | Focused design: "running is the only filled pill" | Running is the outline pill with a Volt ring; idle is an outline without it | Fewer fills; the check is the one filled thing (Q3). Widths 112/144 stay |
| D6B-11 | Live Activity: system rounded semibold, teal | System Light, `mist`, Volt only for the rest's dot and bar; the Next line may take 2 lines; `Brand.signal` added | The extension has no Satoshi; the line truncated at the load |
| D6B-12 | Glow tiles for metrics only | Plans' active plan is a strain-glow tile | The plan is a training object and the screen's hero; one glow per section holds (Q7) |
| D6B-13 | System sheet toolbars ("Cancel"/"Save" capsules) | `SheetHeader` (close circle, title, compact commit pill) | L27: no teal; the system capsules cannot be recoloured. Labels and identifiers are kept |
| D6B-14 | e1RM line in the accent (teal) | `metricStrain`, the last point Volt (L17) | Strength progress is a training metric |
| D6B-15 | DateStrip: ring in `metricStrain`, grey selection | Ring 32 / 2.5 pt, `surface` selection, a Volt dot under today | The brief's "today" mark; the Strain board has no strip, so this is area B's to define (S11) |
| D6B-16 | Activity detail: the strain as the hero | The duration is the numeral; strain has its own block | Every activity has a duration; not every one has strain (honest states) |
| D6B-17 | `PrimaryButton` / `TealButtonStyle` | Not used in area B at all; `PillButton` called directly | T5.0 re-skins the old ones centrally, but these screens must not depend on that mapping |
| D6B-18 | Summary's "Workout done" 26 pt title | Header subtitle | The numeral is the title of the screen |
| D6B-19 | §5.1 "Strain · no heart rate for this workout" on the summary | No such state: an answered session always has a strain (muscular load); an unscored one is the pending state (T6B.3 review) | API.md: `Session.strain` comes back with every `/complete` |
| D6B-20 | Paused tile: "since <date>", "week N waits" | "Paused / name / Resume continues where you stopped."; nothing invented (T6B.3) | `GET /v1/plans` returns no paused enrolment; asked in API_REQUESTS (Train #2) |
| D6B-21 | Builder Rest: the session presets only | Presets plus 0, 30, 45, 360, 480, 600, 900 s and the current value (T6B.4, lead) | Nothing the old stepper allowed is lost (supersets, heavy singles) |
| D6B-22 | b-24: muscle chips only | The kinds filter row is kept under the muscles (T6B.2) | Removing it would drop a working filter |
| D6B-23 | §4.7: List set rows 64 high at AX3 ("as #115") | 56 at every size in List, as the base (T6B.2) | #115 applies to Focused; one row-height constant shared with `CurrentSetHighlight` |
| D6B-24 | Edit targets: "Clear" as a trailing button | Its own row, "Clear target weight" (T6B.2) | The shared stepper row has no trailing slot; the visible label equals the spoken one |
| D6B-25 | b-26: the missing night outlined solid | Dashed 4/4, as §9.2 (T6B.6) | The spec's wording; the draft's disc is already dashed |
| D6B-26 | My Day "Show all" only above the cap, with a count | Whenever the day has activities, no count, as b-17 (T6B.6) | The draft |
| D6B-27 | Exercise page hero: the PR | The newest e1RM estimate; older than 90 days → the newest point overall with its date (T6B.5, lead) | It pairs with "▲ x kg in 90 days"; the PR stays in the rule and the records |
| D6B-28 | `addActivity.cancel` / `addSleep.cancel` | `sheet.close` (label "Cancel"; "Close" when nothing to discard) (T6B.7) | `SheetHeader` owns its close id (D6B-13); no test used the old ids |
| D6B-29 | Activity detail: the Today strain tile itself | `ActivityStrainTile` built from the same parts (T6B.7) | `TodayStrainTile` is a Button bound to Today's content; extract a shared face after PR 6 |
| D6B-30 | Activity detail: route map card | None (T6B.7) | The base had none; data-quality A4 adds it |

## 17. Questions only the user can answer

1. **Q1** Two Volt marks at once while resting (the active row's dot and bar, and the rest ring): fine, or Volt only on the active set?
2. **Q2** List's Finish becomes an outline until every set is done (it is filled from the first set today): fine?
3. **Q3** The running rest pill is an outline with a Volt ring, no longer a filled pill: fine, or a light filled pill (then the ✓ and the pill are both filled ink)?
4. **Q4** The active set's ✓ is a filled light square (the ink of the primary pill), not Volt: fine?
5. **Q5** The Journal says "behaviors" ("Choose behaviors in Profile → Journal."); PR 5's note says not to borrow that word. Rename to "habits" (the card already says "habits")?
6. **Q6** Four more screens get a `DotNumeral` hero (summary, session detail, exercise page, activity detail): fine, beyond Today, Sleep, Strain?
7. **Q7** Plans' active plan as a strain glow tile (paused = an outline): fine?
8. **Q8** The summary loses its celebration (bouncing seal, scale-in) for a calm numeral: fine?
9. **Q9** The live workout keeps 16 pt sides and exercise names in 17 Medium (not 20 pt sides / 26 Light): fine?

## 18. Draft renders

All dark, 390 × 844 at 3×, English, synthetic data ("Upper A", "Bench press", "Barbell row"; no real workouts or names), composed from the PR 2–4 components and throwaway copies of the proposed primitives
(`RyftTests/Draft6b*.swift`, excluded from the commit). Long screens show the top 844 pt; the rest scrolls.
Folder: `the lead's session scratchpad, `pr6-drafts/b/` (not in the repo)`

| File | Screen |
|---|---|
| `b-01-start-sheet.png` | Start workout (over the Strain screen) |
| `b-02-live-list.png`, `b-03-live-list-ax3.png` | Live workout, List, default and AX3 (the stacked header) |
| `b-04-live-focused.png`, `b-05-live-focused-ax3.png`, `b-28-live-focused-320.png` | Focused, default, AX3, 320 × 693 |
| `b-06-live-keypad.png` | Focused with the keypad and a running rest |
| `b-07-rest-sheet.png`, `b-27-rest-sheet-idle.png` | Rest sheet running, idle with a changed length |
| `b-08-all-done.png` | All sets done: the card and the header's Finish turned primary |
| `b-09-summary.png` | Workout summary |
| `b-10-plans.png`, `b-25-plans-paused.png` | Plans, active and paused |
| `b-11-plan-detail.png`, `b-12-plan-builder.png` | Plan detail, plan builder |
| `b-13-history.png`, `b-14-session-detail.png`, `b-15-exercise-page.png` | History, session detail, exercise page |
| `b-16-live-activity.png` | Live Activity: lock screen (resting, working), Dynamic Island (expanded, compact, minimal): replicas |
| `b-17-today-my-day.png` | Today below the fold: My Day, Journal and Train cards |
| `b-18-my-day.png`, `b-26-my-day-missing-night.png` | My Day, full screen; a day without a recorded night |
| `b-19-add-activity.png`, `b-20-add-sleep.png`, `b-21-activity-detail.png` | Add activity, Add sleep, activity detail (manual, no heart rate) |
| `b-22-journal.png` | Journal sheet |
| `b-23-train-entry.png` | Strain's Train group with the resume banner |
| `b-24-add-exercise.png` | Add exercise sheet |

Not rendered: the confirmation dialogs (system), the sport picker, plan builder's other states, the Apple Health ask on the summary, and states described in text only.
