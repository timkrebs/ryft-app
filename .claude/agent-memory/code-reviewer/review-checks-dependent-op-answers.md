---
name: review-checks-dependent-op-answers
description: RYFT re-review checks when an outbox fix lets a later op go past a refused earlier one (Train O1+O2 fix round, 2026-11-19) - the later op's answer overwriting local edits, vacuous fixtures with foreign ids, waits added inside shared calls past callers' guards, explicit-list refusal classifiers vs API.md's catch-all 4xx, refusals Retry can never fix, untested side effects in a second outbox
metadata:
  type: feedback
---

From the O1+O2 fix-round re-review (`fix/train-refusals-kept`, 4dba6ee, 2026-11-19), by reading (no build allowed):
- **"Don't hold the dependent op" needs a look at what its answer writes back.** ADR 0022 §5 let `complete` go past a
  refused `PUT` of an uploaded session (my first-round suggestion). `perform(.complete)` then runs `s.apply(done)`, and
  `LocalSet.update(from:)` overwrites reps, kg and `completedAt` without comparing `updatedAt`. It also overwrites notes
  and title. Every value logged after the refused PUT reverts to the platform's copy, and Retry then sends the
  reverted doc. Plan sessions pre-create their sets (`SessionFactory`), so that can be the rest of the workout. The
  409 path merges by `updatedAt` (`SessionMerge`) and the completion path doesn't. Whenever a fix lets op N+1 pass a
  refused op N, read N+1's answer handler.
- **Fixture ids decide whether an "apply" test can fail.** The §5 test answered `complete` with
  `train_session_completed`, a session with other ids, so `apply` appended exercises and "set 51 stays" was trivially
  true. Ask for the platform's copy of *this* session, plus an edit made after the refusal.
- **A wait added inside a shared function moves the request past its callers' guards.** `savePlan` gained a 10 s
  `exercisesSent` wait. `SessionController+Replace.changePlan` checks generation and Undo *before* calling it, and its
  comment says "no plan PUT with the next account's token". Grep callers for guards placed just before the call.
- **Explicit status lists drift from API.md's catch-all.** API.md → Errors: "any other 4xx (405, 431…) is like 400:
  do not resend unchanged". `isRefusal` lists only 400/409/413/422 (+404 on complete), so 405/410/431, a 2xx it can't
  decode, 426 and non-API errors all became holds. For activities they were refusals before.
- **Refusals that Retry can never fix.** These need a code path or an API request, not a button: stale `plan_day_id`
  or `plan_exercise_id` after a plan was deleted elsewhere (platform `checkReferences` → 422), NUL in typed text
  (API.md: strip it), and a 409 "id taken". Read `plattform/backend/internal/store/train.go` `checkReferences`
  read-only.
- **A one-line change to a shared classifier changes a second outbox, untested.** `ActivityUploader.failed` started
  holding 403-without-code, 426, an unreadable 2xx and unlisted 4xx with backoff. No ActivityUploader test was added.
  Grep the other outbox's tests for each status that changed.
- Mutant logs: "SURVIVED" followed by a rerun with "ERROR 65" plus a detach trap counts as killed. Check the trap is
  the mutant's effect. Line numbers in the log that drift from the current file mean tests were added after the run.

**Why:** the fix round passed 23/23 mutants and the full Unit plan; each of these sat outside the tests' fixtures.
**How to apply:** any fix round that relaxes ordering between dependent ops (O3 backoff, O6 WriteOutbox, O1b heal). See
[[review-checks-refusal-states]], [[review-checks-outbox-queues]], [[review-checks-mutant-evidence]].
