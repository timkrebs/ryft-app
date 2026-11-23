# 0025 — A consent `204` moves onboarding, never an upload

- Status: accepted (2026-11-22, ios-lead: `docs/work/2026-11-22-consent-agree-lag/plan.md` → "Lead decisions").
  Designed in `docs/work/2026-11-22-consent-agree-lag/design.md` (D1–D9, R1–R4).
- Deciders: ios-lead, on ios-architect's proposal. security-privacy-reviewer reviews it with the PR.
- Amends: ADR 0008.
  - Decision 5: the consent record also keeps this phone's agreement.
  - Decision 7: a `GET /v1/me/sync` asked within `statusCacheTime` of this phone's consent records nothing about consent.
- Applies to:
  - `Ryft/Environment/ConsentState.swift`: `Record.agreement`, `consented`, `heard`, `withdrew`, `standingAgreement`
    (an agreement dated after now is void), `pendingAgreement`, `unsettledAgreement`, `awaitsConfirmation`,
    `statusSpeaksForConsent`, `withdrawalUnresolvedSince` (a withdrawal without an answer).
  - `OnboardingCoordinator`: `Facts.agreedVersion` (the flow counts it; `gate` holds on it, code review S3),
    `Facts.withdrawing` (`withdrawalHolds`), `missing`, `gate`, `facts.serverGate`, `check`, `agree`, `withdrawConsent`,
    `confirmAgreement`, `awaitsConfirmation`.
  - `SyncCoordinator`: `LiveSyncSteps.syncStatus(userInitiated:)` and `scoringGate(of:)`; `AppState.syncStatusAskedAt`;
    `Repository.readUserBack(since:settles:)` / `store(fetchedUser:askedAt:settles:)`.
  - Devices & sync's idle state, Profile → Privacy, the training import's pause.
  - Every future reader of `GET /v1/me/sync` → `gate`.

## Context

- **Agree waited for the re-check.** The consent step moved on only after the follow-up check returned. That meant all
  three reads (`/v1/me`, `/v1/config`, `/v1/me/sync`), the user's commit inside its read (ADR 0018) and, sometimes, a
  time-zone `PATCH`. Two facts kept the step on screen until then: the stored user's consent, and the status's `gate`.
- **Two failures came with it:**
  - *A failed re-check stranded the user.* The `204` had landed, but the step stayed, with no message.
  - *A stale status refused again.* `GET /v1/me/sync` is cached 10 s per user, `gate` included (API.md;
    `syncstatus.go`). A status read soon after the consent still said `consent_required`. Under ADR 0008 decision 7 that
    was recorded as a refusal, and it kept both the step and the gate.
- **What the platform says** (API.md):
  - A `204` means the consent was recorded, for the version in force; an outdated one gets `422`. A repeat keeps the
    first `granted_at`.
  - `GET /v1/me` and the upload gates (`POST /v1/sync`, the import) read the account's user row on every request. Only
    `/v1/me/sync` is cached.
- **ADR 0008 and ADR 0018 as they stand:**
  - The upload gate decides from the stored user, which is written through, so the gate decides in the step that stores
    it.
  - A write the phone makes itself may only close the gate (the withdrawal).

## Decision

1. **The `204` records an agreement.**
   - It lives in `ConsentState`'s record, per account and persisted, and is wiped with the account.
   - It holds the version, when the `204` arrived on this phone, and whether it's settled.
   - Only three writers touch it:
     - `consented(to:at:)` records a new, unsettled one.
     - `heard(_:askedAt:)` settles it once a `GET /v1/me` asked for at or after that time is stored. From then on the
       stored user decides. A withdrawal's own re-read settles nothing (RYFT may record the `DELETE` after it), unless
       it shows no consent: settling then only closes (security review round 3, N-b).
     - `withdrew(at:)` removes it.
   - **One dated after now is void** (the clock was set back since; security review N-3, `standingAgreement`):
     - nothing waits for it: the flow, the gate and the status rule decide as if there were none, and the stored user
       decides;
     - a `GET /v1/me` heard meanwhile settles it, whenever it was asked for: the stored user decides then anyway;
     - otherwise it counts again once the clock passes it.
2. **The agreement moves onboarding.**
   - While it's unsettled, `missing` counts it as consent to the policy in force, for the consent step's "hasn't
     agreed" clause only.
   - A refusal (a `403`, `X-RYFT-Gate`, a withdrawal) still shows the step on its own.
   - The next step shows once the `204` is recorded. The re-read runs outside the step's request and never holds
     `isWorking`.
3. **The agreement never opens an upload.**
   - While it's unsettled, except while it's void (decision 1), `gate(_:path:write:)` holds every data path at the
     consent gate, whatever the stored user says (code review S3): a consent cached from before may be one the `204`
     didn't renew, such as one under a refusal it cleared. Erasures still go.
   - While a withdrawal is on its way, `gate` holds data too (`Facts.withdrawing`; security review round 2, S-1): an
     answer heard meanwhile may settle the agreement, and the withdrawal is the last word. Like every fact the phone
     keeps itself, it only closes.
   - So it does after a withdrawal sent with no answer (security review round 3, S-2): the `DELETE` may have landed.
     `ConsentState.withdrawalUnresolvedSince` is kept in defaults beside `withdrawnAt`, so a relaunch and a background
     launch hold too. It ends only on a `GET /v1/me` asked for after the attempt ended and stored (the withdrawal's own
     re-read, asked since then, or the next check), a withdrawal answered, a new agreement, or another account or none
     (a sign-out: `switchAccount`, and the account wipe for a launch that never ran it).
   - **It is written before the `DELETE` leaves** (since: the attempt's start), so an app killed while the request is out
     holds uploads at the next launch (security review round 4):
     - a `204` records the withdrawal (`withdrawnAt`) and removes it;
     - a refusal that left the consent as it was (`4xx`, `500`, `503`, offline) removes it, and an earlier one without an
       answer stays;
     - anything else, a `502` or `504` included (a gateway may answer after the `UPDATE` committed), moves it to when the
       attempt ended: today's no-answer behaviour.
   - **One dated after now is void** (the clock was set back): any stored `GET /v1/me` ends it, as it settles a void
     agreement (decision 1).
   - **The answer that ends it records the withdrawal first** when it doesn't show consent to the latest policy
     (`withdrawnAt`, as `withdrew(at:)` does): a user write the store refuses can't open the gate again after the hold
     is gone.
   - **Still shows the consent:** the answer ends the hold, the withdrawal isn't sent again, and Profile says so plainly
     ("didn't reach RYFT, syncing continues, try again"). Main behaves the same. Resending the idempotent `DELETE`
     while RYFT shows the consent is the follow-up below.
   - **A residual gap, accepted for this PR** (security and code review, rounds 5 and 6):
     - A `GET /v1/me` stored while the `DELETE` is out ends the marker written before it, though the `DELETE` may be
       recorded after that answer.
     - An app killed before the `DELETE` answers, after such a `/v1/me`, leaves no hold at the next launch.
     - The option-A follow-up closes it (below), and takes both cases as acceptance cases.
   - A data gate opens only when the platform's own user shows consent to the fresh policy: stored from a `GET /v1/me`
     asked for at or after the `204`, with no refusal counted.
   - Writes the phone makes itself still only close the gate.
   - The first sync (`startSync`) runs only after that read, and only if the gate is open then.
4. **The re-read and its failures.**
   - The re-read is one `GET /v1/me` asked for after the `204` (`Repository.readUserBack(since:)`). It doesn't wait for
     `/v1/config` or `/v1/me/sync`.
   - It is dropped like any step's answer when the account, Demo data or the turn changes (`Flight`).
   - If it fails, the user stays on the next step with no banner, and the gate stays closed.
   - While the agreement is unsettled, every `check()` asks `/v1/me` again. It is never answered from the last check,
     and coming back online asks too.
5. **Amends 0008 decision 7: a status can't refuse over this phone's newer word.**
   - A `GET /v1/me/sync` asked before the agreement's time plus `ScoringWord.statusCacheTime` (10 s, API.md's cache)
     says nothing about consent:
     - its `consent_required` is neither recorded nor observed, and isn't the coordinator's server gate;
     - its `null` resolves nothing for consent.
   - Its other fields count, the invite included.
   - This covers both a status held from before the `204` and one served from the cache after it. It is the same rule
     `ScoringWord.isAnswered(byStatusRequestedAt:)` applies to scoring.
   - Every reader of `gate` applies it: today `OnboardingCoordinator.check()` and `SyncCoordinator.syncStatus`.
   - All other sources of `consent_required` count as before, at once:
     - a `403`;
     - `X-RYFT-Gate`;
     - a status asked for later;
     - this phone's withdrawal;
     - a `422` on the POST (nothing advances then).
6. **Amends 0008 decision 5.** The record holds the last `/v1/config` answer (or a consent `204`), when it arrived, and
   this phone's agreement. A `204` still counts as a policy answer, so the policy is fresh. That doesn't make the
   agreement an open gate (decision 3).
7. **Honest states.**
   - What the user has to do comes from the coordinator's `pendingGate`, and an unsettled agreement doesn't count as a
     pending gate.
   - A sync held during an unsettled agreement says "Paused", never "Action needed": in Devices & sync as on Today.
   - A pause names its cause: RYFT's confirmation only while the agreement is unsettled and no withdrawal, on its way
     or without an answer, holds instead (round 3, N-a), the privacy policy while it isn't known, otherwise nothing
     (security review round 2, N1). Profile → Privacy says "Given": RYFT recorded the
     consent at the `204`, and only this iPhone's uploads wait (N2).

Not decided here: which session the POST uses. It is sent fail-fast, with "ask again" when no answer comes, as #134 does
for the withdrawal (design.md D6, `SettingsWrite`).

## Consequences

**Good:**
- **One round trip.** Agree reaches the next step after the POST alone. The re-read, the config, the status and the
  commit are off the screen's path.
- **ADR 0008's gate rule is unchanged** for every process. A background launch reads the same record, ignores the
  agreement, and holds until a `/v1/me` has been stored.
- **No bounce.** A cached status can't send the user back to the consent screen, and a failed re-check no longer
  strands them.
- **No second consent.** A relaunch offline before the re-read doesn't ask for consent again.

**Costs:**
- **One more rule.** The record gains a field, and consent has a second rule, the status window. It has to hold in
  every reader of `gate`; tests pin both readers (design.md T3b).
- **An unsettled agreement holds uploads** until a `/v1/me` answers. Offline for days, the sync stays paused.
- **A clock set back after agreeing** voids the agreement while it's dated after now (decision 1): the stored user
  decides, statuses speak for consent again, and a `GET /v1/me` heard meanwhile settles it. Set back by less than
  that, statuses stay silent on consent until the clock passes the window. The uploads' own refusals still count.
- **A refusal can be missed for up to 10 s.** Say the consent is withdrawn on another device within 10 s of agreeing
  here. If the re-read was asked before that withdrawal, the gate opens, and the next upload meets the platform's own
  `403` or `X-RYFT-Gate`. That is the exposure ADR 0008 already bounds: at most one page per withdrawal made elsewhere.

**Follow-ups:**
- **"A withdrawal RYFT hasn't heard is sent again" (option A, security review round 4).** Keep the hold while RYFT still
  shows the consent, and resend the `DELETE` on check, reconnect and launch. It ends on a `204`, a `/v1/me` without the
  consent, a new Agree or an account change. It changes decision 3 (an answer that shows the consent no longer ends the
  hold), so it needs an ios-architect note first; the privacy page should then say that uploads stop on the phone at once.
  Its acceptance cases include the residual gap of decision 3: a `/v1/me` stored while the `DELETE` is out, and an app
  killed before the `DELETE` answers, both still hold.
- **Platform request (D8).** `GET /v1/me/sync` → `gate` should never be served from the cache (`docs/API_REQUESTS.md`).
  Decision 5 then has nothing to do, but it stays.
- **`redeemInvite`'s re-check** should leave the step's request the same way (STATUS).

**Rejected alternatives:**
- **Write the consent into the stored user on the `204`**, as the withdrawal writes its removal. The gate would open on
  a fact the phone wrote itself, and the cached user would no longer be the platform's alone.
- **Open the gate on the agreement plus a fresh policy.** `consented` makes the policy fresh at the same moment, so
  this is the agreement alone. It costs nothing to wait: on the first run HealthKit isn't authorised until the Apple
  Health step, screens later.
- **Keep the agreement in the coordinator's memory.** `SyncCoordinator` needs its time for decision 5, and a relaunch
  would ask for consent again.
- **Wait only for `/v1/me`.** That is still a round trip and a commit on the screen's path, and a failed read would
  still strand the user.
- **Count on the platform clearing its cache on consent.** Each API instance has its own cache, and the app's rule has
  to hold before and after the platform changes.
