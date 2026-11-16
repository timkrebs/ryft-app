# Nocturne — plan

**Goal:** the premium look of `brief.md` (NOCTURNE_STYLE v0.2): the same OrbitGauge geometry, model and mapping,
rendered premium. The rings are the legend (recovery teal, sleep violet, strain blue everywhere), Volt `#D8FF4F` is
signal only, the app is dark-only, and the launch turns the rings into the orbit mark.
**Mockups:** https://claude.ai/artifact/1Gc5U9M2MyFgRKQHwHRtMi (Today, Sleep, Strain, Insights, Profile, Launch, Icon M1).
**Out of scope:** model, sync and API changes. A screen that lacks data gets a MockData placeholder and an
entry in `docs/API_REQUESTS.md`.

## Decisions taken by the lead (2026-11-16)

| # | Decision | Why |
|---|---|---|
| D1 | Previews and validation in **English only** (dark, AX3), not en/de as the session brief says. | `CLAUDE.md` and #105: RYFT is English only. |
| D2 | The ADR is **0016**. | 0015 was used on the closed Alpine PR #100. |
| D3 | PR 1 changes the `CLAUDE.md` preview rule to dark-only. Light previews go file by file as PRs 1–5 touch each file; PR 5 removes the rest. | Avoids a repo-wide preview sweep in a tokens PR. |
| D4 | Satoshi is already in `LicensesView` (ITF Free Font License). PR 1 only adds the Light weight to that entry, `fetch-fonts.sh`, `UIAppFonts` and the archive check. | Same family, same licence. |
| D5 | `main` shows a mixed look between PR 1 and PR 5: the new colours and type on the old layouts. Accepted. | The brief's order. The nightly has been red since 2026-11-05 (signing), so no build reaches testers before the user fixes it anyway. |
| D6 | The widget follows the app: same tokens, dark only. | §1 dark-only; `check-shared-types.py` keeps both catalogs aligned. |
| D7 | `textTertiary` at 45 % is about 4.1:1 on `background`, under 4.5:1 for 11–12 pt text. The designer verifies and raises it if needed. ADR 0016 records the number. | §2 allows deviations "wo Kontrast … es verlangt". |

## Tickets

### PR 1 — `design: nocturne tokens, type and icon` (branch `feat/nocturne-tokens`)

| Ticket | Owner | Files |
|---|---|---|
| T1.1 Tokens, type, wordmark, icon, fonts | ui-designer | `Design/`, both `Assets.xcassets`, `scripts/render-icon.swift`, `scripts/icon-spec.swift`, `scripts/mark-svg.swift`, `scripts/fetch-fonts.sh`, `Makefile`, `Ryft/Info.plist` (`UIAppFonts`), `LicensesView` entry, token tests, `design.md` §PR1 |
| T1.2 Dark-only wiring, caps outside Design | ios-developer (branch `feat/nocturne-dark-only`, merged into PR 1) | `App/Settings.swift`, `App/RyftApp.swift`, `Features/Profile/ProfileView.swift`, `DebugComponentCatalog.swift`, `Features/Train/Session/ExercisePage.swift`, `Ryft/Info.plist` (`UIUserInterfaceStyle`), string catalog (removed keys only) |
| T1.3 ADR 0016 | ios-architect | `docs/adr/0016-…` |

Acceptance criteria:
1. The colorsets in `Ryft/` and `RyftWidgets/` carry the §2 values with a single appearance. `Signal` `#D8FF4F` and
   `OnSignal` `#0A0C0B` exist. A unit test pins every §2 token; any deviation is the ADR's number.
2. Every text token reaches ≥ 4.5:1 on `background` and `surface`. Metric and signal colours reach ≥ 3:1 on both
   (unit test).
3. The app is dark in every context, whatever the system setting: the root, sheets, alerts and the launch screen.
   Profile has no appearance setting, and a stored `appearance` value is ignored.
4. Satoshi Light is registered and fetched, and the archive check covers it. Titles and numbers are Light, body
   Regular and buttons Medium, per the §2 scale with tabular digits. `ryftLabelStyle` is sentence case without
   tracking. No `.textCase(.uppercase)` is left on a label.
5. The wordmark is "RYFT" in Satoshi Light at 0.32 em tracking, beside the orbit mark, with a Preview.
6. `make icon` renders M1 into the asset catalog: `#0A0C0B` tile, "RYFT" Satoshi Light `#F2F1EC`, 0.02 em tracking,
   ≈ 280 px on 1024, no mark, light, dark and tinted alike. `make lint` is green.
7. ADR 0016 covers dark-only, the tokens with every deviation from §2 or from today's assets (with numbers), the
   signal rules, the widget and the icon.
8. Zero warnings in our code, all tests green, a CHANGELOG line under Unreleased, and a line in STATUS.md.

Verify: code-reviewer and ui-validator (dark, en, AX3, icon at 60 and 40 px), in parallel.
No security-privacy-reviewer: the only Info.plist changes are a font entry and the interface style, with no
auth, data or network.

### PR 2 — `design: dot numeral, ruler, glow tile`
`DotNumeral` (5×7, dots 5 pt, gap 2 pt; falls back to Light digits from AX1), `RulerScale` (band zone, Volt
needle), `GlowTile` (§2 gradient, flat `surface` + 2-pt metric border under Reduce Transparency), `DotRow`,
`TickRow` (zones), pill and circle buttons. Catalog entries and tests: the digit matrix, luminance under text in
the glow core (§6). ui-designer specs, then ios-developer. test-engineer writes the tests from the criteria in
parallel.

### PR 3 — `design: orbit gauge v3 and launch`
§3 rendering without model changes. ios-architect design note first, because the launch sequence is a state
machine plus timing at cold start. §5 launch from `RyftMarkGeometry`, played once per cold start, with a static
mark and cross-fade under Reduce Motion. The gauge and mark tests are re-pinned. performance-profiler checks
launch, because the sequence is on the cold start path.

### PR 4 — `today and sleep in nocturne`; PR 5 — `strain, insights, profile in nocturne`
The §4 screens; the new tab bar is in PR 5. Missing data (the Insights hint, among others) comes from MockData
placeholders plus `docs/API_REQUESTS.md`. localization-editor for the new copy. ui-validator against each board.

## Risks
- **The string catalog.** A local Xcode build re-serialised it in the user's checkout (8.7k lines, uncommitted on
  `chore/domain-ryftlab`). Every brief requires `make strings` or targeted edits, and a `--stat` check.
- **The icon render needs Satoshi Light locally.** The fonts are git-ignored; `make fonts` fetches them from
  Fontshare. The PNGs are committed, so CI does not render.
- **Pinned tests.** The gauge contrast, shots and mark tests pin today's colours; PR 1 and PR 3 re-pin them
  deliberately and say so in the PR.
