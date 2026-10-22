---
name: review-checks-shared-transport
description: RYFT review checks when a PR changes APIClient error shapes or adds coalescing/shared tasks (cancellation, queues, deadlines, CI lint)
metadata:
  type: feedback
---

When a RYFT PR changes how `APIClient` reports an error (e.g. T1 rethrew `URLError.cancelled` as
`CancellationError`), grep every caller that branches on `APIError`/`.transport` — especially persisted
queues. `TrainSyncService.drain` keeps ops only for `catch let e as APIError where isRetryable(e)`; any other
error dequeues ("dropped"), and a cancelled task cancels every following request too, so the whole queue
(incl. `.complete`) goes. T3's feedback queue defaults unknown errors to "later" (safe).

When a PR coalesces work through a shared unstructured `Task` and callers `await task.value`: the waiter's
cancellation is ignored, so every deadline built on cancelling a group/run stops working (onboarding
`checkTimeout` 10 s splash, silent-push 25 s cut-off in `AppDelegate`, `SyncCoordinator.windDown`). Ask for a
cancellation-aware wait.

Also run `gh pr checks <n>` first: in T1 the Lint job (SwiftLint `empty_count` on a test helper's `.count == 0`)
was red although the PR body said lint was clean.

**Why:** found in the T1 "refresh per resource" review (2026-10-22); neither was covered by tests.
**How to apply:** see also [[review-checks-outbox-queues]] (account resets refilled by late work).
