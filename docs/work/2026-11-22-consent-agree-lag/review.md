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

### code-reviewer: mergeable after should-fixes 1–3 (and the test gap 4), no blockers
Every round-1 finding is fixed; no path uploads or starts a sync on the local agreement alone. The new problems come from S1's deadline: RYFT's late answer lands after the screen decided.

| # | Finding | Lead decision |
|---|---|---|
| 1 | **A late withdrawal answer opens the consent sheet over Profile.** On `Unanswered`, `deferred.remove(.consent)` also runs when the re-read only missed the 10 s; the read lands later with `consent: nil` and "Agree and continue" appears unasked right after the withdrawal (`OnboardingCoordinator.swift:749-757`). | **Fix:** un-defer only when RYFT answered and still shows the consent. Test: the `DELETE` lands, `/v1/me` held past the deadline, then released; `sheetStep == nil`. |
| 2 | **Agree's "try again" message outlives its cause.** After the late answer resolves it, About you (or Privacy under "Given") still says "RYFT didn't answer in time…". | **Fix:** the message belongs to the consent step; clear it when `.consent` leaves `missing`. Assert `errorMessage == nil` at the end of the S1 test. |
| 3 | **"Check with RYFT" is silent offline and on failure**, and inside a Retry-After window it sends nothing. (Disagrees with the developer's note.) | **Agree with the reviewer.** Offline the row is disabled and the footer says RYFT is asked again when the iPhone is back online. After a failed check, one line says so. The check's read is user-initiated. |
| 4 | N2's two call sites (`SyncCoordinator.swift:549`, `:604`) are untested: reverting either keeps the suite green. | **Fix:** a test through `SyncCoordinator` with a fake `scoringGate` returning nil for a `consent_required` status; the wait keeps the days. |
| 5 | A void (future-dated) agreement comes back and holds the gate until the next foreground check. | **Fix:** a `/v1/me` heard during the void settles it (the stored user decides then anyway, no extra exposure). |
| 6 | The paused words assume consent. | Same as security N1 and the localization-editor's note: words by cause. |
| 7 | Withdraw stays enabled while Check runs; a Check answer handled after the `DELETE` on the server can end #134's Demo / Log out hold early. | **Fix:** Withdraw disabled while `checkingConsent`. |
| 8 | ADR 0025 decision 3's first bullet and its clock-set-back bullet under Costs, and design.md §8, no longer match. | **Fix** together with security N3. |
| 9 | Onboarding's status reaches the scoring wait with its arrival time, not its asked time. | **Fix:** pass `statusAskedAt` through; it's available in `check()`. |

The post-merge run at 9514686: strict build 0 warnings, strings 0, lint OK. The test run failed at launch because the disk was full (the app couldn't start in the simulator), not on code; round 3 re-runs it.

## Round 3 (d1240d3..11ea2fc, strings 6c5174b)

The runs (ios-developer): Unit 4,948 passed, 0 failed; UISmoke 55; strict and Release builds 0 warnings; 20 mutants killed.

### localization-editor: 5 added, 3 dropped, 1 comment updated
Open, not this PR: "Given" has no comment, and it now also means "recorded, confirmation out". Add one with the next strings batch.

### security-privacy-reviewer: approve, one should-fix
Every round-2 item checked is fixed. No upload path runs while the `DELETE` is out, and da684d8 opens nothing early. The 75 public log interpolations are clean.

| # | Finding | Lead decision |
|---|---|---|
| S-2 | **An unanswered withdrawal releases held data before RYFT's state is known.** The `DELETE` commits but its `204` is lost, and the re-read misses its 10 s. `isWithdrawing` then goes false while the stored user still shows the consent, so the gate opens. `gateChanged` flushes Train's outbox, and `PUT /v1/sessions/…` isn't gated on the platform, so one flush is accepted after the withdrawal. Not a regression (main since #134), but it breaks this PR's own rule. | **Fix in this PR:** a close-only `withdrawalUnresolvedSince` kept in defaults beside `withdrawnAt`, fed into `Facts.withdrawing`. It ends on a stored `/v1/me` asked after the cancellation, a successful retry, a new Agree or an account change. The re-read asks `since:` the cancellation. Test with the code-1 shape: assert `uploadGate(for: .train) != nil` and that a Train flush sends nothing. |
| N-a | During a withdrawal of an unconfirmed consent, the pause words say "confirm your consent". | **Fix:** `agreementUnsettled: unsettled && !onboarding.isWithdrawing` (and while unresolved). |
| N-b | After an unanswered withdrawal of an unconfirmed consent, Privacy keeps "RYFT has recorded your consent" even after the late read shows none. | **Fix:** a read showing no consent settles (closing is always safe). |
| Outside | `PushRegistrar.swift:165` and `TrainCoordinator.swift:650` log `error.localizedDescription` publicly (the server's message for some statuses). | Follow-up, low: into STATUS. |

### code-reviewer: every decided item fixed, one small should-fix
All of S-1, code 1–9, N1–N3 hold. The developer's six notes are sound.

| # | Finding | Lead decision |
|---|---|---|
| S | "Check with RYFT"'s failure line has no Details, and its words are wrong when RYFT did answer (a fast 500, or a 429 over the cap) (`ProfileView.swift:454`, `ProfileViewModel.swift:366-373`). Hard rule 6. | **Fix:** `confirmAgreement()` returns the `.me` failure; pass it as `details:`; use `APIError`'s own sentence for 429 and 503. |
| 1 | A late no-consent answer leaves the agreement unsettled. | Same as security N-b: **fix**. |
| 2 | `PauseCause` names confirmation during a withdrawal. | Same as security N-a: **fix**. |
| 3 | Code 1's gap: when RYFT records the `DELETE` after the re-read, the re-read shows the consent, the sheet is un-deferred, and the next check opens it unasked. No test pins the un-defer. | **Fix:** never un-defer on the `Unanswered` path (Today's action and Privacy still offer the step). Test that `.consent` stays deferred. |
| 4 | The failure line shows while offline. | **Fix:** guard on `isOnline`. |
| 5 | Sync details reuses Plans' "Paused" key. | **Fix:** its own keyed string with its own comment. |
| 6 | The `ScreenModels.swift:81` wiring (`requestedAt`) is untested. | **Fix:** a wiring test. |
| 7 | ADR 0025 decision 3 needs "except while the agreement is void". | **Fix.** |

### ui-validator: pass, two nits
Shots: `scratchpad/uiv-consent/shots/` (not in the repo). "Given" is neutral grey, there's no teal outside recovery, the footers and Step 6's pause texts wrap at AX3, and the row order is sensible. Lead spot-check: Profile unconfirmed (default) and Step 6 policy pause (default) match their neighbours.

| # | Finding | Lead decision |
|---|---|---|
| 1 | The busy Check row is dimmed by `.disabled`, so its spinner is faint (Withdraw's busy row stays bright). | **Fix:** block taps while busy with `allowsHitTesting(!busy)`; keep `.disabled` for offline. |
| 2 | The Check row has no trailing glyph next to "Sync now"'s refresh. "Read the policy" wraps mid-link in the withdrawing footer. | **Fix:** the refresh glyph, and a no-break space inside the link text. |
| — | No VoiceOver hint says why Check is dimmed offline. | **Fix:** an accessibility hint. |
| — | No preview covers Check busy or failed, or Sync details' Workouts paused for consent (`MockDevicesStates` has `train.gate == nil`). | **Fix:** add the previews (CLAUDE.md: every state gets one). |
