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
