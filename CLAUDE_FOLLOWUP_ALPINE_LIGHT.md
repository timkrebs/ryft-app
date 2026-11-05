# RYFT iOS — the monochrome light pass ("Alpine") — brief for `ios-lead`

Run: `claude --agent ios-lead` → "Run `CLAUDE_FOLLOWUP_ALPINE_LIGHT.md`". Branch: continue on
`design/alpine-light-palette` (PR #100), which already carries the palette and ADR 0015. Owners:
**ui-designer** (§1, §2, the design note), **ios-developer** (§1–§3), **test-engineer** (§4),
**ui-validator** (§5), **localization-editor** (§3 strings); reviewers per `docs/AGENT_FLEET.md`.
The website has already moved (`timkrebs/ryft-platform` #142/#143, spec in the RYFT project
doc `docs/ALPINE_STYLE.md`); the app follows the same system.

## Where PR #100 stands

The light colour sets are monochrome (ADR 0015 §1–2). CI is red for exactly the reasons the ADR
lists as follow-ups:

- `make lint` → `check-mark-svg`: `design/ryft-app-icon-light.svg` is generated from the light
  colours and is out of date. Run `make mark-svg`, commit the SVG (and the PNG icons if
  `make icon` derives from it).
- `OrbitGaugeBandTests.theColourPastTheBandIsAlertAndReachesThreeToOneOnTheTrack`,
  `OrbitGaugeBandRenderTests.midGlideTheArcInsideTheBandIsNeverAlert`: `Alert` and `Accent` are
  both `#000000` in light now, so "past the band is alert" and "inside the band is never alert"
  can no longer be told apart by colour.
- `OrbitGaugeContrastTests.arcsAndDotsReachThreeToOneOnTheirTrack` / `theRailsOpacityIsPinned…`:
  metric arcs are grey steps on `#EBEBEB` in light; Sleep `#6B6B6B` passes 3:1, lighter steps
  don't, and the rails' pinned opacity no longer gives the expected ratio over a black separator.
- `OrbitGaugeContrastTests.pendingOpacityIsPinnedAndIntentionallyBelowThreeToOne`: pending uses
  `textTertiary` at 0.6; black at 0.55 × 0.6 on white is no longer below 3:1.
- `FocusedPolishTests.theWarmUpMark(scheme:)`: the warm-up mark's colour expectation in light.

These are design decisions, not test fixes. Make them, then update the pins.

## 1. Level by ink, not by hue (ui-designer → ios-developer)

Monochrome means every scale the app shows reads by **fill level, line weight or hatching**, never
by colour alone:

- **Readiness / recovery bands** (`Theme.band(forScore:)`): high = solid ink, moderate = 50 %
  ink (or a 45° hatch at ink), low = outlined (hairline ring, no fill). The number stays the
  truth; the band word under it stays. Both appearances get the same rule; dark simply inverts
  ink and paper when its pass comes.
- **Orbit gauge**: arcs in ink on the `surfaceRaised` track; the strain band rail is a dashed
  hairline; "past the band" is the arc switching to the **hatched** texture (and the
  `accessibilityValue` saying so), not a red segment. Dots hollow when pending (as today).
- **Heart-rate zones** (`Theme.zones`): five grey steps are fine on a bar chart *with* the zone
  label on each bar; for the ring/legend use hatch density 1–5. Sleep stages keep the four grey
  steps (`StageDeep … StageAwake`) — darkest = deepest — plus the swatch in every legend row.
- **Destructive actions** (Delete account, Revoke, Discard): outlined ink button with the
  label; confirmation sheet unchanged. `Theme.alert` stays `#000000`; nothing may rely on
  `alert != accent` any more.
- **Insights severity**: info / notice / warn as a 1-, 2-, 3-bar glyph in ink, not three hues.
- Warning (`#8A8A8A`) is a **mark** colour (bars, borders), never a text colour (3.3:1).

Deliverable: `docs/work/2026-11-06-alpine-light/design.md` with the rules, a swatch sheet of the
grey steps and hatches, and light-mode previews of Today, Sleep, Strain, Insights and Profile.

## 2. Type and shape (ui-designer → ios-developer)

- **Inter** replaces Satoshi: `Typography.swift` → `RyftFonts.postScriptName` maps to
  `Inter-Regular` / `Inter-Bold` (Medium → Bold for the display, number and title styles; Regular
  elsewhere), `Info.plist` `UIAppFonts`, `scripts/fetch-fonts.sh` → Inter 4.1 from
  `https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip` (OFL — the files may be
  committed; the web did, with `OFL.txt`). Display styles get `.tracking(-0.07 * size)`, labels
  `+0.08 * size`, all caps on display and section labels (`ryftLabelStyle` already uppercases).
- **Radii to 0**: `Theme.Metrics.cardRadius = 0`, `tileRadius = 0`; cards become hairline boxes
  (`separator` is full ink now, 1 pt). Buttons square. The orbit mark itself is unchanged.
- **Wordmark**: Inter Bold, caps, tracking −0.04 em (`RyftHeader.swift`, `Wordmark`); the web's
  `tokens.mjs` reads `.tracking(size * …)` from it, so keep that form.
- Hero statement for onboarding / About / the TestFlight screenshots: **"Engineered for peak."**
  (the user's choice; "Your whole health." stays the tagline under the lock-up for now).

## 3. Strings (localization-editor)

Band words, severity labels and any VoiceOver text that named a colour ("red", "green") now
name the level ("solid", "half", "outlined" is for sighted users; VoiceOver says "high / moderate /
low"). English and German, `Localizable.xcstrings`.

## 4. Tests (test-engineer)

- Re-pin `OrbitGaugeContrastTests` and `OrbitGaugeBandTests` to the new rule: arcs and dots in
  ink ≥ 3:1 on the track; the hatched "past the band" state is detected by texture flag, not by
  colour; pending opacity pinned to whatever §1 decides (and the test's "intentionally below 3:1"
  claim rewritten to what is intended now).
- A test per fill level: `Theme.bandStyle(forScore:)` (or whatever §1 names it) returns
  solid / half / outlined at 67 / 34 boundaries, in both appearances.
- `FocusedPolishTests.theWarmUpMark` for the light colour.
- Keep `make check-mark-svg` green: regenerate, don't hand-edit.

## 5. Validate (ui-validator)

Build, demo mode in the simulator, **light** mode first, then dark (unchanged): Today, Sleep,
Strain, Insights, Train live session, Profile → Account (destructive button), onboarding; English
and German; large Dynamic Type; the colour-blind simulator is moot now, but check that every
scale is distinguishable in greyscale screenshots. Compare with the web preview's mock screens
(the Today / Sleep / Strain figures on ryftapp.de's new home) — same hierarchy, same values.

## Out of scope

The dark appearance (its own pass after this one merges), the website, the Band.

## Done when

`make lint` and `make test` green on `design/alpine-light-palette`, PR #100 updated with the
design note and screenshots, CHANGELOG → Unreleased mentions the light redesign, ADR 0015 §4
items ticked or moved to the dark-pass ADR.
