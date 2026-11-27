---
name: project-model-actor-thread
description: Which thread a @ModelActor job runs on differs by OS — iOS 17.0 the making thread, iOS 27.2 the awaiting thread; only made-off-main AND awaited-off-main is off main on both
metadata:
  type: project
---

These are measured facts, pinned in `RyftTests/ReadModelContextFactsTests.swift` (T0.1). The P1 work ("read-model writes off the main actor", 2026-11-17) found them; the lead ran 17.0 on an iPhone 15 Pro simulator.

**iOS 27.2: the awaiting thread decides.**
- The `DefaultSerialModelExecutor` runs a job synchronously on the thread that enqueued it, under the `NSManagedObjectContext`'s queue. `__dispatch_queue_get_label(nil)` reads "NSManagedObjectContext 0x…".
- Awaited from main, the job runs on main even when the actor was made off main.
- Awaited from a `@concurrent` function, the job runs off main even when the actor was made on main.
- A main-actor await while a job runs elsewhere **blocks main** until that job ends: 180 ms of a 200 ms job.

**iOS 17.0: the making thread decides** (F8 as first written).
- An actor made off main runs off main even when awaited from main.
- An actor made on main runs on main even when awaited from `@concurrent`.

**iOS 18–26:** not measured. The T0 observations assert nothing there: `if #available(iOS 27, *)` and `if #unavailable(iOS 18)`.

**Why:** a writer actor exists to move SwiftData work off main. Handle either half wrong and, on one of the OSes, the work runs on main, or main stalls behind another job.

**How to apply:**
- **Make and await** every model actor off main. In P1, a plain actor (`ReadModelDrain`) creates the writer lazily inside its own isolation and is the only thing that awaits it.
- Nothing on `@MainActor` constructs or awaits a model actor.
- Put a Debug `MainThread.assertOff` at the making and in every job.
- Prove the threads through the real path on both runtimes. A hook that reports the thread works: `Hooks.writerMade(onMainThread:)` and `job`.

Related: [[project-swiftdata-group-container]], [[project-swiftdata-two-containers-ios17]].
