---
name: parallel-worktrees
description: How to run several RYFT tickets in parallel without them colliding — worktree base, ignored files to copy, one simulator each, no broad pkill
metadata:
  type: project
---

For parallel tickets I create the worktrees myself with `git worktree add -b <branch> <scratchpad>/wt-<name> origin/main`.
I don't use `isolation: worktree`, and I don't use local `main`, because local `main` lags `origin/main` by several PRs
on a busy day. Afterwards:
- Copy in the git-ignored files the build needs: `Config/Debug.xcconfig`, `Config/Release.xcconfig` and
  `Ryft/Resources/Fonts/*.otf`.
- Give each agent its own simulator in the brief (e.g. iPhone 18 Pro / 17 / Air / 18 Pro Max / 17e), or let it
  `simctl create` a private one and delete it afterwards. The Makefile's `iPhone 17 Pro` isn't installed on this Mac.
- Put this in every brief: **never `pkill -f xcodebuild/xctest/Simulator`; kill only your own PIDs.** On 2026-10-22 a
  profiler's broad pkill shut down a shared simulator mid-run.
- Before starting an agent, `git merge --ff-only origin/main` the empty branches. Main moves often, because the user
  merges PRs during a session.
- When an agent stops early (usage limit), check its worktree before resuming. Work may be uncommitted, or an unpushed
  merge. Resume it with SendMessage, telling it to commit and push first.

**Why:** in the 2026-10-21 and 2026-10-22 sessions, three to six implementers and reviewers ran at once. This kept
builds, DerivedData (keyed by path) and simulators apart, and left the user's checkout untouched.

**How to apply:** any brief with two or more independent tickets. Because `Ryft/` is a classic group, parallel tickets
still share files, so the plan must assign regions within a file. See [[integration-branch]].
