# RYFT iOS — import plans and workout history from CSV (Alpha Progression first) — brief for `ios-lead`

Run: `claude --agent ios-lead` → "Run `CLAUDE_FOLLOWUP_TRAIN_CSV_IMPORT.md`". Platform half (batch import, import origin,
no PR pushes for history): `../plattform/CLAUDE_FOLLOWUP_TRAIN_IMPORT.md` — its contract must exist before §4 uploads.
Owners: **ios-architect** (importer design note), **sync-engineer** (parser, mapping, upload), **ui-designer** →
**ios-developer** (flow), **api-contract-keeper**, **test-engineer**, **localization-editor**; reviewers per fleet.

> **Copy note (lead, 2026-10-23):** the original brief quoted lines from the user's real export. The repo is public, so
> every example value below (plan and day names, exercise lines, dates, times, durations, loads) is replaced with a
> synthetic one in the same format. The structure is unchanged. The original stays local.

## Goal

Under **Strain → My Plans → New Plan → Import from file**, a user picks a CSV exported from another training app and gets
(a) the **plan** (days, exercises, sets, target reps) as a RYFT plan and (b) optionally the **workout history** (every
logged set with weight and reps) as completed RYFT sessions — so e1RM charts, records and "last time" work from day one.

## The real input (samples)

The user's exports are in `local-samples/` (**local only, never commit**: add `local-samples/` to `.gitignore` in the first
PR). Build committed test fixtures as **synthetic** files in the same format (`RyftTests/Fixtures/Import/…`), not copies of
his data — the repo is public.

**Format "Alpha Progression"** (semicolon-separated, double-quoted text fields, ` · ` as inner separator, UTF-8):

`*_Plans.csv`
```
"Base block · 6 weeks";2026-01-05          ← plan name · duration in weeks ; start date
"Day 1 · Upper"                          ← day index · day name
"1. Overhead Press · Barbell";"3 sets";"8 reps"   ← order. exercise · equipment ; sets ; target reps
…
"Day 2 · Lower"
…
```

`*_Workouts.csv` — blocks separated by an empty line, newest first:
```
"Upper · Standalone workout";"2026-02-14 5:10 pm";"42 min"            ← day name · standalone ; local start ; duration
"Lower · Day 2 · Week 3 · Base block";"2026-02-11 7:05 am";"1:12 hr"   ← day name · Day n · Week w · plan name
"1. Overhead Press · Barbell · 8 reps"                          ← order. exercise · equipment · target reps
#;KG;REPS                                                             ← set table header (unit column: KG or LBS)
1;40;8
2;50;6
1;-;-                ← set not performed → skip (count as skipped, not zero)
1;+20;8             ← bodyweight exercise with "+N" → see §2
1;42.5;8            ← decimal point (handle decimal comma too)
```
Durations seen: `42 min`, `1:12 hr` (h:mm). Times: `3:28 pm` (12 h); also accept 24 h (`15:28`) and German exports
(decimal comma, `Std.`/`Min.` if they exist — make the token table data-driven). Exercises can differ between weeks of the
same plan day (weeks 1–2 had one exercise that week 3 didn't) — that's history, not an error.

## 1. Importer architecture (ios-architect → sync-engineer)

- `TrainImportFormat` protocol: `detect(_ data: Data) -> Confidence`, `parse(_:) throws -> ImportBundle`. First
  implementation `AlphaProgressionFormat`; detection by structure (quoted ` · ` headers, `#;KG;REPS`). Leave clear seams for
  later formats (other apps export comma-separated CSVs with header rows — note them in the design, don't build them now).
- `ImportBundle` (pure value types): `plans [ImportedPlan(name, weeks, startDate, days [ImportedDay(index, name, exercises
  [ImportedPlanExercise(order, name, equipment, sets, targetReps)])])]`, `sessions [ImportedSession(title, planName?,
  dayIndex?, week?, start, duration, exercises [ImportedSessionExercise(order, name, equipment, targetReps, sets
  [ImportedSet(index, weightKg?, reps?, bodyweightModifier?, skipped)])])]`, `warnings [ImportWarning(line, message)]`.
- Parser: streaming line reader, tolerant (BOM, CRLF, trailing `;`, empty lines), **never crashes** on bad input — unknown
  lines become warnings with line numbers. Times are interpreted in the **device time zone** (the file has none); show that
  assumption in the preview. Units: `KG`/`LBS` → kg internally.
- Everything runs on device, off the main actor; the file itself is never uploaded or stored — only the parsed result, after
  the user confirms.

## 2. Map exercises to RYFT's library

- Load the library (`GET /v1/exercises`, cached). Match `name · equipment` → RYFT exercise by: exact (normalised case,
  punctuation, plural "Curls"/"Curl") → alias table (`Resources/exercise-aliases.json`, en + de names, e.g. "Wide-Grip
  Pulldowns · Cable" → lat pulldown wide grip, cable; "Lying Triceps Extensions · EZ bar" → lying triceps extension, EZ
  bar) → fuzzy (token overlap with equipment as a hard filter) with a confidence score.
- **Review screen:** every distinct imported exercise once, with its match and confidence; ✓ for exact/alias, "check" for
  fuzzy, "new" for none. The user can pick another library exercise or **create a custom exercise** (name + equipment +
  muscle group; `POST /v1/exercises` with an app id). Remember the user's choices (per source name) for future imports.
- **Bodyweight "+N":** ask once per exercise: "‘+20’ for Dips — is that added weight, or your body weight?" (options: added
  weight → load = N kg added; body weight → bodyweight set with 0 added; ignore weight). Store as the platform's bodyweight
  convention (check `API.md` → Train for how bodyweight and added load are modelled; request it if missing).

## 3. The flow (ui-designer → ios-developer)

Entry: Strain → My Plans → **New Plan** → **Import from file** (also Profile → Data → Import training data, and RYFT appears
in the Share sheet / "Open in" for `.csv` files exported from Files — declare the document type `public.comma-separated-values-text`).
1. **Pick file** (`.fileImporter`, CSV and plain text; one or both files; multi-select).
2. **Detected:** "Alpha Progression export · 1 plan · 2 days · 19 exercises · 12 workouts from 8 Jun to 5 Jul 2026" + warnings.
3. **Choose what to import:** Plan (toggle) · Workout history (toggle, with date range) · "Make this my active plan"
   (enrol, start date = today or the file's start date).
4. **Map exercises** (§2).
5. **Preview:** the plan as RYFT will show it; history as a list with totals (sessions, sets, volume). Duplicates flagged (§4).
6. **Import** with progress; result: "Imported 1 plan and 12 workouts · 3 sets skipped (no weight or reps)" and buttons
   to open the plan and the history. Errors are per item, never all-or-nothing; a retry continues where it stopped.

Plan details: plan name from the file (editable), weeks from "· 4 weeks", day names and order, sets × target reps per
exercise. Starting weights aren't in the plan file: if history is imported, prefill each exercise's suggested load from the
**most recent** imported session ("last time"); otherwise leave empty.

## 4. Upload and duplicates (sync-engineer, with the platform)

- Deterministic ids: `UUIDv5(namespace: RYFT-import, name: source + plan/session key + start time + exercise order)` so a
  re-import of the same file creates nothing new (idempotent), and a later export with more workouts adds only the new ones.
- Use the platform's batch endpoint (`POST /v1/train/import`, see the platform brief) — not one request per session (rate
  limits). Chunk ≤ 50 sessions per request, resumable.
- Sessions are marked `origin: "import"` with the source name; they count for history, e1RM, records and the strain of
  their days (the platform decides how to rescore past days); **no PR push notifications** for imported sessions.
- Duplicate detection against existing RYFT sessions: same day and ≥ 70 % overlapping exercises → preview marks it
  "Looks like a session you already logged" (default skip).
- Offline: the parsed bundle is kept locally until uploaded; the user can leave the screen.

## 5. Tests

- Parser on synthetic fixtures covering: plan header with weeks and date; days; exercise lines; standalone and plan
  sessions; `-` sets; `+N`; decimals with point and comma; `min` and `h:mm hr`; 12 h and 24 h times; CRLF/BOM; a block
  with a missing table header; garbage lines → warnings, no crash. Fuzz test with random line mutations.
- Matching: exact, alias, fuzzy, equipment filter, user override persistence.
- Ids: same input → same ids; one extra workout → one new id.
- Flow: view-model tests for each step; UI test in demo mode importing the synthetic files.
- Manual: the user's real files from `local-samples/` (12 workouts, 1 plan) → expected counts in the result screen; verify
  e1RM for Bench Press and Squats from the imported history.

## Ship

PRs: `chore: ignore local import samples` · `design: training import` · `train: CSV import parser (Alpha Progression)` ·
`train: exercise mapping and aliases` · `train: import flow` · `train: batch upload, ids and duplicates` · `docs: training
import`. Strings en + de. TestFlight note: "Import your plan and workout history from Alpha Progression (CSV export)".
Needs-you: run the platform brief first; test with your files.
