---
name: integration-branch
description: With several parallel PRs on shared files and squash merges, pre-resolve conflicts on an integration branch and let its CI prove the combined state
metadata:
  type: project
---

When parallel PRs share files, a classic group means several PRs edit the same Swift files, plus the string catalog. Do this
while the user hasn't merged yet:
1. Make a scratch worktree from `origin/main`.
2. Merge the PR branches into it in the planned merge order.
3. Resolve each conflict once. Strings: the per-key merger script (keep it in the session's `tools/`). Scripts: take the union.
4. Put the cross-PR wiring on top of that integration branch as its own draft PR. Its CI then proves the combined state.

The user squash-merges, so each later PR still needs `main` merged in after the earlier one lands. The resolutions are already
known, and the integration branch shows what they are.

**Why:** in the 2026-10-22 refresh-resilience work, #26, #28 and #27 conflicted pairwise (xcstrings, `scripts/screenshots.sh`,
`APIClient.exchange`). The integration branch (#31) caught the cross-PR seams, such as the epoch on T1's new code paths and one
shared path redaction. It came up green before any merge.

**How to apply:** any brief that produces two or more code PRs touching the same files. Also, a CI UI-smoke failure on only
one PR line isn't automatically "infra"; keep a tally of red runs, with and without the PR. See [[parallel-worktrees]].
