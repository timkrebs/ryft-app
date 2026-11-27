---
name: project-pr6-r4o-flights-withdrawal-scan
description: PR 6 R4O (2026-11-20) — OnboardingCoordinator's per-account flights, the waiting consent withdrawal, App Attest's sentence on the steps, the app-wide Reduce Motion scan and its allowlist
metadata:
  type: project
---

R4O (branch feat/nocturne-pr6-fix-r4o from 20c70e7; worktree scratchpad/wt-r4o; scripts in scratchpad/r4o).

**OnboardingCoordinator.perform** now:
- captures `Flight` (AccountBinding + `turn`); every body calls `try self.answered(sent)` after each network await, so a
  late answer throws CancellationError and touches nothing of the next account. A stale flight sets no error and its
  `defer` frees `isWorking` only when `sent.turn == turn`.
- `switchAccount` bumps `turn`, resets `isWorking`/`isWithdrawing` and wakes waiters **only when leaving a known
  account** (`self.account != nil`): a step sent before the first check (tests call `redeemInvite` without `check()`;
  the body's own `check(force:)` then does nil→A) belongs to the launch account. Bumping on nil→A would make every
  such step return false (caught in review before a build, not by a run).
- `withdrawConsent` uses `perform(waitsForTurn: true)`: waits on `CheckedContinuation`s (resumed in perform's defer and
  in switchAccount) for the step in flight, then goes. Chosen over "skip the guard": an Agree answered after a
  concurrent DELETE calls `consent.consented` → `endWithdrawal()` and reopens the gate; the server could also take
  POST/DELETE in either order. A withdrawal waiting when the account changes ends unsent (false, no message).
  `isWithdrawing` (Profile's row busy) covers wait + send; Profile shows `consentErrorDetails` under Privacy.
- APIClient returns a 2xx even after the epoch changed (only retries/failures check the epoch), so the coordinator
  must check the account itself after a success.

**hasOwnWords** includes `.http(403, _, _, .appAttestRequired?, _)` (#128's sentence on invite/consent).

**ReduceMotionScanTests**: scans every `Ryft/**/*.swift` (prefiltered by substrings for speed; 5 MB of source);
forms: withAnimation, .animation(, .contentTransition(, withTransaction, .transaction, phase/keyframe animator
(modifier + view), .symbolEffect (needs `isActive: … && !reduceMotion`), `TimelineView(.animation` (needs
`paused: reduceMotion || …`; matched first so its `.animation(` isn't the modifier). Stricter: respecting() must be
given a value naming reduce motion; a local counts only if every same-name declaration in the file is respecting.
`guarded` allowlist = (file, call text, count, reason); unmatched/other count fails. 12 entries, no real hit.
The regex is a multi-line extended literal (swiftlint line length).

**Pitfalls:** InlineMessage's inline Details toggle has no identifier (only `onDetails` gets `<prefix>.details`):
find it by label "Details". `faults["revokeConsent"]` gives requestID "fault-revokeConsent".

**Mutation testing:** groups of mutants applied together (scratchpad/r4o/mut/mutate.py + run.sh) save builds, but
check each mutant's own failing assertion in the xcresult (`xcresulttool get test-results tests` → "Failure Message"
nodes), not just "the group failed". A mutant that makes a waiter never resume shows as the 1-minute time limit.

**R5 (2026-11-20, from 145c91a):** `switchAccount` also empties `inviteCode` when leaving a known account (N-1). A
signed-out invite link never sits in the field: `DeepLinkRouter` keeps it in `pending` (canNavigate = demo || signed
in) and RyftApp's `onChange(of: auth.accountID)` calls `switchAccount(new)` *before* `router.openPending()`. The only
"field set while `self.account == nil`" case is a link routed at launch before the first `check()` (session restored),
which is why the clear must stay inside `if self.account != nil` (mutant N1b caught only by that launch test).
Onboarding's error goes with the Demo switch via `state.forgetsAccountState { onboarding?.clearError() }` in
ScreenModels: every Demo change goes through `ProfileViewModel.setDemoMode`/`endDemo` → `AppState.reset()`, so a
test reaches it with `profile.setDemoMode(_:)` on a graph with `demoOverride: nil`, separate live/demo
MockPlatformAPIs, SystemClock and `reads.random = { $0.lowerBound }`, `budget maxStarts: .max`.
Demo switch vs. a waiting withdrawal (probed, not changed): nothing clears or wakes it; it ends unsent when the step's
request ends (binding changed), or still goes if Demo was switched off again meanwhile (binding equal again).
Known flake, seen again in R5: `AppAttestRequiredTests/fiveConcurrentRefusalsWaitForOneRenewal` (file
AppAttestRefusalTests.swift; `-only-testing` needs the suite name AppAttestRequiredTests). It checks `heldCount == 1`
right after `attestor.waiting == 5`, before the renewal's held challenge has reached the URLProtocol server; then
`releaseHeld()` frees nothing, the late challenge stays held and the test hits its 1-minute limit. Failed in a full Unit
run and alone (load5 ~150), passed in the next full run. Likely fix (not ours): `await rig.until { rig.server.heldCount == 1 }`.
Swift Testing in parallel xcodebuild runs prints no "Test run with N tests passed" line: take counts from
`xcresulttool get test-results summary` and quote `** TEST EXECUTE SUCCEEDED **`.
