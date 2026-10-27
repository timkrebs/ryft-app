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

Uploader with tombstones (A2 part 1 `ActivityUploader`, 2026-10-26), all by reading:
- **"Never sent" must be persisted, not inferred.** `deleted()` removed a row locally when no attempt was recorded,
  but a cancelled request (background expiry) or an app kill wasn't recorded, and either may have reached the server.
  The platform keeps it and the "deleted" activity comes back from the cached list. A test asserting
  `lastAttempt == nil` after a cancellation enshrined it. Look for a marker written *before* the first send.
- **Natural-key rows come back to life.** A night is keyed by day; `saveSleep` revives a tombstone. A DELETE in flight
  then answers 2xx and `removeSleep(day:)` deletes the revived night. Confirm paths must check the row is still the
  tombstone or revision they sent.
- **Per-queue backoff plus strict createdAt order means head-of-line blocking:** one row the server answers with 5xx
  holds back every later row, at the 1 h cap.
- **BG task handlers awaiting `flush()`** (a shared task's `.value`) ignore the expiry cancellation, so
  `setTaskCompleted` comes late. Ask for the bounded, stream-based wait. See [[review-checks-shared-transport]].

Re-review of the fixes plus part 2 (2026-10-26):
- **Where a marker lives matters.** The "sent" marker was put in `lastAttemptData`, which `update` (an edit),
  `saveSleep` and `retry()` clear to forget a refusal. So save, cancel or kill, edit, then delete still removed the row
  locally. Grep every writer of the field a fix reuses.
- **Natural-key forms.** Add or Edit sleep lets the user change the wake date, which is the row's key. `saveSleep`
  then silently overwrites another day's manual night, or puts one over the tracker's. Check that the form validates
  the *target* key, not the day it was opened for.

Release edges keyed on a "held" flag (P2 consent gates, 2026-10-26): `gateChanged` reran a sync only if
`sync.pausedFor != nil`, but a failed revalidation threw without setting it, so the release never reran. For every
"rerun when X opens" edge, list the paths that wait without setting X. Persisted refusals also make the
epoch-after-wipe window above matter more: a late 403 from A, observed before `forgetRequests()`, is stored for B.

Batch uploader of derived-id items (training import I5, 2026-10-26), all confirmed with probe tests in my own copy:
- **A closed error-code enum turns an unknown 403 into "other".** `FailureKind` knows two codes; any other 403 (a
  future gate code, a proxy) refused every batch in turn: 120 sessions "not imported" in 3 requests. Holds should key
  on the status (403), not on the codes this build knows.
- **Whole-request 4xx refuses every item, and Retry resends the same batch.** One bad session means 50 refused,
  for good. Ask for bisection like the 413 path.
- Check that answers are matched to the *job*, not just the generation (discard, then a new job with the same ids).
- Re-review (8d6aa87): a **bisect with a "3 single refusals in a row stop splitting" brake** refuses whole batches
  once three bad items are adjacent; bad items cluster (one unknown exercise in consecutive workouts). Probe: 100
  sessions, bad 30-32 plus every 10th → 61 good refused, and Retry repeats it. Test clustered + spread bad ids.
