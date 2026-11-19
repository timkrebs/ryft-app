# 0022 — A refused upload is kept as state, never dropped; Train's outbox carries custom exercises

- Status: accepted (2026-11-19, O1 + O2, `docs/work/2026-11-19-offline-first/plan.md` gap 1)
- Deciders: ios-lead, on ios-architect's proposal and the code review of O1 + O2
- Applies to: `TrainSyncService`, `PendingTrainOp`, `LocalSession`, `TrainLibrary.createExercise` and `savePlan`,
  `UploadState` / `UploadAttempt`, `ActivityUploader`, and every later outbox (`WriteOutbox`, O6)

## Context

- Before O2, Train's outbox dequeued any op the platform refused (a 4xx that isn't a gate). The local copy stayed,
  and Train said "Will sync", so the workout never reached the platform while the user was told it would.
- The usual cause was a custom exercise made offline. `TrainLibrary` tried `POST /v1/exercises` once. The session's
  `PUT` then answered `422` (`exercise_id` must be built-in or the user's), and its `complete` answered `404`.
- `ActivityUploader` already kept a refusal as a row state with Retry. Train had its own rule, and O6 and O10 need
  one rule.

## Decision

1. **A refusal is state.** A request that can't succeed as it is keeps the op. `UploadAttempt.isRefusal` is the only
   definition, for both outboxes (Train's and `ActivityUploader`):
   - **Refusals** (API.md → Errors: "do not resend unchanged"):
     - `400`, `409`, `413`, `422` on any request (a `PUT`'s `409` only after the merge rounds);
     - `404` on a `complete` (the platform has no such session);
     - every other `4xx` but the holds below (`405`, `410`, `431` …): API.md → Errors, the paragraph under the table
       (`API.md:121`), "any other `4xx` (`405`, `431`, from the HTTP server before a handler runs) is like `400`";
     - a request this build couldn't make: an error that is neither an answer nor a transport failure (an
       `EncodingError` from a weight that isn't finite), thrown before anything is sent. Sent again unchanged, it
       fails the same way. It doesn't hold the queue.
   - **Holds** (never refusals: the queue stays as it is, and the next trigger sends it; `ActivityUploader` holds with
     its backoff):
     - no answer (offline, a timeout), and `408`, `429`, every `5xx` but `501`: transient (`API.md:121`, `:117`,
       `:119`);
     - `501`: the route isn't there yet (`API.md:121`: endpoint-specific, not transient). Nothing is wrong with the
       document;
     - `401` after the client's refresh: a sign-out; no server configured: nothing went out;
     - every `403`, with or without a `code`. The codes are gates (ADR 0008 §7). A `403` without a code means a
       built-in target (`API.md:112`), which a session or an activity can't be, so it's a gate this build doesn't know
       or a proxy. A hold is free and reversible (ADR 0008 §9); dropping the edit, as `API.md:112` says for a
       built-in, would lose a workout;
     - a `404` on a `PUT`, `DELETE` or `POST`: an unknown route, so the app is newer than the server (`API.md:113`);
     - `426`: a deliberate exception to `API.md:121`. The contract lists no `426`; API_REQUESTS §3 proposes it for
       "this app is too old" (`FailureKind.appTooOld`, reserved). A newer build sends the same document, so it isn't
       refused;
     - cancellations.
   - **Delivered:** a `2xx` whose body this build can't read. The platform took the request: Train's op goes, and
     `ActivityUploader` confirms the row (the document sent stands in for the platform's copy until the next read). No
     attempt is kept.
   - The attempt is recorded: status, code, request ID and time (from the injected `AppClock`), never a body or a
     message.
   - The subject's ops are passed over until Retry or a newer edit of it; other subjects' ops go.
   - A `complete` answered `404` for a session the platform never got (`uploaded` is false: an earlier build dropped
     its `PUT`) is no refusal either: the session's `PUT` is queued ahead of it and goes first. Once the platform has
     the session, a `404` on `complete` is a refusal.
2. **The attempt lives on the row the user sees** (`LocalActivity`, the manual night, `LocalSession`). Where the
   subject is a cache the platform owns (`CachedExercise`), or has no row (`PendingWrite`), it lives on the op.
3. **One state model.** `UploadState` and `UploadAttempt` are shared by every outbox. Each owner derives
   `state(of:)` from its rows and its in-memory flight and backoff; it is never stored.
4. **A stale refusal isn't kept.** A refusal of a document edited while the request was out answered an older
   document: nothing is recorded, and the newer document goes at once, as the same op, still ahead of the subject's
   later ops. Train counts a session's edits in memory (`enqueuePut`); `ActivityUploader` compares revisions.
5. **A refused `PUT` of a session the platform already has** (`uploaded`) doesn't hold its `complete`. The platform's
   copy is completed and scored; the refused `PUT` stays for Retry or an edit, and a later `PUT` replaces the session
   whole.
   - The completion's answer is the platform's copy as its last `PUT` left it. While a `PUT` of the session is refused
     (its attempt's request) or queued (an edit while `complete` was out), that copy is older than this one, so the
     answer brings only what the platform owns: the status, `workout_id`, `prs`, `strain`, `muscular_trimp`,
     `volume_kg` and `bodyweight_kg` (`LocalSession.applyPlatformFields`). Every logged field and row stays as it is:
     title, notes, times, exercises, and each set's reps, weight and check-off time. The next `PUT` sends them.
   - Otherwise the answer is applied whole, as before (`LocalSession.apply`, which never removes a row).
6. **Exceptions, by contract:**
   - Train's `DELETE`: a refusal is dropped and logged with status and request ID. The session is gone here, so
     nothing could show it or send it again. A `404` is success; a `403` holds and stays queued (ADR 0008 §3).
   - A `complete` answered `409`: the platform discarded the session (API.md: "treat it as discarded"). The op goes
     and `pendingCompletion` is cleared; it isn't a refusal.
7. **A custom exercise is an outbox op** (`PendingTrainOp.Kind.exercise`), queued ahead of every op, because a queued
   `PUT` sends the session as it is when it goes.
   - It sends the cached row by id (a resend updates it), and the answer replaces the row.
   - It isn't a data write (ADR 0008 §1), so neither the consent gate nor an undo hold stops it, but it is bound to
     its account (ADR 0008 §4). One op per exercise and binding.
   - A session's ops never go while an exercise it uses is queued or refused for the binding in use; such a session
     shows the exercise's attempt.
   - A plan save waits for the exercise ops it names, at most 10 s on the injected clock (`TrainLibrary.exerciseWait`).
     Offline, or after the wait, the plan goes as before. Whatever ends the wait (the ops, the replay's end, the cap, or
     the caller's cancellation), its waiter and its cap go with it. The client and the binding (generation and owner)
     are read before the wait: if either changed meanwhile, or the caller was cancelled, the save is dropped, and an
     answer is cached only for the binding that sent it.
   - A custom exercise the platform answers without taking it (a `5xx`, a `403`, a `404`, not a `429`) is passed over
     for that pass: the sessions that use it wait, other ops go. No answer stops the queue, as for every op.
   - Retry clears the refusals of the session and of the exercises it uses. It re-queues a `POST` for every custom
     exercise the session uses that has no op for the current binding, then the session's `PUT` and, while it's still
     to be completed, its `complete` with the body weight given at Finish. Finish stores that weight on the session
     too (`bodyweightKg`, already an optional attribute), so it's there when the `complete` op is in flight or gone.
   - `TrainLibrary.createExercise` drops NUL from the names (API.md → Text, `API.md:62`), then doesn't queue a name the
     platform refuses (empty, or more than 80 Unicode scalars): it returns nil and says why.
8. **The store grows compatibly.** Outbox fields are optional attributes (lightweight migration). A stored kind this
   build doesn't know is kept and passed over, never read as another kind, and not counted. Installing an older build
   is best-effort: the rows survive (`TrainOutboxSchemaUpgradeTests/anOlderBuildOpensTheStoreThisOneWrote`), but
   newer state is lost. The refusals have no attribute there, and #107 reads an `exercise` op as a `PUT` of no session
   and drops it. The heal pass (O1b) re-queues what an older build dropped.

## Consequences

- Nothing logged is dropped for a refusal. O2's UI shows it with its request ID, and Retry or an edit sends it again.
- Until O2's UI, a refused workout still reads "Will sync", but it is kept (STATUS, known issue).
- A refused subject's ops stay until Retry, an edit, a discard or the wipe. The wipe, or parking (O10), takes the
  attempts with the rows.
- Retrying a refusal the platform will repeat (`413`, `422`) fails the same way; the screen says why.
- `PendingTrainOp.sessionId` now means the op's subject (a session or an exercise). The name is kept, so the store
  needs no migration.
- A hold has no backoff in Train's outbox yet: the queue goes again at the next trigger (reconnect, app active, an
  edit). O3 adds per-op backoff and keeps decision 7's dependency.
- O10 parks the `CachedExercise` rows that parked exercise ops name. O6's `PendingWrite` derives "refused" from its
  attempt instead of storing a flag.
- O6's ADR becomes 0024 and O13a's 0025 (plan.md updated; 0023 is the App Attest client's).
