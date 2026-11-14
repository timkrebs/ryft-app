---
name: orbit-render-flake
description: OrbitGaugeBandRenderTests pixel/byte tests flake in time windows of a process (host rasteriser state), not branch-related; in-process -test-iterations reproduces it
metadata:
  type: project
---
2026-11-04: `theEntrancesLastFrameEqualsTheStaticRenderWithABand` failed on branches that touch no Orbit file. Reproduced on clean main (0b6069b): only with `-test-iterations 60-120` (in-process repeats) on 4-5 sims at once, flags CODE_SIGNING_ALLOWED=NO RYFT_STRICT_WARNINGS=YES; ~10% of reps, clustered in tens-of-seconds windows inside 1 of ~3 processes. Fresh-process loops (36) and 227 other reps: 0.
Cause (observed, trigger not found): in a window the STATIC drawing renders with 7 edge pixels 1 level off (strain 4.0 dark, same 7 every time); the entrance frame is unchanged. In the same windows other tests (theArcIsAlertPast..., theStrainArcAnimates...) saw a blank arc (distance ~1.1 from the colour) in their first dark render: ImageRenderer output is unreliable under host GPU/load. The "2 s" duration is queue wait behind a stalled main actor, not the test body.
Fix: tolerance (2 levels, 64 px) in that test (commit on test/orbit-render-flake). Blank-arc flake of the colour-sample tests is NOT fixed.
**How to apply:** an Orbit render test failing only in dark/first render, at ~2 s, is this; xcresulttool `get test-results test-details` shows the failing expectation text. Don't blame the branch.
