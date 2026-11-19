---
name: review-checks-shared-write-waits
description: RYFT review checks for a fix round that moves several settings pages onto one write wait (SettingsWrite, PR 6 C 6c8, 2026-11-19) and binds feature stores to the account - Demo switch sharing env.persistence, "not the latest" exits skipping the may-differ mark, abandoned requests breaking queue order, mock-thrown 429s, full-suite claims vs logs
metadata:
  type: feedback
---

From the 6c8 re-review (read-only, no build, 2026-11-19). The fixes held; these were what they left or brought:
- **Account resets that clear memory but read a shared disk store back.** `env.persistence` is `TrainStore.shared` on both sides of
  the Demo data switch (only `Repository` keeps a demo store of its own). A feature store (`JournalStore`) that writes
  `CachedDocument`s in demo and reads them back unguarded (`cachedDay`, `loadDay`'s disk step, `init`'s catalog) shows one
  side's data as the other's after the switch; a whole-record PUT built from it (the Journal sheet) writes it to the account.
  A test asserting "nothing of the account's on disk" can pass *because* demo's copy overwrote the same key. Grep every
  `env.persistence` write in demo.
- **Queues whose failure branch starts `guard mine == saves`**: an earlier save's no-answer skips the reread *and* the
  `userMayDiffer()` mark; the latest then fails offline and the page reverts past a change that may have saved.
- **A deadline that abandons a request frees the next queued write** while the first may still commit server-side: "the
  platform ends with the latest" no longer holds. Ask what re-reads after the latest succeeds.
- **One-attempt tests whose 429 comes from the mock's `failNext`** pass with `singleAttempt` removed; only the task-local
  probe (`seen.values`) proves it.
- **"N tests all green"**: read the logs' mtimes. Here the only full run failed one test (an old sentence), and only 9 suites
  x3 ran after the edit. Ask for a full run or CI on the head.
- Behaviour change to name: `singleAttempt` on writes turns a short-`Retry-After` 503 that used to save into a failure.

**Why:** found after the fix author's own green runs; each needed the live graph's wiring or the log files, not the diff.
**How to apply:** any fix round touching account binding, demo, or a shared write path. See [[review-checks-setting-editors]],
[[review-checks-outbox-queues]], [[review-checks-local-overrides]], [[review-checks-mutant-evidence]].
