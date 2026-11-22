# Nocturne gate: review log

Part 1 is #133 (`feat/nocturne-gate`), part 2 is `feat/nocturne-gate-2`. Findings, each with its decision.

# Part 1

## Part 1: security-privacy-reviewer (fe69399 → 7fa1b6f)
No blockers, no should-fix.

| # | Sev | Finding | Decision |
|---|---|---|---|
| 1 | N | The CHANGELOG named the analytics question, which no one sees in phase 1 | Fixed: the line leaves it out |
| 2 | N | Report a problem: Send sits where the old keyboard Done was, so a habit could send a half-written report | Kept: D5's order puts the primary trailing, as every pinned bar does. The report needs a message and is limited to 10 a day |
| 3 | N | The push pre-prompt's "Allow" mirrors the system alert's title (HIG). Not new | Logged for a copy pass |

Checked fine:
- the analytics prompt: equal choice, no default, a swipe means Don't share, nothing sent;
- the push actions and their timing;
- the header move: Cancel and Close paths, secure fields, redaction;
- the debug views are DEBUG-only;
- no logging, network, plist, entitlement or manifest changes.

## Part 1: code-reviewer (028257d)
No blockers.

| # | Sev | Finding | Decision |
|---|---|---|---|
| 1 | S | The new regression test reset `MockTrainSource.shared` itself: the same race, for other suites | Fixed (f76622b): the test and its `AfterPut` helper are gone; every test in the suite keeps its own source |
| 2 | N | `NocturneGateTests` and `NocturneHeaderTests` scans don't strip comments | Part 2 (G4 writes such comments): use the shared `code(_:)`; widen the pattern to `Color("Accent")`, `.accentColor`, `Color.teal` |
| 3 | N | Import steps 1 and 6: the sheet header scrolls with the step | Part 2: pin it, or note the exception in design.md |
| 4 | N | The hosted "clear of the keyboard" check can't fail (no software keyboard in a host) | Part 2: `#require` a keyboard frame or drop it; the UI test is the proof (in Full, not UISmoke) |
| 5 | N | The analytics prompt rebuilds across AX1 (two view identities) | Part 2 |
| 6 | N | The gauge note link underlines its chevron | Part 2 |
| 7 | N | `Card.swift`'s stale TODO | Fixed (ff6f30b) |
| 8 | N | The README lists `ScoreRing` and `MetricTile` | Fixed (ff6f30b) |
| 9 | N | Set new password's Cancel stays tappable while saving (on main already) | Later: a `closeDisabled` pass-through on `SubpageScaffold` |

## Part 1: ui-validator (fe69399, demo app plus hosted renders, default/AX3/AX5)
No blockers.

| # | Sev | Finding | Decision |
|---|---|---|---|
| 1 | S | Sheet headers stay on one row at AX3/AX5 (stacking only under 120 pt); pushed pages stack leading from AX1. Two AX behaviours under "one header" | Part 2 (G4): sheets stack from AX1 the way pushed pages do; design.md §2.4 rule 2 updated |
| 2 | N | The pinned sheet header has no edge while text scrolls under it (AX5) | Part 2: reuse the pinned bar's edge treatment |
| 3 | N | The import card's step chips truncate at AX3 (on main already) | Part 2: they wrap from AX1 |
| 4 | — | `-RyftScreen syncDetails` shows no Close (a debug route; the real sheet has it) | None |

Checked fine:
- every header in scope, at default and AX3;
- no teal outside recovery;
- the three circle menus;
- Report a problem's bar while typing;
- rulers, About you and the journal strip at AX3/AX5;
- card radius 22.

Shots are in `scratchpad/uiv-gate1/shots/`.

# Part 2

## Part 2: code-reviewer (ff6f30b..b47c950)

| # | Sev | Finding | Decision |
|---|---|---|---|
| B1 | B | `Info.plist`'s `UILaunchScreen.UIColorName` still names the deleted `Graphite` set; the launch screen falls back to the system colour, and LaunchHost's pixel hand-off breaks | Fix: `Background` (same #0A0C0B); a test that the launch colour resolves and equals `Theme.background`; LaunchHost comment, APP_STORE.md row |
| S1 | S | Add activity / Add sleep: `scrollTo(saveErrorID, anchor: .top)` lands at offset 10, so the new edge cuts the save error card's top | Fix: scroll to a zero-height anchor above the padding; a hosted check |
| N1 | N | Exercise history sheet (from the live workout), Start workout, Reorder: header not pinned / no edge | Fix: pin and edge, as the others |
| N2 | N | design.md §1.10, ADR 0016's legacy-names paragraph, and comments naming deleted tokens (check-shared-types, ChartStyle, CHART_STYLE.md, ReadinessWidget, NotificationRing, ui-designer.md) | Fix the docs and comments; ADR 0016 gets an amendment line. NotificationRing's literals: map to Nocturne values |
| N3 | N | The keyboard UI test passes without a software keyboard | Fix: `XCTSkip` with a reason when no software keyboard |
| N4 | N | The chip pixel check counts colour across the whole strip | Fix: count within each step's rect |
| N5 | N | `SheetHeader`'s "no row" guard misses the scaffold's `.none` (Optional) | Fix |

**Device look:**
- the Files picker's multi-select check on an ink tint;
- the HealthKit sheet;
- the Control Center Workout control.

These go on the user's device list.

## Part 2: localization-editor (G5: 140fae0, d79383d, 286d27e)
- **No-break spaces:** 136 keys, with comments and variants kept (lead check: 138 keys out and 139 in; no comment or variant lost; the file ends `}\n`).
- **Sentence keys:**
  - 4 import sentences ("The rest imports normally, and %lld notes." was "normally. and 2 notes");
  - joins left: parts lines, the "Demo data · " prefix and VoiceOver-only joins, each with a reason.
- **sync-strings:** the docstring was fixed. The sample VoiceOver keys come from a preview-only helper in RulerScale and stay (harmless; English only).
- **Logged for later:**
  - TrainHistory's subtitle is a plain code string outside the catalog;
  - "%lld s" reads as a letter in VoiceOver;
  - the manual push loc-keys keep plain spaces (the platform's payloads).

## Part 2: G4 round 2 (64a0bce..9c820f3): all code-review findings fixed
- **B1:** the launch colour is `Background`, with a bundle test.
- **S1:** a failed save rests at offset 0.
- **N1:** three more sheets pinned; Reorder's List reports its scroll geometry.
- **N2:** the docs, ADR 0016's amendment, NotificationRing in Nocturne values, two more stale comments.
- **N3:** skips without a software keyboard.
- **N4:** a count per chip.
- **N5:** a `Mirror` check for an Optional trailing view.
- **Not from the review:** `ImportUITests` failed with a plain space after G5; fixed in 9c820f3.
- **Runs:** strict build 0 warnings; Unit 4,847 passed of 4,852 (4 skipped, 1 expected); UISmoke 55 passed, 1 skipped; keyboard UI 4 of 4 with a software keyboard; Release; lint, style and strings. Mutants: 13, all killed.
- **Left:** 9 SwiftLint line-length warnings from G5 (style passes); two are `comment:` literals.

## Part 2: G6 (c602e7f, ca56db2) and the lead's follow-up (f3c4c73)
- **Deleted:** 105 light and German files (the brief's "67 -de" was a loose grep; 57 are German).
- **Re-shot:** 38 dark English shots on a fresh simulator set to en_US (it inherited the Mac's German region), names kept.
- **Lead, f3c4c73:** the 26 shots with no producer in `screenshots.sh` are deleted (old look, German formats). One of them, `tracker-devices-dark-en-AX3.png`, showed real device names ("Tim's Apple Watch", "Tim's iPhone"). It has been public since #34, and its history is the user's call (no force-push). The README's second row now uses re-shot screens.
- **Folder:** 169 files / 45.9 MB → 38 files / 19 MB. Re-shot PNGs are about 2× larger (gradients); no lossless optimiser is installed.
- **Logged:**
  - Notification hours are a hard-coded 24-hour "09:00–21:00" (`NotificationSettingsViewModel.swift:130`).
  - `screenshots.sh` has no routes for Train, the tracker screens or signed-out screens (BETA-C).
  - The debug routes draw `.root` (no Close) for Sync details and Bedtime.

## Part 2: ui-validator (9c820f3, a fresh en_US simulator, default/AX3/AX5)
Verdict: merge. Part 2 introduced no blocker.

**Checked fine:**
- the launch frames (#090C0B to #0A0C0B, no flash);
- the ink accent in every system UI reached: menus, DatePicker, the time wheel, the caret, dialogs, alerts, the share sheet. The Files picker's multi-select badges stay system blue with a white check, so they're readable;
- sheet headers stacked at AX3 and AX5, with no empty row on a root without circles;
- the pinned edge, absent at rest;
- the import chips wrapping whole;
- no-break units at AX3;
- no regressions at default.

| # | Sev | Finding | Decision |
|---|---|---|---|
| 1 | S | StageRow at AX5: "20" / "%", "Awak" / "e" (pre-existing) | Fix in part 2 (round 3): stack from AX1 |
| 2 | S | The coach callout's title is above the screen at AX3 and AX5 (pre-existing) | Fix in part 2 (round 3): keep it inside the safe area |
| 3 | N | Max HR caption at AX loses its "•" | Later |
| 4 | N | A "·" starts a line at large sizes | Later (copy pass) |
| 5 | N | % spacing mixed: `Fmt.percent` "86%" vs strings "60 %" (predates G5) | Later: pick one style in a copy pass |
| 6 | N | Launch #090C0B vs #0A0C0B (simulator rendering) | None |

**Not verified:** widgets, the Log out and Delete account dialogs, the HealthKit sheet, Reorder's scrolled edge (its list fits).

## Part 2: round 3 (9a833cd, a8da779)
- **StageRow:** stacks from AX1 and nothing breaks (hosted check at AX5).
- **The coach card:** stays inside the safe area; it is capped and scrolls when taller than either side of the hole. Placement tests plus a hosted walk at AX3 and AX5.
- **Runs:**
  - strict build 0 warnings;
  - Unit 4,853 passed of 4,858 (4 skipped, 1 expected);
  - UISmoke 55 passed of 56 (1 skipped);
  - Release; lint, style and strings.
- **Mutants:** 3, all killed.
