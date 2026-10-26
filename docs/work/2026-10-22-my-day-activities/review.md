# My Day and activities: review log

Lead: ios-lead. Reviews are read-only; their findings go back to the owner.

## A3a `activities: track pipeline` (2026-10-23)

**Commits:**

| Commit | What |
| --- | --- |
| f729e4f | The pure pipeline: Kalman, geodesy, splits, auto-pause, elevation, codec, seeded fixtures |
| 24c26cf, a2007ad | ADR 0003 Amendment 1, design §3.3/§3.4/§3.9/§11 amended, R20 |
| b059151 | Review fixes (code review + architect) |
| f07b6f4 | Re-review fixes |

**Gates:** strict build clean; Unit 960/960; `make lint`, including `make-tracks.py --check` on Python 3.9–3.15.

**Final fixtures:**

| Fixture | Distance | Other |
| --- | --- | --- |
| road-5k | +0.31 % | splits km 1–4 −1.96 … −2.81 s |
| trail-switchbacks | −0.34 % (raw fixes +10.5 %) | baro ascent 400.5 m (truth 399.9) |
| still phone | 0.0 m | auto-pause on and off |

Over 20 seeds: road −0.10 … +0.45 %, trail −0.95 … +2.09 %, worst split ≤ 4.37 s.

### code-reviewer (f729e4f), then the architect

| # | Finding | Result |
| --- | --- | --- |
| 1 | The start or restart fix counted as distance: +20/+42 m for a still phone | Settle window (Theil–Sen line vs filtered track): 0.0 m |
| 2 | Still phone with auto-pause off, under drifting noise: 15–228 m in 10 min; the fixture never tested it | `isStationary` modelled; a per-sport dead-band backstop; the noise model accepted in §11.2 |
| 3 | Redaction trapped on NaN or ∞ accuracy | "?" rendering, tested |
| 4 | A stopwatch linearity test, flaky under load | A structural retained-sample test |
| 5–14 | `stepFrom` across Start; Python-version-dependent `--check`; staleness after an invalid fix; late fixes after Resume; splits in backdated pauses; ascent 0 vs nil; ∞ average speed; dead code; warm-up diagnostics; `dump` leaking the anchor latitude | All fixed, with tests |
| A (architect) | Sustained multipath "aged open" the speed gate: +79–92 m per episode | The re-init counts both gates: −18 m |
| B (architect) | The auto-pause moving clock jumped back ≥ 10 s | The clock holds while a pause is pending; the displayed time never decreases |
| C (architect) | Route points emitted while paused | Emitted only while recording |
| D (architect) | 558 KB of unused GPX files in the test bundle | Generated on demand |

### code-reviewer re-verification (b059151)

All of the above were confirmed fixed with a standalone harness. New findings:

| # | Finding | Result |
| --- | --- | --- |
| N1 | A settle window closed by its cap with fewer than 3 fixes dropped up to −134 m | Falls back to the gap rule: 0.0 m |
| N3 | Standing start after a warm filter lost 7–20 m | The window always opens at Start: −0.1 … −2.8 m |
| N6 | `pause(at:)` discarded the window's events | Returns them |
| N7 | The dead-band test had no teeth | It fails with the dead-band at the floor |
| N2 | Counting speed-gate rejections costs short 3–6-fix ghosts −18…−27 m. A stretch above `maxSpeed + 2σ` (cycling > 33 m/s) records 0 m silently | **Deferred to A3a.2** (plan): architect first, with a shadow restore, a bridge, and a `.tooFast` event |
| N4, N5 | A U-turn inside the window loses up to ~18 m; +2.6 m per traffic-light stop | Accepted trade-offs |

**Privacy:** the pipeline logs nothing, `Checkpoint` has no coordinate, and every location type redacts in `description` and `dump`.
The security-privacy sign-off for trimming and sealing comes with A3b, where they're built.

**Contracts for A3b:**
- forward the events of `ingest`, `advance(to:)`, `pause(at:)` and `finish(at:)`;
- store splits from `checkpoint`;
- feed the first pedometer sample after `resume(at:)`, and add `rebasePedometer(_:)` for the restore path;
- route chunks only from `.route`, which is emitted only while recording;
- GPS-only elevation on a still phone: about 17 m of false ascent in 10 min. Gate it on `isStationary` (A3b, D1).
- **Merge with A1:** delete `Ryft/Activities/Recording/TrackProfile+Pending.swift`, since A1's `Sport.swift` declares `TrackProfile`. Then point the test fixtures at `Sport.*.trackProfile`.

## A3a.2 `activities: speed-gate guard` (2026-10-24 → 26)

**Commits:**

| Commit | What |
| --- | --- |
| bfbe917 (on `main`) | The design: ADR 0003 Amendment 2, design §3.3 and §11.1 rev. A3a.2 |
| 4ef4c6e | The guard as designed: the speed gate measured from the prediction, association, a provisional re-init with an anchor, `maxSpeed` on the filter's speed with `.tooFast` / `.tooFastEnded`, per-sport limits |
| ee974c0, 03753e6 | Review fixes S1–S3 and the nits; the acceptance after the review |
| c33883f | Re-review fixes X1–X4; Doppler vetoes entering only |
| 2f098b1, b669276, bb76df9 | ADR 0003 and the design describe the rules as built |

**Gates:** strict build clean; Unit 1294/1294; `make lint`; 259 activity-suite tests in the reviewer's own run, longest case 1.6 s.

**Acceptance, as built** (the reviewer's measurements at c33883f; the same with Doppler absent, on every fix, on 30 % of fixes, or in 5-fix gaps):

| Case | Bound | Measured |
| --- | --- | --- |
| GPS ghosts with noise, against the same seed | ±4 m | −3.9 … +2.7 m |
| Cycling descent at 33 m/s | 0 % | −0.05 … +0.15 %, 0 episodes |
| Descent above a 25 m/s limit | ±1 % vs the part below the entry speed | +0.76 … +2.01 % vs "at or below 25", 1 episode |
| "Running" picked on a bike | ≤ 80 m, `.tooFast` within 4 s | 54–68 m, 2–3 s |
| Train after a run | ≤ 135 m | +107 … +131 m over 20 seeds, 1 episode |
| Committed fixtures | identical | road +0.31 %, trail −0.34 %, still phone 0.0 m |

### code-reviewer (4ef4c6e): 3 should-fix, 5 nits

| # | Finding | Result |
| --- | --- | --- |
| S1 | Near the limit, distance was refused silently before the state confirmed, and the state flapped (a sprint at 8.5 m/s: −12 … −18 m on some seeds; cycling at 35.5 m/s: up to −621 m) | Refused steps are held until the state confirms and released if it doesn't. Entry above max(limit × 1.05, limit + 0.6 m/s), exit at or below the limit. 0/20 episodes near the limit; no silent refusals |
| S2 | Walkers and hikers got a false "too fast" in sliding multipath (7/20 walks) | A valid Doppler speed below 0.9 × the limit vetoes entry (`LocationFix.speedAccuracy` added). 0 with Doppler on every fix |
| S3 | A ghost starting inside a non-provisional settle window cost 24–42 m | The window anchors at its first filtered position |
| N-a … N-e | Too fast continuing into pauses; route points at episode edges; `PipelineDiagnostics` decode defaults; a diagnostics invariant after restore; a gap inside the window | N-a: a pause ends the state. N-c: missing counters decode as 0, tested on an A3a checkpoint. N-d: an open anchor counts as dropped. N-e: bridged from the anchor. **A3b:** N-b, route points written before an episode confirms |

### code-reviewer re-verification (ee974c0): 1 should-fix, 3 nits

| # | Finding | Result |
| --- | --- | --- |
| X1 | The Doppler veto failed open on every fix without Doppler (30 % Doppler: 13/10/5/2 false episodes per 20 runs, walk/hike/trail/run) | The last usable Doppler speed is held for up to 8 s, raised by 0.5 m/s² per second of age: 1/1/0/0. Plain 5 s and plain 8 s were measured and rejected (ADR 0003) |
| X2 | A Doppler speed with poor accuracy still vetoed | `speedAccuracy` above 2 m/s counts as unknown |
| X3 | A checkpoint taken while steps were held lost them on restore (−10.8 m per step) | The checkpoint counts them, as Pause and Finish do |
| X4 | The mean-speed rule for position steps was untested (a surviving mutant) | `positionStepsAreJudgedByTheirMeanSpeed`. 65/66 mutants caught; the survivor (`>` vs `>=`) is equivalent |
| — | **Implementer's addition:** with Doppler on every fix, braking ended an episode early and the filter's lag counted (train +129 … +141 m) | Doppler vetoes *entering* only; inside an episode the filter's speed decides. Train +107 … +131 m |

### code-reviewer re-verification (c33883f): ship

X1–X4 are fixed, with tests that fail without them, and nothing in the acceptance regressed. The entry-only rule is sound.

**Carried to A3b:**
- **N1:** a slide that starts during an episode can extend it, by up to 20 s on the walking profile with fast slides. Option: end the episode after about 5 s of fresh, valid Doppler below the limit.
- **N2:** the Doppler holdover crosses Pause and auto-pause (+27 m, 2 s later, in a car scenario). Reset it in `pause(at:)` and `enterAutoPause`.
- **N3:** Doppler gaps longer than 8 s fail open again (10-fix gaps: 7/4/4/3 per 20 runs). D1 logs gap lengths.
- A3b maps `CLLocation.speed` and `speedAccuracy` into `LocationFix`. Without that the veto never applies.
- `PipelineDiagnostics` counts the share of fixes with a valid Doppler speed, for D1.

**Privacy:** unchanged from A3a. The pipeline logs nothing; `LocationFix` gains a speed accuracy, not a coordinate.

## A1 part 1: the activities core (6c63923, 2026-10-23)

**Reviewers:**
- code-reviewer: one blocking finding, three should-fix;
- security-privacy-reviewer: signed off for this commit's scope, with no blocking findings.

### Fixed in `fix/my-day-core-review` (sync-engineer), merged into `feat/my-day`

| # | Source | Finding | Decision |
| --- | --- | --- | --- |
| 1 | code (blocking) | `today.myDay` / `activity.liveHR` don't match the platform's key pattern `^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$`. `PUT /v1/admin/flags` answers 422, so the flags could never be switched on. A widened test regex hid it. | Renamed to `today.my_day` and `activity.live_hr`. The test regex now uses the platform's pattern, and a new test checks every flag key. |
| 2 | code | Before C1, `.notPublished` was recorded as a successful fetch ("loaded" in Sync details) and took a budget slot on every call. | New frozen addition `ActivitiesAPI.publishesActivities`: the live stub skips the scheduler entirely. |
| 3 | code | A whole-document PUT without `route` / `hr_samples` would erase the platform's copy on a later edit. Left-out cleared fields would never clear. | R19 filed: a missing field keeps the stored value, and `null` clears it. Cleared editable fields are sent as `null`. |
| 4 | code | A deleted activity comes back from the cached day list, because the Repository had no single-item removal. | `Repository.forget(activity:)` added to A1's frozen API, for A2's delete. |
| 5 | privacy S-1 | `LocalManualSleep.day` was unique across accounts. A second account's write could upsert into the first account's parked row. | The unique key is scoped by account. Fixed before any build ships the schema. |
| 6 | privacy S-3, code nits 5–6 | The demo store and the mock source survive an account switch, so B could see A's demo notes. | `ActivityStore.accountChanged()` and `MockActivitiesSource.reset()`, called from `AppState.reset()`. |
| 7 | privacy S-2 | `demoFlags` turned on recording and live HR in Release builds, where Demo data exists. | Both moved under `#if DEBUG` until the release PR. |
| 8 | privacy N-1 | Route and HR were stripped only in two store methods. `SportActivity` printed coordinates and notes. | `SportActivity.encode` omits `route` / `hrSamples`, and `description` is redacted. |
| 9 | privacy N-4, N-7; code nits 8–9 | Purge footgun; `.public` error text on store open; a test assertion that can't fail; wall-clock tests. | A doc line; domain and code only; a real German lookup; fixed dates. |

### Carried to later tickets

| Finding | Ticket |
| --- | --- |
| Export of platform copies, unconfirmed rows and manual sleep must exist before `activities.manual` turns on (privacy S-4, GDPR Art. 15/20) | **A2** (moved from A5) |
| `onWipe` / `onAccountWillChange` call `repository.invalidate()`, `activities.accountChanged()` and the mock reset inside the wipe (N-3); purge gets the incoming id (N-4) | A2 |
| The uploader's generation includes the demo switch, so a demo row never goes through the live client (code nit 10) | A2 |
| An unknown `origin` is read-only; an unknown `sport` keeps its raw value for round trips (code nit 7) | A2 / C1 |
| Chunk inits enforce sealing: `init(profile:)` / `init(sealed:)` (N-2) | A3b |
| Vault keys are deleted in `wipeSharedLocalData` (keys first), plus a launch sweep for keys without rows (N-5) | A3b |
| `urlCache = nil` on the API sessions (N-6, pre-existing) | C1 |
| On-device upgrade test from the current TestFlight build: `isDurable == true` after the schema change (N-7) | device check before the next TestFlight |
| Policy text when `activities.manual` turns on: manual activities, manual sleep, unconfirmed rows parked for at most 30 days; "activity notes" under Other User Content | A7 / release |

## Device check N-7: schema upgrade (2026-10-23, the user's iPhone 16 Pro, Debug build of 784bc97 over the T4 Debug build)

- **Upgrade:** the A1 build was installed over the previous one and launched once with its log streamed
  (`OS_ACTIVITY_DT_MODE`). There was no "Train store unavailable, using memory" line, while other error-level system lines
  did appear in the same stream.
- **The live store opened on disk:** `group.dev.timkrebs.ryft` → `Library/Application Support/Train.store` (+ wal/shm)
  was modified at the launch minute. So `isDurable == true` after adding `LocalActivity`, `ActivityTrackChunk` and
  `LocalManualSleep`.
- **New finding (privacy):** an orphaned `Train.store` of about 2.2 MB (with its WAL) remains in the **app** container,
  last written 2026-10-22 10:38. It's the store from before SwiftData's default configuration picked the App Group
  container. It holds earlier read models, and `TrainStore.wipe()` (sign-out, account deletion) never touches it.
  → Follow-up: delete it once at launch, and add it to the STATUS follow-up "the SwiftData store sits in the App Group".
- **Runtime warnings seen in the same log, to check against `main`:**
  - "Charts: Custom UnitPoint values are not supported in AxisValueLabel's anchor property";
  - "onChange(of: SyncLine) action tried to update multiple times per frame".
- **No screenshots:** the Phone/InCallService UI was running, so the session paused per the device rules.

## A1 part 2: My Day card and view (d8f114d → e64716b)

**Gates at e64716b:**
- strict build clean;
- Unit 1,368;
- UISmoke 30;
- `make lint`.

**Commits:**

| Commit | What |
| --- | --- |
| d8f114d | My Day card and full view, `DateStrip` extracted from Strain, `SourceBadge`, `ActivityStateMark`, Strain's list on the assembler (behind `today.my_day`) |
| 140f74d | Strings reviewed |
| 6a899c1 | test-engineer: assembler, view model and UI tests (~99 cases, 6 UI tests in UISmoke) |
| 784bc97 | Review fixes |
| e64716b | Final fixes |

### code-reviewer (d8f114d): 1 blocking, 7 should-fix

| # | Finding | Result |
| --- | --- | --- |
| 1 | **Blocking:** "No sleep recorded" appeared on every day the platform hadn't scored yet (placeholder `sleep: null`), next to "Waiting for last night's sleep" | Only on scored days that aren't pending or waiting for sleep; `nightGap` stays a suppressor |
| 2 | Re-render on every finished read (`reads.revision`), and SwiftData fetches per render | Stored `AppState.failingDayReads`; `snapshots(ids:)` |
| 3 | Tracker catalog parsed on the main actor in Today's first frame | Loaded off-main; raw names until then |
| 4 | Pull to refresh broke the 3 s spinner cap and asked for today twice | Today: the app's pull plus activities, not awaited. Past days: capped, and the app's pull too |
| 5 | Merged rows led nowhere | `MyDayItem.mergedWorkout` opens the tracker's workout (lead-approved interface addition) |
| 6 | Manual night matched by exact time | ±60 s |
| 7 | A moved activity showed on both days once confirmed | Hidden on the old day whenever the local row is elsewhere |
| 8 | One activities read per touched day | Only within the 7-day strip |

**Re-verification (784bc97):** all fixed. Two new items:
- A: the shared "Uploading" key changed Today's first-import step in German → its own key `myday.state.uploading`; "Hochladen" restored for the step.
- B: a past-day pull no longer synced → it runs the app's pull too.

### ui-validator (784bc97): no blockers

| Finding | Result |
| --- | --- |
| Source badge truncated mid-word at AX5 | Wraps to 2 lines |
| "·" and durations broke across lines | No-break joins (`MyDayText.join`) |
| The pinned strip took about a quarter of the screen at AX3 | Capped at xxxLarge |
| Trailing marks misaligned | The chevron column is always reserved |
| German hints machine-translated | Reviewed, with translator comments |
| Journal and Strain AX3 issues | Not A1's; they predate it |

### performance-profiler (784bc97): ship
- **Launch:** 462 / 455 / 463 ms (flag on / flag off / `main`), within noise.
- **Rendering:** no render storm; a 50-activity day builds in 2 ms; linear.
- **Memory:** no leak.
- **Hot spot (`DateParsing.rfc3339`):** about 95 µs per cached date (older code, multiplied by My Day's re-decodes) → its own PR, `perf: fast date parsing for cached reads` (#45).
- **Note:** new Train sessions didn't refresh the card → it now observes `TrainSyncService.sessionsMark`.

### Device: the user's iPhone, his real account (Debug, `-RyftFlags today.my_day`)
- **Today:** last night's sleep, 8h 08m (matches the Today tile), the real 7-day strain strip, "Nothing yet today".
  The "0.0" pill sat alone on its own line → it moves to the title row on days without activities (e64716b).
- **Tue 2026-10-20:** one Garmin run listed about 6× ("6 activities · 54.3 km"); day strain correct at 20.1.
  - The debugger found the platform holds about 6 distinct workout ids. Every layer keys on the HealthKit UUID, so Apple Health most
    likely holds 6 copies written by Garmin Connect. Not an app bug.
  - Pending: the user checks Apple Health; then a platform request (same source, same times → one workout).
  - App hardening: a repeated workout id is never two rows.
- **Schema upgrade check:** passed (above). It found the orphaned pre-App-Group store, fixed in `fix: remove the store left behind by the App Group move`.

### Carried forward
- **Before the flag turns on:** sport names "Running" vs workout detail "Run".
- **German 24 h leading zeros (`Fmt.time`):** a device check.
- **Possible flake:** `MyDayUITests.testEveryRowHasAVoiceOverSentenceWithItsSources` uses a `descendants(matching: .any)` query that timed out once locally (it passed on retry).

## A2 part 1: uploader, account hooks and export (125f7d9, merged with `main` in e985bf8)

Nothing blocked the commit. The live client publishes nothing before C1, and part 1 had no UI. The findings below would
lose data, resurrect it, or send it without consent once C1 lands and `activities.manual` turns on. All of them are
fixed in `fix/a2-review` (sync-engineer, 0ba27f6 and 87551d0), which is merged into `feat/add-activity`.

### code-reviewer (125f7d9): 4 should-fix, 7 nits

| # | Finding | Fix |
| --- | --- | --- |
| 1 | A cancelled or interrupted PUT counted as never sent, so a later delete stayed local and the platform kept the activity | Before every PUT, the row persists a sent marker (`UploadAttempt` `.cancelled`, no status). An answer replaces it, and 404 or no-contract clears it. A cancellation keeps it, with no backoff |
| 2 | Re-adding a night while its DELETE was out deleted the new night | `removeSleep(day:onlyIfDeleted:)` removes the night only while it is still a tombstone. Tested with a held request |
| 3 | One row failing transiently blocked the whole queue | Backoff is per item. After `failedAfter` failures the row is passed over and the rest go |
| 4 | The background refresh waited on `flush()` past its expiry | `flush(upTo: 20 s)`, and the expiration handler stops the replay |
| Nits | Unknown origin showed "Added by you"; `cachedDay` scanned a year; export vs #47; the demo test had no live row; no concurrent-flush test; design §4.3/§10/§11.1 still said `activitySaved` | Neutral badge (part 2); bounded scan; export binding below; both tests added; the design text is carried below |

### security-privacy-reviewer (125f7d9): 4 should-fix, 5 notes

| # | Finding | Fix |
| --- | --- | --- |
| 1 | The uploader didn't check consent: every trigger sent one item and was refused, and a gate appearing triggered a flush | `ActivityUploader.gate` reads `onboarding.syncGate`. It is checked in `startReplay` and before each item, and the app flushes only when the gate clears |
| 2 | An in-app account deletion could park the data instead of deleting it (a concurrent 401 ended the session as an expiry) | `isDeletingAccount` makes any ending a deletion, the uploader stops before `DELETE /v1/me`, and the deletion wipe always runs after success |
| 3 | The export wasn't bound to one account, and A2 added notes and nights to it | The account is captured before the first await, rows are read with `ofAccount:`, an `accountChanges` counter catches A→B→A, and `forgetExport()` runs inside the wipe. **`TODO(#47)`:** fold into `AccountBinding` and remove the export file |
| 4 | Parked rows were invisible to the user, and nothing could delete them while signed out | `parkedCount()` and `purgeParked()`. Welcome shows a count-only line and "Delete from this iPhone" (part 2) |
| N1 | A launch-time sign-in never purged or unparked | Done once when signed in at launch |
| N3 | Tombstones kept their notes | Cleared on tombstone |
| N2 | The first attempt doesn't re-check the account after `accessToken()` | **C1** |
| N4 | The `try?` chunk delete can leave orphans | **A3b** orphan sweep |
| N5 | Export lacks R11 (manual nights from the platform) and routes | **A5** |

**Decision (lead):** the parked-rows notice on Welcome is not gated on `activities.manual`. Signed out, no account
evaluates flags, so the flag reads its compiled default. Parked rows can only exist if the feature was on.

## A2 part 2: Add activity, Add sleep and the detail (555d687), and the fix rounds

### code-reviewer (555d687): 3 should-fix, 5 nits

| # | Finding | Fix |
| --- | --- | --- |
| B1 | Add or Edit sleep could overwrite another day's night, or add one over the tracker's, because the checks looked at the day the sheet was opened for, not at the wake day | The target day is validated against manual and tracker nights; a move saves the new night before tombstoning the old |
| B2 | The detail's Edit and Delete ignored `activities.manual` | Gated on the flag |
| B3 | The ＋ menu offered Add sleep while the tracker's night was only late or being scored | Offered only with the missing-night row |
| Nits | Add activity just after midnight landed on yesterday; Send first's loop lived in the view (and repeated silently offline or in demo); the merge-note copy; no exception for editing an old night; no midnight or DST tests | All done |

### security-privacy-reviewer (555d687 and the fixes): signed off, 3 should-fix

| # | Finding | Fix |
| --- | --- | --- |
| B-1 | The parked-rows notice was behind `activities.manual`, which reads off when signed out | Shown whenever parked rows exist (lead decision above) |
| A-1 | The upload gate opened for a consent to any policy version until `/v1/config` arrived | `uploadGate` stays closed until the policy version is known and matches; the uploader's gate is closed by default |
| A-2 | A deletion's success path could sign out another account that signed in meanwhile | The deletion is bound to its account; `isDeletingAccount` is true only for it |
| Notes | "Log in within 30 days" counted from now; Send first could sign out another account | "Log in by {date}" from `parkedUntil()`; Send first is bound to the account and change counter at the tap |

### code-reviewer re-check (5473810): 1 should-fix, 4 nits

| # | Finding | Fix |
| --- | --- | --- |
| A1 (round 2) | An edit or Retry erased the sent marker, so a cut-off upload followed by an edit and a delete stayed local while the platform kept it | A dedicated `sentAt` field that only the uploader sets and only a confirmation clears; `ActivitySchemaUpgradeTests` opens an A1-era store |
| G1 | The upload gate needed the policy version, which lived in memory only: a cold background launch or an offline start uploaded nothing | Falls back to the account's cached `RemoteConfig`, and the config is refreshed on reconnect |
| Nits | A deletion cut short by an account switch showed a raw error; "gated" won over "offline"; the upgrade test bypassed `TrainStore`; A2-r (privacy, low): A→B→signed out during a deletion showed A's notice to B | Fixed |

**Carried:**
- **C1:**
  - a 2xx this build can't read is recorded as refused forever; treat it as confirming the revision sent;
  - check the account between building the body and attaching the bearer on the first attempt;
  - confirm the platform refuses activity and manual-sleep writes for an outdated consent (403).
- **P2, its own ticket, before any `privacy_policy_version` bump** (sync-engineer, architect note first): the consent gates in background processes.
  - **HealthKit sync** opens its gate for a consent to any version while `/v1/config` hasn't answered in the process (background wakes, a config that times out, a bump mid-session). Up to one page (20,000 records, 32 MiB) per wake goes to the platform and is refused. Give `syncGate` the upload gate's fail-closed semantics via `policyVersionInForce`.
  - **Both gates:** use the cached version only while `fetchedAt + ttlSec > now`, and persist a `consent_required` refusal per account until a check finds consent current. Without these, a stale cache after a bump lets one refused item (or page) out per background wake.
  - **From the re-check of e453232:**
    - a forced check on every reconnect while the config keeps failing (honour the recheck interval);
    - a SwiftData read per pending row per render while the session's config is missing (memoise);
    - a newer cached config doesn't release the gate until the next check.
- **Platform:** refuse activity and manual-sleep writes for an account whose deletion is in progress (R22); confirm `403 consent_required` on them for an outdated consent (R23); R17 (`account_deleted`).

### Re-checks of e453232

Both reviewers signed off. A2-r and G1 are closed, and another account's cached config is never read. Their remaining
notes are in P2 above.

### code-reviewer, integration (555d687 → e4cd91c): nothing blocks

The merge of `main` (#47) lost nothing: export cleanup still runs at launch, in every wipe, when the share sheet closes and
on an account change. B1–B3 and Send first are fixed as asked.

| # | Finding | Fix |
| --- | --- | --- |
| D1 | The deletion note read unobserved state: after a failed deletion it stayed, and nothing restarted the queue | Observed; a failed deletion for the same account flushes |
| Nits | A night from another device read as a tracker's; days not cached on this iPhone weren't checked; Add activity at exactly midnight opened invalid | Neutral wording; the day is loaded first (Save waits); the default window is always valid |

### localization-editor: no changes

The English and German copy is complete, with plurals on the count sentences and matching format arguments.

### ui-validator (5431669): 4 should-fix, nits

| # | Finding | Fix |
| --- | --- | --- |
| 1 | German sheet titles truncated ("Aktivität hinzuf…") | Shorter titles |
| 2 | The splits table mixed km and mi in a miles locale | The table uses its splits' unit (km) throughout; per-mile splits carried to A4 |
| 3 | The "Fastest" marker broke the pace cell (en and de) | The pace column never wraps; a glyph column, with the word kept for VoiceOver |
| 4 | "No sleep recorded · Add sleep" wrapped badly at the default size | One line if it fits; otherwise stacked without the dot |
| Nits | The effort scale's "10" was cropped at AX5; an empty caption gap; a teal toolbar icon; "Use Other" was plain text | Fixed |

**Not reachable in demo mode, still to check:**
- the uploading, gated, offline and failed states (previews only);
- Send first (needs unsent rows and a session);
- 24-hour time on a German device.

**Carried to A4:** the detail's route map and its pace, elevation and HR charts (§8.1.4–8.1.8), "Start activity", per-mile splits.

### test-engineer: UI acceptance in demo mode

`AddActivityUITests` (Full; test 1 in UISmoke):
- Add activity saves a pending row "Added by you" whose VoiceOver label leaves the notes out;
- invalid times disable Save, with their reason; the future can't be picked;
- the detail edits and deletes the new row;
- Add sleep on a missing night (the `-RyftScenario missing-night` demo scenario);
- Add sleep is not offered where the tracker has the night;
- with `activities.manual` off, nothing can be added, edited or deleted.

**Shared helpers:** `RyftUITests/Support/UITestSupport.swift`. `MyDayUITests` now uses typed queries and takes one
snapshot of the rows instead of re-querying the whole tree in a loop. That loop is the likely cause of its CI timeout
(the run on #47).

### Gates (846ec54, merged with `main`)

| Check | Result |
| --- | --- |
| Strict build | no warnings |
| Unit plan | 1977 passed |
| UISmoke | 32 tests; 1 skip that predates A2 |
| `AddActivityUITests` and `MyDayUITests` | 12 of 12 |
| `make lint` | clean |

### Simulator only; device checks still to do
- **The schema upgrade with `sentAt` over a real A1 store.** The upgrade test can't open the store through `TrainStore` itself, so check `isDurable` (no in-memory fallback) on the device, as in N-7.
- **After C1:**
  - expire a session with an unsent activity: the parked notice shows on Welcome;
  - delete the account with an unsent activity: nothing remains on the phone;
  - background the app during an upload.
- **24-hour time in German** on a device: the simulator showed 12-hour times.
