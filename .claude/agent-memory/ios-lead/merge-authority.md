---
name: merge-authority
description: Merge authority is per PR list unless the user says otherwise; time-boxed grants cover own PRs only; review threads block merging
metadata:
  type: feedback
---

"Merge these" covers the PRs named, not a PR opened later. A broad "finish all PRs and open points, I approve your work"
does extend to the follow-ups of that work.

**Why:** the user gave merge instructions PR by PR throughout the focused session work, and only later gave the broad
approval. `CLAUDE.md` says to ask unless he said so for that session.

A time-boxed grant ("merge all PRs and fixes until 16:00 today", 2026-11-21) covers only this session's own PRs until that
time, and it ends at the deadline. Another lead's PR (#129 App Attest that day) is not covered. Neither is starting a
TestFlight build, which needs its own go-ahead.

**How to apply:** read the latest instruction, and name in the PR what you merged on it. Copilot threads block merging
under the ruleset (`required_review_thread_resolution`), so check them. Merge one PR at a time: the ruleset wants
branches up to date, so a merge makes the next PR re-run CI. Hold docs PRs until the queue is empty.
