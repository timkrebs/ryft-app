# 0020 — An account wipe is a debt written down first, finished before the store opens, and no session is published over it

- Status: proposed (2026-11-18), for the lead to accept with #107. Designed in
  `docs/work/2026-11-05-wipe-recovery/design.md` (§9 was this draft, numbered 0016 before Nocturne took that number),
  re-baselined in `rebaseline-2026-11-18.md`, reviewed in `review-w2.md` and `review-w3.md`.
- Built: W1 in #103 (the ledger), W2 and W3 in #107 (the launch's store step and the hold; #106 is included), in one
  squash commit so no build carries W2 without W3.
- Deciders: the user (2026-11-05: U1 the policy wording, U2 `Train.store` and the ledger out of device backups, U3 the
  hold and its copy); ios-lead (one PR for W2 and W3; W4a and W7 before the External build); proposed by
  ios-architect; sync-engineer builds it
- Amends: ADR 0018. `StoreReset` deletes the account store's files outside its ownership table, and only before the
  first `ModelContainer` exists, so no writer, batch or read context can hold them. ADR 0019: the demo's discard lets go
  of its open workout the way the wipe does (decision 7).
- Applies to: `Ryft/Auth/WipeLedger.swift` (`WipeLedger`, `OwedWipe`); `Ryft/Auth/AuthService.swift` (`signOut`,
  `apply`, `publish`, `clearTheWay`, `hold`, `settled`, `resumeOwedWipe`, `finishOwedWipe`, `storeStep`);
  `Ryft/Persistence/StoreReset.swift` (`StoreReset`, `WipeResume`); `Ryft/Train/Model/TrainStore.swift` (`shared`,
  `init(opening:…)`, `wipe`); `Ryft/App/RyftApp.swift` (the first-frame task and the compaction);
  `Ryft/Features/Train/TrainCoordinator.swift` (`releaseRows`, `discardDemoWorkouts`), `SessionController.release` and
  `SessionView`; `AccountScope`; and every future table, lock-screen surface or screen that holds Train rows

## Context

- **One store holds one account's data.** The read models and logged sessions have no account column, so the wipe is
  what separates accounts. A session published over a failed wipe reads the last account's rows.
- **A wipe can fail.**
  - It can be refused (a full disk, a delete the store won't take) or killed.
  - It isn't atomic: batch deletes commit at once, object deletes land in the final save.
  - A refused save leaves its deletes pending in the main context, and the next save by anyone lands them or fails
    with them.
  - The SDK drops the Keychain session before `apply(nil)` runs, so after a kill nothing says a sign-out was under way.
- **#93 made the wipe report failure, but the only record was `auth.lastUserID`.** That id also means "whose data
  this is" to the HealthKit anchors and the export choice. One id can't say both, a second failure overwrote it, and
  the retry at the next sign-in took that account's unsent work.
- **A live store's bytes outlast a wipe:** deleted values stay in the WAL and free pages, and history keeps row counts.
- **On iOS 18 and 26, reading a relationship of a deleted, saved row is a fatal error,** whatever was read before the
  delete: 18.0 says "Context is missing", 18.6 and 26.0 "Never access a full future backing data" (26.0 in one run of
  two). 27 answers. Until the account-change handler ran, a runloop after the wipe, the live workout's screen and the
  in-progress banner held such rows, and the rest bar reads the next set twice a second. The minimum is iOS 18.6
  (ADR 0021).

## Decision

1. **A wipe is written down before it starts.**
   - `WipeLedger` writes the entry to `Application Support/account-wipe.json` (atomic, the Keychain session's
     protection class) before the first destructive step and before the SDK drops the session. Not UserDefaults: it
     may not reach the disk before a crash.
   - One entry. A later wipe merges into it: the earliest `since` stays, and anything that doesn't park the same
     account narrows it to no parking. It never widens back.
   - The entry goes only:
     - when a pass returned true, the launch's replace left no files, an interrupted sign-out's `client.signOut()` has
       run, and no pass in this process was refused;
     - or by `.forget` at launch: its account was published over it (`publishedOver`) and is stored, a W1 build's
       entry over its own account's session (unless it's a deletion's), or a scrub with any session.
2. **`auth.lastUserID` only says whose data the store holds.** The debt is the ledger's. A failed wipe doesn't write the
   id back, and `AccountScope` follows the published session, so anchors and the outbox never read another account's
   id.
3. **At launch the debt is settled before the store opens.**
   - `AuthService.init` decides the entry against the stored session (`WipeResume.decide`) and leaves it in
     `forStoreStep`. `TrainStore.shared`'s initializer runs `StoreReset` on it before the first container exists:
     `Train.store`, its `-wal`, `-shm` and support folder, and the app container's copy, go.
   - The object wipe runs afterwards anyway, and catches a file that couldn't go or a copy SwiftData brought back.
     Files the replace couldn't remove count as a refusal.
   - A session expiry within 30 days of `since` keeps its parked rows: no replace, and the object wipe after the first
     frame, parked `at: since`. Past the limit, or with another account stored, it narrows to a replace.
   - An entry of the stored account's own is a sign-out a kill interrupted: the wipe runs and the session is ended, not
     published.
   - Debug asserts that the ledger was resolved before anything opened the store. Opened first, the store step replaces
     nothing and the launch falls back to the object wipe.
4. **No session is published over a debt.**
   - `publish` goes through `clearTheWay`. Another account's sign-in makes one attempt with no parking: true publishes
     it, false holds it.
   - A hold throws before `session`, `accountChanges` or the hooks change for the new account. A published account's
     session ends first, hooks included, so a wiped account never stays on screen. The SDK keeps the new session, so the
     next launch publishes it without another login.
   - Welcome and Log in say "RYFT couldn't finish removing the previous account from this iPhone. Close RYFT and open it
     again to continue." The message is derived from the hold, so a screen that clears its errors as it appears doesn't
     hide it.
   - The entry's own account coming back (`lastUserID` nil or that account, written by a W2 build or later, and not a
     deletion's) is published after one attempt either way, because its rows are its own. A true attempt in a process
     with no refused pass ends the debt. Otherwise the entry stands, marked `publishedOver`, so the next launch doesn't
     take that account's live work. If the disk refuses the mark, the file goes and this process keeps the entry.
5. **Once a pass is refused in a process, nothing in that process ends the debt.** A refused save leaves rows inserted
   in the context that a batch delete doesn't see, and a later pass's save answers true and writes them. Only a later
   launch's replace or fresh context is proof. So the copy asks for a relaunch, and every route in the process
   (the SDK's events, a sign-in, the first frame, the compaction) holds without trying again.
6. **The retry runs at launch, after the first frame and in the nightly compaction,** once per process, and never over a
   session, published or stored, except the one an interrupted sign-out is ending. A stored session that the launch
   couldn't read goes through the launch table at the next launch.
7. **Code that deletes Train rows lets go of what holds them in the same turn.**
   - The wipe's store step clears the widget's readiness file, stops Train's replay, wipes the offline library and calls
     `TrainCoordinator.releaseRows()`. That releases the open workout (`SessionController.release()`: stopped for good,
     and `SessionView` then draws none of its rows) and the in-progress banner's session, before anything draws again.
     The account-change handler still follows.
   - The demo's discard (ADR 0019) releases its open workout the same way.
   - A launch wipe has nothing open: `TrainCoordinator.existing` keeps it from building the coordinator.
8. **Nothing infers a debt from a missing session.** Before the first unlock a Keychain miss looks the same, and would
   wipe a signed-in user.
9. **No remote flag.** Recovery runs before `/v1/config` and while signed out, and a privacy fix shouldn't be switchable
   off.

## Consequences

**Good:**
- A permanent refusal ends at the next launch, without depending on the delete that failed.
- A launch recovery costs milliseconds: a file replace, not a wipe of every row on main.
- A replace takes the WAL, free pages and history with the files.
- A later account's work can't be taken by a retry, and no account reads or uploads another's rows.
- The same account coming back keeps its work, and a parked row's 30-day limit never restarts.

**Costs:**
- A rare sign-in is held until RYFT is closed and opened again.
- A second piece of launch-critical state, `forStoreStep`, has to stay in step with `TrainStore.shared`. The Debug
  assertion catches a flipped launch order in UISmoke.
- The only code that deletes a live store's files. It stays behind the ledger, and runs only before the container opens.
- A returning account after a refusal works on a context whose saves keep failing until the refusal ends or the next
  launch, as any refused wipe did before.
- The object wipe still blocks the main thread: 3.4 s for 44,500 rows in Debug. A parking resume after the first frame
  can stall the launch sequence (ADR 0017); rare, and it doesn't gate startup.
- Files that never go keep a sign-in held at every launch, and the copy's "close and open" doesn't help there. Deleting
  the app should (unverified, U5).

**Not built here, and needed before the External build:**
- **W4a:** nothing writes the widget while a debt exists (the design's I5). Until then a refused `CachedDay` delete can
  put the leaving account's readiness back on the lock screen through `onWipe`.
- **W7:** after a true no-parking wipe the entry stays as a scrub, so the next launch signed out replaces the files;
  `Train.store` and the ledger leave device backups (U2). Until then, the WAL and free pages keep deleted values after
  an in-process wipe.

**Later tickets:** W4b (the Live Activity, delivered notifications and the push registration during a hold), W5 (the
notice says what's left on the iPhone), W6 (rows never saved before A3b), W9 (a deletion written down before the
`DELETE`), W10 (a held Sign in with Apple keeps its authorization code), W11 (no demo over a debt: the demo's Train
reads the account's store, so a refused wipe's sessions show in it).

**Rules:**
- A new table needs no change here, but it must stay wipeable by `WipedTable`: the healthy-store test lists every
  entity.
- Anything writing a lock-screen surface checks the ledger.
- `StoreReset` runs only in `TrainStore.shared`'s initializer, on what this launch's `AuthService` resolved. Nothing
  replaces the files of a store that's open; a reopen of the account's store, if one is ever built, doesn't either.
- Nothing reachable from `TrainStore.wipe`, the wipe's memory step or `TrainSyncService.accountChanged()` reads
  `AppEnvironment.live` synchronously: a wipe at launch runs inside its `swift_once`, and that was a crash at every
  launch with an entry.
- Code that deletes Train rows a screen may hold releases them in the same turn (decision 7).
- An account column on the read models would make decision 4 removable. It isn't planned.

**Measured** (2026-11-19, simulator, `-parallel-testing-enabled NO`): the wipe, ledger, hold, read-model, consent and
demo-exit suites pass on the iPhone 16 Pro at iOS 18.6 (380 tests in 26 suites), the held-row trap's tests included;
with the auth, Train sync, session and store suites added, 537 tests in 47 suites pass on iOS 27.2. A mutant that stops
the demo's open workout instead of releasing it fails both of its tests on 18.6.

## Alternatives

- **Retry the object wipe at launch.** A permanent refusal fails at every launch, it takes seconds on main with the
  watchdog's risk, and the WAL and history stay.
- **Scope every table by account.** A migration of 12 tables and every read and write, with no versioned schema, and
  the hidden rows are still not deleted.
- **Publish over a failed wipe and wipe again at the next launch** (#93). It takes the next account's work.
- **Release in process, through a reopen of the store** (W12). Not needed by what was measured, and ADR 0019's reopen
  isn't built.
- **Infer the debt from "an id, but no session".** A Keychain miss before the first unlock looks the same.
