# 0011 — Additions to the `POST /v1/sync` request ship behind a remote `sync.*` flag

- Status: proposed (2026-10-31, data quality D1, `docs/work/2026-10-31-data-quality/architecture.md` §D1.1–D1.2)
- Deciders: ios-lead, on ios-architect's proposal. The platform provides the flag (`docs/API_REQUESTS.md` → Sync and
  performance).
- Applies to: `Ryft/Environment/Seams.swift` (`FeatureFlag`), `Ryft/Sync/SyncService.swift` (`SyncService.run`,
  `SyncEngine.Context`, `SyncEngine.send`), `Ryft/Networking/Models.swift` (`SyncRequest` and its records),
  `Ryft/Environment/PlatformAPI.swift` (`MockPlatformAPI`), and every future change to what the app sends on
  `POST /v1/sync`

## Context

- **The ingest decoder is strict.** It rejects a request with any field it doesn't know:
  - `ReadJSONStripNUL` calls `DisallowUnknownFields` (`plattform/backend/internal/httpx/httpx.go:143`), nested records
    included;
  - `WriteDecodeError` answers `400` (`:156-167`);
  - `API.md` says the same ("Request bodies reject unknown fields").
- **A `400` on a page is never retried.** The page's anchor stays uncommitted, so the same page fails on every run. A
  field sent one deploy too early therefore stops all syncing for every user who gets the build.
- **The mock can't catch it.** `MockPlatformAPI` decodes with Swift's lenient decoder, which ignores unknown keys.
- **The changelog isn't the deploy.** The platform merges its `API.md` changelog before its image deploy, in separate
  PRs. A build gated on "the changelog is merged" can reach testers before the ingest that understands it.
- **App releases are slow and can't be withdrawn.** A compiled switch can't be turned off when the platform rolls back.
- **There is a precedent.** `sync.gzip` (a request encoding) is already a remote flag. The app's compiled default is
  off, and on a `400` or `415` the app falls back to plain JSON for the rest of the run.

## Decision

1. **A remote flag gates every addition to the request side of `POST /v1/sync`.** That covers a new request field, a
   new field on a record, and a new encoding. Each addition gets a `sync.*` key in `GET /v1/config`, with a compiled
   default of off. The first one is `sync.deletions`, for `Sample.id`, `SleepSegment.id` and `SyncRequest.deleted`.
2. **The code still waits for the contract.** The mirror and the sending code land only after `API.md` has the
   changelog entry, as `CLAUDE.md` requires. The flag then decides *when* the new shape is sent, not *whether* the app
   may know it.
3. **The platform flips the flag** in an environment once the deploy that accepts the addition is live there. It
   accepts the addition whatever the flag says. The flag is the app's signal, not an authorisation, so a phone with a
   stale cached "on" is never refused for that.
4. **The engine never reads flags.** `SyncService.run` reads the flag once per run into `SyncEngine.Context`.
5. **Narrow fallback, once per run.** While the flag is on, a `400` to a request that carries the addition (`415` for
   an encoding) gets that request sent once more in the old shape. The old shape is then used for the rest of the run,
   and the app logs one `notice` with the request ID. A second refusal is a real error and is handled as today.
6. **Byte-level tests guard the default.** With the flag off, the encoded body contains none of the new keys. The mock
   platform gets a strict mode that answers `400` to unknown request fields, so the fallback is exercised in unit tests.
7. **Nothing to gate on the response side.** The app's decoder ignores unknown response fields (`Models.swift` header,
   `API.md` v1 rule), so response additions are mirrored as optionals when the changelog lands.

## Consequences

**Good:**
- A request-shape change can't take down sync, whether through an early build, a late deploy or a rollback.
- The feature can roll out to allow-listed testers first, which matters on write paths over user data such as
  deletions.
- One pattern, already proven by `sync.gzip`, instead of a new mechanism per field.

**Costs:**
- The platform adds a flag row and an `API.md` line per addition, and must remember to turn it on. Until it does, the
  feature stays dark even though both sides have shipped. This shows in Profile → Developer → Feature flags as
  `compiled`.
- Every `sync.*` flag doubles the request shapes the engine can send, and each needs a test of the old shape. Remove a
  `sync.*` flag, with its old shape and fallback, once the platform has made the addition permanent and the oldest
  supported build sends it. Track that in `docs/STATUS.md`.
- A misconfigured flag costs one refused request and a resend per run until the next `/v1/config` (≤ 6 h). It never
  costs a failed sync.

**Rejected alternatives:**
- **A compiled switch flipped with the mirror PR.** No platform work, but it is coupled to App Store latency, can't be
  rolled back, and assumes the changelog date is the deploy date.
- **Probing**: send the new shape and fall back on `400`. No flag, but against an old platform every page of every
  sync costs a `400` and a resend. It inflates the platform's error rate and hides real `400`s.
- **A capabilities or version field in `GET /v1/config`.** More general, but it invents a contract field, and it is the
  platform's decision to make. The open `flags` map already does the job.
