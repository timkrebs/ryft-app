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
- Give each agent its own simulator. Since 2026-11-16 the named iOS 27.0 devices (e.g. iPhone 18 Pro `D23B7086`,
  iPhone 17 `A79A36CA`) don't boot ("runtime not available"). So create a private one per agent with
  `xcrun simctl create <name> com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-2`,
  pass its UDID in the brief, and delete it afterwards. Tests there need `-parallel-testing-enabled NO`, because
  parallel clones fail.
- `git worktree add -b … origin/main` sets the new branch's upstream to `origin/main`. Push with
  `git push -u origin <branch>`. A sibling branch merged into another one then reports "not fully merged": check
  `git merge-base --is-ancestor` before `git branch -D`.
- Put this in every brief: **never `pkill -f xcodebuild/xctest/Simulator`; kill only your own PIDs.** On 2026-10-22 a
  profiler's broad pkill shut down a shared simulator mid-run.
- Before starting an agent, `git merge --ff-only origin/main` the empty branches. Main moves often, because the user
  merges PRs during a session.
- When an agent stops early (usage limit), check its worktree before resuming. Work may be uncommitted, or an unpushed
  merge. Resume it with SendMessage, telling it to commit and push first.

**Why:** in the 2026-10-21 and 2026-10-22 sessions, three to six implementers and reviewers ran at once. This kept
builds, DerivedData (keyed by path) and simulators apart, and left the user's checkout untouched.

**How to apply:** any brief with two or more independent tickets. Since 2026-10-23 all source folders are synchronized
(#39), so parallel tickets can own separate new files. Shared files still need regions assigned in the plan: the string
catalog, `Models.swift`, `AppEnvironment`. See [[integration-branch]].
