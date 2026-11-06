# The monochrome light pass ("Alpine"): design note

Ticket: `CLAUDE_FOLLOWUP_ALPINE_LIGHT.md` (PR #100, branch `design/alpine-light-palette`). Owner of this note: ui-designer.
Reads with: `architecture.md` in this folder (ios-architect: how values switch by appearance, which this note does not design),
ADR 0015, `docs/work/2026-10-29-orbit-gauge/design.md`, `docs/work/2026-11-04-focused-session/design.md`.
Spec only: no app code, no swatch sheet and no previews in this round (section 9 says what they must show).
Every number below was computed from the colour sets on this branch (WCAG 2.x relative luminance, text composited over its
ground in gamma sRGB, as the tests do), not copied from the brief. Nothing was rendered; the first render is the first check.

## 0. Scope, and where the brief and ADR are wrong

**This pass is light only.** Dark stays exactly as it is: palette, Satoshi, radii 18/16, capsules, tracking, hue-coded bands and
zones. Wherever the brief says "both appearances get the same rule", this note writes the rule for light and the dark pass adopts
it later (marked "dark pass adopts").

What that costs, which the brief does not say: radii, fonts, tracking and the wordmark are not colours. `Theme.Metrics`,
`Typography.swift` and `Wordmark` are appearance-blind today, so "dark unchanged" means **each of them needs a light value and
keeps today's value in dark**. That switch is architecture's; section 4 lists the light and the unchanged-dark value of each.

### 0.1 Things in the brief or ADR that are false or incomplete

| # | Claim | What the code and the maths say |
| --- | --- | --- |
| 1 | "metric arcs are grey steps on `#EBEBEB` in light; Sleep `#6B6B6B` passes 3:1, lighter steps don't" | Of the three arcs only Sleep is grey. Recovery and Strain are `#000000` (17.62:1 on the track). Sleep `#6B6B6B` is **4.47:1**, and the stage step `#7A7A7A` is **3.60:1**; both pass. Failing on the track: `#8A8A8A` 2.90, `#B5B5B5` 1.72, `#E0E0E0` 1.11. The one entry that fails `arcsAndDotsReachThreeToOneOnTheirTrack` is **"band moderate (warning)"**, the centre ring at `#8A8A8A`: 2.90:1 on the track (3.45 on white). |
| 2 | "Warning `#8A8A8A` ... (3.3:1)" | 3.45:1 on white, 2.90:1 on `#EBEBEB`. The rule (never text) stands; the number was off. |
| 3 | ADR: secondary text "5.9:1", tertiary "4.7:1" on white | Secondary (`#000` at 62 %, effective `#616161`) is **6.20:1**; tertiary (55 %, `#737373`) **4.76:1**. Both clear 4.5. Tertiary on the active-row tint is **4.49:1, which fails by 0.01** (section 5). |
| 4 | "the rails' pinned opacity no longer gives the expected ratio over a black separator" | No separator is involved. The rail is `metricStrain` at 0.5 over the background; black at 0.5 on white is **3.95:1**, the test asserts `< 3`. It fails because the colour went black, not because of the separator. |
| 5 | "pending uses `textTertiary` at 0.6" | Pending marks use the arcs' own colours at 0.6; only the number is `textTertiary`. The test fails on the **Strain** arc (black at 0.6 is 5.74:1, the test asserts `< 3`); the grey Sleep arc (2.43:1) is the one that would fail the other way. |
| 6 | "Dots hollow when pending (as today)" | Today a pending gauge draws the previous day exactly as scored (filled dots) at 0.6; dots are hollow only for a missing score or when there is no previous day. Section 2.2 keeps it that way. |
| 7 | "any VoiceOver text that named a colour ('red', 'green')" | None exists. Band words are already High / Moderate / Low, and "above today's recommended range" already speaks the past-band state. One user-visible string names a colour (section 6). |
| 8 | The failing list | Incomplete. `scripts/check-shared-types.py` reports **7 problems**: the widget's `Accent`, `Alert`, `MetricSleep`, `MetricStrain`, `SurfaceRaised`, `TextTertiary`, `Warning` colour sets still hold the old light values (e.g. `Alert #B04436`, `MetricStrain #2E5BBF`). The widget gauge in light would be coloured next to a monochrome app. Decision: the widget copies take the app's values verbatim. |
| 9 | `separator` is "full ink, 1 pt" | True, and it breaks 8 call sites that use `separator` as a **fill or gridline**, not a rule, and thickens 39 row dividers (section 4.4). |
| 10 | Radii to 0 turns cards into hairline boxes | Only the 56 shapes that read `Theme.Metrics.cardRadius` / `tileRadius` change. 148 other `Capsule()`, `Circle()` and literal `RoundedRectangle(cornerRadius: n)` calls outside previews ignore it (section 4.3). |
| 11 | The hero opens the app | `WelcomeView`, the auth screens (`AuthComponents`) and `PlatformConfig` force `.dark`; the default appearance is dark. New users do not see light until they choose it in Profile (section 7.7, section 8). |
| 12 | Wordmark "keep the `.tracking(size * ...)` form" for the web | The checkout I can read (`plattform/web/scripts/tokens.mjs`) matches `\.tracking\(size \* ([\d.]+)\)` and `\.tracking\(([\d.]+)\)`: a **negative factor, or a factor written `0.08 * size`, makes `tokens.mjs` throw** ("label or wordmark tracking not found"). The checkout is pre-Alpine, so the pushed `#142/#143` version may differ; this must be checked against it (section 4.2). |

### 0.2 What I needed from `docs/ALPINE_STYLE.md` and did not have

Not on this machine; nothing below invents its content. Where I needed a value I decided it and marked it **(mine)**. Needed:
the hatch angle, pitch and weight (the brief gives only "45 deg"); the weight and radius of the web's outlined buttons; whether
the web's inner row rules are full ink; hero size and case; the display tracking per style (the brief gives -0.07 em for
"display styles" without saying which); the web's `tokens.mjs` forms for negative and em tracking. The website checkout on this
machine (`plattform/web`) still carries the pre-Alpine tokens (teal, Satoshi, 18 px radii), so it gave nothing to copy; I did
not edit it.

## 1. Light tokens and what they reach

Ground: `background` / `surface` `#FFFFFF`; track `surfaceRaised` `#EBEBEB`; active-row tint = `accent` at 0.10 over white =
`#E6E6E6` (229.5).

| Ink | On `#FFFFFF` | On track `#EBEBEB` | On tint `#E6E6E6` | Use |
| --- | --- | --- | --- | --- |
| `textPrimary` `#000` | 21.00 | 17.62 | 16.75 | values, labels |
| `textSecondary` (62 %, `#616161`) | 6.20 | 5.85 | 5.74 | secondary text |
| `textTertiary` (55 %, `#737373`) | 4.76 | 4.56 | **4.49 (fails)** | captions, dashes. Allowed on white and on the track; **not on any tint of 10 % or more**, not on a pressed or flashing fill |
| `#000` accent / alert / strain / Deep | 21.00 | 17.62 | | marks |
| `#6B6B6B` Sleep, accentSecondary | 5.33 | 4.47 | | marks, and text if ever needed |
| `#7A7A7A` Stage Light | 4.29 | 3.60 | | marks |
| `#8A8A8A` Warning | 3.45 | **2.90** | | **marks on white only** (bars, borders, a glyph alone); never text; never on the track |
| `#B5B5B5` Stage REM | 2.05 | 1.72 | | fill only, with an ink edge |
| `#E0E0E0` Stage Awake | 1.32 | 1.11 | | fill only, with an ink edge |
| `#EBEBEB` track | 1.19 | 1.00 | | the empty scale; never information |

Greys for reference: the lightest grey that reaches 3:1 on the track is `#878787`; on white `#949494`; 4.5:1 on white `#767676`.

Consequences used below:
- **A grey step is a category or an order, never the only carrier.** REM and Awake are under 3:1 on white, so every stage fill
  gets a 1 pt ink edge (section 2.5).
- **Tracks are the empty scale and not information** (1.19:1 on white, as in dark's 1.45). The arc's end, the number and VoiceOver
  carry the value. A track that does carry meaning (the step rule, a progress bar) gets a number or a label (section 4.4).
- The tint recipes `accent.opacity(0.10...0.14)` still work in light: they give `#E6E6E6` to `#DBDBDB` behind ink, 15:1 and better.
  They now look like `surfaceRaised`, so a tinted control and a raised control are the same grey; the distinction is the label.

## 2. Level by ink, every scale

**One vocabulary.** An ordinal level is shown with the same ladder everywhere in light:

| Step | Looks like | Ink coverage |
| --- | --- | --- |
| L0 | outline only: 1 pt ink edge, empty inside | 0 % |
| H1 | 45 deg hatch, 1 pt line, 8 pt pitch | 12.5 % |
| H2 | 45 deg hatch, 1 pt line, 4 pt pitch | 25 % |
| H3 | 45 deg hatch, 2 pt line, 4 pt pitch (fine: 1 pt line, 2 pt pitch) | 50 % |
| H4 | 45 deg hatch, 3 pt line, 4 pt pitch | 75 % |
| H5 | solid ink | 100 % |

Hatch rules **(mine, because the brief gives only the angle)**: lines run bottom-left to top-right ("/"), 45 deg to the
horizontal **in screen space**, not along an arc; pitch is measured perpendicular to the lines; lines are `textPrimary`; the pattern
is clipped to the shape and anchored to the shape's own origin so it does not swim when the shape grows; the clip edge always gets
a 1 pt ink outline (without it H1 and H2 have no visible boundary on white). Weights and pitches are whole points so they land on
whole pixels at 2x and 3x. The **fine** variant (half weight, half pitch) exists for shapes under 12 pt in their short side
(arcs 4.5 to 6 pt wide, a 10 pt swatch); only H3 and H5 are used there. No text is ever set on a hatch: labels sit beside or above.

Average tone is not what tells the steps apart (mean luminance of H1 to H5 is 0.875, 0.75, 0.5, 0.25, 0: adjacent steps are
1.16:1 to 1.8:1 as tones, and 6:1 only between H4 and H5). **Pitch and weight tell them apart, and every use below also has a
word or a position.** That is the honest limit of greyscale ordinal coding: it is a second cue, never the only one.

### 2.1 Readiness and recovery bands (`Theme.band`, `MetricSpec.scoreBand`, `OrbitGaugePalette.band`)

Boundaries unchanged: 67 and up = high, 34 to 66 = moderate, below 34 = low (the `MetricSpec.thresholds` `[33, 67]` put the
gauge tick at 33 while the band starts at 34; a pre-existing one-point mismatch, noted, not changed here).

| Level | Rule | Ink | Is a number or word still there |
| --- | --- | --- | --- |
| High | solid | H5 | yes: the score, "High" |
| Moderate | hatched | H3 (fine where the shape is under 12 pt) | yes: the score, "Moderate" |
| Low | outlined | L0 | yes: the score, "Low" |
| No score | nothing drawn in the band's place; only the track | (none) | the dash, "No data" |

Why not a flat 50 % grey for moderate (the brief's first option): `#808080` is 3.95:1 on white and 3.31:1 on the track, so it passes,
but grey is already the Sleep and stage language. Hatch is reserved for "a level between", so it can't be read as a category.
Why "no score" draws nothing instead of today's `textTertiary` ring: a solid 55 % ink ring would read as "high, but dim".

**Band mark** (new, tiny, used wherever the band word appears): a 10 x 10 pt square, radius 0, 1 pt ink edge; inside it
L0 / fine H3 / H5. It sits 6 pt before the word ("[mark] High"). Where it appears: the Orbit caption, the Recovery tile caption,
`MetricGauge`'s band line, the coach mark's tile. At AX sizes it grows with the caption (14 pt at AX1 and up). It is hidden from
VoiceOver; the word is the label. **Dark pass adopts** the mark and the ladder.

**Orbit centre ring** (stroke 4.5 pt at the 160 dial, centreline radius 32): a hatch does not fit in 4.5 pt, so the ring carries
the same three levels in stroke form:
- High: solid 4.5 pt ring, ink.
- Moderate: the same ring, butt caps, **16 dashes and 16 gaps** (11.25 deg on, 11.25 deg off at every dial size), seam in the
  middle of a gap at 12 o'clock. 50 % ink by construction.
- Low: outlined. Two 1 pt ink circles at radius `centre +/- stroke/2` (2.5 pt clear between them at the 160 dial, showing the
  track). Where the stroke is under 3.5 pt (dial under 124, i.e. `.small` and `.medium` 112 gets 3.15) the outline would close up,
  so low becomes **one 1 pt ink circle on the centreline**: still the thinnest mark in the gauge, still not a ring.
- Contrast: every mark here is `#000`: 21.00 on white, 17.62 on the track. The moderate ring's gaps are information, not a
  contrast problem (a 4.5 pt solid dash against its 11.25 deg gap).
- The widget draws the same ring from `Shared/OrbitGaugeDrawing.swift`, so the rule lands there with the same code.

`MetricGauge` (the Strain tab dial, 6 pt stroke, butt caps, used for strain and in the component catalog for readiness): the arc
is ink; for a banded metric the arc uses the same three treatments (solid / fine H3 hatch / outlined 1 pt edges). Strain has no
good or bad band and stays solid ink. Its `target` arc (today `spec.color` at 0.35, 2.44:1) becomes **an outlined arc on the
track** (two 1 pt ink edges, butt ends, no fill) under the value arc; the value arc is solid ink over it.

### 2.2 Orbit gauge: arcs, tracks, rail, "past the band", pending

Light values for the three orbits: Recovery `#000`, Strain `#000`, Sleep `#6B6B6B` (unchanged colour sets). All on the
`#EBEBEB` track: 17.62, 17.62, 4.47. Orbits are told apart by position (inner left, inner right, outer), as in the brief's colour-blind
check; the grey Sleep arc is an extra cue, not the cue.

- **Strain band rail**: a **dashed hairline in full ink**: 1 pt (floor 1 pt, scaled with the dial above that), butt caps, dash
  3 on / 2 off at the 160 dial (scaled by dial / 160, never under 2 / 1.4 pt), same centreline radius 69.5 and the same dot cut-out.
  Opacity **1.0** (today 0.5). Contrast 21.00 on white, 17.62 on the track. The air to the outer ring's inner edge (74.25) is 4.25 pt and to the inner dots (outer edge 63) 6 pt, more than the old
  3 pt stroke left (3 and 5.5); the geometry tests need no new numbers except the stroke. Still not drawn under a 90 pt dial. The dashed rail means "the scale of the target", the same word as
  a dashed baseline in the charts (`ChartStyle.baseline`).
- **Past the band** (strain above the clamped upper end): the arc past the split turns **hatched**; the dot turns hatched with it.
  - Dial 131 and up (stroke 4.5 pt or more: `.large`, the widget's `systemSmall`): the stretch from the split to the head is an
    **outlined arc**: 1 pt ink edges on both sides, butt end at the split, round cap at the head, filled with the **fine H3
    hatch** (1 pt lines, 2 pt pitch). At the 160 dial that is 5.5 pt wide: 1 pt edge, 3.5 pt of hatch, 1 pt edge. The dot is the same:
    1 pt ink circle, fine H3 inside.
  - Under dial 131 (`.medium` 112 with a 3.85 pt stroke, `.small`): hatch would be mush, so the stretch is a **dashed solid arc**:
    butt-capped, dash 1.2 x stroke on, 0.8 x stroke off. The dot stays solid with a 1 pt white inner ring.
  - A **radial tick** is not added; the split is already the rail's end where the rail is drawn, and the texture change is the
    cue where it is not.
  - The `OrbitStrainArc` structure (one stroked arc drawn twice, clipped at the split by `OrbitWedge`) stays; "past" changes from a
    colour to a texture. The tone decision (`strainTone` `.pastBand`) and the speech ("above today's recommended range") are
    unchanged: **no new string**.
  - Tests: detect the state by the **texture flag** (the tone), never by sampling colour. The old render test sampled "alert vs
    strain" at 77 pt radius; its replacement samples ink coverage over a 6 deg window (past the split it must be between 0.35 and
    0.65 of the stroke; before it, above 0.95).
- **Pending** (previous day's marks, group opacity): `pendingOpacity` **stays 0.6**. The old reason ("intentionally below
  3:1") is gone: black at 0.6 is #666666, **5.74:1 on white and 5.44:1 over the track**. With the app's breath (1.0 to 0.75
  of that, so 0.45 at the trough) it is 3.35:1 on white and **3.26:1 over the track: every pending arc and dot clears 3:1 at every
  moment of the breath**. The one change: **in a pending gauge Sleep is drawn in ink (`#000`), not `#6B6B6B`**, because
  `#6B6B6B` at 0.6 is 2.43:1 (1.89:1 at the trough) and a dimmed grey would drop out. Orbit identity is position, so nothing is lost.
  The "not today" cue is therefore not contrast any more; it is the 0.6 ink (#666666 against `#000`), the number in `textTertiary`
  (4.76:1), the date line, and the words. The test is rewritten to say exactly that: all pending graphics `>= 3` on the track,
  trough included; the number `>= 4.5`.
- Pending without a previous day: three hollow dots (1.25 to 2 pt ink outline at 0.6) and the dash in the number's place. Unchanged.
- Calibrating: the filled segments are ink on the track (17.62:1, test keeps its `>= 3`); the unfilled segments are the track.
  Unchanged. "Pending is an outline" is honoured by the empty segments and the hollow dots, not by outlining pending arcs: an outlined
  arc would read as "low" in this language.

**Tracks not named above:** `RangeBar` and `ZoneBar` use `surfaceRaised` today and take `Theme.track` in light. `ScoreRing` stays as it is. Dark doesn't change in any of them (`architecture.md`).


### 2.3 Heart-rate zones (`Theme.zones`, `ZoneBar`)

Today's light zones are `[E0, 6B, 000, 8A, 000]`: Z3 and Z5 are both black, Z2 and Z4 are 1.54:1 apart, and the order is not
monotone. They go to the ladder: **Z1 H1, Z2 H2, Z3 H3, Z4 H4, Z5 H5**.

- Bar: 16 pt high (was 10, a hatch needs room), radius 0, 1 pt ink outline around the whole bar, **1 pt ink vertical rules**
  between segments instead of the 2 pt gaps. Segment widths stay proportional to minutes; a segment under 3 pt wide is drawn
  solid-ink-edged at its width (it is a sliver and the position says which zone).
- Order is fixed Z1 to Z5 from the left, so position identifies the zone when a segment is too narrow for its texture.
- The minute label stays above its segment (`axis` font, `textSecondary`, 6.20:1); nothing is set on the hatch.
- Legend: five columns as today, the swatch becomes a **16 x 16 square with the same hatch and a 1 pt ink edge**, then "Z1", the
  minutes, and the heart-rate-reserve range. "Z" plus a number is the label on every legend entry.
- Chart bars coloured by zone (Strain and Workout detail) use the hatch fill with the 1 pt edge; per-bar labels are the existing
  axis labels.
- VoiceOver unchanged (it already reads "Zone 3: 18 min").
- **Dark pass adopts** hatch for zones.

### 2.4 Destructive actions

`Theme.alert` stays `#000000`. Nothing may rely on `alert != accent`.

- **Destructive button** (`PrimaryButton(.destructive)`: Delete account, Withdraw consent, Full re-sync, Full resync in the debug
  view; and the Discard-import text button): **white fill, 2 pt ink outline, ink label, radius 0, same 44 pt height**. 2 pt, not the
  card's 1 pt, so it reads as a control and not as another card. Pressed: ink fill, white label (21:1), instant.
  Disabled: 0.45 opacity as today (3.35:1 for a disabled control is allowed to be low).
- It sits beside **secondary** (today `surfaceRaised` fill, no edge) and **primary** (ink fill, white label). Three tiers, none of
  them by hue: filled ink, grey fill, outlined. In Profile -> Account the three buttons stack (Change password, Log out, Delete
  account); Delete is the only outlined one, and the word "Delete" is in the label. No glyph is added: the label is the cue.
- The confirmation dialogs and alerts are **system-drawn**; their destructive buttons stay system red. That is the OS's, not
  ours, and it is unchanged by the brief ("confirmation sheet unchanged"). It is the one place light shows a hue. **Decided (`plan.md` D3): accepted.**
- Context-menu and swipe actions with `role: .destructive` (Delete set, Remove exercise, Discard workout, Remove day): menus stay
  system-drawn. The one themed swipe reveal (`ExerciseCard`, List layout, `Theme.alert` fill, 14 pt radius) becomes a white
  reveal with a 2 pt ink edge, ink `trash` glyph and "Delete" label.
- **Error text** coloured `Theme.alert` (Journal settings, Plan builder, Plans, Import result, Activity detail, Add sleep) is now
  `textPrimary`. Where such a line has no glyph today, it gets `exclamationmark.circle` before it; an error is never "black text
  that looks like body text". Sites: `JournalSettingsView` 22 and 125, `PlanBuilderView` 85, 177, 321, `PlansView` 294,
  `ImportResultView` 378, `ActivityDetailView` 362, `AddSleepSheet` 122. The Plan builder's error panel (`Theme.alert` at 0.1) is
  a `#E6E6E6` tile with a 1 pt ink edge and the glyph.
- **Warning-as-text** (`Theme.warning` on text, 3.45:1): becomes `textPrimary` with a leading `exclamationmark.triangle` where the
  line is a warning; `textSecondary` where it is a quiet note. Sites that set text: `SleepPlannerView` 298, 410, 426; `SleepView`
  257 (debt value); `ProfileView` 371, 413, 708, 768, 834, 2081; `PlansView` 142 ("Paused" label); `RestTimerView` 166;
  `HealthPermissionView` 1368; `StatusViews` 709; `TrainHistoryView` 154 and `ExerciseCard` 234 (the W, section 5).
  Glyph-alone uses stay `warning` only on white (3.45:1 clears the 3:1 for graphics): `ActivityStateMark` 150, `DateRangeControl`
  48, `ImportFileSlot` 79, `ImportWarningsList` 22, `ExercisePage` 314, `AddActivitySheet` 268 and 354. `Theme.warning`
  at 14 % behind a glyph (`TrainComponents` 261 to 263) is 2.98:1 against the tint, so that glyph goes to `textPrimary`.
- **Delta and polarity** (`DeltaLabel`, `RangeBar` status, Behaviors effect): good and bad were `accent` vs `alert`, both
  `#000` now. Direction stays by sign and arrow. The polarity (toward better or toward worse) is carried by the **arrow's fill:
  filled `▲ ▼` toward better, outlined `△ ▽` toward worse**, and in the Behaviors whisker plot by a filled or hollow 7 pt dot
  (1.5 pt edge). Neutral and flat metrics keep the filled arrow. No new words: the VoiceOver sentence already states direction and
  magnitude; polarity was never spoken. **Decided (`plan.md` D4): added.**

### 2.5 Sleep stages

Four grey steps stay, darkest = deepest: Deep `#000` (21.00 / 17.62 on the track), Light `#7A7A7A` (4.29 / 3.60), REM `#B5B5B5`
(2.05 / 1.72), Awake `#E0E0E0` (1.32 / 1.11). Adjacent pairs: Deep-Light 4.89, Light-REM 2.09, REM-Awake 1.55, Light-Awake 3.25.
So **Light, REM and Awake do not separate from each other or from white at 3:1** and need a second cue:

- `StageBar` (proportional stack, 28 pt): radius 0, 1 pt ink outline around the bar, **1 pt ink rules between segments**
  (replacing the 2 pt gaps), so every boundary is 21:1 whatever the greys. Order is the stage order, as today.
- Legend swatches (`StageRow`) and every stage dot: **10 x 10 square, grey fill, 1 pt ink edge**. The row has the stage name, minutes
  and share: the label is on every row.
- Hypnogram and MiniHypnogram: the stage is the **row** (y position, labelled on the axis); the grey is the second cue. Bars
  keep the grey fill without an edge (they can be 2 to 3 pt wide). Axis gridlines go to the soft rule (section 4.4).
- **"Unstaged asleep"** (`accentSecondary` `#6B6B6B`) is 1.24:1 from Light `#7A7A7A`: the same grey twice. It becomes **H2**
  (1 pt hatch, 4 pt pitch) with the 1 pt edge: "asleep, stage unknown" reads as unfilled. In the legend: the same swatch hatched.
- Sleep-need bar (`SleepNeedBar`): base `#6B`, strain `#000`, debt (`warning` `#8A`, 1.54:1 from base) becomes **H3 with a 1 pt
  edge**, the nap credit keeps its dashed outline. Each term has its legend label already.
- Sleep-consistency icon colour (steady/fair/irregular): was accent / sage / warning; it is now the **glyph variant**:
  `bed.double.fill` steady, `bed.double` fair (outline), `bed.double` with `exclamationmark` badge irregular; ink for all three.
  The hint sentence is the label.

### 2.6 Insights severity (`InsightCard`)

Info / notice / warn are today `accentSecondary` / `warning` / `alert` on the 3 pt left capsule, the glyph and the label.
New: a **severity glyph of 1, 2 or 3 stacked bars**: three 12 x 2 pt bars, 2.5 pt apart, radius 0; the first n are ink, the rest
`surfaceRaised`. Info 1, notice 2, warn 3. It replaces the coloured capsule (the left rule becomes a 3 x full-height rectangle in
ink for every severity). The label word ("Insight", "Notice", "Attention") stays and is `textPrimary`, not coloured; the kind glyph
beside it is ink. The glyph is hidden from VoiceOver (the word is read as the card's first element, as today). Contrast: ink 21.00
on white; empty bars are the track (non-informative). **Dark pass adopts.**

## 3. The failing pins: decision replacing each

| Test | Why it fails | Design decision that replaces it | New pin |
| --- | --- | --- | --- |
| `OrbitGaugeBandTests.theColourPastTheBandIsAlertAndReachesThreeToOneOnTheTrack` | asserts `strainPastBand == alert`, different from `strain`, and 3:1 | Past the band is **a texture, not a colour** (section 2.2). `strainPastBand` as a colour stops existing in light; the palette exposes a flag. | Tone `.pastBand` iff strain > clamped upper end (the existing tone tests already say it); the textured stretch's ink (`#000`) is `>= 3` on the track and on the background; **no assertion that past differs from plain by colour**. |
| `OrbitGaugeBandRenderTests.midGlideTheArcInsideTheBandIsNeverAlert` | samples colour at 77 pt radius | Same geometry, new signal: ink coverage | At sample angles behind the split (`degrees < split - 4`) the 6 deg window has stroke coverage `>= 0.95` (solid); past it (`> split + 4`) coverage in `0.35...0.65` for the large dial. Mid-glide the stretch behind the split is never textured. Render only the `.large` dial (the hatch's size rule). |
| `OrbitGaugeContrastTests.arcsAndDotsReachThreeToOneOnTheirTrack` | the "band moderate (warning)" entry: `#8A8A8A` is 2.90:1 on the track | The moderate band is **dashed ink**, not `warning` (section 2.1). The list becomes: Recovery, Sleep (`#6B`, 4.47), Strain, band high (solid ink), band moderate (ink dashes), band low (ink outline), past-band hatch (ink), all `>= 3` on the track and on the background. The centre ring without a readiness: no ring, so the `textTertiary` entry is removed. | The list above, `>= 3` each. The dark loop is unchanged (the test still resolves dark colours; dark is untouched). |
| `OrbitGaugeBandTests.theRailsOpacityIsPinnedAndItsRatioStaysAboveTwo` (the brief files it under `OrbitGaugeContrastTests`; it is in `OrbitGaugeBandTests`) | rail opacity 0.5 gives 3.95:1 and the test asserts `< 3` | Rail is a **full-ink dashed hairline** (section 2.2). `bandRailOpacity` becomes 1.0 in light. | `bandRailOpacity == 1` in light; rail ink `>= 3` on the background and on the track (21.00 / 17.62); rail stroke `>= 1`. The "documented sub-3:1" claim is deleted. Dark keeps 0.5 and its `< 3` assertion. |
| `OrbitGaugeContrastTests.pendingOpacityIsPinnedAndIntentionallyBelowThreeToOne` | asserts the light Strain arc at 0.6 is `< 3` (it is 5.74) | `pendingOpacity` **stays 0.6**; Sleep is drawn in ink while pending. Pending is now intentionally **at or above 3:1** (section 2.2). | `pendingOpacity == 0.6`; all pending arcs and dots `>= 3` on the track at 0.6 **and at 0.45** (the breath's trough: 3.26 over the track, 3.35 on white); the pending number `>= 4.5`; rename the test (it no longer claims "below 3:1"). Dark keeps the old claim. |
| `FocusedPolishTests.theWarmUpMark(scheme:)` | `Theme.warning` on `background` is 3.45:1 | The W is **`textSecondary` in light** (6.20 on white, 5.74 on the active row's tint, 5.85 on the track), enclosed in nothing; it is the one character that is a letter where the others are numerals. Dark keeps `warning` (4.5:1 there today). | Light: `W` ink `>= 4.5` on `background`, on the active-row pill over the tint, and on a plain row. Dark: unchanged. The same token goes to `TrainHistoryView` 154. |

Also needed (not in the brief's list): `check-shared-types` (widget colour sets, section 0.1 row 8), `make mark-svg`, the
`FocusedRowInk` comments (section 5), and the band-level test the brief names (`BandLevel` in `Shared/`, `architecture.md`): solid / half / outlined at
67 and 34, `(66, 67)`, `(33, 34)`, `nil`, in light; dark returns the old hue.

## 4. Type and shape in light

### 4.1 Inter, mapping, tracking (light only; dark keeps Satoshi and its tracking)

Fonts: Inter 4.1 `Inter-Regular` and `Inter-Bold`, OFL, committed with `OFL.txt`. **Satoshi stays bundled** (dark uses it): both
families in `UIAppFonts` ; Inter is committed and `fetch-fonts.sh` keeps fetching Satoshi only (`architecture.md` §6). `RyftFonts.postScriptName(for:)` becomes scheme-aware (`architecture.md`: `RyftFont` / `RyftLook`).

| Style | Size | Light face | Light tracking | Dark (unchanged) |
| --- | --- | --- | --- | --- |
| `display` | 56 | Bold | -0.07 em | Satoshi Medium, 0 |
| `numberLarge` | 40 | Bold | -0.07 em | Satoshi Medium, 0 |
| `title` | 26 | Bold | -0.04 em **(mine)** | Satoshi Medium, 0 |
| `metric` | 22 | Bold | 0 | Satoshi Medium |
| `headline` | 18 | **Bold** | 0 | Satoshi Medium |
| `wordmark` | 17 | Bold, caps | -0.04 em | Satoshi Medium, +0.32 em |
| `body`, `callout`, `caption`, `axis` | 16/14/12/10 | Regular | 0 | Satoshi Regular |
| `label` | 11 | Regular, caps | +0.08 em (0.88 pt) | Satoshi Medium, +2 pt, caps |
| `ryftNumber(size:)` below 32 pt (fields, tables, tiles) | n | Bold | 0 | Satoshi Medium |
| `ryftNumber(size:)` 32 pt and up (ring numbers, rest sheet 56) | n | Bold | -0.07 em | Satoshi Medium |

Departures from the brief, with reasons:
- **`headline` and `metric` are Bold, not Regular** ("Regular elsewhere"). A card title at 18 pt Regular beside a 16 pt Regular
  body has a 12 % size step and no weight step; the hierarchy is gone. Bold costs nothing in contrast.
- **Table and field numerals get no negative tracking.** -0.07 em on a 22 pt tabular digit is 1.5 pt off a 13.6 pt advance; in
  "102.5" that reads as touching. Tracking applies to numbers of 32 pt and up only.
- **Label tracking falls from +2 pt (0.18 em) to +0.08 em.** Inter's caps are wide; the web's 0.08 em is the brief's number.
- Metrics to re-check in the first render, not decided here: Inter Bold tabular digits are about 0.64 em, Satoshi's about 0.58 em
  (my estimate). At 20 pt "102.5" is about 59 pt plus 8 pt padding = 67 pt against the 74 pt compact field, and 22 pt in the 93 pt
  field is about 65 pt: both fit. German `label` caps at AX3 and the Focused header row ("E1RM", 48 pt column) are the two to measure.
- Dynamic Type: unchanged mechanism (`relativeTo:`); the display sizes stay fixed because they live inside rings.

### 4.2 The wordmark

`Wordmark`: Inter Bold, uppercase `Text(verbatim: "RYFT")`, tracking **-0.04 em**, size 17 in the header (`markSize * 0.85`), 32 in the
lock-up; gap mark-to-word `markSize * 0.45` as today (the tracking trims the trailing space, so add the tracking back as trailing padding to centre
the lock-up: one tracking unit, `size * 0.04`). The mark is unchanged and round. The lock-up tagline stays "Your whole health."
in `label` style, tracking +0.08 em (the lock-up's `.tracking(4)` is dark's).

**Web contract**: `tokens.mjs` (this checkout) reads the wordmark with `\.tracking\(size \* ([\d.]+)\)` and the label with
`\.tracking\(([\d.]+)\)`. Neither parses a negative factor, `0.08 * size`, or a scheme branch. Whoever writes the light form must
check it against the pushed `tokens.mjs` of `#142/#143` first, or the web build fails with "tracking not found". If the form can't be
kept, the fix is a one-line regex change on the web side, which is not mine to make.

### 4.3 Radius 0: what changes and what stays round

Rule: **containers and controls are rectangles; instruments are round.** An instrument is a mark that shows a quantity or the
brand: the orbit gauge, `MetricGauge`, the mark, a progress ring, a value dot. A pill-shaped container is not an instrument.

`Theme.Metrics.cardRadius` and `tileRadius` go to 0 in light; the literals do not follow, so every one of the following needs an
explicit decision:

| Element | Today | Light decision |
| --- | --- | --- |
| `Card`, `MetricTile`, `InsightCard`, sheets' panels | `surface` fill, radius 18/16, no edge | White (= background), **1 pt ink edge (`strokeBorder`)**, radius 0. The fill alone can't separate white from white. Padding 18 stays |
| Orbit gauge, `MetricGauge`, `RyftMark`, value dots, `HealthIllustration` disc | round | **Stay round** |
| Done / active check button (56 x 56, radius 14) | filled accent / grey ✓ / outline | **Square 56 x 56.** Active: ink fill, white ✓ (21:1). Done: no fill, `textSecondary` ✓ (6.20). Upcoming: 1 pt `textTertiary` edge (4.76:1) |
| Strip tile (56, radius 14), done badge (16 circle), current ring, superset bar (3 pt capsule), `+` tile | | Tile square, `surfaceRaised`. Current: 2 pt ink inset ring, square. Done badge: **16 x 16 square**, ink, white ✓ 9 pt. Superset bar: 3 pt full-width rectangle, ink. `+` tile: 1 pt dashed `separator` edge, square |
| Rest pill (48 high, capsule) | idle outline / running filled | **Rectangle**, same sizes (idle min 112 wide, running 144). Idle: white, 1 pt ink edge. Running: ink fill, white time (21:1). The 24 pt countdown ring inside stays round (it is an instrument) |
| Keypad keys (`NumberPad`, radius 14, `surfaceRaised`) | 8 pt gaps | **A flush grid**: keys square, no gaps, 1 pt ink rules between and around (a keypad is a grid). Label `ryftNumber` 22. Pressed: ink fill, white label, instant. The Done key: ink fill, white label (primary). This is the one place a deliberate full grid is right |
| Rest-sheet keys (-15 s / +15 s, 56 pt) | | Square, 1 pt ink edge, same pressed inversion |
| Chips (Focused row, radius capsule, 32 high, 44 hit) | `surface` + 1 pt `separator` | **Rectangle, 1 pt ink edge**, 32 high visual, 44 hit. Text `callout` `textPrimary` 21:1. Disabled: text `textTertiary` 4.76:1, edge `textTertiary` |
| `SegmentedPicker` (capsule in capsule) | `surface` container, `surfaceRaised` selected | Container: 1 pt ink edge, square. **Selected: ink fill, white label (21:1)**; unselected: `textPrimary` label on white. Today's selection is `textPrimary` vs `textSecondary` on two greys, which in mono is 21 vs 6.2 and no shape; the inversion is what makes it unmistakable |
| `StrainPill`, `ProviderBadge`, `SourceBadge`, other capsules | grey or tinted capsule | Rectangle. `StrainPill`: keeps its `#DBDBDB` tint (accent 0.14), ink text. Badges: 1 pt ink edge, no fill |
| `PrimaryButton`, `TealButtonStyle`, `AppleSignInButton` surroundings | capsule | Square, min height 44 (56 for `TealButtonStyle`). Primary: ink fill, white label. Secondary: `surfaceRaised` fill. Destructive: section 2.4. Pressed: ink/white inversion for secondary and destructive; the press scale (0.97) goes in light, because a square that shrinks reads as a bug |
| Tab bar | system | See below |
| Fields (`ryftField` 12 radius, Focused fields 12) | `surfaceRaised` at 0.6 | Square. Idle field: `surfaceRaised`, no edge. Focused: 2 pt ink edge (today's 2 pt accent ring). Active Focused row: white field + 1 pt ink edge (section 5) |
| Progress bars (`ImportProgressBar` 4 pt capsule), `StepRule` capsules (3 pt) | track `separator`, fill accent | Rectangles. **Track = the row rule (`Rule`, ink 0.20, `#CCCCCC`), fill = ink** (section 4.4). Light only: dark keeps its track (`separator`, 8 % Mist) as today |
| Toast (`UndoToast`), banners (`InlineMessage`), `OfflinePill` | | Rectangle, 1 pt ink edge |
| Plate calculator plates (3 pt radius) | coloured by weight | Square-cornered, **height and width are the weight cue** (already). Fill: 25 and 20 kg solid ink with white 8 pt label; 15, 10, 5 and under white with a 1.5 pt ink edge and an ink label. Today's label is `Theme.graphite` on `alert` `#000`, which is invisible |

**Tab bar.** iOS 26 and later draw a floating system bar the app can't reshape: leave its shape. Colours: selected tint = ink;
**unselected becomes `textSecondary` (6.20:1), not `textPrimary` at 0.5 (3.98:1, which fails the 4.5 text minimum)**. Selection
must not rely on lightness alone: selected uses the filled symbol variant; unselected the outline variant. Tab symbols are all `.fill` today, so the outline for unselected is new: it needs a look branch, and dark stays `.fill`. The label keeps its weight, because a bold one can't be light only. Before
iOS 26 (`#unavailable(iOS 26)` branch): opaque white bar, 1 pt ink top rule (the existing `shadowColor = Separator` already does it), no
rounded elements. Dark: unchanged.

### 4.4 Rule weights, and does a full-ink 1 pt separator make a grid?

**Yes, in list-heavy screens, and I'd fix it.** Counting rows by code (not rendered): the screens that put a divider between every row
of a long list are Add exercise (`AddExerciseSheet` 90, about 14 rows visible), Splits table, Exercise detail, Journal groups, Import
preview, My Day rows, Notification settings and the Plan builder. At 44 to 56 pt per row that is a full-black line every
~50 pt, 8 to 16 of them in one viewport, each at 21:1 on white, plus the card edges. It reads as a ledger, and the lines outweigh
the text beside them (text is 11 to 16 pt; the rule is the loudest object). Profile and Today, with few rows per card, are fine.

A second, worse problem: `Theme.separator` is used as a **fill or a gridline** in 8 places (of 78 uses; 39 are row dividers), written when it was 8 % Mist:

| Use of `separator` | Where | Now |
| --- | --- | --- |
| Inactive step segment | `StepRule` | `accent` and `separator` are both `#000`: **the progress rule shows no progress** |
| Progress track | `ImportProgressBar`, Behaviors whisker track, `ImportFileSlot` line | a full black bar with a black fill on it |
| Chart gridlines | `ChartStyle.yAxis` 0.5 pt, `Hypnogram`, `MiniHypnogram`, `BedtimeStrip` | solid black lines through every chart |
| Row dividers | 39 `Divider().overlay(Theme.separator)` | the ledger |

**Fix: three rule weights, so `separator` keeps one job.**

| Rule | Token (value) | Width | Where | Contrast |
| --- | --- | --- | --- | --- |
| Edge | `separator`, `#000` | 1 pt | card, tile, chip, field-on-tint, toast and sheet edges; the section break above a pinned bar; the tab bar's top rule | 21.00 |
| Row rule | **new, ink at 0.20** (`#CCCCCC` on white) **(mine)** | 1 pt | `Divider`s between rows inside a card; hypnogram, chart and bedtime gridlines (0.5 pt) | 1.61:1; decorative: the rows are separated by 44 pt hit areas and spacing, not by the line |
| Track (progress) | the row rule, `#CCCCCC` (light only; dark keeps its track as today) | any | step rule inactive, progress tracks, whisker track | 1.61:1; carries "n of m" text or a number beside it. The orbit, `MetricGauge` and stage-bar tracks stay `surfaceRaised` (`#EBEBEB`, 1.19:1) |

The row rule is a new colour set `Rule` / `Theme.rule` (`architecture.md`), `separator` kept for edges. Decided (`plan.md` D2); this
departs from ADR 0015 and the website's row rules. Every swap in this section is light only: dark keeps its current fill or line.

Hairline grid vs lattice: cards in a 2-column grid (`TrackerPickerGrid`) become a lattice of outlined boxes with 12 pt gaps. That is
the intended Alpine look and it is a selection grid, where the edges are the controls; keep.

The Focused set table is not a grid: only the active row has field edges; done rows have none; upcoming rows have the ✓ square
outline in `textTertiary` (not `separator`), which is why section 5 keeps `FocusedRowInk.upcomingOutline` on tertiary and not
on the full-ink edge.

## 5. Focused session in light

Rows and tokens, reusing the seven-state table of `docs/work/2026-11-04-focused-session/design.md` §3.1. Light only; dark unchanged.

| Part | Light | Contrast | Was relying on |
| --- | --- | --- | --- |
| Active row tint (`CurrentSetHighlight`, `FocusedRowInk.activeTint` 0.10) | `accent` 0.10 over white = `#E6E6E6` | `textPrimary` 16.75, `textSecondary` 5.74, `textTertiary` **4.49 (not allowed here)** | teal tint on Mist |
| Active row leading bar | 2 pt ink, square (was capsule) | 21.00 | not hue |
| Active `#` and fields (`raisedFill`) | `surface` white (code already picks `surface` in light) **+ 1 pt ink edge** | white on tint is 1.25:1, so the edge is needed (old note: "`surface` at 1.28:1, about dark's step") | tone step on a tint |
| `#` pill with dot | 32 x 32 **square** (was capsule), dot 5 pt ink, top-right | | |
| Estimate (RM) column | `FocusedRowInk.estimate`: the light special case for the active row (`textPrimary`, "grey is 4.51:1") **can go**: `textSecondary` on the new tint is 5.74:1, a margin of 1.25. Recommended: delete the light branch so the estimate is quieter than the values in both appearances | 5.74 | old tint maths |
| Done row | values `textSecondary` (6.20), ✓ `textSecondary`, no edge | 6.20 | |
| Upcoming ✓ outline (`FocusedRowInk.upcomingOutline`) | `textTertiary`, 1 pt, **square 56** (was 14 radius) | 4.76 (3:1 needed) | unchanged, still passes |
| Ghost value | `textSecondary` | 6.20 on white, 5.74 on the tint | |
| Empty dash | `textTertiary` on white / track only; on the active row `textSecondary` (the code already does) | 4.76 / 4.56 | |
| Warm-up `W` (number slot) | `textSecondary`, replaces `warning` (section 3) | 6.20 / 5.74 / 5.85 | the one hue cue in the table |
| Strip tile text | `textSecondary` on `surfaceRaised` | **5.85** (the Focused note said "6:1 or better"; it is 5.85) | |
| Strip current tile | 2 pt ink ring, number `textPrimary` | 17.62 | not hue |
| Strip done badge | 16 x 16 ink square, white ✓ | 21.00 | |
| Strip superset bar | 3 pt ink rectangle | 21.00 | the "teal ring and bar, one hue two shapes" line is now one ink two shapes |
| Chips | white, 1 pt ink edge, 32 high, rectangle; text 21:1; disabled `textTertiary` | 4.76 on white | the chip row was "never accent" (still true: ink, not accent) |
| Rest pill idle / running / finished | white + 1 pt ink edge / ink fill + white `ryftNumber` 24 (21:1) / flash = `accent` 0.25 for 250 ms (`#BFBFBF`) with `textPrimary` 11.4:1 | | the flash was teal on Mist |
| Keypad | flush ink-ruled grid (section 4.3). Digits `textPrimary`. Pressed inverts | | |
| Finish | unfilled: white, 1 pt ink edge, ink label; filled at all-done: ink, white label | 21.00 | the edge-only 1.13:1 note in the old design is gone: the edge is now ink |
| RPE line / quiet caption | `textSecondary` / `textPrimary` as today | 6.20 | |
| Last-time card | `Card` (1 pt edge), rows `textSecondary`, header `label` `textTertiary` on white | 4.76 | |

What no longer holds in the old Focused note: "colour is the only cue" lines about teal ("one hue, two shapes", the teal
chip warning, "teal as the one accent on the screen") become "ink"; the contrast sums quoting Mist or `#E8E7E3` grounds
(4.9:1 for `textSecondary`, 4.72:1 for the outline, the Finish capsule's 1.13:1) are replaced by the numbers in the column above. The
"one accent per screen" rule is moot in light: there is no accent hue, so the dominant control is the one with the ink fill.

`FocusedRowInkTests` and `FocusedPolishTests`: update the "grey is 4.51:1" comments; `theOutline` stays as is;
`theEstimateOnTheActiveRow` either keeps `textPrimary` (if the light branch is kept) or asserts `textSecondary >= 4.5` on the
tint (if deleted). The test file's `tint(_:)` helper already composes `accent` at `activeTint`; it follows the new colour set with no change.

## 6. Strings that name a colour, for localization-editor

I searched all three catalogs (`Ryft/Resources/Localizable.xcstrings` 1,771 keys, `InfoPlist.xcstrings`,
`RyftWidgets/Localizable.xcstrings`) in both languages for colour words (red, green, yellow, amber, orange, blue, purple, indigo,
teal, sage, mist, graphite, slate, colour, hue, tint, shade, grey/black/white and the German Rot, Grün, Gelb, Blau, Lila, Farbe,
farbig and inflections), and the Swift sources for the same inside string literals and accessibility labels.

**One string in the app names a colour.**

| Where | Key (en) | Current de | Problem | Proposed en | Proposed de |
| --- | --- | --- | --- | --- | --- |
| `CoachMarks.swift:21`, the physiology coach mark | "Tap a tile for the details. The word under recovery is its band, so the colour is never the only cue." | "Tippe auf eine Kachel für die Details. Das Wort unter der Erholung nennt ihren Bereich, die Farbe ist also nie der einzige Hinweis." | Light has no hue; the sentence has to hold in both appearances. In light the band is also a mark | "Tap a tile for the details. The word under recovery is its band, so no colour or mark is ever the only cue." | "Tippe auf eine Kachel für die Details. Das Wort unter der Erholung nennt ihren Bereich, ein Zeichen oder eine Farbe ist also nie der einzige Hinweis." |

Light gets a **new key** with the proposed wording; **dark keeps the old key and sentence unchanged** (it is still true there).

Checked and **not** naming a colour (no change): the band words High / Moderate / Low (spoken as "71, High"), the strain sentences
"above today's recommended range", severity labels "Insight / Notice / Attention", "Dark / Light / System" (appearance names),
"Appearance", the alarm strings that contain "ring" (to ring), "Pick your watch, band or ring" (a wearable), and the zone and stage
legends (they use Z1 to Z5 and stage names).

**New strings the design needs: none**, by design: the band mark, severity glyph, hatch, hollow arrows and outlined button are
visual; VoiceOver already says the band word, "above today's recommended range", direction and magnitude, and the destructive
label. The one new string is the hero (section 8).

## 7. State inventory per screen

"Changes" lists what looks different in light. "Same" lists what is deliberately untouched. Every state keeps its trigger and its
copy; no state is added or removed. Dark: every row is unchanged.

### 7.1 Today
| State | Trigger | Changes | Same |
| --- | --- | --- | --- |
| Scored | `day.hero == .score` | Orbit in ink/grey; centre ring by band (solid / 16 dashes / outlined); band mark before the word; strain rail dashed hairline; past-band hatch | Number, caption, delta text and arrows (delta arrows by polarity, 2.4), speech |
| Past the band | strain > band upper end | Hatched stretch and dot | VoiceOver "above today's recommended range" |
| Pending | night not scored | Previous day at 0.6 ink; Sleep in ink; number `textTertiary`; breathing | Copy, the 15 s tick, still under Reduce Motion |
| Pending, no previous day | | Three hollow dots at 0.6, dash | |
| Calibrating | baselines | Filled segments ink; track grey | "3 / 7", the note, the link |
| Importing | `.importing` | `ImportCard` bar: track the row rule in light (dark unchanged), fill ink; step chips square (the active one `accent` ink fill) | Copy |
| Tiles | | Square outlined tiles; the Recovery icon is ink (band is in the caption word + mark); dimmed tile = value `textTertiary`, icon at 0.5 | Captions, VoiceOver "not today's score" |
| Status line, hints, offline, refresh issue, sync paused | | `InlineMessage`: 1 pt ink edge, glyph; warning-coloured lines go to ink + glyph (2.4); `OfflinePill` square | Copy |
| Trends card | | Chart line ink, gridlines row-rule | Data |

### 7.2 Sleep
| State | Changes | Same |
| --- | --- | --- |
| Loading | `ProgressView` tint ink | |
| Night with stages | `StageBar` ruled (2.5); legend squares with edge; hypnogram greys, row identifies stage | Durations, shares |
| Night without stages ("unstaged") | Unstaged = H2 hatch | Copy |
| Sleep need | `SleepNeedBar`: base `#6B`, strain ink, debt H3, nap dashed | Sentence, legend labels |
| Debt high | `valueColor` warning -> `textPrimary` + glyph | Number |
| Consistency (steady / fair / irregular / unknown) | Glyph variants (2.5), no hue | Hint sentence |
| Range charts | One series ink / `#6B`, row-rule grid | Axis labels |
| Planner (bedtime, alarm, "Not allowed in iOS Settings") | `warning` text lines -> `textPrimary` + glyph; toggles tint ink | Copy |

### 7.3 Strain
| State | Changes | Same |
| --- | --- | --- |
| Scored | `MetricGauge` ring ink, target = outlined arc; band word has no band mark (strain has no good/bad band) | Value, delta, "All out / High strain ..." |
| Zones | `ZoneBar` hatch ladder, 16 pt, ruled | Minutes, ranges, "Zones in % of heart-rate reserve" |
| Workouts list | `StrainPill`: grey fill + ink text, square | Rows, subtitles |
| No data / loading | | `ProgressView` ink |
| Workout detail | Zone bar as above; the glyph discs (accent 12 %) behind header icons become 40 x 40 squares, same tint | Splits table gets row rules |

### 7.4 Insights
| State | Changes | Same |
| --- | --- | --- |
| Insight cards | 1 / 2 / 3-bar glyph; ink left rule; label word ink | Title, body, "Show the chart", dismiss |
| Charts | Series ink; `rhr` and `heartRate` (were `alert`) ink; steps and respiratory rate `#6B`; active energy (`warning`) -> `#6B`; grids row-rule | Axis, selection |
| Range bar | Status arrows by polarity (2.4); the typical band stays flat `surfaceRaised` (it is a range, not a level, so no hatch) | Words "below / in range / above" |
| Behaviors | Filled / hollow dot by polarity; whisker ink at 0.35 -> `#6B` | Copy |
| Empty / failed / offline | Square messages, glyph | Copy |

### 7.5 Train, live session (Focused and List)
| State | Changes | Same |
| --- | --- | --- |
| Focused page, 7 row states | Section 5 | Behaviour, identifiers, the state table |
| Strip | Square tiles, ink ring, square badge | Order, reorder, VoiceOver |
| Chips, warm-up pill (outlined rectangle, chevron), last-time card | Square, 1 pt edges | |
| Rest pill, rest sheet | Rectangle; keys square | Timer behaviour |
| Keypad | Ruled grid | Layout rules at 320 and AX3 |
| All-done card, Finish | Ink fills | |
| List layout | `ExerciseCard` done-row tint `accent` 0.06 = `#F0F0F0`; check button square; swipe reveal outlined (2.4) | Behaviour |
| Plate calculator | Plates by height; solid / outlined (4.3) | Numbers |
| PR/summary (`SessionView`) | Trophy glyph `warning` -> ink | Copy |
| System dialogs | Remain system-drawn, destructive in system red (D3) | |

### 7.6 Profile -> Account
| State | Changes | Same |
| --- | --- | --- |
| Signed in | Card with 1 pt edge; provider badge square, edge; Change password (secondary, grey), Log out (secondary), **Delete account (outlined 2 pt)** | Copy; confirmation dialogs (system) |
| Busy | `ProgressView` ink; button keeps its outline | |
| Error | `InlineMessage`: glyph + `textPrimary`, Details | |
| Signed out (demo) | | |
| Appearance picker | Segmented control inverts (4.3). The `Dark / Light / System` words | Behaviour |
| Other sections (Privacy, Data, Developer) | Withdraw consent and Full re-sync outlined; consent/Health status values `warning` -> `textPrimary` + glyph | |

### 7.7 Onboarding
`WelcomeView`, `AuthComponents` (create account, log in, forgot password, check inbox) and `PlatformConfig` force `.dark`: **no
change in this pass**, and they never show light. The steps that follow the appearance change:
| Step | Changes | Same |
| --- | --- | --- |
| Invite code, consent, about you (birth year, minimum age 16), what do you wear (`TrackerPickerGrid`), set-up | Cards square with 1 pt edges; selection card = 1.5 pt ink edge + ✓ (already `accent` 1.5 pt), chosen state also gets the filled ✓; `StepRule` track the row rule in light (dark unchanged), fill ink, with "Step n of m" text | Copy, order, the pinned bar |
| Health permission | `HealthIllustration`: heart ink, disc `#E6E6E6` (round, decorative); the Workouts warning line `warning` -> `textPrimary` + glyph | Copy |

## 8. "Engineered for peak."

The user's hero statement. English text is fixed; German is a draft for the editor and the user.

| Key | en | de (draft) |
| --- | --- | --- |
| Hero | Engineered for peak. | Für den Gipfel gebaut. |
| Hero, VoiceOver | Engineered for peak. | Für den Gipfel gebaut. |

Style (light): `display`-class, Inter Bold, caps, -0.07 em, 40 pt (`numberLarge` size) left-aligned, `textPrimary`, one rule (1 pt ink)
above it; Dynamic Type caps at AX2 (it is a statement, not content); it wraps to three lines at 390 pt, which is why 40 and not 56.
The tagline "Your whole health." stays below the lock-up in `label` style, as the brief says.

Where it goes (`plan.md`: owned by T6):
1. **Profile -> About, above the lock-up, in light only.** Dark shows no hero. The key is new and only light reads it.
2. Onboarding and the store screenshots keep the hero they have until the dark pass; this pass adds none there.
3. Not on Welcome (forced dark), Today, the widget, notifications or empty states.

## 9. What the swatch sheet and the previews must show (later, with the code)

**Swatch sheet** (a `#Preview` in light, plus a PNG for the PR; one page per group):
- The ten greys with hex, role and the contrast on white and on the track (section 1), the failing ones marked (`#8A8A8A`, REM, Awake, tertiary on the tint).
- The ladder L0, H1 to H5 as 64 x 64 squares, plain and **at actual size** (16 pt, 10 pt fine) at 1x, 2x and 3x; a greyscale rendering next to each.
- The three band levels as the mark (10 pt), as the orbit centre ring at 160, 112 and 72 dials, and as `MetricGauge`.
- Orbit states at 160 and 112: scored, past the band (hatch) and under 131 (dashed), pending at 1.0 and at the 0.75 breath, calibrating, no previous day; with the rail.
- Zone bar with all five, with one narrow sliver, and with zero minutes; stage bar with unstaged; the sleep-need bar.
- Severity glyphs 1/2/3; arrows filled and outlined; the three buttons stacked; segmented control; chip row; keypad; rest pill idle and running; strip tiles.
- The three rule weights on a long list and on a chart (section 4.4's row rule is decided; confirm by eye).
- The type scale in Inter with tracking, Dynamic Type default and AX3, English and German `label` at 11 pt.
- Everything also in **greyscale** with the hue removed from the photo (so you can check it holds without brightness), and at AX3.

**Previews** (light, then confirm dark is bit-identical): Today in all four hero states, Sleep, Strain, Insights, Profile -> Account,
a Focused page in seven row states, onboarding steps; each at 390 and 320, default and AX3, English and German, and with Reduce
Motion for the pending gauge. The dark previews are compared byte for byte against `main` (the Alpine branch must not move them).

## 10. Open decisions for the user

**Decided on 2026-11-05, see [`plan.md`](plan.md):** D1 leave both as they are (option A), D2 the soft row rule, D3 accept the red system buttons, D4 add the arrows, D5 keep both fonts until the dark pass, D6 answered in `architecture.md` §4. The questions stay as asked, for the record.

- **D1. Welcome and the auth screens.** They are forced dark and the default appearance is dark, so most users never see this pass,
  and the hero can't live on Welcome. Option A (my recommendation for this pass): leave both as they are; the pass is visible only
  to users who choose Light. Option B: drop the forced dark on Welcome and auth in light only (they would follow the appearance
  setting), so the hero can open the app. B touches a screen the brief did not scope.
- **D2. The row rule.** Add a soft rule token (ink at 0.20) for dividers, gridlines and tracks, keeping full-ink `separator` for
  edges (my recommendation), or keep one full-ink separator everywhere and accept the ledger.
- **D3. System-drawn destructive buttons** (alerts, confirmation dialogs, context menus) stay red; no code can make them ink. Accept
  that one hue, or replace the Delete-account and Withdraw confirmations with an in-app sheet in the outlined style (extra work,
  and it loses the system's accessibility for alerts).
- **D4. Polarity arrows** (filled toward better, outlined toward worse) are my proposal and not in the brief; without them a
  good and a bad change look the same in light.
- **D5. Fonts in dark.** Keeping dark exact means shipping both Satoshi and Inter. If you'd rather retire Satoshi with the dark pass,
  say so now and architecture can plan the removal.
- **D6. Web contract.** Confirm with whoever owns `tokens.mjs` that the negative-em and scheme-gated tracking can be parsed (section 4.2).
