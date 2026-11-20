# Train reads and the account/side binding (RYFT app) — as of PR 6 @ 145c91a (2026-11-20, after R4)

- TrainLibrary.fetch(_:from:): `Client` = (source, outbox, outbox.binding) read in one main-actor step before the await;
  through `reads.run(ReadKey(.train, id:))` when `reads` is set (ScreenModels.swift:116), else straight to the source (tests).
  After the answer: `client.isCurrent` else `.declined`; cancellation -> `.cancelled`. Used by refresh (3 fetches, one
  client), loadPlan (+ the cached path's quiet Task), sessionRead, sessionsRead, historyRead.
- BYPASS ReadScheduler but binding-guarded: loadToday(from:) (refreshToday, reloadCatalog, sessionCompleted), reloadCatalog.
  Not cancelled by reset(); fine for privacy.
- `.declined` hands the NEW side's store copy to the OLD caller (VMs). Harmless for per-view VMs; matters for process-lived ones.
- TrainSyncService.Binding = Generation(accountCount, store epoch) + owner (demo owner or accountID). Demo switch does NOT bump
  accountCount; owner change covers it; ABA demo flip -> equal binding but same side (and reset() cancels flights).
- ReadScheduler flights coalesce by ReadKey (no side); `attempts(account:)` re-checks accountID; reset() on account change
  (AppState.accountChanged) and Demo switch (setDemoMode/endDemo) cancels all.
- Demo switch: RyftApp onChange(settings.demoMode) -> trainLibrary.demoModeChanged() (histories, catalog, today in memory;
  stored train.plans/train.today/train.sessions/train.history.*) then Task refresh(). Runs after the flip; old-side answers
  already declined by the owner change. Wiring untested (only the method is).
- LEFT (ADR 0019): exercise library (memory+store), plans' details (store.plans / plan(id:)), train.pausedPlanID (global
  UserDefaults), LocalSession rows (account's logged workouts show in Demo: History, Today Last/Done, My Day, Strain).
  docs/APP_STORE.md:67 says Demo "never mixed with an account's data | ok" — not true for Train.
- CLOSED @145c91a (R4T): TrainTodayViewModel.forget() is a forgetter (ScreenModels:127); loadStartOptions checks
  library.binding after each await; activePlan only while loadedPlan.id == activeEnrollment.planId. Demo residual: the
  account's LocalSession rows still feed Repeat last session / Last: / Done in Demo (ADR 0019, same person).
- CLOSED @145c91a (R4T): perform(client first, isCurrent before `then` and the error), deletePlan/enroll/setPaused via
  it; wipe()/demoModeChanged() clear error, errorDetails, plansDeclined. fetch: `guard client.isCurrent` BEFORE sending
  (code S1), keys `TrainLibrary.readKey` = "<owner>/<id>" (owner = account UUID or "demo"; memory only, signposts log the
  resource). Held-back Details = readDetails(reads.states[.train]) at read time; states reloaded per account by reset().
  pausedKey still global across Demo (ADR 0019): a Demo pause shows on the account and Resume POSTs the demo plan id (404).
- Tests: TrainReadsReviewTests (wipe/Demo with HeldTrainSource, reads == nil, unstructured Tasks, load() not
  userInitiated). Not covered: quiet loadPlan Task, reloadCatalog/loadToday/refreshToday, TrainTodayViewModel, RyftApp wiring.
- App Attest (#128): token on every api/ingest request via APIClient.exchange except 3 attest routes; exempt (held token, no
  renewal): DELETE /v1/me, POST /v1/me/apple-authorization, DELETE /v1/me/consent, POST /v1/feedback, DELETE devices push.
  Keychain AfterFirstUnlockThisDeviceOnly; AuthService wipe calls AppAttestor.live.wipe(). Entitlement
  devicecheck.appattest-environment = production; check-entitlements requires that value. Logs only step/DCError/status.
