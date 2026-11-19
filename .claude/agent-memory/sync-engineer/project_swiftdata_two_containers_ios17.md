---
name: project-swiftdata-two-containers-ios17
description: iOS 17.0 SwiftData — only the newest ModelContainer takes inserts (134020); reopen fixes it (T0.7) but wasn't merged: minimum is iOS 18.0 from 2026-11-18
metadata:
  type: project
---

Measured 2026-11-17 on the iOS 17.0 simulator (21A328, iPhone 15 Pro). Pinned as T0.6, the nested suite
`ReadModelContextFactsTests/TwoContainers` in `RyftTests/ReadModelContextFactsTests.swift`. It holds a probe and an
app-path test (on-disk account store, then the Repository's demo store, then demo off, then a read-model write and a
Train row). Each test prints one `T0.6 …` line per runtime.

**What happens once a second container of the same schema exists:**
- A save of a **new** row into any context of an **older** container fails with NSCocoaErrorDomain **134020**: "the object's persistent store is not reachable from this context's coordinator".
- This holds for fresh contexts and `mainContext`, on disk and in memory. Every in-memory `TrainStore` has its own configuration name, so name sharing isn't the cause.
- Releasing the newer container doesn't help.
- Opening the older store again (a new container on its URL) fixes that store and breaks the other one.
- On 17.0 the app path gives: the demo's write is saved; the account's read-model write and Train row are not saved; a fresh context reads 0 of each.
- iOS 27.2: every combination saves.
- 17.1–17.6 and 18–26: not measured. Their runtimes weren't installed on the shared Mac then.

**Where RYFT runs into it:**
- The Repository's first read in demo mode makes the demo store (`demoStoreInstance`), a second container. `ActivityStore` makes another.
- Train's demo data has no store of its own: sessions, ops tagged `demoOwner`, import mappings and pending imports all live in the account store (`TrainStore.shared`). So on 17.0 Train's writes during the demo also fail.
- A workout started in the demo stays in progress after Demo data is turned off.
- main hid it: its failed saves left the inserts unsaved in `mainContext`, readable until relaunch. After P1, the writer's failed save rolls back, so the screen doesn't show those rows either.
- Test fallout:
  - `importsOnceAndDeletesTheFiles` was fixed by using one store, as the app does.
  - `aBatchNeverSpansTwoStores` has its account half marked `withKnownIssue` on `#unavailable(iOS 18)`.
  - Since the P1 fix round, `Repository.reset()` makes a new demo store at every Demo data switch (newest container,
    so demo writes land on 17.0). The wipe stress test's `demo: true` rounds have their account-store half as the same
    known issue (`when: demo && #unavailable(iOS 18)`). Any new test that writes the account store while demo data's
    store exists (`WipeHarness(demo: true)`, `writingToAccountStore`) needs the same.

**P1b (2026-11-18, ADR 0019, branch `fix/ios17-demo-exit`): the user then made iOS 18.0 the minimum, so the reopen
and the one demo store below were NOT merged** (kept on the local branch `backup/p1b-ios17-reopen`). P1b ships only
the OS-independent demo exit. What was measured and built before that decision:
- T0.7 passed on 17.0, 18.0, 26.0, 27.2: a new `TrainStore(url:)` on the account's file, made while the demo's
  container is alive, takes inserts on main and through an off-main writer; a second reopen in one process works; no
  trap reading the old context's pending objects or releasing it. The old container's context still *reads* the file
  (it fetched rows the reopened container saved): never fetch from it again.
- T0.8 found the demo itself broken on 17.0: the Repository's demo store refused once `ActivityStore` made its own.
  Fixed by one `DemoStore` per `AppEnvironment` (`env.demoStore`), shared by both.
- `TrainStore.reopen()` swaps `container` in place (epoch advance, old kept with autosave off); `AppState.demoEnded()`
  reopens only `#unavailable(iOS 18)` (`reopensAccountStoreAfterDemo`, tests set it); the drain reuses a writer only on
  the same container. Writes into the account's store *while* demo is on still fail on 17.0 (accepted; tests state the
  OS rule per runtime instead of `withKnownIssue`).
- T0.9 (measured 2026-11-18): on 17.0 a **new object can't join a relationship with an object made before a newer
  container existed**: NSInvalidArgumentException "Unacceptable type of value for to-one relationship … given type =
  NSManagedObject", which **terminates the process** (Swift Testing reports "crashed with signal abrt" for every test
  left in the run). The test is `.enabled(if:)` off on 17.0 for that reason. In tests the trigger is usually a lazy
  `TrainStore.shared` (the host runs `TestHostApp`, so `AppEnvironment.live` opens on first use, e.g. through
  `TrainCoordinator.sessionLayout`/`jumpToNext`): stub those in rigs. In the app: an account's workout continued during
  the demo crashes on its next set (STATUS → Known issues).
- 17.0 posts no `ModelContext.didSave` to an observer with `object: nil` (measured 2026-11-18 with a print in the
  observer: none of a suite's saves arrived). Save-order tests read the log only `#available(iOS 18)`; on 17 prove the
  order by outcome (rows in the file, `writeHooks.writerMade`).

**Why:** an iOS 17 test failure that involves two stores is this platform bug, not the code under test. A fix has to keep the account's store the newest container, or avoid having a second one.

**How to apply:**
- On 17.x, check `make` order before blaming the writer.
- Read the writer's log (`category == "reads"`, "Read-model save failed: … 134020") with `simctl spawn … log show`.
- A new `TrainStore(inMemory:)` or `ModelContainer` in app code makes every older one refuse on 17.0: demo data must
  stay on `env.demoStore`.

Related: [[project-model-actor-thread]], [[project-swiftdata-group-container]], [[project-os-runtime-probes]].
