---
name: flagged-agent-actions
description: How to check a subagent flagged for "Production Deploy" or similar; a local Release build script named release.sh tripped it once
metadata:
  type: feedback
---

When a task notification says a subagent "performed actions that may violate security policy" (e.g. "Production
Deploy"), check it before using the agent's output:
- `git ls-remote origin` for the branches involved. Nothing pushed means the remote heads are unchanged.
- `gh run list --limit 6`. A `workflow_dispatch` of Nightly TestFlight or Release would show there, with its time.
- The agent's commands. The task's output file is a pointer to the transcript under `tool-results/`; grep it for
  `"command":"` lines with push, gh, archive, upload or release.

**Why:** on 2026-11-20 the M6 merge agent (main #130 into PR 6) was flagged. The cause was `scratchpad/m6/release.sh`,
an unsigned `xcodebuild -configuration Release` for the simulator, which every integration run needs (see
[[release-build-check]]). Nothing was pushed. The Nightly dispatch that day came from the other lead's session, before
M6 started.

**How to apply:** in briefs, have agents name that script `build-release-config.sh` (not `release.sh`). Tell the user
in one line what the flag was and what you checked.
