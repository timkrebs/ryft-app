---
name: project-swiftdata-deleted-row-ios18
description: iOS 18.0, 18.6 and 26.0 trap on relationship reads of a deleted, saved SwiftData row even if read before the delete; 17 and 27 fine; release holders in the wipe turn
metadata:
  type: project
---

Measured 2026-11-18 on the iOS 18.0 simulator (B5a, #107):
- After `context.delete` and `save()`, reading a relationship of a row something still holds traps:
  `SwiftData/BackingData.swift:296` (to-many: `session.exercises`, `exercise.sets`) or `:251` (to-one:
  `set.exercise`), "Context is missing". **Reading the relationship before the delete does not help**: a pre-read of
  every relationship in `TrainStore.wipe` changed nothing (each single-row test trapped before and after).
- Attribute reads and writes on that row still work there, and a later save writes nothing back. The row's
  `modelContext` is nil, `isDeleted` false, `persistentModelID.storeIdentifier` kept (an uninserted row: nil).
- **iOS 18.6** (measured the same day) traps differently: the relationship answers, but a row it yields that nothing
  held traps on access, `BackingData.swift:739` "Never access a full future backing data". The hosted screen without
  its guard did not trap there, because it had loaded every row. **iOS 26.0 traps the same way** (`:908`), in one run of
  two (alone it passed, in the suite it trapped), so one passing run proves nothing. iOS 17.0 and 27.x answer the reads.
- The 18.0 runtime was removed on 2026-11-18. The Mac now has 17.0, 18.6, 26.0 and 27.x, and the minimum is iOS 18.6
  (ADR 0021, PR `chore/min-ios-18`).
- The delete itself doesn't re-render a view that holds the row (hosted probe: banner and presented cover survived
  1.5 s). A later draw does: the rest bar's 0.5 s `TimelineView` reads `nextLabel()` and trapped in a hosted
  `SessionView` test.

**Why:** the lead's suggested fix (pre-read in the wipe) was disproven only by running it on 18.0. Each probe cost a
3–5 min build, so the facts are worth keeping.

**How to apply:** for any code that deletes rows something may still hold, make the holders let go in the same
main-actor turn (as `TrainCoordinator.releaseRows` from the wipe's memory step) and have the screen root draw none of
it. Don't trust "resolved before the delete". To show a trap per read, put each read in its own `@Test` and run them
one by one with `-only-testing:…/name()`, because a trap ends the process. Related: [[project-os-runtime-probes]],
[[project-swiftdata-two-containers-ios17]].
