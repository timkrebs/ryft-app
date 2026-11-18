# 0019 — Ending the demo discards its workouts, and on iOS 17 reopens the account's store

- Status: proposed (2026-11-18, `docs/work/2026-11-18-ios17-demo-exit/design.md`). The T0 gate (design §7) runs first.
- Deciders: the user (the demo's workouts are discarded after a confirmation, 2026-11-17); ios-lead (the reopen is iOS 17
  only); proposed by ios-architect; sync-engineer builds it
- Amends: ADR 0018. The account's `ModelContainer` is no longer one instance for the life of the process: on iOS 17 it
  is replaced in place after the demo. "One writer per store, never a second container" still holds per container.
- Applies to: `Ryft/Train/Model/TrainStore.swift` (`container`, `reopen()`), `Ryft/Environment/Seams.swift`
  (`Persistence.reopen()`), `Ryft/App/AppState.swift` (`demoEnded()`), `Ryft/Train/TrainSyncService.swift` (the demo's
  session list and its discard), `Ryft/Features/Train/TrainCoordinator.swift`, `Ryft/Features/Profile/ProfileViewModel.swift`
  and `ProfileView.swift` (the exit and its confirmation), `Ryft/Persistence/ReadModelDrain.swift` (the writer's key),
  and every future write that happens while Demo data is on

## Context

- **Demo data is a runtime switch,** and Profile's switch is the only production way out of it, signed in or not. "Try
  the demo, then sign in" means switching it off, then signing in on Welcome.
- **The demo's read models and activities each have an in-memory store of their own.** The demo's Train doesn't:
  - its sessions, ops and library live in the account's store (`TrainStore.shared`);
  - only the ops are bound to "demo".
- **So a demo workout becomes the account's:**
  - one still in progress uploads to the account at its next change;
  - finished ones show in the account's Strain, My Day and Train history;
  - a first sign-in doesn't wipe them.
- **iOS 17.0 (measured, T0.6): only the newest `ModelContainer` of the schema takes inserts.**
  - Creation order decides; releasing the newer container doesn't help the older one.
  - The demo's stores are made after the account's, so once the demo ends the account's new rows aren't saved until a
    relaunch.
  - Read models are a cache and are fetched again, but Train sessions and activities are local-first and get lost.
  - 18.0, 26.0 and 27.2 save fine; 17.1–17.6 haven't been measured.
- **A rollback of a refused change traps on iOS 17.0** (ADR 0018, decision 6).
- **Nothing outside `TrainStore` keeps a container or a context:** every holder reads them per call. The model objects
  that outlive a main-actor step are:
  - the coordinator's active session and the live `SessionController`'s;
  - the replay's session across its network await, guarded by `Generation`.

## Decision

1. **A workout started in the demo is discarded when the demo ends, after a confirmation, on every OS.**
   - `TrainCoordinator.start` records the session's id in a list in `UserDefaults` when Train's binding is the
     demo's. The list holds ids only, and `TrainSyncService` owns it.
   - The demo's workouts are the sessions on that list that the store still has, in progress or finished. What the
     confirmation shows is computed from it, never stored.
   - Turning Demo data off with such workouts asks first. Cancel changes nothing, so the demo keeps running. Confirming
     ends the demo:
     - the replay stops before anything is deleted;
     - the live session closes and its Live Activity ends;
     - every session on the list is deleted with its ops.
   - **Nothing is sent, not even a `DELETE`:** the only other copy was on the demo's in-memory platform, which goes
     with it.
   - With no demo workout there's no dialog.
   - A launch with Demo data off and a non-empty list discards without asking. That only happens when the demo ended
     outside the switch (Debug launch arguments, `defaults write`).
   - An account's workout that wasn't started in the demo is never on the list, so it's never discarded.
2. **On iOS 17 (`#unavailable(iOS 18)`), the account's store is opened again in place before its first write after the
   demo.**
   - `TrainStore.reopen()` opens the same configuration again. Then:
     - it advances `StoreEpoch`;
     - it turns off autosave on the old container and keeps it for the process's life, never saved and never rolled
       back;
     - it makes the new container current.
   - Every holder gets the new container without a hand-over, because each reads `container` and `context` per call.
   - If the file doesn't open, the old container stays and the reopen reports false. It never falls back to memory.
   - In-memory stores aren't reopened.
3. **The exit is one synchronous main-actor step, from the discard to the reopen:**
   1. discard;
   2. switch off;
   3. reopen (iOS 17);
   4. `AppState.reset()`, which releases the demo's stores and drops the read contexts;
   5. Train refetches its open workout from the new container.

   The account's first write comes after this step. The drain is the only writer off the main actor, and the epoch
   orders it: a batch for the old container drops, and a save in progress finishes first. A cached writer is reused
   only for the same container, so a new container always means a new writer.
4. **The gate is injectable.** On iOS 17 the reopen fixes the OS fault, and the T0 gate proves that on 17.0. Elsewhere
   tests force it on, and it changes nothing visible. On iOS 18 and later the app never reopens: the discard is the
   only change there.

## Consequences

**Good:**
- On iOS 17, what the user logs right after the demo is saved without a relaunch. Two `withKnownIssue` wrappers go,
  and the app-path tests expect saves on every OS.
- No demo workout reaches an account's platform or its screens on any OS, and the user is asked first.
- One list with one owner names the demo's workouts. The binding rule (ADR 0008) is unchanged.
- No schema change, no new dependency, and no holder of the store changes.

**Costs:**
- `TrainStore.container` is mutable. Review check: no `ModelContainer` or `ModelContext` kept in a property outside
  `TrainStore` and the Repository's read contexts, which `invalidate()` drops. No model object held across an `await`
  without a `Generation` or epoch check.
- On iOS 17, each demo exit keeps one more container alive until the next launch: its row cache, never written.
- The epoch advance at the reopen drops answers in flight (Train's replay, activity and import uploads). They're sent
  again later, idempotently.
- One `UserDefaults` key of session ids.
- Review check: every session start goes through `TrainCoordinator.start(_:)`.

**What could go wrong:**
- **A reopened container still refuses inserts, or something traps** (T0.7 decides). The fallback is a note on iOS 17
  asking for a relaunch after the demo, with workout starts and new activities held until then. Raising the minimum to
  iOS 18 is the user's call.
- **The demo itself is broken on iOS 17.0.** The demo makes two containers (the Repository's and `ActivityStore`'s),
  and on iOS 17.0 the older of them would refuse inserts. T0.8 checks it. If so, one demo store owned by the environment is part of this
  work.
- **A model object from the old container is read later.** The old container is kept, so the read doesn't trap; it
  sees stale values and writes nowhere.

**Rejected alternatives:**
- **Telling the demo's workouts apart by their bindings** (ops or `uploadedTo` of "demo"). It misses a session less
  than 2 s old, and it wrongly takes an account's workout that continued during the demo, which would delete the
  account's data.
- **Putting the demo's Train in the demo's own store, as the read models and activities are.** It's the right end
  state, and it would also stop the demo's journal and Train library from overwriting the account's caches. It touches
  every Train type and the live session across the switch, so it's a follow-up, not this fix.
- **A new `TrainStore` instance at the exit.** Every holder keeps the store in a `let`, so each would have to be told,
  and any one missed would go on writing the old container.
- **One container with two configurations** (decision 11 of the persistence design): an entity belongs to one
  configuration, and both stores hold every entity.
