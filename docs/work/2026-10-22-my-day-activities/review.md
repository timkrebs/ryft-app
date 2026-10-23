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
