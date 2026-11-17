# 0018 — Read-model writes run off the main actor, in order, through one writer per store

- Status: accepted (2026-11-17, `docs/work/2026-11-17-persistence-off-main/design.md`; Nocturne PR 3 review row 22)
- Deciders: ios-lead, on ios-architect's proposal; sync-engineer builds it
- Applies to: `Ryft/Persistence/` (`Repository`, `ReadModels.swift`, `ReadModelWrite.swift`, `ReadModelWriter.swift`,
  `StoreEpoch.swift`), `Ryft/Environment/Seams.swift` (`Persistence`), `Ryft/Train/Model/TrainStore.swift` (`epoch`,
  `wipe`), `ReadScheduler.Store`, and every future write of a platform read model

## Context

- **Cold starts drop about 11 frames in the first 0.3 s.** About 76 of the 85 main-thread samples in the first 90 ms
  after `.active` are the Repository encoding JSON, fetching row by row, upserting and saving, plus the widget publish
  (performance-profiler, PR 3 review rows 22–24).
- **CLAUDE.md rule 5 already forbids JSON encoding on the main actor.** The Repository did it on every answer.
- **The read models are a cache of the server.** Views read them only through the Repository's memoized, revisioned
  reads. Nothing uses `@Query`, and no `@Model` object leaves the Repository.
- **The constraints:**
  - The account wipe is synchronous on main.
  - An upload gate reads the cached user in the same step that writes it (ADR 0008).
  - Swift actors don't run jobs first in, first out.
  - On iOS 17 and 18, a `@ModelActor` built on the main thread is reported to run on it.

## Decision

1. **Every write of the platform's read models runs off the main actor.**
   - It goes through the store's `ReadModelWriter`, a `@ModelActor` on the store's own `ModelContainer`: never a second
     container.
   - **No main-actor code can reach the writer.** It is `private` to a plain `actor ReadModelDrain`. Main-actor
     callers submit synchronously and await only a `WriteTicket`, never the writer. On iOS 27.2 a `@ModelActor` job runs
     on the thread that awaits it, and blocks a waiting main thread, wherever the actor was made; on iOS 17.0 the thread
     that made it decides (T0.1). So the drain both makes and awaits the writer inside its own isolation. Debug asserts
     off main at creation and in every job, and a test through `Repository` proves it on iOS 17.0 and 27.2.
   - Each store has one writer, so the account's and demo's are two instances. Writers are not split by kind.
2. **The writer owns its rows.** These are `CachedDay`, `CachedTrend`, `CachedInsight`, `CachedUser`, `CachedSleepRange`,
   `CachedWorkout`, and the `CachedDocument` keys `activities.*`.
   - Every other document and every Train table stays with the main context.
   - The account wipe is the one operation that crosses owners.
   - A write is a `Sendable` value (`ReadModelWrite`). The writer applies it with `ReadModelWrites.apply`, the one
     implementation of each write, which `seed` also runs on a main context for previews, tests and one-time imports.
   - Nothing that crosses an actor is a `PersistentModel`.
3. **Writes are applied in submit order.**
   - The Repository submits synchronously, in the same main-actor step as the read pipeline's account check.
   - It drains its queue one batch at a time. A batch never spans a store or an epoch, and it saves once.
   - A read-modify-write runs whole inside the writer. The main actor never reads the store to decide a write.
4. **Readers see a write at its commit.**
   - The Repository reads through its own read context, which it replaces at each commit and at `invalidate()`. It
     relies on neither `@Query` nor SwiftData's merging.
   - Revisions bump once per kind per batch.
   - A flight's store awaits the commit, so a refresh, and each sync pipeline stage, ends with its rows readable.
5. **A kind that a decision reads back in the same step is written through.** Today that is `.user`, which the upload
   gate reads. The memo takes it at submit, and the store follows. Adding a kind to this list is a review check.
6. **The wipe and the writer are ordered by `StoreEpoch`.**
   - The wipe's first step advances the epoch under a lock.
   - The writer checks its batch's epoch and saves inside the same lock. On a mismatch it rolls back and drops the
     batch.
   - A wipe retires the writer, so stale objects never outlive it.
   - P2 puts the widget file write under the same check.

## Consequences

**Good:**
- No read-model encoding, fetch, upsert or save runs on main. That covers pull to refresh, a sync and silent pushes on
  a real device, not only the cold start.
- Several answers in one turn cost one save and one re-render per kind instead of one each.
- Writes keep a defined order that the actor scheduler can't reorder. The wipe can't be undone by a write in flight.
- One write implementation serves the writer and fixtures, so tests and previews keep their synchronous setters.
- `cachedDay(ofActivity:)` and the Repository's main-context saves go away.

**Costs:**
- Writes are asynchronous. Production callers submit and, where they read afterwards, await `committed()`. About 7 call
  sites and the tests that read right after a write change.
- Two contexts on one container. The ownership table is a review check, and `seed` asserts that the queue is idle.
- A lock in a Swift-concurrency codebase. Its bodies are synchronous and short, and main holds it only for `advance()`.
- A freshness check can read the store state from before a pending commit for a few ms: one extra or one skipped
  revalidation.

**What could go wrong:**
- **SwiftData behaves differently on iOS 17.** The writer could run on main, or a context could keep stale rows. T0
  checks run first on the oldest runtime available. If they fail, the fallback is to encode off main and write on main
  (design option B).
- **A new write path that writes a writer-owned row on the main context.** That means merge conflicts and failed saves.
  The review check is that only `ReadModelWrites` and `TrainStore.wipe` insert or delete those types.
- **A new gate that reads a read model without write-through.** It would see the value from before the write for a few
  ms. Decision 5 and its review check cover it.
- **The Today re-render stays.** This decision removes persistence from the main thread, not the 45–85 ms first-data
  render. A gap of ≤ 33 ms after `.active` in demo mode needs that follow-up.

**Rejected alternatives:**
- **Encode off main and keep the writes on main.** Lower risk and no second context. But about a third of the cold-start
  burst stays on main, and so does every SQLite save on a device. It needs the same awaited store, ordering and epoch
  check anyway. It is the fallback.
- **A second `ModelContainer` on the same file.** It gives the same isolation as `@ModelActor`, with two coordinators,
  two row caches and WAL contention on one file.
- **One writer per kind.** The kinds share one file and saves serialize there anyway. `markTrendsStale` must follow the
  trend write, and more contexts mean more stale objects.
- **Moving Train's tables to the writer.** Live sessions mutate them on the main context, so a second writer would split
  their ownership. Train moves only its encoding and decoding off main (P3).
