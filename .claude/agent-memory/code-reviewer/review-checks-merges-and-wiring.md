---
name: review-checks-merges-and-wiring
description: RYFT review checks for lead merge resolutions (proving nothing was lost) and for PRs that wire up UI that shipped hidden ("until X is wired")
metadata:
  type: feedback
---

Merge resolutions (integration review, 2026-10-22): don't eyeball `git show --cc` alone. For each branch tip, check
every line it added vs `origin/main` (`git diff -U0`) still exists in the merge, and every line it removed is gone
(count main/tip/merge occurrences; braces are noise). For `Localizable.xcstrings`, compare the parsed `strings` dicts
per key against main and each tip in a scratchpad Python script (`python3 -I`). Expected "missing" lines are only the
conflict lines that combine both sides (e.g. `…, epoch: epoch)` plus `durationMs:`).

Wiring hidden UI (T5 Send to RYFT): code written while a button was hidden ("Send to RYFT hidden until #26 wires it")
was never seen by a user or validator. When it's switched on, re-read the arguments it passes: T1 passed
`ResourceError.statusText` ("timedOut", "signedOut") where `ReportContext.status` documents "No response", so a raw
identifier reached a localized chip.

Parallel tickets (T3 sync-check review, 2026-10-22): `git merge-tree --write-tree --name-only <mine> <theirs>` lists
real conflicts without touching a worktree; then read the region table (design §9.3) to say whose edit is out of
region. Also read the sibling tickets' `review.md` entries: copy already decided there (T1's ui-validator renamed
"Open Garmin Connect" → "Garmin Connect in the App Store") is easily re-introduced by a parallel ticket.

**Why:** both were the non-obvious parts of the T5/integration review; the merges themselves were clean.
**How to apply:** run the survival check on any multi-branch integration; on "wire up" PRs, trace each value from the
previously hidden call site to where it's rendered. See [[review-checks-shared-transport]].
