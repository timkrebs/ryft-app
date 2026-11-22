---
name: shared-mock-train-source-reset
description: Unit-test flake class - tests using default MockPlatformAPI() share MockTrainSource.shared, which any suite's AppState.reset() empties; hits put-then-complete asserts
metadata:
  type: project
---

`MockPlatformAPI()` defaults `train:` to `MockTrainSource.shared` (process-wide). `AppState.reset()` (tests with
`AppState(env: .test())`, ConsentHarness, Journal/Notifications/Insights account tests ...) calls
`demoAPI.trainSource?.reset()` which empties it. A `TrainSyncService` replay does `putSession` then `completeSession`
through the mock; the app target has no SWIFT_APPROACHABLE_CONCURRENCY, so each mock call hops off MainActor =
a real suspension, and another suite's reset can run in between -> `completeSession` 404 -> op stays queued ->
`pendingCount == 1` (calls list still right). Seen once: PR #132 run 44895620063, ConsentTrainTests/withoutConsent...

**Why:** CI log has no Swift Testing issue text (xcresult not uploaded), so this was found by reading, then proved with a
test whose platform wrapper resets the shared source after each PUT.

**How to apply:** for "pending != 0 / complete never landed" flakes, check whether the test's platform is
`MockTrainSource()` of its own (DemoExitGraph, TrainReadsReviewTests do it right). Fix = own source per test.
Note `ConsentTrainTests` held-gate path still starts a replay (gate(.erasure) is nil) so `finish` really suspends.
