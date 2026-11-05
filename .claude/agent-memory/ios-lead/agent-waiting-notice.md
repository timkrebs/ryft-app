---
name: agent-waiting-notice
description: An agent's "waiting on its own background work" notice proves nothing; check for real processes and new output, and own the wait
metadata:
  type: feedback
---

An agent that says it is waiting may be waiting on nothing. Check within minutes, not when the user asks.

**Why:** on 2026-11-05 test-engineer's work finished at 09:24, but seven of its own `until [ -f marker ]` loops watched a
marker that a later run no longer wrote. It looked busy until the user asked at 11:42. Two hours of the day went there.

**How to apply:** on that notice, check `ps` for xcodebuild, the newest files in its output folder and `git log` in its
worktree. Loops of its own that wait on a marker can be released by creating the marker, without killing anything. Tell
agents not to poll marker files and to leave nothing running at hand-back.
