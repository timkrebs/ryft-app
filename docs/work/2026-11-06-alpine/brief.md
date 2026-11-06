# RYFT iOS — the "Alpine" redesign: monochrome, typographic, hairline — brief for `ios-lead`

The user's brief, as given on 2026-11-06. [`plan.md`](plan.md) holds his answers and the facts that differ from it.

Start from `design/alpine-light-palette` (PR #100, rebased on `main`). Read, in this order:
`CLAUDE.md`, `docs/adr/0015-monochrome-light-palette.md`, `CLAUDE_FOLLOWUP_ALPINE_LIGHT.md`
(the light pass: why PR #100 is red and what makes it green), `design/brand-board.png` (the old
look — for the orbit mark only), and the website's record of the same system in
`../plattform/web/docs/DECISIONS.md` (D18–D21) and `../plattform/web/src/styles/globals.css`
(the `--web-*` scale). The website is already live in this style; the app follows it exactly.
Reference images: run the site locally (`cd ../plattform/web && npm run dev`) and look at `/`
— the three mock screens (Today, Sleep, Strain) in the "Systems" section are the target.

## The decision (user, 2026-11-05/06)

RYFT's visual identity is now **black and white only**: Inter, Bold caps with tight tracking
for everything that is a title or a number, Regular with wide tracking for labels, 1 pt ink
rules instead of filled cards and shadows, square shapes, no gradients, no glow, no colour.
Differences that used to be hue (bands, zones, stages, severity) are **fill level, line weight
or hatching**. The hero statement is **"Engineered for peak."**; "Your whole health." stays as
the tagline under the lock-up.

Assumption to confirm with the user in your first message, then proceed: **light is the
default appearance** ("paper and ink"); **dark stays, as the exact inversion** (ink and
paper, every rule the same). If he wants light-only, drop the dark pass (§6) and set
`.preferredColorScheme(.light)`.

## Owners

ui-designer (system, specs, component code in `Design/`), ios-developer (screens, Train,
Profile, onboarding), sync-engineer only where a view model needs a new derived value,
localization-editor (every string that changes), test-engineer (pins), ui-validator (every
PR), accessibility-reviewer (contrast and non-colour cues), release-manager (icon, TestFlight
notes, CHANGELOG), reviewers per `docs/AGENT_FLEET.md`.

## 1. Tokens — `Design/Theme.swift`, `Design/Typography.swift`, `Assets.xcassets`

Light is done (ADR 0015). Add:

- **Dark (universal inversion):** Background `#000000`, Surface `#000000`, SurfaceRaised
  `#1F1F1F`, TextPrimary `#FFFFFF`, TextSecondary white 70 %, TextTertiary white 55 %,
  Separator `#FFFFFF`, Accent `#FFFFFF`, OnAccent `#000000`, AccentSecondary `#9A9A9A`,
  Warning `#7A7A7A`, Alert `#FFFFFF`, MetricStrain `#FFFFFF`, MetricSleep `#9A9A9A`, stages
  Deep `#FFFFFF`, Light `#8C8C8C`, REM `#4F4F4F`, Awake `#262626` (darkest-ink = most, i.e.
  brightest in dark). Keep Graphite/Slate/Sage/Mist/Teal as named constants; nothing new
  may use Teal.
- **Shape:** `Metrics.cardRadius = 0`, `tileRadius = 0`, `hairline = 1 / displayScale`;
  buttons square; no `shadow`, no `LinearGradient` anywhere in `Design/` (grep and remove).
- **Type:** Inter 4.1 (OFL) Regular + Bold in `Resources/Fonts/`, `UIAppFonts`,
  `scripts/fetch-fonts.sh` → `https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip`
  (commit the two files, the OFL allows it). `Typography.swift`: display / number / title /
  headline → Bold, `.textCase(.uppercase)`, tracking `−0.07 × size`; label / caption →
  Regular, uppercase, tracking `+0.08 × size`; body → Regular, sentence case, no tracking.
  Keep the style names and sizes the website's token generator reads (`web/scripts/tokens.mjs`
  parses `Typography.swift` and `Theme.swift`: weights, sizes, `.tracking(size * …)` on the
  wordmark) and run `cd ../plattform/web && RYFT_APP_DIR=.. npm run tokens:check` before
  every commit — the site's CI fails on drift.
- **Wordmark:** Inter Bold caps, tracking −0.04 em (`RyftHeader.swift`).

## 2. Components — `Design/`

- **RyftMark** unchanged in geometry; always `currentColor`.
- **OrbitGauge / MetricGauge:** arcs in ink on the `surfaceRaised` track; strain band rail a
  dashed hairline; **past the band** = the arc switches to a 45° hatch (a `Shape` clipped by
  the arc, stroke 1 pt, 3 pt pitch), never a second colour; hollow dots when pending;
  readiness number Inter Bold tight; band word in a label. `accessibilityValue` says "past
  today's band".
- **Bands** (`Theme.band(forScore:)` → `BandStyle`): high = solid ink, moderate = half ink
  (50 % fill or hatch), low = outlined (hairline, no fill). Used by tiles, rings, the Insights
  list and the widgets.
- **Charts (Swift Charts):** one ink series per chart; comparison series as hatch or dashed
  stroke; today's bar solid, the rest `surfaceRaised`; direct labels instead of legends where
  there are ≤ 3 series; axis lines hairline ink, gridlines `surfaceRaised`.
- **Sleep stages:** the four grey steps + a swatch square in every legend row (as on the web).
- **Zones:** grey steps 1–5 on bars with the zone label on the bar; hatch density 1–5 where
  there is no room for labels.
- **Cards and tiles:** hairline boxes, no fill; adjacent boxes share borders (collapse to one
  line); section headers as eyebrow `02 / SLEEP` (label style) above a Bold caps title.
- **Buttons:** primary = ink fill, paper caps label, `↗` only for external/forward actions;
  secondary = outlined; destructive = outlined (never a colour); disabled = 40 % opacity.
- **Severity (Insights):** 1-, 2-, 3-bar ink glyph; never three hues.
- **Pending / calibrating:** hairline dashed outlines and the calibration orbit filling
  night by night; no colour.

Deliverable first: `docs/work/2026-11-06-alpine/design.md` (the system in app terms: swatches
of the grey steps and hatches in both appearances, type specimen, component sheet) and the
component catalog screen updated. Build the system before touching screens.

## 3. Screens (ios-developer with ui-designer)

Each screen keeps its information and its view model; what changes is type, surfaces, colour
→ fill, and the header pattern (eyebrow + caps title + the one big number):

- **Today:** `TODAY` title, the orbit gauge in ink, seven-day bars (today solid), four stat
  tiles in a hairline 2×2 grid (recovery, sleep, strain, HRV), the band sentence as a label.
  The launch animation stays (orbit assembling), in ink.
- **Sleep:** the big hours, `ASLEEP · 94 % OF NEED` label, the stage bar in grey steps, one
  row per stage with swatch, bedtime/consistency line, seven-night bars.
- **Strain:** the big number, `OF 21 · MODERATE`, zones as labelled bars, the session that
  made it, seven-day bars.
- **Train:** plan and session lists as hairline rows; the live session's timer in Bold caps;
  set/rep inputs square.
- **Insights / Signals:** baseline band as a `surfaceRaised` band, today's value as an ink
  line, deviation with ▲▼ glyphs; severity bars.
- **Profile / Account:** hairline rows; **Export my data** primary; **Delete account**
  outlined destructive; About shows the lock-up with the tagline and, above it, the statement
  **"Engineered for peak."** in display caps.
- **Onboarding:** paper, the statement as the first screen's headline, steps `01 / 02 / 03`.
- **Widgets and Live Activity:** the same gauge in ink; small widget = gauge only.
- **App icon:** ink mark on paper (light), paper mark on ink (dark), tinted variant; regenerate
  with `make mark-svg` / the icon script and commit (`make check-mark-svg` stays green).
- **Empty, offline, gated, error states:** one sentence, one outlined button, the mark at 40 %.

## 4. Strings (localization-editor)

Band words, severity, VoiceOver values that named a colour now name the level; the statement
and any new labels in `Localizable.xcstrings` (en, de — German du-form). No other wearable
brand's name or vocabulary anywhere.

## 5. Tests (test-engineer)

Re-pin `OrbitGaugeContrastTests`, `OrbitGaugeBandTests`, `FocusedPolishTests` to the new rules
(see `CLAUDE_FOLLOWUP_ALPINE_LIGHT.md` for the exact failing assertions); add
`BandStyle` tests at the 67/34 boundaries in both appearances; a test that no view in
`Design/` references `Theme.teal`, a gradient or a shadow; snapshot-free: assert on
`BandStyle`/token values, not pixels.

## 6. Dark (last PR)

Apply the inversion tokens from §1; every component already reads tokens, so this PR should
be colour sets, the icon's dark variant and a validation pass. Keep "dark theme first" out of
`CLAUDE.md` afterwards and write the new rule there: light default, dark inverted.

## Rules that do not bend

`ryft-app-conventions`: never edit the pbxproj by hand; previews for every screen in light and
dark with `Preview/MockData.swift`; build with zero warnings; strings via xcstrings; Dynamic
Type up to accessibility sizes and Reduce Motion for every animation; no keys in Swift. Never
commit to `main`; one PR per step below, `area: what changed` titles, `CHANGELOG.md →
Unreleased` for anything users see. No attribution lines or links in commits or PRs.

## PRs, in order (each shippable, each validated by ui-validator in greyscale screenshots)

1. `design: light pass` — finish PR #100 per `CLAUDE_FOLLOWUP_ALPINE_LIGHT.md` (tests, icon
   SVG), merge.
2. `design: inter, square shapes, hairline surfaces` — §1 type + shape, Wordmark, buttons,
   cards, catalog; `tokens:check` on the web still green.
3. `design: ink gauges and charts` — §2 gauges, bands, charts, stages, zones, severity.
4. `today, sleep, strain in the alpine system` — §3 first three screens + widgets.
5. `train, insights, profile, onboarding, icon` — the rest of §3, the statement, the icon.
6. `design: dark as the inversion` — §6, then update `CLAUDE.md`.

## Done when

All six merged; `make lint` and `make test` green; a TestFlight build cut by release-manager
with notes that say what changed and why; `docs/STATUS.md` updated; ADR 0015 marked complete
and a short ADR 0016 for the dark inversion; the website's `tokens:check` still green against
`main` (then remove the temporary `ref:` in `../plattform/.github/workflows/ci.yml`).
