---
name: review-checks-mutant-evidence
description: RYFT review checks for "a mutant fails both tests" and "trap fixed on OS X" claims (wipe #107 finishing round, 2026-11-19) - read which expectation failed, gated probes that pass by skipping, test files edited after the run, delayed Tasks that outlive a release
metadata:
  type: feedback
---

From the #107 finishing-round review (wipe W2/W3 + #121 merge, 2026-11-19), by reading logs, not running:
- **"The mutant fails both tests" can mean one shared flag.** In `scratchpad/w107-mut18.log` both demo-exit tests failed
  only on `#expect(controller.isReleased)`; the hosted SessionView ran 1.6 s on deleted rows on 18.6 with `stop()` and
  never trapped. Grep the mutant log for `recorded an issue at <file>:<line>` and map each line to its assertion. A
  crash test that also asserts the flag hides that the crash never reproduced.
- **A gated probe passes by not probing.** `aRowStillHeldStaysUsableAndNothingComesBack` skips relationship reads on
  18/26 (`deletedRowsAnswerRelationships`), so "passes on 18.6" isn't evidence the app's fix works there. Diff the test
  body against main before accepting "trap fixed on X".
- **Run order vs mtimes.** `stat -t '%H:%M:%S'` on test files vs the log's end time; the mutant build log's
  `SwiftCompile` lines show which files it rebuilt.
- **Delayed Tasks hold rows too.** `TrainCoordinator.open` sets `live = controller` after a 450 ms sleep; release/account
  change/discard don't reach it, and the cover sits at the root (over Welcome). Grep `Task {` + `sleep` near any "let go in
  the same turn" rule.
- **Semantic merge check:** #121's seed relies on `AccountScope.current()` = `auth.lastUserID`; an ADR saying "AccountScope
  follows the published session" made me verify the implementation (still defaults). Widget writers that run after a
  Demo-data exit read the account store: list them for any "nothing writes the widget during a debt" ticket.

**Why:** the docs read as measured fixes; the logs said otherwise. **How to apply:** any PR whose docs cite mutants, OS
runs or "fixed on iOS X". See [[review-checks-merges-and-wiring]], [[review-checks-ownership-lists]], [[review-checks-undo-windows]].
