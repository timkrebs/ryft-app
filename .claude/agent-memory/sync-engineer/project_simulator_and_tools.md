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
  `<main checkout>/.build/tools/` (the `app/` folder the session started in); run them read-only from a worktree instead of
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
  avoids it entirely; restore each mutant with `git checkout -- <file>` only after committing. Hit again 2026-11-17
  with `args=$(sed …)` then `$args` after `test`: no error at all, **TEST SUCCEEDED with 0 tests**. Inline the
  `$(sed …)` (unquoted command substitution does split) and always check the total. On iOS 17.0 Swift Testing's
  `✔`/`Test run with` lines don't reach the log: read totals with
  `xcrun xcresulttool get test-results summary --path <-resultBundlePath>`.
- **Own simulator, and the idle tail** (2026-10-31, T2 round 2): `CI_SIM_NAME="<mine>" sh scripts/ci-simulator.sh`
  creates a device of your own (without it the script reuses the shared "RYFT CI local"); its first launch failed
  ("Simulator device failed to launch … No such process") until `simctl boot` + `bootstatus -b`. With
  `-only-testing` and failing tests, xcodebuild printed every result, then idled 10+ min (a retry pass, then nothing):
  the console's `✘`/`Test run with` lines are the answer; kill only your own PID. Never point two runs at one log file.
  Combining several mutants in one build and running each one's test (each must fail) saves the per-mutant build.
- **Again 2026-11-14 (domain move T1, "iPhone Duo" iOS 27.1, the only sim):**
  - "Failed to clone … remained in Creating state" twice.
  - `-parallel-testing-enabled NO` then showed the real cause: "device's data is no longer present".
  - `simctl list devices --json` still said `isAvailable: true`.
  - `simctl erase` + `bootstatus -b` fixed it; go there directly.
- **Reading a failed test run headless:** when xcodebuild exits non-zero, the tool truncates its output and the summary is lost.
  - Append `2>&1 | cat`. Exit 0 → the whole log is saved under `tool-results/`, and grep works on it (`"' passed on"`, `"' failed on"`, `"' skipped on"`, `Failing tests:`).
  - Needed approval in that run: `tee`, `xcrun xcresulttool`, `ps -ax`, `git check-ignore`. `ls` outside the repo is blocked.
- **Pre-existing on iPhone Duo (2026-11-14, same on the base via stash):**
  - `FocusedRowInViewTests`, `FocusedPolishHostedTests`, `RestPillHostedTests` (hosted geometry) and one `ImportTimeResolverTests/resolves` case fail, with 37 entries in `Failing tests:`.
  - Compare against that list before suspecting a change.

- **Long runs outside the tool's timeout** (2026-11-17, P1 round 2): a `run_in_background` Bash call still carries
  its `timeout` (10 min max), and a kill mid-mutant leaves a mutated source. Commit first, launch the mutant runner with
  `nohup … &` (pid to a file), give it a SIGTERM handler that raises (`sys.exit`) so its `finally` restores, and watch
  `results.txt` with a Monitor. Its xcodebuild child runs in a session of its own: check for your PID after a stop.
  2026-11-19 (O1): a `run_in_background` call given **no** `timeout` ran a 7-mutant runner for 25 min to the end, and a
  foreground call past ~180 s is moved to the background by itself. A wait-for-preconditions wrapper script (load < 200,
  no "RYFT CI" booted, < 3 xcodebuild) that then runs xcodebuild into a log, plus a Monitor on its `exit` line, worked.

- **Disk and swap exhausted** (2026-11-18 09:00–09:34, P1b): load over 800, 5.5 GB free, 44 GB swap. `simctl list`
  and `simctl boot` hung for 10+ min, another agent's `simctl shutdown all` shut my booted sim mid-run, and a test run
  ended "Failed to install or launch the test runner … Mach error -308 (ipc/mig) server died". All infrastructure: the
  lead said to rerun anything from that window before drawing conclusions. Check `uptime` and `df -h /Users` first; a
  `simctl erase` of my own sim + boot recovered it once CoreSimulator answered again.
  Same day 09:40–10:20 (B5a), load still 700–950 with disk back at 44 GB: unit-test runs passed, but `simctl boot`
  failed "launchd_sim … could not bind to session" and `bootstatus -b` sat 10+ min with the device listed Booted;
  UISmoke failed at launch ("request was denied by service delegate (SBMainWorkspace)", `kAXErrorAPIDisabled`) and a
  17.0 run with "Channel disconnected". Infrastructure again: reboot and rerun. Don't pipe `bootstatus` into `tail`
  (no progress shows until it ends).

- **Three silent filters** (2026-11-19, #107):
  - One Swift Testing test needs its parentheses: `-only-testing:'RyftTests/Suite/test()'`. Without them the run says
    "Test run with 0 tests … passed", and a mutant looks killed-proof. Check the count.
  - `RyftUITests` run only with `-testPlan UISmoke` (or `Full`). The scheme's default plan is Unit: "isn't a member of
    the specified test plan or scheme", exit 70.
  - Two simulator runtimes share one `build/Build/Products/Debug-iphonesimulator`. A build for the 18.6 destination
    replaces what the 27.2 run then tests, mutants included. Rebuild after restoring.
- **An app's defaults on a simulator** (2026-11-19, #107 planted entry): `simctl spawn <udid> defaults write
  dev.timkrebs.ryft …` writes the device's domain, which the app never reads. Use the container plist as the domain:
  `defaults write "$(simctl get_app_container <udid> <bundle> data)/Library/Preferences/<bundle>" key value` through
  `simctl spawn`, with the app not running. Debug's `demoMode` default is on, so a "Demo data off" run must write it.
- **`-only-testing:` takes type names, not file names** (2026-11-20, D247): briefs list files (`AppAttestAvailabilityTests`,
  `FeatureFlagsTests`, `ConsentGateTests`) whose structs are named otherwise (`AppAttestNotServedTests`, `FlagStoreTests`,
  `ConsentGateRuleTests` …); a non-matching name runs 0 tests silently. Grep `^struct|final class` in the files first and
  compare the "N tests in M suites" count. Erase + `bootstatus -b` + `-parallel-testing-enabled NO` got past the clone error.

- **Scratchpad worktree checks** (2026-11-22, N3 round 3):
  - `make lint` prints "Built-in exercises: no platform checkout, check skipped" and still exits 0, because there is no `../plattform` next to the worktree. Run `python3 scripts/builtin-exercises.py --check --platform <main checkout>/../plattform`.
  - UISmoke is XCTest: count `Test Case '-[…]' passed|failed|skipped` and `Executed N tests`, not `' passed on`.
  - A mutant that fails two `eventually` waits (30 s each) runs into the Unit plan's 60 s allowance. xcodebuild prints "Restarting after … test timeout", runs the rest of the suite, and still exits 65 (killed).
  - Swift Testing's console lines carry the `@Test("…")` display name, never the function name: grep a phrase of the title to prove a new test ran (a grep for the function name counts 0 on a pass).

- **More scratchpad worktree checks** (2026-11-22, invalid-workout hotfix):
  - `make style` runs `install-tools.sh`, which downloads into the worktree's git-ignored `.build/`. Copy the two pinned binaries from the user's checkout into `.build/tools/` first, and delete them at cleanup.
  - With `-only-testing`, the console has only `Test case 'Type/func()' failed on`; the expectation text is in the result bundle. Walk `xcrun xcresulttool get test-results tests --path <xcresult>` JSON for `nodeType == "Failure Message"` under each `Test Case`.
  - The destination line `platform=iOS Simulator,id=…` contains a space: never `split()` it in a script (xcodebuild then exits 64).
  - On "iPhone 17 Pro" iOS 27.2, made by `CI_SIM_NAME`, the full Unit plan passed (7 648 passed, 0 failed, 4 skipped). The hosted-geometry failures listed above for iPhone Duo didn't appear.

**How to apply:** any session that builds/tests in a worktree; related [[project-dev-machine-disk]].
