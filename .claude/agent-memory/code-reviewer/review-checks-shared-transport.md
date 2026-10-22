---
name: review-checks-shared-transport
description: RYFT review checks when a PR changes APIClient error shapes or adds coalescing/shared tasks (cancellation, queues, deadlines, joined waits, global holds, debounced saves, CI flakes)
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

The reverse, once waits become cancellation-aware (T1 re-review, 2026-10-22): callers that never saw a
`CancellationError` before now do. Grep `.task(id:)` loads keyed on `state.lastUpdated` (StrainViewModel,
SleepViewModel `load()`) whose `catch` sets `error = error.localizedDescription` — they show
"Swift.CancellationError error 1" when the key changes mid-read. Implementer "caller audits" missed these.

Joined replays (T1 Train fix): when a caller (Finish) now *waits* for a service-owned task instead of returning,
check the wait is bounded and the loop re-checks connectivity — `APIClient.defaultConfiguration` has
`waitsForConnectivity = true` and a 300 s resource timeout, and `isFinishing` isn't rendered anywhere.

Global holds (429 `RequestBudget.notBefore`, ≤30 s) bypass `RetryPolicy.retryAfterCap` (5 s foreground): a pull
shows "Updating…" while nothing is sent. Compare any new global wait with the per-policy caps.

CI: run `gh pr checks <n>` first (T1's Lint was red despite "lint clean"). For a "flake" verdict, check the
xcresult's actual failing test and the spindump's timestamp vs. the failure (T1: the terminate failure was the
*previous* test's app, after XCTest's crash-log wait stalled on ReportCrashService).

**Why:** found in the T1 "refresh per resource" review and re-review (2026-10-22); none was covered by tests.
**How to apply:** see also [[review-checks-outbox-queues]] (account resets refilled by late work).

Debounced persistence (T1 perf 3, 2026-10-22): when a save is coalesced behind a `Task.sleep` (ReadScheduler
`persistDelay` 1.5 s), check for a flush on `scenePhase == .background` and before a silent push's
`completionHandler` — otherwise background-recorded state (429 `retryNotBefore`, failure counts) waits for the next
wake and is lost if the suspended app is jettisoned. Sign-out dropping it is fine when the doc is wiped anyway.
