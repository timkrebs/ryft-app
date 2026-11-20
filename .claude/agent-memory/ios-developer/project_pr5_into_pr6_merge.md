---
name: project-pr5-into-pr6-merge
description: Merging PR 5 (feat/nocturne-tabs) into a PR 6 branch — misplaced presentedRoot from the auto-merge, #126's outbox at every TrainLibrary, test-type name clashes, a shared-Mac gate script
metadata:
  type: project
---

M2 of the PR 6 combine (2026-11-20): `feat/nocturne-pr6-train` merged `feat/nocturne-tabs` (12 conflicts).

**Why:** the same steps come back for PR 6 A and C and the final combine.

**How to apply:**
- Resolve conflicts with a small script (scratchpad `m2/resolve.py FILE ours|theirs|both|keep …`, one choice per hunk in
  order), then hand-edit. After the merge, `git diff HEAD^1 HEAD -- <file>` for every file B restyled: the auto-merge
  put PR 5's `.presentedRoot()` on the wrong lines (inside AddExerciseSheet's two `GroupedCard`s instead of the custom
  form's sheet). The scan only checks "the closure contains it", so an if/else needs it on each branch by hand.
- A quick Python port of `PresentationScan` (`m2/scan.py Ryft`) lists presenters without it before any build.
- #126: `TrainLibrary(store:remote:outbox:…)` has no default outbox, and the outbox must share the store (asserted).
  Previews: `let outbox = TrainSyncService.preview(store: store)` then `outbox: { outbox }` (one instance, not one per
  call). Tests: `TrainLibrary.testing(store:remote:restore:)` in `RyftTests/TrainLibraryTesting.swift` (outbox on the same
  remote, demo owner, open gate). A default argument `TrainStore(inMemory: true)` on that static func doesn't compile
  (main-actor init in a nonisolated default).
- With the outbox, `createExercise` caches and queues and returns at once: a "slow custom save + Cancel" test has no race
  left. The exercise's POST goes through the outbox even while the consent gate holds (ADR 0008 §1).
- A file-private test type with the name of a PR 5 internal one (`WindowPixels`) is an "invalid redeclaration": use PR 5's
  (`try WindowPixels(w, scale: 2)`).
- Strings: `python3 scripts/sync-strings.py --derived-data build/DerivedData --check` lists +/− keys without writing the
  catalog (after a Debug simulator build into that DerivedData).
- Shared-Mac gate as a script (`m2/gate.sh`): waits in 60 s steps while "RYFT CI" is booted, load5 ≥ 200 or ≥ 3
  xcodebuilds; the load often sits at 300+ while CI runs.
- PR 5's `PresentedRootTests.todaysJournal` reads a tint from a bar button or field; B's journal sheet (SheetHeader, hidden
  bar) has neither, so B's branch got its own `expectNocturneFrame` (close id `sheet.close`, no visible bar, no stock
  switch). PR 6 C has one with the same name (`subpage.close` / `subpage.back`): reconcile them in the combine.
- Every B sheet with a toggle sets `.toggleStyle(.ryft)` itself, so no hosted test through a B presenter can catch a
  missing `presentedRoot()`; the scan is the guard.
- Timings on this Mac (idle): full Unit plan ~12 min (4152 tests, 1 known issue), B's 7 UI classes in Full ~17 min
  (39 tests), Release simulator build ~3 min.
