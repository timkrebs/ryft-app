 and `Theme.recovery` too (lead, at integration). `SafariView` still reads `Accent` (T6.0 changes its tint)# Nocturne build plan: PR 5 and PR 6 (2026-11-18)

The lead's contract for every agent that builds Nocturne. It sits on top of the four specs in this folder:
- `design.md` §P5 (PR 5);
- `design-pr6-a-onboarding.md` (A);
- `design-pr6-b-train.md` (B);
- `design-pr6-c-settings.md` (C).

**Where this file and a spec disagree, this file wins.** It reconciles the shared parts the four specs asked for under
different names, it records the user's answers, and it changes the ticket split so that no file is restyled twice.

## 1. The user's decisions (2026-11-18)
The user approved all 124 draft renders and took every default the lead proposed (F1–F24).

**Across areas**
- F1: "Behaviors" becomes **"Habits"** everywhere in the UI. That covers the Journal subpage title, the hints and the cards. The
  API and the model keep their names.
- F2: the T0 extraction (§4) merges as soon as its CI is green.

**PR 5**
- F3: the custom flat `RyftTabBar`.
- F4: the Insights tile says "Insight" (R-N4 optional, later).
- F5: HRV is teal.
- F6: Week and Month get a `metricSleep` "vs 7 d" delta.
- F7: Strain keeps a day strip; the Insights disclaimer goes to the bottom.

**A**
- F8: white Apple button on top, Create account outline.
- F9: violet/teal/blue legend rings on Welcome.
- F10: a small lock-up row instead of the teal glyph on onboarding steps.
- F11: "Checking your account…" after 3 s on the splash.
- F12: the optional extras are not built.

**B**
- F13: two Volt marks while resting, as drawn.
- F14: Finish stays an outline until every set is done.
- F15: the rest pill is an outline with a Volt ring.
- F16: the active ✓ is a filled light square.
- F17: `DotNumeral` hero on summary, session detail, exercise page and activity detail.
- F18: the active plan is a strain glow tile; paused is an outline.
- F19: no celebration on the summary.
- F20: the live workout keeps 16 pt sides and 17 Medium exercise names.

**C**
- F21: the widget stays on the system face, Light.
- F22: Journal settings get a trash button with a confirmation; swipe-to-delete stays as well.
- F23: no "German name" field in the UI.
- F24: the small widget gets a 12 pt margin; the Rest timer gets a light "Open" pill.

**Lead decisions**
- MockData's demo user is "Alex Doe" (`alex@example.com`, "Alex's Apple Watch"), because the repo is public.
- Sleep Day's lower cards (stages, details) are restyled in T5.5.
- The widget's recovery arc stays teal through a `Recovery` colorset.

## 2. Shared components, one owner each
| Component | Replaces / unifies | Rule | Ticket |
|---|---|---|---|
| `PillButton` `.primary` / `.secondary` / `.destructive`, `busy:`, `async` action, `size: .compact` | `PrimaryButton` and `TealButtonStyle` (deleted in the gate); B S1/S2; A `isBusy`; C #4 | §P5-1.2. Destructive = `alert` outline at **70 %**. Busy = a spinner; the title and width stay. `.compact` = B S1 (40 pt visual in a 44 pt box, content width, no icon circle) | T5.0-A |
| `RyftToggleStyle` (`.toggleStyle(.ryft)`) | B S7, C `NocturneSwitchStyle` | §P5-1.4: on = `textPrimary` track, `background` knob; off = 1.5 pt `textTertiary` outline. 51 × 31. Applied once at the root | T5.0-A |
| `ryftLink()` and a Markdown-link helper | A `LinkText`/`LinkButton`/`TextActionButton`, C `TextAction` | §P5-1.4: `textPrimary`, underline at 50 %. Inline Markdown links get the same ink and underline | T5.0-A |
| `IconDisc` | — | §P5-1.4 | T5.0-A |
| `Recovery` colorset in the app and widget catalogs | C's coupling note | `OrbitGaugePalette` reads `Recovery`, so the orbit's recovery arc stays teal when the `Accent` tint goes neutral | T5.0-A |
| `GroupedCard`, `GroupedRow`, `GroupTitle` (`Design/GroupedList.swift`) | A `ListGroup`; B S4; C `SettingsGroup`; `ProfileSection`, `SettingRow`, `SettingRowLabel`, `LinkRow` (callers move in their screen tickets) | Radius 22, rows ≥ 46, `separator` hairline, title 13 `textTertiary`, value `textTertiary`. Row kinds: value, push, link-out (↗), action, select, toggle, destructive. Optional footer text | T5.0-B |
| `NeutralTile` (`Design/NeutralTile.swift`) | B S5; `MetricTile` (T5.2 deletes it once Strain no longer uses it) | 80 high, radius 22, label 13 at `textSecondary`, value 24 Light, unit 12 `textTertiary`, optional note; no icon, no tint | T5.0-B |
| `DateStrip`, restyled in place | PR 5 `DayStrip` (**not built**), B S11 | B §8.4 look; Strain (F7), My Day and the Journal use it | T5.0-B |
| `PlaceholderRow(height:)` | B S12 | 1 pt `separator` outline in the row's size | T5.0-B |
| `SegmentedPicker`, `ScreenHeader(title:trailing:)`, `GlowTile` (`.zones`, `.idea`), `TickRow` (`arrangement`), `ZoneBlock`, `TrendLine`, `DeltaLabel` | §P5-1 / §P5-13 T5.0 row | as specified | T5.0-B |
| `SubpageScaffold` with `PinnedBar` | A's pushed header and `PinnedBar`; C #3 | Back `CircleButton`, 26 Light title, swipe-back kept, optional pinned bar | T6.0 |
| `SheetHeader` | B S3 | Close on the left, centred title, trailing slot | T6.0 |
| `FormField` and `ValueChip` | A `FormGroup`/`FormRow`; B S9 | 56 high, label above value, focus = a 2 × 28 bar with no fill; lives in a `GroupedCard` | T6.0 |
| `InlineMessage`, restyled in place | C `SettingsNotice` (**not built**) | Neutral; severity by glyph + word. Amber only for "needs attention"; `alert` only for destructive | T6.0 |
| `SelectableTile`, `CheckRow`, `NumberedStep`, `TrackerSetupCard`, `StepRule`, `SafariView` tint, restyled in place | A; C #5, #8, #9, #10 (`NeutralSelectableTile` **not built**) | as A's and C's specs | T6.0 |
| `Card` radius 22 / padding 16 | B S10 | once, in `Card.swift` | T6.0 |
| `RyftStepper` | B S8; C's editors | Inline `− value +`. C's editor sheets compose the same `CircleButton`s around a `DotNumeral` and its ruler, as one adjustable element | T6.0 |
| `LegendMark` | A | Welcome, Insights legend, About | T6.0 |
| `ActivityListRow` | B S6 | T5.2 builds the board row; B extends it (badges, state mark, dashed variant) | T5.2, then T6B |

## 3. Ticket split changes against the specs
- **No accent sweeps T5.0b-1 and T5.0b-2.** Areas A, B and C restyle Auth, Onboarding, Push, Train, Import, My Day, Journal,
  Activities and the Profile subpages fully, so they also do their files' `accent-map.md` rows. A sweep before them would
  restyle the same lines twice.
- **What stays as a sweep:** T5.0b-3 covers only the files no screen ticket owns: Today's `TealButtonStyle` sites,
  `FeatureFlagsDebugView`, `DataExport`, and anything the gate's compiler run finds. It runs late, next to the gate.
- **The gate T5.9 becomes the last PR of the set** ("design: retire the pre-Nocturne tokens"). It runs after PR 6 A/B/C, and it
  deletes `PrimaryButton`, `TealButtonStyle`, `Theme.accent`/`onAccent`/`teal` and the rest of §P5-13's list. It also wires
  `check-accent.sh`, removes the light previews and re-shoots the screenshots.
- **PR 6's shared parts land in PR 5's foundation** (T6.0 on `feat/nocturne-tabs`), so PR 6 A/B/C start from one base.
- **What T0 moves** (§4): `SplashView` stays in `RyftApp.swift`, because T5.1 owns that file; T6A.5 moves it. `TrackerPickerGrid`
  and `HealthAccessHint` stay in the onboarding files.

## 4. Waves, branches, file ownership (at most 5 builders on this Mac)
| Ticket | Branch (base) | Owns | Must not touch |
|---|---|---|---|
| **T0 extraction** (pure move) | `refactor/split-large-views` (`origin/main`), its own PR, merges when green (F2) | moves types out of `ProfileView.swift` into one file each in `Features/Profile/`, `SleepNeedSheet` out of `SleepView.swift`, `AccountHintSheet` and `SignInMethodsView` out of `AuthComponents.swift`, `HealthPermissionView.swift` split by step | any behaviour, look, type name or string; `RyftApp.swift`; `Design/` |
| **T5.0-A controls** | `feat/nocturne-t50a` (`feat/nocturne-tabs`) | `PillButton.swift`; new `RyftToggleStyle.swift`, `InlineLink.swift`, `IconDisc.swift`; the `Recovery` colorsets and `Shared/OrbitGaugePalette`; `Theme.swift` additions; `MockData.swift`; its section of `DebugComponentCatalog` | call sites; `RyftApp.swift` |
| **T5.0-B structures** | `feat/nocturne-t50b` (`feat/nocturne-tabs`) | new `GroupedList.swift`, `NeutralTile.swift`, `PlaceholderRow.swift`, `ZoneBlock.swift`, `TrendLine.swift`; changed `DateStrip`, `SegmentedPicker`, `ScreenHeader`, `GlowTile` + `GlowTileSpec`, `TickRow`, `DeltaLabel`; its section of `DebugComponentCatalog` | `PillButton`, `Theme.swift` (send additions to the lead), `MockData` |
| **T5.1 tab bar** | `feat/nocturne-t51` (`feat/nocturne-tabs`) | `RyftTabBar.swift`, `RyftApp.swift` (tab host, the app `.tint`, the root `.toggleStyle(.ryft)` once T5.0-A is in), `AppState.swift`, `ScreenScaffold` in `StatusViews.swift`, the UI tests' tab lookups | other parts of `StatusViews.swift` |
| **T6.0 PR 6 foundation** | `feat/nocturne-t60` (`feat/nocturne-tabs`) | new `SubpageScaffold.swift`, `SheetHeader.swift`, `FormField.swift`, `RyftStepper.swift`, `LegendMark.swift`; in place: `InlineMessage`, `CheckRow`, `TrackerSetupCard`, `NumberedStep` (all in `StatusViews.swift`, not `ScreenScaffold`), `Card.swift`, `StepRule.swift`, `SafariView.swift`; its section of `DebugComponentCatalog` | `PillButton`, `Theme.swift` (send additions to the lead), feature files |

The lead merges T5.0-A, T5.0-B, T5.1 and T6.0 into `feat/nocturne-tabs` and resolves the catalog and `Theme` additions there,
then merges `main` in after T0 lands. **The foundation commit** is the point where all four are in.

- **N1, PR 5 screens:** T5.2 Strain + Workout, T5.3 Insights, T5.4 Profile list, T5.5 Sleep modes + Day's lower cards. Each
  runs on its own branch off the foundation commit, and the lead merges them into `feat/nocturne-tabs`.
- **N2 and N3, PR 6:** A, B and C branch from the foundation commit (`feat/nocturne-pr6-onboarding`, `-train`, `-settings`), with
  their screen tickets on sub-branches. After PR 5 squash-merges, each is moved with
  `git rebase --onto origin/main <foundation commit>`.
- **Strings:** one localization-editor pass per PR, with targeted catalog edits, the per-key merge, and a `--stat` check.
  English only.

The merge set is PR 5 → PR 6 A → PR 6 B → PR 6 C → the gate, all on one day, after an integration-branch trial with every open PR
(strict build plus Unit).

## 5. Rules for every Nocturne ticket
- Dark only, English only. Synthetic data only (Alex Doe). Teal only for recovery (L27). Volt only for "now".
- Every changed view keeps a `#Preview` (dark; no new light previews). Capture it, compare it with its board or approved draft,
  fix, then commit.
- Zero warnings in the strict build (`RYFT_STRICT_WARNINGS=YES` and the grep in `CLAUDE.md`'s CI), `make lint`, `make style`,
  and the Unit plan for the files you touched.
- Reduce Motion, VoiceOver labels, and Dynamic Type up to AX3 (the specs' AX rules).
- Real names: replace any real person's name, email or device name you find in a file you own (previews, fixtures, doc comments; e.g. `tim@example.com`, "Tim's iPhone") with synthetic ones (Alex Doe, `alex@example.com`). `dev.timkrebs.ryft` bundle IDs stay.
- New strings so far, for the PR 5 strings pass: "In progress" (PillButton busy VoiceOver value).
- Never re-serialise `Localizable.xcstrings`. A ticket that needs a new string lists the key and its English value in its
  report; the localization-editor adds them.
- Commits and PR text carry **no** "Generated with Claude Code" line and **no** Co-Authored-By trailer.
