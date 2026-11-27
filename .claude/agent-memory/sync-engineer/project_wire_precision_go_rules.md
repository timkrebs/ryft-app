---
name: project-wire-precision-go-rules
description: Mirroring a platform (Go) validation rule in the app must compare the values as they go over the wire - whole-second dates, distantPast = Go zero time, len() in bytes after NUL strip
metadata:
  type: project
---

Learned on the 2026-11-22 hotfix `fix/sync-invalid-workout`. In production, a zero-duration workout stalled the HealthKit sync for good: ingest's `validate()` answers `422` for the whole page, so the anchor never moved. The fix is `Ryft/Sync/SyncScreen.swift`.

- **Dates.** `APIClient.jsonEncoder` (`.iso8601`) writes whole seconds and floors them. Probed on macOS and the iOS 27.2 simulator: 0.9999999 → 0, but within about 1e-6 below the next second it rounds up. The platform compares what it decodes, so a workout from :00.2 to :00.7 arrives as `end == start`.
  - Compare `Date`s only when they are ≥ 2 s apart.
  - Closer than that, compare the encoder's own output (`APIClient.jsonEncoder.encode(date)`). It's cheap, because such records are rare.
- **Go's zero time.** Foundation encodes `Date.distantPast` as `0001-01-01T00:00:00Z`: it counts Julian days before 1582. Go reads that string as its zero time (`IsZero` → "start is required").
- **Lengths.** Go's `len` counts UTF-8 bytes. On sync, ingest strips `\u0000` first (`ReadJSONStripNUL`). The DB CHECKs count characters, but `validate()` is the stricter rule.
- **Not a 422 but the same stall.** `JSONEncoder` throws on a NaN or infinite `Double`. Not handled yet: reported to the lead as a follow-up.

**Why:** a mirror that compares Swift values passes the tests and still sends a page the platform refuses.

**How to apply:** for any rule copied from `../plattform` (sync, imports, journal), first probe how the app's encoder writes the value. Test with an oracle restated from the Go source over the encoded and decoded request (`ingestRefusal` in `RyftTests/SyncScreenTests.swift`). Related: [[project-simctl-spawn-harness]], [[feedback-tests-pin-decisions]].
