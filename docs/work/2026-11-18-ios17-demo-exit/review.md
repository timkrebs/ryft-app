# P1b review (PR #121), 2026-11-18

Reviewers: code-reviewer and security-privacy-reviewer, both read-only, against head 5774c29.
**Verdict from both: nothing blocking.** No path discards an account's workout, and no path sends a demo workout after the
exit. The lead takes every should-fix and nit below into this PR, except the two marked *follow-up*.

| # | Source | Finding | Decision | Status |
|---|---|---|---|---|
| R1 | security S1, code N4 | Demo workouts logged before this build are never on `train.demoSessions`, so the exit skips them; an in-progress one uploads to the next account | One-time seed at the first launch of this build (`train.demoSessionsSeeded`): Demo data on and nobody signed in → list every stored session. Signed in → no seed; say so in STATUS and CHANGELOG | fixed `0402faa` (code, tests), `5620c14` (design §6.9, ADR, STATUS, CHANGELOG) |
| R2 | security S2 | Discarded workouts outlive the discard: the account's `train.sessions` document keeps the demo's list (`TrainLibrary` 172-185), and `MockTrainSource.shared` keeps them for the process | Remove the listed ids from the `train.sessions` document in the discard; add `MockTrainSource.reset()` next to the other resets. Tests for both | fixed `0402faa` |
| R3 | code S1 | The VoiceOver hint reads unobservable state (defaults plus a fetch per render), so it goes stale | Observable copy of the list on `TrainSyncService`, set in `setDemoSessionIDs`; the hint reads it, no fetch per render | fixed `0402faa` |
| R4 | code N1 | The row is saved before its id is listed; a crash in between leaves an unlisted demo session | Record the id before the insert (pass the id into the factory). A stale id is harmless, a missing one isn't | fixed `0402faa` |
| R5 | code N2 | Pruning on the in-memory fallback store erases the whole list | Remove only ids found and deleted, or skip pruning when the store isn't on its file | fixed `0402faa` |
| R6 | security N4 | The discard fails open on a read error (`try?` → `[]`) and a corrupted defaults value | Release `live`/`active`/`summary` against the stored id list, not the fetch; if the fetch throws, Demo data stays on | fixed `0402faa` |
| R7 | security N5 | The lock-screen readiness widget keeps the demo's score after the exit (predates the PR) | `publishWidget()` after `reset()` in `endDemo` | fixed `0402faa` |
| R8 | code N3 | No test for the launch condition; the UI test reaches Welcome even if the discard is skipped | Test the launch condition through a testable seam; in the existing UI test, relaunch with Demo data on (no Train reset) and assert `train.start` exists and `train.resume` doesn't. No new UI test method (UI smoke is near its 15-minute cap) | fixed `0402faa` |
| R9 | code S2, security N6 | Docs: the ADR 0018 amendment describes the dropped reopen; ADR 0019, ARCHITECTURE:293, STATUS:24/:1567 say 18.0; STATUS:27 says the strings aren't in the catalog | Reword or drop the 0018 amendment; 18.6 everywhere; STATUS:27 fixed | fixed `5620c14` |
| R10 | code N5, N6 | `DemoWorkouts.inProgress` is test-only; shared rigs live in one suite's file | Drop or use it; move `DemoTrainRig`, `RecordingTrainSource`, `RecordingLiveActivity` to `DemoExitHarness.swift` | fixed `0402faa` |
| R11 | re-review code S1 | A refused exit leaves the switch reading off and says nothing | Observable error on `ProfileViewModel`, shown under the switch with `InlineMessage` ("Demo data couldn't be turned off. Try again."); cleared by the next toggle that works | fixed `4b690a5` (code, test), `953af53` (string) |
| R12 | re-review code N2 | `demoWorkouts` is nil for "none" and for "couldn't read", so a read failure skips the dialog and still runs the exit | Tell the two apart; listed sessions plus a failed fetch → R11's error, no dialog, no `endDemo` | fixed `4b690a5` |
| R13 | re-review code N3, security N4 | The seed's flag is written without protected data; the seed needs Demo data on | Return before the flag without protected data or with the store off its file, on every branch. Seed on "nobody signed in" alone; with Demo data off the same launch's sweep discards them | fixed `4b690a5` (code, tests), `e28985f` (design §6.9, ADR, ARCHITECTURE, STATUS, CHANGELOG) |
| R14 | re-review security S1 | Exercise histories (`train.history.<exercise>`) keep the discarded workouts | Filter the listed ids from the documents and the in-memory copies, then `invalidateHistories()`. Plan day, catalog and plans stay in F2 | fixed `4b690a5` |
| R15 | re-review security N2 | `enqueuePut` and `finish` bind a listed workout's ops to the account with Demo data off | Ops for a listed id are only ever bound to "demo"; with Demo data off none is queued. Unlisted workouts unchanged (F1) | fixed `4b690a5` |
| R16 | re-review security N3 | The widget keeps the demo's sync status and bedtime after the exit | Clear `tonightBedtime` and `syncStatus` at the exit, as `forgetActivityState` does; publish after `demoModeChanged(false)` | fixed `4b690a5` |
| F1 | security S3, code "pre-existing" | An account workout that goes on during the demo gets the demo's scores, ops bound to "demo", and a lost complete | *Follow-up*: "bind ops to the session's owner" moves up in STATUS → Open, ahead of the External beta | follow-up; moved to the top of STATUS → Open, before the External beta (`5620c14`) |
| F2 | design Q3 | Cached documents the demo wrote | *Follow-up*, as decided (STATUS → Open, design §12) | follow-up |

**How each was fixed** (sync-engineer, 2026-11-18; tests on iOS 27.2):
- R1: `TrainCoordinator.demoAtLaunch` → `TrainSyncService.seedDemoSessions`. "Signed in" also counts an account
  `auth.lastUserID` still names (its Keychain may be unreadable at a background launch, or its wipe failed). The flag
  isn't set while the store can't be read or is memory in place of its file, so a later launch seeds.
- R2: `TrainLibrary.forgetSessions` in the discard; `MockTrainSource` is a locked class (like the other demo sources),
  so `reset()` in `AppState.reset()` is done when it returns.
- R3: `TrainSyncService.demoSessionIDs` is observable; `ProfileViewModel.showsDemoExitHint` reads it.
- R4: `TrainCoordinator.newSessionID()` lists the id; `SessionFactory` takes it. `start(_:)` is private.
- R5: both options: on its file the list is pruned as before (so a stale id from R4 goes); in memory in place of its
  file only the ids found and deleted go.
- R6: `discardDemoWorkouts() -> Bool`; `fetchDemoSessions()` throws; `endDemo` returns early on `false`. A corrupted
  defaults value isn't failed closed: a string that isn't a UUID names no session, and a value that isn't a list
  would leave the user unable to turn Demo data off, so it reads as empty (only this code writes the key).
- R7, R8, R10: as decided.

**Verified:** strict build (`RYFT_STRICT_WARNINGS=YES`), no warnings in our code; `make lint`, `make style`. On iOS 27.2:
the P1b suites and the touched Train, Profile, consent, import and session suites (425 tests in 34 suites) pass, and
`DemoExitUITests` passes (53 s). Six text mutants (R2 ×2, R3, R4, R7, R8) were each killed by the new tests.

**How each of R11–R16 was fixed** (sync-engineer, 2026-11-18; tests on iOS 27.2):
- R11: `ProfileViewModel.demoExitError`, set when `endDemo` refuses and by R12's refusal, cleared when `endDemo` runs or
  the demo is turned on. Profile shows it under the switch. The one new string went in by insertion only.
- R12: `TrainCoordinator.demoWorkouts()` throws when the list names sessions and the fetch fails (an empty list reads
  nothing, so it can't fail). Profile's setter asks `ProfileViewModel.switchingDemoOff()`: `.confirm`, `.exit` or
  `.refused`.
- R13: `seedDemoSessions(signedIn:protectedDataAvailable:)`; RyftApp passes `UIApplication.isProtectedDataAvailable`.
  The code comment states the dependency: no session and no `auth.lastUserID` means no account rows only while the
  defaults can be read.
- R14: `TrainLibrary.forgetSessions` is now an instance method on the coordinator's library, called after the discard.
  Besides sessions and records it drops the chart points on a discarded workout's days: a point has only its day, and
  without that the chart and "current" would still show the workout's e1RM (another workout that day comes back with
  the next fetch). `MockTrainScoring.records` now names each record's set and session, as API.md's do; before, the
  demo's records had none, so no filter by session could reach them.
- R15: `TrainSyncService.queues(_:for:)` guards `enqueuePut`, the `complete` in `finish`, and also the replay and the
  pending count, so an op for a listed id that was queued before ops had an owner (nil binding) isn't sent either.
- R16: as decided; the bedtime goes first, so each publish in between carries less.


**Verified (R11–R16):** strict build (`RYFT_STRICT_WARNINGS=YES`), no warnings in our code; `make lint` (no SwiftLint
warning on an added line), `make style`. On iOS 27.2: the P1b suites, the touched Train, Profile, consent, import and
session suites, `TrainDecodingTests` and `ReadinessSnapshotTests` (446 tests in 36 suites) pass, and `DemoExitUITests`
passes (52 s). Eight text mutants (R11, R12, R13 ×2, R14 ×2, R15, R16) were each killed by the new tests.
