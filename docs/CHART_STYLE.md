# Chart style

Every chart reads like an instrument, not an illustration. The rules live in code in
`Ryft/Design/ChartStyle.swift`; metric facts (colour, unit, polarity, scale, bands) live
in `Ryft/Design/MetricSpec.swift`. Charts take a `MetricSpec`; they don't pick colours or
formats themselves.

## Marks

- Lines are 1.5 pt with `.interpolationMethod(.linear)`, and break at missing days.
  Never catmullRom; monotone at most.
- Point markers are 6 pt, only at today or the selected point (filled) and at the
  window's min and max (hollow).
- No area fill (6 % at most), no glow, no shadow, no gradient.
- Bars use corner radius ≤ 2 and stage colours for sleep.

## Axes

- Axes are always visible. The y axis is trailing, with 3–5 nice ticks: 1 / 2 / 2.5 /
  5 × 10ⁿ, or whole hours for time.
- Non-negative data never gets a negative floor.
- The top y tick carries the unit ("80 ms").
- Gridlines are `Theme.separator` at 0.5 pt.
- x ticks by window:

  | Window | Ticks | Labels |
  | --- | --- | --- |
  | 7 d | every day | weekday initials |
  | 30 d | weekly, counted back from the last day | |
  | 90 d | first of each month | month names |

- Labels are `caption2` with monospaced digits (`ChartStyle.axisFont`).
- Night axes use the 24-hour clock in every locale ("20 00 04 08 12").

## Reference layers

- **Baseline**: a dashed `RuleMark` in Mist (dark) or Graphite (light) at 40 %. Its
  label sits at the leading end ("baseline 52 ms"), on the card surface.
- **Range band**: a `RectangleMark` at 10 % of the metric colour. It shows the 30-day
  min–max until the API serves σ (`API_REQUESTS.md`).
- **Thresholds**: scores keep a fixed scale (0–100, 0–21). Their band thresholds (33 / 67
  and 10 / 14 / 18) are thin dashed rules, and the y-axis ticks label them in the margin.
- Today's value is annotated with its number.

## Readouts

- Every chart has a `ChartHeader` row:
  - the metric name in small caps
  - the current value with its unit
  - a `DeltaLabel` against the 7-day mean
  - the window ("30 d")
- `DeltaLabel` shows "▲ +4 ms · +8 %". Its colour comes from direction × polarity: teal
  when good, Alert when bad, secondary ink for neutral metrics. Under 2 % it reads "—".
- Scores and percentages change in points, without a percentage.

## Scrub

Finger-down shows a vertical rule and a `ScrubReadout`: value, date and the delta to the
baseline (or to the window's mean). There is a selection haptic on each day change.

## Motion

- Charts fade in with a 250 ms ease-out (`chartAppear()`); gauges settle in 250 ms.
- No count-ups, no springs. Reduce Motion makes both instant.

## Colour

| Metric | Colour |
| --- | --- |
| Readiness, recovery, HRV, e1RM | Accent (teal) |
| Strain | `MetricStrain` (blue) |
| Sleep | `MetricSleep` (indigo) |
| Resting HR, workout HR | Alert (#E36B5B in dark) |
| Respiratory rate, steps | Sage (AccentSecondary) |
| SpO₂ | secondary ink (Mist in dark) |
| Active energy | Warning |

- Bands use the semantic trio, always with a word ("High", "Moderate strain"). Colour
  is never the only carrier of meaning.
- All metric colours reach 4.5:1 on the card surfaces in both appearances.

## Components

| Component | Use |
| --- | --- |
| `TrendChart` | daily series |
| `OrbitGauge` | Today's readiness and the widget: the RYFT mark as a gauge, 72 / 112 / 160 (see below) |
| `MetricGauge` | ring as instrument, 72 / 112 / 160 (the Strain tab) |
| `RangeBar` | value within a personal range |
| `DeltaLabel` | change against a reference |
| `ZoneBar` | heart-rate-zone minutes |
| `MiniHypnogram` | last night, 20:00–12:00 |
| `Hypnogram` | Sleep tab |

Every component has dark and light `#Preview`s.

### OrbitGauge

The app icon's orbits carry the four scores; arc length is the score, the dot at its head is today. The centre ring is
Readiness (its band colour, the number inside); the inner orbit carries Recovery (teal, counter-clockwise from the top)
and Sleep performance (`metricSleep`, clockwise), each half starting 12.5° from the vertical so the two dots never meet;
the outer orbit carries Strain (`metricStrain`, clockwise, 21 = a whole turn). Tracks are `surfaceRaised` with the air
around each dot cut out, caps round. A missing score is a hollow dot at its start, never an arc and never a zero; zero
is a filled dot with no arc. Nothing rotates on its own; a new value moves the arcs on `Theme.Motion.slow`, and under
Reduce Motion it cross-fades. The number is omitted below a 56 pt dial. One VoiceOver element: "Overall readiness",
then "71, High. Recovery 71 percent, Sleep 88 percent, Strain 9.6 of 21", a missing score "Sleep, not scored".

The drawing is shared with the widget (`Shared/OrbitGaugeDrawing.swift`, colours by asset name in
`OrbitGaugePalette`, ADR 0010); `Ryft/Design/OrbitGauge.swift` adds the number, caption, VoiceOver and motion.
Geometry, contrast and what was rejected: `docs/work/2026-10-29-orbit-gauge/design.md`.
