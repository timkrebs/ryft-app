---
name: review-checks-outbox-queues
description: Recurring RYFT review checks for persisted outboxes/queues (feedback queue, Train ops) — stale snapshot loops, late responses after account resets, epoch bumped after the wipe
metadata:
  type: feedback
---

When a RYFT change adds a persisted outbox with both a manual "send now" path and a background `flush()`,
check whether `flush()` iterates a snapshot loaded once (`for item in queue.load() where !inFlight…`).
An in-flight set only guards the moment of iteration: an item the send path finishes (and dequeues) while
flush is busy on an older item gets posted again, and items wiped on sign-out keep going out under the next
account's token.

**Why:** found in T3 "report a problem" review (2026-10-21); tests only covered sequential send/flush.

**How to apply:** look for a per-iteration re-read or membership check before each post, and ask for a test
that interleaves send and flush with a suspending mock. Also check that the platform's limit is measured the
same way the app measures it (e.g. `/v1/feedback` checks `len(json.RawMessage)` raw bytes) by reading
`../plattform/backend/cmd/api/*.go` read-only.

Related (T3 re-review, 2026-10-22): when state is "forgotten" on an account change (`APIStatus.forgetRequests()`),
check for in-flight work that writes it back afterwards (APIClient `served`/`record` after 503/429 waits of up to
~2 min) — a reset needs an epoch/account tag, not just a clear. And check that a race test *fails* against the old
code instead of hanging on a never-advanced `TestClock` sleep (advance generously before awaiting, or `.timeLimit`).

Epoch timing (T1 final, 2026-10-22): an epoch/generation bumped from RyftApp's `.onChange(of: auth.accountID)` runs a
runloop *after* `AuthService.apply` → `wipeSharedLocalData()` (synchronous `TrainStore.wipe()`); a response landing in
between still passes the guard and writes to batch-deleted rows. Check where the bump sits relative to the wipe; bump
in the wipe path (or a store epoch that `wipe()` increments). Also check the race test's stub: an "echo"/hold reply
that can't decode as the real answer makes the test pass with the post-await guard deleted.
