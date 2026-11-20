---
name: project-settings-write-shared-wait
description: SettingsWrite (one attempt, 25 s, offline watch) shared by the editors, Notifications and Journal; account binding for page models and the journal; demo-is-online fallout; Release build and preview types
metadata:
  type: project
---

`Ryft/Features/Profile/SettingsWrite.swift` is the one wait for a settings write (6c8, PR 6 C review S3):
`SettingsWrite.answer(in: env) { … }` runs the send inside `APIClient.$singleAttempt.withValue(true)` (fail-fast session,
no 429/503 loop: 429 comes back at once, `.busy`), gives up after `SettingsWrite.deadline` (25 s, on `env.clock`, so a
TestClock drives it) or at once when `connectivity.isOnline` goes false (ObservationWatch; not in demo), throwing
`SettingsWrite.NoAnswer` (classified `.noAnswer`). `BodySettingsEditor.answerDeadline` is an alias. Journal maps its own
errors first (`JournalSettingsFailure.kind(of:)`: `JournalError.offline` → offline, `.idTaken` → refused) because the
shared classifier calls any unknown error `noAnswer`.

**Why:** the same lost connection read differently per page (300 s wait, 60 s 429 retry, 503 x3 outside the editors).

**How to apply:**
- A page model created in a view body (`NotificationSettingsViewModel(state:push:)` in `NotificationSettingsView.body`)
  must not register `state.forgetsAccountState` in init (it would append a closure per body evaluation). Capture
  `AccountBinding` + `env.api` at the tap, guard the binding before sending and after the answer, and cancel queued
  turns from an `ObservationWatch` on `AccountBinding(env)` that compares bindings (a token refresh also fires it).
- An app-lifetime store (JournalStore) registers once: `JournalStore(state:)` (ScreenModels) → `accountChanged()`;
  every read/write captures `Owner(binding, generation)` and drops a late answer, disk save included; a dropped write
  throws `CancellationError` (callers already treat it as "nothing to say").
- Demo counts as online everywhere now (Journal, BedtimePlanner too). Tests/previews that wanted "offline" on
  `AppState.preview(online: false)` (demo) must use an account graph: `AppState(env: .test(clock: TestClock(now: .now),
  online: false))` + `state.user = MockData.user`.
- Account-switch tests: `WipeHarness` (ReadModelWriteTests.swift) has a real wipe, hooks bound, `signIn(id)`, and with
  `demo: true` a switchable Demo (`env.settings.demoMode` + `state.reset()`). Hold mock writes with `RequestHold`
  (`beforePatchNotifications`, `beforeBehaviorWrite` (DEBUG), `beforePatchMe`).
- Release build: `#Preview` bodies compile in Release, so any DEBUG-only preview type (`MockDevicesStates`) must be
  wrapped in `#if DEBUG` with its previews. `AppEnvironment.test` and `TestClock` are not DEBUG-only.
- The body-setting Save pill keeps "Save" while busy (PillButton's spinner, VoiceOver value "In progress"); tests wait
  for `value == "In progress"`, not a "Saving…" label. Rows still say "Saving…".
- Demo data's small documents: `AppEnvironment.accountDocuments` is nil with Demo on. JournalStore and both planners
  keep demo data's cache in memory only (journal: its own properties; planners: `demoCached`), and read the account's
  documents again on the next load after a switch (`JournalStore.restore()`, never inside the forgetter: a sign-out's
  wipe may not have run yet). Demo previews seed via the DEBUG `seedForPreview` (`journalPreviewStore`, under
  `#if DEBUG` with its previews). BedtimePlanner hears the Demo switch from RyftApp's `onChange(of: settings.demoMode)`;
  Sleep → Bedtime's planner from a forgetter in ScreenModels. A fresh `Settings` in the simulator starts with
  `demoMode == true`: test graphs built by hand set it false.
- Proving a fix's test: copy the file, undo the fix, build non-strict (dead code warns), run, restore (a small
  python script with `.orig` copies). Stage mixed files by hunk with `git diff -U1` split on `@@`, then
  `git apply --cached --unidiff-zero`.
- Running suites: the shell is zsh, which doesn't word-split `$args`, so build the `-only-testing:` list in a bash
  script with an array. Pass `-parallel-testing-enabled NO` so no clone simulators boot. Count the gate's xcodebuilds
  with `pgrep -x` (`pgrep -f` also counts other agents' wait shells). Delete `build/` by its literal absolute path
  (`rm -rf "$VAR/build"` is refused by the safety check).
