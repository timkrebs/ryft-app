---
name: offline-first-requirement
description: The user's product rule (2026-11-19) — RYFT shows everything offline, and data recorded while offline must be kept and uploaded once the API is reachable
metadata:
  type: project
---

The user's rule (2026-11-19, in German): when there's no internet connection, the user in the app should still see
everything. Data that syncs between Apple Health and RYFT while offline must be kept in RYFT, and all of it must upload as
soon as the API is reachable again.

**Why:** he wants an app that holds up offline: no lost data, nothing blank and no false freshness. He said this right
after I made Profile's status row truthful ("not updated yet" or the real age instead of "updated now").

**How to apply:**
- Every feature that writes or shows data has an offline story: an outbox for app writes, the cached read model with an
  honest "As of" note, and an upload on reconnect.
- Review briefs ask about it. A screen that goes blank or claims to be fresh while offline is a finding.
- The audit, its tickets O0–O14 and the sequencing are in `docs/work/2026-11-19-offline-first/plan.md` (PR #124). Batched
  questions worked again: see [[big-programs-parallel]].

**Decided 2026-11-19 ("ok" to every default):** Q1 local unscored HealthKit values offline, limited and labelled;
Q2 online before scoring only the night card and unsent workouts; Q3 offline consent withdrawal takes effect at once;
Q4 park unsent work for 30 days across an expiry; Q5 offline log-out allowed with a list and a warning; Q6 last write
wins; Q7 background catch-up when iOS allows, no push; Q8 sync-only tickets run alongside Nocturne, screen tickets after
PR 5/6. The plan is in PR #124 (`docs/work/2026-11-19-offline-first/plan.md`).
