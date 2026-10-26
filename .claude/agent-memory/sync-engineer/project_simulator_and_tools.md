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
  Again on 2026-10-23 with the assigned iPhone Air: its folder was missing at session start. Check
  `ls ~/Library/Developer/CoreSimulator/Devices/<udid>` before the first build; `bootstatus` then printing
  "Data Migration Failed" after an erase is harmless (the device boots and tests run).
- **Swift style lint on the pinned tools.** SwiftLint lints the whole repo anyway (the config's `included` wins over
  path arguments, seen 2026-10-23), so run `swiftlint lint --quiet` from the worktree root and `grep` the output for
  your paths. Don't wrap commands in `bash -c '…'`: Claude Code's safety check blocked one on 2026-10-23 because it
  can't inspect a nested script. SwiftFormat does honour folder arguments (`swiftformat --lint Ryft/X RyftTests/X`).
  `SwiftLint` flags `String(decoding:as:)` (`optional_data_string_conversion`; in app code where lossy decoding is the
  point, a `// swiftlint:disable:next` with the reason) and explicit memberwise inits (`unneeded_synthesized_initializer`).
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

- **Case-insensitive simulator file system** (2026-10-23): the test host's tmp is on the Mac's APFS, so `RYFT-x.json` and
  `ryft-x.json` are one file. File-name tests must not rely on case alone.

- **The Mac slept mid-run** (2026-10-24 → 26): a `test-without-building` sat for 44 h with no output and the simulator
  was Shutdown afterwards. If a run looks stuck, check `ps -o pid,etime,command -ax | grep '[x]codebuild'` for your own
  PID, kill only that, `simctl boot` + `bootstatus -b`, and rerun. macOS has no `timeout` command; run long tests with
  `run_in_background` and wait with an `until grep …` loop.
- **"Killed: 9" with the simulator Shutdown** (2026-10-26, "RYFT import"): something outside the session ended the run
  minutes in. Not the code: boot, `bootstatus -b`, rerun.
- **zsh doesn't word-split** (2026-10-26, I5): building `O="-only-testing:A -only-testing:B"` and passing `$O` gives
  xcodebuild one argument ("Unknown build action"). Pass `${=O}`. A mutant script in Python (`subprocess` with a list)
  avoids it entirely; restore each mutant with `git checkout -- <file>` only after committing.

**How to apply:** any session that builds/tests in a worktree; related [[project-dev-machine-disk]].
