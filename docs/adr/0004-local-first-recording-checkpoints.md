# 0004 — Activities are local-first: crash-safe checkpoints in the account's store, kept until the platform confirms

- Status: proposed (2026-10-22, My Day and activities, `docs/work/2026-10-22-my-day-activities/design.md` §2.3–§2.4,
  §3.9, §4.1, §8.4)
- Deciders: ios-lead, on ios-architect's proposal
- Applies to: `Ryft/Activities/LocalActivity.swift`, `ActivityStore.swift`, `ActivityUploader.swift`,
  `Recording/ActivityRecorder.swift`, `Recording/TrackCodec.swift`, `Train/Model/TrainStore.swift` (schema, wipe),
  `Auth/AuthService.swift` (wipe hook), `StateMachines/Machines.swift` (`RecordingMachine`)

## Context

**A recorded run can't be repeated, and the app can die mid-run:**
- a crash;
- memory pressure in the background;
- a force-quit;
- a flat battery.

**And uploads can wait:**
- a forest has no network;
- the platform's Activities contract isn't published yet;
- a `422` needs the user's edit.

**What the existing code gives us:**
- **One store.** `TrainStore`, the account's only SwiftData container, already keeps Train's sessions local-first.
  It does so with an outbox table on the main context (`TrainStore.swift`, `TrainSyncService.swift`).
- **One wipe.** Sign-out, expiry and an account switch all wipe that store with batch deletes
  (`AuthService.wipeSharedLocalData`).
- **A fallback.** When the store can't be opened, it falls back to memory.

The brief asks for checkpoints every 30 s, a resume after a kill, an idempotent offline upload queue, and that the
local copy is never lost until the platform confirms it.

## Decision

1. **One row per activity, plus append-only chunks, in the account's SwiftData store.**
   - `LocalActivity` holds what the user owns (sport, times, totals, splits, effort, notes, the route opt-in,
     pauses) and the recording header.
   - `ActivityTrackChunk` holds one checkpoint's new samples per kind, packed by `TrackCodec`:
     - `profile`: time, distance, altitude, speed; no coordinates;
     - `route`: coordinates, **only with the route opt-in**;
     - `heartRate`: BLE readings.
   - Manual activities use the same row. `LocalManualSleep` is its small sibling.
2. **Checkpoints:**
   - **When:** every 30 s on `env.clock`, on every phase change and lap, and when the app goes to the background.
   - **Who encodes:** the `ActivityRecorder` actor, off the main actor.
   - **Who writes:** one writer, `ActivityStore` (`@MainActor`, the main context), with one insert and one `save()`
     per checkpoint.
   - **Streams:** checkpoints travel on an unbounded event stream, separate from the UI's snapshot stream (newest
     only). A slow main actor can drop a stale snapshot, never a checkpoint.
3. **Resume** is part of the recording machine:
   - `interrupted` is a state, entered when a launch finds a recording row;
   - a background relaunch by Core Location resumes at once (device-verified, D3);
   - a foreground launch asks Resume, Finish or Discard;
   - Finish ends at the last checkpoint's time.
4. **The upload queue is the rows themselves:**
   - an activity needs uploading while `localRevision > confirmedRevision`, or while it carries a tombstone;
   - `PUT` by the client id is idempotent and sends the whole document;
   - a confirmation records the revision that was sent, so an edit during a request is uploaded too;
   - rows are never deleted before confirmation; "failed" is a state with a Retry.

   The exceptions: Discard, deleting a row that was never uploaded, and the account wipe.
5. **What stays after confirmation:**
   - raw `route` and `heartRate` chunks are deleted once the platform has confirmed the trimmed route and Apple
     Health (if on) has its copy;
   - the row and its `profile` stay 30 days for charts, then the nightly compaction removes them;
   - after that, the platform's copy is the record.
6. **The wipe:**
   - **User sign-out** first lists unconfirmed activities and offers to send them.
   - **Session expiry** parks unconfirmed rows and a running recording for that account (proposed, lead's question
     Q5). The same account's next sign-in uploads them; another account's deletes them.
   - **Account deletion** wipes everything.
7. **A store that fell back to memory** reports `isDurable == false`, and pre-start warns that the recording won't
   survive the app closing.

## Consequences

**Good:**
- A kill loses at most the last 30 s, and the user decides what happens to the rest.
- Uploads survive days offline and the platform's absence: the in-memory fake, then a stub (`notAvailableYet`), then
  the real client.
- Upload state lives in one place and is derived, not duplicated in an op table.
- No coordinates touch the disk without the route opt-in, and raw coordinates leave the disk at confirmation.
- One store and one wipe, as before, plus one documented exception (parking).

**Costs:**
- **Main-actor work.** One SwiftData save every 30 s on the main actor (small: one header and up to three ~1 KB
  blobs).
- **Explicit deletes.** Chunks have no relationship, because batch deletes skip cascades. They're deleted by
  `activityID`, explicitly.
- **Wipe changes.** The wipe gains a reason and, with parking, a selective path in `TrainStore.wipe`.
- **Schema growth.** The store's schema grows by three entities. That's a lightweight migration, but the "Train"
  store name is now a misnomer.
- **Location of the file.** The store probably lives in the App Group container: SwiftData's `.automatic` group
  container plus the app's group entitlement. It's verified on a device and left there, because moving it would
  orphan existing stores. Its file protection must stay `completeUntilFirstUserAuthentication`, so checkpoints land
  while the phone is locked.

**Rejected alternatives:**
- **A `@ModelActor` with its own background context:**
  - a second writer racing `wipe()` and its epoch;
  - unsaved inserts that could land after a wipe;
  - iOS 17's unreliable merges into the main context.

  Not worth it for one small save per 30 s.
- **One JSON or binary file per activity in Application Support.** A second storage mechanism, with its own wipe,
  file protection and export path.
- **A checkpoint on every fix.** Thirty times the I/O and wake-ups for at most 30 s less loss.
- **An op table like `PendingTrainOp`.** It duplicates state the rows already carry: what needs sending and what was
  confirmed.
- **Keeping the raw route until compaction.** Longer exposure of the most sensitive data, for charts that `profile`
  serves without coordinates.
