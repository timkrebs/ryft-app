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

**Better: rebase --onto instead of merging main.** Write down the parent's commit you branched from (e.g. into a
scratchpad file) when creating the stacked branch. After the parent is squash-merged, run
`git rebase --onto origin/main <that commit> <branch>`. Only the branch's own commits are replayed. Then check that
`git diff --stat origin/main..HEAD` shows only the branch's files.

On 2026-11-17 this worked cleanly for Nocturne PR 4 (three docs commits) after PR 3 (#114). Check
`git diff <parent head> <squash commit>` is empty first, which proves the squash holds everything.

See [[integration-branch]].
