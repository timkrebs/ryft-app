# My Day, Add activity, Start activity (GPS): plan

Brief: `brief.md` (copy of `CLAUDE_FOLLOWUP_MY_DAY_ACTIVITIES.md`). Platform half: `platform-brief.md`
(`../plattform/CLAUDE_FOLLOWUP_ACTIVITIES.md`). Lead: ios-lead. Started 2026-10-22, on `main` at 58b696c.

## Goal
Today shows the whole day in one place: sleep, tracker workouts, Train sessions, and activities the user added or recorded.
The user can add what's missing, and RYFT can record an activity itself, with GPS distance, pace and route. Route data is
opt-in, privacy-trimmed and never lost before the platform confirms it.

## Preconditions
- **Platform contract:** `API.md` → Activities isn't published yet (checked 2026-10-22). Until it is, the app builds
  against an in-memory fake, and nothing uploads.
- **Folders:** `Ryft/` and `RyftTests/` are classic Xcode groups. This feature needs many new types and files, so the user
  converts both to synchronized folders in Xcode before implementation (Needs-you).
- **Tracker setup first:** #33, #34 and #36 change Today, Profile and `HealthStore`, and add the tracker catalog that My
  Day uses for source names. Implementation starts on `main` after they merge.
- **Background location:** Background Modes → Location is added by the user in Xcode (Needs-you), before the recording
  ticket ships.

## Analysis (parallel, before code)

| # | What | Owner | Output |
| --- | --- | --- | --- |
| D1 | Design note + ADRs: data model, sport catalogue, `ActivityRecorder`, location pipeline, upload queue, Health save, Live Activity, My Day read model, privacy, ticket split | ios-architect | `design.md`, `docs/adr/0003…` |
| D2 | UI spec: My Day card and view, Add activity / Add sleep, pre-start, recording, Live Activity, finish, detail, resume, settings | ui-designer | `ui.md` |

## Tickets (per the brief; owners and dependencies are final after D1)

| # | PR | Owner | Needs the platform contract |
| --- | --- | --- | --- |
| A0 | `design: activities and recording engine` (note + ADRs) | ios-architect | no |
| A1 | `today: My Day` | ios-developer | the fake first; the real endpoint once published |
| A2 | `activities: add activity and add sleep` | ios-developer | the fake first; uploads after the contract |
| A3 | `activities: GPS recording engine` | sync-engineer | no (local-first) |
| A4 | `activities: recording UI, Live Activity, finish and upload` | ios-developer + sync-engineer | uploads after the contract |
| A5 | `activities: privacy zones and route opt-in` | sync-engineer + ios-developer | no |
| A6 | `health: save activities with route to Apple Health` | sync-engineer | no |
| A7 | `docs: activities` | lead | no |
| P2 | `sync: consent gates know the policy in force` (from A2's privacy review; **before any `privacy_policy_version` bump**, so before `activities.manual`) | sync-engineer, architect note first | no |

Every ticket gets the localization-editor (en + de) and test-engineer. Reviews per `docs/AGENT_FLEET.md`:
- code-reviewer, always;
- security-privacy-reviewer for location, routes and permissions (sign-off required);
- ui-validator for visible changes;
- performance-profiler for battery (≤ 8 %/h, screen off).

## Acceptance criteria (draft; finalised with D1 and D2)
- **My Day:**
  - chronological rows for sleep, Health workouts (friendly source names), Train sessions, recorded and manual activities;
  - merged rows with two badges;
  - the empty and missing states;
  - day switching;
  - past days read-only except edit/delete of own items.
- **Add activity:** validation refuses a start in the future, more than 24 h, or end ≤ start. Add sleep is marked "added by
  you" and can be deleted.
- **Recording:**
  - When-In-Use permission only;
  - continues with the screen off;
  - auto-pause;
  - crash-safe resume;
  - distances within ±2 % on the fixture tracks;
  - no faked HR.
- **Upload:** idempotent by client id; queued offline; the local copy is kept until confirmed; states pending, uploaded,
  scored and failed.
- **Privacy:** routes are opt-in per activity, trimmed by privacy zones on the device before upload and export, deleted
  with the activity and the account, and exported.
- **Battery:** ≤ 8 %/h with the screen off, measured on a device.

## Risks
- **Battery and background termination.**
- **GPS quality.**
- **App Review** of background location.
- **Privacy of routes.**
- **Merge friction with tracker setup.**
- **The platform contract's timing.**
- **Classic groups,** if the user doesn't convert them.

## Decisions
- **D2 (`ui.md` §15), the lead's answers:**
  1. **Past days:** Add activity and Add sleep for the last 14 days; Start only today. This loosens the brief's
     "read-only" deliberately, because adding a forgotten activity is the point of "add what's missing".
  2. **Units:** pace and speed follow the locale, like `Fmt.distance`. No new setting.
  3. **Live Activity:** no interactive controls in v1 (no Resume or Pause button), to avoid accidental input in a pocket.
  4. **Strain from perceived effort:** keep both copy variants until the contract says which applies.
  5. **Merges:** no unmerge; the contract has none.
  6. **Recording screen:** follows the system appearance, with ≥ 7:1 contrast.
  7. **Privacy zones** (retroactive or not, and whether the local route is full or trimmed) and the **6 h resume cut-off**:
     the architect decides in D1.
  8. **Live HR zones:** only when the profile has a maximum heart rate; otherwise bpm only. Padel uses the
     `figure.racquetball` stand-in.
  9. **`SourceBadge`:** a new shared component that follows the tracker-setup naming. Until #33 merges, rows show the raw
     source name.
- **D1 (`design.md` §15, ADRs 0003–0006), the lead's answers:**
  1. **C1:** the contract mirror is its own PR (`api: activities contract`, api-contract-keeper) once `API.md` publishes
     Activities.
  2. **My Day read:** ask the platform to extend `GET /v1/days/{day}` (R1, filed) rather than add `/v1/my-day/{day}`.
  3. **Record route:** asked once at the first GPS start, then remembered as the default.
  4. **Session expiry:** unconfirmed activities are kept, bound to the account id, and uploaded after the same account
     signs in again. They are wiped if another account signs in. An explicit sign-out with unconfirmed activities asks
     first.
  5. **Voice cues per km:** a follow-up PR (they need the Audio background mode); not in this release.
  6. **Live BLE heart rate:** a follow-up PR behind `activity.live_hr`; the recording screen says "Heart rate is added
     after your tracker syncs."
  7. **Intents and the Control Center "Start run":** open the pre-start screen, so GPS settles first.
  8. **Catalogue calls:** accepted (rowing without GPS, padel → tennis in Health, ski touring → cross-country skiing).
  9. **Bug found:** the existing "remove RYFT's workout when a tracker recorded it" cleanup only looks for strength, so it
     would delete a RYFT-recorded run. A6 fixes it before RYFT writes runs.
  10. **No `DateStrip` exists.** A1 extracts Strain's week strip into `Ryft/Design/DateStrip.swift`.
  11. **The 15 API requests (R1–R15)** are filed in `docs/API_REQUESTS.md` → Activities and My Day.
- **Ticket order (D1 §10):**
  - A1 (My Day + the shared activities core) first.
  - Then A2 (add activity / sleep, uploader) ∥ A3 (recording engine; its pure core can start before the folder
    conversion).
  - Then A4 (recording UI, Live Activity, finish, upload) after A2 and A3.
  - A5 (privacy) ∥ A6 (Health; after the tracker HealthStore PR).
  - A7 docs last.
  - **Uploads go live only after C1.**
- **Privacy review of the design (security-privacy-reviewer):** sign-off withheld for B1–B3.
  - Revised in `design.md` and ADRs 0003–0006 (B1 trim at checkpoint + zones parked per account; B2 account filter, purge on
    account change, 30-day expiry; B3 immutable zones; S1 encrypted route/HR chunks with Keychain keys; S2 auto-resume
    ≤ 10 min; S3 Background Modes only in the release PR; S5–S7). `ui.md` is aligned.
  - **The lead's call on S6 (the architect's split):** deleting an activity deletes RYFT's Apple Health copy; deleting the
    account keeps Health copies and says so. Manual entries aren't written to Apple Health.
  - New API requests: R16 (no route in list or `PUT` answers) and R17 (`account_deleted` on the final 401).
- **Privacy re-review: implementation may start** (per-PR sign-off on A3–A6 still applies).
  - B1–B3 and S1–S7 are fixed; deviation 1 ("send as recorded" after review) and deviation 2 (`workoutType` in both) are
    accepted.
  - **S8 (new):** a restore to a new iPhone drops the device-only zone keys. It's detected with a twin marker (Keychain
    device-only plus UserDefaults); the route default resets to "not chosen", with a notice. It must be in A5 before the
    flag turns on.
  - **Resume:** a gap across a kill is never bridged (a pause, no distance). Background relaunch ≤ 10 min auto-resumes; a
    foreground launch always asks; Resume under 6 h, same day.
  - The policy also needs the 30-day limits (unsent routes, parked data) and "Apple Health copies stay after account
    deletion".
- **A3 is split into two PRs (lead, 2026-10-23):**
  - **A3a** `activities: track pipeline`: the pure pipeline (Kalman, geodesy, splits, auto-pause, elevation, codec, fixtures). It doesn't depend on A1, so it ran in parallel with A1.
  - **A3b** `activities: recorder, checkpoints and vault`: the `ActivityRecorder` actor, live sources, checkpoints, sealing and trimming. It comes after A1's core merges. security-privacy signs off A3b (trimming and sealing at checkpoint).
- **A3a's acceptance (architect, ADR 0003 Amendment 1, design §11.1 rev. 2026-10-23):**
  - Distance comes from the filter's speed.
  - The still-phone guard has two layers: `isStationary`, then a dead-band.
  - The re-init counts both gates.
  - Split and pace bounds are physics-limited and replace "±2 s against ground truth".
  - The fixtures use drifting noise.
  - The auto-pause clock holds; the displayed moving time never decreases (ui.md G3).
  - Route points are emitted only while recording.
  - GPX files aren't committed; they're generated on demand.

- **A3a.2, a follow-up PR before A3b (lead, 2026-10-23):** the speed-gate re-init cost (code re-review N2).
  - **The cost:** counting speed-gate rejections toward the re-init stops sustained multipath (+75 → −18 m). But short
    3–6-fix ghosts now cost −18 to −27 m. A legitimate stretch above `maxSpeed + 2σ` (a cycling descent above 33 m/s) is
    recorded as 0 m, silently.
  - **Fix:** ios-architect designs the guard first:
    - a shadow filter restored when the next fixes fit it;
    - a bridge after a chain of speed-gate re-inits, at most `maxSpeed`, which still rejects trains;
    - a `speedGateReinits` counter and a `.tooFast(since:)` event, so 0 m is never silent;
    - possibly a higher cycling limit.

    sync-engineer then implements it.
  - **Accepted trade-offs:**
    - a U-turn inside the settle window loses up to ~18 m of ~30 m (N4);
    - about 2.6 m extra per traffic-light stop after a stationary pause (N5).
- **A3b adds `rebasePedometer(_:)`** (paused only: it moves the baseline and counts nothing), for the restore path's
  "neither" case (design §3.9). Approved as an addition to the pipeline API.
- **A3a.2 design adopted (lead, 2026-10-24):** the architect's probe-backed design (ADR 0003 Amendment 2) replaces the shadow
  restore described above:
  - the speed gate is measured from the predicted position, with ghost association;
  - a re-init is provisional until its settle window closes, then filled by dead reckoning (≤ 10 s) or the gap rule;
  - `maxSpeed` bounds the filter's ground speed, with `.tooFast` / `.tooFastEnded` instead of silent 0 m;
  - realistic per-sport limits (walking and hiking 6, cycling 36, gravel 30, MTB 25 m/s).

  **Accepted cost:** a train below 130 km/h after a ride counts.
  **Open:**
  - ui-designer writes state G11 ("too fast") in en and de, plus the Live Activity caption and the finish line, with A4;
  - security-privacy confirms "no route points while too fast" at the A3b sign-off;
  - one extra trail seed reads −2.31 % on both `main` and the design (fixture noise, not this change).

