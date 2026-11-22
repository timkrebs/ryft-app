---
name: review-checks-flow-vs-gate-splits
description: RYFT review checks when a local fact moves a flow but must not open a gate (consent agreement vs upload gate, ADR 0025, 2026-11-22) - stale cached user + cleared refusal opens early, every consent-state reader not just Today, untested "asked before T settles nothing", bounded re-checks swapped for bare scheduler reads; round 3: no-settle flags on joined flights, cause enums missing a closing fact, try? checks losing request IDs
metadata:
  type: feedback
---

From the consent "Agree and continue" review (`fix/consent-agree-lag`, read-only, no build, 2026-11-22):
- **"The gate opens only on a fresh read" claims.** Find the case where the *cached* state already satisfies the gate
  and the local write only removes the blocker. Here a cached user with consent V plus a refusal (whose re-check failed)
  showed the step; the `204` cleared the refusal, R2 silenced the old status, and the gate opened before any `/v1/me`
  asked after the `204`. `gateChanged` then reran the held sync. Lawful (the `204` is the platform's word) but contrary
  to the ADR's wording. Ask what in `gate()` actually requires the fresh read.
- **A flag that relaxes the flow but not the gate leaves other readers stale.** The design fixed Today and Devices & sync
  (`pendingGate`). Profile → Privacy still read the stored user: "Not given", and a dead "Review and agree" (`show(.consent)`
  shows nothing because `missing` lacks consent). Withdraw was not offered either. Sync details' `workoutsHeldText` and
  the import pause had the same issue. Grep every reader of `user.consent` and `.gate(.consentRequired)` text.
- **"An answer asked before T settles nothing" branches.** List which test holds a flight that started before T and
  releases it after T. Here none did, so a mutant `askedAt >= at` → `true` would survive.
- **Swapping a bounded re-check for a bare scheduler read drops the deadline.** `check()` raced `checkTimeout` (10 s).
  `readUserBack` has no deadline: 3 attempts × 20–25 s on the fail-fast session, plus backoff. A "hold lasts seconds"
  claim (#134) then grew to about 85–100 s on exactly the network that produced the no-answer.

**Why:** the PR's T1–T11 and mutants all held. These sat outside the design's own list of affected readers and rules.
**How to apply:** any PR where a phone-side word moves UI ahead of the platform (agreements, optimistic flags). See
[[review-checks-local-overrides]], [[review-checks-control-holds]], [[review-checks-shared-write-waits]].

Added after the round-3 verify (d1240d3..11ea2fc, read-only, 2026-11-22). Every decided item held; what the fixes left:
- **A "this read settles nothing" flag on a joined read pipeline.** `ReadScheduler`: the first store given wins, so the flag
  holds only when this caller's store is the flight's. And an answer that can only close (no consent) is always safe to let
  settle: holding it back left Privacy saying "RYFT has recorded your consent" against RYFT's latest word until the next check.
- **A cause enum fed by one fact** (`PauseCause.of(_, agreementUnsettled:)`) ignored a concurrent closing fact its own doc
  lists (a withdrawal on its way). Check every case the doc names against the inputs the function actually takes.
- **A new "no word" line after a `try?` check** drops the request ID (hard rule 6) and says "didn't answer" for a fast
  500 or a 429 past the retry cap. Ask where the swallowed error goes.
- **An un-defer kept "only when RYFT answered"** still reopens the sheet in the ordering the same PR assumes elsewhere (the
  `DELETE` recorded after the read). Look for one PR assuming an ordering in one place and ruling it out in another.
- Wiring that tests copy by hand (`statusReceived = { sync.receive($0, requestedAt: $1) }`) leaves the app's own line untested.
