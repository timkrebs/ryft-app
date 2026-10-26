# 0008 — Uploads of health data fail closed on consent

- Status: proposed (2026-10-26, P2, `docs/work/2026-10-26-consent-gates/design.md`)
- Deciders: ios-lead, on ios-architect's proposal; security-privacy-reviewer
- Applies to: `Ryft/Environment/ConsentState.swift`, `OnboardingCoordinator.uploadGate` / `gate(_:)`, `SyncService`,
  `SyncEngine`, `ActivityUploader`, and every future uploader of health data

## Context

- **What the platform requires.** It processes health data only under a consent to the privacy policy in force
  (`GET /v1/config` → `privacy_policy_version`). It refuses `POST /v1/sync` otherwise (`403 consent_required`).
- **Where A2 left the app:**
  - HealthKit's gate counted a consent to any version until the process had fetched the config. Background processes
    never do.
  - The activity uploader failed closed, but trusted a cached version of any age.
  - Neither remembered a refusal across processes, so every background wake could send a refused page again.

## Decision

1. **One gate.** Every upload of health data asks the same gate, a pure `gate(facts) -> UploadGate?`:
   - before its first read or request;
   - before each page or item.
2. **One policy source.** It is `ConsentState`, persisted per account and wiped with the account in every wipe.
   - It holds the last `/v1/config` answer (or a consent `204`) and when it arrived on this phone.
   - The policy opens a gate only while that answer is fresh: younger than its `ttl_sec`, on the phone's clock.
3. **Unknown means closed.**
   - A missing or stale policy never opens a gate.
   - A known version that differs from the consent closes it for consent (the user's action).
   - Staleness can only hold.
4. **The platform's refusals persist.** A `consent_required` from the platform (a `403`, `X-RYFT-Gate`, or
   `GET /v1/me/sync` → `gate`) is stored for the account. It stays until the platform no longer names the gate or the
   user agrees.
   - A hold the app decides locally is never recorded as a refusal.
5. **Ask before holding.** An upload that finds the policy unknown while online asks `/v1/config` once before it holds.
   That read is:
   - joined with any read in flight;
   - after a failure, not repeated within 60 s.
6. **A hold is free and reversible.**
   - No HealthKit anchor advances and no queued row is dropped.
   - Completion handlers and task rescheduling run as usual.
   - A hold is silent in the background. In the foreground it shows only as the existing gate, offline or paused
     states.

## Consequences

**Good:**
- **Bounded exposure.** At most one page or item per phone reaches the platform under an outdated consent, per bump
  the phone hasn't seen and per withdrawal made elsewhere. Before this, every background wake could send one.
- **Behaviour doesn't depend on the process.** A background process, an offline start and a long session all decide
  from the same persisted facts.
- **Testable.** Unit tests build the gate's state the way a background launch does: the same type over the same store.

**Costs:**
- **An extra request.** One `GET /v1/config` per ttl (6 h) per phone when nothing else fetched it.
- **Uploads depend on `/v1/config`.** They stop if it fails for longer than a ttl while the phone is online. The failure
  shows as a paused sync.
- **A refusal can outlast the reason.** One stored after a consent given on another phone holds this phone's uploads
  until it's next opened.

**Open:**
- **Train's outbox and the training import don't ask this gate.** Whether training logs (sets, loads, body weight)
  count as health data under this rule is for the security and privacy review. Once they do, they ask `gate(_:)` like
  the rest.
- **`invite_required` isn't persisted.** It could be, with the same mechanism, if an enforced invite gate ever applies
  to accounts that have consented.

**Rejected alternatives:**
- **A pre-flight `GET /v1/me/sync` in every background process.** It costs a request per wake, to save one page per
  rare event.
- **Trusting any cached version.** A phone that was offline for days would open on a policy it saw before a bump.
- **`FlagStore` as the policy's owner.** Flag answers are deferred for UI stability, but the policy must apply at once.
  `FlagStore` is also bound to the account by a view, and the test graph doesn't use it.
