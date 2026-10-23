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
