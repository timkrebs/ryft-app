# Data quality: T2 review log

## T2 · `today: pending on every refresh path` (#88)

Round 1 on 82dbabf.
- **code-reviewer:** no blocking findings, 4 should-fix. It probed findings 1 and 2 with failing tests.
- **ios-architect:** fits §D3b, with one blocking finding. It recommends ADR 0013.
- **performance-profiler:** no blocking findings, 2 should-fix.

| # | Finding | From | Decision |
| --- | --- | --- | --- |
| F1 | A wait ends on a status asked less than 10 s after the write, which the ledger ignores. With `expected_within_sec` < 10 (realistic: a p95 with a 1 s minimum), a calibrating day stays on "Scoring your night…" (reproduced with expected = 3). | architect B1, code 1 | **Must fix.** A wait never ends on, and never sends its first read before, `ScoringWord.statusCacheTime` after the write. Path test with `expectedWithinSec: 3`. |
| F2 | A push's `.scored` word replaces `waiting_for_sleep` on a day without a night (reproduced). | code 2 | **Must fix.** `.scored` rules out `pending` only. Test. |
| F3 | Opening the app within 10 s of a background upload: G2 reads a cached "nothing pending" and no wait answers the word. | architect S1 | **Fix.** G2's day list includes the ledger's unanswered pending days. |
| F4 | Two copies of the ledger: a demo switch clears the Repository copy only, and an account change clears SyncService only. | architect S2, code nit | **Fix with one store.** Repository reads the ledger through a closure (like `chosenTrackers`), and SyncService calls a hook that republishes the widget. The owner is cleared on the demo switch too. Test both. |
| F5 | An upload that fails or is cancelled after accepted pages records no `awaiting`. | architect S3 | **Fix in this PR.** The coordinator records the days touched so far on error and on cancel. T4 depends on this. |
| F6 | No test proves `LiveSyncSteps` passes the flight start (the mutant survived all 18 tests). | code 3 | **Fix.** Drive the real step. |
| F7 | G2 can hold the pipeline for up to 300 s with about 6 polls, re-waits for days a previous wait gave up on, and delays the refresh behind the wait. | perf 1–2, code 4 | **Fix.** Refresh what's stale first. Then wait only for days not already waited out. Skip G2's read when the last status read is under 10 s old. Add a poll count to the `score-wait` signpost end. |
| N1 | No cancellation check before `awaiting`, so a sign-out can race it. | architect | Fix. |
| N2 | `writtenSinceStart` is close to derivable. | architect | Add a comment or derive it. |
| N3 | The G2 wait uses `lastScoring`'s expected time, not the status just read. | architect | Fix. |
| N4 | The ledger isn't in the diagnostics line (days and kinds only). | architect | Fix. |
| N5 | The "none behind a gate" comment ignores the local hold. | code | Fix the comment, or check `pausedFor`. |
| N6 | `eventually { inFlight.contains }` is always true, with a 20 ms wall-clock sleep. | code | Fix the synchronisation. |
| N7 | `offline.readsScoringStatus = true` is redundant. | code | Remove. |
| N8 | Ledger times are wall-clock `Date`. | code | Leave as is. In memory only; noted. |
| — | `SyncMachine` has no idle → `awaitingScores` edge. | PR follow-up | Separate PR (sync-engineer, `StateMachines/`). |
| — | A background `awaiting` is answered only by a push or by opening the app. | architect S4 | Follow-up: BGAppRefresh asks `/v1/me/sync` once when old pending words exist. |
| — | ADR 0013 "Being scored is client sync state with one owner". | architect | ios-architect writes it after the fixes, in this PR. |

Round 1 re-check (code-reviewer, on 15e94e6): F1–F7 and N1–N8 resolved as decided; no blocking findings. Two should-fix
gaps and four nits, all fixed in this PR (round 2, sync-engineer).

| # | Finding | Decision |
| --- | --- | --- |
| R1 | A wait's poll that joins a `ReadScheduler` flight started less than 10 s after the write can end the wait (probe: a slow pull 2 s after the write). The end guard measures the poll's own time, so it never fails and a mutant removing it survives. | **Fix.** The ledger decides: the ask passes the awaited days into `scoring.answer` as still pending (the F3 rule), and the dead guard goes. The probe becomes a test. |
| R2 | `touchedSoFar` can return an earlier run's days: a cancel before attempt 1 or after the demo / unconfigured short-circuit marks days pending that this run never uploaded, and a demo switch can put the real account's days back. | **Fix.** Days are owed only once an upload was actually entered; `LiveSyncSteps` reports only days of an upload it started. The probe becomes a test. |
| R3 | A push's `.scored` over a cached `stale` stays stale. | Fix: `stale` → scored as well. Test. |
| R4 | `awaiting` / `scored` assign the ledger per day, one widget publish each (up to 90 on a resync). | Fix: build locally, assign once. |
| R5 | `waitedOut` survives account changes and demo switches. | Fix: cleared on `accountChanged` and the demo switch. |
| R6 | The N1 `isSignedIn` guard and the `accountID == account` guards are untested (mutants survive). | Fix: a test each. |

Round 2 fixes: a246317

Round 3 (sync-engineer, ae5df6d): the end-to-end join test waits on `ReadScheduler.joiners(for:)` instead of a race
(0 issues in 80 repetitions); `Harness.statusReads` reads the mock under its lock (the other flake); `SyncService.run`'s
success path has the account guard too, with a test. ADR 0013 rules 3, 4, 6 and 7 updated by the lead for rounds 2–3.
Follow-up: about 46 test lines read `MockPlatformAPI.calls` without the lock; a locked getter fixes them all.

Round 4 (automated reviewer on the merge candidate; verified by sync-engineer, b16a1d7). All four claims reproduced with
failing tests on 83778a5 (25 issues in 10 of 13 tests; the controls passed), then fixed. `ScoringWordOrderTests`.

| # | Finding | Decision |
| --- | --- | --- |
| V1 | A push during a later page records `.scored`, then the upload's completion says `.pending`. In the background nothing answers it, so a calibrating day stays on "Scoring your night…". The same on a retry after a backoff, a queued `.daysChanged`, and a push merged into one (a day never written went pending). | **Real, fixed.** `SyncService.acceptedAt`, fed by the pages and by `.daysChanged` on arrival (`SyncSteps.accepted`): `awaiting` keeps a `.scored` word said at or after the day's last accepted write. A page accepted after the push is a new write and still says pending. |
| V2 | A word outlives its side: `SyncService.upload` returns the days whoever is signed in, the demo switch cancels nothing, and `isSignedIn` passes for B or for demo. `acceptedBefore` too. | **Real, fixed.** `awaiting` carries `ledgerGeneration` from the run's start, and `LiveSyncSteps` drops an earlier generation, on success, partial failure and a kept backoff. The account path needs a direct A → B (`AuthService.apply` has that branch); with a sign-out between, `isSignedIn` already dropped the word. Demo needs only the Profile switch. |
| V3 | `LiveSyncSteps.scored` had no admission: a delayed push brought back the ledger, and after a sign-out the widget file the wipe removed. | **Real, fixed.** `guard readsScoringStatus`. |
| V4 | A push before the first poll leaves a cached `waiting_for_sleep` over a scored, calibrating row, and has already ended the polling. | **Real, fixed.** A `.scored` word lets a row that says `scored` override it. Any other row, or none, stays waiting (F2). |
| — | ADR 0013 rules 2, 3, 6 and 7 need the changes above. | Lead, as for rounds 2–3. |
| — | An admitted delayed push of A's can arrive during B's session: the payload names no account. | Open. Bounded: a day's "scored", no data of A's; the next late read answers it. |
| — | A `.daysChanged` queued before a demo switch runs in the next generation, so its word lands on the new side until a late read. An account change drops the queue. | Open. |
| — | A push refused by the admission still ends a wait for its day (`scoring.signal`). | Open. Demo only: the wait refreshes early. |

Mutation proof: each fix reverted alone fails its tests, and nine finer mutants are killed (`>=` → `>`, always keep
`.scored`, pages or `.daysChanged` not recorded, a generation read late on the success or the partial-failure path, the
generation not from the ledger, the admission without demo or without sign-in, no sign-in check on `awaiting`, any row
beating `waiting_for_sleep`). 0 issues in 40 repetitions of the suite. Not killed: clearing `acceptedAt` in
`forgetScoringWords` changes no behaviour (a stale time is older than any later push); it's there so one account's days
don't stay in memory.
