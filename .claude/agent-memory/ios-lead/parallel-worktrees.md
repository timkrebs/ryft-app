---
name: parallel-worktrees
description: How to run several RYFT tickets in parallel without them colliding — worktree base, ignored files to copy, one simulator per worktree
metadata:
  type: project
---

For parallel tickets I create the worktrees myself with `git worktree add -b <branch> <scratchpad>/wt-<name> origin/main`.
I don't use `isolation: worktree`, and I don't use local `main`, because local `main` lags `origin/main` by several PRs
on a busy day. Afterwards:
- Copy in the git-ignored files the build needs: `Config/Debug.xcconfig`, `Config/Release.xcconfig` and
  `Ryft/Resources/Fonts/*.otf`.
- Give each worktree its own simulator in the agent brief (e.g. iPhone 18 Pro / 17 / Air / 18 Pro Max / 17e). The
  Makefile's `iPhone 17 Pro` isn't installed on this Mac.
- Before starting an agent, `git merge --ff-only origin/main` the empty branches. Main moves often, because the user
  merges PRs during a session.

**Why:** in the 2026-10-21 refresh-resilience session, three implementers and the debugger ran at once. This kept
builds, DerivedData (keyed by path) and simulators apart, and left the user's checkout (a feature branch with
unpushed commits) untouched.

**How to apply:** any brief with ≥ 2 independent tickets. Because `Ryft/` is a classic group, parallel tickets still
share files, so the plan must assign regions within a file (see [[refresh-resilience-2026-10-21]] if it exists).
