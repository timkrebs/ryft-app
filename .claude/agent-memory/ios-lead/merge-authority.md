---
name: merge-authority
description: Merge authority is per PR list unless the user says otherwise; review threads block merging and a new PR needs its own go-ahead
metadata:
  type: feedback
---

"Merge these" covers the PRs named, not a PR opened later. A broad "finish all PRs and open points, I approve your work"
does extend to the follow-ups of that work.

**Why:** the user gave merge instructions PR by PR throughout the focused session work, and only later gave the broad
approval. `CLAUDE.md` says to ask unless he said so for that session.

**How to apply:** read the latest instruction, and name in the PR what you merged on it. Copilot threads block merging
under the ruleset (`required_review_thread_resolution`), so check them. Merge one PR at a time: the ruleset wants
branches up to date, so a merge makes the next PR re-run CI. Hold docs PRs until the queue is empty.
