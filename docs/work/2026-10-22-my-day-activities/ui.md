# My Day, Add activity, Start activity (GPS): UI spec (D2)

Brief: `brief.md` §1–§5, data in `platform-brief.md`. Code read at `origin/main` (d9fc265). Spec only.
Format follows `docs/work/2026-10-21-refresh-resilience/ui.md`. State vocabulary and neutral source glyphs follow
`docs/work/2026-10-22-tracker-setup/ui.md` incl. its errata (PRs #33, #34, #36, not merged: where this spec uses their
friendly names, it says so). Everything uses `Theme`, `Typography`, `ChartStyle` and shipped components. Copy is a draft:
the localization-editor finalises it. German is du-form and uses the shipped terms (Bereitschaft, Ausgangswerte, Sync).

**File placement.** The brief says `Ryft/` will be converted to synchronized folders. This spec names new files as
`Ryft/Features/MyDay/`, `Ryft/Features/Activities/` and `Ryft/Design/`. Until the user converts `Ryft/` in Xcode, a new
`.swift` file there is not compiled; the developer then puts each type into the nearest existing file. `RyftWidgets/`
is already synchronized, so the Live Activity files are new files there.

## 0. Principles for these screens

1. **Numbers first.** Every row, summary and the recording screen lead with value, unit, then words. Sentences come last.
2. **A day is a list of facts, each with a source.** Every row says where it came from ("Garmin Connect", "RYFT",
   "Added by you"). Merged rows say both. Strain is never shown without saying whether it is scored.
3. **Pending is an outline, scored is a number, failed is a word.** A hollow dot means "waiting for heart rate", never
   a spinner and never zero. A cloud with an arrow means "on this iPhone, not at RYFT yet". Failed says "Not uploaded" and offers Retry.
   Local data is never lost: the copy says so.
4. **Shape and words, never colour alone.** Each row state has its own glyph and its own word (spoken, and visible at
   AX sizes and in the detail). Pace "fastest split" is marked with a glyph and the word, not just teal.
5. **One accent per screen.** Teal is the one primary action (Start, Save, Resume) and the route line. Strain value on
   rows reuses the shipped `StrainPill`. Everything else is `textPrimary / textSecondary / textTertiary`.
   Errors are quiet: `exclamationmark.circle` in `Theme.warning` plus `textSecondary` text (amber text fails
   contrast, as in the tracker-setup spec). Red (`Theme.alert`) only for destructive buttons (Discard, Delete) and the HR curve.
6. **Honest GPS.** The phone says how accurate it is, in metres, and what it will do about it. HR is never faked.
7. **The recording screen is an instrument you read at arm's length in sunlight.** Large, high contrast, few things,
   big targets, no gestures that need precision except one deliberate long press (with a plain alternative).
8. **Location is personal data.** Route is opt-in per activity, the privacy zone is explained in plain words, and
   nothing on screen, in the Live Activity or in a VoiceOver label ever names a place.
9. **Brand rule.** RYFT's names: My Day, Add activity, Start activity, Resume, Finish, Splits. Vendor names only as data
   sources ("Garmin Connect"), never compared. No other product's layout, no "target" or "goal ring" language.

Reading order and eye path:
- **Today:** gauge first, then the sentence, My Day below the scores, Trends after.
- **My Day card:** the list (what happened), then the two buttons.
- **Recording:** time, distance, pace; then the controls; the map is secondary and off by default after the first minute (see 4.2).

---

## 1. State inventory

| ID | Screen | State | Trigger | One action |
| --- | --- | --- | --- | --- |
| M1 | My Day card | populated | at least one item today | row tap opens its detail |
| M2 | My Day card | nothing yet | no items and no sleep missing (e.g. it is early, tracker has sleep) | Add activity / Start activity (buttons) |
| M3 | My Day card | no sleep | today has no sleep item (no tracker sleep, no manual) | Add sleep (inline text button) |
| M4 | My Day card | loading | first load, nothing cached | skeleton outline rows, no spinner |
| M5 | My Day card | stale / offline | platform list unreachable; cached list shown | none: caption "Showing the list from 14:05" |
| M6 | My Day card | recording in progress | `ActivityRecorder` is active | "Resume recording" banner row replaces the Start button |
| R1 | Row | pending upload | RYFT activity saved locally, not confirmed | none (auto retry); the cloud+arrow is a button that opens Details |
| R2 | Row | uploaded, strain pending | platform has it, `scoring_state` not scored | none |
| R3 | Row | scored | `strain` present | tap row |
| R4 | Row | failed upload | retries exhausted or 4xx | Retry |
| R5 | Row | no strain possible | `strain_source: none` and scored | none: shows "no heart rate" word |
| R6 | Row | merged | `merged_with` set | tap row |
| R7 | Row | sleep | tracker or manual sleep | tap opens Sleep |
| F1 | Full My Day | today | opened from card | as card but all rows, DateStrip |
| F2 | Full My Day | past day | other day selected | tap row; edit/delete on manual and recorded |
| F3 | Full My Day | past day, empty | no items | "Nothing recorded on this day" |
| A1 | Add activity | default | opened | Save |
| A2 | Add activity | invalid | end before start, future, over 24 h, distance implausible | fix field |
| A3 | Add activity | strength | sport = Strength | Log in Train |
| A4 | Add activity | saving / saved offline | Save tapped | none |
| A5 | Add activity | rejected | `422` or other | edit, Try again |
| S1 | Add sleep | default | opened | Save |
| S2 | Add sleep | invalid | wake before bed, over 16 h, future | fix |
| S3 | Add sleep | tracker sleep exists | entry in the menu is hidden; sheet shows the fact | none |
| P1 | Pre-start | locating | location authorised, accuracy unknown or > 20 m | Start anyway |
| P2 | Pre-start | ready | accuracy ≤ 20 m | Start |
| P3 | Pre-start | weak | still > 50 m after 30 s | Start anyway / go outside hint |
| P4 | Pre-start | pre-prompt | permission not determined | Continue (then the system prompt) |
| P5 | Pre-start | denied / restricted | status denied | Open Settings / Record without GPS |
| P6 | Pre-start | approximate location | precise location off | Turn on Precise Location (Settings) |
| P7 | Pre-start | indoor | sport has no GPS | Start (no map) |
| P8 | Pre-start | motion permission needed | trail, hike, MTB, ski touring | Allow (before the system prompt) / Skip |
| P9 | Pre-start | already recording | recorder active | Resume recording |
| G1 | Recording | running | recording | pause, lap, hold to stop |
| G2 | Recording | paused (manual) | user pause | Resume |
| G3 | Recording | auto-paused | speed below threshold 10 s | none: resumes by itself |
| G4 | Recording | GPS weak | accuracy > 25 m for > 10 s | none (distance keeps counting only from good fixes) |
| G5 | Recording | GPS lost | no fix for 15 s | none; offers "Keep recording by time" implicitly |
| G6 | Recording | location permission revoked mid-run | status changes | Open Settings |
| G7 | Recording | HR live | BLE sensor connected | none |
| G8 | Recording | HR not live | no sensor | none (explanatory line) |
| G9 | Recording | HR sensor lost | connection dropped | none (line changes) |
| G10 | Recording | low battery / low power mode | LPM or ≤ 10 % | none (info line) |
| L1 | Live Activity | running | recording | tap opens recording |
| L2 | Live Activity | paused / auto-paused | pause | Open (no controls in v1) |
| L3 | Live Activity | stale | app not updating (killed) | tap opens RYFT |
| Z1 | Finish summary | default | Stop confirmed | Save |
| Z2 | Finish summary | too short | < 10 s or < 20 m moved | Discard (Save still allowed) |
| Z3 | Finish summary | saving | Save tapped | none |
| Z4 | Finish summary | queued offline | saved locally, no network | none |
| Z5 | Finish summary | save failed locally | storage error | Try again |
| Z6 | Finish summary | privacy zone suggestion | first route save, no zones | Add zone / Not now |
| Z7 | Finish summary | discard confirmation | Discard tapped | Discard / Keep |
| D1 | Detail | recorded with GPS | route present | edit / delete |
| D2 | Detail | recorded, route not kept | Record route off | none |
| D3 | Detail | manual | origin manual | edit / delete |
| D4 | Detail | merged | `merged_with` | none |
| D5 | Detail | strain from HR | `strain_source: heart_rate` | none |
| D6 | Detail | strain from effort | `perceived_effort` | none |
| D7 | Detail | no strain | `none` / HR pending | none |
| D8 | Detail | strength | sport strength or `session_id` | existing summary |
| D9 | Detail | pending upload / failed | as R1, R4 | Retry |
| D10 | Detail | delete confirmation | Delete tapped | Delete / Keep |
| D11 | Detail / row | route removed after 30 days | route unconfirmed for 30 days | none |
| D12 | Row / detail / sheet | route withheld | recorded with zones, none now | Review: send as recorded / add zones / send without |
| S8 | Settings / pre-start | zones couldn't be restored | restore on a new iPhone | Add zones |
| P10 | Pre-start | first Start of a GPS sport | route choice not yet stored | Record route / Don't record route (equal) |
| U1 | Resume your run | background auto-resume | background relaunch within 10 min of the checkpoint | none (continues; line shown) |
| U2 | Resume your run | asks | foreground launch | Resume (under 6 h and same day) / Finish / Discard |
| T1 | Settings | Activities section | Profile | rows |
| T2 | Privacy zones | none / list / add place | | Add place |

---

## 2. My Day

### 2.1 The card on Today

Position: below the score block (gauge, tiles), above Trends. Built from `Card`, `CardHeader`, the new `MyDayRow`.
Always today; it does not move with the history.

**Header row** (`Card` padding `cardPadding` 18):
- Title "My Day" (`CardHeader` style, headline) and under it a `caption` line `textSecondary`: "Thursday 22 Oct" via `Fmt.dayTitle`.
- Trailing, two 44 × 44 targets, 8 pt apart, no backgrounds:
  - Expand: `arrow.up.left.and.arrow.down.right`, 15 pt medium, `textSecondary`. Opens the full-screen My Day.
  - Plus: `plus`, 17 pt medium, `textPrimary` (one accent per screen: Start is the teal). It is a `Menu`:
    1. Add activity (`square.and.pencil`)
    2. Start activity (`play.circle`)
    3. Start strength workout (`dumbbell`), the existing Train flow
    4. Add sleep (`bed.double`), hidden if today has sleep
- The whole title block is also a button to the full-screen view (one element for VoiceOver: "My Day, Thursday 22 October, opens the list").

**List** (spacing 10 between rows, hairline `Theme.separator` between rows, no inner row card, so the card does not
nest surfaces):
- Chronological ascending by start. Sleep sorts by its start (last night), so it is first.
- Cap 5 rows. Over the cap: sleep, then the latest 4 others in order, and a "Show all 9" text button
  (`callout`, `textSecondary`, 44 min height, chevron) opening the full-screen view.
- Row anatomy: see 2.2.

**Empty and missing** (inside the list area, `callout`):
- M3 no sleep: an extra first line, a muted row: `bed.double` 18 pt `textTertiary` in a 44 pt circle of `surfaceRaised`,
  text "No sleep recorded" (`body`, `textSecondary`) and a text button "Add sleep" (`callout`, `textPrimary`, underlined not needed; min 44 height), separated by " · " in the visible copy: "No sleep recorded · Add sleep". Layout: text and button on one line; at AX sizes the button wraps to its own line.
- M2 nothing: `callout` `textSecondary` "Nothing yet today", under it `caption` `textTertiary` "Add what you did, or start recording." When M2 and M3 both: M3 line first, then M2 under it.
- M4 loading: two outline rows (hairline rounded rect, `separator`, no fill pulse; reduced motion static). No spinner.
- M5 stale: caption under the list "Showing the list from 14:05" `textTertiary`, and `InlineMessage`-style "Try again" only after 2 minutes (follow the refresh-resilience threshold; no red).

**Buttons** (below the list, 16 pt gap, hairline above):
- `HStack(spacing: 10)`: **Add activity** = `PrimaryButton(.secondary)`, **Start activity** = `PrimaryButton(.primary)` (Teal, `onAccent` text), both min 44 height, equal width. At AX sizes stacked vertically, Start first (primary on top).
- Past-day and recording variants: when M6 (recording active) the pair is replaced by one `PrimaryButton(.primary)`
  "Resume recording" with `record.circle` and the running time ("Resume recording · 24:10"), the time updating every second via `Text(timerInterval:)`.

**Tap targets:** rows are one button each (min height 60). The plus menu and expand are 44 × 44.

### 2.2 Row anatomy (`MyDayRow`, shared by card and full screen)

Horizontal: `[icon 44] 14 [text block] Spacer [trailing]`; no chevron on the card (the whole row taps), chevron
`chevron.right` 12 pt `textTertiary` on the full screen. Row min height 60, vertical padding 6.

- **Icon:** 44 pt circle, `Theme.accent.opacity(0.12)` fill, SF Symbol 18 pt medium. Tint `Theme.accent` for workouts,
  `Theme.metricSleep` for sleep (`bed.double.fill`, fill `metricSleep.opacity(0.14)`). This repeats the shipped `ActivityRow`.
- **Line 1:** name, `body`, `textPrimary`, one line, truncates tail (at AX sizes up to 3 lines).
- **Line 2:** `caption`, `monospacedDigit`, `textSecondary`: "07:12–07:48 · 36 min · 5.2 km". Time range en-dash with no spaces; the end is omitted while still recording ("07:12–now"). Distance via `Fmt.distance(meters:)` (locale `.road`: metric or miles). Parts that don't exist are dropped, never a dash. Sleep: "23:05–06:58 · 7 h 53 min".
- **Line 3:** the source badge(s) (2.3), `caption2`-sized capsules.
- **Trailing** (top-aligned with line 1, 44 pt wide minimum): the **state mark** (2.4).
- At AX sizes the trailing mark moves under line 3, left-aligned, with its word; icon shrinks to 36 pt (`@ScaledMetric` capped).

Names: the sport's display name ("Run", "Trail run", "Ride", "Walk", "Hike", "Strength"), the Train session title when
present, "Sleep" for sleep. Apple Health workouts use `ActivityStyle.name`.

### 2.3 Source badges (new, `SourceBadge`, `Ryft/Design/SourceBadge.swift`)

Capsule, `Theme.surfaceRaised` fill, 1 pt `separator` outline in light mode only (needed for contrast on `Mist` surfaces),
padding 8 h / 4 v, `caption` (12 pt) `textSecondary`, leading glyph 11 pt `textTertiary`, 6 pt gap, one line (truncates at middle).

| Source | Label en / de | Glyph |
| --- | --- | --- |
| tracker workout or sleep with friendly name from `trackers.json` (tracker-setup, unmerged) | e.g. "Garmin Connect" | by tracker id: `apple_watch` is `applewatch`; `iphone` is `iphone`; other watch `watch.analog`; ring `circle.circle`; band the neutral glyph T2 proposes; unknown `ellipsis.circle` |
| Apple Health source with no mapping | "Apple Health" / "Apple Health" | `heart.text.square` |
| Train session | "Train" / "Train" | `dumbbell.fill` |
| RYFT recorded | "RYFT" / "RYFT" | `location.fill` (indoor: `figure.run`) |
| Manual | "Added by you" / "Von dir hinzugefügt" | `pencil` |

Until PR #33 lands, the tracker rows use the raw `Workout.source` string through a one-function mapping that tracker-setup
replaces with `trackers.json` names. No vendor logos; the Apple glyphs only for the Apple devices (errata 1).

**Merged rows (R6):** two badges side by side, 6 pt apart, in the order "tracker, RYFT" (the one with heart rate first):
`[watch.analog Garmin Connect] [location.fill RYFT]`. If they don't fit one line (AX, narrow), they wrap into two
lines left-aligned (`Layout` flow: new `FlowLayout` in `SourceBadge.swift`). VoiceOver: "Sources: Garmin Connect and
RYFT, merged". The detail screen explains the merge (D4).

`SourceBadge` takes `kind`, `title`, `glyph`; `SourceBadges` takes an array and lays out the flow.

### 2.4 State marks (new, `ActivityStateMark`, `Ryft/Design/ActivityStateMark.swift`)

Trailing column. Visible words appear in the detail and from the `xxxLarge` Dynamic Type size on, as a `caption`
`textSecondary` under the glyph; on normal sizes the glyph stands alone and VoiceOver speaks the word.

| State | Visual | Word en | Word de |
| --- | --- | --- | --- |
| R1 pending upload | `icloud.and.arrow.up` 16 pt, `textSecondary` | Uploading | Wird hochgeladen |
| R2 uploaded, pending strain | hollow circle 12 pt, 1.5 pt `textTertiary` stroke, no fill (same as the pending outline language) | Strain pending | Strain ausstehend |
| R3 scored | shipped `StrainPill` (value `monospacedDigit`, `callout`) | Strain 8.4 | Strain 8,4 |
| R4 failed | `exclamationmark.circle` 16 pt `Theme.warning` plus a text button "Retry" (`callout`, `textPrimary`, min 44 × 44) | Not uploaded. Retry | Nicht hochgeladen. Erneut versuchen |
| R5 no strain possible | `minus.circle` 16 pt `textTertiary` (the tracker-setup "expected not available" glyph) | No heart rate | Keine Herzfrequenz |
| R7 sleep | no mark (sleep has no strain) | | |

R2 and R5 differ: R2 means data may still arrive; R5 means the platform scored it and had none. The platform's
`scoring_state` decides; Train sessions and tracker workouts only ever show R2, R3 or R5 (they have no upload).
Pending to scored: the hollow dot cross-fades to the pill in 250 ms (`Theme.Motion.quick`), no roll; reduced motion instant.

Failed and pending rows keep the same row layout; the whole row stays tappable and the detail shows the copy "Saved on
this iPhone. RYFT will try again, or tap Retry." (R4 detail: "Couldn't upload. It is still saved on this iPhone.").
The Retry button is only in R4; in R1 the cloud is not a button.

### 2.5 Full-screen My Day

Pushed on Today's `NavigationStack` (nav bar visible, inline title "My Day", back chevron). Not a sheet: it is a place
you stay in.

- **DateStrip:** reuse the shipped `JournalDateStrip` (last 14 days, 48 × 52 chips, selected = Teal fill with
  `onAccent`). It is Journal-named today; this feature moves it to `Ryft/Design/DateStrip.swift` as `DateStrip` and
  Journal imports it (rename only; the brief calls it `DateStrip`). The strip sits under the nav bar, pinned.
- **Header under the strip:** the day title (`Fmt.dayTitle`, `title`), under it one summary line, `callout`, `monospacedDigit`, `textSecondary`:
  "3 activities · 1 h 52 min · 14.8 km" (if any) and, once the day is scored, the day strain as a `StrainPill`.
- **List:** `ScrollView` + `LazyVStack(spacing: 10)`, each row on its own `Theme.surface` tile (`tileRadius` 16, padding 14, the shipped list look),
  all items, sleep first. Section labels are not used; one flat chronological list.
- **Bottom bar** (today only): the same two buttons, pinned above the safe area on `Theme.background` with a hairline.
  Past days: no Start button (you cannot record the past); "Add activity" stays (date prefilled to the viewed day; see
  open question 1).
- **Header trailing** (nav bar): the same plus menu, minus "Start …" entries on past days.
- **Past days:** the list is read-only: rows open the detail; Tracker and Train rows have no edit or delete. Manual
  and recorded rows: swipe actions "Edit" (`pencil`, neutral) and "Delete" (`trash`, `alert`) and a context menu with
  the same, and the detail has both. Swipe is never the only path.
- **F3 empty past day:** "Nothing recorded on this day" + `caption` `textTertiary` "Anything your tracker syncs later will appear here." If there is also no sleep: the M3 line (Add sleep) stays, for the last 14 days.
- **Pull to refresh:** shipped `ScreenScaffold` pattern.

### 2.6 Motion
- List changes (a row arriving, a pending dot becoming a pill): cross-fade 250 ms (`Theme.Motion.quick`). New row from
  Save: fade in at its chronological place; no slide. Day switch: cross-fade 250 ms. All instant under Reduce Motion.
- No count-ups.

### 2.7 VoiceOver and Dynamic Type
- Each row is one element, label built from the visible pieces in the order: name, time range spoken ("from 7:12 to
  7:48"), duration ("36 minutes"), distance ("5.2 kilometres"), state word, sources. Example: "Run, 7:12 to 7:48 AM, 36 minutes,
  5.2 kilometres, strain 8.4, sources Garmin Connect and RYFT, merged." Hint: "Opens the activity." R4: adds the
  custom action "Retry"; swipe actions are exposed as `accessibilityAction`s ("Edit", "Delete").
- Card order: header (title+expand as one button), plus menu, list rows, "Show all", Add activity, Start activity.
- AX sizes (to AX5): the icon shrinks, the trailing mark drops under the text with its word, the buttons stack,
  rows have no line limits except line 1 (3). The DateStrip chips keep 48 × 52 and the strip scrolls; selected chip's
  VoiceOver label is the full date and "selected".
- Both schemes: badges use `surfaceRaised` + outline in light; mark colours reach 4.5:1 (`textSecondary` on surface).

### 2.7a Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| card title | My Day | Mein Tag |
| expand a11y | Open My Day | Mein Tag öffnen |
| plus a11y | Add to your day | Zu deinem Tag hinzufügen |
| menu | Add activity · Start activity · Start strength workout · Add sleep | Aktivität hinzufügen · Aktivität starten · Krafttraining starten · Schlaf hinzufügen |
| no sleep | No sleep recorded · Add sleep | Kein Schlaf erfasst · Schlaf hinzufügen |
| empty | Nothing yet today | Heute noch nichts |
| empty detail | Add what you did, or start recording. | Füge hinzu, was du gemacht hast, oder starte eine Aufzeichnung. |
| show all | Show all %d | Alle %d anzeigen |
| resume rec | Resume recording · %@ | Aufzeichnung fortsetzen · %@ |
| stale | Showing the list from %@ | Liste von %@ |
| past empty | Nothing recorded on this day | An diesem Tag wurde nichts erfasst |
| past empty detail | Anything your tracker syncs later will appear here. | Was dein Tracker später synchronisiert, erscheint hier. |
| summary | %d activities · %@ · %@ | %d Aktivitäten · %@ · %@ |
| sleep row | Sleep | Schlaf |

---

## 3. Add activity sheet

Presented as a sheet (`.large` detent, drag indicator), `NavigationStack` inside, title "Add activity", Cancel
(leading, `textPrimary`) and **Save** (trailing, `PrimaryButton`-style text button, Teal text on bar; disabled with a reason, see below).
Form is `ScrollView` of `Card`-style groups (not a system `Form`, to match Journal's look), each group
`Theme.surface`, `cardRadius`, padding 18, 16 pt apart. Keyboard avoidance: the notes field scrolls into view.

### 3.1 Fields (top to bottom)

1. **Sport** (group, one row): icon 44 pt circle + sport name (`body`) + `chevron.up.chevron.down`. Tap pushes the picker (3.2).
   Default: the most recent sport, else Running.
2. **When** (group):
   - Row "Start": a compact `DatePicker` (date and time), row "End": compact `DatePicker`; labels `callout` `textSecondary`, values `monospacedDigit`.
   - Max for both = now (recomputed every minute); end min = start. Defaults: for today, end = now rounded down to the minute, start = end − 60 min. For a past day: 12:00–13:00 of that day.
   - A summary line under: "Duration 1 h 00 min" (`callout`, `monospacedDigit`, `textPrimary`), live. Beside: if the window crosses midnight, "(next day)".
3. **Distance** (optional, hidden for sports with no distance: Strength, Yoga, Mobility, HIIT, Tennis, Padel, Football, Climbing, Other shows it still as optional): numeric field, trailing unit "km" or "mi" by locale, placeholder "Optional". Decimal pad with a "Done" accessory. `monospacedDigit`.
4. **Effort** (optional): `EffortScale` (new, `Ryft/Design/EffortScale.swift`), see 3.3.
5. **Notes** (optional): multi-line `TextField` (axis `.vertical`, 2 to 6 lines), placeholder "Notes", limit 500; the counter "412 / 500" shows from 400 on (`caption` `textTertiary`, `monospacedDigit`).
6. **Heart-rate footer** (not a group, `caption` `textSecondary`, one line): "Strain comes from the heart rate your tracker syncs for this time. Without it, your effort rating is used." The second sentence only shows if the platform supports effort-based strain (open question 4); otherwise "Without heart rate there is no strain for this activity." Written as a fact at the bottom; hidden if the sport is Strength (A3).

### 3.2 Sport picker

Pushed view "Sport", `.searchable` (always visible, `prompt: "Search sports"`), list on `background`, rows 56 pt min:
icon, name, `checkmark` (Teal, `accent`) on the selected one. Section order:
- **Recent** (up to 5, by last use, from local store; hidden while searching), then
- **All sports** alphabetically in the current language, grouped under no headers (22 items).
Search matches name prefix and synonyms (en: "run", "jog", "bike", "ski"; de: "laufen", "joggen", "rad", "ski"). No result: "No sport matches “%@”" + button "Use Other". `hasGPS` sports show `location` glyph 12 pt `textTertiary` at the trailing edge, spoken "uses GPS" (only in the Start picker, 5.1; in Add they are irrelevant).
Selecting pops back with a 250 ms cross-fade; reduced motion instant.

Catalogue icons (SF Symbols; SF Symbols 6 names exist for iOS 17 except where noted, fall back to `figure.mixed.cardio`):
Running `figure.run`; Trail running `figure.run` (distinguish by name; optionally `mountain.2.fill` badge deferred); Walking `figure.walk`;
Hiking `figure.hiking`; Cycling `figure.outdoor.cycle`; Mountain biking `figure.outdoor.cycle`; Gravel `figure.outdoor.cycle`;
Indoor run `figure.run.treadmill`; Indoor cycling `figure.indoor.cycle`; Rowing `figure.rower`; Swimming `figure.pool.swim`;
Strength `dumbbell.fill`; HIIT `figure.highintensity.intervaltraining`; Yoga `figure.yoga`; Mobility `figure.flexibility`;
Climbing `figure.climbing`; Skiing `figure.skiing.downhill`; Ski touring `figure.skiing.crosscountry`; Football `figure.soccer`;
Tennis `figure.tennis`; Padel `figure.racquetball` (stand-in; no padel symbol); Other `figure.mixed.cardio`.
The catalogue (`SportCatalogue`) belongs to the architect's note; the design only needs `symbol`, `name`, `hasGPS`.

### 3.3 Effort scale (`EffortScale`)

Two rows of five 44 × 44 pt (min) round buttons labelled 1 to 10, `monospacedDigit` `body`. Unselected: `surfaceRaised` fill,
`textPrimary`; selected: `Theme.accent` fill, `onAccent` text, plus a `checkmark`-free but with **bold weight and a 2 pt
outline** so selection is not colour-only. Under the grid, the word for the selected value: "6 · Moderately hard".
Bands: 1–2 Very easy, 3–4 Easy, 5–6 Moderate, 7–8 Hard, 9–10 Maximal (de: Sehr leicht, Leicht, Mittel, Schwer, Maximal).
Tap the selected button again to clear (VoiceOver: custom action "Clear"). As one `accessibilityAdjustableAction` element: "Perceived effort, 6 of 10, Moderate" with swipe up/down changing the value; or each button individually reachable: the adjustable form is the default, the buttons remain for touch.
At AX sizes: 5 columns become 3 (rows of 3, 3, 3, 1) so labels stay big.

### 3.4 Strength suggestion (A3)

When Strength is chosen, the "When" group stays but a notice card is inserted at the top (`surface`, hairline `separator` border, `dumbbell` icon in `textSecondary`, no teal):
"Strength is best logged in Train. Your sets, reps and load count toward muscular load." Buttons: **Log in Train** (`PrimaryButton(.secondary)`, closes the sheet and opens the shipped Train start/log flow) and a text button "Add here anyway". After "Add here anyway" the card collapses to a one-line note. Distance hidden for Strength.

### 3.5 Validation (A2)

Save is disabled while invalid and the reason is visible under the field, never only in a toast:
- Future: "End can't be in the future." (picker max already prevents it; the message shows when time passes during editing.)
- Order: "End must be after start."
- Length: "An activity can be at most 24 hours."
- Distance: must be > 0 and below a sport-specific ceiling of speed (warn, not block): "That's faster than expected for this sport. Check the distance." Warn-state keeps Save enabled.
- Notes over 500: counter turns `textPrimary` with `exclamationmark.circle`, "Notes can be 500 characters." and the field stops accepting.
Error row: `exclamationmark.circle` 14 pt `Theme.warning` + `callout` `textSecondary`, 6 pt under the field. The first invalid field gets VoiceOver focus after Save is attempted with the reason announced.

### 3.6 Save, offline, rejected (A4, A5)
- Save writes locally first and the sheet closes in 250 ms (cross-fade of the list): "Saved" is a local fact. No blocking spinner. The new row appears in My Day with the R1 cloud, then R2 or R3.
- Offline: identical; row stays R1; no alert. `caption` in detail: "Saved on this iPhone. It will upload when you're online."
- `422` or `4xx`: the row shows R4 (failed) and tapping it opens the detail with `InlineMessage`: "RYFT couldn't accept this activity. It is still saved on this iPhone." + Edit (opens the sheet) + Details (status and request ID, shipped pattern). Never "log in again" except a final 401 (shipped handling).

### 3.7 Add sleep sheet (S1 to S3)

Same sheet frame, title "Add sleep", `.medium` detent (`.large` at AX sizes).
- Explanation line (`callout`, `textSecondary`): "For last night, when no tracker recorded it."
- Two rows: "Went to bed" (date + time) and "Woke up" (date + time), compact pickers. Defaults: bed = yesterday 23:00 (or the user's planned bedtime from the Sleep planner when set), wake = today 07:00, capped at now.
- Live line: "Time asleep 8 h 00 min" `headline` `monospacedDigit` `textPrimary`; under it `caption` `textTertiary` "Time in bed. RYFT can't see your sleep stages for this entry."
- Rules: wake after bed, 1 h to 16 h, wake not in the future. Reasons inline as 3.5.
- Footer note with `pencil` glyph: "It's marked “added by you”. If your tracker records this night later, RYFT uses the tracker's data instead." (tracker sleep wins.) 
- S3: if tracker sleep exists, the menu item is hidden; opening from a deep link shows "Sleep was already recorded by %@." and no form.
- Delete: in the Sleep row's detail context menu "Delete this entry" with confirmation "Delete this sleep entry? Your scores for that night are recalculated."
- Copy and offline behaviour as 3.6; sleep scoring is pending until the platform scores: the Today hero already handles the pending night states (existing "Scoring your night").

### 3.8 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| title | Add activity | Aktivität hinzufügen |
| sport | Sport | Sportart |
| start / end | Start · End | Beginn · Ende |
| duration | Duration %@ | Dauer %@ |
| distance | Distance (optional) | Distanz (optional) |
| effort | Perceived effort (optional) | Gefühlte Anstrengung (optional) |
| effort words | Very easy · Easy · Moderate · Hard · Maximal | Sehr leicht · Leicht · Mittel · Schwer · Maximal |
| effort a11y | Perceived effort, %d of 10, %@ | Gefühlte Anstrengung, %d von 10, %@ |
| notes | Notes | Notizen |
| hr footer | Strain comes from the heart rate your tracker syncs for this time. Without it, your effort rating is used. | Strain kommt aus der Herzfrequenz, die dein Tracker für diese Zeit synchronisiert. Ohne sie zählt deine Anstrengung. |
| hr footer (no effort) | Without heart rate there is no strain for this activity. | Ohne Herzfrequenz gibt es für diese Aktivität keinen Strain. |
| strength | Strength is best logged in Train. Your sets, reps and load count toward muscular load. | Krafttraining loggst du am besten in Train. Sätze, Wiederholungen und Last zählen für die muskuläre Belastung. |
| log in train | Log in Train | In Train erfassen |
| add anyway | Add here anyway | Trotzdem hier hinzufügen |
| err future | End can't be in the future. | Das Ende darf nicht in der Zukunft liegen. |
| err order | End must be after start. | Das Ende muss nach dem Beginn liegen. |
| err 24h | An activity can be at most 24 hours. | Eine Aktivität darf höchstens 24 Stunden dauern. |
| warn distance | That's faster than expected for this sport. Check the distance. | Das ist schneller als bei dieser Sportart üblich. Prüfe die Distanz. |
| saved local | Saved on this iPhone. It will upload when you're online. | Auf diesem iPhone gespeichert. Der Upload folgt, sobald du online bist. |
| rejected | RYFT couldn't accept this activity. It is still saved on this iPhone. | RYFT konnte diese Aktivität nicht annehmen. Sie ist weiterhin auf diesem iPhone gespeichert. |
| sleep title | Add sleep | Schlaf hinzufügen |
| sleep intro | For last night, when no tracker recorded it. | Für letzte Nacht, wenn kein Tracker sie erfasst hat. |
| bed / wake | Went to bed · Woke up | Ins Bett gegangen · Aufgewacht |
| asleep | Time asleep %@ | Schlafdauer %@ |
| sleep note | It's marked “added by you”. If your tracker records this night later, RYFT uses the tracker's data instead. | Der Eintrag ist als „von dir hinzugefügt“ markiert. Erfasst dein Tracker diese Nacht später, nutzt RYFT stattdessen seine Daten. |
| sleep err | Sleep can be 1 to 16 hours. | Schlaf kann 1 bis 16 Stunden dauern. |

### 3.9 VoiceOver and Dynamic Type
- Order: Cancel, sport, start, end, duration, distance, effort (adjustable), notes, HR footer, Save. Duration line is
  `accessibilityLabel` "Duration, 1 hour". Errors are announced (`AccessibilityNotification.Announcement`) once, not on every keystroke.
- AX sizes: pickers stack label above value; effort grid 3 columns; Save stays in the bar; the keyboard does not hide the focused field.

---

## 4. Start activity: pre-start

> **Privacy review (Art. 25, no pre-set "on").** Route recording has no default until the user decides.

Presented full-screen (`fullScreenCover`) from the buttons, the plus menu, the App Intent and the Control Center control, with a Close (`xmark`, 44 pt) top leading. Title "Start activity" (inline).

### 4.1 Layout (GPS sports, P1/P2)

Top to bottom, on `Theme.background`:
1. **Sport row** (44 + 16): the sport icon circle, name `headline`, `chevron.up.chevron.down`, whole row a button that pushes the same picker as 3.2 (recents first, `location` glyph on GPS sports, "Indoor" caption on indoor ones).
2. **Map** (`RouteMap` in `.live` mode, new, `Ryft/Design/RouteMap.swift`): rounded `cardRadius`, height 40 % of the safe screen
   (min 220 pt; at AX sizes 180 pt), `Map` with `.mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))`, the user's position as a 14 pt Teal dot with a 2 pt `Mist` ring and a translucent accuracy circle (`accent` at 12 %, 1 pt `accent` edge, radius = horizontal accuracy). Not interactive beyond pan/zoom; the camera follows the user. No other markers.
   Offline map tiles missing: the map shows its grid; the layer is secondary and a small caption "Map unavailable offline" `textTertiary`.
3. **GPS accuracy indicator** (`GPSAccuracyIndicator`, new, `Ryft/Design/GPSAccuracyIndicator.swift`), a row directly under the map:
   - Left: four 4 pt-wide ascending bars (4, 8, 12, 16 pt tall), filled count by accuracy (≤ 10 m: 4, ≤ 20 m: 3, ≤ 50 m: 2, > 50 m: 1, none: 0); filled `textPrimary`, empty `surfaceRaised`. The bars are decorative; the **word and number** carry the meaning.
   - Middle: "GPS · ±8 m" `callout` `monospacedDigit` `textPrimary`, then the word `caption` `textSecondary`: "Ready" (≤ 20 m), "Getting a fix" (> 20 m, or searching), "Weak signal" (> 50 m after 30 s).
   - Right: `location.fill` / `location` / `location.slash` (none).
   - Becoming ready crosses at ≤ 20 m horizontally for 3 consecutive updates (not a single lucky fix), so Start doesn't flicker. Hysteresis: ready is lost only above 30 m for 5 s.
4. **Today's strain as context** (`StatRow`-style single line, no card): "Today's strain so far  7.1" with a `ZoneBar`-less one-liner: `callout` `textSecondary` label, `StrainPill` value; shows "—" and "No strain yet today" if none. Never a target, band or recommendation.
5. **Record route toggle** (`Toggle` row, `Theme.accent` tint is the shipped toggle style): "Record route", sub-label `caption` `textSecondary`: on: "Saved with this activity. Privacy zones are applied before upload."; off: "Distance and pace are still recorded; the route isn't kept." Never preselected by RYFT: until the user has chosen once, this row is replaced by the first-Start question (4.1a); afterwards it starts from the remembered default (Settings). If privacy zones exist and the toggle is on, a second caption line "2 privacy zones active" with `lock.shield` `textTertiary`.
6. **Start** (`PrimaryButton(.primary)` custom large, 72 pt tall, full width, bottom pinned above the safe area, `headline` text "Start"). Disabled (`opacity 0.45`, shipped) until ready; while not ready, under it a text button "Start anyway" (`callout`, `textPrimary`, min 44) and a `caption` line "Waiting for GPS: accuracy 34 m, needs 20 m or better". "Start anyway" starts the recording; distance counts only fixes within the accuracy filter, so it begins when a good fix arrives (G4 line shows).
   When ready: the secondary line disappears and the button is active. A medium-impact haptic once when it turns ready (not under Reduce Motion? haptics are not motion; fine, once only).
- The map's camera move and accuracy-circle resize animate ≤ 250 ms; reduced motion: instant.

### 4.1a First Start of a GPS sport: ask once (P10)
The first time Start is tapped for any GPS sport (route choice not yet stored), Start does not begin recording; a bottom sheet (`.medium` detent, not dismissible by swipe: closing it returns to pre-start) asks:
- `headline` "Record your route?", `callout` `textSecondary`: "Distance and pace are recorded either way. A saved route lets you see the map later. It is uploaded only if you save the activity, and privacy zones are applied first. You can change this per activity and in Settings."
- Two buttons of **equal size, weight and style** (`PrimaryButton(.secondary)` both, 44+ pt, stacked, nothing preselected, no teal): **Record route** and **Don't record route**.
- The choice is stored as the default (Settings: "Record route by default", now showing the stored value) and the activity starts at once with it. The pre-start toggle then shows the stored value and stays changeable. A `caption` `textTertiary`: "You can change this in Settings."
- VoiceOver: sheet focus starts on the headline; the two buttons have no "recommended" trait. Indoor sports never see this.
Copy (en | de): "Record your route?" | "Route aufzeichnen?"; body | "Distanz und Tempo werden in jedem Fall erfasst. Eine gespeicherte Route zeigt dir später die Karte. Sie wird nur hochgeladen, wenn du die Aktivität sicherst, und Privatzonen werden vorher angewendet. Du kannst das pro Aktivität und in den Einstellungen ändern."; "Record route" | "Route aufzeichnen"; "Don't record route" | "Route nicht aufzeichnen"; "You can change this in Settings." | "Das kannst du in den Einstellungen ändern."

### 4.2 Indoor sports (P7)
No map, no GPS indicator, no toggle (route does not exist). Large sport icon (64 pt in a 112 pt circle, `accent.opacity(0.12)`), name `title`, under it `callout` `textSecondary` "Indoor. Steps from this iPhone's pedometer give distance." plus, if Motion & Fitness isn't allowed, a small card with the same pattern as the P8 pre-prompt. Today's strain line as in 4.1. Start is always active.
Pedometer unavailable (no hardware, denied): "Time only. Distance isn't available on this iPhone." and Start stays active.

### 4.3 Permission pre-prompt (P4)
Shown in place of the map when location is `notDetermined`; the screen shape is unchanged so the sheet does not jump.
- Icon `location` 28 pt in a 64 pt `accent.opacity(0.12)` circle (a normal info icon, not teal text), title `headline` "Use your location while you record", body `callout` `textSecondary`:
  "RYFT uses your location only while you record an activity, to measure distance, pace and your route. It stops when you finish. You choose per activity whether the route is saved."
- Primary: **Continue** (`PrimaryButton(.primary)`), which triggers the system prompt (When In Use). Secondary: **Not now** (text), which returns to the pre-start with "Record without GPS" available.
- A `caption` `textTertiary` line: "RYFT never asks for “Always” access."
- No dark pattern: "Not now" is the same size and has the same weight as a secondary button.

### 4.4 Denied or restricted (P5)
Same slot as the pre-prompt: `location.slash` `textTertiary`, `headline` "Location is off for RYFT", `callout`: "Without it, RYFT can't measure distance or pace outdoors. You can record time only, or turn location on in Settings." Buttons: **Open Settings** (`PrimaryButton(.secondary)`; `UIApplication.openSettingsURLString`) and **Record without GPS** (`PrimaryButton(.primary)`: Start becomes available; distance from steps for walking and running, else none; stored as a recording with no route, `Record route` hidden). Restricted (parental controls): "Location is restricted on this iPhone." only the second button.

### 4.5 Approximate location (P6)
Reduced accuracy: the indicator shows `location.slash`, "Precise Location is off", `callout`: "RYFT needs Precise Location to measure your distance." Buttons: **Open Settings**, **Start anyway** (which warns "Distance will be rough" in the recording as G4). Do not ask `requestTemporaryFullAccuracy` silently; the one call is behind a visible button "Turn on Precise Location" (which calls it with a purpose key; the architect confirms the Info.plist key).

### 4.6 Motion permission (P8)
Only for trail, hiking, MTB, ski touring. A single quiet row under the map: `mountain.2` glyph, "Elevation gain needs Motion & Fitness" with **Allow** (secondary text button). Allowing triggers the system prompt; "Skip" hides it for this session. The activity records without elevation otherwise and the recording screen's elevation tile shows "—" with the `caption` "Elevation needs Motion & Fitness". Strings for `NSMotionUsageDescription` (en | de) belong to the localization-editor.

### 4.7 Already recording (P9)
One card in place of everything: `record.circle` `textSecondary`, "A recording is in progress" `headline`, the running time, **Resume recording** primary. Start is not offered (one recording at a time).

### 4.8 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| title | Start activity | Aktivität starten |
| gps | GPS · ±%d m | GPS · ±%d m |
| ready / fix / weak | Ready · Getting a fix · Weak signal | Bereit · Suche Signal · Schwaches Signal |
| waiting | Waiting for GPS: accuracy %d m, needs 20 m or better | Warte auf GPS: Genauigkeit %d m, nötig sind 20 m oder besser |
| start | Start | Start |
| start anyway | Start anyway | Trotzdem starten |
| strain ctx | Today's strain so far | Strain bisher heute |
| no strain | No strain yet today | Heute noch kein Strain |
| route toggle | Record route | Route aufzeichnen |
| route on | Saved with this activity. Privacy zones are applied before upload. | Wird mit der Aktivität gespeichert. Privatzonen werden vor dem Upload angewendet. |
| route off | Distance and pace are still recorded; the route isn't kept. | Distanz und Tempo werden weiter erfasst, die Route wird nicht gespeichert. |
| zones active | %d privacy zones active | %d Privatzonen aktiv |
| indoor | Indoor. Steps from this iPhone's pedometer give distance. | Indoor. Die Schritte des iPhone-Schrittzählers ergeben die Distanz. |
| no pedometer | Time only. Distance isn't available on this iPhone. | Nur Zeit. Auf diesem iPhone ist keine Distanz verfügbar. |
| pre-prompt title | Use your location while you record | Standort nutzen, solange du aufzeichnest |
| pre-prompt body | RYFT uses your location only while you record an activity, to measure distance, pace and your route. It stops when you finish. You choose per activity whether the route is saved. | RYFT nutzt deinen Standort nur, solange du eine Aktivität aufzeichnest, um Distanz, Tempo und Route zu messen. Mit dem Beenden hört es auf. Du entscheidest pro Aktivität, ob die Route gespeichert wird. |
| continue / not now | Continue · Not now | Weiter · Nicht jetzt |
| never always | RYFT never asks for “Always” access. | RYFT fragt nie nach dem Zugriff „Immer“. |
| denied title | Location is off for RYFT | Der Standort ist für RYFT aus |
| denied body | Without it, RYFT can't measure distance or pace outdoors. You can record time only, or turn location on in Settings. | Ohne ihn kann RYFT draußen weder Distanz noch Tempo messen. Du kannst nur die Zeit aufzeichnen oder den Standort in den Einstellungen einschalten. |
| open settings | Open Settings | Einstellungen öffnen |
| no gps | Record without GPS | Ohne GPS aufzeichnen |
| restricted | Location is restricted on this iPhone. | Der Standort ist auf diesem iPhone eingeschränkt. |
| approx | Precise Location is off. RYFT needs it to measure your distance. | Genauer Standort ist aus. RYFT braucht ihn, um deine Distanz zu messen. |
| motion | Elevation gain needs Motion & Fitness | Für den Höhengewinn brauchst du „Bewegung & Fitness“ |
| allow / skip | Allow · Skip | Erlauben · Überspringen |
| in progress | A recording is in progress | Eine Aufzeichnung läuft |

### 4.9 VoiceOver and Dynamic Type
- Order: Close, sport, GPS indicator, strain line, Record route, Start (and Start anyway). The map is **one element** with the label "Map centred on you, accuracy 8 metres" and no hint; panning is not needed. The indicator is a single element "GPS accuracy 8 metres, ready" (and updates announce only on change between Ready, Getting a fix, Weak signal, not every metre).
- When Start becomes ready: announcement "GPS ready. You can start." once.
- AX sizes: the map shrinks to 180 pt, the sport row and the strain line wrap, Start stays 72 pt tall (grows with the label), all targets ≥ 44. Layout scrolls so nothing is cut at AX5.
- Light and dark: the map is the system style; the accuracy circle uses `accent` at 12 % + 1 pt edge so it shows on both.

---

## 5. Recording screen

Full-screen; replaces the pre-start in place (same cover). Status bar visible. **Screen stays awake** (`isIdleTimerDisabled`) while the screen is open and the recording is running or paused; not when the app is in the background (the system stops the timer). `showsBackgroundLocationIndicator` remains the system's blue pill.
Follows the system appearance; no forced dark (light is the better mode outdoors; open question 7). All numbers use `textPrimary`
(contrast ≥ 7:1 on both backgrounds: Mist on Graphite, Graphite on Mist). No `textTertiary` for anything essential. No translucency over the numbers.

### 5.1 Layout (G1)

Safe-area padding `screenPadding` 20. Top to bottom:
1. **Status row** (44 pt): left: sport icon + name `callout` `textSecondary`; right: **GPS chip** (a compact `GPSAccuracyIndicator`: 4 bars + "±8 m", `caption` `monospacedDigit`; tap opens the explanation in G4) and, when a sensor is paired, `heart.fill` + bpm (5.4). Under it a **state line**, `callout` (reserved height so numbers don't jump): empty while running; "Paused" with `pause.fill` for G2; "Auto-paused" with `pause.circle` for G3; the GPS lines for G4/G5.
2. **Primary number: time.** `ryftNumber(size: 76)` `monospacedDigit`, `textPrimary`, centred, label "TIME" above (`ryftLabelStyle()`). Moving time on the face; the full elapsed time in the detail. Updates every second from `Text(timerInterval:)` when running.
   - Dynamic Type: numbers scale with `@ScaledMetric(relativeTo: .largeTitle)` from 76 pt (AX5 → capped so "1:24:08" fits one line, `minimumScaleFactor(0.5)`).
3. **Secondary numbers**, a 2 × 2 grid (`Grid`, 1 pt `separator` rules between cells, no card fills, so the screen reads as an instrument):

   | Sport | Cells |
   | --- | --- |
   | Run, walk | Distance · Current pace · Avg pace · (lap or steps) |
   | Cycling, MTB, gravel | Distance · Speed · Avg speed · Elevation gain |
   | Trail, hiking, ski touring | Distance · Current pace · Avg pace · Elevation gain |
   | Indoor run, indoor cycling | Time-based: Distance (pedometer) · Current pace · Avg pace · Steps (run) / none (cycle) |
   | Rowing and other timed (no GPS) | Time · Active time · (only these two, centred) |

   Each cell: value `ryftNumber(size: 40)` `monospacedDigit` `textPrimary`; unit `callout` `textSecondary` next to it ("km", "/km"); label above `ryftLabelStyle()` ("DISTANCE", "PACE", "AVG PACE"). Distance shows 2 decimals ("5.21"); pace `m:ss`; speed 1 decimal.
   - Current pace is a 30 s rolling value. While it is stabilising (first 30 s) or paused: "–:–" (`textSecondary`), never `0:00`. Distance < 20 m: pace "–:–".
   - At AX sizes the 2 × 2 grid becomes 1 column, each cell full width, scrolls.
4. **Map** (toggle): **off by default**, a `map` toggle button in the controls row (44+ target) swaps the grid for the live map in the same space; the time stays. Map view: `RouteMap(.live)` with the route so far (4 pt Teal polyline with 7 pt `background` casing at 60 %), position dot, camera follows with heading, plus a compact row below with Distance and Pace (`ryftNumber(size: 32)`) so the essentials are never hidden. Turning the map off stops rendering it (battery). Reduced motion: no camera animation (jump).
5. **Controls row** (pinned bottom, `padding 20`, 24 pt above the safe area), three buttons on one line:
   - **Lap** (left, 64 pt circle, `surfaceRaised`, `flag` glyph `textPrimary` 24 pt, label `caption` under "Lap"): adds a lap and shows a 2 s toast row above the controls "Lap 3 · 1.00 km · 5:34" (`callout`, on `surface`, no animation under Reduce Motion). Hidden in indoor sports without distance.
   - **Pause / Resume** (centre, 96 pt circle). Running: `surface`-raised ring with `pause.fill` 36 pt `textPrimary`, label "Pause". Paused: `Theme.accent` fill with `play.fill` `onAccent`, label "Resume". This is the screen's one teal element.
   - **Stop** (right, 64 pt, long press, 5.2): `stop.fill` 24 pt, border 2 pt `textPrimary`, label "Hold to stop".
   - A map toggle (`map` / `chart.bar.xaxis` swap glyph) sits at the left of the status row (not in the controls row) so the three big buttons stay clear; target 44 × 44.
   - Button gaps ≥ 24 pt so gloved or sweaty taps don't hit a neighbour.

### 5.2 Hold to stop (`HoldToStopButton`, new, `Ryft/Features/Activities/HoldToStopButton.swift`)
- Press and hold 1.0 s. While held, a 3 pt Teal ring fills clockwise around the button (linear, 1.0 s, `Theme.accent`); release early cancels, the ring empties in 150 ms. Haptic: `.impact(.light)` at start, `.success` notification at completion. A tap shows a hint `callout` over the controls for 2 s "Hold to stop" (`textPrimary` on `surface`).
- At completion: confirmation is the finish summary itself (Discard has its own confirmation), so no second "Are you sure".
- Reduced motion: the ring fills in 4 discrete steps (25 % per 0.25 s), no easing.
- **Accessibility alternative:** VoiceOver and Switch Control users cannot long-press reliably. The button exposes `accessibilityAction(named: "Stop activity")` and a plain double-tap with VoiceOver on runs the stop after a native confirmation dialog "Stop and finish this activity?" **Stop** / **Keep recording** (`confirmationDialog`). Hint: "Double tap to stop. Asks first." `accessibilityAddTraits(.isButton)`.
- Shipped Train flow note: it ends sessions with a plain button; the long press is specific to a recording where accidental pocket taps cost data.

### 5.3 States

**G2 Paused (manual).** Time stops (shows the paused time, static); a state line "Paused" with `pause.fill`; the time stays `textPrimary` (contrast must stay) and gets a hairline underline 2 pt `textSecondary` under the time and the word "Paused", so the state isn't colour-only. Resume button Teal. The Live Activity shows paused (7).
**G3 Auto-paused.** Same layout with the line "Auto-paused · you stopped moving" (`pause.circle`). The time stops. Resume is automatic when speed returns for 3 s ("Resumed" line for 2 s) or by tapping the Resume button at any time. A manual pause during auto-pause becomes manual (it won't auto-resume). Both never fire audio during the pause.
**G4 GPS weak** (accuracy > 25 m for 10 s): state line `exclamationmark.circle` `Theme.warning` + `textSecondary` text "Weak GPS signal. Distance may be low." The GPS chip drops to 1 bar. When it recovers the line clears with a 250 ms cross-fade. Haptic `.warning` once, not repeated.
**G5 GPS lost** (no fix 15 s): "No GPS signal. Time keeps counting; distance resumes when it returns." The distance keeps its last value, labelled by the state line. The single line stays; no extra hints.
**G6 Permission revoked mid-activity:** line "Location was turned off. Distance and route stop." + **Open Settings** text button in the state line. Time continues.
**G10 Low battery:** `caption` line above the controls, `battery.25` glyph, "Low Power Mode is on. GPS updates are reduced." (Low Power Mode) or "Battery under 10 %. Finish soon to keep your activity." (≤ 10 %). Informational; shown once per level.
**Backgrounded / screen off:** nothing to design beyond the Live Activity.
**Interruptions** (phone call): the recording continues; no UI.

### 5.4 Heart rate
- **G7 live (flag `activity.live_hr`):** a separate full-width row between time and grid (the status row also shows `heart.fill` + bpm): "HEART RATE" label, value `ryftNumber(size: 40)` `monospacedDigit`, unit "bpm" and the zone word ("Zone 3") with the shipped zone colour dot AND text `caption` (colour not alone). Sensor name `caption` `textTertiary`: "Polar H10" (the BLE device name; it's the user's device).
- **G8 not live (default):** a calm line under the grid, `callout` `textSecondary`, `heart` glyph: "Heart rate is added after your tracker syncs." Hidden once HR arrives through the platform (not during recording).
- **G9 sensor lost:** line "Heart rate sensor disconnected. Reconnecting…" (`callout`, `exclamationmark.circle` warning); after 30 s reads "Heart rate sensor disconnected. Heart rate is added after your tracker syncs."
- The flag off: only G8 is ever shown.

### 5.5 Splits during the run
Not on the main face (outdoors, too small). Each km completion shows the 2 s toast "Km 3 · 5:34" like the lap toast, and the audio cue if on (6.3). Splits are read in the finish summary.

### 5.6 Motion
- Time ticks without animation (no count-up). State changes cross-fade 250 ms; the hold-to-stop ring is linear 1.0 s (functional, not decoration); the map camera follows with `Theme.Motion.quick`. Reduced motion: all off, ring stepwise.

### 5.7 VoiceOver and Dynamic Type
- Order: status (sport, GPS), state line (when present), time, distance, current pace, average pace, (elevation or HR), Lap, Pause/Resume, Hold to stop, map toggle. Each tile is one element "Distance, 5.21 kilometres". **The timer is not read every second**: `accessibilityLabel` "Time, 24 minutes 10 seconds" is static to the second only when focused; and updates announce nothing (`.updatesFrequently` trait).
- Announcements (`AccessibilityNotification.Announcement`): "Paused", "Resumed", "Auto-paused", "Lap 3, 5:34", "Kilometre 3, 16 minutes 42 seconds" at each km (this is on **independent** of the audio cue setting so a VoiceOver user gets splits; if audio cues are on and VoiceOver is on, only the audio cue speaks to avoid double speech).
- Map: one element, label "Route map. 5.21 kilometres so far." hint none; its text alternative is the numbers themselves, which are always on screen (the map swaps the grid for a compact distance/pace row).
- Dynamic Type: numbers use `ScaledMetric`; grid → single column from `accessibility1`; controls keep 64/96/64 minimum and the labels under them wrap; the view scrolls above the pinned controls. At AX5 the Pause button stays 96 pt and Lap/Stop 64 pt, with labels in `caption` below.
- Touch targets: Lap 64, Pause 96, Stop 64, map toggle 44, GPS chip 44 high. Nothing smaller.

### 5.8 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| labels | TIME · DISTANCE · PACE · AVG PACE · SPEED · AVG SPEED · ELEVATION GAIN · HEART RATE | ZEIT · DISTANZ · TEMPO · Ø TEMPO · GESCHWINDIGKEIT · Ø GESCHWINDIGKEIT · HÖHENMETER · HERZFREQUENZ |
| pause / resume / lap | Pause · Resume · Lap | Pause · Fortsetzen · Runde |
| hold to stop | Hold to stop | Zum Beenden halten |
| stop dialog (VoiceOver) | Stop and finish this activity? · Stop · Keep recording | Diese Aktivität beenden? · Beenden · Weiter aufzeichnen |
| paused | Paused | Pausiert |
| auto-paused | Auto-paused · you stopped moving | Automatisch pausiert · du bewegst dich nicht |
| resumed | Resumed | Fortgesetzt |
| gps weak | Weak GPS signal. Distance may be low. | Schwaches GPS-Signal. Die Distanz kann zu niedrig sein. |
| gps lost | No GPS signal. Time keeps counting; distance resumes when it returns. | Kein GPS-Signal. Die Zeit läuft weiter, die Distanz folgt, sobald das Signal zurück ist. |
| location off | Location was turned off. Distance and route stop. | Der Standort wurde ausgeschaltet. Distanz und Route stoppen. |
| hr not live | Heart rate is added after your tracker syncs. | Die Herzfrequenz wird ergänzt, sobald dein Tracker synchronisiert. |
| hr lost | Heart rate sensor disconnected. Reconnecting… | Herzfrequenz-Sensor getrennt. Verbinde neu … |
| low power | Low Power Mode is on. GPS updates are reduced. | Der Stromsparmodus ist an. GPS wird seltener aktualisiert. |
| low battery | Battery under 10 %. Finish soon to keep your activity. | Akku unter 10 %. Beende bald, damit deine Aktivität erhalten bleibt. |
| lap toast | Lap %d · %@ · %@ | Runde %d · %@ · %@ |
| km toast | Km %d · %@ | Km %d · %@ |

---

## 6. Live Activity and Dynamic Island

New widget `ActivityTrackingLiveActivity` in `RyftWidgets/ActivityTrackingLiveActivity.swift`, attributes in
`RyftWidgets/ActivityTrackingAttributes.swift`. It reuses the rest timer's look exactly: `Brand` colours (Graphite
background, Mist text, Teal accent), `.rounded` bold monospaced numerals, the tracked caption label ("RUN" like "REST"), the `Open` capsule,
`widgetURL`, `keylineTint(Brand.teal)`. The app's mirror of the attributes goes into the existing app file next to `RestActivity`
(`Ryft/Train/RestActivity.swift`, per its comment; the two must stay Codable-identical).

**Attributes / state (design needs; architect confirms):**
- `RecordingAttributes` (names as `design.md` §6): static `activityID: UUID`, `sport: String` (raw), `title`, `symbol`, `startedAt`.
- `ContentState`: `phase` (recording, paused, autoPaused), `movingAnchor: Date?`, `pausedMovingSec: Double`, `distanceM`, `pace: Double?` / `speedKmh: Double?`, `updatedAt`. Weak GPS and stale are shown from `updatedAt` age (`staleDate` +90 s), not a separate field.
- The timer runs by itself: `Text(timerInterval:pauseTime:)` from `movingAnchor`/`pausedMovingSec`; paused is static text. App pushes distance and pace at most every 10 s or 50 m (whichever first, battery); no location or place name ever goes into the activity.

**Lock screen / banner** (as `LockScreenView`, padding 16, `Brand.graphite`):
- Top: label "RUN" (`caption2.weight(.semibold)`, tracking 2, Teal) with the sport symbol; paused: "PAUSED" (the label word changes; glyph `pause.fill`), auto-paused "AUTO-PAUSED". Right: timer `size 40 .semibold .rounded` Mist, `monospacedDigit`; paused: static, `Brand.mist.opacity(0.6)` plus the word.
- Middle row: two columns separated by a 1 pt `Mist 15 %` rule: Distance "5.21 km" and Pace "5:34 /km" (cycling: "Speed 24.8 km/h"), values `title3` `.rounded` `.semibold` Mist, labels `caption2` tracking 1.2 `Mist 60 %` ("DISTANCE", "PACE").
- Bottom: `Open` capsule (shipped `DoneLink` look) deep link `ryft://activity/recording`. Always `Open` only: **no Pause, Resume or Stop controls in v1** (plan decision 3); resuming happens in the app.
- GPS weak: Pace shows "–:–" and a `exclamationmark.circle` + "Weak GPS" `caption` in Mist 60 %. L3 stale (`isStale`): the metrics dim to Mist 40 %, line "Open RYFT to keep recording" (`callout`) and `Open` capsule; the recorder is system-protected, but the activity can't update.

**Dynamic Island expanded:**
- Leading: `Label(sport, symbol)` `caption.weight(.semibold)` Teal (paused: `pause.fill` + "Paused").
- Trailing: timer `size 28 .semibold .rounded`, max width 110, like the rest timer.
- Bottom: `HStack`: distance `callout` "5.21 km", pace `callout` "5:34 /km", `Spacer`, the `Open` capsule. Values Mist; labels omitted (compact space; the units say what they are).
**Compact:** leading the sport symbol (Teal; paused: `pause.fill`); trailing the elapsed timer `.body .rounded .semibold`, `maxWidth: 56`; for sessions over 59:59 it switches to `h:mm` (static `Text` updated by the app each minute) to fit.
**Minimal:** the sport symbol, Teal; paused `pause.fill`. (Weak GPS: nothing extra; no glyph clutter.)
Light mode: the Island is always dark; the lock screen banner uses `activityBackgroundTint(Brand.graphite)` in both schemes like the rest timer.

**Dynamic Type:** lock screen scales with `font(.system(..))` text styles; at AX sizes the middle row stacks vertically; the banner is height-limited by the system, so the Pace column is dropped before the timer or distance (priority time, distance, pace).
**VoiceOver:** lock screen one element per group: "Run, 24 minutes 10 seconds, 5.21 kilometres, pace 5 minutes 34 per kilometre". Paused: "Run, paused, 24 minutes 10 seconds, 5.21 kilometres". Island similar. `Text(timerInterval:)` is spoken as a timer by the system.
**Motion:** none of our own; the system animates the Island. The `Text(timerInterval:)` ticking is not an animation.

### 6.1 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| labels | RUN · RIDE · WALK · HIKE · ACTIVITY | LAUF · RAD · GEHEN · WANDERN · AKTIVITÄT |
| paused | PAUSED · AUTO-PAUSED | PAUSIERT · AUTOMATISCH PAUSIERT |
| metrics | DISTANCE · PACE · SPEED | DISTANZ · TEMPO · TEMPO |
| weak | Weak GPS | Schwaches GPS |
| stale | Open RYFT to keep recording | Öffne RYFT, um weiter aufzuzeichnen |
| buttons | Open | Öffnen |

---

## 7. Finish summary

Appears when Stop completes (cover replaces the recording; the recording state is already checkpointed, so nothing is lost
if the app dies here). Navigation title "Activity summary" inline, no back (the choices are Save or Discard).

### 7.1 Layout (Z1)
1. **Header:** sport icon circle (64 pt like `WorkoutDetailView`), name `title`, `callout` `textSecondary` "Thursday 22 Oct · 07:12–07:48".
2. **Map** (`RouteMap(.summary)`, `cardRadius`, 220 pt, fits the route with padding 24): Teal 4 pt polyline with casing, hollow start dot, filled finish dot, km ticks every km (small 6 pt `Mist` dots only; no text). Non-interactive; tap opens it full-screen for inspection. If a privacy zone is active: its circle dashed 1.5 pt `textSecondary`, with the caption "The route is trimmed inside privacy zones before upload." The route shown here follows the stored choice for this activity (4.1a), never a RYFT default. If route off: replaced by a muted card `map` + "Route not recorded" (D2). No route and no GPS (indoor): nothing here.
3. **Stat grid** (shipped `WorkoutDetailView` 3-column stat tile pattern): DISTANCE, TIME (moving), AVG PACE (or SPEED); second row: ELAPSED if different from moving ("0:36:20 · 36:02 moving"), ELEVATION ↑, ↓ (when available). Values `headline` `monospacedDigit`.
4. **Splits** (`SplitsTable`, new, `Ryft/Features/Activities/SplitsTable.swift`), `Card` with `CardHeader("Splits")`: one row per km (last partial row "0.21 km"): columns Km · Pace · bar · Elev. Pace `body` `monospacedDigit`; the bar is a 6 pt tall capsule scaled to the pace relative to the fastest, `Theme.accent` for all (single hue; the **fastest** row gets the text "Fastest" `caption` after the number, and the slowest nothing). Elevation delta "+8 m" `caption` `textSecondary`. Hairlines between rows. Header row labels `ryftLabelStyle`. Over 20 km: collapses to the first 10 and "Show all 32" button.
5. **Effort** (`EffortScale`, as 3.3), optional, labelled "How hard did it feel?" 
6. **Notes** (multiline, as 3.1).
7. **Privacy zone suggestion** (Z6, only on the first route save while no zone exists and not dismissed twice): a `Card` with `hairline` border, `lock.shield` `textSecondary`, `headline` "Hide where you start and finish?", `callout`: "A privacy zone removes every part of the route inside its circle, before upload and export. You can add more places in Settings." Radius segmented picker 200 m / 300 m / 400 m / 500 m, **400 m preselected**. Buttons: **Add start as zone** (`PrimaryButton(.secondary)`) and **Not now** (text). Adding it re-draws the map trimmed. It is an offer, not a gate.
8. **Actions** (pinned bottom): **Save** (`PrimaryButton(.primary)`, 56 pt) and **Discard** (text button, `Theme.alert` text, 44 min, below). Discard opens a `confirmationDialog` (Z7): "Discard this activity?" message "The recording and its route will be deleted from this iPhone. This can't be undone." Buttons **Discard** (destructive), **Keep** (cancel). At the dialog the route is not yet deleted.

### 7.2 States
- **Z2 too short** (< 10 s or < 20 m): a `callout` note at the top "That was very short. Save it anyway?" with Discard becoming the visible secondary (`PrimaryButton(.secondary)`, `alert` text) and Save still primary.
- **Z3 saving:** Save becomes "Saving…" (disabled, `textTertiary` per shipped `retryingTitle` pattern, no spinner) for the local write (~100 ms); then the cover closes (cross-fade 250 ms) back to My Day, where the new row shows R1.
- **Z4 queued offline:** closes the same; the row shows R1 "Uploading" with the cloud; the detail says "Saved on this iPhone. It will upload when you're online." No modal, no banner on the summary (it already closed). If the user opens the summary while offline, a quiet `caption` under Save: "You're offline. It will upload later."
- **Z5 local failure** (SwiftData write failed, storage full): the summary stays; `InlineMessage` "Couldn't save on this iPhone. Free up space and try again." with **Try again** and **Details**; the recording stays checkpointed; Discard still gated by confirmation. Never auto-discard.
- Saving to Apple Health (opt-in setting, brief §3): a `Toggle` row "Also save to Apple Health" shown only if the user opted in in Settings; default on; `caption`: "Adds a workout with the route to Health." Otherwise not shown.

### 7.3 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| title | Activity summary | Zusammenfassung |
| splits | Splits | Zwischenzeiten |
| fastest | Fastest | Schnellster |
| show all | Show all %d | Alle %d anzeigen |
| effort | How hard did it feel? | Wie anstrengend war es? |
| zone title | Hide where you start and finish? | Start und Ziel verbergen? |
| zone body | A privacy zone removes every part of the route inside its circle, before upload and export. You can add more places in Settings. | Eine Privatzone entfernt jeden Teil der Route innerhalb ihres Kreises, vor Upload und Export. Weitere Orte fügst du in den Einstellungen hinzu. |
| add start zone | Add start as zone | Start als Zone hinzufügen |
| not now | Not now | Nicht jetzt |
| route trimmed | The route is trimmed inside privacy zones before upload. | Die Route wird in Privatzonen vor dem Upload gekürzt. |
| no route | Route not recorded | Route nicht aufgezeichnet |
| short | That was very short. Save it anyway? | Das war sehr kurz. Trotzdem speichern? |
| save / saving | Save · Saving… | Sichern · Sichere … |
| discard | Discard | Verwerfen |
| discard title | Discard this activity? | Diese Aktivität verwerfen? |
| discard msg | The recording and its route will be deleted from this iPhone. This can't be undone. | Aufzeichnung und Route werden von diesem iPhone gelöscht. Das lässt sich nicht rückgängig machen. |
| keep | Keep | Behalten |
| offline | You're offline. It will upload later. | Du bist offline. Der Upload folgt später. |
| local fail | Couldn't save on this iPhone. Free up space and try again. | Auf diesem iPhone konnte nicht gespeichert werden. Schaffe Platz und versuche es erneut. |
| to health | Also save to Apple Health | Auch in Apple Health sichern |
| to health sub | Adds a workout with the route to Health. | Fügt Health ein Workout mit der Route hinzu. |

### 7.4 VoiceOver and Dynamic Type
- Order: header (one element), map (text alternative, below), stats, splits (table as rows "Kilometre 1, 5 minutes 34 per km, plus 8 metres"; the table's `accessibilityElement(children: .contain)` with `accessibilityLabel("Splits")`), effort, notes, privacy suggestion, Save, Discard.
- **Map alternative:** label "Route map. 5.21 kilometres, out and back. Start and finish 120 metres apart." (computed: out-and-back, loop, one way by comparing start and end distance) + `accessibilityHint` none; the splits table carries the pace detail. The map itself is `accessibilityElement` with `.isImage`.
- AX sizes: stat grid 1 column; splits rows stack pace under km; Save and Discard stack, both ≥ 44 pt high; the page scrolls and the buttons are pinned (safe-area inset) except at AX5 where they scroll with content so the keyboard never covers Save.

---

## 8. Activity detail

Pushed from a My Day row (`NavigationLink`), nav bar inline with the activity name, trailing `ellipsis.circle` menu: **Edit** (`pencil`) and **Delete** (`trash`, destructive) for manual and recorded; none for Apple Health/tracker workouts (the shipped `WorkoutDetailView` stays for those). The new view `ActivityDetailView` (`Ryft/Features/Activities/ActivityDetailView.swift`); both use the same stat grid and `ChartHeader` components.

### 8.1 Sections (D1, scrolling, `sectionSpacing` 24)
1. **Header** (as `WorkoutDetailView.header`): icon circle, name `title`, date and time range `callout`, source badges row (centred), and for R1/R4 a state `InlineMessage` right under it (2.4 copy).
2. **Stat grid:** DISTANCE, DURATION (moving), AVG PACE or SPEED, ASCENT, AVG HR (when HR), STRAIN (pill). Values only where they exist.
3. **Strain card (always, one `Card`):**
   - D5 `heart_rate`: `ChartHeader`-style row "STRAIN" label, value `numberLarge` `StrainPill`-colour (`metricStrain` text, as charts), and the source line `callout` `textSecondary` with `heart.fill`: "Heart rate from Garmin Connect" (the platform's `hr_source`; `hr_source` is a friendly name from `trackers.json` once #33 lands; BLE sensor: "Heart rate from your sensor").
   - D6 `perceived_effort`: "From your effort rating (6 of 10). Strain becomes more precise when heart rate arrives." with a `pencil` glyph in `textSecondary`.
   - D7 `none`: hollow dot + "No heart rate for this time. Strain appears after your tracker syncs." or when scored with no HR: `minus.circle` + "No heart rate for this time."
   - R1/R2: hollow dot + "Waiting for heart rate".
4. **Map** (`RouteMap(.detail)`), 260 pt, with a Full screen button (`arrow.up.left.and.arrow.down.right` 44 pt). Scrubbing: dragging along the pace or elevation chart moves a 10 pt `Mist`-ring dot on the route (and vice versa is not required). D2: a muted card "Route not recorded" (`map`, `callout`).
5. **Splits** (`SplitsTable` as 7.1, plus an average-HR column "HR" when HR exists).
6. **Pace chart** (`Card`, `ChartHeader` with metric `.pace` as a new `MetricSpec` (id `pace`, unit "/km", colour: Accent, polarity: lower is better, scale: auto)): x = distance (km, ticks per km), y trailing, **reversed so faster is up** with the label "faster ↑" at the axis top in `axis` type; 1.5 pt linear line, 30 s smoothing already applied, dashed average rule "avg 5:34", markers only for the fastest point (hollow) and the selected one; gridlines `separator` 0.5 pt; the top tick carries the unit. For cycling: Speed, higher up, same rules. Windowed scrub with the standard `ScrubReadout`.
7. **Elevation chart** (`Card`, `ChartHeader` "ELEVATION", ascent and descent): line 1.5 pt, area fill ≤ 6 % (allowed by CHART_STYLE), `MetricSpec.elevation` colour `accentSecondary` (Sage), y in metres, x distance. Shown only when `ascent_m` or an altitude series exists.
8. **Heart rate** (only when the platform has HR for the window): the shipped `HeartRateChart` and `ZoneBar` ("Heart-rate zones") `Card`s as in `WorkoutDetailView`, avg HR and peak marker, zone minutes with words. Not shown without HR (no empty chart): replaced by the line in the Strain card.
9. **Merge note (D4):** `info.circle` `textSecondary` text "Merged from two sources: heart rate from Garmin Connect, route and distance from RYFT. RYFT counts this activity once." No action (open question 6: unmerge).
10. **Notes** (when present): `Card` "Notes", `body` `textPrimary`; "Add a note" text button if empty and editable.
11. **Footer** (editable only): **Edit** (`PrimaryButton(.secondary)`) and **Delete** (text, `alert`). Delete confirmation (D10): title "Delete this activity?" message "It's removed from RYFT, including its route, and your strain for the day is recalculated." (recorded) / "…It's removed from RYFT and your strain for the day is recalculated." (manual). Buttons **Delete** (destructive) / **Keep**.

**Account deletion confirmation** (Profile, existing flow; add one line to it): en: "Workouts RYFT saved to Apple Health stay there. You can delete them in the Health app." · de: "Trainings, die RYFT in Apple Health gesichert hat, bleiben dort. Du kannst sie in der Health-App löschen." (design.md §5)

**Edit rules:** manual: all fields (sheet from §3, title "Edit activity", Save). Recorded: sport, effort and notes editable; times and distance are measured, not editable (copy "Measured by RYFT. Times and distance can't be changed."); delete only. Editing an uploaded item updates `client_updated_at`; shows R1 until confirmed again. Merged items: only notes/effort.

**D8 strength:** Train sessions open the existing session summary (`TrainRoute.session`) via the row; no `ActivityDetailView`. A manual Strength activity (no sets) opens `ActivityDetailView` without map, charts or splits, with the stat grid duration, effort, and the suggestion card from 3.4 "Log this in Train" (`PrimaryButton(.secondary)`, opens the Train log flow) at the top.

### 8.1a Route removed after 30 days (D11)
A route is kept on the phone for at most 30 days if it hasn't been confirmed as uploaded. After that it is removed; distance, time and splits stay.
- **Detail:** in the map's place a muted card (`map` glyph `textTertiary`, `callout` `textSecondary`): "The route of this activity wasn't uploaded within 30 days and was removed from your phone. Distance and splits are kept." de: "Die Route dieser Aktivität wurde nicht innerhalb von 30 Tagen hochgeladen und von deinem iPhone entfernt. Distanz und Zwischenzeiten bleiben erhalten." No action; `info.circle` glyph.
- **Row (My Day, full screen only; the card shows no extra line):** a fourth line, `caption` `textSecondary` with `map` glyph: "Route removed after 30 days" | "Route nach 30 Tagen entfernt". Detail row only on the day shown; shown once, no badge or colour.
- Before the 30 days (route still on the phone, upload pending/failed): the R1/R4 detail adds "The route is removed from this iPhone after 30 days if it isn't uploaded." | "Die Route wird nach 30 Tagen von diesem iPhone entfernt, wenn sie nicht hochgeladen ist."
- VoiceOver: the row label ends "route removed after 30 days"; the detail card is read as text.

### 8.1b Withheld route: review sheet (D12)
A route is **withheld** when the activity was recorded with privacy zones but the account has none now (`design.md` §8.2). The activity uploaded without the route; nothing sends it automatically.
- **Row and detail:** line `caption` `textSecondary` with `lock.shield`: "Route not sent · Review" | "Route nicht gesendet · Prüfen" (a text button, 44 pt). In the detail the map card shows the same line and the button.
- **Review sheet** (`.medium` detent, title "Route not sent"): `callout` `textSecondary`: "You recorded this activity with privacy zones, but you have none now. RYFT didn't send the route." | "Du hast diese Aktivität mit Privatzonen aufgezeichnet, hast aber jetzt keine. RYFT hat die Route nicht gesendet." A small non-interactive `RouteMap(.summary)` of the stored (already trimmed) route.
- **Choices**, equal weight, stacked, nothing preselected, no teal:
  1. **Send the route as recorded** | "Route wie aufgezeichnet senden": `caption`: "It was trimmed by your privacy zones when you recorded it." | "Sie wurde beim Aufzeichnen durch deine Privatzonen gekürzt."
  2. **Add your zones again** | "Zonen erneut hinzufügen": opens Privacy zones; after adding, the route is re-trimmed and the sheet returns. `caption`: "The route is trimmed again, then sent." | "Die Route wird erneut gekürzt und dann gesendet."
  3. **Send without the route** | "Ohne Route senden": `caption`: "Distance and splits are kept." | "Distanz und Zwischenzeiten bleiben erhalten." Removes the route from this iPhone after confirmation ("Remove the route from this iPhone? This can't be undone." | "Route von diesem iPhone entfernen? Das lässt sich nicht rückgängig machen.").
  Cancel (text): "Decide later" | "Später entscheiden" (the row keeps the line).
- **States:** *sending* (the chosen button shows "Sending…" | "Sende …", disabled, no spinner; others disabled); *sent* (sheet closes, line disappears, the row shows R1 then the usual state); *offline* (choice is stored, "It will be sent when you're online." | "Sie wird gesendet, sobald du online bist."); *failed* (`InlineMessage` "Couldn't send the route. It is still on this iPhone." | "Die Route konnte nicht gesendet werden. Sie ist weiterhin auf diesem iPhone." with Try again, Details).
- VoiceOver: focus on the title; each choice reads its caption as hint; the map is "Route map, already trimmed by your privacy zones." AX: buttons full width, scroll.

### 8.2 States
- Loading: outline placeholders for each card (same size, no spinner), stat values `Fmt.placeholder`.
- Offline with cached: show the cache and `caption` "Showing what's saved on this iPhone."
- Charts unavailable (no series): the card says why in `callout` `textTertiary` ("No pace data for this activity.") like the shipped "No heart-rate series available…" line.

### 8.3 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| edit / delete | Edit · Delete | Bearbeiten · Löschen |
| hr source | Heart rate from %@ | Herzfrequenz von %@ |
| hr sensor | Heart rate from your sensor | Herzfrequenz von deinem Sensor |
| effort strain | From your effort rating (%d of 10). Strain becomes more precise when heart rate arrives. | Aus deiner Anstrengung (%d von 10). Strain wird genauer, sobald Herzfrequenz vorliegt. |
| no hr | No heart rate for this time. Strain appears after your tracker syncs. | Keine Herzfrequenz für diese Zeit. Strain erscheint, sobald dein Tracker synchronisiert. |
| no hr scored | No heart rate for this time. | Keine Herzfrequenz für diese Zeit. |
| waiting hr | Waiting for heart rate | Warte auf Herzfrequenz |
| pace chart | Pace | Tempo |
| faster | faster | schneller |
| elevation | Elevation | Höhe |
| merged | Merged from two sources: heart rate from %@, route and distance from RYFT. RYFT counts this activity once. | Aus zwei Quellen zusammengeführt: Herzfrequenz von %@, Route und Distanz von RYFT. RYFT zählt diese Aktivität nur einmal. |
| measured | Measured by RYFT. Times and distance can't be changed. | Von RYFT gemessen. Zeiten und Distanz lassen sich nicht ändern. |
| delete title | Delete this activity? | Diese Aktivität löschen? |
| delete rec | It's removed from RYFT, including its route, and your strain for the day is recalculated. If it was saved to Apple Health: "Its copy in Apple Health is deleted too." (de: "Auch die Kopie in Apple Health wird gelöscht.") If RYFT can no longer write to Apple Health: "The copy in Apple Health stays; delete it in the Health app." (de: "Die Kopie in Apple Health bleibt; lösche sie in der Health-App.") | Sie wird aus RYFT entfernt, einschließlich ihrer Route, und dein Tages-Strain wird neu berechnet. |
| delete man | It's removed from RYFT and your strain for the day is recalculated. (Manual entries aren't saved to Apple Health, so no Health sentence; see design.md §5.) | Sie wird aus RYFT entfernt und dein Tages-Strain wird neu berechnet. |
| cached | Showing what's saved on this iPhone. | Zeigt, was auf diesem iPhone gespeichert ist. |
| no route | Route not recorded | Route nicht aufgezeichnet |
| log in train | Log this in Train | In Train erfassen |

### 8.4 VoiceOver and Dynamic Type
- Order: header, state message, stats, strain, map (alternative text per 7.4), splits, pace chart, elevation chart, HR, zones, merge note, notes, Edit, Delete.
- **Charts:** each `Chart` gets `accessibilityChartDescriptor` through the shipped `SeriesChartDescriptor` (audio graph), with a one-sentence summary label first: "Pace chart. Average 5:34 per kilometre, fastest kilometre 3 at 5:12, slowest kilometre 5 at 5:51." Elevation: "Elevation chart. 84 metres up, 79 down, highest point 212 metres." HR as shipped.
- AX sizes: stat grid 1 column, charts keep 200 pt min height and their axis tick count falls from 5 to 3 (shipped chart behaviour); splits stack; the map stays 260 pt but "Full screen" is always visible.
- Dark and light: route casing is `background` at 60 % so the Teal line has contrast on every map tile; map style is system `muted`.

---

## 9. "Resume your run?" (U1, U2)

Follows `design.md` §3.9 and the security review:
- **Background relaunch** (the system relaunched the app for location): resumes by itself only within 10 min of the last checkpoint, with no question; the recording screen shows for 2 s "Resumed after a break of 4 min". Over 10 min, it waits for the user at the next foreground launch (below).
- **Foreground launch** (force-quit, crash): always asks, a full-screen cover over Today (not an alert), `interactiveDismissDisabled`.
- **Resume** is offered only when the gap is under 6 h **and** on the same calendar day as the last checkpoint. Otherwise only **Finish** and **Discard**, and the title is "Finish your run?". RYFT never promises to resume after hours.
- **The gap:** The gap across a restart is never bridged: the time from the last saved point to the resume counts as a pause and adds no distance (route on or off; indoor, steps are re-counted from the pedometer). See design.md §3.9.

Layout, centred top to bottom:
- The sport icon circle (64 pt).
- Title `title`: "Resume your run?" when Resume is offered, else "Finish your run?" (sport word swaps: run, ride, walk, hike, activity).
- A small card (`Theme.surface`) of facts, `StatRow`s: "Started 07:12", "Last saved 07:48", "Distance so far 5.21 km", "Time so far 36:02". All from the checkpoint (30 s granularity).
- `callout` `textSecondary`: "RYFT stopped recording at 07:48, when the app was closed. It can't continue from there, but nothing recorded until then is lost."
- **Finish**: the finish summary with the data up to the last checkpoint.
- **Discard** (text button, `Theme.alert`): confirmation dialog as 7.1 (same copy).
- **Resume** (`PrimaryButton(.primary)`, only when offered): continues the same recording at the saved distance; the gap isn't counted. **Finish** is then `PrimaryButton(.secondary)`; when Resume isn't offered Finish is primary.
- Never auto-discards. If neither is chosen, the cover appears again on the next launch.
- A store that can't be read: `InlineMessage` "RYFT couldn't read the saved recording." with **Details**; the data stays untouched.

**Copy (en | de):**
| Key | en | de |
| --- | --- | --- |
| title | Resume your %@? · Finish your %@? | %@ fortsetzen? · %@ beenden? |
| sport word | run · ride · walk · hike · activity | Lauf · Fahrt · Spaziergang · Wanderung · Aktivität |
| facts | Started · Last saved · Distance so far · Time so far | Gestartet · Zuletzt gesichert · Bisherige Distanz · Bisherige Zeit |
| body | RYFT stopped recording at %@, when the app was closed. It can't continue from there, but nothing recorded until then is lost. | RYFT hat um %@ aufgehört aufzuzeichnen, als die App beendet wurde. Es kann von dort nicht weitergehen, aber nichts bis dahin Aufgezeichnetes geht verloren. |
| resume / finish / discard | Resume · Finish with what was saved · Discard | Fortsetzen · Mit dem Gesicherten beenden · Verwerfen |
| auto line | Resumed after a break of %@ | Nach %@ Pause fortgesetzt |
| unreadable | RYFT couldn't read the saved recording. | RYFT konnte die gesicherte Aufzeichnung nicht lesen. |

VoiceOver: focus starts on the title; facts are read as one element each; the gap sentence follows; the primary button is
first among the buttons. AX sizes: facts rows stack, buttons stack, the whole screen scrolls.

---

## 10. Settings

A new section **Activities** in Profile, between Notifications and Data (`ProfileView.swift`; rows as the shipped Profile rows, `Card` groups, toggles tinted `Theme.accent`). A pushed `ActivitySettingsView` holds the detail.

| Row | Control | Default | en | de |
| --- | --- | --- | --- | --- |
| Auto-pause | Toggle; sub-label | on for running and cycling, off for walking, hiking | "Auto-pause" / "Pauses the timer when you stop moving." | "Automatische Pause" / "Hält die Zeit an, wenn du stehen bleibst." |
| Audio cues | Toggle + sub-picker "Every kilometre" (locale: mile) | off | "Audio cues" / "Speaks your distance, time and pace at each kilometre." | "Sprachansagen" / "Sagt bei jedem Kilometer Distanz, Zeit und Tempo an." |
| Record route by default | Toggle, set by the first-Start question (4.1a); until then shown as "Not chosen yet" and not a toggle | not chosen (no default) | "Record route by default" / "You can change it for each activity." | "Route standardmäßig aufzeichnen" / "Das kannst du für jede Aktivität ändern." |
| Privacy zones | chevron row, value "2 places" | none | "Privacy zones" / "Hide where you start and finish." | "Privatzonen" / "Verberge, wo du startest und aufhörst." |
| Heart-rate sensor | chevron row, value name/"Not connected" (flag `activity.live_hr`; hidden when off) | none | "Heart-rate sensor" / "Show live heart rate while you record." | "Herzfrequenz-Sensor" / "Zeigt die Herzfrequenz live beim Aufzeichnen." |
| Save to Apple Health | follows the existing workouts opt-in (shown only if on) | — | "Save activities to Apple Health" | "Aktivitäten in Apple Health sichern" |

Audio cues sub-settings: **Language** follows the app language (en/de), no picker; the phrase: en "Kilometre 3. Time 16 minutes 42. Pace 5 minutes 34 per kilometre."
; de "Kilometer 3. Zeit 16 Minuten 42. Tempo 5 Minuten 34 pro Kilometer." Ducking other audio (`.duckOthers`, no ducking and no cue while a call is active); respects the silent switch? Cues use the playback category so they speak in silent mode (engineer to confirm; sub-label "Plays over your music").
A "Test" text button plays a sample phrase ("Play a sample" / "Beispiel abspielen").

**Privacy zones screen (T2):**
- Intro `callout` `textSecondary`: "RYFT removes every part of a route inside these circles before upload and before any export. Your activity's distance and time are unchanged."
- List: each zone: place name (the user types a label like "Home"; default "Zone 1"), radius, a `Map` thumbnail 56 pt; swipe and context menu **Delete**.
- **Add place** (`PrimaryButton(.secondary)`): a sheet with a map and a movable pin ("Move the map to the place"), options "Use my current location" and a label field, a **radius** control with four detents **200 m · 300 m · 400 m · 500 m** (segmented, **400 m preselected**; the circle is drawn on the map, dashed 1.5 pt `textSecondary`, fill `accent` 10 %). Save adds it. Max 5 zones ("You can have up to 5 privacy zones.").
- Empty: `lock.shield` `textTertiary` "No privacy zones yet" + `callout` "Add your home or workplace so routes don't show where you live or work."
- Zones are stored on the device only and never uploaded (copy line "Stored on this iPhone only.").
- Footer `caption` `textTertiary`: "A zone applies to routes not yet uploaded. Routes you already uploaded aren't changed." **Editing a zone's place or radius replaces the zone** (the old one is removed, a new one created); the edit sheet says so: "Changing the place or radius replaces this zone." | "Wenn du Ort oder Radius änderst, ersetzt das diese Zone." Same footer in de: "Eine Zone gilt für Routen, die noch nicht hochgeladen sind. Bereits hochgeladene Routen ändern sich nicht."

**S8: zones couldn't be restored.** After a restore to a new iPhone the zones can't be opened, so the route default resets to "not chosen" (4.1a asks again). Notice: "Your privacy zones couldn't be restored on this iPhone. Add them again." | "Deine Privatzonen konnten auf diesem iPhone nicht wiederhergestellt werden. Füge sie erneut hinzu." Shown (1) at the top of Settings → Privacy zones as a persistent info block (`info.circle`, `callout` `textSecondary`, with **Add place**), until a zone exists or the user dismisses it; (2) **once** on the next GPS Start, as a short sheet before the route question (4.1a) with **Add zone** and **Continue without** (equal size). Not red; VoiceOver reads it as text.

**Heart-rate sensor screen:** scan list of BLE devices exposing the Heart Rate service (name, signal bars with a word "Strong/OK/Weak", "Connect"), connected state `checkmark.circle.fill` `accent` + "Connected" + "Forget". Empty: "No sensors found. Put on your sensor and keep it close." Bluetooth permission pre-prompt (same pattern as 4.3): "RYFT connects to your heart-rate sensor over Bluetooth while you record." (de "RYFT verbindet sich mit deinem Herzfrequenz-Sensor über Bluetooth, solange du aufzeichnest."). Denied: **Open Settings**.

**VoiceOver and AX:** every toggle has its sub-label as `accessibilityValue`/hint; the zone list rows read "Home, 300 metres"; the add-place map has the text alternative "Map. Zone centred at the pin. Radius 300 metres" and a coordinates-free instruction: "Use my current location" is the accessible path, so the map drag is never required. At AX sizes rows stack label above value; the radius control becomes a vertical list of four buttons.

---

## 11. Components

| Component | Folder | Notes |
| --- | --- | --- |
| `SourceBadge`, `SourceBadges`, `FlowLayout` | `Ryft/Design/SourceBadge.swift` | tokens only; previews dark/light/AX3, two badges |
| `ActivityStateMark` | `Ryft/Design/ActivityStateMark.swift` | R1 to R5; uses `StrainPill` (stays in StrainComponents) |
| `EffortScale` | `Ryft/Design/EffortScale.swift` | adjustable, 2 × 5 grid, 3 columns at AX |
| `GPSAccuracyIndicator` | `Ryft/Design/GPSAccuracyIndicator.swift` | full and compact |
| `RouteMap` (`.live`, `.summary`, `.detail`) | `Ryft/Design/RouteMap.swift` | MapKit `Map`, `MapPolyline`, no new dependency; takes `[CLLocationCoordinate2D]`, zones; text alternative built in |
| `DateStrip` (renamed from `JournalDateStrip`) | `Ryft/Design/DateStrip.swift` | rename and move only |
| `MyDayCard`, `MyDayRow`, `MyDayView`, `MyDayViewModel` | `Ryft/Features/MyDay/` | row used by card and full-screen |
| `AddActivitySheet`, `AddSleepSheet`, `SportPicker`, `SportCatalogue` | `Ryft/Features/Activities/` | |
| `PreStartView`, `LocationPrePrompt`, `RecordingView`, `HoldToStopButton`, `BigStat` | `Ryft/Features/Activities/` | |
| `FinishSummaryView`, `SplitsTable`, `ActivityDetailView`, `ResumeRunView` | `Ryft/Features/Activities/` | |
| `ActivitySettingsView`, `PrivacyZonesView`, `HeartSensorView` | `Ryft/Features/Profile/` | |
| `ActivityTrackingLiveActivity`, `ActivityTrackingAttributes` | `RyftWidgets/` | mirror attributes in `Ryft/Train/RestActivity.swift`'s file |
| `MetricSpec` additions: `.pace`, `.speed`, `.elevation` | `Ryft/Design/MetricSpec.swift` | colours per 8.1 |

Reused unchanged: `Card`, `CardHeader`, `StatRow`, `PrimaryButton`, `InlineMessage`, `StrainPill`, `LoadChip`, `ZoneBar`,
`ChartHeader`, `HeartRateChart`, `SeriesChartDescriptor`, `ScreenScaffold`, `PressableButtonStyle`, `SchemePair`, the shipped stat tile.
Needs a small change: `PrimaryButton` gains a `.large` size (72 pt, `headline`) for Start/Save, and `InlineMessage` may need the plain `action` from the tracker-setup spec (PR #33 area); the developer coordinates.

## 12. Motion summary
All ≤ 250 ms ease-out from `Theme.Motion`, never a spring; Reduce Motion makes each instant:
state cross-fades, row arrivals, map camera, accuracy circle, hold-to-stop ring (functional: 1.0 s linear, stepwise under Reduce Motion), the toast rows.
No count-ups; the timers tick without animation.

## 13. Accessibility summary
- Dynamic Type to AX5: recording numbers scale (capped by `minimumScaleFactor` only for the time), grids become one column from `accessibility1`, button rows stack, screens scroll above pinned controls.
- VoiceOver: single-element rows, announcements for state changes only, the timer not read per second; maps have text alternatives plus the numeric splits; charts have audio graphs and summaries; hold-to-stop has a confirm-dialog alternative; swipe actions have `accessibilityAction`s.
- Colour is never the only signal: states have glyph + word; selected effort has weight and outline; fastest split says "Fastest".
- Contrast ≥ 4.5:1 everywhere, recording numbers ≥ 7:1; amber text is never used (glyph in `warning`, text `textSecondary`).
- Touch targets ≥ 44 pt everywhere; recording controls 64/96/64 with ≥ 24 pt gaps.
- Reduce Transparency/Increase Contrast: no translucent layers over numbers; badge outline appears with Increase Contrast in dark too.

## 14. Previews to build (each in dark and light unless noted; `SchemePair` where it fits)

1. `MyDayRow` gallery: sleep, tracker workout (scored), Train session, recorded R1, R2, R3, R4 failed, manual, merged (two badges). Dark, light, AX3 and AX5.
2. `MyDayCard`: populated (5 rows), nothing yet, no sleep + nothing, no sleep + rows, recording active, loading, stale. Dark and light; de; AX3.
3. `MyDayView`: today, past day with manual item (swipe actions visible), past empty. Dark, light, AX3.
4. `TodayView` with My Day between scores and Trends (scenario `.watch`), dark and light.
5. `AddActivitySheet`: default, invalid (3 reasons), strength suggestion, saving offline (row R1 behind), rejected. Dark, light, de, AX3.
6. `SportPicker`: recents, search with results, no result. Dark, de.
7. `AddSleepSheet`: default, invalid, tracker-sleep-exists. Dark, light, de.
8. `PreStartView`: locating (34 m), ready (8 m), weak, pre-prompt, denied, approximate, indoor, motion permission row, already recording. Dark, light, de (ready), AX3, AX5.
9. `RecordingView`: running run, running cycling, trail (elevation), paused, auto-paused, GPS weak, GPS lost, HR live, HR not live, sensor lost, low battery, map on. Dark and light, AX3, AX5; a "sunlight" check at max brightness is a device item.
10. `HoldToStopButton`: idle, mid-hold, completed; Reduce Motion variant.
11. `FinishSummaryView`: default with route, route off, too short, privacy suggestion, saving, offline, local failure, discard dialog. Dark, light, de, AX3.
12. `ActivityDetailView`: recorded with HR + merged, recorded no HR (strain pending), effort strain, no route, manual, strength manual, failed upload. Dark, light, de, AX3.
13. `SplitsTable`, `RouteMap` (three modes, zone circle), `GPSAccuracyIndicator` (all levels), `EffortScale`, `SourceBadge(s)`, `ActivityStateMark`: component galleries in dark, light and AX3; add all to `DebugComponentCatalog`.
14. `ResumeRunView`: U1 and U2, with the unreadable message. Dark, light, de, AX3.
15. Widget previews: Lock screen (running, paused, weak GPS, stale), Dynamic Island expanded, compact, minimal (running and paused); each with a long (h:mm) time. The rest timer previews stay.
16. `ActivitySettingsView`, `PrivacyZonesView` (empty, list, add place), `HeartSensorView` (empty, scanning, connected, denied). Dark, light, de.
17. Mock data: `MockData` My Day list with every row state; a GPX track (5 km road, trail with bad fixes) as a preview route; scenarios for the recorder (locating, ready, running) so previews and UI tests need no location services.

## 15. Open questions
1. **Past days:** the brief says read-only; I kept "Add activity" and "Add sleep" for the last 14 days (the sheet already lets you pick any past time), only Start is removed. OK, or hide Add on past days too?
2. **Units:** `Fmt.distance` follows the locale road units; pace and speed would follow it too (min/km vs min/mi, km/h vs mph). Is there, or should there be, a units setting?
3. ~~Live Activity controls~~ Decided: none in v1.
4. **Strain without heart rate:** does the platform score `perceived_effort`? The Add sheet footer and detail copy have two variants; the scoring-scientist decides.
5. **Merged row source order and names:** relies on `hr_source` being a friendly name and on `trackers.json` (PR #33); until then the raw source string is shown.
6. **Unmerge:** the contract has no way to undo a merge; none is designed. Needed?
7. **Recording appearance:** follows the system. Should the recording screen always be dark (battery on OLED) or always light (sunlight)? I chose system with 7:1 contrast.
8. ~~Privacy zones retroactive~~ (decided: applies to routes not yet uploaded). Previously: the zone applies to future saves only in this spec; routes stored locally in full or already trimmed on device? The route shown on the summary and detail would be the trimmed one if only the trimmed one is stored. Architect and security reviewer to decide; copy depends on it.
9. **Gap bridging:** waiting for the architect's sentence (marked in §9).
10. **Padel symbol:** no SF Symbol exists; `figure.racquetball` is a stand-in. Acceptable?
11. **Live HR zones:** zone word during recording needs the user's HR max/reserve on the phone; the phone computes no scores. Show bpm only, and the zone only from the platform's profile values already on device? I specified the zone word; drop it if the profile values aren't available on device.
