# Tracker setup, sync check, honest calibration: plan

Brief: `brief.md` (copy of `CLAUDE_FOLLOWUP_TRACKER_SETUP.md`). Platform half: `../plattform/CLAUDE_FOLLOWUP_BASELINE_WITHOUT_HRV.md`.
It must land before §1 (T4) shows real numbers. §0 and §2–§5 start now. Lead: ios-lead. Started 2026-10-22, on `main` at
d9fc265.

## Goal
A Garmin (or any HRV-less) user is never stuck at "Baselines 0 / 7". RYFT asks what the user wears, shows exactly what reaches
it and how to set the sync up, and checks that data actually arrives. Today names the tracker properly and tells "your night
isn't in Apple Health yet" apart from "scoring".

## Analysis (parallel, before code)

| # | What | Owner | Output |
| --- | --- | --- | --- |
| T0 | Confirm the root cause (§0) | debugger | `t0.md`: verdict, Incidents entry, evidence request |
| R1 | Vendor facts per tracker, verified against current vendor help pages | general-purpose (web research) | `trackers-research.md`, `trackers.draft.json` |
| D1 | Design note: catalog, selection, sync check, source names, Today states, ticket regions | ios-architect | `design.md` (+ ADR 0002 if needed) |
| D2 | UI spec: onboarding step, setup card, Devices & sync, Check sync, Today hints | ui-designer | `ui.md` |

## Tickets (one PR each)

| # | PR title | Owner → tests | Brief | Depends on |
| --- | --- | --- | --- | --- |
| T1 | `fix: source names and the night-not-synced state` | sync-engineer + ios-developer → test-engineer | §4 | D1, the catalog interface |
| T2 | `feat: tracker setup and devices & sync` | ios-developer (catalog: sync-engineer) → test-engineer | §2 | D1, D2, R1 |
| T3 | `feat: sync check` | sync-engineer + ios-developer → test-engineer | §3 | D1, D2, R1, T2's catalog |
| T4 | `fix: honest calibration and recovery inputs` | api-contract-keeper → ios-developer → test-engineer | §1 | **platform contract in `API.md`** |
| T5 | `docs: tracker setup` | lead (+ localization-editor) | §0, Ship | all |

Strings for every ticket: localization-editor (en + de, brand guard green). Reviews per `docs/AGENT_FLEET.md`:
- **always:** code-reviewer;
- **security-privacy-reviewer:** remote content, HealthKit queries, what goes into diagnostics, `PATCH /v1/me`;
- **ui-validator:** every visible change;
- **performance-profiler:** HealthKit queries on launch or Today.

## Acceptance criteria (testable)

**T1: source names and the night-not-synced state**
- **Display names:** the stale-source hint, Profile's Data sources and Sync details show the catalog's display name for a known
  bundle ID (`com.garmin.connect.mobile` → "Garmin Connect"). Unknown sources keep HealthKit's name.
- **Night not in Apple Health:** in the morning, if the newest sleep/HR sample from the user's tracker is older than the wake-up
  window, Today says the night hasn't reached Apple Health yet and names the app to open. "Scoring your latest data" is **not**
  shown then.
- **Scoring:** "Scoring…" appears only while `GET /v1/me/sync` reports `pending`. Beyond `expected_within_sec` × 3 it becomes
  "Taking longer than usual", with Details. It never shows as an endless line.
- **No regressions:** the refresh-resilience rows (A–E) and the status line behave as before. Their tests stay green.

**T2: tracker setup and devices & sync**
- **Onboarding:** a skippable "What do you wear?" step after "About you" and before Apple Health access. Several trackers can be
  selected; "Just my iPhone" is exclusive.
- **Setup card per tracker:** what reaches RYFT (per signal) and the resulting features, setup steps with the vendor guide link
  and checked date, habits, "Open/Get <app>" (App Store link, no private URL schemes) and "Show me again later". The
  honest-limit variants (Fitbit, Samsung, Just my iPhone, Other).
- **Catalog:** bundled copy; remote `https://ryftapp.de/trackers.json` with ETag cache and schema validation. Invalid or
  unreachable → the bundled copy. Remote content can't inject links outside the allow-list.
- **Profile → Devices & sync:** edit the selection, see each card, run Check sync (T3).
- **Selection storage:** stored per account, gone after sign-out or an account switch.
- **Tests:** persistence; decode + validation + fallback; capability → feature text.

**T3: sync check**
- **Classification:** for each selected tracker and signal, the newest sample in 48 h from that tracker's sources is classified
  as ✓ (with time), expected ✗ (the catalog says it isn't shared), unexpected ✗ (with the fix) or waiting.
- **Nothing in 48 h:** "No data from <app> yet. Open <app> and let it sync, then tap Check again."
- **Permission wording:** only what HealthKit can know; read permission isn't observable (D1 defines the rule).
- **Tests:** a Garmin-like `MockHealthStore` (no HRV) → HRV expected ✗, HR ✓, sleep ✓. A demo scenario drives a UI test.

**T4: honest calibration and recovery inputs** (after the platform)
- **Decoding:** `DailyScore.hrv_baseline_days` (int?) and `recovery_inputs` ([string], tolerant of unknowns), each with a fixture
  test from the `API.md` example.
- **Detail text:** without `hrv` in `recovery_inputs`, Recovery/Readiness detail says it's based on resting heart rate, sleep
  (and breathing rate), with a link to the tracker's card.
- **No stuck counter:** a counter is never shown when it can't move; the missing signal is named instead.

**T5: docs**
- `docs/STATUS.md` → Incidents (from T0); `docs/API_REQUESTS.md` (`User.trackers` via `PATCH /v1/me`, `trackers.json` on the
  web); `TESTFLIGHT_NOTES.md` en + de; review log; CHANGELOG lines in each code PR.

## Risks
- **Vendor facts change.** Each guide carries its source URL and checked date, and the remote catalog fixes them without a
  release.
- **HealthKit read permission is opaque.** Wording must not claim "denied" when we can't know.
- **Classic Xcode groups.** No new files in `Ryft/` or `RyftTests/`: the catalog's bundled copy and new types go into existing
  files (D1).
- **Parallel PRs share files** (`Models.swift`, `HealthStore.swift`, `TodayViewModel.swift`, `ProfileView.swift`,
  `HealthPermissionView.swift`, `Localizable.xcstrings`). Assign regions (D1) and pre-resolve on an integration branch.
- **Brand rule:** vendor names only as data sources, no logos, no comparisons; the denylisted brand never appears.
- **§1 depends on the platform's model change and rescore;** until then the app must not promise "7/7".

## Findings from T0 and R1 (2026-10-22)
- **T0, partly confirmed:**
  - The platform cause is confirmed: `baseline_days = min(N_hrv, N_rhr)`, and calibrating while either is under 7.
  - The tester's build (1eb5192) showed "0 / 7" for any calibrating day. `main` (d9fc265, #28) already shows the score with
    a note, but with fewer than 7 cached days it still shows "0 / 7". Its note blames "your watch".
  - "Scoring your latest data" isn't stuck. It's the `awaitingScores` phase after any upload (e.g. iPhone steps), ending on
    `/v1/me/sync` or after 300 s. It's misleading next to the stale-tracker hint.
  - The brief's evidence commands are corrected in `t0.md`.
- **R1:**
  - Garmin Connect writes **no HRV and no resting HR** (and no respiration, no SpO₂). It sends only while Connect is open
    in the foreground, and Apple Health backfills at most 2 weeks.
  - Oura: no HRV, no resting HR. Fitbit now writes natively ("Google Health"). Samsung writes nothing.
  - The bundle IDs are verified. Apple Watch matches by device, not by bundle ID.
- **Consequence:** the platform's planned fix (baseline from resting-HR nights) doesn't help Garmin users unless the platform
  derives resting HR from overnight HR. Filed as `API_REQUESTS.md` → Tracker setup §1, for the user to relay to the platform
  session **before** it runs its brief. The app builds every "based on …" sentence from `recovery_inputs`, never from a
  fixed list.

## Decisions
- **"Open <app>":** the App Store page only. iOS can't tell whether an app is installed without declaring private URL
  schemes, and the store page shows "Open" when it is.
- **Fitbit/Samsung "Tell us you'd like this":** dropped (not in the brief).
- **Devices & sync** (D2): a new pushed screen in Profile → Data. It absorbs the source list (`User.sources`, shown as "Seen
  in Apple Health" with display names) and links Sync details, which stays as is (request IDs for support).
- **`User.trackers`:** local per account until the platform accepts it.
- **D1 (`design.md`, ADR 0002), with the lead's answers to its §11:**
  1. **The bundled catalog:** `Content/trackers.json` is turned into a Swift string by `scripts/trackers.py` (checked in
     `make lint`), because `Ryft/` is a classic group. Converting the groups to folders stays an optional user step and
     doesn't block anything.
  2. **Dark launch:** T2 and T3 ship dark behind the remote flag `devices.setup`. The user turns it on after the platform
     deploy and T5's text.
  3. **Diagnostics:** `trackers` (ids) and `sync_check` (codes) go into Report a problem only after security-privacy
     review.
  4. **Night window:** fixed at 04:00 / 08:00 / 15:00 for now. Using the Bedtime & wake time is a follow-up.
  5. **Slow scoring:** "Taking longer than usual" after max(60 s, 3 × `expected_within_sec`).
  6. **"Based on …":** the note goes on Insights' Readiness and Recovery cards (no detail screens exist).
  7. **The setup screen after Health access:** a RootView case, with no state-machine change.
  8. **T5 is content:** the catalog's en + de text and the regenerated region, titled `content: tracker guides`. A final
     `docs: tracker setup` PR (T6) closes the release with STATUS, ARCHITECTURE, Incidents and the review log.
  9. **T4's blocker** ("never a counter that can't move") may merge before the platform, because it needs no new API
     fields. `recovery_inputs` and `hrv_baseline_days` are decoded only once they're in `API.md`.
  10. **The features line for Garmin/Oura** follows `RyftFeatures.restingHRFromHeartRate` until the platform decides on
      derived resting HR.
  11. **Doc drift:** the hook message and "brand guard in `make lint`" are fixed in T6.
  12. **The id is `iphone`,** never `iphone_only`.
- **Execution:**
  - T1 starts now (sync-engineer, own worktree). Its first commit is the frozen catalog core.
  - T2 (ios-developer) and T3 (sync-engineer) branch from that commit and run in parallel, wiring into each other only
    after T2 merges.
  - The localization-editor translates the catalog text now, from R1's draft.
  - Conflicts are pre-resolved on an integration branch, as last time.
