# Training import from CSV (Alpha Progression first): plan

Brief: `brief.md` (a copy of `CLAUDE_FOLLOWUP_TRAIN_CSV_IMPORT.md`). Platform half: `platform-brief.md` (a copy of
`../plattform/CLAUDE_FOLLOWUP_TRAIN_IMPORT.md`). Lead: ios-lead. Started 2026-10-23, on `main` at 02a3403.

## Goal
In Strain → My Plans → New Plan → **Import from file**, the user picks a CSV exported from another training app. The app
turns its **plan** into a RYFT plan and, optionally, its **workout history** into completed RYFT sessions. e1RM, records
and "last time" then work from day one. Everything is parsed on the device; the file itself is never uploaded or stored.

## Preconditions
- **Platform contract:** `POST /v1/train/import` (with `Session.origin`, `import_source`, skipped and bodyweight sets,
  and per-item `results`) isn't in `API.md` yet (checked 2026-10-23). Until it is:
  - the app builds parsing, mapping, the flow, ids and duplicates against an in-memory fake;
  - nothing uploads;
  - the feature is dark behind `train.import`.
- **Existing contract to reuse:** `GET`/`POST /v1/exercises` (custom exercises with an app id), `Exercise.load_type`
  (`bodyweight`: `weight_kg` is added load), `Session.bodyweight_kg`, and plans and enrolment (`/v1/plans`).
- **Synchronized folders (#39):** the import adds many new files (`Ryft/Train/Import/…`, fixtures, an alias JSON
  resource). Code tickets start after #39 merges, or stack on it.
- **Personal data:** the user's real exports in `local-samples/` are local only. #40 git-ignores them. Committed
  fixtures are **synthetic** files in the same format. No exercise list, date, weight or plan name from the real files goes
  into the repo, a doc, a PR body or a test name.

## Tickets (one PR each)

| # | PR | Owner (reviewers beyond code-reviewer) | Needs | Notes |
| --- | --- | --- | --- | --- |
| I0 | `chore: ignore local import samples` | lead | — | **#40** |
| I1 | `design: training import` | ios-architect (design note, ADR if needed) ∥ ui-designer (`ui.md`) | — | This plan, plus design.md and ui.md |
| I2 | `train: CSV import parser (Alpha Progression)` | sync-engineer + test-engineer (fixtures, fuzz) | I1 types frozen | Pure, off the main actor, never crashes |
| I3 | `train: exercise mapping and aliases` | sync-engineer (security-privacy: what's remembered per source name) | I1, I2's `ImportBundle` | `Resources/exercise-aliases.json` (en + de), user overrides |
| I4 | `train: import flow` | ui-designer → ios-developer (ui-validator; security-privacy for file access, "Open in" and the document type) | I1 ui.md, I2 and I3 APIs | Steps 1–6, the bodyweight question, preview and result; behind `train.import` |
| C2 | `api: training import contract` | api-contract-keeper | the platform publishes `POST /v1/train/import` | Mirror, fixtures, decode tests |
| I5 | `train: batch upload, ids and duplicates` | sync-engineer (performance-profiler for a large file; security-privacy) | ids and duplicates now; the upload after C2 | UUIDv5 ids, ≤ 50 per request, resumable, local bundle until uploaded |
| I6 | `docs: training import` | lead + localization-editor | all | STATUS, CHANGELOG, TestFlight note en + de, ARCHITECTURE seam table |
| S1 | on #67 (2026-10-27) | test-engineer (ui-validator reads the PNGs; code-reviewer on the tests) | #67's lint fixed | Screenshot tests for the import UI: `ImageRenderer`/hosting controller from the preview mocks, PNGs attached, `make ui-shots` exports to `build/ui-shots/`. No reference images. |

Every ticket gets en + de strings (localization-editor) and tests (test-engineer). Reviews per `docs/AGENT_FLEET.md`.

## Acceptance criteria (draft; finalised with I1)
- **Parser:**
  - the brief's §5 list on synthetic fixtures, with a fuzz test (random line mutations): never a crash, every unknown line
    a warning with its line number;
  - times in the device time zone, said in the preview;
  - KG/LBS to kg;
  - decimal point and comma;
  - `min` and `h:mm hr`, 12 h and 24 h; BOM and CRLF.
- **Mapping:**
  - matching goes exact → alias → fuzzy, with equipment as a hard filter and a confidence;
  - the user's choices persist per source name, per account;
  - custom exercises are created through `POST /v1/exercises`.
- **Bodyweight `+N`:** asked once per exercise (added weight / body weight / ignore). It is stored in the existing
  `load_type: bodyweight` convention, or as an API request if that doesn't fit.
- **Ids:** the same input gives the same ids; one extra workout gives exactly one new id. A re-import creates nothing.
- **Duplicates:** same day and ≥ 70 % overlapping exercises → "Looks like a session you already logged", skipped by default.
- **Upload:** ≤ 50 sessions and ≤ 5 plans per request. Per-item results; a retry continues where it stopped. The parsed
  bundle survives leaving the screen and an app restart until it's uploaded. It's never uploaded for another account.
- **Flow:**
  - the six steps of brief §3, with the result counts;
  - "Open in" for CSVs from Files;
  - VoiceOver, Dynamic Type, dark and light, en and de;
  - a UI test in demo mode with the synthetic files.
- **Manual (the user):** his real files give the expected counts on the result screen, and e1RM for Bench Press and
  Squats is right.

## Risks
- **The platform contract's timing.** Uploads wait for C2; the rest doesn't.
- **Personal data in the repo** (public). Fixtures are synthetic, the samples are ignored (#40), and reviewers check every
  fixture and doc.
- **Matching quality.** Alias data is curated. The fuzzy matcher never auto-accepts below a threshold, and the review
  screen is the safety net.
- **Time zones.** The files have no zone, so device time is assumed and shown. A workout logged while travelling may shift.
- **Rescoring history** changes past strain once (platform). TestFlight notes say so.
- **Parallel work in Train/Strain.** My Day (A1) changes Strain's activities list. The import touches My Plans and
  Profile → Data. Regions are assigned in I1.

## Decisions
- **Flag:** `train.import` (the platform's key pattern, see the A1 review). Compiled default off, on in demo.
- **Order:** I0 → I1 (architect ∥ ui-designer) → I2 ∥ I3 (on frozen types) → I4 → I5 (ids and duplicates first, the
  upload once C2 lands) → I6.
- **I1 answers (lead, 2026-10-23):**
  - **design.md** (494 lines, ADR 0007 for ids) is accepted as written.
  - **"Open in":** the `CFBundleDocumentTypes` / `LSSupportsOpeningDocumentsInPlace` keys ship **only in the PR that turns
    `train.import` on**, as Background Modes does for activities. Otherwise RYFT appears in "Open in" while the feature is
    dark. I4 builds the routing code; the keys wait.
  - **Remembered exercise choices** (`ImportMapping`) are part of "Export my data". security-privacy confirms in I3.
  - **Plan targets without history:** `rpe` 8, because `PlanValidation` refuses an empty `kg`. This is the closest to the
    brief's "leave empty".
  - **"Survives an app restart"** applies from the Import tap. Before that, the parse stays in memory, per the brief's
    "only the parsed result, after the user confirms".
  - **`SyncCoordinator` trigger:** A2's `.activitySaved(days:)` and the import's day refresh share one trigger, renamed
    `.daysChanged(days:)` by whichever PR lands second.
  - **ui.md questions:**
    1. Steps 2 and 3 stay separate.
    2. Defaults: all time; today; "make active" off when a plan exists.
    3. Duplicates: same day, ≥ 70 % overlap, skipped by default (final).
    4. Yes to "Clear remembered matches" in Profile → Data.
    5. No time-zone override in v1.
    6. Drop the guessed export menu path unless the user confirms it.
    7–8. Reconciled with design.md.
    9. The resume row clears after 7 days.
    10. The document type is CSV only; `.fileImporter` also accepts plain text.
  - **API requests T1–T12** are filed in `docs/API_REQUESTS.md` → Training import.
- **Open for the user:**
  - the sample holds 13 workout blocks on 13 days, while the brief expects 12;
  - a German export, to confirm the German tokens (Q1).

