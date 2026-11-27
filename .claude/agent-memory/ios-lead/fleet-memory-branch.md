---
name: fleet-memory-branch
description: Agent memory lives on the branch chore/fleet-memory (PR #125), not in the user's checkout — new and changed memory files get committed there from a scratch worktree
metadata:
  type: feedback
---

Every agent's memory (`.claude/agent-memory/**`) is kept on the branch `chore/fleet-memory` (PR #125, opened by the user
2026-11-19 as "chore: the fleet's memory"). New or changed memory files go there as commits, not as untracked or modified
files in the user's checkout.

**Why:** the user (2026-11-19) committed the fleet's whole memory into its own branch and cleaned his checkout, then said
"keep future memory files in chore/fleet-memory". Memory scattered as dirty files in his checkout blocked branch switches
and mixed with his own work.

**How to apply:**
- Keep a scratch worktree of `chore/fleet-memory` (from `git worktree add <scratchpad>/wt-mem chore/fleet-memory`); never
  check the branch out in the user's checkout.
- When an agent reports a new or changed memory file (they still write to the checkout path), copy it into the worktree, add
  its index line to that agent's `MEMORY.md`, scan it ([[public-repo-personal-data]]), and commit without trailers
  ([[no-attribution-lines]]). Batch several into one push: each push reruns #125's CI on the one runner.
- Write my own memories in that worktree too, then push.
- Tell the user which untracked copies remain in his checkout; don't delete them there.
