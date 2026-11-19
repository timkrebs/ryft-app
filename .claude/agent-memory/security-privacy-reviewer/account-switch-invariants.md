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
- OPEN (pre-existing, confirmed 6c8): JournalStore uses env.persistence (the account's on-disk store) in Demo too,
  same keys journal.behaviors / journal.day.* / journal.impact. Demo switch is not a wipe. Account answers flash in
  Demo (loadDay copies disk before asking the mock; built-in ids are the platform's); demo's answers/impacts/custom
  habit persist into the account's cache and can be shown or Saved as the account's. Contradicts APP_STORE.md:67 and
  ARCHITECTURE.md:273 ("never mixed"). Repository uses its own in-memory demo store; Journal should too.
