---
name: project-classic-groups
description: Ryft/ and RyftTests/ were classic Xcode groups (new .swift files not compiled) as of 2026-10-22; only RyftUITests is a synchronized folder — contrary to the conventions skill
metadata:
  type: project
---

As of 2026-10-22, `Ryft/` and `RyftTests/` are **classic groups**: a new `.swift` file is not compiled
without a pbxproj edit, which agents may not make. New types go into existing files next to their users
(e.g. ReadScheduler at the end of `Persistence/Repository.swift`, RequestBudget in `Networking/APIStatus.swift`).
Only `RyftUITests` is a synchronized folder (a scratch UI test file there compiles — handy for screenshots
that need scrolling or taps; delete it, never commit it). The `ryft-app-conventions` skill says all three are
synchronized, which is drift.

**Why:** converting the groups to folders is on the user's list but wasn't done; pbxproj edits are forbidden.

**How to apply:** before adding a file, check (`grep -n PBXFileSystemSynchronizedRootGroup -A3
Ryft.xcodeproj/project.pbxproj`); if the target isn't listed, extend an existing file and report the drift.
