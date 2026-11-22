# Consent agree lag — review log

## Round 1 (9f0d00d..6d3bb2b)

### security-privacy-reviewer: approve after one should-fix, no blockers
No path uploads or starts a HealthKit sync on the local agreement alone. No App Privacy or policy change.

| # | Finding | Lead decision |
|---|---|---|
| S-1 | APIClient attempt signposts (`APIClient.swift:568`, `:581-584`) log `redactedPath` at `.public`, which keeps day segments (`/v1/journal/2026-11-22`). That breaks §6.5's "no dates". | **Fix.** Signposts use a template route that turns day segments into `{day}`. `redactedPath` stays as it is for Sync details, which deliberately shows the day. Unit test. |
| N-1 | `startSync()` can run while a withdrawal's DELETE is unanswered, if `/v1/me` answers first (`OnboardingCoordinator.swift:662`). This is not a regression. | **Fix:** `if read, !isWithdrawing, uploadGate(...) == nil`. T9b covers the other order. |
| N-2 | ADR 0025 decision 3 promises more than the code: with a cached consent to V, a refusal cleared by the `204` opens the gate before the re-read, as before this change. | **Superseded by code review S3:** the gate holds while the agreement is unsettled, so the ADR stays as written. |
| N-3 | The agreement is ordered by the wall clock. With the clock ahead and a failed re-read, it can stay unsettled once the clock is corrected. Fail-closed, honest states only. | **Fix:** an agreement with `at > now` is void for the flow. Test. |

### code-reviewer: mergeable after S1 and S2, no blockers

| # | Finding | Lead decision |
|---|---|---|
| S1 | The "ask again" `readUserBack` has no deadline: three attempts on the fail-fast session take 63–78 s. #134's hold and Agree's busy pill can last over a minute, against the promise "lasts seconds" and "an answer within the deadline". | **Fix:** one `askAgain(since:)` that races the read against `checkTimeout`, as `fetchWithTimeout` does, used at both call sites. Test with `beforeMe` held. |
| S2 | While the agreement is unsettled, Profile → Privacy says "Not given" in the warning colour, and "Review and agree" opens nothing. Withdraw isn't offered. Sync details' held-workouts line and the import pause say "Action needed". This breaks hard rule 9 (honest states). | **Fix:** Privacy says the consent is given and RYFT hasn't confirmed it yet. Its action asks again; Withdraw is offered. The held-workouts line and the import pause go through `pendingGate`. New words go to the localization-editor. |
| S3 | With a cached consent to V, the `204` clears a kept refusal and the gate opens before any `/v1/me` asked after it. Same as security N-2. | **Fix: `gate` holds while `agreedVersion != nil`.** This is fail-closed, keeps ADR 0025 decision 3 true, and costs one round trip in a rare case. Test pins it. |
| S4 | Two untested paths: R3's negative branch (a `/v1/me` asked before T0 and stored after must not settle; its mutant would survive), and Devices & sync's Paused. | **Fix:** T3d, plus a `SyncIdleState.decide(pendingGate:)` / `SyncDetailsModel(onboarding:)` test. |
| N1 | With the clock set back after agreeing, `heard` never settles. | **Fixed by security N-3:** an agreement with `at > now` is void for the flow. |
| N2 | The scoring wait reads the raw `status.gate` (`SyncCoordinator.swift:543`, `:598`), so a cached `consent_required` ends it early. | **Fix:** the same R2 helper there. |
| N3 | The agree line's `dropped` is documented as "a withdrawal meanwhile"; a tz or birth-year `PATCH` also drops it. | **Fix the wording.** |
| N4 | STATUS isn't written yet. | Lead, at close. |
