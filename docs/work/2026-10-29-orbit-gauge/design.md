# OrbitGauge: design note (PR 1, the component)

Component: `Ryft/Design/OrbitGauge.swift` (view, `OrbitArc`, `OrbitDot`, previews), `OrbitGaugeGeometry.swift` (numbers),
`OrbitGaugeModel.swift` (`OrbitGaugeValues`, `OrbitGaugeMode`, `OrbitGaugeCalibration`; Foundation only, easy to move).
Tests: `OrbitGaugeGeometryTests` (angles, spacing, sentence), `OrbitGaugeContrastTests` (the numbers below).
Screenshots: `docs/work/2026-10-29-orbit-gauge/shots/`, produced by `make orbit-shots` (the `OrbitGaugeShotsTests` suite
renders the same views as the `#Preview`s with `ImageRenderer`, light and dark; a simulator named `orbit-ui` by default).

## 1. Geometry, and how it moved from the brief's numbers

Reference drawing: `.large`, dial 160 pt, frame 172 pt. Radii are stroke centrelines. Everything scales by dial / 160
with a floor (stroke 1.5 pt, dot radius 1.15 x stroke), the way `RyftMarkGeometry.metrics(forSide:)` does it.

| Element | Brief (start) | Built | Why it moved |
| --- | --- | --- | --- |
| Outer orbit (Strain) | r about 80, stroke 6 | r 77, stroke 5.5 (outer edge 79.75) | the edge stays at the dial's 80; strokes lighter so the dots can grow |
| Inner orbit | r about 50, stroke 6 | r 54, stroke 5.5 | even spacing: 23 pt outer to inner, 22 pt inner to centre (the mark's rings: 18.4 / 18.0 of 44) |
| Centre ring | r about 16, stroke 5 | r 32, stroke 4.5 | the number lives inside it. A 16 pt ring holds nothing: "71" at 30 pt is 36 pt wide. The icon's own centre ring (13 pt at this scale) is the one real departure from the mark |
| Dots | 9 pt | radius 9 (18 pt across), hollow outline 2 pt | at 9 pt across (first render, radius 7 was also tried) the dots read as thick arc ends, not as "you are here". 18 pt is 3.3 x the stroke; the icon's dots are 3.8 x |
| Air around a dot | none | 2.5 pt cut out of the track around every dot | the mark breaks its ring where a dot sits; here the track ahead of the dot is cut the same way |
| Caps | butt | round | the mark's caps are round; `MetricGauge`'s butt caps would make the 44 pt render read as a different object |
| Inner start | both at 0 deg | 12.5 deg either side of the top (see below) | two dots on one spot |

Frames equal `MetricGauge`'s outer frame (dial + 12): `.small` 84, `.medium` 124, `.large` 172, so nothing around the gauge
moves. The dial is 72 / 112 / 160 (scale 0.45 / 0.70 / 1.0). `Size.custom(dial:)` exists for the widget's other families and
for the 44 pt check; screens use the three.

What the centre lost: `MetricGauge`'s mark, the "OVERALL READINESS" caption and "/ 100" do not fit inside a 59 pt ring. The
gauge is the mark now, and the VoiceOver label carries the name. Open question for the lead: whether Today wants the caption
above the gauge.

Number: `ryftNumber(size: dial x 0.19)` (30 / 21 / 14 pt), tabular, fixed size (the gauge keeps its size under Dynamic Type),
`minimumScaleFactor 0.6` so "100" fits. Below a dial of 56 pt the number is omitted: it would be under 10.5 pt.

## 2. Mapping

Angles are degrees clockwise from 12 o'clock; f is the fraction of the score's scale.

| Score | Orbit | Direction | Start | Head at f | Whole |
| --- | --- | --- | --- | --- | --- |
| Recovery (teal, `Theme.accent`) | inner | counter-clockwise | -12.5 deg | -(12.5 + 155 f) | f = 1: 167.5 deg left of the top |
| Sleep (`Theme.metricSleep`) | inner | clockwise | +12.5 deg | 12.5 + 155 f | f = 1: 167.5 deg right of the top |
| Strain (`Theme.metricStrain`) | outer | clockwise | 0 deg | 360 f, f = strain / 21 | 21 = 359.99 deg (a closed ring) |
| Readiness | centre ring + number | none | | | a full ring in the band colour |

Change to the brief: Recovery and Sleep do not meet at exactly 180 deg. Both start at the top, so at 0 (and, at 100 %, at the
bottom) their two dots would share a spot, and a missing Recovery and a missing Sleep would be one hollow dot. Each half starts
12.5 deg from the vertical, so the two dots always keep 23 pt (a dot's width plus 5 pt of air) between them. The mapping stays
linear and f = 0.5 is exactly 3 and 9 o'clock. The inner orbit now reads as the icon's middle ring: two dots, two arcs.

Example (71 / 71 % / 88 % / 9.6): Recovery head at -122.5 deg (lower left), Sleep at 148.9 deg (lower right), Strain at
164.6 deg, close to where the icon's outer dot sits (155 deg). 0 is a filled dot at the start with no arc; missing is a hollow dot.

## 3. Colour and hollow-dot rules

- Tracks: `Theme.surfaceRaised`, round caps; the inner orbit's tracks are two half rings (the gaps are where the dots start and
  meet), the outer one a full ring.
- Arc and dot: the orbit's metric colour, no gradient, no glow. Recovery is teal, Sleep indigo, Strain blue.
- Missing score: a hollow dot at the start (2 pt outline in the orbit's colour, the track cut out of its inside), no arc. Zero is
  a filled dot with no arc. A hollow dot never means "low".
- Centre ring: `Theme.band(forScore:)` (teal / yellow / red at 67 / 34) with a readiness, `Theme.textTertiary` without one (and a
  tertiary "-" inside; 5.25:1 dark, 4.72:1 light on the background). It is a ring, not an arc: the number is the readiness, the ring only carries its band.
- Teal appears twice at a high band (Recovery and the centre ring). It stays one accent: they never carry different meanings.
- Stubs (`.calibrating`, `.assembling`, `.pending`): tracks, a centre ring in the track colour and three hollow dots; PR 2 and 3 do the rest.

## 4. The 44 pt check ("still the app icon")

`shots/icon-44-{dark,light}.png`: the app icon's tile (the `RyftMark` at the icon's 0.963 ring span on Graphite / Mist, the
same drawing as `scripts/icon-spec.swift`) beside two gauges (71 / 71 % / 88 % / 9.6 and 64 / 62 % / 55 % / 14) at a dial of 44 pt,
and again at 88 pt. I judged it by looking at the 44 pt row at 1x and the 88 pt row at 3x, covering the colours (squint test) and
comparing the silhouette: three concentric rings; two dots on the middle ring, one on the outer; the middle ring broken in
two places, the outer ring ending in a dot.

Verdict: yes, as the same object in colour. At 44 pt the stroke floor (1.5 pt) and the dot floor keep all three rings and three dots
apart; the number is dropped below 56 pt, which makes the 44 pt render more like the icon, not less. Where it differs: the centre ring
is 2.4 times the icon's (the number must fit), and the outer ring is only drawn up to the dot, with the rest as a faint track
(the icon's is a bright ring broken once). A 64 / 55 % example with the outer dot at the left reads less like the icon than 71 / 88 %,
whose dots fall near the icon's: the likeness depends on the day, the structure does not.

## 5. Colour-blind check

Simulated with the Machado 2009 matrices (severity 1.0) on the rendered shots: `shots/sizes-{protanopia,deuteranopia,tritanopia}-
{dark,light}.png` (the CoreImage colour matrix is applied in sRGB-encoded values, an approximation; the simulator's own filter was
not scriptable from `simctl`). Result: under protan and deutan vision the teal turns grey and Sleep and Strain both turn blue,
so colour alone does not separate the three. Position and direction do, by construction: Strain is the only outer ring; Recovery
is the inner arc that grows to the left of the top, Sleep the one that grows to the right. Nothing is encoded in colour only.
The centre ring's band colour (teal / yellow / red) is also in the number and the band word under the gauge.

## 6. VoiceOver

One element, `accessibilityElement(children: .ignore)`; label "Overall readiness"; identifier from the caller (`identifier:`, default
`orbitGauge`; Today passes `today.readinessGauge`); the caller's `accessibilityNote` is appended after a full stop, as `MetricGauge` does.

Value (scored): "71, High. Recovery 71 percent, Sleep 88 percent, Strain 9.6 of 21". A missing score is named, never skipped:
"Sleep, no data". No readiness: "Overall readiness, no data. Recovery ...". Nothing at all: "No data". The other modes say
"Not scored yet" until PR 2 / 3 write their sentences. German: "71, Hoch. Erholung 71 Prozent, Schlaf 88 Prozent, Belastung 9,6 von 21".
Strings added: `Recovery %@ percent`, `Sleep %@ percent`, `Strain %@ of 21`, `%@, no data`, `Overall readiness, no data` (de, no en entries).

Motion: a changed value moves the arcs and dots on `Theme.Motion.slow` (0.6 s, ease-out) from where they were, the number rolls with
`numericText`. The first frame draws at the value (PR 3 owns the launch). Reduce Motion: no sweep and no roll; a new value cross-fades
over 250 ms (`Theme.Motion.quick`). Nothing rotates on its own. Dynamic Type: the gauge does not scale (fixed 172 / 124 / 84 pt frames,
fixed-size number); the captions around it do (`OrbitGauge · AX3` previews).

## 6b. Contrast of each graphic on its track (WCAG 1.4.11, 3:1)

Computed in `OrbitGaugeContrastTests` from the asset-catalog colours (relative luminance, resolved per appearance). Track =
`surfaceRaised`; `shots/contrast.txt` has the raw output.

| Graphic | Dark, on track | Dark, on background | Light, on track | Light, on background |
| --- | --- | --- | --- | --- |
| Recovery / high band (`accent`) | 6.97 | 10.09 | 3.97 | 4.54 |
| Sleep (`metricSleep`) | 4.38 | 6.34 | 4.36 | 4.98 |
| Strain (`metricStrain`) | 4.12 | 5.97 | 4.42 | 5.04 |
| Moderate band (`warning`) | 7.69 | 11.14 | 4.03 | 4.61 |
| Low band (`alert`) | 4.13 | 5.99 | 3.99 | 4.55 |
| Centre ring without readiness (`textTertiary`, composited) | | 5.25 | | 4.72 |

All at least 3:1 (the lowest: light Recovery, 3.97). The track itself is 1.45:1 on the dark background and 1.14:1 on the light one:
it is the empty scale, not information, and is the same as `MetricGauge`'s; the hollow dots (2 pt coloured outline) carry the
"missing" state and have the contrast of the arc colours on the background. The number is `textPrimary` (15.59:1).

The edge preview labelled "0" had passed readiness 1; it now passes 0, and `readinessZeroIsZeroNotOne` covers the number and the spoken value.

## 7. Tried and rejected

- Three concentric full rings with one arc each: a gauge, not the logo (the brief's own example).
- The brief's dot size (9 pt across) and my first guess (radius 7): dots as thick arc ends; the icon's dots are the point of the mark.
- Both inner halves from exactly 0 to 180 deg: two dots on one spot at 0 and at 100 %, and two hollow dots at the top overlapping.
- Butt caps: tidy, but a different object from the icon at 44 pt.
- A 16 pt centre ring with the number under the gauge: loses "the number inside" and the likeness of a small bright centre is not worth an extra line.
- The mark (18 pt) and the "OVERALL READINESS" caption inside the centre ring: no room at 59 pt; the gauge is the mark.
- Animating the first appearance from zero (as `MetricGauge` does): a launch effect that PR 3 owns, and it makes snapshots time-dependent.
- Inner start inset 9 deg / 10 deg: the two end dots at 100 % kept 17 / 19 pt, less than the new dot's width plus air.

## 8. Proposals for later PRs (the geometry leaves room)

**PR 2, calibrating (7 segments).** The outer orbit becomes seven round-capped segments with the seam at the top, where the outer
hollow dot sits: the segments start 9 deg after the top and end 9 deg before it (the dot's half-width plus its air), so the dot never
cuts one; the 7 x 44.6 deg segments are separated by 5 deg (6.7 pt on r 77, 4 pt of air after the caps). `nights` of them in `Theme.accent`
(the teal of the baselines, as `BaselineGauge`), the rest `surfaceRaised`, filling clockwise, one after another at 60 ms each (no motion
under Reduce Motion). Inner orbit and centre ring stay tracks, the three dots hollow at their starts. "3 / 7" in the centre
number's place at `.large` and `.medium` (`ryftNumber`, same size as the readiness), "of 7 nights" in the VoiceOver sentence. Path S2
(readiness computed while the baseline is still learning): the scored gauge with the seven segments under the Strain arc at
0.35 opacity would sit on the same radius as the arc, so they are only visible past its head; I expect that to be too faint
at `.large` and unreadable at `.small`, so S2 keeps the note only, unless the lead wants the experiment. `OrbitGaugeCalibration.counted`
already clamps nights to the requirement.

**PR 4, strain band.** A rail inside the outer ring: radius 69.5, stroke 3, `butt` caps, `metricStrain` at 0.35, from the band's lower to
upper end on the 0-21 scale (360 x v / 21 degrees). It sits in the corridor between the outer ring's inner edge (74.25) and the inner
dots' outer edge (63), 3 pt clear of the first and 6.5 pt of the second, and the arc's dot passes over it. Past the band's upper end the
arc is split into two `OrbitArc`s: up to the end in `metricStrain`, beyond it in `Theme.alert` mixed 60 / 40 with the strain hue
(designer's first guess; to be tuned against 3:1 on the track, `alert` alone is 4.13 dark and 3.99 light), the dot taking the colour of
its segment. `OrbitGaugeValues.strainBand` is already in the model and ignored by the drawing.

## 9. PR 2: calibrating and pending (as built)

Shots: `shots/pr2-calibrating-{dark,light}.png` (0 / 3 / 7 nights at large, medium, small), `pr2-pending-{dark,light}.png`
(with and without a previous day at the three sizes), `pr2-calibrating-3-large-*`, `pr2-pending-large-*`, `pr2-scored-reference-*`.
Raw numbers: `shots/pr2-contrast.txt`. Compared with `design/brand-board.png`: the same thin rings and hollow orbit dots as the mark,
teal as the only accent, nothing rotating; the filled segments are the one teal on the screen.

**Segments (differs from section 8 in one number).** Section 8 measured 9 deg and 5 deg on the centrelines, which leaves 1.2 pt of air between
two round caps at r 77 (the caps take 5.5 of the 6.7 pt). Both numbers are now the *visible* distances between cap tips, which is what
the eye measures: the first tip is 9 deg after the top and the last 9 deg before it (the hollow Strain dot with its air spans 8.6 deg, so the dot
never touches a segment), neighbours are 5 deg apart tip to tip. The centrelines are shortened by one cap (stroke / 2 / radius = 2.05 deg) at each
end: 7 segments of 44.57 deg visible, 40.5 deg centreline, starting at 11.05 deg + n x 49.57 deg. `OrbitGaugeGeometry.segments(required:dial:)`
returns them for any `required`; the number scales with the dial because the stroke does.

**Number.** `.large` and `.medium` (dial of 100 pt or more): "3" in the readiness number's size and style (`ryftNumber`, 0.19 x dial,
`textPrimary`), then " / 7" at 0.55 of it in `textTertiary`, one `Text`, `minimumScaleFactor` 0.6. `.small` (and any dial under 100 pt): the count
only, "3": the centre slot is 23 pt wide there, "3 / 7" would drop to about 8 pt, and the seven segments around the number already say "of 7".
The count is `OrbitGaugeCalibration.counted`, so a counter never reads past its requirement. 0 draws "0" and seven unfilled segments: the gauge
can always move.

**Fill motion.** The drawing is static and takes `counted` as given. The app wrapper steps the displayed count up one night per 60 ms
(`OrbitGauge(animatesFill:)`, default true), each segment growing from its start over 60 ms (`easeOut`), when the gauge appears and when `nights`
grows (a lower count is taken at once). Reduce Motion, or `animatesFill: false`, draws the count from the first frame. Previews and snapshots
pass `false`, so nothing depends on time. The widget draws the static count.

**Pending.** `.pending(previous:)` draws `previous` exactly as scored, with all marks (arcs, dots, centre ring) in one group at 0.6 opacity
(`OrbitGaugeMarks.pendingOpacity`, shared, so the widget gets the same), tracks at full strength under them, the number in `textTertiary`
(the previous day's, never in the primary ink). The app wrapper breathes the group between 1.0 and 0.75 of that (0.6 to 0.45 effective) on
1.4 s `easeInOut`, the rhythm of `PendingGauge`'s outline; `breathes: false` holds it still (for "takes longer than usual"), and it
is always still under Reduce Motion. Without a previous day: tracks, the three hollow dots (dimmed the same way) and a dash in the number's place.

**S2** (readiness scored while the baselines still learn) draws the plain scored gauge; `learning` is not drawn (plan.md decision 3).

**VoiceOver.** Calibrating: label "Baselines", value the sentences `BaselineGauge` spoke ("3 of 7 nights. Readiness appears once the baselines
are complete.", and the three signal variants), so no new keys. Pending: "Not scored yet", then "Last scored: 71. Recovery 71 percent, Sleep 88
percent, Strain 9.6 of 21." when there is a previous day, then the caller's `accessibilityNote` (the title and the date).

### Contrast (WCAG 1.4.11 asks 3:1 for graphics)

| Graphic | Dark | Light |
| --- | --- | --- |
| Filled segment (`accent`) on its track / on the background | 6.97 / 10.09 | 3.97 / 4.54 |
| Unfilled segment (the track) on the background | 1.45 | 1.14 |
| Pending accent arc, 0.6, on the background / over the track | 4.23 / 3.50 | 2.35 / 2.21 |
| Pending sleep arc, 0.6 | 2.98 / 2.51 | 2.45 / 2.30 |
| Pending strain arc, 0.6 | 2.85 / 2.41 | 2.47 / 2.33 |
| Pending, trough of the breath (0.45), accent / sleep / strain | 2.87 / 2.17 / 2.10 | 1.86 / 1.91 / 1.93 |
| Pending number (`textTertiary`) | 5.25 | 4.72 |

The filled segments meet 3:1 in both schemes (the lowest is light, 3.97 on the track). The unfilled segments are the empty scale, as in the
scored gauge (same colour as `MetricGauge`'s track): not information; the count in the middle and the filled segments carry it. The dimmed
pending arcs are **below 3:1 on purpose** (1.9 to 4.2): they are "yesterday, not today" and must not compete with the number or look like a score of
today. Nothing is carried by them alone: the previous day's number is 5.25 / 4.72 : 1, the arcs repeat it, and VoiceOver says it. Raising them to 3:1
in light would need roughly 0.8 opacity or more (estimate, not measured), at which a pending gauge reads as a scored one. If the lead prefers 3:1, change `pendingOpacity` (one constant).

## 10. PR 3: the entrance (as built)

Files: `Ryft/Design/OrbitGaugeEntrance.swift` (timings, `OrbitEntranceFrame`, `OrbitEntranceStage`, previews), the wrapper in
`OrbitGauge.swift`. Shots: `shots/pr3-{scored,calibrating,pending}-{dark,light}.png`, each row t = 0, 0.25 s, 0.6 s, end (medium).
Tests: `OrbitGaugeEntranceTests` (the last frame equals the static render byte for byte, in all three modes, dark and light).

**API.** `OrbitGauge(mode:, ..., entrance: .none | .assemble | .assembleOverTracks)`. The view latches the value at its first appearance (`@State`),
plays once per view instance and ignores later changes. `.assembling` is gone from `OrbitGaugeMode`: the mode is data. The first
frame is already the entrance's frame 0 (empty), never the final state.

**Timeline (850 ms, one linear clock, the curves are applied inside `OrbitEntranceFrame`; all ease-out cubic, no springs).**

| Step | Window | What |
| --- | --- | --- |
| 1 | 0 to 250 ms | Tracks trim 0 to 1: outer 0-150, inner 50-200, centre ring 100-250 ms. |
| 2 | 150 to 600 ms | The dots fly from 0.62 x the frame (outside its bounds) to their orbit's start and turn 40 degrees along it; strain, recovery, sleep 30 ms apart, all landed by 600 ms. |
| 3 | 600 to 850 ms | Glide, `Theme.Motion.quick`'s 250 ms: arcs grow from the start, each dot goes from its turned position to the head of its arc (a missing score glides back to the start, hollow), the centre ring changes from its track to the band colour, the number and the caption (title, band word, change) fade in. Never before 600 ms. |

Total 850 ms, inside the 900 ms budget. Calibrating: the dots land hollow at their starts, the seven track segments trim in, and the PR 2
fill (60 ms a night) starts when the entrance has ended (completion callback), so 3 of 7 reads as one more step. Pending: the dimmed marks
(0.6) glide in, and the 1.4 s breathing starts at the last frame. No step 4 (plan.md decision 5).

**Over the placeholder's tracks (review round 3).** On a first launch, and in demo mode, Today shows the no-data gauge (tracks,
hollow dots, a dash, "OVERALL READINESS") until the scores arrive; the entrance plays on the first gauge with something to show
(architecture §4). That gauge replaces the placeholder with `.assembleOverTracks`: its tracks, centre ring and caption title are at
full strength from frame 0, so the rings never blink out; the dots fly in (step 2) and glide (step 3), and the band word and change
fade in with the glide. Under Reduce Motion over tracks only the marks and the number fade.

**The clock.** A `TimelineView(.animation)` reading the time since the first appearance, paused once done. Not a `withAnimation`
transaction: that animated unrelated hero layout changes in the same update (the status line at AX3) along with it (review round 2).

**Seam.** At 850 ms the stage draws the same `OrbitGaugeDrawing` the static path draws, with `.transition(.identity)`: no swap is visible.
A track is cut for the air around a dot only on that dot's own orbit, so a dot flying in leaves no gap in the rings it crosses. Dots are not clipped
while they fly in; they cover up to 0.62 x the frame, so nothing around the gauge may clip it (Today has no clip there).

**Reduce Motion and Low Power Mode.** The same gauge at its values from the first frame, cross-faded in over 250 ms (`Theme.Motion.quick`):
no flight, no rotation, no trim. Low Power Mode is read once when the view is created (`ProcessInfo.isLowPowerModeEnabled`, no
observer: the entrance lasts under a second). The calibrating fill and the pending breathing keep following Reduce Motion only.

**Previews and tests.** `OrbitGauge(..., entrance: .assemble, frozenAt: seconds)` draws one moment without animating (tests, previews):
`frozenAt: OrbitEntranceFrame.end` equals the static render. Previews: "entrance, replay" (scored, calibrating, pending, with a Replay
button), "entrance, Reduce Motion" (`orbitForcesReducedMotion`, as `accessibilityReduceMotion` cannot be set) and "entrance frames".
VoiceOver is unchanged and not delayed: it speaks the final value while the gauge assembles.

## 11. PR 4: strain band (as built)

Files: `Shared/OrbitGaugeGeometry.swift` (the numbers and the decisions), `Shared/OrbitGaugeDrawing.swift` (`OrbitGaugeBandRail`,
`OrbitStrainArc`, `OrbitWedge`), the entrance in `Ryft/Design/OrbitGaugeEntrance.swift`, VoiceOver and previews in
`OrbitGauge.swift`. Shots: `shots/pr4-{band,modes,icon44,entrance}-{dark,light}.png` and `pr4-band-{protanopia,deuteranopia}-*`.
Driven only by `OrbitGaugeValues.strainBand`; Today and the widget still pass nil, and nothing outside the gauge changed.

**Geometry (reference dial 160, scaled by dial / 160).** Rail: centreline r 69.5, stroke 3 (floor 1.5 pt), butt caps, from
`Orbit.strain.headDegrees(lo / 21)` to `(hi / 21)`, so its ends sit where an arc of those strains ends. It lies between the outer ring's
inner edge (74.25) and the inner dots' outer edge (63): 3 pt clear of the ring. The air around the strain dot is cut out of the rail
as it is out of the tracks. Colour `metricStrain` at 0.5 (`bandRailOpacity`; the proposal in §8 said 0.35, which was 1.7:1 and
looked like a rendering error on the light background). The rail is drawn in the marks layer, so a pending gauge dims it with the
rest. Band clamped to 0...21 (`clampedBand`); an empty or one-point range, or one wholly outside the scale, draws nothing and
speaks nothing (`ClosedRange` cannot be inverted).

**Past the band.** Only when strain is above the clamped upper end: the same arc, drawn twice and clipped to either side of the radial line
at the band's upper end (`OrbitWedge`): `metricStrain` before, `alert` after, round caps at both ends, no fringe. The dot is `alert` when it is past. Below
the band, inside it and exactly at its upper end: plain `metricStrain`. Strain missing: the rail and the hollow dot only. Pure
decisions: `strainPastBandDegrees`, `strainTone`, `bandRail`, `drawsBandRail`.

**The mix.** I tried `alert` mixed into `metricStrain` at 50 / 60 / 75 / 90 / 100 %; 100 % wins: a blue-red mix is mauve, and the more blue
in it the less it differs from blue for the colour-blind (table). The shipped colour is `alert` itself (`palette.strainPastBand`).

| Mix toward alert | 50 % | 60 % | 75 % | 90 % | **100 %** |
| --- | --- | --- | --- | --- | --- |
| Dark: on track | 3.74 | 3.76 | 3.84 | 3.99 | **4.13** |
| Light: on track | 4.80 | 4.73 | 4.51 | 4.22 | **3.99** |
| Dark: Lab dE from in-band blue, normal / deutan / protan | 39 / 42 / 34 | 48 / 52 / 41 | 64 / 67 / 54 | 80 / 83 / 67 | **92 / 94 / 76** |
| Light: same | 38 / 43 / 34 | 47 / 53 / 42 | 63 / 69 / 55 | 80 / 85 / 68 | **91 / 96 / 78** |

All mixes reach 3:1 on the track; the choice is the separation. `alert` on the background: 5.99 dark, 4.55 light; `metricStrain` is
4.12 / 4.42 on the track. The two differ little in lightness (ratio 1.0 to 1.4), so the separation is hue only; that is why it is not alone (below). The
rail: 2.33:1 (dark) and 2.09:1 (light) on the background, 2.08 / 1.99 on the track. **Below 3:1 on purpose**: it is the scale of the
target, not the value; the value is the arc, and the range is spoken. Reaching 3:1 needs about 0.75 opacity, where the rail competes with the arc.

**Colour-blind check** (`shots/pr4-band-{protanopia,deuteranopia}-*.png`, the Machado matrices of §5, severity 1.0). Under deutan and protan
vision the past-band arc turns olive / khaki and the in-band arc stays blue: clearly two colours (dE 94 / 76 against 39 to 42 for the 50 % mix).
Nothing is colour-only either: the rail's end and the radial join sit at the same angle, and VoiceOver names the range.

**Sizes.** `.medium` and `.large` draw the rail. At `.small` (72 pt; any dial below 90) it is hidden: a 1.5 pt line 1.4 pt from the outer ring
turned the ring into a double line in the 44 pt test and no longer read as the icon. The shift past the band stays at `.small` (a
colour change, no extra stroke); the 44 / 88 pt shots (`pr4-icon44`) still read as the icon's three rings and dots.

**Modes.** Calibrating: no band. Pending: the previous day's band, dimmed 0.6 with its marks. Locked widget / no mode: unchanged.
**nil parity:** 84 renders (7 modes and states x 3 sizes x light/dark x static/entrance frame) hash-identical between `main` and this branch.

**Entrance.** The rail fades in with the tracks (0 to 250 ms, ease-out); the arc's split is in the glide; Reduce Motion fades it with the marks. The last frame is
the static drawing (the stage ends in `settled`); the entrance tests pass unchanged.

**VoiceOver.** "Strain 9.6 of 21, today's recommended range 8 to 13" (key `Strain %@ of 21, today's recommended range %@ to %@`); ends shown to at most one decimal; no band or an empty one: the old sentence.

**Rejected.** A 60 / 40 mix (mauve, dE 52 for deutan); a gradient along the arc (no clear "this is where the range ended"); a dashed rail
(noise at medium); the rail on the outer track itself (it would hide the empty scale); keeping the rail at `.small`; 0.35 opacity (1.7:1).

**Review round 1 (animation, cut-out, sentence).**
- *One structure.* With a usable band the strain arc is always `OrbitStrainArc` + `OrbitStrainDot` (split = the band's upper end,
  `strainSplitDegrees`), whatever the strain is; only a nil or unusable band keeps the old `OrbitArc` + `OrbitDot` (nil is byte-identical to
  `main`: the 84-render hash check, repeated after this change, matches). Both are `Animatable` in the sweep, so the past layer grows and
  shrinks with the arc and a change that crosses the band's end moves continuously, with no swap and no crossfade. `OrbitWedge` is empty
  when `to <= from` (it used to wrap the long way: the whole arc turned `alert` mid-glide in the entrance).
- *The dot's colour* is decided from the animated sweep: it switches at the instant its head crosses the split (hard switch, not a blend), on
  the way up and the way down. In the entrance the dot position's degrees decide the same way.
- *Rail cut-out* uses `start: 0, sweep:` like the tracks (it follows the dot's animation); in the entrance the cut sits at the dot's flying position.
- *VoiceOver* says "above" when the arc has turned red (colour is not the only carrier): "Strain 16.5 of 21, above today's recommended range 8 to 13"
  (key `Strain %@ of 21, above today's recommended range %@ to %@`). Inside or below: "Strain 9.6 of 21, today's recommended range 8 to 13".
- *Rail opacity stays 0.5* (dark 2.33:1 on the background, light 2.09:1): it is the target's scale, the value is the arc, and the range is spoken; 0.6
  would be 2.85 dark. Not changed, because the tests pin 0.5 and 3:1 is out of reach without competing with the arc.
- *Shots* are rendered from the preview views themselves (`OrbitBandPreviewGrid`, `OrbitBandPreviewModes`); `pr4-entrance` adds t = 0.65 / 0.72 / 0.8 s.
