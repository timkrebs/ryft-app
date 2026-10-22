---
name: project-simulator-and-tools
description: Shared iPhone 17e simulator can lose its data dir mid-session (clone/boot errors); pinned SwiftLint/SwiftFormat live in the user's checkout; Bash writes bypass the brand hook
metadata:
  type: project
---

Seen 2026-10-22 (tracker setup T1, several agents on one Mac):

- **Simulator vanished.** `Failed to clone device named 'iPhone 17e' … remained in Creating state`, then
  `Unable to boot device because it cannot be located on disk`: the device's folder under
  `~/Library/Developer/CoreSimulator/Devices/<udid>` was gone. `xcrun simctl erase <udid>` recreated it; then
  `simctl boot` + `bootstatus -b` before the first test run (a freshly erased device failed the first launch).
- **Style tools.** The pinned `swiftlint`/`swiftformat` (`scripts/install-tools.sh` versions) are already at
  `/Users/tim.krebs/Development/Projects/ryft/app/.build/tools/`; run them read-only from a worktree instead of
  downloading. The repo has many pre-existing warnings: compare per-file counts against `origin/main` copies.
- **Brand hook.** `.claude/hooks/pre-edit-guard.sh` only guards Edit/Write; text written through Bash (heredocs,
  python) isn't checked. Grep the diff with the hook's pattern before committing; tests build the brand at
  runtime (`["wh", "00", "p"].joined()`), and the regex text itself doesn't self-match.

- **AX screenshots.** `-UIPreferredContentSizeCategoryName …` works as an XCUITest launch argument but not with
  `simctl launch`; use `xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large` (reset to `large`).
  For a card below the fold, a scratch file in `RyftUITests/` that scrolls and writes `XCUIScreen.main.screenshot()`
  to a host path works; delete it before committing.

**How to apply:** any session that builds/tests in a worktree; related [[project-dev-machine-disk]].
