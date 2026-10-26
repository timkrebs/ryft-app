---
name: review-checks-multistep-flows
description: RYFT review checks for multi-step SwiftUI flows that build a result off the main actor (training import I4) — stale Task results after back/forward, reused sheets with side effects, auto-"seen" defeating resume rows
metadata:
  type: feedback
---

Found by reading the I4 import flow (2026-10-26):
- **One unstructured `Task` per Continue, no generation.** `continueFromMap` started `prepareBuild` (network check, then
  an off-main build) and back/forward started a second; whichever finished last set `build`, and the first to finish
  set `.ready`, so Import could send a build made from the decisions the user had just gone back to change. Look for
  a token or a cancelled handle on every "prepare" step.
- **Reused sheets carry their own side effects.** Step 4 reused `AddExerciseSheet`, whose "Custom exercise" button
  saves through `TrainLibrary.createExercise` at once (random id, local-only offline), bypassing "nothing is sent before
  Import". Check every button of a shared sheet in its new context.
- **Auto-mark-seen on display** (`.task { markResultSeen() }`) also fired for a partly failed result, so the
  "needs attention" resume row vanished and the next app-active purge deleted the job with its Retry.

**Why:** none were covered by the flow's unit or UI tests. **How to apply:** any wizard-style flow or result screen.
See [[review-checks-outbox-queues]], [[review-checks-dark-launch]].
