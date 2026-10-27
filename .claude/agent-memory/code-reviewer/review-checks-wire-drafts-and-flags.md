---
name: review-checks-wire-drafts-and-flags
description: RYFT review checks for new remote flags (platform key grammar), draft wire types for unpublished endpoints (stub errors inside ReadScheduler, whole-document PUTs), and read-model caches that need a removal path
metadata:
  type: feedback
---

Found in the A1 "activities core" review (2026-10-23); all passed the implementer's green suite:
- **Flag keys vs the platform's grammar.** `plattform/backend/internal/flags/flags.go` `keyPattern` is
  `^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$`; the admin `PUT /v1/admin/flags/{key}` answers 422 otherwise
  (`backend/cmd/api/config.go`). A1 shipped `today.myDay` / `activity.liveHR`: can never be turned on. A test regex
  relaxed to let new flag values through (ReportProblemTests `flags`) is the tell. Check every new `FeatureFlag` raw value.
- **"Not published" swallowed inside a `ReadScheduler.run` fetch closure** returns success: `succeeded()` sets and
  persists `fetchedAt`, so Sync details / Copy diagnostics claim a fetch that never happened, and nothing cached means
  `.ifStale` never short-circuits (a budget start per call). Ask what the pipeline *records* for "nothing sent".
- **Whole-document PUT drafts** vs data the app deletes after confirm (route / HR chunks): a later edit PUTs without
  them; under "create or replace" the server copy loses them. Ask for omitted-field semantics in API_REQUESTS.
- **Cache with store() but no remove().** A confirmed DELETE removes the local tombstone; the cached server list
  (24 h TTL for past days) brings the row back. Check every delete path has a cache removal.

**Why:** contract/ops mismatches only show once the feature is switched on. **How to apply:** on any PR adding flags,
draft wire types or a new Repository resource. See [[review-checks-dark-launch]], [[review-checks-shared-transport]].

Identity by exact `Date ==` across the wire (My Day manual night, 2026-10-23): `APIClient.jsonEncoder` is `.iso8601`
(whole seconds), so a local value with sub-seconds never equals the server's copy; ask for a tolerance.
