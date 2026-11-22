---
name: fleet-memory-merge
description: Agents write memory into the user's checkout while chore/fleet-memory holds the curated copy; the two diverge both ways, so merge three-way, never by mtime
metadata:
  type: feedback
---

Agents write their project memory into the user's checkout (`app/.claude/agent-memory/`), whatever worktree they work in. `chore/fleet-memory` (wt-mem) is where the user wants memory kept. The two copies diverge in both directions: the checkout misses older curated notes, wt-mem misses the newest ones, and single files gain separate additions on each side.

**Why:** on 2026-11-23 a copy-if-newer-mtime sync would have dropped about 30 lines of wt-mem-only notes from `project_simulator_and_tools.md`. It would also have overwritten the newer index lines.

**How to apply:**
- **Notes that exist only in the checkout:** copy them.
- **Notes changed on both sides:** use `git merge-file` with the merge-base version (`git merge-base HEAD origin/main`) as the base. The conflicts are usually additive, so keep both sides.
- **The `MEMORY.md` index:** match lines by link target. Take the checkout's line only for notes taken from the checkout.
- **Before committing:** grep for `/Users/<name>` and replace it with `<main checkout>`, because the repo is public ([[public-repo-personal-data]]).
- **Never delete anything in the checkout.** It is the user's tree.
