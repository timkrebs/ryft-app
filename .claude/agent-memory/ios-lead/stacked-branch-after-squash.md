---
name: stacked-branch-after-squash
description: Merging main into a branch stacked on a squash-merged PR can silently resurrect replaced code; verify the merged tree against the branch head
metadata:
  type: feedback
---

When a branch was stacked on another PR's branch, and that PR was squash-merged, merging `main` into it uses an old
merge base. Git then reports "both added" conflicts in the parent PR's files, and it **auto-merges other files without
a conflict**. Those clean hunks can bring back parent code that the stacked branch had replaced.

On 2026-10-26, P2 (#57) was stacked on A2 (#54). The merge re-added A2's `syncGate`/`config` lines to
`HealthPermissionView.swift`, and CI failed to compile.

**How to apply:** after merging main into such a branch:
1. Check that main's copy of each conflicted file equals the parent's last commit. Then take the branch's side.
2. Run `git diff --stat <branch head before merge> HEAD`. It must show only the files main changed since the parent
   PR (here, just `PrivacyInfo.xcprivacy`). Restore anything else from the branch head.
3. Run a strict build before pushing.

See [[integration-branch]].

Also, from the focused session PRs (2026-11-04):
- If the parent was squashed, merge the parent's old head first, then record `main` with `-s ours` when the two trees are
  byte-identical. Prove it: `git diff --name-status` and sorted changed lines of `main..HEAD` equal the branch's own delta.
- Git can't see a signature change meeting another PR's new caller: after a merge, grep closures and compile. `wipeLocalData`
  gained a Bool return in one PR and a test written in another stopped building.
