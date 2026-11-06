# Alpine: the design system (PR 0)

Owner: ui-designer. Reads with [`plan.md`](plan.md) (wins any conflict), [`brief.md`](brief.md), and [`architecture.md`](architecture.md)
(ios-architect: how values are stored and resolved, which this note does not design).
Sources: ADR 0015, `CLAUDE_FOLLOWUP_ALPINE_LIGHT.md`, `docs/work/2026-10-29-orbit-gauge/design.md`,
`docs/work/2026-11-04-focused-session/design.md`.

Spec only. No app code, no swatch sheet and no previews yet; section 12 says what the catalog must show.
Every number was computed from the colour values in the brief and on this branch (WCAG 2.x relative luminance; text
composited over its ground in gamma sRGB, as the tests do), not copied. Nothing was rendered, so the first render is the first check.

## 0. What this is

RYFT is black and white in both appearances. **One system, no second look in the code:** light is paper and ink, dark is the
inversion (ink on paper becomes paper on ink), and every rule below is written once. Where a number differs by appearance, both
are given. Dark's colour values are the brief's §1; they are checked in section 1.2.

The dark appearance only changes colour. Between PR 2 and PR 6 dark carries the new type and shape with the old hue colours
(`plan.md`); nothing here is gated by appearance except colour values.

### 0.1 Which section lands in which PR

| PR | Title | Sections of this note |
| --- | --- | --- |
| 0 | Design system | this note, and the catalog (section 12) |
| 1 | `design: light pass` (#100) | 1.1, 3 (the pins, minimal), 4.7 (warning and alert as text), 7 (W mark), 8.1 first row, 10 (strings that name a colour only) |
| 2 | `design: inter, square shapes, hairline surfaces` | 5 (type, shape, rules, buttons, tab bar, shared borders, header component), 2 (the ladder as a drawing primitive, if the catalog needs it) |
| 3 | `design: ink gauges and charts` | 2, 4 (all scales), 6 (charts), 3 (the pins, final), 1.3 |
| 4 | `today, sleep, strain in the alpine system` | 8.1 to 8.3 (screens), 9 (widgets, Live Activities) |
| 5 | `train, insights, profile, onboarding, icon` | 7 (Focused), 8.4 to 8.7, 9.1 (icon), 11 (hero), empty states 8.8, Welcome and auth stop forcing dark |
| 6 | `design: dark as the inversion` | 1.2 (dark colour sets and their decisions), 9.1 (icon dark and tinted), the default flips to light |

### 0.2 Where the brief, the ADR and the old notes are wrong or incomplete

| # | Claim | What the code and the maths say |
| --- | --- | --- |
| 1 | "metric arcs are grey steps on `#EBEBEB`; Sleep `#6B6B6B` passes 3:1, lighter steps don't" | Of the three arcs only Sleep is grey. Recovery and Strain are `#000` (17.62:1 on the track). Sleep `#6B6B6B` is **4.47:1**, stage Light `#7A7A7A` **3.60:1**; both pass. Failing on the track: `#8A8A8A` 2.90, `#B5B5B5` 1.72, `#E0E0E0` 1.11. The one entry that fails `arcsAndDotsReachThreeToOneOnTheirTrack` is **"band moderate (warning)"**: `#8A8A8A` is 2.90:1 on the track. |
| 2 | "Warning `#8A8A8A` (3.3:1)" | 3.45:1 on white, 2.90:1 on the track. The rule (a mark, never text) stands. |
| 3 | ADR 0015: secondary text "5.9:1", tertiary "4.7:1" | **6.20:1** and **4.76:1** on white. Tertiary on the active-row tint (`#E6E6E6`) is **4.49:1**, which fails by 0.01 (section 7). |
| 4 | "the rails' pinned opacity no longer gives the expected ratio over a black separator" | No separator is involved. The rail is `metricStrain` at 0.5 over the background; black at 0.5 on white is **3.95:1**, and the test asserts `< 3`. |
| 5 | "pending uses `textTertiary` at 0.6" | Pending marks use the arcs' own colours at 0.6; only the number is `textTertiary`. The test fails on the **Strain** arc (black at 0.6 is 5.74:1; the test asserts `< 3`). |
| 6 | "Dots hollow when pending (as today)" | Today a pending gauge draws the previous day exactly as scored (filled dots) at 0.6; dots are hollow only for a missing score or with no previous day. Section 4.2 follows the brief's §2 and makes pending hollow and dashed. |
| 7 | "VoiceOver text that named a colour" | None exists. Band words are High / Moderate / Low and "past today's band" already speaks the past-band state. One string names a colour (section 10). |
| 8 | The failing list | Incomplete. `scripts/check-shared-types.py` reports **7 problems**: the widget's `Accent`, `Alert`, `MetricSleep`, `MetricStrain`, `SurfaceRaised`, `TextTertiary`, `Warning` colour sets still hold the old light values. PR 1 copies the app's values (`plan.md`). |
| 9 | `separator` is "full ink, 1 pt" | True, and it breaks 8 call sites that use `separator` as a **fill or gridline** and thickens 39 row dividers (section 5.5). |
| 10 | Radii to 0 turns cards into hairline boxes | Only the 56 shapes that read `Theme.Metrics.cardRadius` / `tileRadius` change. 148 other `Capsule()`, `Circle()` and literal `RoundedRectangle(cornerRadius: n)` calls outside previews ignore it (section 5.3). |
| 11 | "`hairline = 1 / displayScale`" and "1 pt ink rules" | Two different widths in one brief. 1 device pixel is 0.33 pt at 3x: a card edge that thin is not "1 pt", and the row rule (20 % ink) would vanish. This note keeps **1 pt** for edges and rules and uses `1 / displayScale` for nothing (**decision D3**). |
| 12 | "caption → Regular, uppercase, +0.08 em" | Captions carry sentences (hints, errors, dates, "Zones in % of heart-rate reserve"). Upper case plus tracking would shout every one, and German runs about 30 % longer. This note keeps captions in sentence case and uppercases `label` only (**decision D7**). |
| 13 | "The website is already live in this style" | It is not (`plan.md`). Section 13 records what is on this Mac and what is only on a branch. |
| 14 | `tokens.mjs` "keeps working" | It matches `\.tracking\(size \* ([\d.]+)\)` and `\.tracking\(([\d.]+)\)`; a negative factor or `0.08 * size` makes it throw. Platform changes `tokens.mjs:188` or the wordmark needs another form (`plan.md`). Recorded in PR 2's `tokens:check`. |

### 0.3 What I needed from `docs/ALPINE_STYLE.md` and did not have

Not on this machine. Where I needed a value I decided it and marked it **(mine)**: the hatch pitch and weight (the brief gives
"45 deg, 1 pt, 3 pt pitch" for the gauge only), the outlined buttons' weight, the row rule, the display tracking per style, the hero's
size. The web's `docs/ALPINE_STYLE.md` may disagree with any of them; the first render settles it.

## 1. Tokens and what they reach

### 1.1 Light (ADR 0015, in place on this branch)

Ground: `background` / `surface` `#FFFFFF`; track `surfaceRaised` `#EBEBEB`; active-row tint = ink at 0.10 over white = `#E6E6E6`.

| Ink | On `#FFFFFF` | On track `#EBEBEB` | On tint `#E6E6E6` | Use |
| --- | --- | --- | --- | --- |
| `textPrimary` `#000` | 21.00 | 17.62 | 16.75 | values, labels |
| `textSecondary` (62 %, `#616161`) | 6.20 | 5.85 | 5.74 | secondary text |
| `textTertiary` (55 %, `#737373`) | 4.76 | 4.56 | **4.49 (fails)** | captions, dashes. Allowed on `background` and on the track; **not on any tint of 10 % or more**, not on a pressed or flashing fill |
| `#000` accent / alert / strain / Deep | 21.00 | 17.62 | | marks |
| `#6B6B6B` Sleep, accentSecondary | 5.33 | 4.47 | | marks |
| `#7A7A7A` Stage Light | 4.29 | 3.60 | | marks |
| `#8A8A8A` Warning | 3.45 | **2.90** | | **marks on `background` only**; never text; never on the track |
| `#B5B5B5` Stage REM | 2.05 | **1.72** | | fill, with an ink edge |
| `#E0E0E0` Stage Awake | 1.32 | **1.11** | | fill, with an ink edge |
| `#EBEBEB` track | 1.19 | 1.00 | | the empty scale; never information |

### 1.2 Dark (brief §1: the inversion), checked

Ground: `background` / `surface` `#000000`; track `surfaceRaised` `#1F1F1F`; active-row tint = white at 0.10 over black = `#1A1A1A`;
row rule = white at 0.20 over black = `#333333`. Secondary `#FFFFFF` at 70 % = `#B3B3B3`; tertiary at 55 % = `#8C8C8C`.

| Ink | On `#000000` | On track `#1F1F1F` | On tint `#1A1A1A` | On rule `#333333` | Use |
| --- | --- | --- | --- | --- | --- |
| `textPrimary` `#FFF` | 21.00 | 16.48 | 17.49 | 12.63 | values, labels |
| `textSecondary` (70 %) | 9.96 | 8.66 | 9.03 | 7.08 | secondary text |
| `textTertiary` (55 %) | 6.27 | 5.87 | 6.04 | 5.02 | captions, dashes |
| `#9A9A9A` Sleep, accentSecondary | 7.46 | 5.86 | | | marks |
| `#8C8C8C` Stage Light | 6.25 | 4.90 | | | marks |
| `#7A7A7A` Warning | 4.89 | 3.84 | | | marks (kept "never text" so the rule is one rule) |
| `#4F4F4F` Stage REM | **2.56** | **2.01** | | | fill, with an ink edge |
| `#262626` Stage Awake | **1.39** | **1.09** | | | fill, with an ink edge |
| `#1F1F1F` track | 1.27 | 1.00 | | | the empty scale; never information |

Other dark pairings: stage neighbours Deep-Light 3.36, Light-REM 2.44, REM-Awake 1.85 (light: 4.89, 2.09, 1.55); Sleep `#9A9A9A`
against Light `#8C8C8C` 1.20 (light 1.24). The dimmest grey that reaches 3:1 on black is `#5A5A5A` (on the track `#696969`), 4.5:1 `#757575`.

What the inversion does **not** preserve, and what to do:

| What fails in dark | Value | Smallest fix | Token change? |
| --- | --- | --- | --- |
| Stage REM as a graphic | 2.56:1 on black, 2.01 on the track (<3) | Second cue, as in light: 1 pt paper-ink (white) edge on every stage fill, stage = row in the hypnogram, label in every legend row | none |
| Stage Awake as a graphic | 1.39:1 on black, 1.09 on the track | same | none |
| Sleep arc while pending | `#9A9A9A` at 0.6 over the track is **2.99:1** (2.26 at the breath's trough) | Pending is drawn in dashed ink outlines (section 4.2): no grey, no opacity floor problem | none |
| "Unstaged asleep" `#9A9A9A` against Light `#8C8C8C` | 1.20:1 | H2 hatch with an edge, as in light (section 4.5) | none |
| Flash fill (rest pill, 250 ms) white 0.25 = `#404040` | primary 10.41, secondary 6.07, **tertiary 4.43** | the flash carries `textPrimary` only (light `#BFBFBF`: primary 11.44, secondary 4.93, **tertiary 4.00**) | none |
| Disabled at 40 % | white 40 % on black 3.66; ink 40 % on white **2.85** | disabled controls are exempt from the contrast minimum; the label stays legible; it is not information | none |
| White hatch on black reads heavier than black on white | (irradiation; not a ratio) | Check H2 and H3 on the swatch sheet at 3x; if H3 reads as H4, dark hatch lines drop 0.5 pt (catalog decision, no user decision) | none |

Everything else in dark clears more than light does: secondary 9.96 vs 6.20, tertiary 6.27 vs 4.76, tertiary on the tint 6.04 vs the
light failure of 4.49. The brief's dark secondary (70 %) differs from light's (62 %); it is not an exact mirror and does not need to
be (both clear 4.5 on every ground in use).

**Decision D1 (needs the user).** The brief's stage greys leave REM and Awake under 3:1 in both appearances (light 2.05 and 1.32, dark 2.56 and 1.39). I recommend keeping the tokens and relying on the edge, the row and the label. Lifting REM to `#5A5A5A` (3.04:1 on black) would fix one step, but Awake would then sit between REM and the track and the four steps would collapse; I can't offer a token set that is better, only this trade. It is repeated in section 14.

### 1.3 Consequences used below

- **A grey step is a category or an order, never the only carrier.** Every grey fill has an ink edge, a label or a position.
- **Tracks are the empty scale, not information.** They are `surfaceRaised` everywhere (the brief), 1.19:1 on white and 1.27:1 on
  black. The arc's end, the number and VoiceOver carry the value. A track that implies a count ("Step 2 of 5") has the text.
- The tint recipes `accent.opacity(0.10...0.14)` keep working in both appearances (a grey of 10 to 14 % ink behind ink). They look like
  `surfaceRaised`; the label tells a tinted control from a raised one.

## 2. The ladder: one vocabulary for levels

An ordinal level is drawn the same way everywhere, in **ink**, which is `textPrimary`: black on white, white on black.

| Step | Looks like | Ink coverage |
| --- | --- | --- |
| L0 | outline only: 1 pt ink edge, empty inside | 0 % |
| H1 | 45 deg hatch, 1 pt line, 8 pt pitch | 12.5 % |
| H2 | 45 deg hatch, 1 pt line, 4 pt pitch | 25 % |
| H3 | 45 deg hatch, 2 pt line, 4 pt pitch (fine: 1 pt line, 2 pt pitch) | 50 % |
| H4 | 45 deg hatch, 3 pt line, 4 pt pitch | 75 % |
| H5 | solid ink | 100 % |

Hatch rules **(mine)**: lines run bottom-left to top-right ("/"), 45 deg to the horizontal in screen space, not along an arc; pitch is
measured perpendicular to the lines; the pattern is clipped to the shape and anchored to the shape's own origin so it does not swim
when the shape grows; the clip edge always gets a 1 pt ink outline (without it H1 and H2 have no visible boundary). Weights and
pitches are whole points so they land on whole pixels at 2x and 3x. The **fine** variant (half weight, half pitch) is for shapes under
12 pt in their short side (a 5.5 pt arc, a 10 pt swatch) and only exists for H3 and H5. The brief's gauge hatch (1 pt, 3 pt pitch,
33 %) is not a step of this ladder; the gauge uses fine H3 (1 pt, 2 pt pitch, 50 %) because 33 % is too close to H2 at 5.5 pt wide.
No text is ever set on a hatch: labels sit beside or above.

The steps are told apart by pitch and weight, not by tone. Mean luminance of H1 to H5 is 0.875, 0.75, 0.5, 0.25, 0, so neighbours
are 1.16:1 to 1.8:1 as tones and 6:1 only between H4 and H5. **Every use below therefore also has a word, a label or a position.** That
is the honest limit of greyscale ordinal coding: a second cue, never the only one.

## 3. The failing pins: the decision that replaces each

This section is for test-engineer and ios-architect. "Needs" is the design decision a pin cannot be written without; section 3.1 says
which PR can carry it.

| Test | Why it fails | Decision that replaces it | New pin | Needs |
| --- | --- | --- | --- | --- |
| `OrbitGaugeBandTests.theColourPastTheBandIsAlertAndReachesThreeToOneOnTheTrack` | asserts `strainPastBand == alert`, apart from `strain`, 3:1 | Past the band is **a texture, never a colour** (4.2) | `strainTone == .pastBand` iff strain > clamped upper end (existing tone tests); the textured stretch's ink `>= 3` on the track and the background in both appearances; no colour comparison | the "texture, not colour" decision |
| `OrbitGaugeBandRenderTests.midGlideTheArcInsideTheBandIsNeverAlert` | samples colour at 77 pt radius | same geometry, new signal: **ink coverage** | behind the split (`degrees < split - 4`) a 6 deg window has stroke coverage `>= 0.95`; past it (`> split + 4`), `.large` dial only, coverage in `0.35...0.65` | PR 1: the first half only (nothing is hatched yet); PR 3: the second half, which needs the hatch drawing (2, 4.2) |
| `OrbitGaugeContrastTests.arcsAndDotsReachThreeToOneOnTheirTrack` | the "band moderate (warning)" entry: `#8A8A8A` 2.90 on the track | The centre ring's levels are **ink in different shapes** (4.1): the list becomes Recovery, Sleep (`#6B` 4.47 / dark `#9A` 5.86), Strain, band high, moderate, low, past-band ink; the `textTertiary` no-readiness entry goes (no ring is drawn) | each `>= 3` on the track and the background, both appearances | colour only (ink); the shapes can follow in PR 3 |
| `OrbitGaugeBandTests.theRailsOpacityIsPinnedAndItsRatioStaysAboveTwo` (the brief files it under `OrbitGaugeContrastTests`) | rail 0.5 gives 3.95:1; the test asserts `< 3` | the rail is a **full-ink dashed hairline** (4.2); opacity 1 | `bandRailOpacity == 1`; rail ink `>= 3` on both grounds (21.00 / 17.62 light, 21.00 / 16.48 dark); stroke `>= 1`; the "sub-3:1 on purpose" claim is deleted | one constant, trivial |
| `OrbitGaugeContrastTests.pendingOpacityIsPinnedAndIntentionallyBelowThreeToOne` | asserts the Strain arc at 0.6 is `< 3` (it is 5.74) | final: **pending is a dashed hairline outline, no opacity** (4.2); interim for PR 1: `pendingOpacity` stays 0.6 and the drawing is untouched (`architecture.md` §5.1) | final: `pendingOpacity` no longer exists; every pending mark is ink `>= 3` on the track; the breath's floor (0.6) keeps it `>= 3` (light 5.44, dark 6.72 over the track); the number `>= 4.5`. Interim: the pin in `architecture.md` §5.1, in both appearances | interim: the pin only; final: the dashed drawing |
| `FocusedPolishTests.theWarmUpMark(scheme:)` | `Theme.warning` on `background` is 3.45:1 in light | the W is **`textSecondary` in both appearances** (7) | `W` ink `>= 4.5` on `background`, on the active-row pill over the tint and on the track, both schemes (light 6.20 / 5.74 / 5.85, dark 9.96 / 9.03 / 8.66); the same token for `TrainHistoryView` 154 | a token choice, no drawing |

Also needed (not in the brief's list): `check-shared-types` (the 7 widget colour sets), `make mark-svg`, the `FocusedRowInk` comments
and its `scheme == .light` branches (7), and the band-level test the brief names (`BandStyle` in `Shared/`, `architecture.md`):
solid / half / outlined at 67 and 34, `(66, 67)`, `(33, 34)`, `nil`, in both appearances.

### 3.1 PR 1's scope problem, for sequencing

`CLAUDE_FOLLOWUP_ALPINE_LIGHT.md` asks PR 1 to re-pin the gauge tests, but the brief puts the gauges in PR 3. Which pin needs which
decision, and the smallest honest PR 1:

| Pin | Can PR 1 pin it without the PR 3 drawing? | Smallest PR 1 |
| --- | --- | --- |
| `theWarmUpMark` | yes: a token | W is `textSecondary` |
| `theRailsOpacity...` | yes: a constant | `bandRailOpacity = 1`; width and dash can wait |
| `arcsAndDots...` | yes, as colour only | palette `moderate` and `low` become ink; high, moderate and low are then the same colour in the ring until PR 3 draws the shapes. The band word stays under the gauge, so nothing is unlabelled, but the ring is temporarily a single level |
| `pendingOpacity...` | yes, interim | keep 0.6, with the drawing untouched; replace the assertions and the test's name as `architecture.md` §5.1 sets out |
| `theColourPastTheBand...` | partly | the palette stops exposing a colour for "past"; the tone tests stay; **no hatch is drawn yet, so "past the band" is invisible in PR 1**: the strain arc keeps its ink and only VoiceOver and the rail's end say it |
| `midGlide...NeverAlert` | half | nothing is disabled. PR 1 keeps the half that holds without a hatch: behind the split the stroke coverage is `>= 0.95` in light (dark keeps its colour check until PR 6). PR 3 adds the half past the split, which needs the drawing |

My recommendation for ios-architect: PR 1 takes the five cheap pins above and the first half of `midGlide`, and disables nothing; PR 3 adds the second half
of `midGlide` and replaces the interim pending pin. The alternative (draw the hatch in PR 1) moves the gauge work the
brief assigned to PR 3 and leaves PR 1 with no clean boundary. The interim states in PR 1 (one-level ring, invisible past-band) are
visible regressions in a gauge that is already unusual in grey; they last until PR 3 and the PR description should say so.

## 4. Level by ink, every scale (PR 3)

### 4.1 Readiness and recovery bands (`Theme.band`, `MetricSpec.scoreBand`, `OrbitGaugePalette.band`)

Boundaries unchanged: 67 and up high, 34 to 66 moderate, below 34 low. (`MetricSpec.thresholds` `[33, 67]` puts the gauge tick at 33
while the band starts at 34; a pre-existing one-point mismatch, noted, not changed.)

| Level | Rule | Ink | Word still there |
| --- | --- | --- | --- |
| High | solid | H5 | the score and "High" |
| Moderate | hatched | H3 (fine below 12 pt) | the score and "Moderate" |
| Low | outlined | L0 | the score and "Low" |
| No score | nothing drawn in the band's place; only the track | | the dash, "No data" |

Why hatch and not a flat 50 % grey for moderate: `#808080` is 3.95:1 on white and 3.31:1 on the track, so it passes, but grey is
already the Sleep and stage language. Hatch is reserved for "a level between". No score draws nothing instead of today's
`textTertiary` ring because a solid 55 % ink ring would read as "high, but dim".

**Band mark** (new, used wherever the band word appears): a 10 x 10 pt square, radius 0, 1 pt ink edge; inside it L0 / fine H3 / H5,
6 pt before the word ("[mark] HIGH"). On the orbit caption, the Recovery tile, `MetricGauge`'s band line, the Insights list, the
widgets' text variants. It grows with the caption (14 pt at AX1 and up) and is hidden from VoiceOver; the word is the label.

**Orbit centre ring** (4.5 pt stroke at the 160 dial, radius 32): a hatch does not fit in 4.5 pt, so the ring carries the same three
levels as stroke forms.
- High: solid 4.5 pt ring.
- Moderate: the same ring, butt caps, **16 dashes and 16 gaps** (11.25 deg on, 11.25 deg off at every dial size), the seam in the
  middle of a gap at 12 o'clock.
- Low: **outlined**: two 1 pt ink circles at `centre +/- stroke/2` (2.5 pt clear between them at 160, showing the track). Where the
  stroke is under 3.5 pt (dial under 124; `.medium` 112 has 3.15) the outline would close up, so low is **one 1 pt circle on the centreline**.
- Contrast: every mark is ink (21.00 on white and black; 17.62 and 16.48 on the track).
- The widget draws the same ring from `Shared/OrbitGaugeDrawing.swift`; accessory widgets are rendered by the system in vibrant
  monochrome, where only luminance survives, so the shapes (solid / dashed / outlined) are what carries the level there.

`MetricGauge` (the Strain-tab dial, 6 pt stroke, butt caps): the arc is ink. For a banded metric the same three treatments (solid /
fine H3 / outlined). Strain has no good or bad band and is solid ink. Its `target` arc (today `spec.color` at 0.35, 2.44:1) becomes
**an outlined arc on the track** (two 1 pt ink edges, butt ends) under the value arc.

### 4.2 Orbit gauge: arcs, tracks, rail, past the band, pending, calibrating

Orbit colours: Recovery and Strain ink; Sleep `#6B6B6B` (light) / `#9A9A9A` (dark), 4.47 / 5.86 on the track. Orbits are told apart by
position (inner left, inner right, outer); the grey Sleep arc is an extra cue, not the cue. Tracks `surfaceRaised`.

- **Strain band rail**: a dashed hairline in full ink: 1 pt (floor 1 pt, scaled above that), butt caps, dash 3 on / 2 off at the 160
  dial (scaled by dial / 160, never under 2 / 1.4 pt), centreline radius 69.5, the same dot cut-out. Opacity 1. Air to the outer ring's
  inner edge (74.25) is 4.25 pt and to the inner dots (63) 6 pt. Not drawn under a 90 pt dial. Dashed means "the scale of the target",
  as `ChartStyle.baseline` does.
- **Past the band** (strain above the clamped upper end): the arc past the split and its dot turn **hatched** (the brief: "never a second colour").
  - Dial 131 and up (stroke 4.5 pt or more: `.large`, the widget's `systemSmall`): the stretch from the split to the head is an
    **outlined arc**: 1 pt ink edges both sides, butt end at the split, round cap at the head, filled with **fine H3** (1 pt lines,
    2 pt pitch). At 160 that is 1 pt edge, 3.5 pt of hatch, 1 pt edge. The dot is a 1 pt ink circle with fine H3 inside.
  - Under 131 (`.medium` 3.85 pt stroke, `.small`) hatch would be mush, so the stretch is a **dashed solid arc**: butt caps, dash
    1.2 x stroke on, 0.8 x stroke off; the dot stays solid with a 1 pt inner ring in the ground colour.
  - `OrbitStrainArc` (one arc drawn twice, clipped at the split by `OrbitWedge`) stays; "past" changes from a colour to a texture. The tone
    decision and the speech ("past today's band") are unchanged, except that PR 1 renames the sentence to the brief's wording.
- **Pending** (the brief: "hairline dashed outlines", "hollow dots when pending"). With a previous day, its marks are drawn as
  **dashed outlines, no fill**: arcs of dial 131 and up as outlined arcs whose two 1 pt edges are dashed (3 on, 2 off); smaller dials as one dashed 1.5 pt
  centreline stroke; dots hollow with a dashed 1.25 pt edge (2 pt at 160); the centre ring is **one dashed 1 pt circle** (the band belongs
  to a scored day, so none is shown); the number in `textTertiary`. The breath (opacity 1.0 to 0.6) stays; at 0.6 ink is 5.74 on white and
  7.37 on black, 5.44 and 6.72 over the track, so every pending mark clears 3:1 at all times. A **dashed** edge means "not final";
  a **solid** edge means the low level, so the two do not collide. With no previous day: three hollow dots (same dashed edge) and the dash
  in the number's place. `pendingOpacity` (0.6 as a group opacity) is deleted; the breath keeps a floor constant of 0.6.
- **Calibrating**: the filled segments are ink on the track (the orbit "filling night by night"); unfilled segments are the track. Unchanged
  apart from colour. The count and VoiceOver sentences are unchanged.
- Pending without a previous day, calibrating and pending never use a spinner.

### 4.3 Heart-rate zones (`Theme.zones`, `ZoneBar`)

Today's light zones are `[E0, 6B, 000, 8A, 000]`: Z3 and Z5 are both black, Z2 and Z4 are 1.54:1 apart, and the order is not monotone.
They become the ladder: **Z1 H1, Z2 H2, Z3 H3, Z4 H4, Z5 H5**.

- Bar: 16 pt high (was 10), radius 0, 1 pt ink outline, **1 pt ink vertical rules** between segments instead of the 2 pt gaps. Widths
  stay proportional to minutes. Order is fixed Z1 to Z5 from the left, so position says the zone when a segment is too narrow for its texture.
- The **zone label sits directly above its segment** (`Z3`, with the minutes under it in the legend) wherever the segment is at least
  26 pt wide; nothing is set on the hatch.
- Legend: five columns as today; the swatch is a 16 x 16 square with the same hatch and a 1 pt ink edge; "Z1", the minutes, the heart-rate-reserve range.
- VoiceOver unchanged ("Zone 3: 18 min").

**Decision D2 (needs the user), a departure from the brief.** The brief says grey steps 1 to 5 with the zone label *on* each bar and
hatch only where there is no room. I use hatch for every zone and put the label above. Reasons: a label on a grey step has to flip
between ink and paper (an ink label on `#4D4D4D` is 2.5:1), neighbouring greys are only 1.2:1 to 1.8:1 apart, and the legend swatch
must be the same encoding as the bar. If you prefer the brief's greys, the label on the bar flips at Z4 and the legend swatches
carry the hatch as well.

### 4.4 Destructive actions, buttons

`Theme.alert` is ink in both appearances; nothing may rely on `alert != accent`.

| Button | Fill | Edge | Label | Pressed |
| --- | --- | --- | --- | --- |
| Primary | ink | none | paper, Bold caps | invert (paper fill, ink label, 1 pt ink edge) |
| Secondary | ground | 1 pt ink | ink, Bold caps | ink fill, paper label |
| Destructive | ground | **2 pt** ink **(mine)** | ink, Bold caps, always a verb ("Delete", "Withdraw") | ink fill, paper label |
| Disabled | any of the above at **40 %** opacity | | | none |

- Label: `callout` 14, **Bold, uppercase, tracking +0.04 em (mine)**, min height 44 (56 for the Focused buttons), `lineLimit(1)` with
  `minimumScaleFactor(0.8)` as today, wrapping at AX sizes. Radius 0. The press scale (0.97) is dropped; a square that shrinks reads as a bug.
- **`↗`** (SF Symbol `arrow.up.right`, label weight, after the label, hidden from VoiceOver) only on actions that leave the screen
  for another app, Safari or Settings, or that start a flow in a sheet from a primary button: "Open Health ↗", "App in the App Store ↗",
  "Open Settings ↗", "Privacy Policy ↗", "Export my data ↗" (share sheet). Never on Save, Done, Cancel, or a destructive button.
- Three tiers by shape and weight, none by hue: filled ink, 1 pt outline, 2 pt outline. In Profile -> Account the three stack:
  Change password and Log out are secondary, **Delete account is the only 2 pt one**, and "Delete" is in its label. Export my data is primary (brief §3).
- The confirmation dialogs and alerts are **system-drawn**; their destructive buttons stay system red. That is the OS's (`plan.md`),
  unchanged by the brief, and the one place a hue remains. Menus keep system drawing. The one themed swipe reveal (`ExerciseCard`,
  List layout) becomes ground fill, 2 pt ink edge, ink `trash` glyph and "Delete".
- Disabled at 40 % is 2.85:1 ink on white and 3.66:1 on black; disabled controls are exempt from the contrast minimum.

### 4.5 Sleep stages

Four grey steps, darkest ink = deepest: Deep ink, Light, REM, Awake (values in 1.1 and 1.2). Neighbours do not separate at 3:1 in
either appearance (light 4.89 / 2.09 / 1.55, dark 3.36 / 2.44 / 1.85), so:

- `StageBar` (28 pt): radius 0, 1 pt ink outline, **1 pt ink rules between segments** (not 2 pt gaps), stage order as today.
- Legend swatches (`StageRow`) and every stage dot: **10 x 10 square, grey fill, 1 pt ink edge** (the brief: "a swatch square in every legend row"). Each row has name, minutes, share.
- Hypnogram, MiniHypnogram: the stage is the **row** (y, labelled on the axis); the grey is the second cue. Bars keep their grey without an edge (they can be 2 to 3 pt wide).
- **"Unstaged asleep"** (`accentSecondary`) is 1.24:1 from Light in light and 1.20:1 in dark: the same grey twice. It is **H2 hatch with the 1 pt edge**, in the legend too.
- `SleepNeedBar`: base = Sleep grey, strain ink, debt (`warning`, 1.54:1 from base in light) = **H3 with a 1 pt edge**, nap keeps its dashed outline; the legend labels name each.
- Sleep-consistency icon (was accent / sage / warning): the glyph varies: `bed.double.fill` steady, `bed.double` fair, `bed.double` with an `exclamationmark` badge irregular; ink for all; the hint sentence is the label.

### 4.6 Insights severity (`InsightCard`)

Info / notice / warn become a **1, 2 or 3 bar glyph**: three 12 x 2 pt bars, 2.5 pt apart, radius 0; the first n ink, the rest
`surfaceRaised`. It replaces the coloured left capsule (which becomes a 3 pt full-height ink rule for all severities). The label word
("Insight", "Notice", "Attention") stays in `textPrimary`. The glyph is hidden from VoiceOver (the word is read first, as today).

### 4.7 Warning, error and polarity (hue stops carrying meaning)

- **Warning as text.** `Theme.warning` on text was 3.45:1 in light as soon as #100 landed, so **PR 1** fixes it: `textPrimary` with a leading
  `exclamationmark.triangle` where the line is a warning, `textSecondary` where it is a quiet note. Sites that set text:
  `SleepPlannerView` 298, 410, 426; `SleepView` 257 (debt value); `ProfileView` 371, 413, 708, 768, 834, 2081; `PlansView` 142; `RestTimerView` 166;
  `HealthPermissionView` 1368; `StatusViews` 709; `TrainHistoryView` 154 and `ExerciseCard` 234 (the W, section 7). A glyph standing alone may stay
  `warning` on `background` only (`ActivityStateMark` 150, `DateRangeControl` 48, `ImportFileSlot` 79, `ImportWarningsList` 22,
  `ExercisePage` 314, `AddActivitySheet` 268 and 354); `Theme.warning` at 14 % behind a glyph (`TrainComponents` 261 to 263) is 2.98:1 in light, so that glyph goes to `textPrimary`.
- **Error text** (`Theme.alert` on text) is `textPrimary`, and any such line without a glyph gets `exclamationmark.circle` before it. Sites:
  `JournalSettingsView` 22 and 125, `PlanBuilderView` 85, 177, 321, `PlansView` 294, `ImportResultView` 378, `ActivityDetailView` 362,
  `AddSleepSheet` 122. The Plan builder's error panel (`alert` at 0.1) is a 10 % ink tile with a 1 pt ink edge and the glyph.
- **Delta and polarity** (`DeltaLabel`, `RangeBar` status, Behaviors effect), decided (`plan.md`): direction stays by sign and arrow;
  **filled `▲ ▼` toward better, outlined `△ ▽` toward worse**; in the Behaviors whisker plot a filled or hollow 7 pt dot (1.5 pt edge).
  Neutral and flat metrics keep the filled arrow. No new words (polarity was never spoken).

## 5. Type and shape (PR 2)

### 5.1 Inter, one table

Inter 4.1 `Inter-Regular` and `Inter-Bold`, OFL, committed with `OFL.txt`. **Satoshi goes** with Inter (`plan.md`): its files, the
`UIAppFonts` entries and `fetch-fonts.sh` change in PR 2. `RyftFonts.postScriptName` loses its Medium case.

| Style | Size | Face | Case | Tracking |
| --- | --- | --- | --- | --- |
| `display` | 56 | Bold | caps | -0.07 em |
| `numberLarge` | 40 | Bold | as formatted | -0.07 em |
| `title` | 26 | Bold | caps | -0.07 em |
| `headline` | 18 | Bold | caps | -0.07 em (fallback -0.04 if the first render shows touching caps) |
| `metric` | 22 | Bold | as formatted | 0 |
| `wordmark` | 17 | Bold | caps | -0.04 em |
| `body`, `callout` | 16, 14 | Regular | sentence | 0 |
| `caption` | 12 | Regular | sentence | 0 (**D7**) |
| `label` | 11 | Regular | caps | +0.08 em |
| `axis` | 10 | Regular | sentence | 0 |
| `ryftNumber` below 32 pt (fields, tables, tiles) | n | Bold | as formatted | 0 |
| `ryftNumber` 32 pt and up (ring numbers, rest sheet) | n | Bold | as formatted | -0.07 em |

Departures from the brief, with reasons:
- **Numbers keep their case.** The brief says caps for "everything that is a title or a number". Uppercasing a formatted value corrupts
  its unit: "7h 48m" becomes "7H 48M", "kg" and "kcal" change meaning. Titles and headlines are uppercased by `textCase`; values come
  from `Fmt` as written. VoiceOver always reads the original string.
- **Table and field numerals get no negative tracking.** -0.07 em on a 22 pt tabular digit takes 1.5 pt off a 13.6 pt advance; "102.5" would touch.
- **Captions stay sentence case (D7).**
- `headline` and `metric` are Bold (the brief names headline Bold too; `metric` is a number style). A card title in Regular beside a Regular body has no weight step.
- Uppercase German: `textCase(.uppercase)` renders ß as SS on screen only. AX3 German titles wrap in caps; titles cap at `.accessibility3` in headers.
- To measure in the first render: Inter Bold tabular digits (about 0.64 em), the compact Focused fields (74 pt for "102.5" at 20 pt: about 67 pt with padding), German `label` at AX3, the Focused header row.
- Dynamic Type: unchanged mechanism (`relativeTo:`); display sizes are fixed because they live inside rings.

### 5.2 The wordmark and the lock-up

`Wordmark`: Inter Bold, `Text(verbatim: "RYFT")`, tracking -0.04 em, 17 pt in the header (`markSize * 0.85`), 32 in the lock-up, mark-to-word gap
`markSize * 0.45`; add one tracking unit (`size * 0.04`) of trailing padding to centre the lock-up. The mark is unchanged and round. The
lock-up tagline stays "Your whole health." in `label` style. The form `tokens.mjs` reads is the open item of 0.2 row 14.

### 5.3 Radius 0: what changes and what stays round

Rule: **containers and controls are rectangles; instruments are round.** An instrument is a mark that shows a quantity or the brand: the
orbit gauge, `MetricGauge`, the mark, a progress ring, a value dot. `Metrics.cardRadius` and `tileRadius` go to 0; the 148 literals do not follow and each needs a decision:

| Element | Decision |
| --- | --- |
| `Card`, `MetricTile`, `InsightCard`, sheet panels | ground fill (= `background`), **1 pt ink edge**, radius 0, padding 18. No fill, no shadow, no gradient (grep `Design/`) |
| Orbit gauge, `MetricGauge`, `RyftMark`, value dots, `HealthIllustration` disc | stay round |
| Check button (56 x 56, radius 14) | square. Active: ink fill, paper ✓. Done: no fill, `textSecondary` ✓. Upcoming: 1 pt `textTertiary` edge |
| Strip tile (56), done badge (16 circle), current ring, superset bar (3 pt capsule), `+` tile | tile square on `surfaceRaised`; current: 2 pt ink inset ring; done badge a 16 x 16 ink square with a paper ✓; superset bar a 3 pt ink rectangle; `+` tile a 1 pt dashed ink edge |
| Rest pill (48 high, capsule) | rectangle, same widths (idle min 112, running 144). Idle: ground, 1 pt ink edge. Running: ink fill, paper time. The 24 pt countdown ring inside stays round |
| Keypad keys (`NumberPad`, radius 14, 8 pt gaps) | **a flush grid**: square keys, 1 pt ink rules between and around, `ryftNumber` 22 labels; pressed inverts; Done is ink fill. The one place a full grid is right |
| Rest-sheet keys (-15 s / +15 s) | square, 1 pt ink edge, pressed inverts |
| Chips (capsule, 32 high visual, 44 hit) | rectangle, 1 pt ink edge; text `callout` `textPrimary`; disabled: text and edge `textTertiary` |
| `SegmentedPicker` | container 1 pt ink edge; **selected = ink fill, paper label**; unselected = ink label on ground |
| `StrainPill`, `ProviderBadge`, `SourceBadge` | rectangle; `StrainPill` keeps a 10 to 14 % ink tint; badges a 1 pt ink edge, no fill |
| `PrimaryButton`, `TealButtonStyle`, `AppleSignInButton` surroundings | square (4.4) |
| Fields (`ryftField` radius 12, Focused fields 12) | square. Idle: `surfaceRaised`, no edge. Focused: 2 pt ink edge. Active Focused row: ground fill + 1 pt ink edge (section 7) |
| Progress bars (`ImportProgressBar`), `StepRule` | rectangles, track `surfaceRaised`, fill ink (5.5) |
| Toast, `InlineMessage`, `OfflinePill` | rectangle, 1 pt ink edge |
| Plate calculator plates | square-cornered; height and width carry the weight (already). 25 and 20 kg: ink with a paper 8 pt label; the rest ground with a 1.5 pt ink edge and an ink label. Use `onAccent`, not `Theme.graphite`, for the label |

**Tab bar.** iOS 26 and later draw a floating system bar the app can't reshape: its shape stays. Selected tint = ink; **unselected =
`textSecondary`** (6.20 light, 9.96 dark; the old `textPrimary` at 0.5 is 3.98:1 and fails 4.5). Selection must not rely on lightness alone: selected uses the
**filled** symbol variant and a **Bold** label, unselected the outline variant and a Regular label. Today's tab symbols are all `.fill`,
so the outline for unselected is new (both appearances use it; there is no look to gate any more). Before iOS 26 (`#unavailable(iOS 26)`): opaque ground bar, 1 pt ink top rule
(`shadowColor = Separator` already does it), no rounded elements.

### 5.4 Shared borders, eyebrows, the header pattern

- **Shared borders.** Adjacent boxes collapse to one line: a grid of tiles is one container with a 1 pt ink outline and 1 pt ink rules
  between cells (full-ink edges, not the row rule), not four outlined boxes with doubled lines. At AX sizes the grid becomes one column
  with the same shared rules. `TrackerPickerGrid` (selection cards with a 12 pt gap) is the exception: its boxes are controls, keep the gap.
- **Eyebrow** `02 / SLEEP`: `label` style (Regular caps +0.08 em, `textSecondary`), digits tabular, above a Bold caps title. The number is the **tab's position**
  (01 Today, 02 Sleep, 03 Strain, 04 Insights, 05 Profile) and appears on those five screens only; pushed screens and sheets have a title and no index, and sections inside a screen keep today's `label` headers with no number (**D4**). The eyebrow is one VoiceOver element with the title ("Sleep", header trait); the index is hidden.
- **Header pattern per screen**: eyebrow, Bold caps title, then the one big number. Today `01 / TODAY`, the orbit; Sleep `02 / SLEEP`, the hours, `ASLEEP · 94 % OF NEED` as a label; Strain `03 / STRAIN`, the number, `OF 21 · MODERATE`; Insights `04 / INSIGHTS`, the count of notices; Profile `05 / PROFILE`, the account title. The big number is `numberLarge` or `display`, never both on one screen.
- The same component is `ScreenScaffold`'s header (PR 2 builds it; screens adopt it in PR 4 and 5).

### 5.5 Rule weights, and does a full-ink 1 pt rule make a grid?

**Yes, in list-heavy screens, and the row rule is the fix** (decided, `plan.md`). By code count (not rendered): the screens with a divider
between every row of a long list are Add exercise (about 14 rows visible), Splits table, Exercise detail, Journal groups, Import preview,
My Day rows, Notification settings and the Plan builder. At 44 to 56 pt per row that is a full-ink line every ~50 pt, 8 to 16 in a
viewport, each at 21:1, plus card edges: a ledger in which the rules outweigh the 11 to 16 pt text.

A second problem: `Theme.separator` is used as a **fill or a gridline** in 8 places (of 78 uses; 39 are row dividers), written when it
was 8 % Mist: `StepRule` (inactive segment and active segment are both ink, so the rule shows no progress), `ImportProgressBar`, the Behaviors track,
`ImportFileSlot`'s line, and the gridlines of `ChartStyle.yAxis`, `Hypnogram`, `MiniHypnogram`, `BedtimeStrip` (solid ink through every chart).

| Rule | Token | Width | Where | Contrast |
| --- | --- | --- | --- | --- |
| Edge | `separator`, ink | 1 pt | card, tile, chip, field, toast, sheet edges; grid rules between tiles; the section break above a pinned bar; the tab bar's top rule; chart axis lines | 21.00 |
| Row rule | **`Rule` colour set, ink at 0.20** (light `#CCCCCC`, dark `#333333`) | 1 pt | `Divider`s between rows **inside a card** | 1.61:1 on white, 1.66:1 on black; decorative: rows are separated by 44 pt hit areas and spacing |
| Track, gridline | `surfaceRaised` | any (gridlines 0.5 pt) | orbit and gauge tracks, progress and step tracks, chart gridlines, the typical band (a range, not a level) | 1.19:1 / 1.27:1; never information |

Gridlines take `surfaceRaised` as the brief says, not the row rule; the row rule covers dividers inside a card only. The row rule departs from ADR 0015 (`plan.md`). `Metrics.hairline` stays 1 pt (**D3**).

The Focused set table is not a grid: only the active row has field edges, done rows have none, and upcoming rows have the ✓ outline in
`textTertiary` rather than the full-ink edge (section 7).

## 6. Charts (Swift Charts, PR 3)

From the brief: **one ink series per chart**; comparison series as hatch or dashed stroke; today's bar solid and the rest `surfaceRaised`;
direct labels instead of legends for up to three series; axis lines hairline ink; gridlines `surfaceRaised`.

- Series: line 2 pt solid ink; markers only at today (solid ink dot). The dashed personal baseline (`ChartStyle.baseline`, 1 pt, [3, 3]) in `textSecondary` (6.20 / 9.96); the personal range a flat `surfaceRaised` band with no edge. A second series is a dashed 1.5 pt [4, 3] ink line, or a hatched bar (H2).
- **Bars.** The brief's "the rest `surfaceRaised`" gives 1.19:1 on white and 1.27:1 on black for bars that carry data, under the 3:1 for graphics.
  **Fix without a token: past bars get a 1 pt ink outline** (outlined = not today, solid = today), so the boundary is 21:1 and the value is the bar's height; the value of the selected bar is a label above it.
- Direct labels: the series name at the line's end in `label` style, `textSecondary`; no legend for up to three series; a legend row (swatch square + name) beyond that.
- Axes: tick labels `axis` `textTertiary` (4.76 / 6.27); the axis line a 1 pt ink hairline; the y axis keeps its trailing ticks and the unit on the top tick.
- Per-metric colours that were hue (`rhr` and `heartRate` `alert`, `activeKcal` `warning`, `steps` and `respRate` sage) become ink, or Sleep grey for the second series where two metrics share a chart; no chart uses two greys for two series without a direct label.
- Behaviors whisker: track `surfaceRaised`, interval an ink 4 pt bar at 0.35 becomes a **hatched H2 bar**, the point a filled or hollow dot (polarity, 4.7).
- Accessibility: every chart keeps `ChartAccessibility` summaries; the dashed or hatched series is named in the audio graph description, not only drawn.

## 7. Focused session (PR 5)

Rows and tokens, reusing the seven-state table of `docs/work/2026-11-04-focused-session/design.md` §3.1. One system, so the old
`scheme == .light` branches in `FocusedRowInk` go; both appearances are given.

| Part | Rule | Contrast (light / dark) |
| --- | --- | --- |
| Active row tint (`FocusedRowInk.activeTint` 0.10) | ink at 0.10 over ground: `#E6E6E6` / `#1A1A1A` | `textPrimary` 16.75 / 17.49; `textSecondary` 5.74 / 9.03; `textTertiary` **4.49 / 6.04: not allowed on a tint, one rule for both** |
| Active row leading bar | 2 pt ink, square | 21.00 |
| Active `#` and fields | ground fill **+ 1 pt ink edge** (white on `#E6E6E6` is 1.25:1; black on `#1A1A1A` 1.10:1, so the edge is needed in both) | edge 21.00 |
| `#` pill with dot | 32 x 32 square, 5 pt ink dot top-right | |
| Estimate (RM) column | `textSecondary` on every row. The light special case for the active row (`textPrimary`, "grey is 4.51:1") goes: secondary on the new tint is 5.74 / 9.03 | 5.74 / 9.03 |
| Done row | values `textSecondary`, ✓ `textSecondary`, no edge | 6.20 / 9.96 |
| Upcoming ✓ outline (`FocusedRowInk.upcomingOutline`) | `textTertiary`, 1 pt, square 56, both appearances (dark was `surfaceRaised` at 1.45:1) | 4.76 / 6.27 (3:1 needed) |
| Ghost value | `textSecondary` | 6.20 / 9.96 |
| Empty dash | `textTertiary` on `background` or the track; `textSecondary` on the active row | 4.76 / 6.27 |
| Warm-up `W` | `textSecondary` (replaces `warning`; the pin of section 3) | 6.20 / 9.96 |
| Strip tile text | `textSecondary` on `surfaceRaised` | **5.85** / 8.66 (the old note said "6:1 or better") |
| Strip current tile | 2 pt ink ring, number `textPrimary` | 17.62 / 16.48 |
| Strip done badge, superset bar | 16 x 16 ink square with paper ✓; 3 pt ink rectangle | 21.00 |
| Chips | ground, 1 pt ink edge, 32 high; disabled `textTertiary` | 4.76 / 6.27 |
| Rest pill idle / running / finished | ground + 1 pt ink edge / ink fill + paper `ryftNumber` 24 / 250 ms flash of ink at 0.25 with `textPrimary` only | flash `#BFBFBF` 11.44 / `#404040` 10.41 |
| Keypad | flush ink-ruled grid (5.3); digits `textPrimary`; pressed inverts | |
| Finish | unfilled: ground + 1 pt ink edge + ink label; filled at all-done: ink + paper label | 21.00 |
| Last-time card | `Card` (1 pt edge), rows `textSecondary`, header `label` `textTertiary` on `background` | 4.76 / 6.27 |

What no longer holds in the old Focused note: the teal lines ("one hue, two shapes", "never accent", "teal as the one accent on the
screen") become "ink"; the contrast sums on Mist and `#E8E7E3` grounds are replaced by the column above. "One accent per screen" is moot:
the dominant control is the one with the ink fill.

Tests: `FocusedRowInkTests` and `FocusedPolishTests` lose their `.light`-only expectations: the estimate and outline are asserted for both
schemes with one token; `theOutline` stays; `theEstimateOnTheActiveRow` asserts `textSecondary >= 4.5` on the tint; the `tint(_:)` helper
already composes `accent` at `activeTint`.

## 8. Screens: what changes, state by state

Each keeps its information and view model; what changes is type, surfaces, colour to fill, and the header (5.4). "Same" is deliberate.

### 8.1 Today (PR 4; PR 1 touches only the warning-as-text rows)
| State | Changes | Same |
| --- | --- | --- |
| Scored | `01 / TODAY`; orbit in ink; centre ring by band (solid / 16 dashes / outlined); band mark and the band sentence as a `label`; rail dashed; past-band hatch | Number, caption, delta and arrows (polarity), speech |
| Past the band | hatched stretch and dot | VoiceOver "past today's band" |
| Pending | dashed outlines (4.2); number `textTertiary`; breathing | Copy, the 15 s tick, still under Reduce Motion |
| Pending, no previous day | three hollow dashed dots | |
| Calibrating | filled segments ink; track grey | "3 / 7", note, link |
| Importing | `ImportCard`: track `surfaceRaised`, fill ink; steps square | Copy |
| Seven-day bars | today solid, the rest outlined (6) | Data, `Trends` link |
| Tiles | **a 2 x 2 hairline grid with shared borders**: Recovery, Sleep, Strain, **HRV (new)**; icon ink; the Recovery tile carries band mark + word; dimmed = value `textTertiary`, icon at 50 % | Captions, VoiceOver "not today's score". The HRV value needs a derived value in `TodayContent` (the day data has `hrvMs`); sync-engineer, not a design question |
| Status line, hints, offline, refresh issue, sync paused | `InlineMessage`: 1 pt ink edge, glyph; `OfflinePill` square | Copy |
| Launch animation | the orbit assembles, in ink | duration 250 ms, off under Reduce Motion |

### 8.2 Sleep (PR 4)
| State | Changes | Same |
| --- | --- | --- |
| Loading | `ProgressView` ink | |
| Night with stages | big hours, `ASLEEP · 94 % OF NEED` label, `StageBar` ruled, one legend row per stage with swatch, bedtime and consistency line, seven-night bars | Durations, shares |
| Without stages | unstaged = H2 hatch | Copy |
| Sleep need | `SleepNeedBar`: base grey, strain ink, debt H3, nap dashed | Sentence, legend |
| Debt high | `valueColor` `warning` -> `textPrimary` + glyph | Number |
| Consistency | glyph variants (4.5) | Hint sentence |
| Planner | warning text lines -> `textPrimary` + glyph; toggles tint ink | Copy |

### 8.3 Strain (PR 4)
| State | Changes | Same |
| --- | --- | --- |
| Scored | the big number, `OF 21 · MODERATE`; `MetricGauge` ink, target an outlined arc; no band mark (strain has no good or bad band) | Value, delta, "All out / High strain ..." |
| Zones | labelled hatch bars (4.3) | Minutes, ranges, "Zones in % of heart-rate reserve" |
| The session that made it | hairline row; `StrainPill` square | Subtitles |
| Seven-day bars | today solid | Data |
| Loading / no data | `ProgressView` ink; empty state (8.8) | |
| Workout detail | zone bar as above; header glyph discs become 40 x 40 squares | Splits table gets row rules |

### 8.4 Train (PR 5)
| State | Changes | Same |
| --- | --- | --- |
| Plan and session lists | hairline rows (row rule inside cards) | Behaviour |
| Focused page, 7 row states | section 7 | Identifiers, the state table |
| Live timer | Bold caps `ryftNumber` | Timer behaviour |
| Strip, chips, warm-up pill, last-time card, rest pill and sheet, keypad | square, 1 pt edges (5.3) | Layout rules at 320 and AX3 |
| List layout | done-row tint 6 % ink; square ✓; swipe reveal outlined (4.4) | Behaviour |
| Plate calculator | plates by height, ink or outlined | Numbers |
| PR/summary (`SessionView`) | trophy glyph `warning` -> ink | Copy |
| Rest timer Live Activity | section 9 | |

### 8.5 Insights / Signals (PR 5)
| State | Changes | Same |
| --- | --- | --- |
| Insight cards | 1 / 2 / 3-bar glyph; ink left rule; label word ink | Title, body, "Show the chart", dismiss |
| Signals | baseline band flat `surfaceRaised`, today's value an ink line, deviation with `▲ ▼` (polarity) | Data |
| Charts | section 6 | Axis, selection |
| Range bar | status arrows by polarity | Words "below / in range / above" |
| Behaviors | filled or hollow dot; interval hatched H2 | Copy |
| Empty / failed / offline | empty state (8.8) | Copy |

### 8.6 Profile -> Account (PR 5)
| State | Changes | Same |
| --- | --- | --- |
| Signed in | hairline rows; **Export my data** primary; Change password and Log out secondary; **Delete account** 2 pt outlined; provider badge a 1 pt edge | Copy; confirmation dialogs (system) |
| Busy | `ProgressView` ink; the button keeps its outline | |
| Error | `InlineMessage`: glyph + `textPrimary`, Details | |
| Signed out (demo) | | Copy |
| Appearance picker | the segmented control (selected inverts); words Dark / Light / System | Behaviour |
| Other sections | Withdraw consent and Full re-sync 2 pt outlined; status values `warning` -> `textPrimary` + glyph | |

### 8.7 Onboarding (PR 5)
`WelcomeView`, `AuthComponents` (create account, log in, forgot password, check inbox) and `PlatformConfig` **stop forcing dark in PR 5**; they follow the appearance.
Steps `01 / 03` in the eyebrow position (the `StepRule` segment count, with "Step n of m" as the text, replaces the old caption).
| Step | Changes | Same |
| --- | --- | --- |
| First screen | the hero as its headline (11) | Copy of the step |
| Invite code, consent, about you (birth year, minimum age 16), what do you wear, set-up | cards square, 1 pt edges; selection card 1.5 pt ink edge + filled ✓; `StepRule` track `surfaceRaised`, fill ink | Copy, order, the pinned bar |
| Health permission | `HealthIllustration`: heart ink on a 10 % ink disc (round, decorative); the Workouts warning line -> `textPrimary` + glyph | Copy |

### 8.8 Empty, offline, gated and error states
One sentence (the reason, in `body`), **one** outlined button (the action, if there is one; none when waiting is the only thing to do), the mark at 40 %
(decorative, hidden from VoiceOver; 2.85:1 ink on white by design). No spinner, no colour. Applies to full-screen and full-card states
(no data, offline, gated by invite or consent, platform errors with their request ID in Details). Inline banners stay `InlineMessage`.
Honest states stay: pending is an outline, calibrating shows the count, stale data shows its date.

## 9. Widgets, Live Activities, notifications, app icon

- **Home-screen widget** (`systemSmall`): the gauge only, no text, ink on the widget background (`WidgetBackground`: paper in light, ink in dark). The same
  `Shared/` drawing as the app (bands, rail, pending). Accessory families are tinted by the system: shapes carry the level (4.1).
  `accessoryRectangular` and `accessoryInline` keep the number and the band word (no band mark at inline size).
- **Live Activities** (rest timer, wake alarm; PR 5): the Lock Screen banner and the Dynamic Island are system chrome on a dark material. They draw
  **white ink on black in both appearances**, from the dark token values, and drop `Brand.teal`, `mist` and `graphite`. The rest timer shows
  its remaining time in Bold caps `ryftNumber`; the wake alarm its time. No colour is the only cue.
- **Notification image** (`NotificationRing`): it can't read the asset catalog and draws a fixed square today (Graphite, teal / amber / red band). It becomes a fixed
  black square with a white ring using the three level shapes (solid / dashed / outlined), which is what both appearances share.
- **App icon** (PR 5 for light; PR 6 for dark and tinted): ink mark on paper (light), paper mark on ink (dark), and a tinted variant (the mark in white on a black
  tile, for the system to tint). `make mark-svg` and the icon script regenerate them from the colour sets; `make check-mark-svg` stays green. The mark's geometry is
  unchanged; one ink, no accent dot.

## 10. Strings that name a colour, for localization-editor

I searched all three catalogs (`Ryft/Resources/Localizable.xcstrings` 1,771 keys, `InfoPlist.xcstrings`, `RyftWidgets/Localizable.xcstrings`) in both languages
for colour words and the Swift sources for the same inside string literals and accessibility labels.

**One string names a colour.** One system means one wording for both appearances (no new key for one look).

| Where | Key (en) | Current de | Proposed en | Proposed de |
| --- | --- | --- | --- | --- |
| `CoachMarks.swift:21`, the physiology coach mark | "Tap a tile for the details. The word under recovery is its band, so the colour is never the only cue." | "Tippe auf eine Kachel für die Details. Das Wort unter der Erholung nennt ihren Bereich, die Farbe ist also nie der einzige Hinweis." | "Tap a tile for the details. The word under recovery is its band, so no colour or mark is ever the only cue." | "Tippe auf eine Kachel für die Details. Das Wort unter der Erholung nennt ihren Bereich, ein Zeichen oder eine Farbe ist also nie der einzige Hinweis." |

Checked and not naming a colour: the band words High / Moderate / Low, "past today's band", the severity labels, "Dark / Light / System",
"Appearance", the alarm strings containing "ring", "Pick your watch, band or ring", the zone and stage legends.

New strings the design needs: the hero (11), the eyebrow words (they are the tab names), `01 / 03` (digits, no key). Button labels become caps through `textCase`, not through new keys.
**Nothing else is new**: the band mark, severity glyph, hatch, hollow arrows and outlined button are visual.

## 11. "Engineered for peak."

| Key | en | de (draft) |
| --- | --- | --- |
| Hero | Engineered for peak. | Engineered for peak. (the hero stays in English in the German UI, `plan.md`) |

Style: `display` class, Inter Bold caps, -0.07 em, 40 pt (`numberLarge` size), left-aligned, `textPrimary`, a 1 pt ink rule above it; Dynamic Type caps at
AX2; it wraps to three lines at 390 pt, which is why 40 and not 56.

Where it goes (brief §3, `plan.md`):
1. **Profile -> About, above the tagline.** The lock-up keeps "Your whole health." under it, in `label` style.
2. **The first onboarding screen's headline**, once, above the symbol; not on later steps and not in the sheet variant of a step.
3. **Welcome**, now that it follows the appearance (PR 5): it may carry the same line above the lock-up. The brief doesn't list it; I
   would not add a third place. Ask if wanted.
4. Store screenshots (`docs/APP_STORE.md`), first frame.
Nowhere else: not Today, widgets, notifications, or empty states.


## 12. What the catalog and swatch sheet must show (PR 0, updating `DebugComponentCatalog`)

In **both appearances side by side** (a `#Preview` pair, plus a PNG for the PR), one page per group:
- The greys with hex, role and contrast on the ground and on the track (1.1, 1.2); the failing ones marked.
- The ladder L0, H1 to H5 as 64 x 64 squares, plain and at actual size (16 pt, fine 10 pt) at 1x, 2x and 3x, and in greyscale. This is where the dark irradiation check happens.
- The three band levels as the mark (10 pt), as the orbit centre ring at 160, 112 and 72, and as `MetricGauge`.
- Orbit states at 160 and 112: scored, past the band (hatch at 160, dashed under 131), pending (dashed) at 1.0 and the 0.6 breath, calibrating, no previous day; with the rail.
- Zone bar with all five, one narrow sliver and zero minutes; stage bar with unstaged; the sleep-need bar; a seven-day bar chart with today solid and the rest outlined.
- Severity glyphs 1/2/3; filled and outlined arrows; the three buttons stacked (primary, secondary, destructive), disabled at 40 %, the `↗` variant; segmented control; chip row; keypad; rest pill idle and running; strip tiles; tab bar.
- A 2 x 2 shared-border grid; the eyebrow header pattern for the five screens; the empty state; the three rule weights on a long list and a chart.
- The type scale in Inter with tracking at default and AX3, English and German `label` at 11 pt.
- Everything also in **greyscale** (so it can be checked without brightness) and at AX3.

Previews for screens (later PRs): each state of 8.1 to 8.7 at 390 and 320, default and AX3, English and German, light and dark, Reduce Motion for the pending gauge.

## 13. The website

It is **not** live in this style and is not the reference for this work (`plan.md`). Read-only checks against `../plattform`:
- This checkout (HEAD `798fcdb`, no Alpine commits) still has the pre-Alpine tokens (teal, Satoshi, 18 px radii); `web/src/styles/globals.css` has no `--web-*` property and `web/docs/DECISIONS.md` ends before D18.
- **D18 to D21 and the `--web-*` scale exist only on `origin/web/alpine`** (not merged into this checkout's HEAD; `origin/web/english-light-inter` is a sibling branch). On that branch: D18 English only, D19 **light only, no dark theme**, D20 Inter under the OFL, D21 the restyle (`--web-display` 56 to 144 px, `--web-tracking-display` -0.07 em, `--web-tracking-label` 0.08 em, `--rule-soft` at 14 % of the separator, square buttons with `↗`, the `02 / LABEL` eyebrow).
- So the site has **no dark counterpart**: the dark inversion is an app-only look. The generator `tokens.mjs` reads this folder's colour sets; whether `tokens:check` accepts an app whose dark values are monochrome is for platform to confirm (**D5**). The site's row rule is 14 %, the app's is 20 % (ink on white vs the app's 1 pt hairline on a phone); they are independent numbers and nothing in the generator links them.
- `docs/ALPINE_STYLE.md` is not in either checkout I can read.

## 14. Open decisions for the user

**Decided on 2026-11-06, see [`plan.md`](plan.md):** D1 keep the brief's tokens, D2 hatch for all, D3 1 pt, D4 tab screens only, D6 the hero stays in English, D7 captions in sentence case. D5 stays open until PR 6. The questions stay as asked, for the record.

Only things I can't settle:

- **D1. Stage greys below 3:1.** REM and Awake stay under 3:1 in both appearances (light 2.05 / 1.32, dark 2.56 / 1.39) because four greys can't each reach 3:1. I recommend keeping the brief's tokens and relying on the 1 pt edge, the row and the label. A token change cannot do better without merging two steps (1.2).
- **D2. Zones: hatch for all, or grey steps with the label on the bar** (the brief). I recommend hatch for all with the label above (4.3).
- **D3. Rule width.** The brief has both `hairline = 1 / displayScale` (0.33 pt at 3x) and "1 pt ink rules". I keep 1 pt for edges and the row rule. Say if you want 1 px.
- **D4. Eyebrow numbering.** Index on the five tab screens only (my recommendation), or on every section of every screen. Numbering Profile's ten sections or Add exercise's lists is noise and costs VoiceOver reading time (5.4).
- **D5. Website dark.** The site ships light only (D19 on `web/alpine`). Does the site follow the app to the dark inversion, or does its generator keep reading only the light colour sets? It decides what `tokens:check` has to accept in PR 6.
- **D7. Caption case.** Captions stay sentence case (my recommendation), or uppercase as the brief says (0.2 row 12). Affects every hint, error and date line.

Already decided (`plan.md`): light default and dark as the inversion; existing users who chose dark keep it; the soft row rule; polarity arrows;
system-drawn destructive buttons stay red; Satoshi goes with Inter.
