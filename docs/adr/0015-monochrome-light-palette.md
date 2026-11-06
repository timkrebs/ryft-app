# 0015 — The light appearance becomes the monochrome "Alpine" palette

- Status: accepted (2026-11-05, design direction set by the user; the website follows in
  `timkrebs/ryft-platform` `web/`, see its `docs/DECISIONS.md`)
- Deciders: the user; app and web agents
- Applies to: `Ryft/Assets.xcassets/*.colorset` (universal/light entries only), every view that reads `Theme`

## Context

RYFT's web and app share one design language, and the website's tokens are generated from this
folder (`web/scripts/tokens.mjs` reads the colour sets, `Theme.swift`, `Typography.swift`; CI fails
on drift). The user has decided to move RYFT's visual identity to a monochrome, typographic style
(reference: a black-on-white, Inter-bold, hairline-grid landing-page style; internal spec
`docs/ALPINE_STYLE.md` in the RYFT project): **black and white only, differences carried by fill
level and hatching rather than hue**. The website ships light-only and first; the app follows.

Changing the dark appearance now would restyle the shipping TestFlight build before its views are
ready for monochrome (gauges, bands and sleep stages still rely on hue). The light appearance is
the web's source and the app's secondary look, so it can move first.

## Decision

1. **Universal (light) colour entries are monochrome.** Background and Surface `#FFFFFF`; text
   `#000000` at 100 / 62 / 55 % (primary / secondary / tertiary); Separator `#000000` (full, 1 pt);
   SurfaceRaised `#EBEBEB`; Accent `#000000` with OnAccent `#FFFFFF`; AccentSecondary `#6B6B6B`;
   Warning `#8A8A8A`; Alert `#000000`.
2. **Metric and stage colours in light are grey steps, darkest = most:** MetricStrain `#000000`,
   MetricSleep `#6B6B6B`; stages Deep `#000000`, Light `#7A7A7A`, REM `#B5B5B5`, Awake `#E0E0E0`.
3. **Dark entries are unchanged** until the app's monochrome pass (hatching for bands and zones,
   outlined destructive actions, the orbit gauge in ink). Brand constants (Graphite, Slate, Sage,
   Mist, Teal) stay as named colours; new UI should not reach for Teal.
4. **Follow-up for the app pass (not this change):** `Theme.band(forScore:)` and `Theme.zones` must
   encode level by fill or hatch, not by `warning`/`alert` hue; destructive buttons move to an
   outlined style; Inter replaces Satoshi (`Typography.swift`, `UIAppFonts`), display sizes gain
   the tight tracking (−0.07 em) of the web.

## Consequences

- Light mode of the app is monochrome from this change on. The orbit gauge ships with the palette: its
  centre ring reads by `BandStyle` (solid, dashed, outlined) and past the strain band by texture, because
  a colour could no longer tell them apart. The other scales follow in their own PR, each with a number or
  a word beside it until then. ADR 0017 extends this to the dark appearance.
- The website regenerates its tokens from these values and renders light-only.
- Contrast: secondary text (#616161 effective) 6.20:1 and tertiary (#737373) 4.76:1 on white; both
  above 4.5:1, so `web/tests/contrast.test.ts` keeps passing.
