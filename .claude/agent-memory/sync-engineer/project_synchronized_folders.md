---
name: project-synchronized-folders
description: Since 2026-10-23 (#39) Ryft/, RyftTests/, RyftWidgets/ and RyftUITests/ are all synchronized folders; new files compile without a pbxproj edit, and non-Swift files in Ryft/ ship in the app
metadata:
  type: project
---

Since 2026-10-23 (#39) all four source folders are synchronized Xcode folders. A new `.swift` file in `Ryft/` or
`RyftTests/` compiles with no project-file edit. Before that, `Ryft/` and `RyftTests/` were classic groups, which is
why older code puts helper types at the end of unrelated files (e.g. ReadScheduler in `Persistence/Repository.swift`,
RequestBudget in `Networking/APIStatus.swift`). New types now get their own files.

Three traps:
- Never name a source folder `Build/` (any case). `.gitignore`'s unanchored `build/` plus `core.ignorecase=true` hid
  it from git (the file compiled and tested but was missing from the commit), and SwiftFormat 0.64 silently skips any
  folder named `Build`, so CI never lints it. I2 (2026-10-23, `feat/import-parser`) anchored the rule to `/build/` and
  renamed the import's folder to `Ryft/Train/Import/Builder/`. Check `git show --stat` lists every new file.
- Every non-Swift file in `Ryft/` is copied into the app bundle. Keep notes, drafts and scratch JSON out of it. Xcode
  excludes only `Info.plist` and `Resources/Fonts/.gitkeep`.
- A file both the app and the widget compile needs a second target membership, set in Xcode by the user. Until then
  the duplicated types stay, checked by `scripts/check-shared-types.py`.

A scratch UI-test file in `RyftUITests/` still compiles at once, which helps with screenshots that need taps. Delete it;
never commit it.

**Why:** the user converted the groups in Xcode on 2026-10-23 so the activities work could add many files.

**How to apply:** add new files freely. Check `git status` for stray non-Swift files under `Ryft/` before committing.
