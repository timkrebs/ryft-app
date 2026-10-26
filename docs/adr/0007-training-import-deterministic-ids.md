# 0007 — Imported training data gets deterministic ids; the file stays on the device

- Status: proposed (2026-10-23, training import, `docs/work/2026-10-23-train-csv-import/design.md` §6, §7, §9)
- Deciders: ios-lead, on ios-architect's proposal; the batch contract (`POST /v1/train/import`) is the platform's
- Applies to: `Ryft/Train/Import/Build/ImportIDs.swift`, `ImportBuilder.swift`, `DuplicateDetector.swift`,
  `Upload/TrainImportUploader.swift`, `Access/ImportFileAccess.swift`

## Context

The user imports plans and workout history from another app's CSV export (Alpha Progression first). The same export,
or a newer one with more workouts, will be imported again. Three requirements pull together:
- **No duplicates.** A re-import must create nothing, and a newer export must add only the new workouts.
- **Retries are safe.** Uploads are batched and resumable, and the answer to a successful batch can be lost.
- **Personal data stays put.** The file holds personal training data and must never be stored or uploaded.

The app already generates the ids of sessions, plans and custom exercises (`API.md` → Train). The file has no ids and
no time zone. Exercise order and names in the source app can change between exports.

## Decision

1. **Every imported item gets a UUIDv5 id**, derived from the content that identifies it:
   - **Algorithm:** RFC 9562, SHA-1 through CryptoKit.
   - **Namespace:** `aed18370-8351-4f38-9f14-af711a508076`.
   - **Parent:** a per-account namespace (`account␟<user id>`) for top-level items; a child is derived from its
     parent's id.
   - **Name:** the source format, then normalised names, then the **wall-clock** start (`YYYY-MM-DDTHH:mm`), then an
     occurrence counter.
   - **Never in the name:** exercise order, titles, durations or the resolved instant.

   The recipe table in design §6 is part of this decision. **Changing the namespace, the separator (U+001F), the field
   order or the normalisation of keys is a breaking change**: every earlier import would come back as duplicates.
2. **The app skips what already exists.** Before uploading, it reads the user's plans and the sessions in the
   import's range:
   - a derived session id that is already present is not sent;
   - an existing plan is kept unless the user asks to replace it;
   - the platform's idempotency by id covers retries whose answer was lost;
   - a skipped item is never written to the server, so "import anyway" later reuses the same id.
3. **The file never leaves memory.**
   - It is read through security-scoped access (`.fileImporter`, or Open-in with `LSSupportsOpeningDocumentsInPlace`)
     into `Data`.
   - It is parsed `@concurrent` and dropped when the flow ends; Inbox copies are deleted at once.
   - Only the confirmed, wire-ready result (a `PendingImport` per account in `TrainStore`) is stored until it's
     uploaded, for at most 30 days, and it's wiped at sign-out.
4. **Imports never touch the live-session path.** No `LocalSession`, no `PendingTrainOp`, no Apple Health save. The
   import has its own uploader and its own job row.

## Consequences

- **Re-imports are idempotent across devices and reinstalls** (the ids depend only on the account and the file),
  and the same file in two accounts never collides.
- **Edits made in the source app after an import aren't applied to sessions already imported.** Their ids exist, so
  they're skipped. Updating imported history would need a "replace" option and the platform's `updated` result,
  which is a later decision.
- **Renaming a plan in the source app** gives a new plan. Renaming a day or reordering exercises doesn't.
- **A user who travels** and imports again in another zone gets no duplicates. New sessions use the current zone,
  which the preview names.
- **New formats** (header-row CSVs) reuse the recipe with their own `ImportFormatID`. That id is part of every name, so
  it can't be renamed later.
- `ImportIDsTests` pins the RFC test vector and fixed ids for the synthetic fixtures; a recipe change fails them.

## Amendment 1 (2026-10-23): the source-exercise key is vocabulary-free

**Context.** I3's review found that the custom-exercise id and the `ImportMapping` key were built from the *matching*
normalisation. That normalisation uses the editable alias file: synonyms, equipment phrases, plural rules. Editing
`exercise-aliases.json` would then have changed ids and orphaned remembered choices. For example, adding `landmine` as an
equipment word would turn "Landmine Press · Landmine" from `landmine press|landmine` into `press|landmine`, creating a
second custom exercise and splitting its history.

**Decision.** `SourceExerciseKey` is computed only by `fold`, a fixed Unicode clean-up that never reads the vocabulary:
- `name` = `fold(name)`;
- `equipment` = `fold(field)`, or "" when the field is missing or empty. It is never the vocabulary's canonical equipment id.

`fold(text)`, in this order:
1. On the raw scalars: any White_Space becomes U+0020. Drop every scalar of category Cc or Cf, every
   Default_Ignorable_Code_Point, and the apostrophes U+0027, U+0060, U+00B4, U+02B9, U+02BB, U+02BC, U+02BD, U+2018,
   U+2019, U+201B, U+2032 and U+FF07.
2. NFKC.
3. Each scalar becomes its own full lowercase mapping (UnicodeData plus SpecialCasing's unconditional mappings), with no
   context and no locale: no Final_Sigma ("ΟΔΟΣ" → "οδοσ"), "İ" → "i̇". No diacritic folding; ß stays ß.
4. Step 1's drop set is dropped again first (steps 2 and 3 can produce it: U+0149 → U+02BC n). Then each run of scalars
   that aren't letters, marks or numbers (L*, M*, N*) becomes one U+0020. No leading or trailing space. The result is
   idempotent: `fold(fold(x)) == fold(x)`.
5. No sorting, no deduplication, no length cap.

`scripts/import-fold-check.py` implements these steps a second time, with the Unicode tables written out (White_Space,
Default_Ignorable_Code_Point, the apostrophes), and checks the golden file in `make lint`.

The id recipe is unchanged:
- custom exercise = UUIDv5(account namespace, `exercise␟<source>␟<key.name>␟<key.equipment>`);
- an `ImportMapping` row is keyed by (account, source, key.name, key.equipment).

The alias vocabulary is used **only** for matching, and for a custom exercise's kind and load type.

**Consequences.**
- Editing `exercise-aliases.json` can never change an id or orphan a remembered choice.
- `RyftTests/Fixtures/Import/source-keys.golden.json` pins 1,065 keys: every alias name, built-in name, fixture name and
  equipment spelling. An independent Python implementation of `fold` agrees on all of them.
- Only a change to `fold` itself is a breaking id change, and it needs a new amendment and a migration of remembered rows.
- **Accepted cost:** two spellings of the same equipment ("Barbell" / "Langhantel") make two step-4 rows and two custom
  exercises if both are new. Within one export app spellings are consistent, so this is rare.

## Amendment 2 (2026-10-26): plans, days and sessions, as I5 built them

**Context.** The recipe table in design §6 left four details open: where occurrence counters start, which way they
count, how a plan's name is normalised, and what tells two days with the same number apart (I2 keeps both, with
`.duplicateDay`).

**Decision.** `ImportIDs` (I5), pinned by `ImportSessionIDsTests` with vectors computed independently in Python:
- Every occurrence counter starts at **0**.
- A session's occurrence counts the sessions with the same wall-clock start key **oldest first**, which is from the end
  of an Alpha Progression export (it lists the newest first). A newer export that adds workouts at the top keeps every
  earlier id.
- A plan's name in its key is `fold(name)` (Amendment 1's fold), its start date `YYYY-MM-DD` or "".
- A plan day is `day␟<number>`; a number the file names again adds `␟<occurrence>` (1, 2, …), so the first day keeps the
  plain recipe.
- A plan exercise's and a session exercise's occurrence counts the same source-exercise key within its day or session.

Not ids, but decided with them: a plan day's `day_index` is its place in the order of day numbers (the file's number
minus one when the numbers run 1, 2, 3, …), so gaps and repeats still give `0 …< days_per_week`.

**Consequences.** Changing any of these is a breaking id change, like Amendment 1's.

