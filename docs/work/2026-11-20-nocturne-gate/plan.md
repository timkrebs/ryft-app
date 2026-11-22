# Nocturne gate (T5.9) and PR 6 follow-ups — plan (ios-lead, 2026-11-20)

Nocturne's six PRs are on `main` (#112–#114, #117, #127, #131). Still to come:
- **The gate** (`docs/work/2026-11-16-nocturne/design.md` §P5-13 T5.9, `build-plan.md` §3) retires the pre-Nocturne
  tokens and components, and takes the items the PR 5 and PR 6 reviews left for it
  (`docs/work/2026-11-16-nocturne/review.md`, "Left for later").
- **A behaviour PR** with the PR 6 re-checks' nits. They are not design and could go independently.

Two PRs:

| PR | Branch (base) | Title |
|---|---|---|
| Gate | `feat/nocturne-gate` (`origin/main` b6e416e), tickets on branches off it | `design: retire the pre-Nocturne tokens` |
| Follow-ups | `fix/pr6-follow-ups` (`origin/main`) | `train: the PR 6 re-checks' follow-ups` |

## Inventory at b6e416e (`Ryft/`, `RyftWidgets/`, `Shared/`)

| What T5.9 deletes | Uses | Files |
|---|---|---|
| `PrimaryButton(` (incl. `ImportPrimaryButton(`) | 23 | 9 |
| `TealButtonStyle` | 8 | 5 |
| `Theme.accent` | 21 | 11 |
| `Theme.onAccent` | 4 | 4 |
| `Theme.zones` | 2 | 1 |
| `StageDeep/Light/REM/Awake` | 4 | 1 |
| `SchemePair` | 16 | 6 |
| `MetricTile` | 23 | 3 |
| `AppState.workoutDetail` | 8 | 4 |
| Light previews / `.light` schemes | 54 | 38 |
| `docs/screenshots` `-light` / `-de` | 74 / 67 | — |

## Tickets: the gate

| # | Ticket | Owner | Depends | Acceptance (testable) |
|---|---|---|---|---|
| G0 | Design note `design.md` here: the replacement for every remaining use above, by file; the open design calls D1–D9 (below); drafts of the analytics prompt, the one circle menu and the sheet header | ui-designer | — | Every inventory row has a replacement or a deletion; each D has a decision with its reason; drafts in the scratchpad, synthetic data |
| G1 | Sweep: every remaining old-token site to its Nocturne replacement (Today, Push, the import, Profile components, `FeatureFlagsDebugView`, `Design/` CoachMarks, RangeBar, ScoreRing, MetricSpec, StatusViews); the analytics prompt redrawn | ios-developer | G0 | The inventory's grep is empty outside the token definitions; previews and hosted tests of the changed views; no teal in a pixel test of Today, the import and the analytics prompt |
| G2 | Components: one `CircleMenu` for the three hand-drawn menus; one sheet header convention; the live workout's offline line once; the card radius as one token; `MetricTile`, `MetricGauge`, `AppState.workoutDetail` deleted | ios-developer | G0 | One `CircleMenu` type, used by all three; one header rule with a lint or test; tests for each removal (compiler) and the offline line (hosted) |
| G3 | AX and keyboard: HR ruler labels at AX3, About you's wheel at AX sizes, the journal chips at AX5, the keyboard's Done over Report a problem's and Add activity's Send (D5) | ios-developer | G0 | Hosted AX3/AX5 checks per item; the Send button hittable with the keyboard up (UI test) |
| G4 | Delete the tokens (`Theme.accent`, `onAccent`, `teal`, `zones`, Stage colours, `SchemePair`, `PrimaryButton`, `TealButtonStyle`); the `AccentColor` asset becomes ink; the accent lint covers all of `Ryft/`; light previews removed | ios-developer + test-engineer (lint) | G1, G2, G3 | Builds with the symbols gone; lint self-test cases for the widened scope; `make lint` green |
| G5 | Strings: the remaining plain-space unit keys, the joined lines R3 left (sentence keys), catalog comments | localization-editor | G1–G4 | `sync-strings --check` 0; a no-break-space scan of the catalog finds none before units or % |
| G6 | Screenshots: the 74 `-light` and 67 `-de` files go; `make screenshots` re-shot (dark, English, demo data) | ios-developer | G4, G5 | `docs/screenshots` holds only dark English shots; each checked for synthetic data |

Reviews: code-reviewer on the whole branch; ui-validator on the integrated app (default, AX3, AX5); security-privacy-reviewer
only if G1 touches Push or Profile behaviour. Integration run: strict build, Unit, the whole UISmoke plan, Release, lint,
style, strings.

### Design calls for G0
- **D1:** the Insight glow tile's teal (spec F4's exception) once `Theme.teal` is gone.
- **D2:** the analytics prompt in Nocturne (`OnboardingScreen`, `OnboardingPoint`, `PillButton`). `ui.md`'s "accent only
  on the symbol" conflicts with the accent map.
- **D3:** one circle menu (the three hand-drawn ones).
- **D4:** one sheet header convention (B and C put the close button on different sides).
- **D5:** the keyboard's floating Done over a pinned Send (Report a problem, Add activity): Done in the header, or hide
  the pinned bar while editing.
- **D6:** Profile while a consent withdrawal is on its way: hold the Demo data switch and Sign out (security N-2). The
  follow-ups PR builds it.
- **D7:** `SchemePair` and the Stage colours: the dark values as tokens, or the existing palette.
- **D8:** the card radius (22 in the cards vs `Theme.Metrics.cardRadius` 18).
- **D9:** `ValueChipRow`'s label ink, `PillButton`'s dimmed state, the "Last time" card at its fade (the PR 5/6 nits).

## Tickets: the follow-ups PR

| # | Ticket | Owner | Acceptance |
|---|---|---|---|
| F1 | `loadPlan`'s failure stays on the plan page (not the library's shared message); My Day's `forget()` gets a generation; a failed plans re-read after pause or delete says so, or patches the list; Insights' loaded range is forgotten on a switch | sync-engineer | One test per item, each failing against its mutant |
| F2 | Profile holds the Demo switch and Sign out while a withdrawal is on its way (D6); Train's online failure with nothing cached gets its own words, not "try again when you're online" | ios-developer + localization-editor | Hosted Profile test; History, exercise and session tests for the online and offline words |

Not here: the `ReadScheduler` states hardening (security's idea, not reachable today). It goes to the offline-first
work with an ios-architect note (it is `Persistence/`).

## Risks
- **G1 and G2 both touch `Design/`.** G0 assigns each file to one ticket.
- **The token deletion (G4) finds the last uses at compile time.** It runs after G1–G3 have merged into the branch.
- **CI time.** The Unit step is ~15 of 25 minutes and UI smoke ~14 of 25. Deleting light previews doesn't change tests;
  new hosted tests should stay few.
- **Main moves** (the other lead's App Attest and analytics work). Merge `origin/main` into the branch before each
  integration run.

## Lead decisions on G0 (2026-11-20)
- **D1, D2, D3, D5, D7, D8, D9: as `design.md` §2.**
  - D1 removes the last exception to L27: teal means recovery.
  - D2 follows the Consent step and ships dark; #130's decision B (the prompt as an onboarding step) stays the user's.
  - D3, D5, D7, D8 and D9 settle review nits or delete code nobody calls.
- **D6: as designed, built in F2.** The one sentence there is settled with the localization-editor. The draft shows
  "… is available when your consent withdrawal has finished", the note "Waiting for your consent withdrawal to finish.".
- **D4 and DG-6 (sheet and pushed-page headers) go to the user.** They change the look of about 30 pages. G2 builds
  everything else first; `SubpageScaffold.swift` and `SheetHeader.swift` wait.
- **F1 extras accepted:** deleting a paused plan forgets its paused id, and the plan-day patches. Logged as a follow-up:
  `savePlan` after a failed re-read (the new plan is missing until the next refresh).
- **Started:** G1 (`feat/nocturne-gate-g1`) and G2 (`feat/nocturne-gate-g2`), both off e04090d. G3 starts once F1's runs are
  done. G4 starts after G1–G3 are merged into `feat/nocturne-gate`.

## The user's call on headers (2026-11-21)
**One header everywhere.** Sheet roots get D4's `SheetHeader`: close leading, title centred, commit trailing, pinned. Every
pushed page gets the `PushedHeader` row: Back leading, title centred (with a subtitle), a trailing circle or an empty slot.
This includes C's Profile subpages and the import's steps (Back · title · close). Tab roots keep `ScreenHeader`. G2's second
part builds this on `feat/nocturne-gate-g2` after G1 and G2 are merged (f51a7fa).

## Status (2026-11-21)
- **G1 and G2 part 1 are merged** into `feat/nocturne-gate` (f51a7fa).
  - G1: 7 commits; Unit 4,792 passed, 0 failed.
  - G2: 5 commits; Unit 4,784 passed, 0 failed.
- **Now:** G2 part 2 (headers, `GaugeNoteLink` → `.ryftLink()`, G1's scan skip list) and G3 (`wt-g3`).
- **Follow-ups PR:** F1's four commits on `fix/pr6-follow-ups`. 16/16 mutants killed; UISmoke 53/0/1; Release passes.
  Code review is running. F2 (D6 and Train's online-failure words) becomes its own PR: it changes the consent flow, so
  it needs a security review.
- **Found:** `ActivitiesNocturneRuleTests/saveStaysOffUntilTheFormIsValid` fails between 00:00 and 00:30. The form's
  start is midnight and its end lies in the future. A `test:` fix (inject the clock) goes into the follow-ups PR.

## Part 1 and part 2 (2026-11-21)
To fit a merge window the gate ships in two PRs:
- **Part 1** (this branch): G1, G2 with the one header, G3, the strings pass, and the `ConsentTrainTests` platform fix.
- **Part 2:** G4 (delete the tokens, `AccentColor`, the lint's widened scope, light previews), G5 (the remaining unit keys
  and sentence keys), and G6 (the screenshots).

The 16:00 grant ran out before part 1 was ready. #132 was merged in time; part 1 waits for the user's go.
Also for part 2: `sync-strings.py` extracts the sample VoiceOver values in `#Preview` bodies (its docstring says it
skips them). Decide whether to fix the script or the docstring.

## Status (2026-11-22)
- **Part 1:** #133, green, waiting for the user's merge.
- **Part 2** (`feat/nocturne-gate-2`):
  - G4, G5, G6 and three review rounds are done (`review.md`);
  - opened against `main` once #133 is merged.
- **F2:** #134.
- **Follow-ups from the reviews:**
  - S-3: a sign-out started by the auth system during a withdrawal. It needs an ios-architect note.
  - The % spacing ("86%" vs "60 %") and the separators that start a line.
  - "%lld s" in VoiceOver.
  - TrainHistory's subtitle outside the catalog.
  - The 24-hour notification hours.
  - Routes in `screenshots.sh` for Train, the trackers and signed out.
  - The Max HR caption's separator at AX sizes.
