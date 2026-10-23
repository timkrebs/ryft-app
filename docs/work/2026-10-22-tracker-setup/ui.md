# Tracker setup, Devices & sync, Check sync, Today's night states: UI spec (D2)

Brief: `CLAUDE_FOLLOWUP_TRACKER_SETUP.md` §1–§4 (copy at `brief.md`). Code read at `main` d9fc265. Spec only.
Everything uses `Theme`, `Typography` and shipped components. `Ryft/` is a classic group: **no new files**; each new
type names the existing file it goes into (§9). Format and vocabulary follow
`docs/work/2026-10-21-refresh-resilience/ui.md` (rows A–E, status-line states 1–9). Wording is a draft; the
localization-editor finalises it. German is du-form and uses the shipped terms (Ausgangswerte, Bereitschaft, Sync).

## 0. Principles for these screens
1. **Expected is not an error.** A signal a tracker never shares (HRV from Garmin) is shown as a neutral fact:
   `minus.circle`, `textTertiary` glyph, `textSecondary` label, the words "Not shared by Garmin Connect". Never red,
   never amber, never an X. Only a signal that *should* arrive and doesn't is amber, with a fix.
2. **Shape and words, never colour alone.** Each capability and check state has its own symbol and its own word.
3. **One accent per screen.** Teal = the one primary action (Continue / Check again) and the small check glyphs.
   Everything else `textPrimary` / `textSecondary` / `textTertiary`. Secondary buttons are `PrimaryButton(.secondary)`.
4. **Honest uncertainty.** HealthKit cannot tell RYFT whether a read type is denied. "No data" and "RYFT isn't allowed
   to read it" look identical to RYFT, so the copy says both and names where to look.
5. **Numbers first.** "6 of 6 expected signals arriving" before any sentence. Times are real clock times, never
   "recently". A guide shows the date it was checked.
6. **Every state has a reason and at most one action.**
7. **Brand rule.** Vendor names appear only as data sources, with neutral SF Symbols (`applewatch`, `circle.circle`
   for rings, `iphone`, `ellipsis.circle`). No vendor logos, no comparisons, no "better than". Fitbit and Samsung are
   named only in the honest-limit sentence.

---

## 1. State inventory

| # | Screen / component | State | Trigger |
| --- | --- | --- | --- |
| P1 | Pick ("What do you wear?") | empty (none selected) | first visit; Continue disabled, Skip enabled |
| P2 | Pick | one or more selected | tap tiles |
| P3 | Pick | "Just my iPhone" selected | tap it; clears all others |
| P4 | Pick | saving | Continue; button "Saving…" disabled, no spinner |
| P5 | Pick | save failed | local save cannot fail; the account PATCH fails silently and retries (never blocks) |
| C1 | Setup card | full (normal tracker) | tracker with a capability matrix |
| C2 | Setup card | honest limit (Fitbit, Samsung) | `trackers.json` flag `readsOnIPhone: false` |
| C3 | Setup card | Just my iPhone | selection |
| C4 | Setup card | Other | selection |
| C5 | Setup card | Apple Watch | "nothing to set up in another app" |
| C6 | Setup card | guide stale | `checked` older than 180 days |
| C7 | Setup card | bundled fallback | remote `trackers.json` invalid or unreachable: identical look, no message (the bundled copy is valid content) |
| K1 | Check sync | running | opened / Check again |
| K2 | Check sync | row OK | sample from the tracker's sources within 48 h |
| K3 | Check sync | row expected-missing | matrix says the tracker doesn't share it |
| K4 | Check sync | row unexpected-missing | matrix says it should arrive; nothing found; the tracker is otherwise present |
| K5 | Check sync | tracker silent | no sample of any type from the tracker's sources in 48 h |
| K6 | Check sync | all as expected | summary line |
| K7 | Check sync | RYFT permission hint | any K4/K5 present; always the last card |
| K8 | Check sync | offline | check is local (HealthKit); runs offline, no state |
| K9 | Check sync | Health access not asked yet | RYFT never requested Health access |
| D1 | Devices & sync | no trackers chosen | skipped onboarding |
| D2 | Devices & sync | trackers chosen | rows + Check sync |
| D3 | Devices & sync | source seen but unmapped | a HealthKit source not in `trackers.json` |
| T1 | Today | night hasn't reached Apple Health | morning, source quiet since the last wake window |
| T2 | Today | Scoring | uploaded, unscored, `pending` |
| T3 | Today | Taking longer than usual | `pending` > 3 × `expected_within_sec` |
| T4 | Today | no tracker chosen | unchanged: shipped generic hint (§7.4) |
| R1 | Recovery / Readiness detail | recovery without HRV | `recovery_inputs` lacks `hrv` |
| R2 | Baseline gauge | blocked | a required signal has no source |

---

## 2. Onboarding step: "What do you wear?"

**Purpose.** One question, so the app can show the right setup steps. Skippable; changeable in Profile.
**Position.** `invite`, `consent`, `aboutYou`, **`wear`**, then Apple Health. Same `OnboardingScreen` frame as About you
(symbol `applewatch.and.arrow.forward` 30 pt Teal, `title`, `body` text, then content). The step belongs to the first run
only; Profile → Devices & sync reopens the same picker as a sheet ("Done" instead of Continue/Skip).

### 2.1 Hierarchy
1. Title "What do you wear?" 2. One sentence. 3. Tiles. 4. Pinned Continue / Skip bar. Eye order: title, then tiles.

### 2.2 Layout
- Scroll view; content width max 480 (shipped). Horizontal padding `screenPadding + 4`.
- **Grid:** `LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10)`.
  - Default sizes (up to XXXL): two columns on a 6.1" iPhone; "Other" and "Just my iPhone" span the full width
    and sit last (a full-width row each).
  - From AX1 up to **AX5**: one column, every tile a full-width row (the adaptive minimum cannot fit twice).
    Drive it with `dynamicTypeSize.isAccessibilitySize`, not by trusting the adaptive column (deterministic).
- **Tile** (`SelectableTile`): `HStack(spacing: 10)` of symbol (20 pt, `textSecondary`; Teal when selected) + name
  (`callout`, `textPrimary`, wraps freely, no `lineLimit`) + trailing selection mark. `minHeight: 56`, vertical padding
  12, horizontal 14, radius `Theme.Metrics.tileRadius` (16), continuous.
  - Unselected: fill `Theme.surface`, 1 pt `Theme.separator` border, trailing `circle` (`textTertiary`).
  - Selected: fill `Theme.surfaceRaised`, 1.5 pt `Theme.accent` border, trailing `checkmark.circle.fill` (`Theme.accent`),
    symbol Teal. Selection is carried by the border, the check *shape* and the VoiceOver trait: not colour alone.
  - Pressed: `PressableButtonStyle`.
- Symbols: Apple Watch `applewatch`; Garmin, Polar, Suunto, COROS, Amazfit (Zepp), Samsung Galaxy Watch, Fitbit,
  Withings `applewatch`; Oura, Ultrahuman `circle.circle` (ring); Other `ellipsis.circle`; Just my iPhone `iphone`.
  Names carry the identity, the glyph only the form factor. Drive the glyph from `trackers.json` (`form`: watch | ring | …).
- Tile text for long names ("Samsung Galaxy Watch", "Amazfit (Zepp)") wraps to two lines at default sizes; never truncates.
- Footnote under the grid, `caption`, `textTertiary`: "RYFT only uses this to show you setup steps and to check
  that your data arrives. You can change it any time in Profile → Devices & sync."

### 2.3 Selection rules
- Multi-select; a watch and a ring together is allowed. Any number of non-iPhone trackers.
- **"Just my iPhone" is exclusive:** selecting it deselects every other tile; selecting any other tile deselects it.
  Animation `Theme.Motion.quick` (border/fill cross-fade, 250 ms); reduced motion: instant.
- "Other" combines freely with named trackers.
- Order of cards later follows selection order in the tile list (§3.4), not tap order (stable).

### 2.4 Buttons (pinned bar)
`safeAreaInset(edge: .bottom)` bar: `Theme.background` with a 1 pt `separator` hairline on top, padding 16/20.
Pinned so Continue stays reachable at AX5 where the tile list is long.
- **Continue** (`PrimaryButton`, `.primary`, Teal). Disabled until at least one tile is selected. Saves the selection
  locally (per account), queues the account `PATCH /v1/me` (silently, retried; never blocks), goes to Apple Health.
- **Skip** (`LaterButton`, `textSecondary`). Saves nothing, marks the step done for this account (no re-prompt on the next
  start), goes to Apple Health. Always enabled.
- At AX sizes the bar stacks (Continue above Skip), each at least 44 pt, full width.
- After Apple Health access, if the selection contains at least one tracker other than "Just my iPhone" / Apple Watch
  alone, a second screen follows (§3.5). Skipped, nothing follows.

### 2.5 VoiceOver
- Grid is a container: label "What do you wear?", hint "Choose all that apply". Each tile is a button with
  `.isSelected` when chosen; label = name ("Garmin"), no separate glyph element. Selected state is spoken by the trait
  ("selected"), not by the label.
- Form-factor is not spoken. "Just my iPhone": hint "Clears your other choices"; when it replaces other selections post
  one `.announcement`: "Other choices cleared" (de: "Andere Auswahl entfernt").
- Order: title, sentence, tiles in visual order, footnote, Continue, Skip. Continue disabled is spoken "dimmed".
- Focus lands on the title on appearance (shipped `OnboardingScreen` does).

### 2.6 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| title | What do you wear? | Was trägst du? |
| text | Pick your watch, band or ring. RYFT then shows how to get its data into Apple Health. | Wähle deine Uhr, dein Armband oder deinen Ring. RYFT zeigt dir dann, wie die Daten in Apple Health landen. |
| tiles | Apple Watch · Garmin · Oura · Polar · Suunto · COROS · Withings · Amazfit (Zepp) · Ultrahuman · Fitbit · Samsung Galaxy Watch · Other · Just my iPhone | Apple Watch · Garmin · Oura · Polar · Suunto · COROS · Withings · Amazfit (Zepp) · Ultrahuman · Fitbit · Samsung Galaxy Watch · Andere · Nur mein iPhone |
| footnote | RYFT only uses this to show you setup steps and to check that your data arrives. You can change it any time in Profile → Devices & sync. | RYFT nutzt das nur, um dir Einrichtungsschritte zu zeigen und zu prüfen, ob deine Daten ankommen. Du kannst es jederzeit unter Profil → Geräte & Sync ändern. |
| a11y container hint | Choose all that apply | Wähle alles Zutreffende |
| a11y iPhone hint | Clears your other choices | Entfernt deine anderen Auswahlen |
| announce | Other choices cleared | Andere Auswahl entfernt |
| Continue / Skip | Continue / Skip (existing) | Weiter / Überspringen (existing) |

---

## 3. The setup card (`TrackerSetupCard`)

### 3.1 Several trackers: decision
**One card per tracker, stacked, as a collapsible list: the first expanded, the rest collapsed to a header row.**
Not a pager. Reasons: a pager hides content from VoiceOver rotor and from scrolling users, breaks at AX5 (page
height > screen), and makes "which one am I on" a state to track. A flat list of full cards is long (a watch plus a
ring = two full cards, 2+ screens). A disclosure list lets the user see all trackers at once and open one.
- Header row (always visible, whole row is the toggle, min 44 pt, `Button` with `.isButton` + expanded/collapsed value):
  symbol, name (`headline`), one-line verdict in `callout`/`textSecondary`, e.g. "Heart rate, sleep, workouts · no HRV",
  chevron (`chevron.down` rotating 180° in `Theme.Motion.quick`; reduced motion: swaps, no rotation).
- Single expansion at a time in onboarding (opening one closes the other: keeps the screen short). In Profile several may be open.
- With exactly one tracker: card shown expanded, no disclosure header.

### 3.2 Card anatomy (C1, full)
`Card` (`Theme.surface`, radius 18, padding 18), inner `VStack(alignment: .leading, spacing: 18)`. Sections are separated by a
hairline `Theme.separator`, each opens with a `ryftLabelStyle()` label (capped at AX3, as `ProfileSection` does).

**Header.** `applewatch` 22 pt `textSecondary`, name `headline`, trailing nothing. Under it the *RYFT features line* (3.3).

**(a) What reaches RYFT**
- Label "What reaches RYFT".
- Eight `CapabilityRow`s in a fixed order: Heart rate · HRV · Resting heart rate · Sleep (stages) · Breathing rate ·
  SpO₂ · Workouts · Steps. Row height min 44, hairline between rows.
- Row = state glyph (20 pt, fixed width 24) · signal name (`callout`, `textPrimary`) · state word right-aligned (`callout`,
  `textSecondary`) · optional detail line below the name (`caption`, `textTertiary`, e.g. "Newer models only").
- States (data: `yes` | `partial` | `no`):

| State | Glyph | Glyph colour | Word (en) | Word (de) |
| --- | --- | --- | --- | --- |
| yes | `checkmark.circle.fill` | `Theme.accent` | Arrives | Kommt an |
| partial | `circle.lefthalf.filled` | `textSecondary` | Partly | Teilweise |
| no | `minus.circle` | `textTertiary` | Not shared | Wird nicht geteilt |

  A "no" row is quiet by design: no tint, no bold, no "missing". Its word is "Not shared" (a fact about the tracker),
  and for HRV the detail line says why, e.g. "Garmin keeps HRV in its own app." (de "Garmin behält HRV in der eigenen App.")
  as long as the guide data says so; it is the `capability.note` string from `trackers.json`, verified like the steps.
- Dim only the glyph, not the name: the name stays `textPrimary` so the row remains legible (contrast).
- At AX sizes: glyph + name on line 1, state word under the name (left-aligned), detail under that. No truncation.

**RYFT features line** (under the header, `callout`, `textPrimary` for the feature names, `textSecondary` for the rest).
Format: `Strain ✓ · Sleep ✓ · Recovery from resting heart rate and sleep, no HRV`.
- One line of text, wraps. "✓" is the literal glyph `✓` inside text, not an image. Never an ✗ in this line: what's missing is
  said in words after a comma. Generated from the matrix (architect: pure mapping function, tested).
- Templates: all signals → "Strain ✓ · Sleep ✓ · Recovery ✓ · Readiness ✓". No HRV → "Strain ✓ · Sleep ✓ · Recovery from
  resting heart rate and sleep, no HRV · Readiness from the same". No heart rate → "Sleep ✓ · Steps ✓ · Strain and
  Recovery stay empty without heart rate". No sleep → "Strain ✓ · Recovery and Readiness need sleep from your tracker".
- This line is the card's answer to "so what?": it sits above the matrix because the matrix is evidence for it.

**(b) Set it up**
- Label "Set it up".
- Two sub-groups, each with a `caption` `textSecondary` heading, then numbered steps (`NumberedStep`, the shipped `SetupStep`
  promoted from private; `callout`, `textSecondary`, number in a 18 pt Teal-tinted circle; numbering restarts per group,
  or runs on 1–n across both: **one run, 1–n**, so "step 3" is unambiguous):
  1. **In the {vendor app}** (e.g. "In Garmin Connect"): steps from `trackers.json`.
  2. **In iPhone Settings**: "Open Settings → Health → Data Access & Devices → {vendor app}. Tap Turn On All." (the iOS part is
     generic; the vendor app name is substituted). Verified once against current iOS, dated like the rest.
- Garmin example (illustrative; the real text is **verified against the vendor help page** and stored with URL and date):
  1. Open Garmin Connect, tap More, then Settings. 2. Open Connected Apps, then Apple Health. 3. Turn on every type. 4. In
  Settings → Health → Data Access & Devices → Garmin Connect, tap Turn On All.
- "Vendor guide" row: `LinkRow` look (shipped, private in ProfileView; promote), `arrow.up.right` trailing, min 44 pt, opens
  `SafariView` (shipped). Under it `caption`/`textTertiary`: "Checked 14 Oct 2026". If the date is older than 180 days:
  "Checked 3 Mar 2026. Steps may have changed." (honest staleness; C6.) Date format `.dateTime.day().month(.abbreviated).year()`.
- If the guide has no URL: the row and caption are absent, never an empty link.

**(c) Keep it flowing**
- Label "Keep it flowing". Bulleted habits, `callout`/`textSecondary`, bullet = `circle.fill` 4 pt `textTertiary`, wrap.
- For apps that write to Apple Health only while they run (Garmin Connect, Polar, COROS, Suunto): "Open {app} each morning
  before you open RYFT." · "Turn on Background App Refresh for {app} (Settings → General → Background App Refresh)." · "Stay
  signed in to {app}." Per-tracker lists come from `trackers.json`.
- Apple Watch: "Keep your Apple Watch near your iPhone overnight." only if verified; else the card is short (C5).

**(d) Buttons**
- **Open {app}** (`PrimaryButton(.secondary)`, full width, min 44). Variants (§3.6). One accent per screen: it is *not* Teal.
- **Show me again later** (`LaterButton`-style, `textSecondary`, min 44). In onboarding it closes the card and the step
  continues; the card then appears in Profile → Devices & sync with the row state "Set up later" (`textSecondary`). It is not
  a push notification and not a Today card.
- At AX sizes buttons stack full width.

### 3.3 Header verdict line (collapsed row)
Same sentence source as the RYFT features line, shortened: "Heart rate, sleep, workouts · no HRV" (de "Herzfrequenz, Schlaf, Workouts · kein HRV").

### 3.4 Order
Cards follow the order of the picker tiles (Apple Watch first, "Other" last). The tracker with the most expected-missing/at-risk
signals is *not* promoted; order is stable.

### 3.5 Onboarding: the second screen (after Apple Health access)
Shown only when the selection has a tracker needing setup (anything except Apple Watch alone, or Just my iPhone alone).
`OnboardingScreen`, title "Set up your tracker" / "Richte dein Gerät ein", text "A few minutes now saves a silent week of missing data."
(de "Ein paar Minuten jetzt ersparen dir eine Woche ohne Daten."). Content: the collapsible cards (§3.1), then a `Check sync`
button (`PrimaryButton(.secondary)`), then pinned **Done** (Teal) and "Show me again later". "Done" is always enabled: nothing is
mandatory. The **Check sync** result opens below the cards inline (not a new screen), same component as §5.

### 3.6 Open / Get button variants
HealthKit's list of sources is the only reliable "installed" signal (a source whose bundle ID is in `trackers.json` has written
to Apple Health). iOS offers no installed-apps list and RYFT must not guess private URL schemes.
| Condition | Label | Action |
| --- | --- | --- |
| source seen in Apple Health **and** `trackers.json` has a verified `open_url` | Open {app} | open that URL |
| source seen, no verified URL | Open {app} in the App Store | App Store page (its own "Open" button) |
| source not seen | Get {app} | App Store page |
App Store URL = `https://apps.apple.com/app/id…` from `trackers.json`. If the URL is missing the button is absent, not disabled.
Caption under the button when it is a store link, `caption`/`textTertiary`: "Opens the App Store."

### 3.7 Honest-limit variants

**C2: Fitbit, Samsung Galaxy Watch.** No setup steps (nothing to set up), no Open button, no matrix.
- Header: `applewatch`, name.
- Message block (`InlineMessage`-style container, `exclamationmark.circle`... **no**: use `info.circle`, `textSecondary`; this is a fact, not a fault): "RYFT can't read Fitbit data on iPhone today."
- Second paragraph, `callout`/`textSecondary`: "Fitbit doesn't write to Apple Health, so nothing it records can reach RYFT. Your iPhone's own step count still does."
- "What stays empty" list: Heart rate · HRV · Resting heart rate · Sleep · Breathing rate · SpO₂ via the same `CapabilityRow` in "no" state with the word "Not available" (not "Not shared": the reason differs). Steps "From your iPhone" partial glyph.
- Features line: "Steps ✓ · Sleep, Strain and Recovery stay empty without data from your tracker".
- Buttons: **Tell us you'd like this** (`.secondary`; opens Report a problem with category `idea`, message prefilled "I'd like RYFT to read {vendor} data.") and "Show me again later". No third-party bridge is named unless verified and privacy-reviewed.

**C3: Just my iPhone.** Header `iphone`, "Just my iPhone".
- Features line: "Steps ✓ · Sleep, Strain, Recovery and Readiness stay empty: they need heart rate and sleep from a watch or ring."
- Matrix: Steps "From your iPhone" ✓; Workouts "Only ones you log in RYFT" partial; the other six "Not available" (no-glyph quiet state).
- A sentence (`callout`): "You can add a tracker any time. RYFT will show how to connect it."
- Button: **Add a tracker** (`.secondary`: opens the picker, `Done`). No "Show me again later" (nothing to defer); no Check sync (it checks steps only; kept in Devices & sync as a one-row check "Steps — last 07:42" so the screen is consistent).

**C4: Other.** Header `ellipsis.circle`, "Other tracker".
- No matrix (unknown). Sentence: "RYFT reads whatever your tracker saves to Apple Health. What arrives depends on the tracker, so the check below shows exactly what it is."
- Generic steps: 1. In your tracker's app, find Apple Health (sometimes "Health integration") and turn on every type. 2. Settings → Health → Data Access & Devices → your tracker's app → Turn On All.
- Habits: "Open the app each morning before RYFT, if it only syncs while it runs."
- Buttons: **Check sync** (secondary, any source) and "Show me again later". The check lists all types found from non-RYFT, non-iPhone sources, with no expected/unexpected split (all rows are K2 or "nothing").

**C5: Apple Watch.** Matrix usually all ✓ (sleep stages "Watch Series with watchOS 9 or later" as detail, verified). Steps: "Make sure your Apple Watch is paired and Sleep is set up in Health." Set up (b) has just the iOS Settings group. No Open button (it's a system app); Check sync is the one button. If matrix is all ✓ the features line is "Strain ✓ · Sleep ✓ · Recovery ✓ · Readiness ✓".

### 3.8 Copy (en | de) draft
| Key | en | de |
| --- | --- | --- |
| section a | What reaches RYFT | Was bei RYFT ankommt |
| section b | Set it up | Einrichten |
| section c | Keep it flowing | Damit es weiterläuft |
| group 1 | In {app} | In {app} |
| group 2 | In iPhone Settings | In den iPhone-Einstellungen |
| ios step | Open Settings → Health → Data Access & Devices → {app}, then tap Turn On All. | Öffne Einstellungen → Health → Datenzugriff & Geräte → {app} und tippe auf „Alle aktivieren“. |
| vendor guide | Vendor guide | Anleitung des Herstellers |
| checked | Checked %@ | Geprüft am %@ |
| checked old | Checked %@. Steps may have changed. | Geprüft am %@. Die Schritte können sich geändert haben. |
| state yes / partial / no | Arrives / Partly / Not shared | Kommt an / Teilweise / Wird nicht geteilt |
| state n/a | Not available | Nicht verfügbar |
| signals | Heart rate · HRV · Resting heart rate · Sleep (stages) · Breathing rate · SpO₂ · Workouts · Steps | Herzfrequenz · HRV · Ruheherzfrequenz · Schlaf (Phasen) · Atemfrequenz · SpO₂ · Workouts · Schritte |
| features, no HRV | Strain ✓ · Sleep ✓ · Recovery from resting heart rate and sleep, no HRV | Strain ✓ · Schlaf ✓ · Recovery aus Ruheherzfrequenz und Schlaf, ohne HRV |
| features, all | Strain ✓ · Sleep ✓ · Recovery ✓ · Readiness ✓ | Strain ✓ · Schlaf ✓ · Recovery ✓ · Bereitschaft ✓ |
| habit morning | Open {app} each morning before you open RYFT. | Öffne {app} jeden Morgen, bevor du RYFT öffnest. |
| habit bg | Turn on Background App Refresh for {app} (Settings → General → Background App Refresh). | Aktiviere die Hintergrundaktualisierung für {app} (Einstellungen → Allgemein → Hintergrundaktualisierung). |
| habit signed in | Stay signed in to {app}. | Bleib in {app} angemeldet. |
| open / get / store | Open {app} · Get {app} · Open {app} in the App Store | {app} öffnen · {app} laden · {app} im App Store öffnen |
| store caption | Opens the App Store. | Öffnet den App Store. |
| later | Show me again later | Später noch einmal zeigen |
| later row value | Set up later | Später einrichten |
| limit | RYFT can't read {vendor} data on iPhone today. | RYFT kann {vendor}-Daten auf dem iPhone derzeit nicht lesen. |
| limit body | {vendor} doesn't write to Apple Health, so nothing it records can reach RYFT. Your iPhone's own step count still does. | {vendor} schreibt nicht in Apple Health, deshalb kann nichts davon RYFT erreichen. Die Schritte deines iPhones kommen weiterhin an. |
| limit features | Steps ✓ · Sleep, Strain and Recovery stay empty without data from your tracker | Schritte ✓ · Schlaf, Strain und Recovery bleiben ohne Daten deines Trackers leer |
| limit action | Tell us you'd like this | Sag uns, dass du das möchtest |
| iPhone features | Steps ✓ · Sleep, Strain, Recovery and Readiness stay empty: they need heart rate and sleep from a watch or ring. | Schritte ✓ · Schlaf, Strain, Recovery und Bereitschaft bleiben leer: Sie brauchen Herzfrequenz und Schlaf von einer Uhr oder einem Ring. |
| iPhone add | Add a tracker | Gerät hinzufügen |
| iPhone workouts | Only ones you log in RYFT | Nur in RYFT erfasste |
| other body | RYFT reads whatever your tracker saves to Apple Health. What arrives depends on the tracker, so the check shows exactly what it is. | RYFT liest, was dein Gerät in Apple Health speichert. Was ankommt, hängt vom Gerät ab; die Prüfung zeigt dir genau, was es ist. |
| setup screen title / text | Set up your tracker / A few minutes now saves a silent week of missing data. | Richte dein Gerät ein / Ein paar Minuten jetzt ersparen dir eine Woche ohne Daten. |

### 3.9 Accessibility, Dynamic Type, appearance
- Each `CapabilityRow` is one element: label "Heart rate variability", value "Not shared. Garmin keeps HRV in its own app." (the state
  *word* comes first in the value). Glyphs hidden. Use full signal names for speech: "Heart rate variability", "Resting heart rate",
  "Blood oxygen", "Breathing rate".
- The features line is a single element above the matrix; "✓" is spoken as "yes": provide an `accessibilityLabel` string from the
  same template with "yes" ("Strain, yes. Sleep, yes. Recovery from resting heart rate and sleep, no HRV").
- Collapsed header: button, value "collapsed/expanded", label "Garmin, heart rate, sleep, workouts, no HRV".
- Steps read as a list: "Step 1 of 4, ...". Vendor guide: "Vendor guide, link. Checked 14 October 2026".
- AX1–AX5: one column everywhere, rows stack, buttons full width, section labels capped at AX3 (shipped), body text never capped. The
  card scrolls inside the screen's `ScrollView`; nothing nested.
- Contrast: `textTertiary` glyph and detail lines on `surface` must be checked in both schemes (flag: dimmed glyph is non-text,
  needs 3:1; detail line is text, **use `textSecondary` for detail lines that carry a reason**, `textTertiary` only for captions such as the "Checked" date; the date is informational, flag in review).
- Dark and light: all via `Theme` assets; no hard-coded colours.

---

## 4. Profile → Devices & sync

### 4.1 Proposal: **merge Data sources into a new "Devices & sync" screen; link (not merge) Sync details; replace the hard-coded Garmin line**
(`Data sources` is not a screen in the code at d9fc265: the closest are the "Data" section's Garmin sentence and Sync details → Streams. See open question 1.)

Profile → **Data** section keeps its job: Apple Health access, the workout-export toggle, Last sync, Sync now, Full re-sync,
Export, Demo data. It changes in two ways:
1. The hard-coded caption "Garmin Connect must write to Apple Health …" (`ProfileView.swift`, Data section) is **removed**: it is
   wrong for every other tracker and is replaced by the per-tracker cards.
2. A new first row (a `NavigationLink`, `SettingRowLabel`): symbol `applewatch`, title **Devices & sync**, value = summary ("Garmin · 1 ring").
   If no trackers: value "Not set". If a check last found something wrong: value "Check needed" in `Theme.warning` text is **not**
   used (amber text fails contrast); use `textSecondary` text plus a `exclamationmark.circle` glyph in `warning`.

Why this split:
- **Replace/merge Data sources:** *which tracker's data reaches RYFT* is one question, and it belongs next to the tracker. A separate list
  of HealthKit source names would show "Connect" without context; inside Devices & sync, sources are shown under the tracker they match.
- **Link Sync details:** it is an engineering view (resources, streams, last 20 requests, request IDs) that support asks for and that
  `Report a problem` attaches. Merging it would put request IDs on the screen a user opens to fix their watch. It stays where it is and
  Devices & sync links to it in its footer ("Sync details", for support).
- **Not in Data:** the Data section is already 12 controls tall; tracker content is long and grows with `trackers.json`.

### 4.2 Screen layout (pushed, `ScrollView`, `ProfileSection` cards, title "Devices & sync" inline)
Order of sections, top to bottom:
1. **Your trackers** (`ProfileSection`). One row per selected tracker (`SettingRowLabel`-like: symbol, name, status line under it
   `caption`), chevron: pushes the tracker's full card (§3) with a "Done" ... no: pushes, standard back. Row status text (priority):
   "Heart rate last 07:42" (last check OK) · "Set up later" · "Not checked yet" · "Check needed" (last result had K4/K5). Trailing
   header action **Edit** (`textSecondary`, 44 pt) opens the picker sheet (§2, "Done" only; changes save on Done; **Cancel** reverts).
   With no trackers (D1): one sentence "Tell RYFT what you wear to see how to set up your data." and a **Choose** secondary button.
2. **Check sync** (`ProfileSection`): `PrimaryButton(.primary)`, the one Teal action on the screen, "Check sync". Pushes the Check
   sync screen (§5). Under it `caption`/`textTertiary`: "Last checked today 08:12" or "Never checked". With no trackers the check
   still runs, source-agnostic (like "Other").
3. **Seen in Apple Health** (`ProfileSection`; replaces "Data sources"). Rows = HealthKit sources with friendly names ("Garmin Connect",
   "Apple Watch", "Health" for manual): name, kinds ("Heart rate, sleep, steps"), newest sample time. Unmapped source (D3): its raw
   name, `textSecondary`, and the caption "Not a tracker RYFT knows. It still counts." (honest: it is read.) Empty: "No data from other apps yet."
4. **Apple Health access** row: status + "Open Health permissions" (`secondary`), the existing `HealthLinks.open`. This is shown here and in Data;
   Data keeps the status row and drops the buttons? **Keep both**: duplication is cheap; the check's hint (K7) needs one tap to it.
5. Footer link **Sync details** (`LinkRow` look, accent text as the shipped Data section row) with caption "For support: requests and streams."

Spacing: `Theme.Metrics.sectionSpacing` between sections; `screenPadding` horizontal (shipped `ProfileSection`).

### 4.3 States
D1 none chosen · D2 chosen · D3 unmapped source. Loading `trackers.json` is invisible: the bundled copy is always there.
Offline: nothing changes (all local); the account PATCH is queued silently.

### 4.4 Accessibility
Rows: label "Garmin", value "Heart rate last 07:42", hint "Opens setup and details". Edit: "Edit trackers". At AX the status line sits
under the name, chevron stays trailing. Section labels capped at AX3 (shipped).

### 4.5 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| row / title | Devices & sync | Geräte & Sync |
| value none | Not set | Nicht festgelegt |
| section | Your trackers | Deine Geräte |
| edit | Edit | Bearbeiten |
| empty | Tell RYFT what you wear to see how to set up your data. | Sag RYFT, was du trägst, dann zeigt es dir, wie du deine Daten einrichtest. |
| choose | Choose | Auswählen |
| row statuses | Heart rate last %@ · Set up later · Not checked yet · Check needed | Herzfrequenz zuletzt %@ · Später einrichten · Noch nicht geprüft · Prüfung nötig |
| check | Check sync | Sync prüfen |
| last checked | Last checked %@ · Never checked | Zuletzt geprüft %@ · Noch nie geprüft |
| seen section | Seen in Apple Health | In Apple Health gefunden |
| unmapped | Not a tracker RYFT knows. It still counts. | Kein Gerät, das RYFT kennt. Die Daten zählen trotzdem. |
| none seen | No data from other apps yet. | Noch keine Daten aus anderen Apps. |
| sync details | Sync details · For support: requests and streams. | Sync-Details · Für den Support: Anfragen und Datenströme. |

---

## 5. Check sync

**Purpose.** Answer "is my data actually arriving?" with evidence per signal, and fix what isn't.
**Entry.** Profile → Devices & sync → Check sync (pushed screen, title "Check sync"); onboarding §3.5 (inline). Runs on appearance and on
"Check again". It reads HealthKit locally (last 48 h); it uploads nothing and works offline.

### 5.1 Layout
`ScrollView` / `ScreenScaffold` style, top to bottom:
1. Header caption `callout`/`textSecondary`: "Looks at the last 48 hours in Apple Health. Nothing is uploaded."
2. One `Card` per tracker (selection order). Card = tracker header (symbol, name `headline`) + **summary line** (below) + the rows
   (`CheckRow`s, §5.2) + per-card actions (K4/K5 only).
3. RYFT-permission card (K7, §5.5) when needed.
4. Pinned bar: **Check again** (`PrimaryButton(.primary)`, Teal). In running state: label "Checking…", disabled, no spinner.
   Pinned at AX so it is reachable (safeAreaInset, like §2.4).

**Summary line** (numbers first, `callout` `textPrimary`, monospaced digits):
- K6: "6 of 6 expected signals are arriving" / "6 von 6 erwarteten Signalen kommen an".
- K4: "4 of 6 expected signals are arriving. 2 need a fix." / "4 von 6 … 2 brauchen eine Korrektur."
- Signals the tracker never shares do not count in "expected".

### 5.2 `CheckRow`
`HStack(alignment: .firstTextBaseline, spacing: 10)`: glyph (20 pt, 24 wide) · name (`callout`, `textPrimary`) · result (`callout`,
`monospacedDigit`, `textSecondary`, trailing). AX: result under the name. Min height 44, hairline between rows.

| State | Glyph | Name | Result (en) | Result (de) |
| --- | --- | --- | --- | --- |
| waiting (queued) | `circle` outline, `textTertiary` | Heart rate | waiting… | wartet … |
| checking | `circle.dotted`, `textSecondary`, pulse | Heart rate | checking… | prüft … |
| OK, today | `checkmark.circle.fill`, Teal | Heart rate | last 07:42 | zuletzt 07:42 |
| OK, sleep | same | Sleep | last night | letzte Nacht |
| OK, older | same | Steps | yesterday 22:10 | gestern 22:10 |
| expected missing | `minus.circle`, `textTertiary` | HRV | Not shared by Garmin Connect | Wird von Garmin Connect nicht geteilt |
| unexpected missing | `exclamationmark.circle`, `Theme.warning` | Resting heart rate | should arrive, nothing yet | sollte ankommen, bisher nichts |

- Relative times use the shipped `Fmt.time` and `SyncLine.dataTime` rules (same day clock, "Yesterday 22:10", weekday), never "x min ago".
- Sleep: "last night" if the newest night ended today or last evening; otherwise a date.
- "(expected)" in the brief's draft is dropped from the label: the sentence "Not shared by Garmin Connect" already says it is expected; the detail line under the row adds "That's normal." (de "Das ist normal.") in `caption`/`textSecondary` **once per tracker** under the first such row, not on each (repeating it is noise).
- Unexpected-missing rows have a **fix disclosure** directly under them (`caption`+`callout`, `textSecondary`, one container `surfaceRaised`, radius 12, padding 12):
  - Line: "Open the Apple Health permission in Garmin Connect and make sure Resting heart rate is on." (the type is named: from the row)
  - Then two numbered steps (shipped `NumberedStep`): "1. In Garmin Connect: More → Settings → Connected Apps → Apple Health: turn on every type." "2. In Settings → Health → Data Access & Devices → Garmin Connect: Turn On All."  (same steps as the card, filtered to the permission steps; data from `trackers.json`.)
  - Buttons (stack at AX): **Show setup steps** (`.secondary`, opens the tracker's card; pushes in Profile, scrolls to it in onboarding) and the shared **Open {app}** (§3.6).
  - If several rows fail for the same tracker, **one** disclosure under the last of them (not repeated): "Several signals should arrive and don't. The cause is usually one permission. …".
- Rows are not tappable except the disclosure's buttons. No chevrons.

### 5.3 Whole-tracker states
**K5: silent tracker** (no sample of any type in 48 h from that tracker's sources). The rows collapse behind a "Show details" toggle
(`textSecondary`, collapsed) and the card body becomes:
- Glyph `tray`, `textSecondary`, 28 pt, centred? **Left aligned** like every card here.
- Text (`callout`, `textPrimary`): "No data from Garmin Connect yet. Open Garmin Connect and let it sync, then tap Check again."
- Buttons: **Open Garmin Connect** (`.secondary`); the pinned **Check again** (Teal) is the next step.
- Under it, `caption`/`textSecondary`: "If it still shows nothing after it has synced, the Apple Health permission is the usual cause." with the **Show setup steps** button.
This is also what a user sees right after granting Health access on a new install (honest: nothing has arrived *yet*).

**Tracker "Just my iPhone":** one row "Steps — last 07:42"; no expected-missing rows beyond "Heart rate, sleep and others — not available from an iPhone" as a single quiet row `minus.circle` with that sentence.
**Other:** rows only for types found; no expected-missing, no unexpected (nothing is promised). If nothing from any non-iPhone source: K5 wording with "your tracker's app" instead of a name.
**Fitbit / Samsung:** the card shows "RYFT can't read {vendor} data on iPhone today." (C2) instead of rows. No check is run for it; it contributes no counts.

### 5.4 Motion (≤ 250 ms; reduced-motion variant)
- Rows start as *waiting…* with the outline glyph. The query runs per row; each row's result replaces its state as soon as it arrives:
  glyph and text cross-fade in `Theme.Motion.quick` (250 ms). While *checking…* the glyph pulses opacity 1 → 0.4 → 1 (the shipped
  status-line pulse, 0.8 s loop). Results already known are never held back artificially, but a result is shown at least 150 ms after
  its predecessor's so the list *reads* top-down: this is debounce, not animation.
- Summary line changes with a 250 ms cross-fade after the last row resolves. "Check again" returns rows to *waiting…* in place (no
  layout jump: rows keep their height).
- **Reduced Motion:** no pulse (glyph static `circle.dotted`), no cross-fade; rows update instantly; the 150 ms stagger is dropped. The
  text "checking…" is the progress signal.
- No spinner anywhere, no progress bar.

### 5.5 The RYFT permission card (K7) and honest wording
HealthKit does not reveal whether RYFT may read a type. For the check, "nothing found" is therefore ambiguous. Rules for the copy (the
architect decides the logic):
- **Never claim RYFT *is* blocked.** Never claim the tracker *isn't* sending. Say both possibilities, then name the place.
- Shown whenever any tracker has K4 or K5. Placed last. Container as `InlineMessage` (`lock` glyph, `textSecondary`, `surface` at 60 %).
- Text: "For Health data, iOS only tells RYFT what it may read, not what it may not. So 'nothing yet' can mean no data, or that RYFT isn't allowed to read it."
- Instruction: "Check Settings → Health → Data Access & Devices → RYFT and turn on every type."
- Button: **Open Health permissions** (`.secondary`, existing `HealthLinks.open`).
- Case copy direction (row-level, to complete the K4 sentence; the localization-editor finalises):

| Case | Logic hint (architect) | Direction |
| --- | --- | --- |
| Some types from the tracker arrive, one should and doesn't | tracker present; type absent | Vendor permission is the likely cause: "should arrive, nothing yet", fix = the *vendor app's* Apple Health toggle for that type, then iOS Settings. |
| Nothing at all from the tracker | no sources match | K5 text. Both causes named; first action is open the vendor app and let it sync. |
| Nothing from *any* source, RYFT never asked | authorization status not determined | K9: "RYFT hasn't asked for Health access yet." **Allow access** (existing `model.requestHealthAccess`). Not an error. |
| Everything missing including iPhone steps | likely RYFT denied | Same as K7 text, but first sentence "Even your iPhone's steps aren't arriving, so RYFT may not be allowed to read Health." and the button is the only action. |
| All expected arriving | n/a | no permission card; K6 summary alone. |

### 5.6 VoiceOver
- Each tracker card is a container (label "Garmin Connect"); the summary line is the first element, then rows. Rows are single elements:
  label "Heart rate", value "Arriving, last 07:42" · "Not shared by Garmin Connect, expected" · "Should arrive, nothing yet. Fix available" ·
  "Waiting" · "Checking". Glyphs hidden.
- Row with a fix: custom action "Show setup steps"; the disclosure's buttons are reachable by swipe after the row.
- On completion post one `.announcement`: "Check finished. 6 of 6 expected signals are arriving." (or "… 4 of 6 … 2 need a fix."). During the run nothing is announced (rows
  would chatter). "Check again" while running: label "Checking", trait notEnabled.
- Focus after Check again: stays on the button; announcement carries the result.
- Order: header, cards in order, permission card, Check again.
- AX1–AX5: result under the name; disclosure buttons full width; pinned bar stacks; the screen scrolls (nothing nested scrolls).

### 5.7 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| header | Looks at the last 48 hours in Apple Health. Nothing is uploaded. | Sieht sich die letzten 48 Stunden in Apple Health an. Es wird nichts hochgeladen. |
| summary ok | %lld of %lld expected signals are arriving | %lld von %lld erwarteten Signalen kommen an |
| summary fix | %lld of %lld expected signals are arriving. %lld need a fix. | %lld von %lld erwarteten Signalen kommen an. %lld brauchen eine Korrektur. |
| waiting / checking | waiting… / checking… | wartet … / prüft … |
| last night | last night | letzte Nacht |
| expected | Not shared by %@ | Wird von %@ nicht geteilt |
| expected note | That's normal. | Das ist normal. |
| unexpected | should arrive, nothing yet | sollte ankommen, bisher nichts |
| fix lead | Check the Apple Health permission in %@ and make sure %@ is on. | Prüfe die Apple-Health-Berechtigung in %@ und achte darauf, dass %@ aktiviert ist. |
| fix several | Several signals should arrive and don't. The cause is usually one permission in %@. | Mehrere Signale sollten ankommen, tun es aber nicht. Meist liegt es an einer Berechtigung in %@. |
| show steps | Show setup steps | Einrichtungsschritte zeigen |
| silent | No data from %@ yet. Open %@ and let it sync, then tap Check again. | Noch keine Daten von %@. Öffne %@ und lass es synchronisieren, dann tippe auf „Erneut prüfen“. |
| silent hint | If it still shows nothing after it has synced, the Apple Health permission is the usual cause. | Zeigt sich auch nach dem Sync nichts, ist meist die Apple-Health-Berechtigung die Ursache. |
| show details | Show details | Details zeigen |
| perm text | For Health data, iOS only tells RYFT what it may read, not what it may not. So "nothing yet" can mean no data, or that RYFT isn't allowed to read it. | Bei Health-Daten sagt iOS RYFT nur, was gelesen werden darf, nicht was nicht. „Noch nichts“ kann also bedeuten: keine Daten, oder RYFT darf sie nicht lesen. |
| perm steps | Check Settings → Health → Data Access & Devices → RYFT and turn on every type. | Prüfe Einstellungen → Health → Datenzugriff & Geräte → RYFT und aktiviere alle Typen. |
| perm all missing | Even your iPhone's steps aren't arriving, so RYFT may not be allowed to read Health. | Nicht einmal die Schritte deines iPhones kommen an, RYFT darf Health womöglich nicht lesen. |
| not asked | RYFT hasn't asked for Health access yet. | RYFT hat noch nicht um Zugriff auf Health gebeten. |
| open perms | Open Health permissions | Health-Berechtigungen öffnen |
| check again / checking | Check again / Checking… | Erneut prüfen / Prüft … |
| announce ok | Check finished. %lld of %lld expected signals are arriving. | Prüfung beendet. %lld von %lld erwarteten Signalen kommen an. |

---

## 6. Today: the night, scoring and slow scoring

Reading order of Today (unchanged from the last release): header, greeting, sentence, **status line**, gauge, raw night (pending only),
**hint card**, tiles, other cards, Trends, error card. The hint card keeps its shipped slot (`WatchSyncHintCard`, between the raw-night card and the tiles).

### 6.1 Two distinct states, never both
| | **T1: night hasn't reached Apple Health** | **T2: Scoring** | **T3: Taking longer than usual** |
| --- | --- | --- | --- |
| Truth | RYFT has nothing to score yet: the tracker hasn't written the night | RYFT uploaded; the platform hasn't scored (`pending`) | `pending` for more than 3 × `expected_within_sec` |
| Status line | **unchanged: state 9** "Up to date · 2 min ago" (or whatever is true: 4/6/7/8) | state 5: "Scoring your night" / "Scoring your latest data" | state 5b: "Taking longer than usual · Details" |
| Hint card | **"Your night hasn't reached Apple Health yet. Open Garmin Connect to sync it."** + button | none | none |
| Gauge | row C waiting_for_sleep (shipped) | row C pending (shipped) | row C pending, **outline static** (no breathing) |
| "Scoring your latest data" | **never shown** | only if the pending day isn't last night | n/a |
Exclusivity rule (for the architect): T1 requires "nothing uploaded and unscored for today"; the moment an upload exists, T1 ends and T2 shows.
Status-line state 5's string is only ever produced from `pending`. `waiting_for_sleep` with no upload must never map to 5.

### 6.2 T1 hint card
- Container: shipped `InlineMessage` (symbol `moon.zzz`; was `applewatch.radiowaves.left.and.right`; `moon.zzz` is the night-specific state), message `callout`/`textSecondary`.
- Replaces the shipped stale-source hint *when the morning rule applies* (architect: newest sleep/HR from the user's tracker predates the last wake window). Outside the morning the shipped "Nothing new from {source} since {time}. …" remains, with the friendly source name.
- Action: one button **Open Garmin Connect** (`PrimaryButton(.secondary)` look, `callout`, min 44) using §3.6's variants. This needs `InlineMessage` to gain a plain action: `action: (title: LocalizedStringKey, perform: () -> Void)?` placed where `retry` sits; `retry` keeps its async "Trying again…" semantics. No action if the source has no app (Apple Watch): the sentence changes to the Watch form.
- Sentence variants:
  - App source: "Your night hasn't reached Apple Health yet. Open Garmin Connect to sync it."
  - Apple device: "Your night hasn't reached Apple Health yet. Keep your Apple Watch near your iPhone so it syncs."
  - Source unknown/unmapped: "Your night hasn't reached Apple Health yet." + **Check sync** button (Devices & sync).
  - No tracker chosen (T4, §7.4): shipped generic sentence; no regression.
- Dismissal: none. It disappears when a night sample arrives (cross-fade 250 ms; reduced motion: instant).
- Data age in the card's caption (`caption`, `textTertiary`, monospaced digits): "Last data from Garmin Connect: Wed 23:24" (shows the date, honest staleness; contrast flag as in the last release).
- VoiceOver: one element, label is the sentence, value "Last data Wednesday 23:24", button "Open Garmin Connect".

### 6.3 T2 Scoring
Shipped strings kept: "Scoring your night" (symbol `waveform.path.ecg`, pulse). "Scoring your latest data" only when `pending` is about newer data than the night. No new copy.

### 6.4 T3 Taking longer than usual
- Status line row 5b (between 5 and 6 in priority): `clock` symbol, "Taking longer than usual · Details", `textSecondary`, **no pulse** (nothing implies progress). Tap and "Details" open the Sync details sheet (shipped `SyncDetailsSheet`).
- Hero C: title "Scoring your night…" becomes "Taking longer than usual", detail "Your data is safe. RYFT will keep trying." (replaces "Usually ready within 20 s"). The outline gauge stays, breathing stops (static; under Reduce Motion already static).
- No error card, no retry button; the platform is working. After a further threshold the shipped error-card rules apply unchanged.
- VoiceOver: "Taking longer than usual. Details" with hint "Opens sync details"; one `.announcement` when it appears.

### 6.5 Interplay with last release's rows A–E and status states 1–9
| Hero row | T1 hint | Status line | Note |
| --- | --- | --- | --- |
| A scored | no (night arrived) | 9 | unchanged |
| B calibrating | no | 9 | unchanged |
| C waiting_for_sleep, nothing uploaded | **yes** | 9 (was "Scoring your latest data": removed) | gauge title "Waiting for last night's sleep" stays; the card carries the action |
| C pending, uploaded | no | 5 → 5b | as §6.1 |
| D recalculating | no | 9 | unchanged |
| E first import | no | importing row | the hint isn't shown while importing (shipped `watchHint` rule) |
States 1–4, 6, 7, 8 (action needed, offline, unlock, syncing, updating, stale, paused) **win over** T1's *line*, and the hint card still shows beside them only if the user is online (offline: a stale-tracker hint is noise, hidden). One retry/action on screen rule unchanged: the hint's button is an "open app" action, not a retry; if the error card is showing, the hint card drops its button.
Dimming, dates, tiles, delta rules from rows A–E are untouched.

### 6.6 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| T1 app | Your night hasn't reached Apple Health yet. Open %@ to sync it. | Deine Nacht ist noch nicht in Apple Health angekommen. Öffne %@, um sie zu synchronisieren. |
| T1 Apple | Your night hasn't reached Apple Health yet. Keep your Apple Watch near your iPhone so it syncs. | Deine Nacht ist noch nicht in Apple Health angekommen. Halte deine Apple Watch in der Nähe deines iPhones, damit sie synchronisiert. |
| T1 unknown | Your night hasn't reached Apple Health yet. | Deine Nacht ist noch nicht in Apple Health angekommen. |
| T1 age | Last data from %@: %@ | Letzte Daten von %@: %@ |
| T1 action | Open %@ | %@ öffnen |
| T3 line | Taking longer than usual · Details | Dauert länger als üblich · Details |
| T3 title | Taking longer than usual | Dauert länger als üblich |
| T3 detail | Your data is safe. RYFT will keep trying. | Deine Daten sind sicher. RYFT versucht es weiter. |
Existing and unchanged: Scoring your night · Scoring your latest data · Waiting for last night's sleep.

---

## 7. Today: when no tracker was chosen, and fallbacks
7.4 (T4): no selection (skipped): everything as shipped, but friendly source names come from `trackers.json` where known. Unmapped sources
display the HealthKit name and add nothing. Never "Connect" for Garmin Connect once mapped (brief §4).

---

## 8. Calibration honesty on Recovery / Readiness detail (§1, later)

### 8.1 R1: recovery without HRV
- Where: Recovery detail and Readiness detail, a note directly under the score block, before the charts. `GaugeNote` look (shipped, `MetricGauge.swift`): glyph
  `info.circle`, `caption`/`textSecondary`, but **left aligned and full width** (the shipped note centres; a two-sentence note + link reads better left-aligned; add `alignment` parameter).
- Text: "Based on resting heart rate, sleep and breathing rate. Your tracker doesn't share HRV with Apple Health." The first sentence lists the platform's `recovery_inputs` (composed from the actual list, not fixed). "Your tracker" becomes the tracker's name when exactly one selected tracker lacks HRV: "Garmin Connect doesn't share HRV with Apple Health."
- Link: **How to set up {tracker}** (`callout`, `Theme.accent`, 44 pt, `chevron.right`): opens the tracker's card (a sheet with `NavigationStack` and "Done", same as the status sheets). Several trackers: **Devices & sync**. No tracker chosen: **Choose your tracker** → picker sheet.
- If HRV *is* arriving, no note. If `recovery_inputs` has fewer signals than usual, the sentence lists what's missing the same way ("… no breathing rate.").
- VoiceOver: one element for the text, link as the second element ("How to set up Garmin Connect, link"). Dynamic Type: wraps, link on its own line.

### 8.2 R2: Baseline gauge never shows a counter that can't move
`BaselineGauge` (in `MetricGauge.swift`) gets a **blocked** mode, used when the platform says a required signal has no source (e.g. RHR missing, or HRV the only required signal and absent):
- Seven segments drawn as `textTertiary` hairline outlines (like `PendingGauge`), none filled. Centre: "—" in `ryftNumber`, `textTertiary`. Caption under the dial (`caption`/`textSecondary`): **"Needs resting heart rate"** / "Braucht Ruheherzfrequenz" (names the missing signal; plural-aware list: "Needs resting heart rate and sleep").
- Below it a `GaugeNote`: "No source in Apple Health yet. Check how your tracker shares it." with link **Check sync** (opens Devices & sync → Check sync).
- Never "n of 7" in this mode. If HRV is missing but RHR counts, the gauge counts normally (its counter *can* move); the HRV statement lives in the R1 note.
- VoiceOver: "Baselines, waiting for resting heart rate. No source in Apple Health yet." No pulse, no animation (nothing is happening).
- Copy: "Needs %@" · "No source in Apple Health yet. Check how your tracker shares it." | "Braucht %@" · "Noch keine Quelle in Apple Health. Prüfe, wie dein Gerät sie teilt."
- Combined with the previous release's row B: row B's existing `needsVitals` note reads from the same source (the signal list); the architect keeps one decision.

---

## 9. Components, files, previews

No new Swift files. Placement (all `Theme`/`Typography` tokens only):

| Component | Kind | Goes into | Notes |
| --- | --- | --- | --- |
| `SelectableTile` | new | `Design/Card.swift` | symbol, title, `isSelected`; tile of §2.2 |
| `CapabilityRow` + `CapabilityState` | new | `Design/Card.swift` | yes / partial / no / notAvailable |
| `NumberedStep` | promote shipped private `SetupStep` | `Design/StatusViews.swift` (drop `private`, rename or keep name) | used by cards and fix disclosures |
| `TrackerSetupCard`, `TrackerCardHeader` | new | `Design/StatusViews.swift` (next to `SetupCard`) | takes a `TrackerGuide` value; no networking |
| `CheckRow` + `CheckRowState` | new | `Design/StatusViews.swift` | K2–K5 states |
| `TrackerCheckView` (screen) | new | `Features/Profile/ProfileView.swift` | pushed and embeddable in onboarding |
| `DevicesAndSyncView` | new | `Features/Profile/ProfileView.swift` | §4 |
| `TrackerPickerView` (+ onboarding step `wear`) | new | `Features/Onboarding/HealthPermissionView.swift` | uses `OnboardingScreen`, pinned bar |
| `TrackerSetupStepView` (post-Health) | new | `Features/Onboarding/HealthPermissionView.swift` | §3.5 |
| `InlineMessage.action` | extend | `Design/StatusViews.swift` | plain action, not a retry |
| `WatchSyncHintCard` | extend | `Features/Today/TodayView.swift` | night variants, action |
| `SyncLine.slow` (state 5b) | extend | `Features/Today/TodayViewModel.swift` | symbol `clock`, no pulse |
| `BaselineGauge.blocked` | extend | `Design/MetricGauge.swift` | R2 |
| `GaugeNote` | extend | `Design/MetricGauge.swift` | `alignment`, optional link |
| `LinkRow` | promote shipped private | `Features/Profile/ProfileView.swift` | already shared there |

### Previews (each: dark, light, **de**, **AX3**; screens also **AX5** for the grid and the pinned bar). Component previews use `SchemePair`; screens use `.previewEnvironment`.
1. `SelectableTile · states` (Card.swift): unselected, selected, long name (Samsung Galaxy Watch), full-width "Just my iPhone".
2. `CapabilityRow · states` (Card.swift): yes, partial with detail, no with reason, notAvailable; AX3 stacked.
3. `Tracker picker` (HealthPermissionView.swift): empty, Garmin + Oura selected, Just my iPhone selected; AX5 (single column, pinned bar stacked).
4. `Tracker card · Garmin` (StatusViews.swift): full, collapsed header, expanded; HRV "Not shared"; guide fresh.
5. `Tracker card · guide stale` (>180 days caption).
6. `Tracker card · Fitbit` (honest limit), `· Samsung`.
7. `Tracker card · Just my iPhone`, `· Other`, `· Apple Watch`.
8. `Tracker card · Open variants`: Open (verified scheme), Open in App Store, Get.
9. `Check sync · running` (rows waiting/checking/ok mix), `· all arriving`, `· HRV expected missing` (Garmin: the K3 case), `· resting HR unexpected` with the fix, `· several unexpected` (one disclosure), `· silent tracker` (K5), `· permission card`, `· not asked yet` (K9), `· Just my iPhone`, `· Other`. Reduced-motion variant: `.environment(\.accessibilityReduceMotion, true)` for `running`.
10. `Devices & sync` (ProfileView.swift): none chosen, two trackers (watch + ring) with statuses, with an unmapped source, "Check needed".
11. `Profile · Data row` (ProfileView.swift): the new first row, showing the Garmin caption removed.
12. `Today · night hasn't arrived` (TodayView.swift): hero C waiting_for_sleep + T1 card (app, Apple device, unknown source), status line 9; AX3.
13. `Today · scoring` (shipped C pending) and `Today · taking longer` (5b + hero C slow, static outline).
14. `Status line · taking longer` (StatusViews.swift, extends "Sync status line").
15. `Recovery detail · no HRV` (the detail screen file) with the R1 note and link; one-tracker and multi-tracker link variants.
16. `Baseline gauge · blocked` (MetricGauge.swift), `GaugeNote · link`.
Mock data: add Garmin-like scenarios to `MockHealthStore` (sources without HRV) so previews, UI tests and screenshots share them.

### Identifiers for UI tests
`wear.tile.<id>`, `wear.continue`, `wear.skip`, `tracker.card.<id>`, `tracker.open`, `tracker.later`, `check.run`, `check.row.<signal>`, `check.summary`, `devices.row.<id>`, `today.nightHint`.

---

## 10. Open questions
1. **Data sources** is named in the brief but not a screen in `Ryft/` at d9fc265 (only the Data section's Garmin sentence and Sync details → Streams). Confirm whether it lives on another branch or was meant as "the sources the platform reports" (`User.sources`); §4.1 assumes the latter and shows them as "Seen in Apple Health".
2. **Opening another app:** iOS gives no installed-apps list and no safe URL schemes; `LSApplicationQueriesSchemes` entries and verified `open_url` need an Info.plist/capability decision (a user step in Xcode). §3.6 degrades to the App Store page.
3. **Matrices and steps** are placeholders until verified against each vendor's current help page; every card shows its `checked` date. Garmin and Oura HRV claims are in the brief as "verify" and must be, or the "Not shared" row for them must read "Partly / unclear".
4. **Samsung / Fitbit "Tell us you'd like this":** needs product approval (it turns a dead end into a feature-request signal through Report a problem).
5. **Account storage:** if `User.trackers` via PATCH isn't accepted, the selection stays local; "so support can see it" is dropped from the footnote? Footnote avoids the claim; confirm.
6. **Amber `warning` on `surface`:** the glyph is non-text (3:1); confirm both schemes against the asset values in review.
7. **Morning rule** (when T1 appears) and the 48 h window are the architect's; the copy above assumes T1 only appears when the tracker's newest sleep/HR is older than the last wake window.
8. **Apple Watch capability detail** ("Sleep stages need watchOS 9 or later") is unverified for iOS 27-era models; verify or drop.

## Errata (lead, 2026-10-22, after the T1 and T3 reviews)

These override the sections above.
1. **Glyphs** (§0.7, §2.2, §3, §4, §5): Apple glyphs are chosen by **tracker id**, never by form.
   - `apple_watch` → `applewatch`; `iphone` → `iphone`.
   - Every other watch → `watch.analog`; ring → `circle.circle`; band → a distinct neutral glyph (T2 proposes one);
     Other → `ellipsis.circle`.
   - A remote catalog entry can never get an Apple glyph. SF Symbols restricts Apple-product glyphs to the Apple products
     themselves.
   - Generic "devices" places (the Devices & sync row, the card headers at lines 153 and 242) use
     `antenna.radiowaves.left.and.right`, never `applewatch`.
2. **The store button** (§3.6, the copy table): RYFT declares no URL schemes, so row 1 of the §3.6 table (a verified
   `open_url`) never applies.
   - The button always reads **"{app} in the App Store" / "{app} im App Store"** and opens the App Store page, which shows
     "Open" when the app is installed.
   - Sentences such as "Open {app} to sync it." stay as written.
3. **Health** (§4, §5): the button "Open Health permissions" becomes **"Open Health" / "Health öffnen"**, because
   `x-apple-health://` opens the Health app's start screen. The path text from the catalog's `health_access.steps` always
   sits next to it.
4. **Fix panel** (§5.2): the setup steps show **inline** in the fix panel, from the catalog, with no "Show setup steps"
   button. In a raised panel, the secondary button gets a visible shape (outlined, or on `surface`).
5. **Permission card wording** (§5.5):
   - en: "iOS doesn't tell apps whether they may read Health data: RYFT only sees what it's allowed to read. So “nothing
     yet” can mean no data, or that RYFT isn't allowed to read it."
   - de: "iOS sagt Apps nicht, ob sie Health-Daten lesen dürfen: RYFT sieht nur, was es lesen darf. „Noch nichts“ kann
     also heißen: keine Daten, oder RYFT darf sie nicht lesen."
