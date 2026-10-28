---
name: external-testflight-hold
description: No External TestFlight promotion until the training import is live in the app (user decision 2026-10-27)
metadata:
  type: project
---

Don't promote any build to the External TestFlight group until the CSV training import is live in the app. That means
C2 has landed, `train.import` is on, and the pre-flag list in STATUS is done. Builds keep going to Internal
automatically.

**Why:** on 2026-10-27 the user said "let's wait until I have the import training in the actual app". The External
testers' next build should carry the import.

**How to apply:** don't propose `weekly.yml` / External promotion before then. When the import goes live, offer it
once, with notes covering the import.
