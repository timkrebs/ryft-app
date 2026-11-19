---
name: shared-mac-hygiene
description: Several leads and agents share this Mac and repo — fetch and compare trees before pushing, kill only recorded PIDs, never let a failed cd run git in the user's checkout, and expect idle worktrees to be removed
metadata:
  type: feedback
---

The Mac, the repo and the scratchpad are shared: my agents, a parallel ios-lead started by head-architect (from
`../.claude/bin/delegate.sh`; timeline in `../.claude/runs/index.log`), the platform lead, and the one CI runner.

**Why:** on 2026-11-19, four surprises in one afternoon:
- A parallel ios-lead run (brief `docs/briefs/2026-11-19-checkout-cleanup-109-app.md`) pushed the same #109 merge my agent
  had built. The trees were identical, so nothing collided; a different tree would have meant a merge of merges.
- An agent killed `tail` processes by a pattern on the scratchpad path and took three of its siblings' with it.
- A `cd <worktree> && …; git …` line in one of my own commands hit a removed worktree. The commands after the `;` ran in
  the user's checkout (read-only that time).
- Idle scratch worktrees (integration ones too) vanished mid-session; only ones with live agents or untracked files
  stayed. The branches were safe because every integration branch was pushed after each merge.

**How to apply:**
- Before any push to a shared branch: `git fetch` first, then compare `git rev-parse A^{tree} B^{tree}`. If the remote moved,
  look before merging. Check `../.claude/runs/index.log` for a running `app (ios-lead)` entry before big git moves.
- Kill only PIDs you recorded yourself, never `pkill -f` or a pattern on shared paths. Agent briefs say the same.
- In shell lines: `git -C <path>` for every git command, or chain everything after `cd` with `&&`. Never `cd X; git …`.
  In zsh, `G="git -C x"; $G …` doesn't word-split; spell the command out.
- Push an integration branch after every merge, and recreate a missing worktree from its branch
  (`git worktree add <path> <branch>`, then copy the Config xcconfigs and fonts) instead of assuming it is there.
- UI smoke at 834 s fits the 25-minute cap (#123) even at peak load; a timeout is a real signal now.
