---
name: project-swiftdata-batch-delete
description: SwiftData delete(model:) skips the context's unsaved inserts and changes; the next save writes them back — fetch and delete each inside a batched writer
metadata:
  type: project
---

Found 2026-11-17 in P1 (read-model writes off the main actor, iOS 27.2 sim). The writer applies a batch of writes on one
context and saves once. `context.delete(model:where:)` is a store-level batch delete: it doesn't see rows the same
context inserted and hasn't saved, so the batch's one save inserts them after the delete. A `.clear` or `.compact` queued
behind inserts left rows behind, and two `.insights` writes in one batch left two sets of cards. Before P1 every write saved
on its own, which hid this.

**Why:** a cleared or wiped read model that keeps rows is a privacy bug (another account, the demo switch). A batch delete
may also reach the store at once, outside the save and its epoch check (design F4).

**How to apply:** in any context that batches writes before one save, delete with fetch and `context.delete(each)`
(`ReadModelWrites.deleteAll`). `TrainStore.wipe` deletes one by one for the same reason. Test it with a write held in the
writer (`WriterHold`), so the deletes and the inserts land in one batch. Related: [[project-model-actor-thread]].
