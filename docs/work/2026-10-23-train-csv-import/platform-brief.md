# RYFT Platform — batch import of plans and workout history — brief for `platform-lead`

Run: `claude --agent platform-lead` → "Run `CLAUDE_FOLLOWUP_TRAIN_IMPORT.md`". Owners: **api-contract-owner** (first),
**backend-engineer**, **database-engineer**, **scoring-scientist** (rescoring past days), **test-engineer**; review
**code-reviewer**. App half: `../app/CLAUDE_FOLLOWUP_TRAIN_CSV_IMPORT.md` (the app parses the CSV on device and sends
structured data; the platform never sees the file).

## Contract (`API.md` → Train; additive)

- `POST /v1/train/import` — body `{source: "alpha_progression", plans: [Plan], sessions: [Session]}` using the existing
  `Plan` / `Session` shapes plus: `Session.origin` (`app` default | `import`), `Session.import_source?`, sets that carry
  `skipped: true` and bodyweight sets (`bodyweight: true`, `added_kg?`) — check how Train models bodyweight today and extend
  additively if needed. Ids come from the app (deterministic) → **idempotent**: an existing id with identical content is a
  no-op, different content updates it. Limits: ≤ 50 sessions and ≤ 5 plans per request, 1 MiB; `422` per item with its id
  and reason in a `results` array (`created | unchanged | updated | rejected`) — partial success, never all-or-nothing.
- Exercises referenced must exist (built-in or the user's custom ones, created before via `POST /v1/exercises`).
- Changelog, JSON examples, Swift mirror, `make check-swift`.

## Behaviour

- Imported sessions are completed sessions at their original times: they feed history, e1RM, records and "last time".
- **No push notifications** (`SESSION_SCORED`, `PR`) for `origin: import`, and no "new record" insight spam: records found in
  imported history are recorded silently (the newest one may surface once as an info card, scoring-scientist decides).
- **Rescoring past days:** imported sessions add muscular load to their days' strain. Enqueue one rescore for the affected
  date range after the batch (not per session); document the effect in `SCORING.md` (history changes once on import).
- Rate limiting: the batch counts as one request; per-user import concurrency 1.
- Migration if needed (`origin`, `import_source`, set flags); deletion/export cover them; tests: idempotency, partial
  failure, bodyweight sets, skipped sets, rescore enqueued once, no push for imports.

## Done when

Contract published, endpoint live with tests, the app can import the user's 12 workouts and 1 plan in one or two requests,
re-import creates nothing, and his history shows correct e1RM and records without notifications.
