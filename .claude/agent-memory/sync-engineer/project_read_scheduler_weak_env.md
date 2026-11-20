---
name: read-scheduler-weak-env
description: ReadScheduler holds its AppEnvironment weakly; a test env released early makes every read "offline" (hold() says .offline, run returns nil)
metadata:
  type: project
---

`ReadScheduler` keeps its `AppEnvironment` weakly. In a test, a `let env = AppEnvironment.test(...)` whose last use is
early can be released by ARC before the reads run: then `hold(_:userInitiated:)` says `.offline` and `run` returns nil
without sending, so a "held back" or "online" test silently becomes an offline one.

**Why:** found writing R4T's held-back tests (2026-11-20); `TrainPlansSummaryShotsTests` keeps a static env for the same
reason. An inline `AppEnvironment.test(online: false).reads` only "works" because a dead env also reads as offline.

**How to apply:** in every test that hands `env.reads` to a library or model, add
`defer { withExtendedLifetime(env) {} }` right after creating it (or end the test with `withExtendedLifetime(env) {}`).
See also [[test-waits-on-actors]] and [[repetitions-and-mock-calls]].
