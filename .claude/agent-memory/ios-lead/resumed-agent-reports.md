---
name: resumed-agent-reports
description: A subagent resumed with SendMessage can finish without its final report reaching me; verify its work from git and rerun tests/lint myself before building on it
metadata:
  type: feedback
---

When I resume a finished subagent with SendMessage, its follow-up report may never arrive. The notification says
"waiting on its own background work", ListAgents later shows it "completed", and no hand-back message comes.

**Why:** on 2026-11-16 (Nocturne PR 1) this happened twice with the ui-designer: once after the SurfaceRaised change,
once after the review-fix round. Both times the commits had landed and the tree was clean. I still couldn't tell
whether its tests had passed. Asking "please end with a final hand-back report" in the follow-up didn't help.

**How to apply:**
- After a resumed agent goes quiet, read `git log`/`git status` in its worktree and check `pgrep -fl xcodebuild` for its path.
- Then run `make lint` and the Unit plan myself, on a throwaway simulator ([[parallel-worktrees]]), before review or push.
- For a long follow-up, prefer a fresh agent with a self-contained brief over a resume when I need the report itself,
  e.g. numbers that go into a doc.
