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

## Round 2 (085a945..8a1f5c8, merge 93d4a4f, strings 9514686)

### localization-editor: five keys added as written
- **Open:** "It continues by itself once RYFT confirms your consent. Nothing to do here." also shows for the import's `policyUnknown` hold, where RYFT's privacy policy is awaited, not consent (Sync details says "Waiting for the privacy policy" for the same hold). **Lead decision:** a sixth key for the policy case, worded like Sync details' line, in the next fix round.
- **Open:** in `ImportResultView.swift` (about line 485), the "kept on this iPhone" (privacy S2) doc comment now sits above `gatedWaiting`, and `keptLimits` lost its doc. **Lead decision:** move it back in the same round.

### security-privacy-reviewer: approve after one should-fix, no blockers
No upload leaves before RYFT confirms the consent: `gate` holds all four data paths while an unsettled agreement stands. App Attest's `off` mode and renewal are as on main after the merge.

| # | Finding | Lead decision |
|---|---|---|
| S-1 | **The gate can open during a withdrawal.** N-1 guards only Agree's `startSync()`. A `/v1/me` answer (from Check with RYFT, a reconnect or Agree's re-read) that arrives while the `DELETE` is out settles the agreement; `gateChanged` then reruns the held sync, flushes activities and Train, and resumes the import, while Privacy says "Withdrawing your consent…". The withdrawal's own no-answer `askAgain` can do the same. T9b doesn't see it (the gate is open at `:776`). | **Fix:** a close-only `Facts.withdrawing` from `isWithdrawing`; `gate` holds `.data` while it is set; erasure unaffected (ADR 0008 allows a local fact that only closes). The withdrawal's own re-read doesn't settle a pending agreement. T9b asserts `uploadGate(for:)` is non-nil on all four paths while the `DELETE` is held, and that a flush sends no `putActivity`. The footer for the settled case changes with it. |
| N1 | The "waiting" copy names consent for holds that aren't about consent: `policyUnknown`, an account not known yet, a stale `beta_access`. | **Fix** (same as the localization-editor's note): the consent wording only while `unsettledAgreement != nil`; the policy wording for `.policyUnknown`, as `workoutsHeldText` does; neutral otherwise. |
| N2 | "Given, not confirmed yet" understates: the platform recorded the consent at the `204`; only this iPhone's uploads wait. | **Fix:** the value is "Given"; the footer says RYFT recorded the consent and this iPhone starts syncing once it hears back. The key "Given, not confirmed yet" goes. |
| N3 | ADR 0025 says `gate` decides as if there were no agreement; the code now holds (S3). The N-3 rule (an agreement dated after now is void) isn't in the ADR. | **Fix** in ADR 0025: decision 1 and "Applies to". |
| Outside | The journal's `PUT /v1/journal/{day}` and behaviour writes never ask the upload gate (ADR 0008 decision 1 leaves them out; the platform gates only `/v1/sync` and `/v1/train/import`). Habits like alcohol may be Art. 9 data. | **Follow-up, not this PR:** a scoping decision in ADR 0008 (ios-architect) with the platform. Into STATUS as open. |
| Outside | `APIClient.swift:624`, `:646` log `redactedPath` at `.public`, which keeps the day. | **Fix in this PR:** those two lines use `signpostRoute`. Small, and consistent with §6.5. |
