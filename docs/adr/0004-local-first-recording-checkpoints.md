# 0004 — Activities are local-first: crash-safe checkpoints in the account's store, kept until the platform confirms

- Status: proposed (2026-10-22, My Day and activities, `docs/work/2026-10-22-my-day-activities/design.md` §2.3–§2.4,
  §3.9, §4.1, §8.4, §8.6); revised the same day after the security and privacy review (B1, B2, S1, S2)
- Deciders: ios-lead, on ios-architect's proposal; security-privacy-reviewer for the account and at-rest rules
- Applies to: `Ryft/Activities/LocalActivity.swift`, `ActivityStore.swift`, `ActivityUploader.swift`,
  `ActivityVault.swift`, `Recording/ActivityRecorder.swift`, `Recording/TrackCodec.swift`,
  `Train/Model/TrainStore.swift` (schema, wipe), `Auth/AuthService.swift` (account hooks),
  `StateMachines/Machines.swift` (`RecordingMachine`)

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
  It does so with an outbox table on the main context.
- **One wipe.** Sign-out, expiry and an account switch all wipe that store with batch deletes, including every
  `CachedDocument`.
- **No memory of the last account.** `AuthService` forgets the last account id on sign-out, so a later sign-in by
  someone else triggers no wipe.
- **A fallback.** When the store can't be opened, it falls back to memory.
- **Backups.** The store probably sits in the App Group container, and it goes into device backups.

The brief asks for checkpoints every 30 s, a resume after a kill, an idempotent offline upload queue, and that the
local copy is never lost until the platform confirms it. The review adds:
- an expired session must not leak a home or move a run to another account (B1, B2);
- data at rest must be protected (S1);
- a background relaunch must not locate someone long after their run (S2).

## Decision

1. **One row per activity, plus append-only chunks, in the account's SwiftData store. Every row carries its
   `account`.**
   - `LocalActivity` holds what the user owns (sport, times, totals, splits, effort, notes, the route opt-in,
     pauses, the zone count at recording) and the recording header. The header holds **no coordinates**, not even
     the filter's anchor.
   - `ActivityTrackChunk` holds one checkpoint's new samples per kind, packed by `TrackCodec`:
     - `profile`: time, distance, altitude, speed; no coordinates; not sealed;
     - `route`: only with the route opt-in, **trimmed by privacy zones and sealed before it's written**;
     - `heartRate`: sealed.
   - `LocalManualSleep` and `LocalPrivacyZone` (sealed) follow the same account rule.
2. **Checkpoints:**
   - **When:** every 30 s on `env.clock`, on every phase change and lap, and when the app goes to the background.
   - **Who encodes, trims and seals:** the `ActivityRecorder` actor (AES-GCM, per-activity keys in the Keychain,
     `AfterFirstUnlockThisDeviceOnly`). If the Keychain fails, no route chunk is written: never an unsealed one.
   - **Who writes:** one writer, `ActivityStore` (`@MainActor`, the main context), with one insert and one `save()`
     per checkpoint.
   - **Streams:** checkpoints travel on an unbounded event stream, separate from the UI's snapshot stream (newest
     only).
3. **Resume** is part of the recording machine. `interrupted` is a state, entered when a launch finds a recording
   row of the signed-in account.
   - **A background relaunch** resumes at once only if the last checkpoint is at most 10 min old. Otherwise the
     background location session is invalidated immediately, and the next foreground launch asks.
   - **A foreground launch** offers Resume only for a gap under 6 h on the same day; otherwise Finish or Discard.
   - Finish ends at the last checkpoint's time.
4. **The upload queue is the rows themselves:**
   - an activity needs uploading while `localRevision > confirmedRevision`, or while it carries a tombstone;
   - `PUT` by the client id is idempotent and sends the whole document;
   - a confirmation records the revision that was sent, so an edit during a request is uploaded too;
   - rows are never deleted before confirmation; "failed" is a state with a Retry.

   The exceptions: Discard, deleting a row that was never uploaded, the account rules below, and point 6's raw-route
   limit (which drops the route, not the activity).
5. **Every read is scoped to the account.**
   - `ActivityStore` filters every fetch by the signed-in account, and the uploader and My Day read only through
     it.
   - `AuthService.onAccountWillChange` runs inside `apply` before the new session is published. It purges every
     other account's rows, chunks, zones and keys (keys first) before the first flush or My Day read.
6. **Lifetimes:**
   - **At confirmation:** the activity's keys are deleted once Apple Health (if on) has its copy, then the raw
     `route` and `heartRate` chunks. This is crypto-shredding: ciphertext left in SQLite free pages or backups is
     unreadable.
   - **Unconfirmed for 30 days:** the raw route goes the same way; the activity stays and says so.
   - **After confirmation:** rows and `profile` stay 30 days for charts, then compaction removes them.
7. **The wipe, per path:**
   - **User sign-out** first lists unconfirmed activities and offers to send them, then deletes that account's rows
     and keys.
   - **Session expiry** parks unconfirmed rows, their chunks, the account's zones and keys, and a running recording,
     all still bound to the account. `TrainStore.wipe(parkingActivitiesOf:)` skips the four models.
   - **The same account** signing in unparks and uploads them. **Another account** signing in purges them.
   - **Parked rows expire after 30 days.** An account deleted on the web looks like an expiry.
   - **Account deletion** in the app deletes everything.
8. **A store that fell back to memory** reports `isDurable == false`, and pre-start warns that the recording won't
   survive the app closing.

## Consequences

**Good:**
- A kill loses at most the last 30 s, and the user decides what happens to the rest.
- Uploads survive days offline and the platform's absence: the in-memory fake, then a stub (`notAvailableYet`), then
  the real client.
- Upload state lives in one place and is derived, not duplicated in an op table.
- No in-zone coordinate touches the disk. Raw coordinates are sealed, and they're unreadable once the platform has
  them, after 30 days unsent, or after any wipe.
- One account's data can't be shown or sent under another account, whatever the order of sign-out and sign-in.

**Costs:**
- **Main-actor work.** One SwiftData save every 30 s on the main actor (small: one header and up to three ~1 KB
  blobs). Sealing and trimming happen in the actor.
- **Keychain lifecycle.** Keys per activity and per account, with orphan cleanup at launch and after a reinstall
  (Keychain items survive an uninstall).
- **Explicit deletes.** Chunks have no relationship, because batch deletes skip cascades. They're deleted by
  `activityID`, explicitly.
- **Wipe changes.** The wipe gains a reason and a parking path. The 30-day parked limit can delete an expired user's
  unsent run if they don't sign in for a month; the confirmation of that risk is the review's.
- **Schema growth.** The store's schema grows by four entities. That's a lightweight migration, but the "Train"
  store name is now a misnomer.
- **Location of the file.** The store's file location is verified on a device and left where it is, because moving
  it would orphan existing stores. Its file protection must stay `completeUntilFirstUserAuthentication`, so
  checkpoints land while the phone is locked; the Keychain class matches.

**Rejected alternatives:**
- **A `@ModelActor` with its own background context:**
  - a second writer racing `wipe()` and its epoch;
  - unsaved inserts that could land after a wipe;
  - iOS 17's unreliable merges into the main context.
- **One file per activity in Application Support.** A second storage mechanism, with its own wipe, protection and
  export path.
- **A checkpoint on every fix.** Thirty times the I/O and wake-ups for at most 30 s less loss.
- **An op table like `PendingTrainOp`.** It duplicates state the rows already carry.
- **Trimming only at send time** (the first version of this ADR). The raw route sat at rest untrimmed, and an expiry
  that lost the zones uploaded it untrimmed (B1).
- **Relying on `lastUserKey` to detect another account.** Sign-out clears it (B2).
- **SQLCipher or a separate encrypted store.** It's a dependency. CryptoKit and the Keychain are system frameworks
  and cover the only sensitive columns.
