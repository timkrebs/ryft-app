---
name: consent-agree-lag
description: Why "Agree and continue" takes seconds before the next screen; where the wait is, what to measure on a device
metadata:
  type: project
---

Agree (OnboardingCoordinator.agree) = consent POST (default session) then `check(force: true)`; the step only
changes when the whole re-check (me + config + sync status, `withTaskGroup`) has returned, because `syncStatus`
(serverGate) is assigned only at the end of `check()`. So the screen waits for the slowest of three reads, config
included (not needed for the decision). Busy state is immediate (3 ms); title stays, only the 40 pt circle swaps to
a small spinner.

**Why:** server `GET /v1/me/sync` is cached 10 s per user in memory and `POST /v1/me/consent` does not invalidate
(plattform backend/cmd/api/syncstatus.go) -> a tap within 10 s of the last status read can re-read a stale
`consent_required` and the step stays (not reproduced, code-read).

**How to apply:** for a "consent is slow" report, first ask for Profile -> Sync details -> Copy diagnostics right
after one Agree (APIStatus keeps 20 requests with durationMs); durations sum << observed wait means a non-network
wait (App Attest `firstTokenWait` 3 s, ReadScheduler retry jitter, 503 default 5 s on the default-session POST).
Signposts: subsystem dev.timkrebs.ryft categories `reads` (budget/fetch/store) and `appattest` (renewal).
Probe technique that worked: MockPlatformAPI before* hooks with real Task.sleep + poll `flowStep`/`isWorking`
(TestClock keeps the 10 s check timeout from firing).
