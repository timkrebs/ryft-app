# Review log: read-model writes off the main actor (P1, ADR 0018)

Design note: `design.md` (decisions 1–12). Branch `perf/persistence-off-main`.

## Round 1 — code-reviewer and security-privacy-reviewer on 5670676

Neither found a blocker. Every finding was fixed in `523e34d..53d7c48`.

| # | Finding | Decision |
|---|---|---|
| CR1 | Should fix: after Demo data off → on, Today stayed empty (a queued clear raced the refresh). | `Repository.reset()` releases demo data's store and drops its queued writes; tests from the reviewer's probe, plus "no flash of old rows". |
| CR2 / N5 | Should fix: main waited 324 ms behind a held save (one lock for the epoch value and the save). | `StoreEpoch` split into a save gate and a value lock; main reads `current` without the gate. |
| S1 | Should fix (privacy, pre-existing): a `PATCH /v1/me` answered after the sign-out wrote A's user for B. | `userChange()` before the request; `store(user:asOf:)` drops an answer that a wipe, the demo switch, a store or epoch change overtook. All five call sites. |
| S2 | Should fix (privacy): a refused `.user` save lost a consent withdrawal. | One resubmit of the written-through user while its epoch is current. |
| S3 | Should fix (privacy): a `/me` asked before the withdrawal could reopen the gate. | `store(fetchedUser:askedAt:)`; the re-check asks `.changed(since: revokedAt)`; `check()` decides from the Repository's user. |
| S4 | Should fix: test gaps (widget after the wipe, the stress test). | `aCommitAfterTheWipeDoesntPublishTheWidget`; the stress test mixes `.user`, demo writes and repeated days. |
| N1–N4 | Notes: wiped writers kept, flights after a wipe, uploader follow-ups, the seed's user. | Retired with `StoreID` keys; flights re-check the account; follow-ups skip dropped writes; the seed writes through per store. |
| CR3 | System completions waited without a bound. | `settledBeforeCompletion()`: at most 2 s on `env.clock`, ends on cancel. |
| CR4 | The drain inherited a low submitter priority. | `.userInitiated`. |
| CR5 | The HealthKit delivery's completion waited for writes. | No wait. |
| CR6 / CR7 | Uploader follow-ups; `replaceScores` dead. | Covered by N3; deleted. |

## Round 2 — both reviewers on 53d7c48

No blocker; 10 of 11 claims verified. Both found the same consent hole independently. Fixed in `f7b1248..4f1ef67`.

| # | Finding | Decision |
|---|---|---|
| F1 / C1 | Should fix (privacy): a `PATCH /v1/me` sent before the withdrawal and answered after it brought the consent back, and its arrival made the re-check's correct `/me` drop. The mock built its answer after the hold, so the tests missed it. | `UserChange.began` (a count of stored changes): an answer begun before a newer change is dropped and re-read with `.changed(since:)`; the withdrawal writes through `storeConsentWithdrawn`; the mock answers as of the request's arrival. |
| F2 | Should fix (privacy, iOS 17 only after T0.6): after a demo session the withdrawal's `.user` save is refused, so a relaunch or a background launch read the old consent. | A per-account withdrawal marker in defaults, counted as a consent signal, plus a `consent_required` refusal. Ends at `agree()` or a later `/me` with consent to the latest policy. Passes on 17.0 without a known issue. |
| C2 | Should fix: completing at the 2 s bound could suspend the app mid-save into the App Group store (0xdead10cc). | In the background the drain pauses at the bound or on cancel; the completion awaits only the batch in progress; writes resume at `.active` or after 10 s. Compaction got an expiration handler and a bounded wait. |
| C3 | Test gap: nothing pinned S2's resubmit bound. | `aRefusedSaveOfTheUserGoesAgainOnceOnly`. |
| C4 | The stress test never ran `Repository.reset()`. | It calls `accountChanged(from:)` after the sign-out, as RyftApp does. |
| C5 | Wall-clock bounds tight for a loaded CI Mac. | 250 ms, positive waits 5 s, event-based where possible; touched suites pass in parallel at width 4. |
| Nits | `clear()` test-only; Notification settings wrote an assembled user; `retire` didn't advance the epoch; `refreshDay`'s fallback; `fetching` checked only the account. | Deleted; re-read after the PATCH; advances; nil on a binding change; `AccountBinding`. |

**Found by the iOS 17.0 run, not by review (9ecc6cd):** on iOS 17.0, after demo data's container exists, a refused save of a change to existing rows followed by `ModelContext.rollback()` traps inside SwiftData. Round 1 introduced the rollback. A refused or dropped batch now drops its writer instead; `theAccountsUserChangedAfterTheDemo` reproduces the crash on 17.0 without the fix.

**Mutation testing:** 69 mutants over both rounds (`p1fix-mutants.py`); every one is killed by at least one test, except `FIX-rollback-back`, which is equivalent on 27.2 (only 17.0 traps) and was killed on 17.0. Two N1 survivors showed the `retired` set had become redundant once `retire` advanced the epoch; it is deleted (4f1ef67) and the epoch checks are pinned by new mutants.

## Runtimes

| Runtime | Result |
|---|---|
| iOS 27.2 | Unit plan and UISmoke green; the 22 touched suites green serially and in parallel at width 4 |
| iOS 17.0 | 58 persistence, sync, wipe and consent suites: 416 tests, 2 known issues (T0.6 `aBatchNeverSpansTwoStores`; `didSave` without deleted IDs on iOS 17) |
| iOS 18.0, 26.0 | T0 and T0.6: the account's writes after the demo land (the iOS 17 fault doesn't occur) |

## Open

- **P1b (iOS 17 only):** reopen the account's container after the demo, with the demo's workouts discarded after a confirmation. Until then: on iOS 17, after "demo, then sign in", relaunch before the first sync lands. The consent marker (F2) holds meanwhile.
- **AC3** (frames in the first 0.3 s) is not met: the remaining stalls are Today's first-data render, which is the Today render follow-up. **AC5** (no cold-launch regression) showed no regression within the noise of a loaded Mac; a quiet rerun is pending.
- **Device checks** (the user's list): consent withdrawal on a slow network and offline, iOS 17 after the demo, sign-out during a refresh, the widget after sign-out, background refresh with no 0xdead10cc.
