# Train reads and the account/side binding (RYFT app) — as of PR 6 @ a0bd5c2 (2026-11-20)

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
- OPEN S (found 2026-11-20, pre-existing since 4316f5b, widened by R1): ScreenModels.trainToday (TrainTodayViewModel) is
  process-lived, no forgetter; lastSession/activePlan survive sign-out/account switch/Demo; loadStartOptions only replaces
  activePlan when the new side has an enrolment AND the read returns a plan -> B's Start sheet shows/starts A's plan days
  and (briefly) "Repeat last session" of A.
- OPEN N: TrainLibrary.error/errorDetails not cleared by wipe()/demoModeChanged(); deletePlan/perform/setPaused write
  error + pausedKey after the await with no binding check.
- Tests: TrainReadsReviewTests (wipe/Demo with HeldTrainSource, reads == nil, unstructured Tasks, load() not
  userInitiated). Not covered: quiet loadPlan Task, reloadCatalog/loadToday/refreshToday, TrainTodayViewModel, RyftApp wiring.
- App Attest (#128): token on every api/ingest request via APIClient.exchange except 3 attest routes; exempt (held token, no
  renewal): DELETE /v1/me, POST /v1/me/apple-authorization, DELETE /v1/me/consent, POST /v1/feedback, DELETE devices push.
  Keychain AfterFirstUnlockThisDeviceOnly; AuthService wipe calls AppAttestor.live.wipe(). Entitlement
  devicecheck.appattest-environment = production; check-entitlements requires that value. Logs only step/DCError/status.
