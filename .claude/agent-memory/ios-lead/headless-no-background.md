---
name: headless-no-background
description: In a headless/delegated session, ending the turn ends the session and kills background sub-agents; run builders with run_in_background false and never end the turn to "wait"
metadata:
  type: feedback
---

In a delegated (headless) run, ending my turn ends the session. Any background sub-agent dies with it, and nothing re-invokes me
when it would have finished.

**Why:** on 2026-11-15 (ingest URL on #109) I launched sync-engineer in the background and ended the turn with "waiting for
sync-engineer". The session ended. The builder's work was left half-done and uncommitted, and the merge commit was never
pushed. The head-architect had to send a follow-up brief.

**How to apply:**
- Headless: pass `run_in_background: false` to every Agent call whose result I need. Run parallel reviewers as several
  foreground calls in one message.
- Never end a turn while a build, test, agent or CI watch is still running. `gh pr checks --watch` stays in the foreground.
- If a session dies anyway, the next one starts from `git status` plus the diff. Don't assume the agent's work landed.

See [[headless-permission-preflight]].
