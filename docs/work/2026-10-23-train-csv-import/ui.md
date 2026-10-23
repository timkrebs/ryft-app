# Training import from CSV: UI spec (I1)

Brief: `brief.md` §1–§5 (§3 is the flow and is binding). Plan: `plan.md`. Data side: `platform-brief.md`. Types, parser,
mapping, ids and upload are in `design.md` (architect; accepted by the lead, see `plan.md` → "I1 answers"). This spec
uses its frozen names (`ImportBundle`, `ImportWarning.Kind`, `ImportConfidence`, `ExerciseMatch.Tier`, `BodyweightAnswer`,
`ImportedLoad`, `PendingImport`, `ImportMapping`) and where it still depends on a detail it says **Assumes**. Code read at `main` (02a3403): `PlansView`, `PlanBuilderView`, `AddExerciseSheet` /
`CustomExerciseForm`, `TrainComponents`, `ProfileView` → Data, `StatusViews`. House style follows
`docs/work/2026-10-22-my-day-activities/ui.md`. Spec only: no code, no screenshots.

**Personal data rule.** Every example here is invented (plan "Upper/Lower · 6 weeks", "Bench Press · Barbell"). Nothing is
copied from `local-samples/`. Realistic sizes taken from them for limits only: a plan file is about 1 KB (1 plan, 2 to 4
days, 10 to 20 exercises); a workouts file is about 12 KB for 12 sessions, so a multi-year history is well under 1 MB (the cap is 8 MiB per file, about 9,000 workouts).

**Brand rule.** The source is named only as a data source, factually: "Alpha Progression export", "from Alpha
Progression". No comparison, no "better than", no borrowed layout or words. RYFT's own names: Plan, Workout history,
Strain (the tab; the app calls it "Train" in code), "Last time". German is du-form and uses the shipped terms: Plan,
Pläne, Sätze, Volumen, Eigene Übung, Hauptmuskel, Workout.

## 0. Principles

1. **Numbers first, then the sentence.** Every summary leads with counts and unit ("1 plan · 2 days · 19 exercises ·
   12 workouts"), then the date range, then words. Counts use tabular figures.
2. **Nothing is a surprise before the button.** Step 5 shows exactly what will be created, what will be skipped and why,
   what looks like a duplicate, and the one side effect on existing data (past strain is recalculated once).
3. **Pending is an outline; a failed item is a word.** Uploading is a thin determinate bar and counts ("8 of 12"), never a
   spinner and never a blocking overlay. A failed item says "Not imported" with its reason and one Retry.
4. **Your file stays yours.** The file is read on this iPhone and never uploaded or stored. Only the result you confirm is
   sent. The copy says so once, at Step 1 and in the Step 5 footer.
5. **Never guess silently.** A fuzzy match is never accepted without a tap. A time without a time zone is read in the iPhone's
   zone and the screen says so. A skipped set is counted, not turned into zero.
6. **Shape and words, never colour alone.** Each match state has its own glyph and its own word.
7. **One accent per screen.** Teal is the primary action only (Continue, Import, Open plan) and the progress bar fill.
   States use `textPrimary / textSecondary / textTertiary`. Problems are quiet: `exclamationmark.circle` in
   `Theme.warning` plus `textSecondary` text. `Theme.alert` only for the destructive "Discard" button.
8. **Every state has a reason and, where possible, one action.**

Eye path per screen: the title and the count line first, then the list or toggles, then the single teal button at the
bottom (pinned, `safeAreaInset(edge: .bottom)`, with a hairline `Theme.separator` above, background `Theme.background`).

## 1. State inventory

| ID | Where | State | Trigger | One action |
| --- | --- | --- | --- | --- |
| E1 | My Plans | New plan menu | flag `train.import` on | Import from file / Start from scratch |
| E2 | My Plans | New plan, flag off | flag off | plain button, as today (no menu) |
| E3 | My Plans / Profile | import waiting | an unfinished upload exists (U-states) | Continue import |
| E4 | Profile → Data | row | flag on | opens the flow (or resumes E3) |
| E5 | Open in | file arrives, idle | the app opens a `.csv`, nothing running | flow at Step 2, file loaded |
| E6 | Open in | signed out | no session | Sign in, then the flow continues |
| E7 | Open in | workout in progress | `SessionController` active | none now; Open when finished |
| E8 | Open in | import being set up | a flow is open at Step 1 to 5 | Replace / Keep current |
| E9 | Open in | import uploading | Step 6 or E3 active | none now; Open when finished |
| E10 | Open in | flag off | `train.import` off | OK (sheet) |
| P1 | Step 1 | pick | opened | Choose files |
| P2 | Step 1 | reading | files selected, reading | none (outline row per file) |
| P3 | Step 1 | not a CSV | wrong type | Choose another file |
| P4 | Step 1 | too large | over 8 MiB per file | Choose another file |
| P5 | Step 1 | unreadable | permission, iCloud not downloaded, not text | Try again |
| P6 | Step 1 | empty | 0 bytes or only blank lines | Choose another file |
| P7 | Step 1 | too many files | more than 6 | Choose fewer files |
| D1 | Step 2 | detected, both | plan and workouts present | Continue |
| D2 | Step 2 | detected, plan only | no workouts file | Continue / Add workouts file |
| D3 | Step 2 | detected, workouts only | no plan file | Continue / Add plan file |
| D4 | Step 2 | warnings | parser reported lines | expand the list |
| D5 | Step 2 | not supported | no format detected | Choose another file |
| D6 | Step 2 | mixed | formats differ, or one file unsupported among valid ones | Remove file |
| D8 | Step 2 | partly recognised | `ImportConfidence.weak` | review warnings / Continue |
| D7 | Step 2 | nothing in file | detected but 0 plans, 0 workouts | Choose another file |
| C1 | Step 3 | choose | default | Continue |
| C2 | Step 3 | existing active plan | an enrolment exists | the toggle default is off |
| C3 | Step 3 | nothing selected | both toggles off | Continue disabled with reason |
| C4 | Step 3 | range empty | no workouts in the chosen range | widen the range |
| M1 | Step 4 | mapping | at least one exercise | resolve rows |
| M2 | Step 4 | all matched | every row ✓ and no question | Continue |
| M3 | Step 4 | rows left | any check, new or question open | Continue disabled with count |
| M4 | Step 4 | library loading | library not cached | none (outline rows) |
| M5 | Step 4 | library unavailable | offline and no cache | Try again / Continue offline (see 6.4) |
| M6 | Step 4 | creating custom | Continue with new exercises, offline | none (they are created in Step 6) |
| V1 | Step 5 | preview | default | Import |
| V2 | Step 5 | duplicates | any flagged session | per-item toggle |
| V3 | Step 5 | nothing to import | everything skipped or already imported | none (explains) |
| V4 | Step 5 | already imported | same ids exist | Done |
| V5 | Step 5 | uploads not available | `importUploadAvailable` false | Keep on this iPhone |
| I1 | Step 6 | preparing | Import tapped | none |
| I2 | Step 6 | uploading | batches in flight | Close (continues) |
| I3 | Step 6 | done | all `created` or `unchanged` | Open plan / Open history |
| I4 | Step 6 | partly done | some `rejected` | Retry / Done |
| I5 | Step 6 | failed, retryable | network, 429, 503, 5xx | Retry (auto when back online) |
| I6 | Step 6 | offline | no network | none (kept; continues) |
| I7 | Step 6 | signed out mid-import | final 401 | sign in; the import resumes |
| I8 | Step 6 | gated | 403 with code | existing gate routes |
| I9 | Step 6 | kept, not uploaded | V5 confirmed | Done |
| N1 | Cancel | discard confirmation | Cancel at Step 2 to 5 | Discard / Keep |
| N2 | Background | app backgrounded | scene phase | state is kept |
| N3 | Relaunch | process was killed | before Step 6 | start over (file is not stored) |

## 2. Navigation, presentation and state

- **Presentation.** A `fullScreenCover` holding a `NavigationStack`, one screen per step, pushed. Full screen (not a sheet)
  because the flow is long, has a keyboard and nested sheets (picker, custom exercise, details); a sheet would stack three
  deep. The cover is presented from the Train root (one `ImportCoordinator`), so Open in, My Plans and Profile all open the
  same instance. From Profile the cover rises over the Profile tab; "Open plan" then dismisses it and switches to
  Strain → Plans → that plan.
- **Title bar.** Inline title (the step's name), leading button, trailing none. Under the bar a `StepRule`: thin segmented
  line of 6 segments (`Theme.separator` unfilled, `Theme.accent` filled up to the current step) with caption
  `textTertiary` "Step 3 of 6". When Step 4 does not apply (see 7.1) the count still says 6; Step 4 shows "All matched".
- **Back / Cancel.** Step 1: leading "Cancel", no confirmation (nothing parsed). Steps 2 to 5: system back chevron (and
  swipe-back) goes one step and keeps all choices; trailing **Cancel** text button asks N1:
  - Title "Discard this import?" Message "RYFT forgets what it read from the file and your choices here. The file itself is not
    changed." Buttons "Discard" (destructive) and "Keep going". Dismiss by swipe-down is disabled
    (`interactiveDismissDisabled`) from Step 2 on.
  - Step 6: no back chevron, no Cancel. One button "Close" (leading, text) that leaves the screen; the import continues
    (see 8.5). Never "Discard" here.
- **State kept.** `ImportFlowModel` (`@MainActor @Observable`) holds the bundle, choices and step path, so going back and
  forward, backgrounding (N2) and the keyboard never lose anything. Security-scoped file access is opened, read fully into
  memory and closed in Step 1, so a backgrounded app holds no file handle. Before the user taps Import, state is in memory
  only: if iOS kills the app (N3) the user picks the file again, and the copy on the discard alert is the only warning
  needed. **From Step 6 on** the confirmed bundle and its progress are persisted until uploaded (brief §4), per account.
- **Scene phase.** Entering the background mid-upload: the request in flight finishes if iOS allows; the rest resumes on
  the next foreground (and a `BGAppRefreshTask` where the design allows). The screen reopens at the right state (E3).
- **Reduced motion.** Step push is the system transition (already respects it). Custom motion in this spec is 250 ms or
  less and has a reduced-motion variant (no motion, state change only).

## 3. Entry points

### 3.1 My Plans → New plan → Import from file (E1, E2)

`PlansView` today ends with one secondary `TealButtonStyle` "New plan" button that opens `PlanBuilderView`.
With `train.import` on, that button becomes a `Menu` with the same label and style ("New plan", `plus`), two items:
1. "Start from scratch" (`square.and.pencil`): opens the builder as today.
2. "Import from file" (`square.and.arrow.down`): opens the flow at Step 1.
Flag off (E2): exactly today's button, no menu. The menu replaces a tap-then-choose sheet because it is one gesture and
keeps the button where users expect it. VoiceOver: "New plan, menu button"; items read their titles.

When an unfinished import exists (E3), a `ImportResumeRow` sits at the top of My Plans, above the active-plan card
(see 8.6 for its states). It is a `TrainLinkRow`-style row, not a banner that covers content.

### 3.2 Profile → Data → Import training data (E4)

In `ProfileView.data`, directly above "Export my data" (the two are data moving in and out): a tappable row
(`square.and.arrow.down`, "Import training data", detail line `textSecondary` caption, chevron). Same width and divider
as the Devices row. Detail line:
- idle: "From a CSV file"
- E3: "8 of 12 workouts uploaded" or "Waiting for a connection" or "Needs your attention" (the row opens Step 6)
- flag off: the row is not shown.
It opens the same cover at Step 1, or at Step 6 when E3 exists.

**Clear remembered matches** (new row, same section, directly below, `eraser`, `textPrimary`, detail `caption`). Shown only when `ImportMapping` has entries. Tap opens a confirmation alert: title "Clear remembered matches?", message "Your next import asks about every exercise again. Imported workouts and plans stay as they are.", buttons "Clear" (destructive) and "Cancel". After clearing the row is hidden and VoiceOver announces "Remembered matches cleared". The choices are part of Export my data (lead's decision, security-privacy confirms in I3). `accessibilityIdentifier("profile.importTraining")`.

### 3.3 "Open in RYFT" from Files and the Share sheet (E5 to E10)

The document type `public.comma-separated-values-text` only (design §9: Viewer, Alternate, open in place; the picker in
Step 1 also takes plain text, but RYFT is not offered for every `.txt`). **The `Info.plist` keys ship only in the PR that
turns `train.import` on** (lead's decision), so until then RYFT is not offered in Open in; the routing below exists and
is tested from day one. RYFT receives a file URL
in `onOpenURL` / `onOpenURLs`, not a pasted body.

Where it lands: the same flow at **Step 2, with the file already read** (Step 1 is skipped because the user already
picked). Back goes to Step 1 where "Add another file" is available. The user never has to re-pick.

| Situation | Behaviour |
| --- | --- |
| E5 idle, signed in | Switch to the Strain tab, present the cover at Step 2. Parsing runs first: while it runs, Step 2 shows its outline rows (P2). |
| E6 signed out | Read and parse the file (needs no network), hold it in memory, show the existing sign-in. After sign-in, present the cover at Step 2 (the mapping needs the library, which needs the account). If the app is killed while signed out the file is gone: nothing is stored. Sign-in screen shows a one-line `InlineMessage` (`doc.text`): "Your file is ready. Sign in to continue." |
| E7 workout in progress | Never interrupt a session. Keep the file in memory and show a quiet row on `WorkoutInProgressBanner`'s place in My Plans and in Profile → Data: "File waiting: <file name>. Open it after your workout." with button "Open now" enabled only when no session is active. No modal, no toast over the session screen. |
| E8 another import being set up (Step 1 to 5) | Alert, because one of the two must win: "Replace the import you're setting up?" Message "You're in the middle of another import. Opening this file starts over." Buttons "Replace" (default role, not destructive: nothing is lost that is stored) and "Keep current" (cancel). With "Keep current" the new file is dropped; the user can open it again from Files. |
| E9 an import is uploading | Do not replace. Banner row as E7: "An import is still uploading. Open this file when it's done." plus "View progress" (opens Step 6). The file is held in memory and offered with "Open this file" at the Step 6 result (I3/I4) and on the resume row. If the app closes, the file is gone: Files has it. |
| E10 flag off | A calm `.sheet` (medium detent): icon `doc.text`, headline "Importing isn't available on this account yet", body `callout` `textSecondary` "RYFT can't import training files for your account right now. The file wasn't read or changed.", one button "OK". Nothing is read (design §9). Because the document-type keys ship only with the flag-on PR, this state is reachable only in debug builds, tests and a build with the keys but the flag off for a remote account. |

Open in with a file that is not a supported CSV goes through the same Step 2 error states (D5, P3 to P6), so the user
always gets one explanation in one place.

## 4. Step 1: Pick

**Purpose.** Choose the file or files. Nothing is parsed before the files are read.

**Layout** (`ScrollView`, `screenPadding` 20, pinned bottom button):
1. Title (nav bar): "Import training data".
2. Headline (`ryft title`, `textPrimary`): "Import a plan and your workout history".
3. Body (`callout`, `textSecondary`): "Choose the CSV files exported from Alpha Progression: the plans file, the workouts file, or both. RYFT reads them on this iPhone. The files themselves are never uploaded or stored."
4. `ImportFileSlot` rows (see 9): two outline slots, "Plans file" and "Workouts file", each a hairline-outlined rounded rectangle (`tileRadius` 16) with an icon (`list.bullet.rectangle`, `clock.arrow.circlepath`), title, caption "Optional" (neither is required alone), and a chevron-less "Choose" affordance. The slots are **hints, not constraints**: tapping either opens the same multi-select picker; the file's content, not the slot, decides what it is.
5. Pinned teal button "Choose files" (`TealButtonStyle(prominent: true)`), always enabled.
6. Caption `textTertiary` under the button: "Save the files from the other app to Files, then choose them here." (No menu path of the other app is named.)

**Picker.** `.fileImporter(isPresented:allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: true)`.
Selection: at most 6 files (P7). Each is read off the main actor to `Data`, max 8 MiB per file (design §3), kept in memory as picked files (name, data).

**States.**

| ID | What the user sees | Action |
| --- | --- | --- |
| P2 reading | The slot rows are replaced by one outline row per selected file: file name (`callout`), caption "Reading…", hairline bar track only (no fill, no spinner). Max 2 s typical. Under reduced motion identical (nothing animates). | none |
| P3 not a CSV | `InlineMessage` (`doc.badge.ellipsis`): "“<name>” isn't a CSV file." caption "RYFT can read CSV and plain text files." | "Choose another file" |
| P4 too large | "“<name>” is larger than 8 MB." caption "Training exports are usually well under 1 MB. Is this the right file?" | "Choose another file" |
| P5 unreadable | "RYFT couldn't read “<name>”." caption "If it's in iCloud Drive, open Files and let it finish downloading, then try again." | "Try again" |
| P6 empty | "“<name>” is empty." | "Choose another file" |
| P7 | "Choose up to 6 files at a time." | "Choose files" |

Multiple files with a mix of good and bad: good ones continue to Step 2; bad ones are listed in Step 2's file list with
their reason (so the user sees which one failed, and it doesn't block the rest). If **all** files fail, the user stays on
Step 1 with the messages. Wrong type is judged by content type and by "does it decode as text" (UTF-8, falling back to
UTF-16 with BOM); extension alone is not trusted.

**Accessibility.** Reading order: headline, body, slots (each "Plans file, optional, button"), then Choose files. After a
selection VoiceOver announces "Reading 2 files". Dynamic type AX: slots stack their text under the icon; the bottom button
is full width and grows; the scroll view carries everything (nothing is cut).

## 5. Step 2: Detected

**Purpose.** Say what the app found, before asking anything. This is the screen to earn trust.

**Hierarchy.** First the sentence of counts (the facts), second the file list and warnings, last the time-zone line.

**Layout:**
1. `ImportSummaryCard` (`Card`): label `Alpha Progression export` (`ryftLabelStyle`, `textSecondary`) with a trailing
   `checkmark.circle` (`textSecondary`; teal is reserved for the button).
   Line 1 (`metric` 22, `textPrimary`, tabular): "1 plan · 2 days · 19 exercises". Line 2: "12 workouts · 8 Jun to 5 Jul 2026"
   (`callout` `textSecondary`). Full sentence for VoiceOver is one string (see below). Each figure is optional and drops
   out when 0 (plan-only: no workouts clause; workouts-only: no plan clause).
2. **Files** (when more than one file or any failed): small section "Files": one row per file: name, "Plans" or "Workouts"
   caption, `checkmark.circle` or `exclamationmark.circle` + reason. A row has a trailing `xmark` (44 x 44) to remove
   the file (D6 recovery), and the section ends with a text button "Add another file" (opens the picker; the new file
   merges).
3. **Warnings** (D4), only if any: a collapsed disclosure row `exclamationmark.circle` "3 lines couldn't be read" with
   caption "The rest imports normally." Tap expands (animation 200 ms, ease-out, none under reduced motion) a list:
   one row per warning: "Line 41" (tabular, `textSecondary`) then the reason, which is the localised text of
   `ImportWarning.Kind` ("This line isn't recognised", "No kg or lb header here: RYFT assumed kg"). **A warning carries a
   line number and a kind, never file text** (design §2, §10), so nothing from the file is shown, copied or logged here.
   Up to 20 rows are shown, then "and N more" built from the rest plus `suppressedWarnings` (counts only, no further
   expansion). Line numbers are per file, with the file name as a sub-header when there are several files (`SourceLine.file`
   indexes the picked files). Some kinds are notes, not problems, and read as such: `durationAssumed` ("No duration: 60 min
   assumed"), `assistedLoad` ("Assisted weight isn't imported, reps are"), `nonexistentLocalTime` and `repeatedLocalTime`
   (see the time-zone line), `overPlatformLimit` and `limitReached` ("Some items were left out: RYFT limits a workout to
   50 exercises and 50 sets per exercise"). The disclosure row's title counts only warnings that dropped content; notes are
   a second line "and 2 notes".
4. **Time zone** (when there is a workouts file): `clock` icon, caption `textSecondary`: "The file has no time zone. RYFT keeps its times as written and applies this iPhone's time zone, Europe/Berlin." Name from the zone captured when the flow started (`TimeZone.current`). **No override in v1** (lead's decision).
   The same line is repeated in the Step 5 History segment (see 8.1) because that is where times become real; it is *not* a control.
5. Pinned "Continue" (teal). Disabled only in D5, D7.

**States.**
- **D1 both**: as above.
- **D2 plan only**: summary has no workouts clause. Under the card an `InlineMessage` (`info.circle`): "No workouts file. Add it if you also want your workout history." button "Add workouts file" (picker). Continue is enabled: a plan alone is a valid import.
- **D3 workouts only**: summary has no plan clause. Message: "No plan file. Your workouts import as standalone sessions." button "Add plan file". Continue is enabled. Per design §8, sessions import as standalone sessions without the plan; with the plan imported, a session that names a plan in the file is linked to its day and exercise, which is what makes "last time" and targets work.
- **D8 weak detection** (`ImportConfidence.weak`): the file is parsed, and an `InlineMessage` (`questionmark.circle`) says "RYFT only partly recognised this file. Some lines weren't recognised; the rest is imported." The warnings row opens by default. `.none` is D5. A comma-separated file with a header row (another app's format) is also D5, with the caption "RYFT can't read this kind of file yet."
- **D5 not supported**: replaces the card. Icon `questionmark.folder`, headline "This isn't a supported format", body "RYFT can import exports from Alpha Progression. “<name>” doesn't look like one." caption `textTertiary` "More apps may come. Nothing was imported." Buttons: "Choose another file" (teal). There is no Continue.
- **D6 mixed**: some files detected as Alpha Progression, others not (or detected as different apps in future). Valid files carry on; invalid file row shows reason and the user may remove it. If two **different supported** formats are present (future): message "These files come from different apps. Import one at a time." with remove buttons; Continue disabled until one remains.
- **D7**: "The file is valid but has no plan and no workouts." plus "Choose another file".
- Same plan repeated across files (two plans files) merges as multiple plans; same session repeated merges by id and is counted once. No message.
- **Large**: an 8 MiB file parses off the main actor. Step 2 shows P2 outline rows with caption "Reading… 4,200 of ~9,000 lines" (tabular, updates at most every 250 ms) only if parsing takes more than 1 s. No spinner.

**VoiceOver.** The card is one element: "Alpha Progression export. 1 plan, 2 days, 19 exercises. 12 workouts from 8 June to 5 July 2026." The warnings row: "3 lines couldn't be read, collapsed, button" and expanded rows read "Line 41, Unexpected text". The time-zone line reads in full. Order: card, files, warnings, time zone, Continue.

**Dynamic Type AX3.** The count lines wrap (no truncation, `fixedSize(horizontal:false, vertical:true)`); the file row's remove button stays 44 x 44 and moves under the name; the pinned button is full width.

## 6. Step 3: Choose what to import

**Purpose.** Decide plan, history, and what happens to the active plan.

**Layout** (grouped `Card`s, spacing `sectionSpacing`):

1. **Plan** card (hidden when no plan in the file; replaced by a disabled row "No plan in the file" in D3):
   `Toggle` "Plan" (on by default), subtitle `textSecondary`: "Upper/Lower · 6 weeks · 4 days". With several plans: one toggle per plan, each with its name and "· 6 weeks · 4 days". Under the toggle when on:
   `Toggle` "Make this my active plan" with explanation, and the start-date choice (below). With several plans, "Make active" applies to one only: a `Picker` row "Active plan" listing the imported plans plus "None".
1b. **Plan states from the architect's checks** (shown in the Plan card, in place of the subtitle's reassurance):
   - **Already in RYFT** (a plan with the derived id exists): row says "Already in RYFT", the toggle is off, and a text button "Replace with the file's version" turns it on with the caption "This replaces your copy, including edits." Default keeps RYFT's copy (design §6).
   - **Can't be imported** (more than 7 days, or it fails the plan checks): toggle off and disabled, reason in `textSecondary` ("This plan has 9 days. RYFT plans have at most 7."). History can still be imported.
2. **Workout history** card (hidden in D2; disabled row "No workouts in the file" if the file has none):
   `Toggle` "Workout history" (on by default) with the subtitle "12 workouts · 31 sets" and, when on, a `DateRangeControl`:
   a `Picker` (menu style, row) "Range" with options "All time", "Last 12 months", "Last 3 months", "Custom"; for Custom two compact `DatePicker`s "From" and "To", limited to the file's first and last day. The row beneath states the result in tabular figures: "12 workouts from 8 Jun to 5 Jul 2026". **Default: All time** (the user came to bring history over; narrowing is the exception). Sessions dated in the future (clock or zone issues) are excluded and counted in Step 5 ("1 workout in the future was left out").
3. **Active plan** details (when "Make this my active plan" is on): there is **no start-date choice**. Enrolment always
   starts at week 1, day 0 today (design §8: "from the file's start date" and "continue where I am" need the platform's
   T8 and stay hidden until then). A caption states it: "Starts today, at week 1." The file's own start date is shown
   nowhere as an option, so no screen can promise something enrolment can't do. When T8 lands, the two choices from the earlier draft come
   back (Today / the file's start date, with "This plan would already be over" disabling a past date).
4. **C2: an existing active plan.** When the user is enrolled (`library.currentPlanID` set; paused counts as existing):
   - The toggle "Make this my active plan" defaults to **off**; importing must not change someone's training silently.
   - When the user turns it on, the footer text becomes: "This replaces your current plan, “Upper/Lower · 6 weeks”, which is in week 3. It stays in My Plans and you can switch back." The existing enrol call (`library.enroll(in:)`) already replaces the enrolment; this copy just says so. No extra confirmation alert (the sentence is the confirmation and it is reversible).
   - Paused current plan: "Your current plan is paused. Making this one active replaces it."
   - Without an existing plan the default is **on** and the footer says "You can change this later in Plans."
5. **Footnotes** `caption` `textTertiary`: "Imported workouts count towards strain on their days. Past strain can change once." only when History is on.
6. Pinned "Continue", disabled with reason in C3 (both off): a `textSecondary` caption above the button: "Turn on at least one to continue."

**States.**
- C3: as above.
- C4 range empty: the range row reads "0 workouts in this range" with `exclamationmark.circle`; the History card stays on; Continue is disabled while the toggle is on and the count is 0, with caption "Widen the range or turn history off."
- Plan-only (D2) hides the History card entirely; History-only hides the Plan card.

**Interactions.** Toggles are the system `Toggle` with `tint(Theme.accent)`. Changing the range updates the count
immediately (no animation needed; a 150 ms cross-fade of the number, none under reduced motion). The picker is a
menu; custom dates reveal with a 200 ms height animation.

**VoiceOver.** "Plan, Upper/Lower, 6 weeks, 4 days, switch, on." "Make this my active plan, switch, off. This replaces ..." (the
footer is attached as `accessibilityHint`). Range: "Range, All time, 12 workouts from 8 June to 5 July 2026, button".

**Dynamic Type AX.** Toggle rows keep their label on top and the switch trailing (the system handles it); the segmented
start-date options stack as full-width tiles.

## 7. Step 4: Map exercises

**Purpose.** Every distinct imported exercise is matched to a RYFT library exercise exactly once. This is the correctness
step: all later e1RM and "last time" depend on it.

**Hierarchy.** First the count line (how many need you), then the rows that need you, then the matched ones.

### 7.1 Layout

1. **Count line** (`metric`-style numbers, tabular), `Card`-less, at the top: "19 exercises" and under it `callout` `textSecondary`:
   "15 matched · 3 to check · 1 new". When 0 needs attention (M2): "All 19 matched. Check them if you like." and the screen is
   shown anyway (never skipped silently: the user may want to verify) but the button reads "Continue".
2. **Controls** (only when more than 8 exercises): `.searchable` on the stack (prompt "Search exercises", searches both the
   file's name and the matched name) and a two-option `SegmentedPicker`: "All" and "Needs a check (4)". The count is live.
   Search and filter keep their state when going back and forward.
3. **List** in two sections with `TrainSectionTitle`: "Needs your attention" first, then "Matched". Each exercise appears
   once, with the weeks where it appears hidden (this is history, not an error that week 4 has a different exercise). A
   row for an exercise that appears only in the plan or only in history shows a trailing caption "Plan only" / "History
   only" so the user knows why it is there.
4. **Bulk action** (only when there are "check" rows and no "new" rows being forced): a text button above the list
   "Accept 3 likely matches". It confirms nothing destructive: it marks all fuzzy suggestions as chosen, remains undoable
   row by row, and VoiceOver announces "3 matches accepted".
5. **Footer** `caption` `textTertiary`: "RYFT remembers your choices for next time. They're part of Export my data, and you can clear them in Profile → Data." Choices are saved when Import is tapped, never per tap, so an abandoned flow changes nothing. A remembered match shows "Matched · from your earlier choice" (`ExerciseMatch.Tier.remembered`).
6. Pinned "Continue", disabled in M3 with a caption above: "4 left to check." (tabular; counts rows that are `check` (`Tier.fuzzy`), `new` (no match)
   without a muscle group, ; the bodyweight question has a default and never counts).

### 7.2 The row (`ExerciseMatchRow`)

Two lines in a left column and a status block trailing; the whole row is a button that opens the row's actions.
- Line 1 `body` `textPrimary`: the **file's name** as written, e.g. "Bench Press" and the equipment in `textSecondary` ("· Barbell").
- Line 2 `callout`: a `arrow.turn.down.right` glyph and the **RYFT exercise** the row maps to (`textPrimary`), e.g. "Barbell bench press".
- Trailing status (glyph + word, `caption`, never colour only):

| Match | Glyph | Word | Default state | Blocks Continue |
| --- | --- | --- | --- | --- |
| exact or alias | `checkmark.circle` (`textSecondary`) | "Matched" | accepted | no |
| fuzzy | `questionmark.circle` (`textPrimary`, stronger so it draws the eye) | "Check" | the suggestion is pre-selected but **not accepted** | yes until tapped |
| none | `plus.circle` | "New" | will create a custom exercise named like the file's | until the muscle group is set |
| user chose another | `checkmark.circle` | "Your choice" | accepted | no |
| skipped | `minus.circle` | "Skipped" | excluded | no |

Confidence is **words, not percentages**: a fuzzy row's detail line reads "Likely match" (high) or "Possible match"
(low); a percentage invented by token overlap would look more precise than it is. The words are the only confidence
display; VoiceOver reads them.

Trailing area also shows a `scalemass` glyph + "Question" when the bodyweight question is open (7.4).

### 7.3 Row actions (sheet from the row)

Tapping a row opens a `confirmationDialog` (iOS 17: popover on iPad) titled with the file's name:
1. "Use <Barbell bench press>" (only for check rows): accepts the suggestion.
2. "Choose another exercise…": opens the existing `AddExerciseSheet(title: "Match “Bench Press”")` as a sheet from the flow
   (reuse as is; its `onPick` returns the library exercise). The sheet starts with the search field prefilled with the
   file's name, muscle/kind filters as today.
3. "Create a custom exercise…": opens the existing `CustomExerciseForm(name:)` prefilled with the file's name; **Assumes** a
   small extension: `kind` preselected from the equipment word (else machine, as design §4), `load_type` bodyweight for bodyweight equipment or `+N`
   sets, name limited to 80 characters, and the muscle picker left empty until chosen. (The brief says name + equipment + muscle group; the form's
   "Kind" is the library's equipment field. No new form is built.)
4. "Skip this exercise": excluded. The footnote in the dialog: "Its sets aren't imported and it's removed from the plan."
5. "Cancel".
The dialog message shows what the row currently maps to.

A "new" row's "Create" is also directly offered as a primary inline button "Create as custom exercise" in the row
when its muscle group is missing (so the user doesn't need to open the dialog first). Choosing a muscle there
(one `Menu` "Muscle group") is enough; name and equipment come from the file.

Offline: the library comes from the cache; "Create a custom exercise" queues the `POST /v1/exercises` for Step 6
(row says "New · created when you import"). If there is **no** cached library, see M5.

### 7.4 The bodyweight question (inline)

**Decision: inline on the row, not a sheet.** It belongs to one exercise, it is asked once per exercise, there are usually
one to three such rows, it needs three equal choices and a one-line explanation, and a sheet on top of a sheet
(the picker flow) would be the third nested presentation. It also lets the user see the exercise it concerns while
answering.

When an imported exercise has `+N` sets (`ImportedLoad.plus`), its row expands (200 ms, none under reduced motion), with a
hairline top rule and an indent of 16 (no nested surface). The question and its options depend on the matched exercise's
`load_type` (design §5), and the answer is a `BodyweightAnswer` (`addedWeight`, `bodyWeight`, `ignore`).

- Question `callout` `textPrimary`: "‘+20’ for Dips: is that added weight, or your body weight?" N is the most frequent `+N`
  for that exercise; the caption says "Seen on 8 sets." or "Seen on 8 sets with different values."
- **`bodyweight` exercise: three equal options** (`SelectableTile`, full width, min height 44, selected = filled radio, not colour alone):
  1. "Added weight": "Each set adds 96 kg to your body weight." (`weight_kg = N`)
  2. "Body weight": "The number is your own weight. RYFT logs the sets without added weight and notes 96 kg as your body weight for the workout." Offered only when 30 to 300 kg (design §5); otherwise hidden.
  3. "Ignore": "Import the reps only."
- **`weight` exercise** (the user picked a loaded exercise for a bodyweight-style source): **two options**: "96 kg is the weight" (`addedWeight`) and "Ignore" (reps only). The row also says "The file logs this as a bodyweight exercise."
- **`time`/`distance` exercise:** not asked; the weight is left out and the row says so in `textTertiary`.
- **Default and blocking.** A default is pre-selected (design §5): "Body weight" when N is the same on every set and within
  30 to 300 kg, otherwise "Added weight". The question is therefore **never a blocker** and doesn't count in "left to check".
  Its row sits in "Needs your attention" with the glyph `scalemass` and the word "Question", and moves to "Matched" once the
  user taps any option (including the default). Answered, the row collapses to a tag beside the match name, tappable to change.
- **Assisted (`-N`):** no question. The row shows a calm line `callout` `textSecondary` with `info.circle`: "Assisted sets: RYFT
  imports the reps and leaves out the assistance weight." (`ImportWarning.Kind.assistedLoad`, also listed in Step 2 notes.)
- The answer is remembered per source exercise (`ImportMapping.bodyweightRaw`).
- The question appears only for exercises with `+N` sets in the workouts file. Plan files carry no `+N`, so plan-only imports never see it.

### 7.5 States

- **M4 loading**: first 6 outline rows (hairline rounded rect, no fill, no shimmer) and caption "Loading the exercise library…". Continue disabled. No spinner.
- **M5 library unavailable** (offline and nothing cached): showing every row as "New" would be wrong, so
  the screen shows `InlineMessage` (`wifi.exclamationmark`): "The exercise library isn't available offline yet." caption "RYFT needs it to match exercises." and "Try again". Continue is disabled. A text button "Back" is the other path. No partial matching without the library.
- **M6**: Continue with "new" exercises while offline is allowed: the footer says "3 new exercises are created when you import."
- **Many exercises** (e.g. 60): the two sections, search, and the filter segment. The list is a `LazyVStack`; section headers pin. The count line stays at the top as a non-pinned header; the "left to check" caption is in the pinned bottom bar so the user always sees it.
- **Empty search**: `InlineMessage` (`magnifyingglass`) "No exercise matches “xyz”."

### 7.6 Motion, VoiceOver, Dynamic Type

- Accepting or answering moves the row from "Needs your attention" into "Matched" with a 200 ms ease-out move; reduced motion: the row switches section with no movement. VoiceOver announces "<name>, now matched. 3 left to check."
- A row reads as one element: "Bench Press, Barbell, matched to Barbell bench press, exact match, button. Actions: use suggestion, choose another, create custom, skip." Custom actions (`accessibilityAction`) mirror the dialog so VoiceOver users don't have to open it. Bodyweight rows read "question open: is +20 added weight or your body weight".
- AX3: the row's status block moves below line 2 as one line "Check · likely match" (glyph + words); the question options stack and stay 44 pt tall; the bulk text button wraps.

## 8. Step 5: Preview, and Step 6: Import

### 8.1 Preview layout (V1)

**Purpose.** Show exactly what will be created. This is the last stop before data leaves the iPhone.

1. Top **summary line** (tabular): "1 plan · 12 workouts · 31 sets · 9,420 kg" (volume in the user's unit setting, same
   formatting as History). `callout` `textSecondary` beneath: "3 sets skipped · 1 workout looks like one you already logged".
2. **Segmented control** (`SegmentedPicker`): "Plan" and "History" (hidden when only one exists; the segment keeps its
   scroll position when you switch).
3. **Plan segment.** The plan as RYFT will show it, using the **same layout as `PlanDetailView`'s read-only days**
   (`TrainLinkRow`-style exercise rows with `targetText`): header with the **plan name as a `TextField`** (editable;
   required, max 80 characters, "Plan name" label), summary "6 weeks · 4 days/week" (`planSummaryText`), the days with
   sets × reps. If a plan exercise is mapped to a bodyweight library exercise the row says "Bodyweight". Skipped
   exercises are listed once at the bottom, "Not imported (1): Wrist Curl · Cable".
   **"Last time" prefill.** When History is on, each plan exercise that has an imported session shows a second line
   `caption` `textSecondary`: "Starts at 60 kg · last time, 5 Jul". Tabular. When History is off or an exercise has no
   history the row shows the plan's target as RYFT builds it without history: **"RPE 8"** (design §8: the plan checks refuse an empty
   kg target, and RPE shows no weight, which is the brief's "leave empty"); bodyweight exercises show "Bodyweight". The load shown with history is the
   **heaviest performed set of the most recent imported session** with that exercise, the same plan day first. A help footnote: "Last time comes from your imported
   workouts."
4. **History segment.** A `LazyVStack` of `ImportSessionRow`, grouped by month (`TrainSectionTitle` "June 2026"), newest
   first, same as the file. Row: date short and weekday (`body`), title (e.g. "Upper" or "Upper · Day 1, week 2"),
   caption "9 exercises · 31 sets · 11,420 kg" (tabular), trailing:
   - normal: a toggle `Image("checkmark.circle.fill")`-style control, 44 x 44, "Included" (word shown at AX only);
   - skipped sets inside the session: a second caption `textTertiary` "2 sets skipped".
   Tap the row (not the toggle) opens a read-only `ImportSessionDetailSheet`: the exercises and their sets
   ("1  60 kg × 10"), skipped sets shown as "Skipped · no weight or reps" in `textTertiary`.
   Per-section footers explain the skip reason: "Skipped sets have no weight or no reps. They are counted, not imported as zero."
5. **Duplicates (V2).** Rows that overlap an existing RYFT session (same day, at least 70 % of exercises in common) show a
   leading glyph `rectangle.on.rectangle` and the caption "Looks like a session you already logged" in `textPrimary`
   (the one-glance cue; no colour), and the control is **off** by default (Skip). The section header collapses all
   flagged items: first in the History segment an `InlineMessage` (`rectangle.on.rectangle`) "2 workouts look like ones you already logged. They're skipped unless you turn them on." with a text button "Review". The control's off state reads "Skipped". Toggling one back on shows a
   short note in the row: "Will be imported next to your own session." Nothing is merged.
   Sessions that were already imported earlier (their derived id exists on the platform) show "Already imported" (`checkmark.circle`, no toggle) and are not
   counted in the totals.
6. **Other count lines** (history segment, below totals), only when they apply: "1 workout in the future was left out", "4 workouts are before your chosen start date".
6b. **Time-zone line** (History segment, above the list, `clock` icon, `caption` `textSecondary`): "Times are kept as written in the file and shown in Europe/Berlin." When any warning of kind `nonexistentLocalTime` or `repeatedLocalTime` exists, a second line: "2 workouts fall on a clock change. RYFT used the next valid time for one and the first of two for the other." Affected rows carry `clock.badge.exclamationmark` and "Clock change" in their caption, and their detail sheet names the rule in words ("This time didn't exist in your time zone, so RYFT used the next valid time"), without file text. Dates and the day grouping use the same zone.
6c. **Offline duplicate check.** The preview needs the network to check for duplicates and for ids that already exist (design §6). When it
   can't: an `InlineMessage` (`wifi.exclamationmark`) at the top of the History segment: "You're offline, so RYFT couldn't check for duplicates yet." caption "It checks again before uploading. Workouts that look like ones you already logged are skipped and listed on the result screen, where you can import them anyway." No row is flagged, no totals claim "0 duplicates", and the summary subline omits the duplicates clause. The Import button still works. The job is saved with `duplicatesChecked = false`.
7. **Footer** `caption` `textTertiary`: "Imported workouts count towards strain on their days, so past strain can change once. You won't get record notifications for them. RYFT sends only what's listed here. The file stays on your iPhone."
8. Pinned button: "Import 1 plan and 12 workouts" (the label carries the counts so the action is unambiguous; plural rules below; 1 line, wraps at AX).

**States.**
- V3 nothing to import: the summary says "Nothing to import" with the reason ("All workouts are skipped or already imported.") and the button is disabled. Back is the only path.
- V4 already imported: all items have existing ids. Summary: "This file is already in RYFT. Nothing new to import." Button "Done" (closes). No upload happens.
- V5 uploads aren't available yet: replaces the Import button area with `InlineMessage` (`icloud.slash`): "Uploads aren't available yet." caption "RYFT can keep this import on your iPhone and upload it when importing is switched on for your account." and the pinned button changes to "Keep on this iPhone" (teal). Tapping persists the confirmed bundle and shows the result state I9. (The same text appears if a request returns "not available".) Because the feature is flag-dark, V5 is the state actually visible whenever the flag is on but the platform contract is not live; see the demo scenario in §12.
- Plan name empty: the text field shows `exclamationmark.circle` "Give the plan a name." and the button is disabled.
- A plan day with every exercise skipped: row "Day 3 · Legs" says "No exercises (all skipped)". It still imports; the footnote lists it. If the **whole plan** has no exercises, Plan segment disabled and the plan is excluded (counted: "The plan has no exercises left").

**VoiceOver.** The summary is one element. Plan segment reads the name field first ("Plan name, text field, Upper/Lower"). The "Last
time" line is an `accessibilityValue`-style part of the exercise row: "Bench Press, 4 sets of 10 reps, starts at 60 kilograms, last time on 5 July". Session rows read "5 July, Upper, 9 exercises, 31 sets, 11,420 kilograms, included, switch" and duplicates "...looks like a session you already logged, skipped, switch".

**Dynamic Type AX.** Session rows stack: title, caption lines, then the control as a full-width row "Included / Skipped"; the segmented control becomes a vertical two-option menu picker (`SegmentedPicker` falls back to a menu at accessibility sizes: existing behaviour assumed; if not, the developer applies `Picker(.menu)`).

### 8.2 Step 6: Import (progress and result)

**Layout.** One screen with a state header, a thin progress bar (determinate), a counts list and the result actions. No back chevron. A text "Close" leading.

**I1 preparing.** Header "Getting ready" `title`; line `callout` `textSecondary` "Creating 3 custom exercises…" (only if needed), then "Preparing your import…". Bar track outline only (no fill).
**I2 uploading.** Header "Importing…". Bar fills by items: `Theme.accent` fill, `Theme.separator` track, 4 pt tall, rounded. Under it a tabular line "8 of 12 workouts" and, if a plan, "Plan: done". Progress moves at most every 250 ms with a 150 ms ease-out (none under reduced motion). Under the bar: "You can close this. The import continues while RYFT is open and picks up where it stopped." Button "Close" in the nav bar.
**I3 done.** Header "Done" with `checkmark.circle` (`textSecondary`; one accent). The **result sentence** is the first thing, big (`headline`): "Imported 1 plan and 12 workouts". Under it a counts list (`StatRow`s, tabular): "Plan: Upper/Lower · 6 weeks", "Workouts: 12", "Sets imported: 28", "Sets skipped: 3" with the helper "No weight or reps." and "Already in RYFT: 2 workouts left as they were" (if any). The sentence variants:
- Both with skips: "Imported 1 plan and 12 workouts · 3 sets skipped (no weight or reps)". On one line when it fits, otherwise the
  sentence and the skipped part wrap to a second line.
- Plan only: "Imported 1 plan".
- Workouts only: "Imported 12 workouts".
- Nothing new but valid: "Nothing new: everything in the file was already in RYFT".
Buttons: if a plan was imported: **"Open plan"** (teal) and "Open history" (secondary); else **"Open history"** (teal) only. "Done" is the trailing nav text button. Footer: "Past strain on these days is being recalculated. It may take a minute to show." (shown only when History was imported).
  - Open plan: dismisses the cover, selects Strain → My Plans and pushes `TrainRoute.plan(id)`. Open history: the same, to the history view.
  - "Open this file" row (E9): if a file is waiting, a text row "Open the file you just received" above the buttons.
**I4 partly done.** Header "Some items weren't imported". The sentence: "Imported 1 plan and 9 workouts · 3 workouts not imported". An expandable "Not imported (3)" list: each row date + title (from the file) + reason in plain words from the platform's `results`: "The exercise wasn't found", "The date is invalid", "Rejected by the server". Details toggle (`InlineMessage`'s existing "Details") carries the request ID and status. Buttons: **"Retry 3"** (teal; continues with only the failed ids, never resubmits the rest) and "Done". Every retry updates the counts in place.
**Duplicates found at upload** (after an offline preview): the result lists "3 workouts looked like ones you already logged and were skipped" as an expandable row with a text button "Import these too", which sends only those ids (idempotent).
**I5 failed, retryable.** Network failure, `429`, `503` or 5xx. `InlineMessage` (`wifi.exclamationmark`): "The upload paused." caption: "Your import is kept on this iPhone. RYFT retries when the connection is back." plus "Try again" and Details (request ID). `429`/`503` honour `Retry-After` and show "Trying again in 30 seconds" tabular, counting down only text every second (no animation). Never signs out.
**I6 offline.** `SyncStatusLineView(line: .offline)` style line plus: "You're offline. Your import is kept on this iPhone and continues when you're back online." The bar shows the last progress (frozen, with a hollow end cap). Close is available.
**I7 signed out mid-import.** Final `401` after the one refresh: existing sign-in; after signing in the same account the import resumes. A different account: the persisted bundle is not uploaded; the row says "This import belongs to another account." with a single "Discard import".
**I8 gated.** `403` with `code`: routes to the existing invite or consent gate, then returns to the screen.
**I9 kept, not uploaded** (from V5): header "Ready". Sentence "Your import is saved on this iPhone." caption "It uploads when importing is available for your account." Buttons: "Done". The Profile row and My Plans resume row read "Saved on this iPhone: 12 workouts, 1 plan".

**Leaving and resuming.**
- Close during I1/I2/I5/I6/I9: the cover dismisses; the import continues if possible; the `ImportResumeRow` shows on My Plans and in Profile → Data.
- Resume row copy by state: "Import uploading · 8 of 12" (outline determinate hairline under the text, 2 pt), "Import paused · waiting for a connection", "Import needs attention · 3 workouts not imported", "Import saved on this iPhone". Tap opens Step 6 at the matching state. When complete the row disappears after the user has seen I3 once; if the user never opened it, the row becomes "Import finished: 12 workouts" with a "Dismiss" button; it clears after 7 days.
- **A job still uploading when a new import starts** (from New plan, Profile or Open in): a second import never starts. "Import from file" and "Import training data" open **Step 6 of the running job** with a first line "An import is in progress. Finish it before starting another." The menu item and the Profile row carry the same detail line. Open in follows E9. If the platform answers a second import with `429` and `Retry-After` (design T9), the text is the paused state's ("Trying again in 30 seconds"), never an error.
- **Saved imports expire.** An upload job is kept until done and seen, and at most 30 days; after that it is removed and the row disappears. A job older than 30 days that wasn't finished says nothing on screen except that the row is gone (the Profile row detail returns to "From a CSV file").

**Accessibility (Step 6).** The sentence is the first focus item and is announced on completion ("Import finished. Imported 1 plan and 12 workouts"). Progress is an `accessibilityValue` "67 percent, 8 of 12 workouts" updated at most every 2 s (announce only at 25 % steps). Errors are announced once.

**Dynamic Type AX.** Counts list rows stack label over value; buttons are full width, primary first.

## 9. Components

**Reuse unchanged:** `Card`, `CardHeader`, `StatRow`, `SelectableTile`, `SegmentedPicker`, `InlineMessage`, `TealButtonStyle`,
`PressableButtonStyle`, `TrainSectionTitle`, `TrainLinkRow`, `LoadChip`, `PrimaryButton`, `SyncStatusLineView`, `AddExerciseSheet`,
`CustomExerciseForm` (see extension below), `ExerciseRow`, `PlanDetailView`'s day/exercise rows (extract to a shared
read-only `PlanDayList` if they are private).

**New** (all token-only, with `#Preview`s dark, light and AX3):
| Component | Path | What |
| --- | --- | --- |
| `StepRule` | `Ryft/Design/StepRule.swift` | thin n-segment progress line + "Step n of N" caption; VoiceOver "Step 3 of 6" |
| `ImportFileSlot` | `Ryft/Features/Train/Import/ImportFileSlot.swift` | outline slot, states empty / reading / read / failed |
| `ImportSummaryCard` | `Ryft/Features/Train/Import/ImportSummaryCard.swift` | the counts card (Step 2) with its accessibility sentence |
| `ImportWarningsList` | `Ryft/Features/Train/Import/ImportWarningsList.swift` | collapsed/expanded warning rows with line numbers |
| `DateRangeControl` | `Ryft/Features/Train/Import/DateRangeControl.swift` | preset menu plus custom From/To |
| `ExerciseMatchRow` | `Ryft/Features/Train/Import/ExerciseMatchRow.swift` | the mapping row, all match states, AX layout |
| `BodyweightQuestion` | `Ryft/Features/Train/Import/BodyweightQuestion.swift` | the inline three-option question |
| `ImportSessionRow` | `Ryft/Features/Train/Import/ImportSessionRow.swift` | history row with include control, duplicate and skipped-set states |
| `ImportSessionDetailSheet` | `Ryft/Features/Train/Import/ImportSessionDetailSheet.swift` | read-only exercise and sets |
| `ImportProgressBar` | `Ryft/Design/ImportProgressBar.swift` | determinate hairline bar, hollow-end paused variant (could be reused later; keep name generic if the lead prefers `ProgressRule`) |
| `ImportResumeRow` | `Ryft/Features/Train/Import/ImportResumeRow.swift` | the My Plans / Profile resume row |
| `ImportFlowView` (+ per-step views) | `Ryft/Features/Train/Import/` | feature views (ios-developer's): `ImportPickView`, `ImportDetectedView`, `ImportChooseView`, `ImportMapView`, `ImportPreviewView`, `ImportResultView`; `ImportFlowModel` |

**Changes to existing files:** `PlansView` (New plan becomes a `Menu`; resume row), `ProfileView.data` (the row),
`CustomExerciseForm` (accept `kind` and an optional initial muscle; today it only takes `name`).

## 10. Dark and light, contrast, Dynamic Type

- All colours from `Theme`: text on `Theme.background`/`Theme.surface` only at `textPrimary` / `textSecondary` (both at least
  4.5:1 in both appearances); `textTertiary` is used only for captions with no required information that is
  not also reachable elsewhere (footnotes, excerpts). Warning amber is an icon only, never text.
- Hairlines: `Theme.separator`, 1 pt. Surfaces: `Theme.surface` (cards), `Theme.surfaceRaised` (selected tiles).
- Dynamic Type to AX3: no fixed-height rows; every HStack that holds text and a control switches to a `VStack` at
  `dynamicTypeSize.isAccessibilitySize` (the `InlineMessage` pattern). Pinned bottom bar grows; the scroll content gets
  matching bottom inset. Numbers keep `monospacedDigit`.
- Landscape and iPad: content max width 560 centred.

## 11. Copy table (en | de)

Plural forms are String Catalog variations (`one`/`other`; German the same). `%lld` is a count. German is du-form.
This is a draft: the localization-editor finalises it.

| Key / context | en | de |
| --- | --- | --- |
| New plan menu: scratch | Start from scratch | Von Grund auf neu |
| New plan menu: import | Import from file | Aus Datei importieren |
| Profile row | Import training data | Trainingsdaten importieren |
| Profile row detail, idle | From a CSV file | Aus einer CSV-Datei |
| Flow title | Import training data | Trainingsdaten importieren |
| Step caption | Step %lld of %lld | Schritt %lld von %lld |
| Step names | Choose files · Detected · What to import · Match exercises · Preview · Import | Dateien wählen · Erkannt · Was importieren · Übungen zuordnen · Vorschau · Import |
| Step 1 headline | Import a plan and your workout history | Importiere einen Plan und deinen Trainingsverlauf |
| Step 1 body | Choose the CSV files exported from Alpha Progression: the plans file, the workouts file, or both. RYFT reads them on this iPhone. The files themselves are never uploaded or stored. | Wähle die CSV-Dateien aus dem Alpha-Progression-Export: die Plan-Datei, die Workout-Datei oder beide. RYFT liest sie auf diesem iPhone. Die Dateien selbst werden nie hochgeladen oder gespeichert. |
| Slot titles | Plans file · Workouts file · Optional | Plan-Datei · Workout-Datei · Optional |
| Choose files | Choose files | Dateien wählen |
| Step 1 hint | Save the files from the other app to Files, then choose them here. | Speichere die Dateien aus der anderen App in Dateien und wähle sie dann hier aus. |
| Reading | Reading… | Wird gelesen … |
| Reading lines | Reading… %lld of ~%lld lines | Wird gelesen … %lld von ca. %lld Zeilen |
| Not a CSV | “%@” isn't a CSV file. | „%@“ ist keine CSV-Datei. |
| Not a CSV caption | RYFT can read CSV and plain text files. | RYFT kann CSV- und Textdateien lesen. |
| Too large | “%@” is larger than 8 MB. | „%@“ ist größer als 8 MB. |
| Too large caption | Training exports are usually well under 1 MB. Is this the right file? | Trainingsexporte sind meist deutlich kleiner als 1 MB. Ist das die richtige Datei? |
| Unreadable | RYFT couldn't read “%@”. | RYFT konnte „%@“ nicht lesen. |
| Unreadable caption | If it's in iCloud Drive, open Files and let it finish downloading, then try again. | Liegt sie in iCloud Drive, öffne Dateien und warte, bis sie geladen ist. Versuche es dann erneut. |
| Empty file | “%@” is empty. | „%@“ ist leer. |
| Too many files | Choose up to 6 files at a time. | Wähle höchstens 6 Dateien auf einmal. |
| Choose another file | Choose another file | Andere Datei wählen |
| Try again | Try again | Erneut versuchen |
| Summary label | Alpha Progression export | Alpha-Progression-Export |
| Plans count | %lld plan(s) | %lld Plan / %lld Pläne |
| Days count | %lld day(s) | %lld Tag / %lld Tage |
| Exercises count | %lld exercise(s) | %lld Übung / %lld Übungen |
| Workouts count | %lld workout(s) | %lld Workout / %lld Workouts |
| Date range | %@ to %@ | %@ bis %@ |
| Detected sentence (VO) | Alpha Progression export. %@. %@. | Alpha-Progression-Export. %@. %@. |
| Files section | Files | Dateien |
| Add another file | Add another file | Weitere Datei hinzufügen |
| Remove file | Remove file | Datei entfernen |
| Warnings row | %lld line(s) couldn't be read | %lld Zeile konnte nicht gelesen werden / %lld Zeilen konnten nicht gelesen werden |
| Warnings caption | The rest imports normally. | Der Rest wird normal importiert. |
| Warning row | Line %lld | Zeile %lld |
| Warnings more | and %lld more | und %lld weitere |
| Time zone | The file has no time zone. RYFT keeps its times as written and applies this iPhone's time zone, %@. | Die Datei enthält keine Zeitzone. RYFT übernimmt die Zeiten wie notiert und wendet die Zeitzone dieses iPhones an: %@. |
| Plan-only message | No workouts file. Add it if you also want your workout history. | Keine Workout-Datei. Füge sie hinzu, wenn du auch deinen Trainingsverlauf importieren willst. |
| Add workouts file | Add workouts file | Workout-Datei hinzufügen |
| Workouts-only message | No plan file. Your workouts import as standalone sessions. | Keine Plan-Datei. Deine Workouts werden als einzelne Workouts importiert. |
| Add plan file | Add plan file | Plan-Datei hinzufügen |
| Unsupported headline | This isn't a supported format | Dieses Format wird nicht unterstützt |
| Unsupported body | RYFT can import exports from Alpha Progression. “%@” doesn't look like one. | RYFT kann Exporte von Alpha Progression importieren. „%@“ sieht nicht danach aus. |
| Unsupported caption | More apps may come. Nothing was imported. | Weitere Apps können folgen. Es wurde nichts importiert. |
| Mixed apps | These files come from different apps. Import one at a time. | Diese Dateien stammen aus verschiedenen Apps. Importiere sie nacheinander. |
| Empty content | The file is valid but has no plan and no workouts. | Die Datei ist gültig, enthält aber weder Plan noch Workouts. |
| Continue | Continue | Weiter |
| Plan toggle | Plan | Plan |
| Plan subtitle | %@ · %lld week(s) · %lld day(s) | %@ · %lld Woche / %lld Wochen · %lld Tag / %lld Tage |
| No plan in file | No plan in the file | Kein Plan in der Datei |
| History toggle | Workout history | Trainingsverlauf |
| No workouts in file | No workouts in the file | Keine Workouts in der Datei |
| Range | Range | Zeitraum |
| Range presets | All time · Last 12 months · Last 3 months · Custom | Gesamter Zeitraum · Letzte 12 Monate · Letzte 3 Monate · Eigener Zeitraum |
| From / To | From · To | Von · Bis |
| Range result | %lld workout(s) from %@ to %@ | %lld Workout / %lld Workouts vom %@ bis %@ |
| Range empty | 0 workouts in this range | 0 Workouts in diesem Zeitraum |
| Range empty hint | Widen the range or turn history off. | Erweitere den Zeitraum oder schalte den Verlauf aus. |
| Make active | Make this my active plan | Als meinen aktiven Plan festlegen |
| Active help, none | You can change this later in Plans. | Du kannst das später unter Pläne ändern. |
| Active help, existing | This replaces your current plan, “%@”, which is in week %lld. It stays in My Plans and you can switch back. | Das ersetzt deinen aktuellen Plan „%@“ in Woche %lld. Er bleibt unter Meine Pläne, du kannst jederzeit zurückwechseln. |
| Active help, paused | Your current plan is paused. Making this one active replaces it. | Dein aktueller Plan ist pausiert. Wenn du diesen aktivierst, ersetzt er ihn. |
| Starts today | Starts today, at week 1. | Startet heute in Woche 1. |
| Plan already there | Already in RYFT | Schon in RYFT |
| Replace plan | Replace with the file's version | Durch die Version aus der Datei ersetzen |
| Replace plan caption | This replaces your copy, including edits. | Das ersetzt deine Kopie samt Änderungen. |
| Plan too long | This plan has %lld days. RYFT plans have at most 7. | Dieser Plan hat %lld Tage. RYFT-Pläne haben höchstens 7. |
| Weak detection | RYFT only partly recognised this file. Some lines weren't recognised; the rest is imported. | RYFT hat diese Datei nur teilweise erkannt. Einige Zeilen wurden nicht erkannt, der Rest wird importiert. |
| Format not readable yet | RYFT can't read this kind of file yet. | RYFT kann diese Art von Datei noch nicht lesen. |
| Warning kinds | This line isn't recognised · No kg or lb header here: RYFT assumed kg · No duration: 60 min assumed · Assisted weight isn't imported, reps are · Some items were left out: RYFT limits a workout to 50 exercises and 50 sets per exercise | Diese Zeile wird nicht erkannt · Hier fehlt eine kg/lb-Kopfzeile: RYFT nimmt kg an · Keine Dauer: 60 Min. angenommen · Entlastungsgewicht wird nicht importiert, die Wiederholungen schon · Einiges wurde ausgelassen: RYFT begrenzt ein Workout auf 50 Übungen und 50 Sätze je Übung |
| Warnings notes | and %lld note(s) | und %lld Hinweis / und %lld Hinweise |
| Preview time zone | Times are kept as written in the file and shown in %@. | Zeiten bleiben wie in der Datei notiert und werden in %@ angezeigt. |
| Clock change | %lld workout(s) fall on a clock change. RYFT used the next valid time for a time that didn't exist and the first for one that occurred twice. | %lld Workout fällt auf eine Zeitumstellung. / %lld Workouts fallen auf eine Zeitumstellung. RYFT nimmt für eine nicht existierende Uhrzeit die nächste gültige und für eine doppelte die erste. |
| Clock change row | Clock change | Zeitumstellung |
| Offline duplicates | You're offline, so RYFT couldn't check for duplicates yet. | Du bist offline, daher konnte RYFT noch nicht auf Duplikate prüfen. |
| Offline duplicates caption | It checks again before uploading. Workouts that look like ones you already logged are skipped and listed on the result screen, where you can import them anyway. | Vor dem Hochladen prüft RYFT erneut. Workouts, die wie bereits erfasste aussehen, werden übersprungen und auf dem Ergebnisbildschirm aufgelistet. Dort kannst du sie trotzdem importieren. |
| Duplicates at upload | %lld workout(s) looked like ones you already logged and were skipped | %lld Workout sah aus wie ein bereits erfasstes und wurde übersprungen / %lld Workouts sahen aus wie bereits erfasste und wurden übersprungen |
| Import these too | Import these too | Diese trotzdem importieren |
| Remembered match | Matched · from your earlier choice | Zugeordnet · aus deiner früheren Wahl |
| Assisted note | Assisted sets: RYFT imports the reps and leaves out the assistance weight. | Sätze mit Entlastung: RYFT übernimmt die Wiederholungen und lässt das Entlastungsgewicht weg. |
| Body weight option caption | The number is your own weight. RYFT logs the sets without added weight and notes %@ as your body weight for the workout. | Die Zahl ist dein eigenes Gewicht. RYFT erfasst die Sätze ohne Zusatzgewicht und notiert %@ als dein Körpergewicht für das Workout. |
| Weight exercise option | %@ is the weight | %@ ist das Gewicht |
| Logged as bodyweight | The file logs this as a bodyweight exercise. | Die Datei erfasst das als Körpergewichtsübung. |
| Time/distance exercise | The weight is left out for this exercise. | Das Gewicht wird bei dieser Übung weggelassen. |
| In progress | An import is in progress. Finish it before starting another. | Ein Import läuft gerade. Schließe ihn ab, bevor du einen neuen startest. |
| Clear matches row | Clear remembered matches | Gemerkte Zuordnungen löschen |
| Clear matches detail | RYFT forgets how it matched imported exercises. | RYFT vergisst, wie es importierte Übungen zugeordnet hat. |
| Clear matches alert | Clear remembered matches? | Gemerkte Zuordnungen löschen? |
| Clear matches message | Your next import asks about every exercise again. Imported workouts and plans stay as they are. | Beim nächsten Import fragt RYFT wieder bei jeder Übung nach. Importierte Workouts und Pläne bleiben unverändert. |
| Clear / Cancel | Clear · Cancel | Löschen · Abbrechen |
| Nothing selected | Turn on at least one to continue. | Schalte mindestens eines ein, um fortzufahren. |
| Strain footnote | Imported workouts count towards strain on their days. Past strain can change once. | Importierte Workouts zählen zur Belastung ihrer Tage. Die bisherige Belastung kann sich einmal ändern. |
| Mapping count | %lld exercise(s) | %lld Übung / %lld Übungen |
| Mapping breakdown | %lld matched · %lld to check · %lld new | %lld zugeordnet · %lld zu prüfen · %lld neu |
| All matched | All %lld matched. Check them if you like. | Alle %lld zugeordnet. Prüfe sie, wenn du magst. |
| Filter | All · Needs a check (%lld) | Alle · Prüfen (%lld) |
| Sections | Needs your attention · Matched | Braucht dich · Zugeordnet |
| Bulk accept | Accept %lld likely match(es) | %lld wahrscheinliche Zuordnung übernehmen / %lld wahrscheinliche Zuordnungen übernehmen |
| Status words | Matched · Check · New · Your choice · Skipped · Question | Zugeordnet · Prüfen · Neu · Deine Wahl · Übersprungen · Frage |
| Confidence | Likely match · Possible match | Wahrscheinlich passend · Möglicherweise passend |
| Plan only / History only | Plan only · History only | Nur im Plan · Nur im Verlauf |
| Row dialog | Use “%@” · Choose another exercise… · Create a custom exercise… · Skip this exercise | „%@“ verwenden · Andere Übung wählen … · Eigene Übung erstellen … · Diese Übung überspringen |
| Skip consequence | Its sets aren't imported and it's removed from the plan. | Ihre Sätze werden nicht importiert, und sie wird aus dem Plan entfernt. |
| Picker title | Match “%@” | „%@“ zuordnen |
| Create inline | Create as custom exercise | Als eigene Übung erstellen |
| Muscle group | Muscle group | Muskelgruppe |
| New created later | New · created when you import | Neu · wird beim Import erstellt |
| Left to check | %lld left to check. | Noch %lld zu prüfen. |
| Remembered | RYFT remembers your choices for next time. They're part of Export my data, and you can clear them in Profile → Data. | RYFT merkt sich deine Zuordnungen für das nächste Mal. Sie sind Teil von „Meine Daten exportieren“, und du kannst sie unter Profil → Daten löschen. |
| New exercises offline | %lld new exercise(s) are created when you import. | %lld neue Übung wird beim Import erstellt. / %lld neue Übungen werden beim Import erstellt. |
| Library loading | Loading the exercise library… | Übungsbibliothek wird geladen … |
| Library unavailable | The exercise library isn't available offline yet. | Die Übungsbibliothek ist offline noch nicht verfügbar. |
| Library unavailable caption | RYFT needs it to match exercises. | RYFT braucht sie, um Übungen zuzuordnen. |
| No match for search | No exercise matches “%@”. | Keine Übung passt zu „%@“. |
| Bodyweight question | ‘%@’ for %@: is that added weight, or your body weight? | „%@“ bei %@: Ist das Zusatzgewicht oder dein Körpergewicht? |
| Bodyweight seen | Seen on %lld set(s). | In %lld Satz gefunden. / In %lld Sätzen gefunden. |
| Bodyweight seen, mixed | Seen on %lld sets with different values. | In %lld Sätzen mit unterschiedlichen Werten gefunden. |
| Option: added | Added weight | Zusatzgewicht |
| Option: added caption | Each set adds %@ to your body weight. | Jeder Satz fügt %@ zu deinem Körpergewicht hinzu. |
| Option: body | Body weight | Körpergewicht |
| Option: ignore | Ignore | Ignorieren |
| Option: ignore caption | Import the reps only. | Nur die Wiederholungen importieren. |
| Preview totals | %lld plan(s) · %lld workout(s) · %lld set(s) · %@ | %lld Plan / %lld Pläne · %lld Workout / %lld Workouts · %lld Satz / %lld Sätze · %@ |
| Preview subline | %lld set(s) skipped · %lld workout(s) look like ones you already logged | %lld Satz übersprungen / %lld Sätze übersprungen · %lld Workout sieht aus wie ein bereits erfasstes / %lld Workouts sehen aus wie bereits erfasste |
| Segments | Plan · History | Plan · Verlauf |
| Plan name | Plan name | Planname |
| Plan name missing | Give the plan a name. | Gib dem Plan einen Namen. |
| Not imported list | Not imported (%lld): %@ | Nicht importiert (%lld): %@ |
| Day empty | No exercises (all skipped) | Keine Übungen (alle übersprungen) |
| Plan empty | The plan has no exercises left. | Im Plan sind keine Übungen übrig. |
| Last time line | Starts at %@ · last time, %@ | Startet bei %@ · zuletzt am %@ |
| Last time note | Last time comes from your imported workouts. | „Zuletzt“ stammt aus deinen importierten Workouts. |
| Session caption | %lld exercise(s) · %lld set(s) · %@ | %lld Übung / %lld Übungen · %lld Satz / %lld Sätze · %@ |
| Skipped sets row | %lld set(s) skipped | %lld Satz übersprungen / %lld Sätze übersprungen |
| Skipped set | Skipped · no weight or reps | Übersprungen · kein Gewicht oder keine Wiederholungen |
| Skipped sets footer | Skipped sets have no weight or no reps. They are counted, not imported as zero. | Übersprungene Sätze haben kein Gewicht oder keine Wiederholungen. Sie werden gezählt, nicht als null importiert. |
| Duplicate | Looks like a session you already logged | Sieht aus wie ein Workout, das du schon erfasst hast |
| Duplicates banner | %lld workout(s) look like ones you already logged. They're skipped unless you turn them on. | %lld Workout sieht aus wie ein bereits erfasstes. Es wird übersprungen, außer du schaltest es ein. / %lld Workouts sehen aus wie bereits erfasste. Sie werden übersprungen, außer du schaltest sie ein. |
| Review | Review | Prüfen |
| Included / Skipped | Included · Skipped | Enthalten · Übersprungen |
| Duplicate on note | Will be imported next to your own session. | Wird neben deinem eigenen Workout importiert. |
| Already imported | Already imported | Bereits importiert |
| Future left out | %lld workout(s) in the future left out | %lld Workout in der Zukunft ausgelassen / %lld Workouts in der Zukunft ausgelassen |
| Outside range | %lld workout(s) are outside your chosen range | %lld Workout liegt außerhalb deines Zeitraums / %lld Workouts liegen außerhalb deines Zeitraums |
| Preview footer | Imported workouts count towards strain on their days, so past strain can change once. You won't get record notifications for them. RYFT sends only what's listed here. The file stays on your iPhone. | Importierte Workouts zählen zur Belastung ihrer Tage, die bisherige Belastung kann sich also einmal ändern. Für sie gibt es keine Rekord-Benachrichtigungen. RYFT sendet nur, was hier aufgelistet ist. Die Datei bleibt auf deinem iPhone. |
| Import button | Import %@ | %@ importieren |
| Import button parts | %lld plan(s) · %lld workout(s) (joined with “and”) | %lld Plan / %lld Pläne · %lld Workout / %lld Workouts (mit „und“ verbunden) |
| Nothing to import | Nothing to import | Nichts zu importieren |
| Nothing to import reason | All workouts are skipped or already imported. | Alle Workouts sind übersprungen oder bereits importiert. |
| Already in RYFT | This file is already in RYFT. Nothing new to import. | Diese Datei ist schon in RYFT. Es gibt nichts Neues zu importieren. |
| Uploads unavailable | Uploads aren't available yet. | Uploads sind noch nicht verfügbar. |
| Uploads unavailable caption | RYFT can keep this import on your iPhone and upload it when importing is switched on for your account. | RYFT kann diesen Import auf deinem iPhone aufbewahren und hochladen, sobald Importe für dein Konto freigeschaltet sind. |
| Keep | Keep on this iPhone | Auf diesem iPhone behalten |
| Preparing | Getting ready | Wird vorbereitet |
| Preparing line | Creating %lld custom exercise(s)… · Preparing your import… | %lld eigene Übung wird erstellt … / %lld eigene Übungen werden erstellt … · Import wird vorbereitet … |
| Importing | Importing… | Import läuft … |
| Progress | %lld of %lld workouts | %lld von %lld Workouts |
| Plan done | Plan: done | Plan: fertig |
| Can close | You can close this. The import continues while RYFT is open and picks up where it stopped. | Du kannst das schließen. Der Import läuft weiter, solange RYFT geöffnet ist, und macht dort weiter, wo er aufgehört hat. |
| Close / Done | Close · Done | Schließen · Fertig |
| Done header | Done | Fertig |
| Result both | Imported %@ and %@ | %@ und %@ importiert |
| Result plan | Imported %lld plan(s) | %lld Plan importiert / %lld Pläne importiert |
| Result workouts | Imported %lld workout(s) | %lld Workout importiert / %lld Workouts importiert |
| Result skipped | %lld set(s) skipped (no weight or reps) | %lld Satz übersprungen (kein Gewicht oder keine Wiederholungen) / %lld Sätze übersprungen (…) |
| Result nothing new | Nothing new: everything in the file was already in RYFT | Nichts Neues: Alles aus der Datei war schon in RYFT |
| Result rows | Plan · Workouts · Sets imported · Sets skipped · Already in RYFT | Plan · Workouts · Importierte Sätze · Übersprungene Sätze · Schon in RYFT |
| Left as they were | %lld workout(s) left as they were | %lld Workout unverändert gelassen / %lld Workouts unverändert gelassen |
| Open buttons | Open plan · Open history | Plan öffnen · Verlauf öffnen |
| Rescoring | Past strain on these days is being recalculated. It may take a minute to show. | Die bisherige Belastung dieser Tage wird neu berechnet. Das kann eine Minute dauern. |
| Open received file | Open the file you just received | Gerade erhaltene Datei öffnen |
| Partly | Some items weren't imported | Einige Einträge wurden nicht importiert |
| Partly sentence | … · %lld workout(s) not imported | … · %lld Workout nicht importiert / %lld Workouts nicht importiert |
| Not imported header | Not imported (%lld) | Nicht importiert (%lld) |
| Reasons | The exercise wasn't found · The date is invalid · Rejected by the server | Die Übung wurde nicht gefunden · Das Datum ist ungültig · Vom Server abgelehnt |
| Retry | Retry %lld | %lld erneut versuchen |
| Paused | The upload paused. | Der Upload ist pausiert. |
| Paused caption | Your import is kept on this iPhone. RYFT retries when the connection is back. | Dein Import bleibt auf diesem iPhone. RYFT versucht es erneut, sobald die Verbindung wieder da ist. |
| Retry in | Trying again in %lld seconds | Neuer Versuch in %lld Sekunden |
| Offline | You're offline. Your import is kept on this iPhone and continues when you're back online. | Du bist offline. Dein Import bleibt auf diesem iPhone und läuft weiter, sobald du wieder online bist. |
| Other account | This import belongs to another account. | Dieser Import gehört zu einem anderen Konto. |
| Discard import | Discard import | Import verwerfen |
| Ready | Ready | Bereit |
| Saved | Your import is saved on this iPhone. | Dein Import ist auf diesem iPhone gespeichert. |
| Saved caption | It uploads when importing is available for your account. | Er wird hochgeladen, sobald Importe für dein Konto verfügbar sind. |
| Resume row | Import uploading · %lld of %lld · Import paused · waiting for a connection · Import needs attention · %lld workout(s) not imported · Import saved on this iPhone | Import läuft · %lld von %lld · Import pausiert · wartet auf Verbindung · Import braucht dich · %lld Workout nicht importiert / %lld Workouts nicht importiert · Import auf diesem iPhone gespeichert |
| Resume row finished | Import finished: %lld workout(s) | Import abgeschlossen: %lld Workout / %lld Workouts |
| Import in progress | An import is in progress. | Ein Import läuft gerade. |
| Dismiss | Dismiss | Ausblenden |
| Sign-in note | Your file is ready. Sign in to continue. | Deine Datei ist bereit. Melde dich an, um fortzufahren. |
| File waiting | File waiting: %@. Open it after your workout. | Datei wartet: %@. Öffne sie nach deinem Workout. |
| Open now | Open now | Jetzt öffnen |
| Uploading elsewhere | An import is still uploading. Open this file when it's done. | Ein Import wird noch hochgeladen. Öffne diese Datei, wenn er fertig ist. |
| View progress | View progress | Fortschritt ansehen |
| Replace alert | Replace the import you're setting up? | Den Import, den du gerade vorbereitest, ersetzen? |
| Replace alert message | You're in the middle of another import. Opening this file starts over. | Du bist mitten in einem anderen Import. Mit dieser Datei beginnst du von vorn. |
| Replace / Keep | Replace · Keep current | Ersetzen · Aktuellen behalten |
| Flag off sheet | Importing isn't available on this account yet | Der Import ist für dein Konto noch nicht verfügbar |
| Flag off sheet body | RYFT can't import training files for your account right now. The file wasn't read or changed. | RYFT kann für dein Konto gerade keine Trainingsdateien importieren. Die Datei wurde weder gelesen noch verändert. |
| OK | OK | OK |
| Discard alert | Discard this import? | Diesen Import verwerfen? |
| Discard message | RYFT forgets what it read from the file and your choices here. The file itself is not changed. | RYFT vergisst, was es aus der Datei gelesen hat, und deine Auswahl hier. Die Datei selbst bleibt unverändert. |
| Discard / Keep going | Discard · Keep going | Verwerfen · Weitermachen |
| Cancel | Cancel | Abbrechen |
| VO: step | Step %lld of %lld | Schritt %lld von %lld |

(Plural-form notes: `%lld plan(s)` etc. use `one` / `other`. For compound strings with several counts, build the parts
with separate plural keys and join; never one string with two plural variables.)

## 12. Preview and demo scenarios, and the UI test

### 12.1 `#Preview`s (dark and light for each; AX3 for the starred)

Use `Preview/ImportMockData.swift` with **synthetic** bundles (no real names or dates). Each step view takes an
`ImportFlowModel` seeded to a state:
1. `ImportPickView`: empty; reading (2 files); each error P3 to P7. *
2. `ImportDetectedView`: both (D1) *, plan only, workouts only, with warnings collapsed and expanded, not supported, mixed.
3. `ImportChooseView`: both on, history off, existing active plan, paused plan, empty range, nothing selected, paste-a-plan-that-already-exists, plan with 9 days. *
4. `ImportMapView`: 12 rows mixed (matched, check, new, bodyweight open, skipped) *, all matched, loading, library unavailable, 60 rows with filter on.
5. `ImportPreviewView`: plan segment with last-time lines *, history segment with a duplicate and an already-imported row *, nothing to import, uploads not available.
6. `ImportResultView`: preparing, uploading (8 of 12), done, partly done with reasons, paused (retry in 30 s), offline, saved on this iPhone, other account.
7. Components in isolation: `ExerciseMatchRow` (all states), `BodyweightQuestion` (unanswered, answered), `ImportSessionRow`, `StepRule`, `ImportFileSlot`, `ImportResumeRow`.
8. `PlansView` with the menu and with the resume row; `ProfileView` Data section with the row.

### 12.2 Demo-mode data and the UI test

In demo mode (no server), `train.import` is on and the platform is the in-memory fake (`importUploadAvailable` true, plus a
launch argument `-importUploadsUnavailable` to show V5). Synthetic files are in `RyftTests/Fixtures/Import/` and also copied into the
UI-test bundle: `plans.csv` (1 plan, 2 days, 6 exercises, one fuzzy and one unknown name), `workouts.csv` (4 sessions
including a skipped set, a `+N` bodyweight set, one session on a day that duplicates a seeded RYFT session), and `garbage.txt`.
Passing the file without the system picker: a launch argument `-uiTestImportFiles <comma-separated paths>` that the flow uses in place of `.fileImporter`
(the system document picker cannot be driven reliably); `accessibilityIdentifier`s: `import.choose`, `import.continue`, `import.cancel`, `import.discard`,
`import.row.<n>`, `import.accept`, `import.bodyweight.added`, `import.session.<n>.toggle`, `import.import`, `import.result`, `import.openPlan`.

UI test path (UISmoke, `Full` for the variants):
1. Launch demo, go to Strain → Plans → New plan → Import from file (assert the menu items).
2. Choose the synthetic plans and workouts files (launch argument); assert Step 2 shows "1 plan · 2 days · 6 exercises"
   and "4 workouts"; expand warnings if the fixture has them.
3. Continue; assert "Make this my active plan" defaults to **on** (no active plan) or **off** (seed an active plan in a variant).
4. Continue; on Step 4 assert 1 "Check" and 1 "New", Continue disabled with "2 left to check"; accept the suggestion, create the custom exercise with a muscle,
   answer the bodyweight question ("Added weight"); Continue enables.
5. Preview: assert the duplicate row is flagged and off, "Last time" lines on the plan, totals; tap Import.
6. Result: assert "Imported 1 plan and 3 workouts" and the skipped-sets part; tap Open plan and assert the plan screen.
7. Variants: `garbage.txt` shows "This isn't a supported format"; cancel at Step 3 shows the discard alert; relaunch with
   `-importUploadsUnavailable` shows "Uploads aren't available yet" and "Keep on this iPhone"; an airplane-mode-like fake error shows "The upload paused" and Retry continues from where it stopped; "Open in" is tested by calling the same
   handler with a file URL (unit test of the coordinator; the system share sheet isn't UI-tested).
8. Re-import: run again with the same files; Step 5 says "This file is already in RYFT".

Also test: Dynamic Type AX3 snapshot of Steps 2, 4, 5 and 6; VoiceOver labels audit on the match row and the bodyweight question;
reduced motion on (no custom animations).

## 13. Reconciliation with `design.md` and what is still assumed

Taken from `design.md` (frozen): wall-clock `LocalDateTime` and the device zone with the DST rules (§3); `ImportWarning` as
line + kind, no file text (§2, §10); `ImportConfidence` `none`/`weak`/`strong` for detection only (D5, D8); `ExerciseMatch.Tier`
`remembered`/`exact`/`alias`/`fuzzy` and "never accepted without a tap" (§4); `BodyweightAnswer` by `load_type` and the default
rule (§5); derived ids, already-imported and duplicate checks, `duplicatesChecked = false` offline (§6); plan building,
RPE 8 without history, enrolment at week 1 only (§8); CSV-only document type with keys shipping in the flag-on PR (§9);
8 MiB cap, up to 6 files; 30-day job retention (§10).

Still assumed (the lead reconciles):
1. The flow model exposes: "left to check" count, totals (sessions, sets, volume), skipped-set counts, duplicate flags, already-imported ids, per-plan states ("already in RYFT", "can't be imported" with a reason), and per-id upload results with reasons.
2. A capability signal `importUploadAvailable` exists (flag or `GET /v1/config`), plus per-item results (`created | unchanged | updated | rejected` with a reason).
3. The "clear remembered matches" action is a method on `ImportMappingStore`, and `ImportMapping` can report whether it has entries.
4. The result screen can offer "Import these too" for duplicates found at upload (design §6 says it does).
5. A fuzzy row's confidence words ("Likely match" / "Possible match") are derived from `ExerciseMatch.confidence` with one threshold chosen in I3 (the UI never shows the number).
6. The `Session.bodyweight_kg` side effect of the "Body weight" answer is shown only as the caption in 7.4.
