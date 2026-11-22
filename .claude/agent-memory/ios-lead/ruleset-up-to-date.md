---
name: ruleset-up-to-date
description: main's ruleset requires PR branches to be up to date (BEHIND blocks merge); after one merge, update the other open PRs while their iOS run is still queued
metadata:
  type: project
---

`main`'s ruleset requires branches to be up to date before merging. `mergeStateStatus` shows `BEHIND`, and the merge is blocked even with every check green. `gh pr update-branch <n>` merges main into the branch on GitHub and starts a new CI run.

**Why it matters:** the iOS workflow takes about 36 minutes, and this Mac is its only runner. On 2026-11-22, merging #136 left #135 `BEHIND`. #135's iOS run was still queued behind main's run, so updating it at once cost nothing: `concurrency: cancel-in-progress` replaced the queued run. Waiting for that run to finish and then updating would have cost a second full run.

**How to apply:**
- Right after merging a PR, check the other open PRs I'm about to merge (`gh pr view --json mergeStateStatus`).
- Update any that are `BEHIND` while their iOS run is still queued or early.
- Afterwards, fast-forward the local branch (`git merge --ff-only origin/<branch>`): GitHub's update commit isn't local.
- A docs-only PR's checks skip the build, so updating it is cheap at any time.
