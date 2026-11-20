# Account-switch invariants (RYFT app) — learned 2026-11-19, PR 6 C review; updated after fix round 6c8

- ScreenModels is built ONCE in RyftApp (@State) and lives for the process. Every long-lived model must drop
  per-account state itself. Hooks: RyftApp `.onChange(of: auth.accountID)` (~RyftApp.swift:178), Demo switch goes
  through ProfileViewModel.setDemoMode/endDemo -> `state.reset()` (RyftApp's demoMode onChange does NOT reset).
  `AppState.forgetsAccountState(_:)` forgetters run from BOTH `reset()` and `forgetActivityState()` (wipe + accountWillChange).
  Registered (6c8): BodySettingsEditor, ProfileViewModel.forgetAccount, JournalStore(state:).accountChanged.
- Ownership token: `AccountBinding(env)` (account id + demo flag + auth.accountChanges; accountChanges is
  @ObservationIgnored, so an ObservationWatch on the binding fires on accountID/demoMode only). Correct pattern:
  capture binding AND `state.source`/`env.api` in the same main-actor step the write begins, check binding BEFORE
  sending and after answering. Demo off->on (ABA) leaves the binding equal; JournalStore adds a `generation` for that.
- APIClient binds a single request's retries (401 refresh, 429/503 waits) to the APIStatus epoch. A NEW request after
  the switch gets the new token: queues must check the binding before each send.
- `SettingsWrite.answer` (Features/Profile/SettingsWrite.swift, 6c8): one attempt (singleAttempt keeps 401 refresh),
  25 s deadline or offline -> NoAnswer and request.cancel(); no logging, no body in errors.
- Sign-out wipe: TrainStore.wipe batchDeletes ALL CachedDocument (journal.* included) on every wipe; failed wipe is
  retried via WipeLedger / lastUserKey (AuthService.apply runs it in AuthService init, before ScreenModels).
- CLOSED (re-check @ a819ff5, 2026-11-19): Journal docs + plan caches. `AppEnvironment.accountDocuments` = nil in Demo;
  JournalStore keeps demo's catalog/days/effects in memory, `restore()` re-reads the account's on its next load();
  BedtimePlanner (`sleep.tonight`) and SleepPlannerViewModel (`sleep.plan`) keep `demoCached` in memory. Flip + reset() is
  one main-actor step (setDemoMode/endDemo), reset() cancels all ReadScheduler flights first (ReadKey has no side, so
  cancelAll is what keeps sides apart), then forgetters. BedtimePlanner forgets via RyftApp onChange(demoMode) Task (async,
  untested wiring); SleepPlannerViewModel via forgetter in ScreenModels.
- OPEN S (pre-existing since #23, 24b137d): Bedtime & wake schedule `sleep.schedule.<accountID>` and planned nights
  `sleep.planned.<accountID>` (UserDefaults) use auth.accountID in Demo too: Demo edits the account's schedule (alarm off
  persists -> no real wake alarm), demo-planned bedtimes frozen into the account's records, account's planned bedtimes shown
  on demo nights. Drives local bedtime.* reminders, AlarmKit/wake.* alarms. No platform write yet (API_REQUESTS sleep
  schedule #1 would make it one). Fix: demo schedule/records in memory + Demo schedules no OS reminders/alarms.
- Hardening ideas noted: journal sheet has no side binding (unreachable today); journal.*/sleep.* docs carry no account tag
  (double-failed wipe -> restore() shows A's catalog to B, same as Repository).
