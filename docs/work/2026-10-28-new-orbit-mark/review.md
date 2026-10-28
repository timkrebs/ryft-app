# Review — new orbit mark (round 1)

## code-reviewer
- **Blocking** — `RyftMark.swift` `arcs`: at 18 pt (MetricGauge ×3) the optical rule widened the gaps until the middle
  ring's short arc ran 234.9° → 229.1°; `addArc` then drew ~354° through both dots. 20 pt was down to 6°.
  → ui-designer reworks the small-size rule + a guard in `arcs`; test-engineer adds `RyftMarkGeometry` tests
  (every arc ≥ 15° at 18…1024 pt).
- Should: no unit test for the geometry → same test ticket.
- Verified: SVG numbers and arc flags hand-checked against the constants; wrap-around arc; optical rule pure, no
  division by zero; icons 1024², no alpha, token colours; `check-mark-svg` in `make lint` is safe on the macOS runners.

## Round 2 (re-verify, code-reviewer)
- Blocker fixed: dots and clear air now grow by √k, not k; `arcs` drops an arc with end ≤ start. 18 pt middle short
  arc = 26.2°. Header table recomputed and correct; nominal (≥ 39.6 pt) unchanged; `make check-mark-svg` passes.
- Nits applied by ios-lead: the collapse test asserts one arc per dot (a dropped arc now fails); the bounds test
  runs at 18, 24 and 100 pt. `RyftMarkGeometryTests` pass.

## ui-validator
- 1024: geometry matches the reference (3 rings, no centre dot, dots at +65°, −76°, 180°); nothing clipped. At 0.963
  the bottom dot clears the tile by ~15.7 px and the rounded mask by ~12–15 px (estimate): tight, not clipped.
- Opinion: 0.80 reads better on a home screen; 0.963 is the strict match. The brief asks for 0.963 in the PR → kept;
  the user decides from `build/icon-compare/`.
- 44 pt dark: clean, centred next to the wordmark; reads slightly lighter than the old mark (thinner stroke), not
  smaller (the old ring's edge was at 90 %, the new at 91 %). No change.
- Not captured: light mode in the running app (it forces dark at launch), the debug catalog (no tap tool), the 20 pt Today
  header (covered by the tour card). → Previews / the user.
