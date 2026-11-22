---
name: consent-agree-lag
description: ADR 0025 agreement (consent 204 moves onboarding, never an upload), R2 10 s status rule, agree line/signposts; where to look and what was verified (2026-11-22)
type: project
---
Code (fix/consent-agree-lag @ 6d3bb2b): ConsentState.Record.agreement {version, at, settled}, keyed `consent.<account>`
(per account, CachedDocument, wiped with the account; a failed wipe can't leak A's to B). Writers: consented(to:at:settled:)
(also endWithdrawal + clears consent refusal), heard(_:askedAt:) settles when askedAt >= at (any answer), withdrew removes it.
OnboardingCoordinator: Facts.agreedVersion feeds missing() only; gate() copies facts with agreedVersion=nil (~:108-117).
Only readers of the agreement: ConsentState, OnboardingCoordinator, SyncCoordinator R2 (~:780). All 4 upload gates
(ScreenModels:71-78) -> uploadGate -> gate(). SyncService asks gate before any HealthKit read and before each page.
R2: statusSpeaksForConsent(askedAt) false when askedAt - at < 10 s (incl. before at), any agreement settled or not;
applied in check() (refuse/resolve, serverGate via syncStatusAskedAt from ReadScheduler.runAsked) and SyncCoordinator observe.
Uploads' 403 / X-RYFT-Gate (APIClient -> APIStatus.observe) are never filtered. Clock set back past the 204: isPolicyFresh
false (age<0) and received() drops older-dated config answers -> policyUnknown holds every upload anyway.
Repository.store(fetchedUser:askedAt:) has NO binding check itself; ReadScheduler.attempts + post-store accountID check +
cancelAll on wipe/reset protect it. readUserBack returns true even when the store dropped the answer.
agree(): perform = policy-TTL read, POST via failingFast (SettingsWrite.answer, isOnline pre-check), Unanswered -> readUserBack
(since sentAt) inside perform, answered(sent) before/after; consented in the same step; re-read outside perform; going==flight;
startSync only `if read, uploadGate == nil` (~:662) -- no isWithdrawing check.
Findings @6d3bb2b: S APIClient attempt signposts (:568, :581) .public redactedPath keeps day segments (/v1/days/<day>,
/v1/journal/<day>) on every round trip; N startSync during a withdrawal whose DELETE hasn't answered (T9 pins DELETE-first
order only); N ADR 0025 dec. 3 overstates (gate opens at 204 when cached user already has V and step showed for a refusal);
N wall-clock agreement can't settle if clock was ahead at the 204 (flow hides step, uploads held).
Agree line: AgreeTiming CachedDocument `onboarding.agree` single key with account+at inside (not in text), load checks
account/!demo, 14 d reportAge; Report a problem key `agree` only with includeDiagnostics; T11 regex pins no date/UUID/req ID.
