# New orbit mark and app icon (2026-10-28)

Brief: `../docs/briefs/` (head-architect, 2026-10-28). Reference: `../docs/briefs/assets/2026-10-28-new-app-icon-reference.jpg`.
Branch `design/new-orbit-mark`. One PR, no merge, no TestFlight.

## Measured geometry (100-box = the mark's outer extent, centre 50/50)
- stroke 3.16, round caps on every arc
- outer ring r 44.0, one dot at +65° (0° = 3 o'clock, clockwise, y down)
- middle ring r 25.6, two dots at −76° and 180°
- inner ring r 7.6, closed, no centre dot
- dot r 6.0, centred on its ring; clear air from a cap tip to the dot edge ≈ 1.0 × stroke

## Tickets
| # | Ticket | Owner | Depends on |
|---|--------|-------|------------|
| T1 | `RyftMark.swift`: new geometry as named constants in the 100-box, the small-size (optical) rule, source-compatible API; `design/ryft-mark.svg` generated from the same numbers | ui-designer | — |
| T2 | `scripts/render-icon.swift`: scale constant (reference 0.963 default, Apple-grid 0.80 compare to `build/icon-compare/`); `make icon`; `design/ryft-app-icon-{light,dark}.svg`; previews of RyftHeader + Today; CHANGELOG, STATUS | ios-developer | T1 |
| R  | ui-validator (24 / 44 / 1024 pt vs reference, dark + light) and code-reviewer, in parallel, read-only | — | T2 |

## Acceptance criteria
1. `RyftMarkShape().path(in: 100×100)` matches the measured numbers (radii, angles, dot r, stroke) at sizes where the optical rule doesn't kick in.
2. At 24 pt the stroke and dots are no thinner than the documented minimum; the rule is written in the file.
3. All callers compile unchanged or are updated; zero new warnings; `make lint` passes.
4. `make icon` writes three 1024² PNGs without alpha; Light = Graphite on Mist, Dark = Mist on Graphite, Tinted = white on black.
5. The outer ring spans 0.963 of the tile in the committed icons; an 0.80 render exists in `build/icon-compare/`.
6. `design/ryft-mark.svg` (viewBox 0 0 100 100, `currentColor`) and the two 1024 icon SVGs agree with the Swift geometry.
7. The RyftWidgets AppIcon set has no images and the widget target doesn't set `ASSETCATALOG_COMPILER_APPICON_NAME`, so it is left alone.

## Risks
- Hairline strokes at 24 pt → optical size rule (T1).
- 0.963 scale is close to the squircle mask at the corners; rings are circular, so only the outer ring's 4 % margin matters. The compare render lets the user judge.
- Brand board shows the old mark: the brief supersedes it; the PR says so.
