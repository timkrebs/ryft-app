---
name: review-checks-refusal-states
description: RYFT review checks when an outbox turns "drop on 4xx" into "keep as a refused state" (Train O1+O2, 2026-11-19) - what the old drop let through behind the op, 2xx-undecodable as refusal, queued creates breaking online callers, form validation the online error used to surface, Retry that can't recreate a missing dependency
metadata:
  type: feedback
---

From the Train O1+O2 review ("a refusal stays queued", `fix/train-refusals-kept`, 2026-11-19), by reading (the caller
said don't build):
- **What did the old drop let through behind the refused op?** The old code dropped a refused `PUT` and then sent the
  session's `complete`, which scored the platform's earlier copy. "Hold the session's later ops" withholds that for a
  session the platform already has (`LocalSession.uploaded`). The app has no 50-sets cap and no 2,000-character notes
  cap, so a 51st set did it. For every "the item's later ops wait", ask whether the server would have accepted them.
- **`APIClient.decode` maps a `DecodingError` to `APIError.http(<2xx>)`**, which `FailureKind.of` calls `.other`. So
  any rule based on `isRefusal` stores a delivered request as refused (closed-enum drift: a new PR kind in a
  completion's answer). Check 200..<300 in every new refusal classifier.
- **Moving a create from "await online" to an outbox breaks callers that relied on the order.** The plan builder and
  replace's "Also change the plan" save a plan right after `createExercise`. That `PUT /v1/plans` can now beat the
  queued `POST /v1/exercises` (the platform answers `422`). Grep every caller of the moved function.
- **Validation that the online error used to show.** Online, a `422` (name over 80 runes) was shown at once. Queued, it
  is silent and permanent, and every workout that uses the exercise is refused with it. Compare the form's checks with
  the platform's validator, e.g. `plattform/backend/internal/train/train.go` `validName`. It counts runes, not Swift
  Characters.
- **Retry that can't succeed.** A refusal whose root cause has no op left can't be fixed by Retry: an exercise the demo
  left in the account's store (ADR 0019, STATUS known issue), an op an older build dropped (`Kind ?? .put` dequeues an
  unknown kind), or a legacy orphan. Ask whether Retry re-queues the dependency.
- The unknown-403 check from [[review-checks-outbox-queues]] recurred: Train made a 403 without a known code a
  permanent refusal, while `TrainImportUploader` holds every 403. Quote the precedent.

**Why:** the PR's tests passed and followed the plan's acceptance criteria literally; each of these was outside them.
**How to apply:** any PR that turns drops into states (O6 WriteOutbox next). See [[review-checks-outbox-queues]],
[[review-checks-undo-windows]], [[review-checks-mutant-evidence]].
