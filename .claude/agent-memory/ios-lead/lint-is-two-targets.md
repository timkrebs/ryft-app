---
name: lint-is-two-targets
description: CI's Lint job runs `make lint` AND `make style` (swiftformat + swiftlint); locally green `make lint` is not enough before a push
metadata:
  type: feedback
---

CI's "Lint" job runs two targets: `make lint` (strings, entitlements, scripts) and then `make style` (`swiftformat --lint`
plus `swiftlint`). Agents and I usually only report `make lint`. Before pushing, run both.

**Why:** On 2026-11-16, PR 2 (#113) went red in Lint after everyone reported "make lint green". SwiftLint's `empty_count`
flagged `x.count == 0` on an `Int` counter class and on a tuple field named `count` in new test files. These are false
positives as errors, but the job still fails. It cost one CI round of about 20 minutes.

**How to apply:**
- Put "`make lint` and `make style`" in every implementer and test brief.
- In a scratchpad worktree, `.build/tools` is missing. Symlink `swiftlint` and `swiftformat` from the main checkout's
  `.build/tools/` before running `make style`.
- Rename a counter (`total`, `pixels`) rather than adding a disable comment.

See [[parallel-worktrees]].
