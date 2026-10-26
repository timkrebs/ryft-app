# 0008 — Uploads of health data fail closed on consent

- Status: proposed (2026-10-26, P2, `docs/work/2026-10-26-consent-gates/design.md`); amended the same day after the
  privacy review
- Deciders: ios-lead, on ios-architect's proposal; security-privacy-reviewer
- Applies to: `Ryft/Environment/ConsentState.swift`, `OnboardingCoordinator.uploadGate(for:)` / `gate(_:path:)`,
  `SyncService`, `SyncEngine`, `ActivityUploader`, `TrainSyncService`, the training import's upload, and every future
  uploader of health data

## Context

- **What the platform requires.** It processes health data only under a consent to the privacy policy in force
  (`GET /v1/config` → `privacy_policy_version`). It refuses `POST /v1/sync` otherwise (`403 consent_required`).
- **Where A2 left the app:**
  - HealthKit's gate counted a consent to any version until the process had fetched the config. Background processes
    never do.
  - The activity uploader failed closed, but trusted a cached version of any age.
  - Neither remembered a refusal across processes, so every background wake could send a refused page again.
  - Demo mode could reach the live sync through `syncNow` / `fullResync`.
  - Training logs went up with no gate.

## Decision

1. **Health data includes training logs.** Body weight, effort and notes are health data (Art. 9), and so is their use
   for strain and recovery scoring. Every write of any of these asks the gate:
   - HealthKit pages;
   - activities and manual nights;
   - Train's outbox (sessions, completions, deletes);
   - the training import.
   Reads are never gated.
2. **One gate.** It is a pure `gate(facts, path) -> UploadGate?`, asked by every such upload:
   - before its first read or request;
   - before each page, item or op.
3. **Demo opens only a path whose client is the mock and whose every request is bound to the demo flag.** Today that's
   the activity uploader.
   - HealthKit sync (always the live client) holds in demo, and `SyncService.run()` refuses in demo itself.
   - Train's outbox and the import hold too.
4. **One policy source.** It is `ConsentState`, persisted per account and wiped with the account in every wipe.
   - It holds the last `/v1/config` answer (or a consent `204`) and when it arrived on this phone.
   - The policy opens a gate only while that answer is younger than `min(ttl_sec, 24 h)`, on the phone's clock.
   - A record that can't be read (before the first unlock) is never cached, and holds every path.
5. **Unknown means closed.**
   - A missing or stale policy never opens a gate.
   - A known version that differs from the consent closes it for consent (the user's action).
   - Staleness can only hold.
6. **The platform's gates persist.** A `consent_required` or `invite_required` from the platform (a `403`,
   `X-RYFT-Gate`, or `GET /v1/me/sync` → `gate`) is stored for the account. It stays until the platform no longer names
   that gate or the user passes it.
   - Warn-mode gates count as refusals, on purpose: the app fails closed where the platform would serve.
   - A hold the app decides locally is never recorded as a refusal.
7. **Ask before holding.** An upload that finds the policy unknown while online asks `/v1/config` once before it holds.
   That read is:
   - joined with any read in flight;
   - after a failure, not repeated within 60 s.
8. **A hold is free and reversible.**
   - No HealthKit anchor advances and no queued row or op is dropped.
   - Completion handlers and task rescheduling run as usual.
   - A hold is silent in the background. In the foreground it shows only as the existing gate, offline or paused
     states.

## Consequences

**Good:**
- **Bounded exposure.** At most one page or item per phone reaches the platform under an outdated consent, per bump
  the phone hasn't seen and per withdrawal made elsewhere. Before this, every background wake could send one. R26 asks
  that such a body is never stored.
- **Behaviour doesn't depend on the process.** A background process, an offline start and a long session all decide
  from the same persisted facts.
- **Testable.** Unit tests build the gate's state the way a background launch does: the same type over the same store.

**Costs:**
- **An extra request.** One `GET /v1/config` per age limit (6 h) per phone when nothing else fetched it.
- **Uploads depend on `/v1/config`.** They stop if it fails for longer than the limit while the phone is online. The
  failure shows as a paused sync.
- **A refusal can outlast the reason.** One stored after a consent given on another phone holds this phone's uploads
  until it's next opened.
- **Warn mode now holds uploads.** Accounts without an invite code stop syncing until they redeem one.
- **Demo's Train flow waits.** A session finished in demo waits in the outbox until demo is off.
- **Platform asks.** R25 (consent on Train writes, and a check of training data received without consent) and R26.

**Follow-ups:**
- **A smaller first page in background runs.** Then a refusal costs a probe, not up to 20,000 records.
- **Deletes.** Whether a delete (activity, night, session) should bypass the policy rule, since it carries no health
  data and holding it keeps data the user wants gone. Kept held for now (R25).
- **`TrainLibrary`'s direct writes** (custom exercises, plans, enrolment) stay ungated as not health data, unless
  privacy decides otherwise.

**Rejected alternatives:**
- **A pre-flight `GET /v1/me/sync` in every background process.** It costs a request per wake, to save one page per
  rare event.
- **Trusting any cached version.** A phone that was offline for days would open on a policy it saw before a bump.
- **`FlagStore` as the policy's owner.** Flag answers are deferred for UI stability, but the policy must apply at once.
  `FlagStore` is also bound to the account by a view, and the test graph doesn't use it.
