---
name: review-checks-area-integration
description: RYFT checks for a whole-area integration review of tickets that each had their own review (Nocturne PR 6 C, 2026-11-19) - #Preview compiles without DEBUG (probed), merge-tree against sibling area branches, per-page failure classifiers and wait budgets drifting apart, a third host of a shared editor, short eventually timeouts, catalog pass gaps
metadata:
  type: feedback
---

From the PR 6 C integration review (C1-C5 + W merged on `feat/nocturne-pr6-settings`, read-only, no build, 2026-11-19):
- **`#Preview` bodies are type-checked without DEBUG.** Probe: `xcrun swiftc -typecheck -sdk $(xcrun --sdk iphonesimulator
  --show-sdk-path) -target arm64-apple-ios18.6-simulator a.swift` with a `#if DEBUG` type used in `#Preview` -> "cannot find
  in scope"; with `-DDEBUG` it passes. PR CI builds Debug only (ios.yml, security.yml); Release is only `_testflight.yml`
  archive. So a preview using a `#if DEBUG` mock (C2's `MockDevicesStates`) breaks the next TestFlight with green PR checks.
  Precedent: Import and Profile previews sit inside `#if DEBUG`. Scan: list types declared only inside `#if DEBUG` and grep
  their uses outside such blocks (scratchpad script, `python3 -I`).
- **Run `git merge-tree --write-tree` against the sibling area branches** (`origin/feat/nocturne-pr6-onboarding`, `-train`), not
  only base: C3 edited About you rows in A's file; A rewrote them. The conflict resolution can drop C's change silently when
  C has no test for it (here: "Saving..." rows).
- **A shared editor's "said where the user is" wiring: list every host.** `BodySettingsEditor.errorMissed` was read by Profile and
  the need sheet, not onboarding's About you (which owns a second editor instance), so a failure after closing the sheet there
  is silent. Grep `BodySettingsEditor(state:` for instances and `.bodySettingSheet` for hosts.
- **Tickets that fix a shared failure rule fix only their own pages.** C3 added `SettingsWriteFailure` (2xx-unreadable = no
  answer), a 25 s answer deadline + offline watch, and `userMayDiffer()`. Journal (own `FailureKind`-based classifier: 2xx ->
  "Nothing changed") and Notifications (default `APIClient` session: waitsForConnectivity 300 s, every switch disabled; no
  `userMayDiffer`) kept the old behaviour. Tabulate offline / no answer / 5xx / 429 / 4xx / 2xx-unreadable per page.
  `APIClient.$singleAttempt` (fail-fast session) already exists for foreground one-shot writes.
- **Chained saves that read `env.api` after awaiting the previous one** send to whatever side/account is current then; the
  binding is checked only on the answer. Capture source + binding in the step the change is made (C3's `answer(to:)` does).
- **`eventually(timeout: .seconds(5))`** in new tests vs the helper's documented 30 s (CI main-actor backlog reached 12 s).
  `HostedWindow.wait` is poll-count based and fine; `eventually` is wall-clock.
- Catalog: the strings pass may not have run yet; diff new literals vs `Localizable.xcstrings` keys both ways (72 missing,
  8 orphaned here) and the widget catalog too. Leftover old components (ProfileSection, SheetTitle, SettingRow) the design
  said go "as the last commit of" a ticket: grep each on the tip and on the sibling branches.
- Duplicates written per ticket: placement enums (C2 `DevicesPagePlacement`, C4 `SleepScheduleView.Placement`, C3 bool),
  six teal scans with different token lists, five shot harnesses. Report as one consolidation nit.

**Why:** each ticket's own review and suite were green; these only show with all tickets and the sibling branches together.
**How to apply:** any integration review of a multi-ticket area branch before its PR. See [[review-checks-merges-and-wiring]],
[[review-checks-setting-editors]], [[review-checks-settings-subpages]], [[review-checks-refusal-states]].
