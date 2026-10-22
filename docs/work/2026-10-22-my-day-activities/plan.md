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
  6. **Live BLE heart rate:** a follow-up PR behind `activity.liveHR`; the recording screen says "Heart rate is added
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
