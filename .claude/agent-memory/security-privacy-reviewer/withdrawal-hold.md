---
name: withdrawal-hold
description: Consent withdrawal (DELETE /v1/me/consent) lifecycle, the D6 hold on Demo data / Log out (F2), and its known gaps
type: project
---
Withdrawal path: ProfileView confirm dialog -> unstructured `Task { model.withdrawConsent() }` (tab switch doesn't cancel) ->
OnboardingCoordinator.withdrawConsent (~570): isWithdrawing=true before any await; `defer { if started == turn {false} }`;
perform(waitsForTurn:) waits (CheckedContinuation, not cancellation-aware) for a step's request; body = revokeConsent ->
answered(sent) -> consent.withdrew + storeConsentWithdrawn -> check(force:, changedSince:) (10 s cap). Returns `sent == flight`
=> true only when confirmed for the same binding. switchAccount (only if self.account != nil) bumps turn, clears isWithdrawing,
resumes waiters. Flight = AccountBinding (account id + demo flag + accountChanges) + turn; accountChanges bumps only on a
different user id (same-account auth callback doesn't end it).

Transport: live revokeConsent = APIClient default session (waitsForConnectivity=true, resource timeout 300 s, 503 x3 up to
30 s, 429 up to 60 s). No connectivity pre-check in withdrawConsent (check() has one at ~350). Offline => ~5 min busy.

F2 (fix/withdrawal-hold @ f93387e, 2026-11-21): hold is VIEW-ONLY (`.disabled(held)` on the Demo toggle and the Log out
pill; RyftToggleStyle = Button + accessibilityRepresentation, so taps and VoiceOver both blocked). Model setDemoMode/endDemo/
logOut/sendFirstThenLogOut have no guard. Gaps found: Send first (ProfileView ~60, ProfileViewModel ~193) logs out after a
10 s flush with no withdrawingConsent check, and re-presents the Log out dialog on .unsent; offline hold ~5 min; auth-driven
ends (expiry on the withdrawal's own 401, auth-callback link to another account) end it unsent silently, nothing persisted,
A's next sign-in shows Given and sync resumes; DEBUG API key mode / URL override not held. Announcement
"Consent withdrawn. Syncing has stopped." generic, only on true. `MockPlatformAPI.beforeRevokeConsent` compiled into Release
(MockPlatformAPI is the Release demoAPI), inert, like beforeConsent/beforeInvite (only beforePlan is #if DEBUG).
In-app "Sign in" taps (signInAgain) only after a refresh already ended the session: not bypasses.

Re-verify @ dc5d882 (2026-11-22): S-1 CLOSED (model guards logOut/setDemoMode/endDemo; sendFirstThenLogOut .held before
and after the wait, no await between the last check and logOut; view re-asks only on .unsent && !held). S-2 CLOSED
(revokeFailingFast: isOnline pre-check, then SettingsWrite.answer = singleAttempt fail-fast, 25 s on env.clock, offline
watch; NoAnswer -> transport(timedOut) -> "No connection…"); residual = the wait for a step's request is still on the
default session. N-1..N-4 CLOSED (beforeRevokeConsent #if DEBUG; ProfilePreview is inside #if DEBUG ProfileView ~695).
Hold now = isWithdrawing && state.user?.consent != nil (Repository.user(): writtenThroughUser or store), released by
storeConsentWithdrawn; onRecorded announces before the re-check. Re-check runs unheld: check() guards accountID only, a
Demo flip there = pre-F2 exposure (reset() cancels reads). Agree during the re-check shows busy (isWorking).
Timeout semantics: URLSession cancel doesn't undo a processed DELETE -> the platform may be withdrawn while the app shows
Given + "No connection…" (the safe direction). API.md: DELETE /v1/me/consent is 204 also when there was none (idempotent),
so trying again records it; 403 consent_required on upload / next /v1/me converge. The mock's checkCancellation after the
hold models "never arrived" only. S-3 is still open (follow-up).

Round 3 @ 467db54 (2026-11-22, PR #134): Unanswered path (OnboardingCoordinator ~582-603): SettingsWriteFailure.noAnswer
(not cancellation; includes non-API/non-URLError errors, 408, undecodable 2xx, transport other than sentNothing) ->
answered(sent) -> defer .consent -> check(force:, changedSince: sentAt) -> answered(sent) -> decides from the CACHED
repository.user() (nil user => Unanswered, conservative) -> consent nil => recorded as answered, no second re-check.
`deferred` never feeds the upload gate (gate() uses missing(f); deferred only sheetStep/Today line ~212-229).
Window: the re-read stores the fresh user inside the read, so the hold (consent != nil) can release before
consent.withdrew is written (tz PATCH / status awaits); a Log out/Demo flip there skips the local record + announcement,
but the platform and the cached user both have no consent. Unanswered's diagnosticDetails = nil (drops a 408/2xx request ID).
Log out: loggingOut flag set before await; withdrawConsent guards it; row .disabled(loggingOut). Verdict: all fine, nits only.
