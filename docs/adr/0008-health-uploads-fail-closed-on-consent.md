# 0008 — Uploads of health data fail closed on consent

- Status: proposed (2026-10-26, P2, `docs/work/2026-10-26-consent-gates/design.md`); amended the same day after the
  privacy review and the lead's decisions on demo, invite and deletes
- Deciders: ios-lead, on ios-architect's proposal; security-privacy-reviewer
- Applies to: `Ryft/Environment/ConsentState.swift`, `OnboardingCoordinator.uploadGate(for:write:)` /
  `gate(_:path:write:)`, `SyncService`, `SyncEngine`, `ActivityUploader`, `TrainSyncService` (and `PendingTrainOp`),
  the training import's upload, and every future uploader of health data

## Context

- **What the platform requires.** It processes health data only under a consent to the privacy policy in force
  (`GET /v1/config` → `privacy_policy_version`). It refuses `POST /v1/sync` otherwise (`403 consent_required`).
- **Where A2 left the app:**
  - HealthKit's gate counted a consent to any version until the process had fetched the config. Background processes
    never do.
  - The activity uploader failed closed, but trusted a cached version of any age.
  - Neither remembered a refusal across processes, so every background wake could send a refused page again.
  - Demo mode could reach the live sync through `syncNow` / `fullResync`.
  - Training logs went up with no gate, and Train's outbox picked its client per call, so an op could cross between
    demo and the account.

## Decision

1. **Health data includes training logs.** Body weight, effort and notes are health data (Art. 9), and so is their use
   for strain and recovery scoring. **Data writes** are every write that carries any of these:
   - HealthKit pages;
   - activity and night `PUT`s;
   - Train session `PUT`s and completions;
   - the training import.
   Reads are never gated. Neither are `TrainLibrary`'s writes (custom exercises, plans, enrolment).
2. **One gate.** It is a pure `gate(facts, path, write) -> UploadGate?`, asked by every upload:
   - before its first read or request;
   - before each page, item or op.
3. **Erasure isn't held by consent.** A `DELETE` goes out without a current consent, because erasure is in the user's
   interest (Art. 17).
   - Only demo, an unreadable record and an enforced invite gate hold it.
   - A `consent_required` answer to a `DELETE` is recorded as a refusal, and the delete stays queued.
4. **An op never crosses between demo and the account.**
   - Every queued write is bound to its account, with demo as its own account, and goes only through that binding's
     client: the mock for demo, the live API for the account.
   - With that binding, demo is open against the mock (activities, Train, the import).
   - HealthKit sync, whose client is always the live API, holds in demo, and `SyncService.run()` refuses in demo itself.
5. **One policy source.** It is `ConsentState`, persisted per account and wiped with the account in every wipe.
   - It holds the last `/v1/config` answer (or a consent `204`) and when it arrived on this phone.
   - The policy opens a data gate only while that answer is younger than `min(ttl_sec, 24 h)`, on the phone's clock.
   - A record that can't be read (before the first unlock) is never cached, and holds every write.
6. **Unknown means closed for data.**
   - A missing or stale policy never opens a data gate.
   - A known version that differs from the consent closes it for consent (the user's action).
   - Staleness can only hold.
7. **The platform's refusals persist** per account, until the platform no longer names the gate or the user passes it.
   - `consent_required` is recorded in any mode (a `403`, `X-RYFT-Gate`, `GET /v1/me/sync` → `gate`). The app fails
     closed on consent even where the platform would serve.
   - `invite_required` is recorded and holds only when enforced (a `403`). Warn mode is a product nudge, not a legal
     basis: it prompts and never holds.
   - A hold the app decides locally is never recorded as a refusal.
8. **Ask before holding.** A data write that finds the policy unknown while online asks `/v1/config` once before it
   holds. That read is:
   - joined with any read in flight;
   - after a failure, not repeated within 60 s.
9. **A hold is free and reversible.**
   - No HealthKit anchor advances and no queued row or op is dropped.
   - Completion handlers and task rescheduling run as usual.
   - A hold is silent in the background. In the foreground it shows only as the existing gate, offline or paused
     states.

## Consequences

**Good:**
- **Bounded exposure.** At most one page or item per phone reaches the platform under an outdated consent, per bump
  the phone hasn't seen and per withdrawal made elsewhere. Before this, every background wake could send one. R26 asks
  that such a body is never stored.
- **Erasure is never blocked by the app's own consent rule.**
- **Behaviour doesn't depend on the process.** A background process, an offline start and a long session all decide
  from the same persisted facts.
- **Testable.** Unit tests build the gate's state the way a background launch does: the same type over the same store.

**Costs:**
- **An extra request.** One `GET /v1/config` per age limit (6 h) per phone when nothing else fetched it.
- **Uploads depend on `/v1/config`.** Data writes stop if it fails for longer than the limit while the phone is online.
  The failure shows as a paused sync.
- **A refusal can outlast the reason.** One stored after a consent given on another phone holds this phone's data
  writes until it's next opened.
- **Refused deletes repeat.** A `DELETE` refused for consent is sent again, without a body, on each outbox trigger
  until the platform accepts deletes without consent (R25).
- **`PendingTrainOp` gains its account** (a lightweight SwiftData change). Ops queued before it count as the signed-in
  account's.
- **Platform asks.** R25 (consent on Train writes, deletes accepted without consent, and a check of training data
  received without consent) and R26.

**Follow-ups:**
- **A smaller first page in background runs.** Then a refusal costs a probe, not up to 20,000 records.

**Rejected alternatives:**
- **A pre-flight `GET /v1/me/sync` in every background process.** It costs a request per wake, to save one page per
  rare event.
- **Trusting any cached version.** A phone that was offline for days would open on a policy it saw before a bump.
- **`FlagStore` as the policy's owner.** Flag answers are deferred for UI stability, but the policy must apply at once.
  `FlagStore` is also bound to the account by a view, and the test graph doesn't use it.
- **Holding every path in demo.** Ops queued in demo would flush to the live account once demo is off.
- **Holding deletes behind consent.** It keeps data on the platform that the user wants gone.
- **Holding on a warn-mode invite gate.** It isn't a legal basis, and it would stop pre-beta accounts from syncing.
