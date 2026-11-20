# Nocturne PR 6, area C — Profile's subpages, Sleep's sheets, the widget

Ticket T6C.1 · ui-designer · 2026-11-18 · base `origin/main` 9af6049 · English only · dark only.
Inputs: `brief.md`, `plan.md` (D6, L27–L30), `design.md` (PR 1–4: tokens, components, P2-8, §P4-6, the PR 4 conventions),
`audit.md`, the PR 5 boards (`pr5-boards.md`), the PR 2–4 components in `Ryft/Design/`.
**Status: a draft for the user's approval (L28).** No board exists for any screen here; the renders below are composed
from the components and the proposals in §3, not from the shipped views. Nothing is built until the user approves.

Draft renders (390 × 844, dark, English, synthetic data, 3x PNGs) are in
`pr6-drafts/c/` in the lead's session scratchpad (not in the repo),
named `c-<nn>-<screen>.png`. §1 maps each screen to its file. The draft code (a hosted test that composes the views) is not
in the commit: the real primitives are §3's job.

Conventions as in PR 4: the board is 390 pt wide and content is **350 pt** (20 pt sides); CSS px = pt; "ink" is
`Theme.textPrimary`; ink alphas map to tokens (**0.62 = `textSecondary`**, **0.55 and 0.45 = `textTertiary`** (48 %),
0.78 = a glow-tile label); a gap is from the bottom of the element above to the top of the next; a text line is its natural
height. Content starts at the safe-area top (D4-1). Layout constants are `nonisolated static let`s on a layout type so tests
assert numbers, not pixels (P2-D9). Where a number is mine and not from a board it is marked "derived".

---

## 1. Scope and inventory

Everything the audit marks C or D that is not Today, Sleep Day, PR 5 (Strain, Workout detail, Insights, Profile's main
list, the tab bar, Sleep Week, Month, Bedtime) or PR 6 areas A (signed out, onboarding, splash, status sheets) and B
(Train, My Day, Journal sheet). **Beyond the lead's list** I found and took: Account, Privacy, Data and Training (today
sections of the long Profile page; their homes depend on PR 5's main list, see §4.0), the Maximum heart rate editor, Tracker
detail and the tracker picker sheet, Add a behavior, the Sleep-need card that opens the need sheet, the training import's six
steps with their dialogs, the two Live Activities (Rest timer, Wake-alarm snooze) and the Start-workout control. Not taken:
DEBUG-only screens (Component catalog, Feature flags, the Developer section), which stay as they are and are not reachable in
Release; the Safari legal sheet, the share sheet and the HealthKit sheet (system, §4.9).

| § | Screen | Reached from | Today's file | Draft |
|---|---|---|---|---|
| 4.1 | Display | Profile → Settings | `ProfileView.display`, `HeroNumeralsRow` | c-01, c-01b, c-01x |
| 4.2 | About | Profile → Settings | `ProfileView.about` | c-02 |
| 4.3 | Report a problem (form, states, sent, queued) | About; an error's Details | `ReportProblemView` | c-03…c-04b |
| 4.4 | Devices & sync | Profile → Devices and sync | `DevicesAndSyncView` | c-05, c-05b, c-05c, c-05x |
| 4.4 | Tracker detail · tracker picker sheet | Devices & sync | `TrackerDetailView`, `TrackerSetupCard`, `TrackerPickerSheet` | c-06, c-07 |
| 4.5 | Check sync | Devices & sync | `TrackerCheckView`, `CheckRow` | c-08, c-08b |
| 4.6 | Sync details | Devices & sync; Today's status line (sheet) | `SyncDetailsView` | c-09, c-09b |
| 4.7 | Notifications (switches, rolling out, off in iOS) | Profile → Settings | `NotificationSettingsView` | c-10, c-10b, c-10c |
| 4.8 | Journal (settings) · Add a behavior | Profile → Settings | `JournalSettingsView`, `AddBehaviorSheet` | c-11, c-11b |
| 4.9 | Sign-in methods · Licences | Account; About | `SignInMethodsView`, `LicensesView` | c-12, c-12b, c-13 |
| 4.10 | Account · Privacy · Data · Training | Profile | `ProfileView.account/privacy/data/training` | c-14, c-15, c-16, c-16b, c-17 |
| 4.11 | Baseline sleep need · Maximum heart rate (editors) | Profile → About you; the need sheet | `BaselineSleepNeedForm`, `MaxHeartRateForm` | c-19, c-19b, c-19x, c-20 |
| 4.12 | Sleep need (card, sheet) | Sleep Day | `SleepNightCards`, `SleepNeedSheet`, `SleepNeedBar` | c-18, c-18b, c-18c |
| 4.13 | Bedtime & wake (editor) · Tonight (card) | Sleep Bedtime; Profile → Sleep | `SleepScheduleView`, `TonightCard` | c-21, c-21b, c-22, c-22b, c-22c |
| 4.14 | Import training data, steps 1–6 | Profile → Data | `Features/Train/Import/*` | c-23, c-23b, c-23c, c-23d |
| 4.15 | Widget: home small, lock screen, Rest timer, Wake snooze | the system | `RyftWidgets/*`, `Shared/*` | c-24…c-27 |
| 4.16 | System dialogs the app controls | various | — | table only |

---

## 2. The grammar (one for every page in this document)

Subpages must read as children of the Profile board's grouped-card list: the same card, the same row, the same type, the same
hairline. Everything here is built from the PR 2–4 components and the shared grammar the lead set for PR 5 and 6; the three
things that are not covered are in §3.

### 2.1 The subpage frame

| Part | Spec |
|---|---|
| Navigation bar | Hidden (`toolbar(.hidden, for: .navigationBar)`). The frame draws its own header. The interactive back swipe must keep working: with the bar hidden SwiftUI may disable the edge swipe, so the frame re-enables the interactive pop gesture (the usual one-time `UINavigationController` extension) and a hosted test proves the gesture still pops. |
| Header | 40 high, content's first row. Pushed page: a `CircleButton` "Back" (chevron.left, 14 pt, 44 pt box overhanging 2 on each side as in `ScreenHeader`), 12 pt gap, the title `Font.ryft(.title)` (26 Light), tracking −0.01 em, one line (`minimumScaleFactor(0.8)`), then a flexible gap and 0–2 trailing `CircleButton`s (8 apart). Sheet root: no back; a trailing `CircleButton` "Close" (xmark) and the title leading. A page pushed inside a sheet shows Back, not Close. The title carries the header trait. |
| Header → content | 22 below the 40 pt row (the Strain board's 22). |
| Scroll | One `ScrollView`, `scrollIndicators(.hidden)`, content 350 wide (max 560, centred, as `ImportStepScaffold` has it), 20 sides, 32 below the last group plus the safe area. Pull to refresh only where a page has one today (none of these do). |
| Pinned action bar | When a page has one primary action (Send, Save, Done, Check again, Continue): a bar in `safeAreaInset(.bottom)`: `background` fill, a 1 pt `separator` hairline on top, 12 above the pill, the pill 52, 12 below plus the safe area. A caption that says **why the pill is disabled** sits above the pill (12 pt `textSecondary`, centred); a **footnote** sits below it (12 pt `textTertiary`). The pill grows to three lines at AX3 (about 155 pt) and the bar with it; the scroll content keeps room for it. |
| Sheet | `.presentationDetents([.large])`, drag indicator visible, `presentationBackground(Theme.background)`. The header starts 26 below the sheet's top edge (derived). |
| Backgrounds | `Theme.background` everywhere; the system's grouped and list backgrounds are never used (no `List`, no `Form`). |

### 2.2 Groups and rows

Groups are the board's grouped cards. A group is an optional title, a card, and an optional footer.

| Part | Spec |
|---|---|
| Group title | 13 pt (`.label`), `textTertiary`, flush with the card's left edge, 8 above the card; header trait. A trailing text action may sit on the title's line ("Edit") as a text link (§2.6). |
| Card | `surface`, radius 22 (`Theme.Metrics.neutralTileRadius`, continuous), no border, no shadow. Rows inside have no background of their own. |
| Row | at least **46** high, padding 0 16, 12 between leading glyph, text and trailing item; title 15 pt (`.callout`) `textPrimary`; text never truncated (it wraps; the row grows). A row with a second line has 10 above and below; the second line is 12 pt (`.caption`) `textTertiary`, 2 below the title. |
| Hairline | 1 pt `separator` between rows, inset 16 on both sides (the card's padding). The board says 0.06 and `separator` is 0.08: the token wins (D6C-1). |
| Footer | 12 pt `textTertiary`, flush left, 8 below the card, any number of lines; one sentence of what the group does or why. |
| Groups apart | **18** (bottom of a card or footer to the next group title's top). |
| Leading glyph | where a row stands for a thing (a tracker, a sign-in method, a file): a 36 pt circle with a 1 pt `textPrimary` 16 % border, an SF Symbol 16 pt Light in `textPrimary` (the Strain board's activity circle). |

**Row kinds** (one SwiftUI type, `SettingsRow`, with a `Kind`): every kind has the same height, padding and title.

| Kind | Trailing | Role (VoiceOver) |
|---|---|---|
| value | a value, 15 pt `textTertiary` (0.55 on the board), tabular | static text; one element "title, value" |
| push | an optional value, then a chevron (12 pt semibold, ink 35 %) | button, hint "Opens …" |
| link-out | "↗" (15 pt, ink 35 %, hidden from VoiceOver) | link, hint "Opens in Safari" or "Opens Health" |
| action | an SF Symbol 15 pt at ink 55 % (arrow.clockwise, doc.on.doc, eraser, plus, arrow.uturn.backward) | button |
| select | a checkmark (14 pt medium, `textPrimary`) on the chosen row, nothing on the others | button, `isSelected` on the chosen row |
| toggle | the switch (§2.4) | switch, value on/off |
| destructive | nothing; the title in `Theme.alert` (5.7:1 on `surface`) | button; the role is spoken only by the dialog that follows |

The ↗ and the chevron are at 35 % (3.0:1) because they are decoration: the row's title and its role say what it is.
Everything that is read as text is at 48 % or more (4.5:1).

### 2.3 Colour rules (L27)

Teal is recovery only. Nothing on these pages is teal. Checkmarks, toggles, links, icon tints and step marks are `textPrimary`
or its alphas. Volt (`Theme.signal`) appears only as the ruler's needle (the editors, §4.11), which is on the brief's list; the import's step rule is neutral (§3, row 5). Amber (`Theme.warning`) is the one "needs attention" tone (a missing
signal in Check sync, a refused permission); coral (`Theme.alert`) is for destructive rows and a hard failure. Each is paired
with a glyph and a word, never alone. The metric colours appear only where a metric is shown (the Sleep need tile).

### 2.4 The switch (shared primitive, §3 row 2)

A system `Toggle` tinted `textPrimary` has a white knob on a near-white track, so its on state loses the knob. The neutral
switch is drawn: 48 × 30, knob 22 with 4 inset. **On:** track `textPrimary` (16.2:1 on `surface`), knob `background`.
**Off:** no fill, a 1 pt border in `textPrimary` 35 % (3.0:1), knob `textPrimary` 55 % (5.6:1). The knob slides 250 ms (none
under Reduce Motion). It is a `ToggleStyle`, so a `Toggle` keeps its binding, its disabled state (the whole row at 35 %) and its
VoiceOver switch semantics (`accessibilityAddTraits(.isToggle)` and an on/off value, proved by a hosted test). The whole row
is the 46 pt target.

### 2.5 Fields and forms (the P2-8 tokens)

A field is a row-shaped card: `surface`, radius 22, padding 0 16, one line at 46, or a multi-line field with a minimum
height (Report's message: 132) and 14 above and below the text. The text is `.callout` `textPrimary`; the prompt is
`textTertiary` (4.5:1). Focus: a 1 pt border in `textPrimary` 30 %, no animation. The field's label is the group title above it
(13 pt, `textTertiary`); its helper is a footer. A counter ("812 / 4000") sits bottom-right inside the card at 12 pt
`textTertiary` and turns `warning` over the limit with the word "too long" in the footer. Keyboard: `scrollDismissesKeyboard(.interactively)`
and a "Done" key-bar button as today. Pickers that must stay system controls (compact time, menu) are tinted `textPrimary`
and sit in a row's trailing slot.

### 2.6 Buttons, links, destructive and busy states

| Role | Look | Where |
|---|---|---|
| Primary action | `PillButton(.primary)`: the light pill, the dark 40 pt icon circle, 52 high. The one per page, pinned (§2.1) or the page's only action in flow. Icons: arrow.right (go on), checkmark (save, done), arrow.up (send), arrow.clockwise (again), plus (add) | Save, Send, Done, Check again, Continue, Choose files |
| Secondary | `PillButton(.secondary)`: outline 52 | Done on a result page, Open plan |
| Action row | a row (§2.2), not a pill | everything else: Allow access, Open Health, Sync now, Copy diagnostics, Rescore, Use the estimate |
| Text link | `Font.ryft(.button)` (16 Medium), `textPrimary`, a 1 pt underline in ink 35 %, 44 pt tall. The underline is the non-colour cue that tells it from body text. | an action inside a notice ("Try again", "Copy message", "Add workouts file"); a title-line action ("Edit") |
| External link | a link-out row (↗) | Privacy Policy, Terms of Use, store pages |
| **Destructive** *(shared, to reconcile with T5.0)* | A destructive **row** in `Theme.alert` at the end of its group, never a filled red pill. Where it is a page's only action (rare) a `PillButton` destructive style: outline 1 pt `alert` at 45 % (2.1:1 border, decoration), title `alert`, 52 high. The confirmation is always the system dialog, with its destructive button (§4.16). | Delete account, Withdraw consent, Full re-sync, Turn off Bedtime & wake |
| **Busy** *(shared, to reconcile with T5.0)* | No spinner. The control's title changes to the progressive form ("Sending…", "Checking…", "Syncing…", "Saving…"), the control is disabled, and its glyph becomes `ellipsis` (a primary pill's icon circle shows it at 55 %; an action row's trailing glyph is replaced by it). The ellipsis pulses 100 → 35 % over 1 s while busy (none under Reduce Motion; the title says it). The pill's fill drops to 35 % like any disabled pill. | Send, Check again, Sync now, Save, Rescore |
| Disabled | the whole control at 35 % (as `PillButton`); a caption above says why when it is not obvious | Send with no message; Continue with items left to check |

### 2.7 Notices and honest states

An inline notice replaces `InlineMessage` on these pages: a `surface` card (radius 22, padding 14 16), a 16 pt glyph in
`textSecondary` (not teal), the sentence in `.callout` `textPrimary`, an optional 12 pt caption (`textTertiary`; the request ID
lives here), an optional text link. Amber glyph only where the notice asks the user to fix something. It sits above the
group it is about, 18 apart. VoiceOver reads it as one element, in order.

Every page states **loading** (rows with their titles and "–" values, never a spinner; a list of unknown length shows one
outline card, 1 pt `separator`, with a caption "Loading…"), **empty** (the sentence that says why and the one action),
**offline** (the cached values stay; a notice "You're offline. …" where an action needs the network), **error** (a notice with
the request ID in its caption and a Details link into Report a problem), **saving** (§2.6 busy), **demo** (a caption
"Demo data" where a write goes nowhere, as Report already says). The per-page tables below list only what differs.

### 2.8 Motion

Every animation is `Theme.Motion.quick` (250 ms ease-out): the switch's knob, a disclosure opening, a row's state change,
the ruler's needle (the component's own). Nothing springs, nothing counts up. **Reduce Motion:** no animation at all; the
busy ellipsis is static; the disclosure and the Report result cross-fade becomes a cut.

### 2.9 Accessibility and Dynamic Type, the baseline

- **Order** is visual order: header (title, then buttons), notices, groups top to bottom, rows top to bottom, the pinned bar.
  A group card is not one element; each row is. A group title has the header trait so the rotor reaches it.
- **Labels:** icon-only buttons say what they do ("Back", "Close", "Add a behavior", "Less", "More"). A row is one element
  "title, value" (value rows) or "title" with the value as its value (push rows). Colour never carries state: select rows
  have a checkmark and the `selected` trait, switches say on/off, Check sync's rows say their result in words.
- **Hit targets** 44 pt or more (rows are 46; a CircleButton's box is 44).
- **Dynamic Type to AX3:** the header becomes two rows (Back and the trailing buttons, then the title, wrapping), the title
  scales (`.title`); rows grow, never truncate; a value row's value goes under its title (as `SettingRowLabel` does today);
  toggle rows keep the switch trailing, the text wraps beside it; pickers in a row's slot go under the title; the pinned
  bar's pill wraps to three lines; `DotNumeral` falls back to Light digits from AX1 (the PR 3 rule); a two-up becomes one
  column. Group titles are capped at AX3 (`dynamicTypeSize(...accessibility3)`, as `ProfileSection` does).
- **Reduce Transparency:** nothing here uses blur; glow tiles use PR 2's flat fallback.

---

## 3. Shared primitives requested

These are not covered by PR 2–4. They are proposals, small and token-only; the PR 5 and the other PR 6 designers will ask for
overlapping ones, so the lead reconciles them into one set in T6.0 (§7). Names are proposals.

| # | Primitive | Proposal | Used by | Reconcile with |
|---|---|---|---|---|
| 1 | `SettingsGroup` + `SettingsRow` (+ `SettingsDivider`) | §2.2. `SettingsGroup(title:footer:trailingAction:content:)`; `SettingsRow(title:subtitle:value:glyph:kind:)`. Dividers: draw each row's top hairline offset 1 outside its frame and clip the card, so no variadic API is needed on iOS 17 (the first row's hairline falls outside). Replaces `ProfileSection`, `StatRow` on these pages, `SettingRow`, `SettingRowLabel`, `LinkRow`, `ReportProblemRow`, `DevicesRowLabel`. | every page | Profile's main list (PR 5, T5.x): the same type, so its groups are these groups |
| 2 | `NocturneSwitchStyle` (`ToggleStyle`) | §2.4 | Notifications, Journal, Bedtime & wake, Report, Data, Training | all areas with a toggle |
| 3 | `SubpageScaffold` | §2.1: hidden bar + back-swipe shim, header, scroll, optional pinned bar, sheet variant | every page | PR 5 Profile (root has no back), area B's Train pages |
| 4 | `PillButton` additions | `Style.destructive` and a `busy` flag (§2.6). Additive; the caller still disables | Send, Check again, Sync now, Save | **T5.0** (the lead named destructive and busy "shared") |
| 5 | `StepRule` restyle | The six segments: done `textPrimary` at 55 %, **current `textPrimary` in full**, upcoming `textPrimary` at 16 % (the track token); 3 pt high, 4 apart; "Step 3 of 6" says it in words. Replaces the teal fill. No Volt: its list is closed. Only the import uses it | Import | none |
| 6 | `SettingsNotice` | §2.7, replacing `InlineMessage` on these pages (the type stays for the rest of the app until PR 6 finishes) | all | area A and B will want the same restyle: one component, `InlineMessage` restyled in place is the cheaper form |
| 7 | `TextAction` | §2.6 text link: 16 Medium, underline at 35 %, 44 tall | notices, title lines, import | all |
| 8 | `NeutralSelectableTile` | `SelectableTile` with the accent removed: selected = `surfaceRaised` fill, a 1 pt border at 30 %, `checkmark.circle.fill` in `textPrimary`; unselected = `circle` at 35 % | tracker picker; area A's "What do you wear?" in onboarding is the same tile | area A |
| 9 | `NumberedStep` restyle | The 22 pt circle outlined at ink 20 % with the number in `textPrimary` (was a teal badge) | Devices, Tracker detail, Check sync | area A (onboarding tracker setup uses it) |
| 10 | `CheckRow` palette | `ok` = `textPrimary` (was the accent). The other kinds keep their symbols and colours (amber for `fix`) | Check sync | area A's tracker setup |

Not requested, deliberately: a settings-specific toggle, a settings-specific button, a list. `List` and `Form` are not used
(they cannot take radius 22 or the hairline inset on iOS 17).

---

## 4. Screens

Each screen: what the eye sees first and second, the layout in the §2 grammar, the states that differ, copy (English, today's
key unless marked **new**), accessibility, AX3. Tests and files per screen are in §6 and §7.

### 4.0 How the pages hang on Profile's main list (an assumption, PR 5 owns the list)

The PR 5 board's list has three groups: About you (Birth year, Maximum heart rate, Baseline sleep need), Devices and sync
(Apple Health access, Trackers), Settings (Notifications, the journal row, Privacy Policy), and the pills Export data and Log out.
The app's long page has more content than that. My assumption, which the Profile designer may overrule without touching the
pages: **every page here is a group or two that the main list can show inline or push**, because they are the same
`SettingsGroup`.

| Row on the main list (assumed) | Opens | § |
|---|---|---|
| the avatar row | Account | 4.10 |
| Birth year | a menu (system `Picker`, tinted `textPrimary`; "Not set" while empty) | 4.11 |
| Maximum heart rate · Baseline sleep need | the editors, as sheets | 4.11 |
| Apple Health access · Trackers | Devices & sync | 4.4 |
| Notifications · Journal · Display · Training · Privacy | their pages | 4.7, 4.8, 4.1, 4.10 |
| Data (sync, import, demo) | Data | 4.10 |
| About | About (Report a problem, Licences, legal links) | 4.2 |
| Export data (pill), Log out (pill) | the share sheet; the Log out dialog | 4.16 |

### 4.1 Display (c-01, c-01b, c-01x)

**Purpose:** choose how Today, Sleep and Strain draw their large numbers. **First thing the eye sees:** the preview, which shows
the effect (the numeral of today's readiness in the chosen style), then the two choices.
- Layout: header "Display" · 22 · a preview tile (`surface`, radius 22, 132 high, centred): `DotNumeral("84")` in the chosen
  style (Light 52 for Thin), 10 below it "Readiness · High" 13 pt `textSecondary` · 18 · group "Hero numbers": select rows "Dots"
  (default) and "Thin" · footer "Large numbers on Today, Sleep and Strain.".
- A choice applies at once (the screens read the observable `Settings`, `ui.heroNumerals`, unchanged).
- States: at AX1 and up the numeral is Light whatever is chosen (the PR 3 rule); the preview then shows Light, the rows stay
  selectable (the preference is kept), and a second footer line reads **new** "Larger text sizes always use thin digits.".
- VoiceOver: the preview is one element "Preview of the hero numbers. Readiness 84 of 100." (**new**); the rows are "Dots, selected" and "Thin".
- Copy: keeps "Hero numbers", "Dots", "Thin", the footer; adds the line above.

### 4.2 About (c-02)

**Purpose:** who made it, which version, the disclaimer, support and legal. **First:** the brand lock-up.
- Layout: header "About" · 22 · `BrandLockup` (mark 44, wordmark 32, the tagline 13 pt `textSecondary`), centred, 8 above and 14 below
  · group: value row "Version" `1.4 (213)` · 18 · the disclaimer as a 15 pt `textSecondary` paragraph (legal wording unchanged) · group "Help":
  push rows "Report a problem" (value "2 waiting to send" when a report is queued, 48 %) and "Licences" · group "Legal and sources": link-out
  rows "Privacy Policy", "Terms of Use", "Apple Health privacy", and, only while `devices.setup` is off, "Garmin Connect and Apple Health".
- The legal rows open the Safari sheet the app already has (`SafariView`); its bar tint is `background`, its control tint `textPrimary` (§4.16).
- VoiceOver: the lock-up reads "RYFT, Engineered for peak." (as `BrandLockup`); link-out rows say "link" and "Opens in Safari".
- AX3: the lock-up keeps its size; rows wrap; the "2 waiting to send" value goes under "Report a problem".

### 4.3 Report a problem (c-03 … c-04b)

**Purpose:** tell RYFT what went wrong, with only the diagnostics the user allows. **First:** the message field, then the category, then what is attached.
- Layout: header "Report a problem" · 22 · [a context chip when opened from an error's Details: a capsule (`surface`, 12 pt `textSecondary`,
  padding 8 14) "About: Today · 503 · request 01a14ffa…"; VoiceOver reads the whole ID] · [a notice for a refusal, below] · group title "Message" · a
  multi-line field card (132 min, §2.5), counter bottom-right · footer "Please don't type health values you'd rather keep private." ·
  group "Category": four select rows ("Something's broken", "An idea", "My numbers look wrong", "Something else") · group "Diagnostics":
  a toggle row "Include diagnostics" (footer "Nothing is attached except your message." while off; while on, a disclosure row "What's included" that
  opens the list inside the card: bullets at 12 pt `textSecondary` and the sentence "No health values: …" in `textPrimary`) · pinned bar: **Send**
  (primary, arrow.up) and under it "Reports are limited to 10 a day.".
- The bullets are the exact items `FeedbackPayload` sends, in its order (unchanged logic, `included(about:)`).

| State | Trigger | Look |
|---|---|---|
| Empty | no message | Send disabled (35 %); the prompt "What happened? What did you expect?" |
| Writing | focus | 1 pt focus border; counter shows (`model.showsCount`); over 4,000 the counter is `warning`, Send disabled, VoiceOver adds "over the limit" (**new**) |
| Sending | `model.sending` | the three groups at 50 % and not interactive; Send busy "Sending…" (§2.6); focus released |
| Sent | `.sent` | replaces the form: a 72 pt circle (1 pt ink 16 % border) with a 24 pt Light checkmark, 22 below the headline 20 Light "Thanks, your report reached RYFT." (demo: "Sent in demo mode: nothing reached RYFT."), 22 below a secondary "Done" pill; content starts 56 below the header; VoiceOver focus goes to the headline; the success haptic stays |
| Queued | `.queued` | same, a `clock` glyph and "Saved. It will be sent as soon as you're back online. You can close the app." |
| Rate limited | `.rateLimited` | a notice above the form: clock glyph, "You've reached today's limit of 10 reports. Your message is kept; try again tomorrow.", the request ID as its caption, text link "Copy message" |
| Refused | `.rejected`, `.saveFailed`, `.signedOut` | the same notice with its sentence ("RYFT couldn't take this report. Copy your message and try again later.", "Couldn't save your report. Copy it and try again later.", "You're signed out, so this report can't be sent. Your message is kept.") |
| From Details, diagnostics off | `context` with the toggle off | the chip drops the request ID (it isn't sent), as today |

- VoiceOver order: header, chip, notice, message (label "Message"), counter, category rows, diagnostics toggle, disclosure, Send. The success
  and failure announcements stay as today. AX3: the chip wraps; the bar's pill is three lines; the message field's minimum height grows with its text.

### 4.4 Devices & sync, Tracker detail, the tracker picker (c-05 … c-07)

**Purpose:** what the user wears, whether its data arrives, and what Apple Health has seen. **First:** the user's trackers, then the one action, Check sync.
- Layout: header "Devices & sync" · 22 · group "Your trackers" with the text action "Edit" on the title's line (hidden while the list is empty): one
  push row per tracker with a glyph circle, the title, and the status as its second line ("Nothing to set up", "Set up in 3 steps", "Set up later")
  · 18 · [only with a tracker] a 15 pt `textSecondary` sentence "See whether your trackers' data arrives in Apple Health." · 12 · the primary pill **Check sync** (arrow.right) ·
  8 · the caption "Last checked 14 min ago" / "Not checked yet" (12 pt `textTertiary`, centred) · 24 · group "Seen in Apple Health" (one non-interactive
  row per source: the source's name, 12 pt kinds, 12 pt "Last data 10:37"; an unknown source adds "Not a tracker RYFT knows. It still counts."), footer
  "Apps and devices that sent data to RYFT in the last 30 days." · group "Apple Health access": a value row "Apple Health" (value: the status; `warning` with a
  word when it needs attention), an action row "Allow access" when RYFT may still ask, a block with "To check what RYFT may read:" and the numbered
  steps from the catalog, a link-out row "Open Health" · a last group with one push row "Sync details" and the second line "For support: requests and streams."
- The check button is the page's one primary action, so it is in flow, not pinned: the page is a list and the button belongs after the thing it checks.

| State | Look |
|---|---|
| None chosen | the group holds the sentence "Tell RYFT what you wear to see how to set up your data." and a primary pill **Choose** below the card (replaces Check sync) |
| Never checked | caption "Not checked yet" |
| Sources loading | the group shows the outline card with "Loading…" |
| Stale | the sources group's footer adds "Showing what RYFT last loaded, 14:05." (**new**) |
| Offline | nothing blocks: Check sync reads Apple Health, not the network |

**Tracker detail** (c-06) is the catalog's card as a page: title = the card title, a 15 pt `textPrimary` sentence (what RYFT can read), group "What reaches RYFT"
(rows: a 17 pt glyph in a 24 column, the signal, the state word; `yes` = `checkmark.circle.fill` `textPrimary` "Arrives", `partial` = `circle.lefthalf.filled`
`textSecondary` "Partly", `no` and `notAvailable` = `minus.circle` `textTertiary`, `unverified` = `questionmark.circle` `textTertiary`; a reason is the second line),
group "Set up" (the numbered steps in one block, then link-out rows for the store and the vendor's guide), groups "Keep it flowing" and "Good to know"
(each one block of paragraphs), and a last row "Show me again later". An integration of `.none` shows the honest limit (a sentence and the vendor's page) and nothing
else; "Just my iPhone" shows "You can add a tracker any time. RYFT will show how to connect it." and a primary pill **Add a tracker** (plus). State is
never colour alone: each state has its own glyph and word, as `CapabilityRow` already does.

**Tracker picker** (c-07, sheet): header "What do you wear?" with Close · the 15 pt sentence · the tiles in two columns (`NeutralSelectableTile`: 56 high, radius 22,
glyph 16 Light, the name, a trailing check circle; selected = `surfaceRaised` fill, 1 pt ink 30 % border, `checkmark.circle.fill`; unselected = `circle` at
35 %) · "Just my iPhone" full width, which clears the others (hint "Clears your other choices", as today) · the footnote · pinned **Done** (checkmark): it saves; Close
leaves the choice as it was.

- VoiceOver: a tracker row is "Apple Watch, Nothing to set up", hint "Opens setup and details"; "Edit" is "Edit trackers"; a tile is "Garmin, selected".
- AX3: "Edit" moves to its own line under the group title; the glyph circles keep 36 pt; tiles go to one column.

### 4.5 Check sync (c-08, c-08b)

**Purpose:** show, signal by signal, whether the last 48 hours reached Apple Health, and the one fix. **First:** the summary sentence (numbers first), then the rows.
- Layout: header "Check sync" · 22 · the 15 pt `textSecondary` line "Looks at the last 48 hours in Apple Health. The check uploads nothing." · one block per tracker, 24 apart: a
  glyph and the name (`.headline`), 8 below the summary (`.callout` `textPrimary`, from `TrackerCheckText.summary`), 12 below a rows card: `CheckRow`s 46 high (a 17 pt glyph in a 24 column,
  the signal, the result in `textSecondary`), "That's normal." (12 pt `textSecondary`) once under the first expected gap, and under the last unexpected gap the **fix panel**: a
  `surfaceRaised` block (radius 16, inset 8) with the lead sentence, the numbered steps; then, below the card, a group of link-out rows ("Garmin Connect in the App Store",
  "Open Health"). Pinned: **Check again** (arrow.clockwise).
- Row kinds (symbol · tint): waiting `circle` `textTertiary` · checking `circle.dotted` `textSecondary`, pulsing (static under Reduce Motion) · **ok `checkmark.circle.fill` `textPrimary`
  (was teal)** · expected `minus.circle` `textTertiary` · neutral `circle.dashed` `textTertiary` · late `clock` `textSecondary` · fix `exclamationmark.circle` `warning`. The result is always a word.

| Phase | Look |
|---|---|
| Not asked | a notice (lock glyph) "RYFT hasn't asked for Health access yet." and the pinned pill becomes **Allow access** (the page's one primary) |
| Unavailable / locked / failed | a notice with its sentence ("Apple Health isn't available on this device.", "Unlock your iPhone to check: Apple Health can't be read while it's locked.", "Apple Health couldn't be read this time. Tap Check again."); the pill stays (disabled when unavailable) |
| Running | rows resolve one by one (not staggered under Reduce Motion); the pill is busy "Checking…" |
| Done | the summary and rows as above; one VoiceOver announcement of the result (as today); the pill is "Check again" |
| Silent tracker | a notice-like block: a `tray` glyph, the sentence, link-out rows, a disclosure row "Show details" |
| Can't read / unidentified / other | the sentence only; "Other" lists "From apps RYFT doesn't know yet:" with its rows |
| Permission card | a notice with the lock glyph, the explanation, the steps, a link-out row "Open Health" |
| Embedded (onboarding's tracker step, area A) | the same blocks without the header and the pinned bar; "Check again" is the secondary pill, because Done is the step's primary |

- VoiceOver: each tracker block is a container named for the tracker; each row says its name then its result; the done announcement is unchanged. AX3: results go under the names.

### 4.6 Sync details (c-09, c-09b)

**Purpose:** for support, what the sync engine knows. Numbers first, no decoration. **First:** the Engine group.
- Layout: header "Sync details" · groups, in order: "Engine" (value rows State, Scoring (second line "Taking longer than usual" when slow), Queue, Backlog, Uploaded, "Deletions kept"
  only if any; the last error as selectable monospaced 12 pt `warning` text) · "Loaded data" (a row per resource: name, load time as its value, status as its second
  line; a failing resource's line is `textSecondary`, a warning one `warning`; the times refresh every 30 s as today) · "Streams" (name, count as its value, "Newest 10:40" and
  "Last page 10:41 · 500 records" as lines) · "Last requests" (one card of monospaced lines: 12 pt path, 11 pt `textTertiary` request ID and time; a non-2xx line is `warning`;
  "No requests since launch." when empty) · a last group with the actions: action rows "Sync last 3 days again" and "Copy diagnostics", a destructive row "Full resync";
  footer "Counts, dates and request IDs for support; no health data.".
- Monospace (SF Mono) is allowed here and in Developer only: paths and IDs need fixed width.
- States: loading the queue: the Engine values read "–" (no spinner); actions disabled (35 %) while `!canSync`; "Copy diagnostics" becomes "Copied" with a checkmark glyph for 2 s, and VoiceOver
  announces "Copied"; a resync tap opens the dialog (§4.16). As a sheet (Today's status line) the header has Close in place of "Done".
- VoiceOver: a "Loaded data" row is one element with `row.spoken(now:)` as today; request lines are one element each. AX3: values go under names; monospaced lines wrap.

### 4.7 Notifications (c-10, c-10b, c-10c)

**Purpose:** choose what RYFT may tell the user, and when not to. **First:** the categories.
- `push.enabled` on: group "Notify me about": four toggle rows (title, second line: the sentence); group "Quiet hours": a toggle row "Pause at night" (second line) and, only while on, value
  rows "From" and "Until" with the system compact time picker in the trailing slot (tinted `textPrimary`); footer "Times are local. Equal times turn quiet hours off; a start later than the end spans midnight.".
  A switch is disabled (35 %) while its request is in flight; if it fails the switch returns to its value and a notice says so.
- Permission: **not asked** → a notice "RYFT hasn't asked to send notifications yet." and the pinned primary **Allow notifications** (bell); **off in iOS** → a notice with a `bell.slash` glyph
  "Notifications are off in iOS Settings" and caption "Your choices below are kept for when you turn notifications back on.", the groups stay live, and the pinned pill is **Open Settings**
  (arrow.up.right).
- **Rolling out** (`push.enabled` off): no switches ("no switches that look on while nothing can be sent"): a notice "Notifications are being rolled out" (a `bell` glyph) with the caption "We'll let you know here
  when notifications reach your account.", then a group "You'll get" with the four categories as non-interactive rows (title and sentence).
- VoiceOver: a toggle row reads "Morning score, on", hint is the sentence; the rollout rows read title then sentence. AX3: switch stays trailing, text wraps; time pickers go under their titles.

### 4.8 Journal settings and Add a behavior (c-11, c-11b)

**Purpose:** choose which behaviors the Journal asks about. **First:** the groups by category.
- Layout: header "Journal" with a trailing `CircleButton` "Add a behavior" (plus) · one group per category (title: the category), each row a toggle row (title; second line: the answer kind, "Yes or no" / "How many" / "What time") · a
  group "Custom" holds the user's own behaviors: a toggle row with a trailing trash button (44 pt target, glyph 14 pt at 55 %) before the switch; footer "Your own behaviors can be deleted. The built-in ones can only be turned off." (**new**).
- Swipe-to-delete is dropped: it needs `List`, which cannot take the 22 pt card. The trash button opens a confirmation dialog (§4.16) (D6C-9).
- States: loading → one outline card "Loading…"; empty → the sentence "No behaviors yet." (**new**) and the header's plus; error → a notice at the top (a calm sentence and the request ID in its caption; the page shows `error.localizedDescription` today, which the developer replaces with the
  app's failure text as Sleep does); a toggle in flight is disabled.
- **Add a behavior** (sheet): header with Close; group "Name" (a field card; footer "Up to 60 characters."); group "German name (optional)" (a field card; see Q3); group "Answer": three select rows; group "Category": select rows; a notice for a failure; pinned **Add** (plus), disabled until the name is 1–60 characters, busy "Adding…".
- VoiceOver: the trash button is "Delete Evening walk"; select rows carry `selected`; the header's plus is "Add a behavior". AX3: the trash button stays 44 pt, the switch drops under the title.

### 4.9 Sign-in methods and Licences (c-12, c-12b, c-13)

**Sign-in methods.** Purpose: how this account can be opened. First: the list of methods.
- Layout: header "Sign-in methods" · 22 · the 15 pt `textSecondary` line "You can sign in to this account with:" · a group of rows with a glyph circle (`envelope`, `apple.logo`), the
  title ("Email and password", "Apple ID") and the address as its second line (middle-truncated, the one place text may truncate: an address; VoiceOver reads it whole) · without an Apple link: the sentence "Add Sign in with Apple to open this account with your Apple ID too. Your data stays in this account." and the **system `SignInWithAppleButton(.continue)`**, style `.white`, **52 high, radius 26**
  (was 50 and a capsule): it is the light pill of this page, the page's one action; disabled at 35 % while `auth.isWorking`; a failure shows a notice.
- Loading: the session's own provider shows at once as one row (as today), the rest arrive; nothing else changes. Linked: both rows, no button.
- VoiceOver: a row is "Email and password, alex@example.com"; the button is Apple's. AX3: the button grows with its text; addresses wrap rather than truncate.

**Licences.** Purpose: the open-source notices. The legal wording is unchanged and so are the rows' names, licences and holders.
- Layout: header "Licences" · 22 · one group of link-out rows: the package or typeface name (15 pt), "MIT · Supabase" as the second line, ↗. No group title (a title is new wording).
- VoiceOver: "supabase-swift, MIT, Supabase", hint "Opens the licence in Safari". AX3: rows wrap.

### 4.10 Account, Privacy, Data, Training (c-14 … c-17)

**Account.** Purpose: who is signed in and the two things that change it. First: the identity.
- Layout: header "Account" · 22 · a group: a row with the name (15 pt) and the address (12 pt, middle-truncated), the sign-in method as an outline capsule trailing (1 pt ink 16 %, 12 pt `textSecondary`: "Email", "Apple") · value row "Timezone" with its detail line (`timezoneDetail`) · push row "Sign-in methods" ·
  push row "Change password" (only when `canChangePassword`; it opens `SetNewPasswordView(mode: .change)`, area A's page, as a sheet) · 18 · a group with the destructive row **Delete account** and the footer "Deleting your account removes everything RYFT stores for you. Apple Health on this iPhone isn't touched." (**new**: a shorter form of the dialog's message).
- Log out is Profile's pill (PR 5); if the list does not carry it, add the secondary pill **Log out** under this page's groups (busy "Sending…" while "Send first" runs, as `busy: sendsFirst` today).
- States: signed out or demo: the group holds a value row "Signed in: No" and the sentence "Turn off Demo data to log in or create an account."; an account error: a notice with its request ID; deleting: the destructive row shows "Deleting…" with the ellipsis and the page is not interactive.
- VoiceOver: the identity row is one element "Alex Doe, alex@example.com, signed in with email". AX3: the capsule goes under the address.

**Privacy.** First: whether consent is current.
- Layout: header "Privacy" · 22 · group "Health-data consent": value row "Consent" (value from `consentText`: "Given 12 Nov 2026"; when not current the value is `warning` and reads "Needs review"), link-out row "Privacy Policy", destructive row **Withdraw consent** (only while current); the footer is `consentDetail`. Not current: the pinned primary **Review and agree**.
- Busy: "Withdrawing…" on the row; an error: a notice. Withdraw opens the dialog in §4.16.

**Data.** First: whether Apple Health is connected, then the last sync.
- Layout: header "Data" · groups: "Apple Health" (value row "Access" with the status (`warning` plus a word when it needs attention), an action row "Allow access" when RYFT may still ask, a link-out row "Open Health", a toggle row "Save strength workouts to Apple Health" with its two-line sentence; a notice for `HealthWriteAccessHint`; the footer is the catalog path (with `devices.setup`)
  or today's Garmin sentence (without)) · "Sync" (value rows "Last sync", "Device ID" (tabular, long-press copies it), a progress row while syncing (the progress text, a static `ellipsis` pulse, never a spinner), a notice for retrying or failed (`syncNotice`, with Details), the action row **Sync now** (busy "Syncing…"), a push row "Sync details", the destructive row **Full re-sync**; all disabled at 35 % while `!canSync`)
  · "Import and export" (a push row "Import training data" with the resume detail as its second line, only with `train.import`; the waiting-file row; the action row "Clear remembered matches" (eraser) with its sentence, only when matches exist; the action row "Export my data" (busy "Preparing…") when Profile's pill is absent, with `exportError` as a notice) · "Demo" (a toggle row "Demo data", footer "Show a realistic sample history instead of your server.").
- VoiceOver: status rows say the status in words; the busy rows say "Syncing, busy". AX3: values go under titles.

**Training.** Header "Training" · group "Workouts": a toggle row "Advance to the next exercise" (second line "Jumps to the next set when you finish an exercise.") · group "Session layout": two select rows "Focused" and "List" (the segmented control goes: two options with a footer read better as rows), footer "Focused: one exercise at a time. List: all exercises on one screen. Applies the next time you open a workout.". The group shows only with `showsSessionLayout`.

### 4.11 The editors: Baseline sleep need and Maximum heart rate (c-19, c-19b, c-19x, c-20)

**Purpose:** set one number and see where it sits. **First:** the number, then the ruler that shows the range.
- The editor is a sheet from Profile (`showsClose`) or a pushed page inside the Sleep-need sheet (Back).
- Layout: header with the title and Close (or Back) · 22 · a row, centred: a `CircleButton` "Less" (minus), 18, the numeral, 18, a `CircleButton` "More" (plus). Baseline: `DotNumeral("7:45")`, glyph gap 7, minimum width 130,
  placeholder "0:00". Maximum heart rate: `DotNumeral("190")` and under it "bpm" in 13 pt `textSecondary` · 8 below the source line (13 pt `textSecondary`: "Set by you · learned 7:52",
  "Estimated from your age (born 1990)", "Default · add your birth year for an estimate": the existing `…SourceText`) · 14 · a `RulerScale`: baseline 4–12 h with **33 ticks** (one per 15-minute step, so the needle lands on a tick), labels "4 h · 8 h · 12 h"; heart rate 100–230 with **27 ticks** (5 bpm), labels "100 bpm · 165 · 230 bpm"; no zone; the needle (Volt) is the draft value ·
  24 · the explanation as a 15 pt `textSecondary` paragraph (today's sentence) · [an action row "Use RYFT's estimate" / "Use the default" / "Use the estimate" with the learned value as its value, only when `canUseLearnedBase` / `canUseMaxHREstimate`] · pinned **Save** (checkmark).
- The numeral and the two buttons are **one adjustable element** (as `SettingStepper` is today): "Baseline sleep need, 7 hours 45 minutes", swipe up and down moves 15 minutes (1 bpm). The buttons are also tappable but hidden from VoiceOver; the ruler is hidden from VoiceOver (it repeats the value).
  Pressing the numeral's buttons animates the needle 250 ms (none under Reduce Motion).

| State | Look |
|---|---|
| Unchanged | Save disabled (35 %) |
| Changed | Save enabled |
| Saving | Save busy "Saving…"; the buttons disabled |
| Refused | a notice above the paragraph with `editor.error` and its request ID |
| Saved | the pill disabled again; a notice with a checkmark glyph "Saved. Past days keep their scores until you rescore them."; a group with the action row **Rescore the last 90 days** (busy "Rescoring…"); the result as a notice ("failed" carries its request ID) |
| Account not loaded | the numeral reads the default, Save is disabled, the source line is empty |

- AX3: the numeral is Light at 52 scaled (c-19x); the minus and plus stay 44 pt and sit on either side of it, or under it when they would not fit (then the row stacks: numeral, then the two buttons side by side).

### 4.12 Sleep need: the card and the sheet (c-18, c-18b, c-18c)

**Sleep Day's need card** (below the board, today the old blue, yellow and grey bar) becomes one push row in a group, *Sleep need 8:18 ›*, with the sentence as the group's footer ("You needed 8:18: 7:30 baseline, +0:20 for yesterday's strain, +0:28 of debt."). Hint: "Shows how your sleep need adds up, and your baseline to change". The Details card's "Sleep need" row for nights without a breakdown stays a row. (This is the only change to a Sleep Day card; the stages and details cards below the board are Sleep Day's, not mine, see Q4.)

**Sleep need sheet.** Purpose: why last night's need was what it was. **First:** the total as a numeral, then the terms that add up to it.
- Layout: sheet header "Sleep need" with Close · 22 · "Last night · Sun, Nov 15" (13 pt `textSecondary`) · 14 · `DotNumeral("8:18")`, glyph gap 7, centred, with "needed for this night" (13 pt `textSecondary`) 10 below · 20 · **one glow tile** (`GlowTile(Theme.metricSleep, kind: .hypnogram)`, 168 min, radius 28, padding 14 16): a head row "How it adds up" (13 pt label) and the total (12 pt); 14 below, `TickRow`s 9 apart, all on one scale (`scaleMax` = the total): "Baseline 7:30", "Strain +0:20", "Sleep debt +0:28", and "Nap credit −0:25" (a real minus) only when there is a credit. The terms are in ink (not blue, amber and grey: one tile, one colour, the legend; the labels carry the meaning).
  18 below: the sentence (`SleepNeedBreakdown.sentence`, 15 pt `textPrimary`), then the paragraph "Your baseline is yours to set. The top-ups follow yesterday's strain and your sleep debt; a nap lowers the next night's need." (15 pt `textSecondary`), then a group with the push row "Baseline sleep need" (value 7:30, second line the source) which pushes the editor (§4.11) inside the sheet.
- No breakdown (a night scored before it existed): the numeral shows `total`, the tile is replaced by a notice "This night was scored before RYFT broke the need down.", the rest stays.
- The tick block follows PR 5's one-column rule: if a label is wider than 74 pt (German is out, English "Sleep debt" and "Nap credit" fit) all rows stack together.
- VoiceOver: the numeral "Sleep need, 8 hours 18 minutes"; the tile is a container; each row one element ("Strain, plus 20 minutes"); then the sentence, the paragraph, the row. AX3: the numeral Light 52; rows stack label over ticks over value; the tile grows.

### 4.13 Bedtime & wake and Tonight (c-21, c-21b, c-22, c-22b, c-22c)

**Bedtime & wake** (a pushed page, from Profile and from Tonight). Purpose: when to wake, how much of the need to aim for, and the nudges. **First:** the wake times.
- Layout: header "Bedtime & wake" (Back) · groups: "Wake up at" (a toggle row "Same time on weekdays"; then value rows "Weekdays", "Weekend", or seven day rows from the calendar's names, each with the **system compact time picker** in its trailing slot, tinted `textPrimary`;
  verified in c-21: it draws as the system's grey capsule with the time in `label`, which is neutral) · "Aim for" (three select rows "Peak", "Perform", "Get by", the second line "100 % of your need", "85 %", "70 %"; the check is `textPrimary`) · "Wind down" (one row: the title "Remind me before bedtime" and the PR 5 segmented control 15 / 30 / 45 / 60 min; at AX1 a menu row) ·
  "Bedtime reminder" (a toggle row, second line "A notification 30 min before tonight's bedtime. It moves with your day.") · "Wake-up alarm" (a toggle row; second line is the real-alarm sentence or "A notification at your wake time. It won't ring like an alarm on this iOS version."; when iOS refused, an amber row "Not allowed in iOS Settings." with the trailing link "Open Settings ↗" and a VoiceOver announcement, as today; `alarmProblem` shows as an amber row) · a last group with the destructive row **Turn off Bedtime & wake** and the footer **new** "Changes save as you make them.".
- Saving is as today (400 ms after the last change, and on leaving). Under Reduce Motion the seven-day list opens without animation.
- VoiceOver: a goal row is "Peak, 100 percent of your need, selected"; a time row is "Weekdays, 6:30 AM" with the picker's own action. AX3: pickers go under their titles; the segmented control becomes a menu row.

**Tonight** (the card, in Sleep's Bedtime mode; its placement belongs to PR 5's Sleep spec, its content to this one). **First:** the time to be in bed, as a dot numeral.
- Set: one glow tile (`GlowTile(Theme.metricSleep, kind: .hypnogram, minHeight: 218)`): a head row "Tonight" and "As of 17:42" (12 pt) · 14 · "In bed by" (13 pt) · 8 · `DotNumeral("22:41")`, glyph gap 7, placeholder "00:00" · 10 · "for 100 % · wake 06:30 · need 8:18" (13 pt) · 16 · three goal rows 8 apart: a 6 pt dot (filled = the user's goal, outlined = the others), "Peak · 100 %" (label), the time (`.callout`, full ink). Below the tile, 18: a group with a disclosure row "Why this need" (it opens `NeedBasisRows` as value rows in the card: Baseline, Today's strain so far, Sleep debt, Nap credit, Tonight's need) and a push row "Bedtime & wake" with the schedule's summary as its value; an amber notice above the group when `alarmProblem`.
- Not set up: an outline card (radius 28, 1 pt `separator`) with "Tonight", the sentence "Tell RYFT when you want to wake up. It tells you when to go to bed, with what today's strain and your sleep debt add." and a primary pill **Set up Bedtime & wake** (bed.double).
- Loading: the same outline card with the unlit numeral grid and "Planning tonight…" (**new**); no spinner. Error: a notice with "Try again" (`planner.error`).
- VoiceOver: the tile is a container: "Tonight. In bed by 22:41, for 100 percent of your need. Wake 6:30, need 8 hours 18 minutes. As of 17:42." then the goal rows ("Peak, 100 percent, 22:41, your goal"; the dot is hidden). Reduce Transparency: the tile is flat. AX3: the numeral is Light 52; goal rows stack label over time.

### 4.14 Import training data, steps 1 to 6 (c-23, c-23b, c-23c, c-23d)

The flow stays a full-screen cover with one pushed screen per step; its frame becomes the subpage frame.
- **Frame.** Header = the step's title (26 Light): "Import training data", "Detected", "What to import", "Match exercises", "Preview", "Import". Step 1: Close (xmark) trailing; steps 2 to 5: Back and a trailing Close that asks first (the "Discard this import?" dialog); step 6: Close only. Under the header, 20 below, the **step rule**
  (§3 row 5): six 3 pt capsules 4 apart, done ink 55 %, current ink 100 %, upcoming ink 16 %, and "Step 3 of 6" (12 pt `textTertiary`) 6 below; 20 below that the content. Content max 560. The pinned bar holds the step's one primary pill and, above it, the caption that says why it is disabled (`ImportBarCaption`).
  Swipe-down is off from step 2, as today.
- **Step 1 Choose files** (c-23): the headline "Import a plan and your workout history" at `.headline`, the paragraph (today's text, 15 pt `textSecondary`), two outline slots (radius 22, 1 pt `separator`, 64 high: a glyph, "Plans file" / "Workouts file", "Optional"); problems after them as notices (one each: not a CSV, too large, unreadable, empty, too many); a file being read shows a 2 pt hairline track in its slot (never a spinner). Pinned: **Choose files** (plus), footnote "Save the files from the other app to Files, then choose them here.".
- **Step 2 Detected** (c-23b): a summary tile (`surface`, radius 22, padding 16): the source "Alpha Progression export" (13 pt `textTertiary`) with a checkmark, "1 plan · 2 days · 12 exercises" at `.metric` (26 Light), "10 workouts · 2 Mar – 27 Apr 2026" at 15 pt `textSecondary` · notices for D1–D5 (no plan, no workouts, different apps, partly recognised, unsupported: each with its one text link) · group "Files" (glyph-circle rows; a remove button 44 pt; "Add another file" as an action row) · pinned **Continue**, or **Choose another file** when nothing is importable.
- **Step 3 What to import**: a group "Plan" (a toggle row with the plan's name and its weeks and days as the second line; when on and the plan already exists, the notice "Already in RYFT" and the action row "Replace with the file's version"; "Make this my active plan" as a toggle row and, when on, the choice rows "No plan" / "Active plan"; the sentence about what it replaces as the footer) and a group "Workout history" (a toggle row with the counts; value rows for the date range with compact date pickers; footer "Imported workouts count towards strain on their days. Past strain can change once."). Pinned **Continue**, disabled with the caption "Turn on at least one to continue." or "Widen the range or turn history off.".
- **Step 4 Match exercises** (c-23c): the count line (15 pt `textPrimary`: "12 matched · 2 to check · 1 new"), the PR 5 segmented control "All | Needs a check (2)", a text link "Accept 3 likely matches", then groups "Needs your attention" and "Matched": one row per exercise (the file's name, the equipment in `textSecondary`; the second line "→ Barbell bench press"; trailing: a word, "Likely" and "Check" in `warning`, "New" in `textSecondary`, a checkmark for matched, "Skipped" in `textTertiary`). A row opens a confirmation dialog with "Use “X”", "Choose another exercise…", "Create a custom exercise…", "Skip this exercise" (destructive), and each action is a VoiceOver custom action too (as today). The bodyweight question stays inline (select rows). Search is the system search field. Pinned **Continue** with "2 left to check." above it.
- **Step 5 Preview**: a field card "Plan name"; one group per plan day (rows: exercise, sets); one group per month with a session row each (a push into the session-detail sheet); the notes as footers (`ImportNoteLine` becomes a footer line with its 12 pt glyph); a notice for duplicates with the text link "Review" / "Show all"; the sentence about strain; pinned **Import 10 workouts and 1 plan** (the count title, `ImportPreviewSummary`), or "Keep on this iPhone" (V5), or "Done" (nothing to import).
- **Step 6 Import** (c-23d): a lead line (a 44 pt circle with a checkmark and "Done" at 20 Light; the other jobs say "Getting ready", "Importing…", "Some items weren't imported", "Saved on this iPhone") · the determinate progress (`ImportProgressBar`: 3 pt, track ink 16 %, fill `textPrimary`, no teal; "10 of 12 workouts"; "Plan: done") · value rows for what happened ("Workouts imported 10", "Plans imported 1", "Already in RYFT: 2 left as they were", "Sets skipped 3" with its reason as the second line) · disclosure rows for "Not imported (n)" and the skipped duplicates (the text link "Import these too") · the notices I1–I9 as today (offline, paused with a countdown, signed out, not enabled, needs an answer) · pinned: one primary (**Open history**, **Open plan**, **Retry 3**) and at most one secondary. Close only; the import continues in the background as today.
- **Import unavailable** (the "Open in" sheet when `train.import` is off): a medium sheet with a `doc.text` glyph (28 pt `textSecondary`), the headline "Importing isn't available on this account yet", the sentence, and a primary **OK** pill (checkmark).
- VoiceOver: the step rule reads "Step 4 of 6"; each step's header is the page title; the done announcement stays. AX3: slots and rows stack their glyph above the text; the pinned bar's pill wraps.

### 4.15 The widget (c-24 … c-27)

D6: the widget follows the app: the same tokens, dark only, the shared v3 orbit. What exists: the **Readiness** widget (`systemSmall`, `accessoryCircular`, `accessoryRectangular`, `accessoryInline`), two Live Activities (**Rest timer**, **Wake-alarm snooze**), and the **Start workout** control. The orbit is already `Shared/OrbitGaugeDrawing` (the app's own drawing); what is not Nocturne is the text around it: the system's rounded face in
semibold, teal on things that are not recovery, and a 16 pt content margin that makes the orbit smaller than it needs to be.

**Tokens in the widget.** `Brand` (hex literals that `check-shared-types.py` compares with the app's colorsets): `graphite` = background, `mist` = `textPrimary`. The neutral ladder is `mist` at fixed opacities, named in `Brand` (`inkSecondary` 0.62, `inkTertiary` 0.48, `inkTrack` 0.16). **`Brand.teal` is removed** from every non-orbit use (the orbit takes its colours from the shared palette, not from `Brand`). **Type:** the system face in its default design (not rounded), numbers **Light** from 20 pt up, Regular below, tabular digits; labels Regular, the "Open" pill Medium. (Satoshi is not in the extension; Q1.) The widget never shows the dot grid: at a 104 pt dial the dots would be 2.4 pt, so the centre is a Light number, the same rule the app applies at AX1 (D6C-8).

| Family | Spec (as drawn in the renders) |
|---|---|
| **Small** (158 × 158 and the larger iPhones' 170) | `contentMarginsDisabled()` and a 12 pt inset: the orbit's dial **104** (was about 94 under the system's 16 pt margin), its frame 116, centred; 4 below it one 11 pt caption. The caption: "Readiness · High" in `inkSecondary` (**new**; it was the bare band word); from 17:00 until bedtime "Bed by 22:41" in 11 pt Medium `textPrimary` (was teal); calibrating "Baselines 3 of 7"; pending "Scoring your night…" (the previous day's orbit dimmed, as today); waiting "Waiting for last night" (tracks and hollow dots, no number). The centre number: Light, `OrbitGaugeGeometry.numberPointSize(forDial:)`, `textPrimary` (a dimmed `inkTertiary` for a previous day's number and the dash). |
| Small, no snapshot | not an empty tile: a `circle.dashed` glyph (30 pt Ultralight, `inkSecondary`) with "Open RYFT to see your readiness." (12 pt, `inkSecondary`): an outline, not a blank |
| **Circular** (lock screen) | the orbit fills the 76 pt circle (dial 62); the centre number Medium (a Light stroke vanishes in the system's vibrant rendering), in `.primary`; calibrating shows the count, pending the previous number dimmed, no orbit shows `circle.dashed` |
| **Rectangular** | the orbit at dial 44 without a number, 10 pt gap, then: "Readiness" 13 pt Medium (still `widgetAccentable`), the value 22 pt Light, the band or status 11 pt, and the bedtime line 11 pt; at most three lines under "Readiness" (the status wraps before it truncates; with a bedtime the status line is one line) |
| **Inline** | "Readiness 71 · High" or "Bed by 22:41" (text only, unchanged) |
| Locked device | unchanged (the `.privacy` redaction): tracks only, the constant "00", the single word "Readiness" for VoiceOver and inline |
| Tinted and clear home screens | unchanged: the marks are `widgetAccentable`, the tracks one flat white at 25 % |
| **Rest timer**, lock screen banner | `Brand.graphite` background; the label ("Rest" or "Workout", 11 pt Medium) and the session title (12 pt) in `inkSecondary`, **no teal**; the clock 40 pt **Light**, tabular, `textPrimary`; while resting a 4 pt progress rail (`ProgressView(timerInterval:)`, tint `textPrimary`); "Next: …" 14 pt `textPrimary`, one line (`privacySensitive`); the **Open** action is a compact light pill (32 high: `textPrimary` fill, `graphite` 14 pt Medium text), the widget's counterpart of `PillButton(.primary)` (D6C-10) |
| Rest timer, Dynamic Island | expanded: leading a `timer` glyph and "Rest" in `inkSecondary` (no teal), trailing the clock 28 Light, bottom the rail, the next line and the Open pill; compact: the glyph in `inkSecondary` and the clock 15 Regular; minimal: the glyph; **`keylineTint`: `Brand.mist` at 50 %** (was teal) |
| **Wake-alarm snooze** | the same: "Snoozing" in `inkSecondary`, "Your alarm rings again" 12 pt, the countdown 40 Light; island: `zzz` glyphs in `inkSecondary`, no teal; the keyline as above |
| **Start workout** control | no change (the system draws it; `Label("Workout", systemImage: "dumbbell.fill")` takes the system tint) |

- **Accessibility:** no change to what is spoken (`Words.spoken`); the new caption is decoration under the element's own label. Dynamic Type: the caption (11 pt, `.caption2`) scales and may take two lines (`lineLimit(2)`, `minimumScaleFactor(0.8)`); the orbit stays square and shrinks to leave room (it is a `GeometryReader` today).
- **Shared types (`check-shared-types.py`).** Nothing in `Shared/` changes in this area. One coupling for T5.0: `OrbitGaugePalette.assets` names the colorset **`Accent`** for both `recovery` and `calibration`. If T5.0 re-points `Accent` to a neutral, the orbit's recovery arc turns neutral too. T5.0 must either leave `Accent` teal for the orbit or add a `Recovery` colorset to both catalogs (the script compares their `Contents.json`) and point the palette at it in the same PR. The widget's `Brand.teal` is deleted in T6C.6 (the script requires each `Brand` literal to have an app colorset of its name; a removed one needs none).
- **Previews:** the existing `#Preview`s (Small, Lock screen, Circular, Inline, Families, Locked, Rest timer, Dynamic Island, Compact) stay and are dark only; `ReadinessWidgetGallery` shows the new caption. Strings go in the widget's own catalog (English only).

### 4.16 System dialogs and sheets the app controls

The dialogs are drawn by iOS (dark, because the app is dark-only). What the app controls is the title, the message, the buttons, and their roles; their wording stays unless a row says so. After T5.0 the root `.tint` is `textPrimary`, so a default button reads light, not teal.

| Dialog | Where | Title | Buttons (role) | Change |
|---|---|---|---|---|
| Re-upload 90 days | Data; Sync details | "Re-upload the last 90 days of Health data?" | "Re-sync" (destructive) · Cancel (system) | none |
| Log out | Profile pill | "Log out of RYFT?" (message: with or without unsent items, offline or not) | "Send first" (default, only when it can send) · "Log out anyway" or "Log out" (destructive) · Cancel | none |
| Delete account | Account | "Delete your RYFT account?" | "Delete account" (destructive) · "Cancel" (cancel), an alert | none |
| Withdraw consent | Privacy | "Withdraw your consent?" | "Withdraw consent" (destructive) · "Export my data first" (default, only when it can export) · "Delete account instead" (destructive) · Cancel | none |
| Clear matches | Data | "Clear remembered matches?" | "Clear" (destructive) · "Cancel" (cancel), an alert | none |
| Discard import | Import steps 2–5 | "Discard this import?" | "Discard" (destructive) · "Keep going" (cancel), an alert | none |
| Discard saved import | Import step 6 | "Discard the saved import?" | "Discard" (destructive) · "Cancel" (cancel), an alert | none |
| Replace import | a file arrives mid-import | "Replace the import you're setting up?" | "Replace" · "Keep current" (cancel), an alert | none |
| Delete a behavior | Journal | **new** "Delete “Evening walk”?" with the message "This removes the behavior from your Journal." | "Delete" (destructive) · Cancel | new, D6C-9 |
| Match actions | Import step 4 | none (the row's name) | "Use “X”" · "Choose another exercise…" · "Create a custom exercise…" · "Skip this exercise" (destructive) · Cancel | none |

System surfaces with nothing to design: the **share sheet** for Export (title and file name from the app: unchanged; detents medium and large), the **Safari sheet** for legal pages and the store pages (set the bar tint to `background` and the control tint to `textPrimary` in `SafariView`), the file picker, the compact time pickers' popovers, Sign in with Apple's sheet, the HealthKit permission sheet. None of them is teal once the root tint is neutral.

---

## 5. Strings (English only; localization-editor finalises)

Targeted edits to `Ryft/Resources/Localizable.xcstrings` and `RyftWidgets/Localizable.xcstrings`, with a `--stat` check. Legal pages' wording is unchanged. Everything not in the table keeps its key.

| Key (English) | Where | Note |
|---|---|---|
| Larger text sizes always use thin digits. | Display footer, AX1 and up only | new |
| Preview of the hero numbers. Readiness 84 of 100. | Display preview, VoiceOver | new; the numbers come from the sample value |
| Over the limit | Report counter, VoiceOver | new |
| Showing what RYFT last loaded, %@. | Devices & sync footer when stale | new; the time as a placeholder |
| Syncing… · Saving… · Rescoring… · Adding… · Preparing… · Withdrawing… · Deleting… | busy titles (§2.6) | "Sending…" and "Checking…" exist |
| Your own behaviors can be deleted. The built-in ones can only be turned off. | Journal footer | new |
| No behaviors yet. | Journal empty | new |
| Delete “%@”? · This removes the behavior from your Journal. · Delete | Journal dialog | new; "Delete" may exist |
| Delete %@ | trash button, VoiceOver | new |
| Changes save as you make them. | Bedtime & wake footer | new |
| Planning tonight… | Tonight, loading | new |
| Your goal | Tonight goal row, VoiceOver | new |
| needed for this night | Sleep need numeral caption | new |
| How it adds up | Sleep need tile head | new |
| Deleting your account removes everything RYFT stores for you. Apple Health on this iPhone isn't touched. | Account footer | new; shorter than the dialog's message |
| Readiness · %@ | widget caption | new, in the widget catalog (the app has the same text on Today) |
| Back · Close · Less · More | icon-button labels | exist in part; the editor's Less and More are new |

## 6. Tests to write

Swift Testing, `RyftTests/`; the hosted window (`HostedWindow`) for anything about frames, order and traits. Dark, English, default size and AX3.

1. **Row and group geometry (hosted):** a row is ≥ 46 high; a group card's radius 22; hairlines inset 16; groups 18 apart; the first row has no hairline above it.
2. **Switch:** on and off colours and contrast (track 16:1, border 3.0:1, knob 5.6:1) computed from the tokens; the `Toggle` keeps its binding; VoiceOver reads "on" and "off" and the switch trait.
3. **Subpage frame (hosted):** the header is 40 high, the title has the header trait, Back is 44; at AX3 the title is a second row; **the back swipe still pops** with the bar hidden; the pinned bar does not cover the last row at AX3.
4. **Select rows:** exactly one `selected` trait per group (Category, Answer, Goal, Hero numbers, Layout).
5. **Report:** Send disabled with no message and over 4,000; busy title and not interactive while sending; focus on the outcome headline after sent and queued; each refusal shows its notice and keeps the message.
6. **Devices & sync:** with no tracker the pill is "Choose", with one it is "Check sync"; "Edit" hidden while empty; stale footer shows the time.
7. **Check sync:** every `CheckRow.Kind` has a distinct symbol and a word; `ok` is `textPrimary` (a token test: no teal on the page); the pinned pill is "Allow access" while not asked.
8. **Sync details:** "Copied" for 2 s and the announcement; actions disabled while `!canSync`; the mono lines wrap at AX3.
9. **Notifications:** the four modes (allowed, not asked, off in iOS, rolling out) show the right groups and the right pinned pill; switches disabled in flight; the choices stay live when off in iOS.
10. **Journal:** the trash button exists only on custom behaviors; the dialog names the behavior; Add is disabled outside 1–60 characters.
11. **Editors:** the numeral is one adjustable element (increment and decrement move 15 min, or 1 bpm; clamped 4–12 h and 100–230 bpm); the ruler's tick count is 33 and 27 and the needle lands on a tick; Save disabled until changed; the saved state shows the rescore row.
12. **Sleep need:** the tick rows' minutes and `scaleMax`; the nap row only with a credit; the sentence equals `SleepNeedBreakdown.sentence`; no-breakdown shows the notice and no tile; the tile's text contrast (the PR 2 glow test, with a sleep tile at 350 × 168 and AX3).
13. **Bedtime & wake and Tonight:** the goal select row; the toggles' refusal row and its announcement; "Turn off" is destructive; Tonight's four states; the numeral falls back to Light at AX1.
14. **Import:** the step rule's segment states; each step's title; Close and Back by step; the pinned pill's title per state; the unavailable sheet.
15. **Colour audit (token test):** no view in these folders names `Theme.accent`, `Theme.onAccent` or `TealButtonStyle` (a grep-style test over the source files, so a regression is caught); Volt appears only in the editors' ruler.
16. **Widget:** a unit test over `Words` (the new caption and bedtime line); `check-shared-types.py` stays green; the pure layout of the small family (dial 104, frame 116) as constants; a hosted render of each family at default and AX3 text sizes with no clipped caption.
17. **A11y sweep (hosted, AX3):** no element frame leaves 0…390; every icon-only button has a label; reading order equals visual order on each page.
18. **Existing tests to update:** `HeroNumeralsTests` (the row becomes two select rows), the tests that pin `PrimaryButton`'s look on these pages, and any that read the old `ProfileSection` text; each is listed in the PR.

## 7. Files and the split

All work is on a branch of `main` after PR 5's accent change (T5.0) has landed, because the grammar needs the accent decision. **`ProfileView.swift` is 2,772 lines and PR 5 rewrites its top; the first ticket here is therefore a pure move** so the two PRs do not collide.

| Ticket | Owner | Files | Depends on | Parallel-safe with |
|---|---|---|---|---|
| **T6C.0a Extract** (no visual change; a `refactor:` PR on its own) | ios-developer | out of `Features/Profile/ProfileView.swift` into their own files in `Features/Profile/`: `SyncDetailsView.swift`, `BodySettingsForms.swift` (`BaselineSleepNeedForm`, `MaxHeartRateForm`, `SettingStepper`), `ReportProblemView.swift`, `DevicesAndSyncView.swift`, `TrackerCheckView.swift`, `HeroNumeralsRow.swift`, `ProfileBuildingBlocks.swift` (`ProfileSection`, `SettingRow*`, `LinkRow`, `PrimaryButton` stay here until T6C.0); out of `Features/Sleep/SleepView.swift`: `SleepNeedSheet.swift`; out of `Features/Auth/AuthComponents.swift`: `Features/Profile/SignInMethodsView.swift` (area A edits the rest of that file) | none | PR 5's Profile ticket if it rebases after; T6C.6 widget |
| **T6C.0 Grammar** | ios-developer (+ ui-designer review) | new: `Design/SettingsGroup.swift` (`SettingsGroup`, `SettingsRow`, `SettingsDivider`, `SettingsNotice`, `TextAction`), `Design/NocturneSwitchStyle.swift`, `Design/SubpageScaffold.swift`; edit: `Design/PillButton.swift` (destructive, busy), `Design/StepRule.swift`, `Design/ImportProgressBar.swift`, `Design/Card.swift` (`SelectableTile`, `CapabilityState.tint`, `CapabilityRow`), `Design/StatusViews.swift` (`CheckRow`, `NumberedStep`, `InlineMessage` palette), `Design/SafariView.swift`, `Features/Profile/DebugComponentCatalog.swift`, `Preview/MockData.swift` (the synthetic "Alex Doe" account, sources, a queued report), tests 1–4, 15 | T5.0, T6C.0a, the lead's reconcile of §3 with PR 5 and areas A and B | none: everything below needs it |
| T6C.1 Profile pages | ios-developer | `Features/Profile/`: `DisplayView.swift`, `AboutView.swift`, `AccountView.swift`, `PrivacyView.swift`, `TrainingSettingsView.swift`, `ReportProblemView.swift`, `NotificationSettingsView.swift`, `LicensesView.swift`, `Features/Journal/JournalSettingsView.swift`, `SignInMethodsView.swift`; tests 4–5, 9–10, 15 | T6C.0 | T6C.2, T6C.3, T6C.4, T6C.5, T6C.6 |
| T6C.2 Devices & sync | ios-developer | `DevicesAndSyncView.swift`, `TrackerCheckView.swift`, `SyncDetailsView.swift`, the tracker picker; `Design/StatusViews.swift` `TrackerSetupCard` | T6C.0 | T6C.1, T6C.3–T6C.6; coordinate `TrackerSetupCard` and `TrackerPickerGrid` with area A (onboarding), the lead assigns the shared file to one ticket |
| T6C.3 Data and editors | ios-developer | `DataView.swift` (new), `BodySettingsForms.swift`, `SleepNeedSheet.swift`, `Design/SleepNeedBar.swift` | T6C.0 | T6C.1, T6C.2, T6C.4–T6C.6 |
| T6C.4 Bedtime & wake and Tonight | ios-developer | `Features/Sleep/SleepPlannerView.swift` (`SleepScheduleView`, `TonightCard`, `NeedBasisRows`); `SleepNightCards`' need row in `SleepView.swift` (a one-row change, coordinated with PR 5's Sleep ticket, which owns the rest of that file) | T6C.0; PR 5 Sleep Bedtime for the card's placement | T6C.1–T6C.3, T6C.5, T6C.6 |
| T6C.5 Import | ios-developer | `Features/Train/Import/*` (not `TrainComponents.swift` or `TrainSectionTitle`, area B's) | T6C.0; area B's header decision | T6C.1–T6C.4, T6C.6 |
| T6C.6 Widget | ios-developer | `RyftWidgets/ReadinessWidget.swift`, `WidgetOrbitGauge.swift`, `RyftWidgets.swift` (`Brand`, Rest timer), `WakeAlarmLiveActivity.swift`; `scripts/check-shared-types.py` run; `Shared/` only if T5.0 needs the `Recovery` colorset | T5.0's decision on `Accent` | everything (own target) |
| T6C.7 Copy | localization-editor | `Ryft/Resources/Localizable.xcstrings`, `RyftWidgets/Localizable.xcstrings` | all UI tickets | none (the one catalog) |
| T6C.8 Tests | test-engineer | `RyftTests/` per §6 | the UI tickets | after each |
| Shared, last | the lead | `CHANGELOG.md`, `docs/STATUS.md` | all | — |

Shared files and their single owner: the string catalogs (T6C.7), `MockData` and `DebugComponentCatalog` (T6C.0), `PillButton`, `StepRule`, `Card`, `StatusViews` (T6C.0), `SettingRow` and the old settings components (T6C.0 deletes them once T6C.1 to T6C.3 have moved off, so the deletion is the last commit of T6C.3), the widget's shared types (T6C.6, untouched otherwise).

## 8. Deviations

| # | From | To | Why |
|---|---|---|---|
| D6C-1 | board hairline ink 0.06 | `Theme.separator` (0.08) | the token; 0.02 is below what the eye separates on `surface` |
| D6C-2 | board: link-out "↗" at 0.35 only | push rows carry a chevron at 0.35 | a push needs an affordance; the board's pushed rows are not in view (reconcile with the Profile designer) |
| D6C-3 | Workout detail's centred 15 pt header title | subpages: Back, then the 26 pt Light title | pages are children of the Profile list, whose own header is 26 Light |
| D6C-4 | system `Toggle` with a tint | the drawn neutral switch (§2.4) | a white knob on a near-white track disappears |
| D6C-5 | a pill per action | the one primary as a pill, the rest as action rows | the board has two pills on a whole screen; the Data page has seven actions |
| D6C-6 | `List` and `Form` (Journal, Add a behavior) | cards and field cards | radius 22 and the hairline inset are not available to a `List` on iOS 17 |
| D6C-7 | the import's teal step rule | neutral segments (no Volt) | L27; Volt is a closed list |
| D6C-8 | the widget's rounded semibold number | the system face, Light, never the dot grid | the dot grid cannot be drawn at 104 pt; Light is the app's own fallback |
| D6C-9 | Journal swipe to delete | a trash button and a confirmation dialog | no `List`; a deletion without a confirmation is too easy to hit |
| D6C-10 | the app's 52 pt pill in a Live Activity | a compact 32 pt light pill | the activity's height is the system's |
| D6C-11 | toolbar "Save" in the editors | a pinned **Save** pill | the one primary action, as everywhere else |
| D6C-12 | `Sign in with Apple` 50 pt capsule | 52 pt, radius 26 | the pill's size and radius |
| D6C-13 | Sleep need's blue, amber and grey bar | one sleep tile of tick rows | one colour per metric; the bar used three |
| D6C-14 | the editors' bare stepper | the numeral, the ruler and an adjustable element | numbers first; the ruler shows the range |
| D6C-15 | Check sync: Check again always the pinned primary | **Allow access** while not asked | one primary per page |
| D6C-16 | the small widget's 16 pt margin | 12 pt | the orbit is the mark: 104 pt instead of about 94 |
| D6C-17 | Notifications' quiet-hours times as `DatePicker` rows | the same, tinted `textPrimary` | the system capsule is already neutral (c-21) |

## 9. Questions only the user can answer

1. **Widget type.** Should the widget bundle Satoshi (a user step in Xcode: add the three `.otf` to the extension target and `UIAppFonts` to its Info.plist) so its numbers match Today's, or stay on the system face in Light (as drawn)? Default: the system face.
2. **Journal delete.** Is a trash button with a confirmation dialog acceptable in place of swipe-to-delete (D6C-9)?
3. **"German name (optional)"** in Add a behavior: the app is English only. Keep the field (the API takes it) or remove it from the UI?
4. **Sleep Day's cards below the board** (stages, details): they are still the old look and belong to neither the PR 4 board nor this area. Who takes them?
5. **The small widget's 12 pt margin** (a bigger orbit) and the neutral "Open" pill in the Rest timer: OK to build as drawn?

---

## Appendix: the draft renders

All in `pr6-drafts/c/` in the lead's session scratchpad (not in the repo) (390 × 844 at 3x, dark, English). `c-NNx` are AX3. The renders are composed by a hosted test from the components and the §3 proposals; the source is kept beside them in `src/` and is not part of the commit. Where a render shows less than the spec (the Display footer's AX line, the widget's lock-screen vibrancy, the tracker picker's tile wrapping), the spec wins.

- c-01-display.png
- c-01b-display-thin.png
- c-01x-display-ax3.png
- c-02-about.png
- c-03-report-problem.png
- c-03b-report-problem-filled.png
- c-03c-report-problem-included.png
- c-03d-report-problem-limited.png
- c-03e-report-problem-sending.png
- c-03x-report-problem-ax3.png
- c-04-report-sent.png
- c-04b-report-queued.png
- c-05-devices-sync.png
- c-05b-devices-sync-scrolled.png
- c-05c-devices-sync-none.png
- c-05x-devices-sync-ax3.png
- c-06-tracker-detail.png
- c-07-tracker-picker.png
- c-08-check-sync.png
- c-08b-check-sync-running.png
- c-09-sync-details.png
- c-09b-sync-details-scrolled.png
- c-10-notifications.png
- c-10b-notifications-rollout.png
- c-10c-notifications-denied.png
- c-10x-notifications-ax3.png
- c-11-journal-settings.png
- c-11b-add-behavior.png
- c-12-sign-in-methods.png
- c-12b-sign-in-methods-both.png
- c-13-licences.png
- c-14-account.png
- c-15-privacy.png
- c-16-data.png
- c-16b-data-scrolled.png
- c-17-training.png
- c-18-sleep-need-sheet.png
- c-18b-sleep-need-sheet-no-breakdown.png
- c-18c-sleep-need-card.png
- c-19-baseline-sleep-need.png
- c-19b-baseline-sleep-need-saved.png
- c-19x-baseline-ax3.png
- c-20-max-heart-rate.png
- c-21-bedtime-wake.png
- c-21b-bedtime-wake-scrolled.png
- c-22-tonight.png
- c-22b-tonight-not-set-up.png
- c-22c-tonight-loading.png
- c-23-import-1-choose-files.png
- c-23b-import-2-detected.png
- c-23c-import-4-match.png
- c-23d-import-6-result.png
- c-24-widget-home.png
- c-25-widget-lock-screen.png
- c-26-widget-rest-timer.png
- c-27-widget-snooze.png
