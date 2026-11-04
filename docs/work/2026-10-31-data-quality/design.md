# Data quality: design note (ticket B)

Brief: `brief.md` (D2, D3, D4). Plan: `plan.md`. Code read on `origin/main` 69ca9ad. Spec only: no Swift in this ticket.
Wording is a draft in en with a de (du-form) sketch; the localization-editor writes the final strings. Example numbers
only. Vendor names appear only as data sources ("Garmin Connect", "Oura", "Apple Watch"), never as comparisons.

Order of shipping: §D3, then §D4, then §D2 (gated on the platform's changelog entries).

**What the code says that shapes the design**
- The hint is `WatchSyncHintCard` (`TodayView.swift:715`), an `InlineMessage` with a secondary-capsule action
  "Garmin Connect in the App Store" (`WatchSyncHint.opensApp`, `TodayViewModel.swift:742`). No scheme or `sync` field exists
  in `Content/trackers.json` (the Garmin entry has `habits`, `limits`, `capability_notes`, `app_store_id`, nothing else
  that opens an app). Both fields are new catalog schema (see Decisions).
- Under the gauge there is already one slot: the band/delta caption, or `TodayPresentation.Note` via `noteBlock`
  (`TodayView.swift:257`), which VoiceOver reads as part of the gauge's value when `readWithGauge` is true. Provisional
  and "Updated" use that slot and that mechanism; nothing new on the hero's geometry.
- **There is no explain sheet.** `grep Explain` finds nothing in the views. The coverage line needs a home (§D2.4).
- **A "Seen in Apple Health" section already exists** in Profile → Devices & sync (`DevicesAndSyncView.seen`,
  `SourceRowView`: name, kinds, last seen, over `User.sources`, 30 days). The Sources screen grows out of it.
- **"What do you wear?" runs before Apple Health access** (`Step.wear`, "before Apple Health"). At the first run RYFT can
  read nothing, so nothing can be detected there. See §D4.5.
- `OrbitGaugeMarks.pendingOpacity` is **0.6** and pending also breathes. The brief's provisional "70 %" is 0.1 away
  from it. See §D2.1: do not use opacity.

---

## §D3 · The staleness line becomes a button (ships first)

### D3.1 Purpose and hierarchy
Today says a tracker has gone quiet and what to do. The eye reads, in order: the sentence (what is stale, since when), the
age line (night variant), then the one verb. The verb is on the same card, not a separate capsule floating below.

### D3.2 The control
One card, one tap target. The card (`InlineMessage` surface, `Theme.surface`, `cardRadius` 18, `cardPadding` 18) stays; the
secondary capsule goes. A verb row replaces it, inside the card, 8 pt under the text:

```
+----------------------------------------------------------+
| (antenna)  Nothing new from Garmin Connect since 23:24.  |
|            Garmin Connect passes data to Apple Health    |   callout, textSecondary
|            only while it is open.                         |
|            Open Garmin Connect                       ↗    |   callout, textPrimary, arrow.up.forward.app
+----------------------------------------------------------+
```

- Verb row: `Text("Open \(app)")` in `ryft(.callout)`, `Theme.textPrimary`; trailing glyph `arrow.up.forward.app`,
  `textSecondary`, 15 pt scaled with `@ScaledMetric(relativeTo: .callout)` like `InlineMessage.iconSize`.
- No teal. Today's one accent is the gauge; the verb is ink, the glyph says "leaves RYFT".
- Whole card is the hit area (`contentShape(RoundedRectangle)`), min height 44 pt, `PressableButtonStyle` (the existing
  press scale; no other motion). A 1 pt `Theme.separator` hairline is not added: the card already has a surface.
- App Store fallback: same layout, verb "Garmin Connect in the App Store" (today's string, `storeTitle`), glyph
  `arrow.down.app`. Different glyph so the two destinations do not look the same.

### D3.3 States

| # | State | Trigger | Shows |
| --- | --- | --- | --- |
| 1 | Open the app | `isApp`, catalog has a scheme, `canOpenURL` true | verb "Open Garmin Connect", `arrow.up.forward.app` |
| 2 | App Store | `isApp`, no scheme, or scheme not installed, or `open` fails; `storeURL` known | verb "Garmin Connect in the App Store", `arrow.down.app` |
| 3 | Information only | `isApp` with neither a usable scheme nor a store URL | sentence only, not a button |
| 4 | Apple device | `!isApp` ("Wear it and keep it near your iPhone so it syncs") | sentence only, **no button, no glyph, no verb row**; not focusable as a button |
| 5 | Error card on screen | `showsRefreshIssue` (today `showsAction = false`) | sentence only: one action on screen, the error card's |
| 6 | Night variant | `kind == .night` | same as 1/2/3/4; the caption "Last data from Garmin Connect: Wed 23:24" sits between sentence and verb row |

State 2 includes the silent fallback: if `openURL` reports failure, open the store page instead and do not show an error.

### D3.4 Copy
- Sentence, catalog carries `sync` for the screen's language: `"Nothing new from \(app) since \(time)."` then the catalog's
  `sync` sentence as the second line, verbatim, e.g. "Garmin Connect passes data to Apple Health only while it is open."
  The catalog sentence **replaces** today's tail ("Open the Garmin Connect app to sync it to Apple Health."), because the
  verb row now says "open".
- No `sync` (or none in the language): today's full sentence, unchanged, including its "Open the … app" tail. Keep it
  even when the verb repeats it; the fallback is the shipped text, and the repetition is harmless.
- Verb: `"Open \(app)"` (en), `"\(app) öffnen"` (de). Store: today's `"\(app) in the App Store"`.
- de sketch: "Nichts Neues von Garmin Connect seit 23:24." / "Garmin Connect überträgt Daten nur an Apple Health, solange sie geöffnet ist."

### D3.5 VoiceOver
The card is a container (as now), two elements in this order:
1. Static text: the sentence, then the age line when present (one element, `.combine`).
2. Button, label "Open Garmin Connect", trait `.isButton`, hint "Leaves RYFT.". In state 2 the label is "Garmin Connect in the App Store".

Reading the information first and the action second matches the eye order. The decorative glyphs are hidden. Identifiers
stay `today.watchHint` / `today.nightHint`, the button `today.watchHint.action`. Sighted tap anywhere on the card fires the
same action as the VoiceOver button (a hidden tap gesture on the card, the verb row is the accessible one).

### D3.6 Dynamic Type, motion, appearance
- Text wraps; the verb row wraps to two lines at AX3, glyph stays on the first line, trailing. No truncation.
- Motion: press feedback only. Reduce Motion: unchanged (it is not motion, it is a scale of 0.98 in `PressableButtonStyle`
  which already respects it).
- Dark and light: ink and surface colours only. Contrast of `textSecondary` on `surface` is the shipped one.

### D3.7 Returning from the app
Nothing new: foreground return already runs the sync and the refresh path. The note for T2 is that this return is the
common route to `.pending`, which makes the audit of that path matter more.

---

## §D4 · Sources screen and the wizard's pre-selection

### D4.1 Purpose and where it lives
"Which apps and devices sent RYFT what, in the last 7 days, and is anything missing." Numbers first: the count per source,
then the types, then the warnings.

Three routes, one destination:
1. **Profile → Devices & sync → "Sources"**: the existing "Seen in Apple Health" section is replaced by one row that
   pushes the screen: title "Sources", subtitle "2 sources in the last 7 days" (monospaced digits), chevron. The inline rows
   move into the screen, so nothing is shown twice. Footer "Apps and devices that sent data to RYFT in the last 30 days"
   moves with it and says 7 days (or the platform's window when `samples_7d` is the source).
2. **Today → provenance line** (§D2.5): presents the same screen in a sheet with its own `NavigationStack` and a Done
   button, the way Today already presents `DevicesAndSyncView` (`TodayView.swift:524`).
3. **Tracker setup (onboarding, after Apple Health) → below "Check sync"**: a secondary row "See what Apple Health has sent",
   pushing the screen. Check sync's result stays the verdict; Sources is the evidence behind it.

Title: "Sources" (de "Quellen"). Inline navigation title like its siblings.

### D4.2 Layout
`ScrollView` in the usual screen padding (`screenPadding` 20, `sectionSpacing` 24), `Theme.background`. Sections use
`ProfileSection` (the label style header, `ryftLabelStyle`, as Devices & sync does).

```
Sources                                   (nav title)

  LAST 7 DAYS                              ryftLabelStyle
 +----------------------------------------------------+
 | (icon)  Garmin Connect              Thu 07:12      |  callout primary / caption secondary
 |         [HR] [Sleep] [Steps]                        |  chips
 |         5,312 samples                               |  caption, monospacedDigit, secondary
 |         (minus) Garmin Connect doesn't share HRV    |  neutral note, §D4.3 B
 |         with Apple Health; recovery uses resting    |
 |         heart rate and sleep.                       |
 |-----------------------------------------------------|  separator hairline
 | (icon)  Apple Watch                 Thu 07:14      |
 |         [HR] [HRV] [Sleep] [Steps]                  |
 |         9,880 samples                               |
 +----------------------------------------------------+

  PICKED IN SETUP, NOT SEEN                ryftLabelStyle  (only when there are any)
 +- - - - - - - - - - - - - - - - - - - - - - - - - - +   dashed outline card, no fill
 | (icon)  Oura                                       |
 |  (!) Nothing from Oura in 7 days.                  |   amber glyph, primary text
 |      Open Oura, then pull to refresh.   Open Oura ↗ |
 +- - - - - - - - - - - - - - - - - - - - - - - - - - +

  Pull to refresh re-reads Apple Health.   caption, textTertiary → use textSecondary in light
```

- Row: icon column 22 pt (scaled like `SelectableTile.glyphColumn`), name `ryft(.callout)` `textPrimary` (unknown source:
  `textSecondary`, with "Not a tracker RYFT knows. It still counts." kept from `SourceRowView`), last seen right-aligned
  caption, `monospacedDigit`. At accessibility sizes the last-seen line drops under the name.
- **Icon by bundle id:** the catalog's `Tracker.symbol` for a source `TrackerCatalog.match` knows (neutral SF Symbols:
  `applewatch`, `circle.circle`, `iphone`, `watch.analog`); unknown: `ellipsis.circle`. Never a vendor logo and never the
  app's own store icon (brand rule, and HealthKit does not provide one). "Known icon by bundle id" in T3's acceptance
  criterion means this glyph.
- **Type chips** are a new Design primitive, `SignalChip` (a `SourceBadge` capsule without the glyph: `surfaceRaised`
  capsule, 8 x 4 padding, `ryft(.caption)` `textSecondary`, hairline `separator` outline in light or Increase Contrast).
  Order is fixed: HR, HRV, Sleep, Steps, Workouts; others collapse to "+2". `FlowLayout(spacing: 6, lineSpacing: 6)` wraps
  them. Chip words: "HR", "HRV", "Sleep", "Steps", "Workouts" (de: "Herzfrequenz" is long, so de chips are "HF", "HRV", "Schlaf",
  "Schritte", "Training"; the localization-editor confirms "HF").
- **Counts:** one caption line, "5,312 samples" (total over the chips' types), not per-chip numbers. Count source is
  `User.sources[].samples_7d` when present, else HealthKit's. A tap on a row opens nothing in this ticket.
- Tracker the user picked but whose source never appeared: a **dashed outline row** (no fill, `separator` dashes, 1 pt).
  This is the "pending is an outline" rule: the thing is expected, not present. It is not a card with a sad face.

### D4.3 Notes and warnings (three, with their colours)
Colour follows `tracker-setup/ui.md` §0: expected is not an error. Amber is only for a signal that should arrive and does not.
Every note has a glyph and words, so colour is never alone. Text is always `textPrimary` or `textSecondary` (amber text fails
4.5:1 on `surfaceRaised` in light); only the 16 pt glyph takes `Theme.warning`.

| Note | When | Glyph | Text | Action |
| --- | --- | --- | --- | --- |
| A. Nothing seen | a tracker picked in setup has written nothing in 7 days (the dashed row above) | `exclamationmark.circle`, `Theme.warning` | "Nothing from Oura in 7 days. Open Oura, then pull to refresh." | the D3 verb ("Open Oura" / App Store); none for an Apple device |
| B. Expected absence | the source's catalog capability for HRV is `no` and it writes heart rate | `minus.circle`, `textTertiary` | "Garmin Connect doesn't share HRV with Apple Health; recovery uses resting heart rate and sleep." | none |
| C. Mismatch | HealthKit has a type for this source in 7 days but the platform's `samples_7d` for it is 0 (so only once the platform sends it) | `arrow.triangle.2.circlepath`, `textSecondary` | "Apple Health has HRV from Oura; RYFT hasn't received it yet. Pull to refresh." | the screen's pull to refresh |

- B is **neutral** although the brief calls it a warning chip: the user cannot fix it, and a permanent amber mark on every
  Garmin user is the "borrowed alarm" the earlier design avoids. If the lead wants amber, change the glyph colour only.
- B's clause "recovery uses resting heart rate and sleep" is true only if the platform says so. It must be built from the
  day's `recovery_inputs` (`tracker-setup/design.md` §0.2: nothing may assume what Recovery is based on). Without that
  answer the note is only "Garmin Connect doesn't share HRV with Apple Health."
- C needs both numbers, so it cannot appear before `samples_7d` exists. Until then the screen has A and B only.
- Several notes under one source stack in the order A, C, B, 8 pt apart. Maximum three per row.
- de: A "Nichts von Oura in den letzten 7 Tagen. Öffne Oura und zieh dann zum Aktualisieren." B "Garmin Connect teilt HRV nicht mit Apple Health; die Erholung nutzt Ruhepuls und Schlaf." C "Apple Health hat HRV von Oura; RYFT hat sie noch nicht erhalten. Zieh zum Aktualisieren."

### D4.4 States of the screen

| # | State | Trigger | Shows |
| --- | --- | --- | --- |
| 1 | Loading | first read of HealthKit in flight (up to the query's time) | the section label, two outline rows (hairline, no fill) with "Reading Apple Health…" in `textSecondary`. No spinner, no skeleton shimmer. Cached platform rows (`User.sources`) show at once if there are any, marked by nothing; the HealthKit counts replace them |
| 2 | Sources | at least one source in 7 days | as §D4.2 |
| 3 | Nothing detected | HealthKit authorised or asked, zero sources in 7 days | text "Apple Health has no data for the last 7 days." / "That can mean your tracker has not synced, or that RYFT isn't allowed to read it." Actions: "Check sync" (existing) and, secondary, "Open Health" (existing `HealthLinks.open`). Picked trackers still show their dashed rows below |
| 4 | Not authorised | `HealthAccess` says RYFT never asked | "RYFT hasn't asked for Apple Health yet." Action "Allow access" (existing). No rows |
| 5 | Maybe denied | asked, but HealthKit cannot tell denied from empty | state 3's text, because RYFT cannot tell the two apart; it must say both (principle 4 of the earlier design) |
| 6 | Platform offline | `GET /v1/me` failed | HealthKit counts only, no note C; footer "RYFT can't reach its server. Counts are from Apple Health." |
| 7 | Demo mode | `AppEnvironment` demo | the mock sources (a Garmin-like source with HR, Sleep, Steps and no HRV, and an Apple Watch with all four), first line "Sample data" in `textSecondary`, no HealthKit read, "Open Health" and "Allow access" hidden |

State 4 and 5 are never shown together with rows from a stale platform cache without saying so; if rows come from the cache
the footer reads "As of your last sync".

### D4.5 "What do you wear?" pre-selects what is detected
**Constraint:** the wear step precedes Apple Health access on the first run, so the detection has nothing to read there.
Pre-selection works in three places:
- Profile → Devices & sync → Edit (`TrackerPickerSheet`): Health is already authorised. Always.
- A re-install on a phone that already granted access (HealthKit remembers the grant): at the first run, if a read
  returns sources, pre-select. Else nothing is pre-selected and the step is exactly today's.
- First run with no access: unchanged. After Health is granted, the tracker-setup step (`TrackerSetupStepView`) carries one
  line above the cards when something was detected that is not picked: "RYFT also found Oura in Apple Health. Add it?" with
  one button "Add Oura". This keeps the order of the flow. (If the lead prefers to move the wear step after Apple Health
  instead, the whole pre-selection then works at the first run; see Decisions.)

**Pre-selection reads differently from a choice.** Reuse `SelectableTile` and `TrackerPickerGrid`.
- A *chosen* tile is as today: accent check, `Theme.accent` glyph, `surfaceRaised` fill.
- A *detected* tile has the same check slot but drawn as an outline: a hollow circle with an accent hairline, no fill on the
  tile, and under the name a caption line "Found in Apple Health" (`ryft(.caption)`, `textSecondary`). The tile is one line
  taller than its neighbours; that is the cue.
- Tapping a detected tile **confirms** it (it becomes chosen, no motion beyond the 250 ms selection ease). A second tap
  clears it. Tapping an undetected tile chooses it as today. "Just my iPhone" clears the others, as today.
- Screen text changes when anything was detected: title "What do you wear?" (unchanged), body "RYFT found these in Apple
  Health. Check that they are right." In place of "Pick your watch, band or ring…". The footnote stays.
- The primary button is "Confirm" while every detected tile is still detected-and-untouched; the first change turns it
  to "Continue". It is never enabled on a detected-only selection by default: pressing it confirms them all. The button
  therefore does not need the `picked.isEmpty` disable when a detection exists.
- VoiceOver: each tile reads its name, then "Found in Apple Health, not confirmed" or "Selected" / "Not selected". The grid's
  hint changes from "Choose all that apply" to "Confirm or change what RYFT found".
- Nothing is saved on the strength of detection alone: the user's Confirm writes `answerWear`.

### D4.6 The seam for per-metric pinning (not designed)
Platform M6b may let a user pin which source feeds a metric. The screen leaves room: each row's chip row stays a plain row,
and later a **disclosure under the row** ("Use for: HR, Sleep") expands to one line per metric with a segmented choice
("Automatic" / this source). Nothing in this ticket draws it, adds a model field, or reserves vertical space. Two constraints
for the implementer: a row is already an accessibility element that reads its notes, so do not make the whole row a
button; and a disclosure row would need its own 44 pt target.

### D4.7 VoiceOver, Dynamic Type, motion
- Each row is one element (`.combine`): "Garmin Connect. Heart rate, sleep, steps. 5,312 samples. Last data Thursday 07:12."
  then each note as its own element after it (notes can carry an action), in the order A, C, B.
- Chips are hidden from VoiceOver individually; the row's label carries them in words ("Heart rate", not "HR").
- A dashed row reads "Oura. Picked in setup. Nothing in the last 7 days." then its note and button.
- AX3: the icon moves above the name only if the name will not fit beside it (else stays); chips wrap; the last-seen line
  moves under the name; nothing truncates. `ryftLabelStyle` section headers cap at `accessibility3` as Devices & sync does.
- Motion: pull-to-refresh and the 250 ms ease on chosen tiles. No count-up on the numbers. Reduce Motion: the same, minus the ease.
- Dark and light: `surface` cards, `surfaceRaised` chips, hairlines in light.

---

## §D2 · Provisional and final, the "Updated" line, coverage, provenance (gated)

### D2.1 Provisional hero and the gauge
The readiness number is real but the night is not finished. The honest picture: the numbers are today's, the status says they
may move.

**Do not dim the gauge at 70 %.** `.pending` already uses 0.6 opacity on every mark with `textTertiary` ink and breathing.
0.7 versus 0.6 cannot be told apart, and the two states mean opposite things (pending: "this is yesterday's"; provisional:
"this is today's, still moving"). Dimming also drops the arcs under 3:1 on the track (measured in the orbit-gauge note,
section 9: 0.6 accent arc is 2.21:1 over the track in light). Recommendation: **a different channel, the centre ring.**

| State | Marks | Number ink | Centre ring | Motion |
| --- | --- | --- | --- | --- |
| Scored (final) | full | `textPrimary` | solid, band colour | none |
| **Provisional** | **full** | **`textPrimary`** | **dashed, band colour, butt caps** | **none** |
| Pending | 0.6, previous day's | `textTertiary` | solid at 0.6 | breathing 1.0 to 0.75, 1.4 s |
| Calibrating | segments | `textPrimary` count | none | segments fill, 60 ms steps |

- The dashed ring: stroke unchanged (4.5 pt at dial 160, scaled), dash pattern 9 pt on / 5 pt off at dial 160 (14 dashes
  around r 32), phase set so a gap sits at 12 o'clock like the orbit's own openings; scaled by dial / 160 with the stroke floor
  for `.medium` and `.small`. Below dial 56 pt it is solid (the dashes would be under the stroke floor): the line under the gauge
  carries the status there.
- Why this cannot be confused: pending is a *fade* of everything and a breathing; provisional is *full strength* with one
  broken ring, still. Calibrating's segments are seven long ones on the **outer** ring, filled or unfilled; the provisional
  dashes are fourteen short ones on the **centre** ring in one colour. They differ in place, count and length, and the two
  states never occur together.
- It needs `OrbitGaugeMode` to carry a provisional flag (`.scored(values, provisional: Bool)`), `OrbitGaugeMarks` to draw the
  dash, and the preview and snapshot suites to cover it. That is a change to the **shared** gauge files, which the app and widget
  both compile (`scripts/check-shared-types.py`): the ios-developer's work in T5, not this ticket's.
- Fallback if the dashed ring is rejected: leave the gauge identical to final and let the line alone say "Provisional". That is
  still honest because the line sits directly under the gauge and is in its VoiceOver value. Do **not** fall back to 0.7.

**The line.** In place of the band/delta caption (the slot `OrbitGauge.Caption` / `TodayPresentation.Note` fill):

```
              (gauge, readiness 71, dashed centre ring)
        (circle.dotted)  Provisional · based on 2h 50m of heart rate so far
                                                      ^ one caption line, centred
```

- `ryft(.caption)`, `textSecondary`, glyph `circle.dotted` (hidden from VoiceOver), via the existing `GaugeNote` (it already
  handles the AX centred paragraph with the symbol leading the first line).
- The delta ("+4 vs 7 days") and the band word are not shown while provisional: both would be claims about a night not over.
- Copy: `"Provisional · based on \(duration) of heart rate so far"`. `duration` is `Fmt.duration(minutes:)`, which prints "2h 50m"
  (the brief's "2 h 50 m" has spaces; use the shipped formatter and let the localization-editor decide).
  de: "Vorläufig · bisher auf Basis von 2h 50m Herzfrequenz".
- If heart-rate minutes are zero but sleep exists: "Provisional · based on the part of the night synced so far"
  (de "Vorläufig · auf Basis des bisher synchronisierten Teils der Nacht").
- Provisional is **not** an error and not amber. Tiles unchanged, and not dimmed.

**Cross-fade to final.** When `status` turns `final`: the caption cross-fades to the band/delta line over 250 ms
(`Theme.Motion.quick`, same `.animation(value:)` hook as `hero.kind` and `gaugeNote`, keyed on `isProvisional`), the centre
ring's dashes fade to solid in the same 250 ms (opacity cross-fade of the two rings, not a stroke animation), the arcs and
number move only if the values changed, with the existing `ringAnimation` (250 ms, ease-out, no count-up). One light haptic
(`.success`) is **not** used here; the pending-landed haptic must not fire for this, because `hero.isPending` did not change.
Reduce Motion: instant swap, no fade.

### D2.2 The "Updated" line (a change of 5 or more points)
`"Updated after your watch synced the rest of the night (was 61)"`, de "Aktualisiert, nachdem deine Uhr den Rest der Nacht
synchronisiert hat (vorher 61)".
- Condition: final readiness differs from the stored provisional by 5 or more, either direction. Once per day.
- Place: under the band/delta line, a second `GaugeNote`-style line (`clock.arrow.circlepath`, `textSecondary`, caption), with a
  trailing dismiss button `xmark` 44 x 44 pt hit area, `textTertiary` glyph at 12 pt, label "Dismiss".
- It is not a card, a banner or a push, takes no extra surface, and never moves the gauge. It enters with a 250 ms opacity
  fade; leaves the same way on dismiss. Reduce Motion: instant.
- Once per day: shown from the final until dismissed or until the day changes. Dismissed means never again that day, also after
  a relaunch (stored with the day key, local only). A later re-score of the same day does not show a second one.
- The "was" value is the stored provisional. If the stored provisional is missing (app was closed), the line is not shown;
  nothing is guessed.
- If final is lower than provisional the sentence is the same (the word "Updated" is neutral). No red, no arrow up or down.
- VoiceOver: one element after the gauge's value, label "Updated after your watch synced the rest of the night. It was 61.",
  custom action "Dismiss" (and the visible button, as a separate element for Switch Control). It is **not** part of the gauge's
  spoken value (it is about the change, not the state), but the gauge's value changes silently with the number.
- AX3: the line wraps centred with the glyph leading (as `GaugeNote`), the dismiss button moves under the text, right-aligned.

### D2.3 Gauge state in VoiceOver
The gauge value already speaks "Recovery 71 percent, Sleep 88 percent, Strain 9.6 of 21" with an `accessibilityNote`. Add
status and coverage to it (`readWithGauge = true` for the provisional line, so the line is not read twice):
- Final: unchanged.
- Provisional: "Readiness 71, provisional, based on 2 hours 50 minutes of heart rate so far. Recovery 71 percent…".
- A floor-missing component adds "Resting heart rate not scored" in its slot (§D2.4).

### D2.4 Coverage: where it goes, and a missing component
There is no explain sheet. Recommendation: **a medium-detent sheet "How this was scored"**, opened by tapping the band/delta
or provisional line. That line is the gauge's caption and already sits next to its VoiceOver value.
- Affordance: the caption line gets a trailing `chevron.right` (10 pt, `textTertiary`) only when coverage exists, and becomes a
  button (`PressableButtonStyle`, min 44 pt) with hint "Shows what this score is based on". Final scores without a coverage
  object keep a plain caption. Discoverability is deliberately low for a final score and high for a provisional one
  (the chevron is always on a provisional line).
- Sheet: `presentationDetents([.medium, .large])`, drag indicator, title "Based on" (`ryft(.headline)`), a Done button; contents in
  `Card`s over `Theme.background`; at AX3 it opens at `.large`.

```
Based on                                    Done
 +----------------------------------------------+
 | 6h 40m   heart rate         Garmin Connect   |   number first (metric), then name
 | 5        HRV readings       Apple Watch      |
 | Sleep                       Garmin Connect   |
 +----------------------------------------------+
 (minus) Resting heart rate: not enough overnight
         data (needs 2h)                              neutral, textSecondary
 caption: Sources are picked per hour and per night. Details in Sources ›   (link to §D4)
```

- Rows: value in `ryft(.metric)` `monospacedDigit` `textPrimary`; label `callout` `textSecondary`; source right-aligned
  `textPrimary`. At AX3 each row stacks (value, label, source) and the dividers are `separator` hairlines.
- One-sentence form for the sheet's header or for VoiceOver:
  "Based on 6h 40m of heart rate from Garmin Connect · 5 HRV readings · sleep from Garmin Connect".
  de: "Basiert auf 6h 40m Herzfrequenz von Garmin Connect · 5 HRV-Messwerten · Schlaf von Garmin Connect".
- A missing component because of a floor: a neutral line (glyph `minus.circle`, `textTertiary`, words in `textSecondary`),
  "Resting heart rate: not enough overnight data (needs 2h)", de "Ruhepuls: nicht genug Daten aus der Nacht (braucht 2h)".
  The floor number comes from the platform's coverage, never hard-coded in the app. Floors are facts, not errors: no amber.
- Source names: `TrackerCatalog.displayName` by bundle id via `User.sources`; unknown: HealthKit's name verbatim.
- This sheet is the only place coverage is spelled out. The widget and the tiles do not carry it.

### D2.5 Provenance under the tiles
One caption line, tap opens Sources (§D4.1 route 2).

```
 [Sleep] [Recovery] [Strain]                      tiles, unchanged
   HRV: Apple Watch · Sleep: Garmin Connect · HR: Garmin Connect 14h, Apple Watch 9h  ›
```

- `ryft(.caption)`, `textSecondary` (tertiary fails 4.5:1 on the background in light), trailing `chevron.right` 10 pt
  `textTertiary`, 12 pt above (the tiles' own `10` spacing plus 2), min height 44 pt, full width, leading aligned.
- Each clause is "Label: names". Several sources for one metric: "Garmin Connect 14h, Apple Watch 9h" (durations in
  `Fmt.duration`, monospaced digits). Metrics shown: HRV, Sleep, HR (HR order by hours, descending). A metric no source
  covered is omitted, never "none".
- **Hidden when one source did everything** (the same name in every clause, and one source for HR) and while the hero is
  pending, calibrating or importing. No empty placeholder.
- Wrapping: normal sizes, a flowing paragraph up to 3 lines, clauses kept intact (a `·` is a figure space plus the separator so a
  clause breaks after it, not inside it). At AX sizes it becomes a vertical list, one clause per line:
  ```
  HRV: Apple Watch
  Sleep: Garmin Connect
  HR: Garmin Connect 14h
      Apple Watch 9h                    ›
  ```
  The chevron sits on the first line, trailing.
- VoiceOver: one button. Label "Sources: heart rate variability from Apple Watch. Sleep from Garmin Connect. Heart rate from Garmin
  Connect, 14 hours, and Apple Watch, 9 hours." Hint "Opens Sources". Placed after the tiles, before Trends.
- de: "HRV: Apple Watch · Schlaf: Garmin Connect · Herzfrequenz: Garmin Connect 14h, Apple Watch 9h".

### D2.6 The widget
`ReadinessSnapshot` (shared) gains a provisional flag; `Words.status` (`ReadinessWidget.swift:90`) returns "Provisional" for it.
- Home-screen small / medium: the number as today, the band word replaced by "Provisional" (`textSecondary`), the gauge with the
  dashed centre ring (at `.small` it is solid below dial 56; the word says it). No coverage text.
- Lock-screen inline: "Readiness 71 · provisional". Redacted (locked device): unchanged, the constant placeholder.
- VoiceOver: "Readiness 71, provisional." (extends `spoken`).
- de: "Vorläufig"; inline "Bereitschaft 71 · vorläufig".
- The widget cannot show the "Updated" line; it just shows the final one when the timeline reloads.

### D2.7 Dynamic Type, motion, appearance (D2 as a whole)
- Hero captions and the Updated line wrap and centre; nothing truncates up to AX3; the gauge itself stays at its fixed size.
- Provenance and the sheet follow the AX layouts above; the sheet opens at `.large` at AX3.
- Motion: only 250 ms fades (`Theme.Motion.quick`); no count-up, no springs. Reduce Motion: every fade is an instant swap.
- Dark and light: all ink colours from the theme; the dashed ring uses the band colour (teal / `warning` / `alert`) already
  contrast-checked for the solid ring. The dash gap shows `surfaceRaised`/background, not a track, so contrast is the ring's own.

---

## §States inventory

Screens: **T** Today, **W** widget, **S** Sources screen, **P** picker/wizard, **E** the "Based on" sheet.

| # | Screen | State | Trigger | en (draft) | de (draft) |
| --- | --- | --- | --- | --- | --- |
| 1 | T | Staleness, `sync` present | catalog entry has `sync` in locale | "Nothing new from \(app) since \(time)." + catalog `sync` | "Nichts Neues von \(app) seit \(time)." + `sync` |
| 2 | T | Staleness, fallback | no `sync` | today's sentence, unchanged | unchanged |
| 3 | T | Verb: open app | scheme known and installed | "Open \(app)" | "\(app) öffnen" |
| 4 | T | Verb: store | no scheme, not installed, or open failed | "\(app) in the App Store" | unchanged (shipped) |
| 5 | T | Apple device | `!isApp` | sentence only, no verb | unchanged |
| 6 | T | VoiceOver | 3, 4 | button "Open Garmin Connect", hint "Leaves RYFT." | "Garmin Connect öffnen", "Verlässt RYFT." |
| 7 | T | Provisional line | `status == provisional`, HR minutes known | "Provisional · based on \(duration) of heart rate so far" | "Vorläufig · bisher auf Basis von \(duration) Herzfrequenz" |
| 8 | T | Provisional, no HR minutes | provisional, sleep only | "Provisional · based on the part of the night synced so far" | "Vorläufig · auf Basis des bisher synchronisierten Teils der Nacht" |
| 9 | T, W | Gauge provisional | 7 or 8 | dashed centre ring; VoiceOver "provisional" in the value | "vorläufig" |
| 10 | T | Updated line | final differs from provisional by 5 or more, not dismissed, same day | "Updated after your watch synced the rest of the night (was \(old))" | "Aktualisiert, nachdem deine Uhr den Rest der Nacht synchronisiert hat (vorher \(old))" |
| 11 | T | Updated dismissed | tap "Dismiss" | line leaves, not shown again that day | "Schließen" |
| 12 | T | Provenance line | coverage has more than one source | "HRV: Apple Watch · Sleep: Garmin Connect · HR: Garmin Connect 14h, Apple Watch 9h" | "HRV: Apple Watch · Schlaf: Garmin Connect · Herzfrequenz: Garmin Connect 14h, Apple Watch 9h" |
| 13 | T | Provenance hidden | one source for all; or hero pending, calibrating, importing | none | none |
| 14 | E | Coverage sentence | coverage present | "Based on \(hr) of heart rate from \(src) · \(n) HRV readings · sleep from \(src)" | "Basiert auf \(hr) Herzfrequenz von \(src) · \(n) HRV-Messwerten · Schlaf von \(src)" |
| 15 | E | Component floored | component below its floor | "Resting heart rate: not enough overnight data (needs \(floor))" | "Ruhepuls: nicht genug Daten aus der Nacht (braucht \(floor))" |
| 16 | E | Sheet title / hint | caption tapped | "Based on" / "Shows what this score is based on" | "Grundlage" / "Zeigt, worauf dieser Wert beruht" |
| 17 | W | Provisional status | snapshot provisional | "Provisional"; inline "Readiness 71 · provisional" | "Vorläufig"; "Bereitschaft 71 · vorläufig" |
| 18 | S | Title / row | Sources opened | "Sources"; "\(n) sources in the last 7 days" | "Quellen"; "\(n) Quellen in den letzten 7 Tagen" |
| 19 | S | Chips | types seen | "HR", "HRV", "Sleep", "Steps", "Workouts", "+\(n)" | "HF", "HRV", "Schlaf", "Schritte", "Training", "+\(n)" |
| 20 | S | Samples | counts known | "\(n) samples" | "\(n) Messwerte" |
| 21 | S | Loading | HealthKit read in flight | "Reading Apple Health…" | "Apple Health wird gelesen…" |
| 22 | S | Nothing detected / maybe denied | zero sources | "Apple Health has no data for the last 7 days. That can mean your tracker has not synced, or that RYFT isn't allowed to read it." | "In Apple Health gibt es für die letzten 7 Tage keine Daten. Entweder hat dein Tracker nicht synchronisiert, oder RYFT darf sie nicht lesen." |
| 23 | S | Not asked | access never requested | "RYFT hasn't asked for Apple Health yet." + "Allow access" | "RYFT hat Apple Health noch nicht angefragt." + "Zugriff erlauben" |
| 24 | S | Note A | picked tracker, no data in 7 days | "Nothing from \(app) in 7 days. Open \(app), then pull to refresh." | "Nichts von \(app) in den letzten 7 Tagen. Öffne \(app) und zieh dann zum Aktualisieren." |
| 25 | S | Note B | HRV capability `no`, HR present | "\(app) doesn't share HRV with Apple Health; recovery uses resting heart rate and sleep." (second clause only when `recovery_inputs` says so) | "\(app) teilt HRV nicht mit Apple Health; die Erholung nutzt Ruhepuls und Schlaf." |
| 26 | S | Note C | HealthKit has a type, `samples_7d` is 0 | "Apple Health has \(type) from \(app); RYFT hasn't received it yet. Pull to refresh." | "Apple Health hat \(type) von \(app); RYFT hat sie noch nicht erhalten. Zieh zum Aktualisieren." |
| 27 | S | Picked, not seen (section) | A applies | "Picked in setup, not seen" | "In der Einrichtung gewählt, nicht gesehen" |
| 28 | S | Platform offline | `GET /v1/me` failed | "RYFT can't reach its server. Counts are from Apple Health." | "RYFT erreicht den Server nicht. Die Zahlen stammen aus Apple Health." |
| 29 | S | Demo | demo mode | "Sample data" | "Beispieldaten" |
| 30 | S | Unknown source | not in catalog | "Not a tracker RYFT knows. It still counts." (shipped) | shipped |
| 31 | P | Pre-selected tile | detected, not confirmed | caption "Found in Apple Health" | "In Apple Health gefunden" |
| 32 | P | Pre-selection copy | any detected | "RYFT found these in Apple Health. Check that they are right." | "RYFT hat diese in Apple Health gefunden. Prüfe, ob sie stimmen." |
| 33 | P | Button | detected and untouched / changed | "Confirm" / "Continue" | "Bestätigen" / "Weiter" |
| 34 | P | VoiceOver | detected tile | "Found in Apple Health, not confirmed" | "In Apple Health gefunden, nicht bestätigt" |
| 35 | P | Grid hint | detection exists | "Confirm or change what RYFT found" | "Bestätige oder ändere, was RYFT gefunden hat" |
| 36 | P | Setup-step offer | first run, detected tracker not picked, after Health access | "RYFT also found \(app) in Apple Health. Add it?" + "Add \(app)" | "RYFT hat auch \(app) in Apple Health gefunden. Hinzufügen?" + "\(app) hinzufügen" |

Tests keyed to this table: 1-6 (T1), 18-30 (T3), 31-36 (T3), 7-17 (T5), 12-13 (T6).

---

## Decisions that need the lead

1. **Provisional dimming.** The brief says dots at 70 %. Pending is 0.6 and breathing, so 0.7 cannot be told from it, and a dimmed
   gauge misses 3:1. Recommended: full-strength gauge with a **dashed centre ring** and the line (§D2.1). Needs a flag in the shared
   `OrbitGaugeMode` and an App/Widget change. Alternative: line only, no gauge change.
2. **Wizard order.** "What do you wear?" runs before Apple Health access, so a first run has nothing to detect. Options: (a)
   keep the order and use the setup-step offer, plus pre-selection on re-install and in Devices & sync (this note); (b) move
   the wear step after Apple Health (the feature then works at the first run, but it changes the onboarding funnel and its
   tests). Recommended: (a) now.
3. **Catalog schema.** `trackers.json` has no `sync` field and no URL scheme. The tracker-setup ADR and its design dropped
   `open_url` in 2026-10; this brief reverses that. Someone owns adding `sync` ({en, de}) and a `url_scheme` string per tracker
   (plattform/web side), plus `LSApplicationQueriesSchemes` (the plan's T1 test already checks the list).
4. **Note B is neutral, not amber.** The brief calls it a warning chip; this note shows it as an expected absence (earlier
   design principle). Say if you want amber.
5. **"recovery uses resting heart rate and sleep".** Only true if the platform says so (`recovery_inputs` / `rhr_source`); the
   clause is built from that, so it may be absent for Garmin until the platform derives resting HR from overnight HR.
6. **No explain sheet exists.** This note adds a "Based on" sheet from the caption line. If you would rather not add a surface,
   the fallback is to put the coverage sentence in the provisional line's own second line, at the cost of the hero growing.
7. **Duration format.** `Fmt.duration` prints "2h 50m"; the brief writes "2 h 50 m". Used the shipped one.
8. **Sources screen replaces "Seen in Apple Health"** (30 days, platform data) with a 7-day screen. The window shrinks; say if
   30 days should stay as a second line.
9. **New Design primitive** `SignalChip` (type chip) is needed for T3; it is a `SourceBadge` without the glyph and could be
   a `SourceBadge(glyph: nil)` instead.
