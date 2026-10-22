---
name: project-classic-groups
description: Ryft/ and RyftTests/ were classic Xcode groups (new .swift files not compiled) as of 2026-10-21, contrary to the conventions skill saying synchronized folders
metadata:
  type: project
---

As of 2026-10-21 (refresh-resilience plan), `Ryft/` and `RyftTests/` are **classic groups**: a new `.swift`
file is not compiled without a pbxproj edit, which agents may not make. New types go into existing files next
to their users (e.g. ReadScheduler at the end of `Persistence/Repository.swift`, RequestBudget in
`Networking/APIStatus.swift`). The `ryft-app-conventions` skill says "synchronized folders", which is drift.

**Why:** converting the groups to folders is on the user's list but wasn't done; pbxproj edits are forbidden.

**How to apply:** before adding a file, check whether the target is a synchronized folder now
(`grep -c PBXFileSystemSynchronizedRootGroup Ryft.xcodeproj/project.pbxproj`); if not, extend an existing file
and report the drift.
