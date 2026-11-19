---
name: project-os-runtime-probes
description: How to make a platform-fact test answer per simulator runtime in one line (print shows in xcodebuild only when not parallel, nested-suite filter, OS-gated known issues); which runtimes the shared Mac has
metadata:
  type: project
---

Learned 2026-11-17 (P1b, T0.6 probe), Xcode 27.2:

- A `print(...)` inside a Swift Testing test shows up in the plain `xcodebuild test` log. So a probe can print one
  observation line on every OS (grep the log for its prefix), while only the measured OS versions get `#expect`s.
  Unmeasured versions use `Issue.record(Comment(rawValue: line))` only when the bad outcome shows.
- Not in a parallel run (the Unit plan's own setting, "Clone 1 of <sim>"): there, prints never reach the log or
  `xcresulttool get log --type console` (2026-11-17). Record the probe's lines as an issue and read them with
  `xcresulttool get test-results summary --path X` → `testFailures[].failureText`. CI's host stdout (e.g. a fatal
  error) is in the downloaded diagnostics: `diag/…/StandardOutputAndStandardError.txt`.
- A nested suite (`extension Outer { @Suite(.serialized) struct Inner {...} }`) is selected with
  `-only-testing:RyftTests/Outer/Inner`, and `test-without-building` reuses the last build for that runtime: a
  rerun takes seconds. The summary counts the parent as a second suite ("2 tests in 2 suites").
- For an OS-specific known issue: `withKnownIssue("reason") { #expect(...) } when: { if #unavailable(iOS 18) { return true }; return false }`.
  On other OSes the body's issues count as usual. Wrap only the expectations that are affected, so the rest of the
  test still checks things on the old OS.
- Runtimes on the shared Mac at that date: iOS 17.0 (create it with `iPhone-15-Pro`), 27.0, 27.1, 27.2. iOS 18–26 were
  not installed, so facts about those versions are unmeasured until the user adds the runtimes.
  **By 2026-11-18 `simctl list devices` also shows iOS 18.0 and 26.0** (B5a): check the list before saying a version
  can't be measured.
- **Prove "pre-existing" with a base worktree** (2026-11-18, P1b): `git worktree add --detach <scratch>/wt-base <base>`,
  copy the git-ignored `Config/*.xcconfig`, `build-for-testing` into its own DerivedData, run the one suite. Found
  `TrainStoreWipeTests/aRowStillHeld…` trapping on 18.0 ("Context is missing", SwiftData/BackingData.swift:296) on
  base too. Remove the worktree (`git worktree remove --force`) afterwards.

**Why:** the lead decides whether to ship from per-runtime observations (T0.1, T0.6). A one-line answer per runtime
avoids a full Unit-plan run each time.

**How to apply:** new platform-fact tests go in the T0 suite (`ReadModelContextFactsTests`) in this shape. Related:
[[project-swiftdata-two-containers-ios17]], [[project-model-actor-thread]], [[project-simulator-and-tools]].
