---
name: review-checks-validator-mirrors
description: RYFT review checks for app-side mirrors of a platform validator (sync screen vs ingest validate()) and for new elements in Report a problem diagnostics
metadata:
  type: feedback
---

From the hotfix review of `fix/sync-invalid-workout` (SyncScreen, 2026-11-22). Nothing blocked. What to check:
- **Compare what goes over the wire, not the in-memory value.** `.iso8601` writes whole seconds (truncated), so
  a 0.5 s workout inside one second arrives with `end == start`. A mirror should ask the real encoder (`wire()`),
  and the tests should include sub-second cases on both sides of a second boundary.
- **Go `len` is bytes, Postgres `length()` is characters**, and ingest strips `\u0000` before `validate()`.
- **List every other way the same request is refused**, not only `validate()`: decode errors (400:
  DisallowUnknownFields, RFC 3339 years outside 0000-9999), `normalizeRaw`, DB CHECKs reaching `Fail` (a 500 is
  retried forever, which is also a stall). `validate()` runs before the window filter, so old records count too.
- **Anchor rule:** a page left empty must still commit its anchor (`upload` returns true on empty). Count
  dropped records only in the anchored pass, because the recent window is read again. A full resync resets
  `streams`.
- **New element in the report diagnostics:** the `noHealthValuesInTheDiagnostics` allowlist (`wholeMatch`
  templates) and the "What's included" list both have to learn it. A fixture without the new element passes
  while the guard doesn't cover it.

**Why:** a mirror that drifts from the server means one record stalls a stream again. A privacy guard that
never sees the new suffix proves nothing about it.
**How to apply:** any PR that filters or reshapes data to fit a server rule, or adds a field to feedback
diagnostics. See [[review-checks-outbox-queues]] (whole-batch 4xx) and [[review-checks-fast-paths]] (ISO8601 facts).
