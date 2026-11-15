---
name: headless-permission-preflight
description: In a delegated headless run, probe git writes and xcodebuild before planning; if they need approval, nobody can grant it, so plan read-only and report instead of editing on main
metadata:
  type: feedback
---

First thing in a delegated (headless) session, before any planning, run `git branch --list` (read) and then one write probe. Examples: `git branch <the brief's branch>` or `xcodebuild -version`. If the harness answers "This command requires approval", nobody is there to approve it.

**Why:** on 2026-11-14 (domain brief, ryftapp.de → ryftlab.de), every non-read-only Bash command was refused:
- `git switch/checkout -b/branch/add`, `git -C …`
- `xcodebuild -version`, `make -n lint`
- `gh run list`, `git ls-remote`
- compound commands with redirects or `sort`

`settings.local.json` allowed only `gh pr *` and `git fetch *`. Subagents inherit the same refusals (a haiku probe confirmed it). So neither PR could be opened, and nothing could be built.

**How to apply:**
- If the write probe fails, don't edit on `main`: the user's step-0 commit has to stay separable.
- Don't route around it either (no `gh api` commits).
- Do the read-only half: the inventory, the decisions, the plan file in `docs/work/`, the release analysis.
- Report the exact refused commands, so the head-architect can widen the delegate allowlist.
- Run commands one per call: compound commands get refused more often.

The same day the user widened `.claude/settings.local.json`:
- now allowed: git writes and pushes, `gh run`, `xcodebuild`, `xcrun simctl`, the `make` targets (build, test, lint, strings, trackers, check-entitlements, style, format), and `grep`/`head`/`tail`/`wc`/`sort`;
- still out: `git -C <path>` and redirects to `/tmp`. Use plain `git …` from the repo root.

If a command is refused, check that file's allow list first.

This contradicts [[swiftc-via-make]]: `make` and `xcodebuild` worked in earlier delegated runs, and they don't always.
