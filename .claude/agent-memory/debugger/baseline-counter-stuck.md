---
name: baseline-counter-stuck
description: Why "Baselines 0 / 7" never moves (platform min(HRV,RHR) nights); where to look first
metadata:
  type: project
---

`baseline_days = min(HRV nights, RHR nights)` over the 30 scored days before (plattform scoring/compute.go:355,
algorithms.go:170). No `hrv_sdnn` samples from any source => 0 forever while recovery/readiness still compute. Platform rule, not an app bug.
Seen 2026-10-21/22 on the same TestFlight device (Garmin tester). Evidence: `scripts/user.sh <id>` -> "with HRV N" (days_with_hrv_14d);
`scripts/beta_report.sh` for source kinds (user.sh doesn't print them; kind `hr` also covers resting HR). No operator route for GET /v1/days: use read-only SQL on daily_scores.
**How to apply:** for any "counter stuck" report check hrv_ms/rhr in daily_scores before touching the app; "Scoring your latest data" is the local awaitingScores phase (needs a non-empty upload, max 300 s), not /v1/me/sync directly.
