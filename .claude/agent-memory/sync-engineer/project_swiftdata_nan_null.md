---
name: project-swiftdata-nan-null
description: A Double.nan saved through SwiftData reads back nil (SQLite stores NaN as NULL); provoke an EncodingError with .infinity instead
metadata:
  type: project
---

Seen 2026-11-19 (O1/O2 round 3, iOS 27.2 simulator, `TrainStore(inMemory: true)`): setting `LocalSet.weightKg = .nan`
and saving (any `store.save()`, e.g. `sessionChanged`) leaves the row with no weight, so `s.wire` encodes fine and the
`PUT` goes. SQLite binds NaN as NULL. `.infinity` survives the store and still makes `JSONEncoder` (default
`.throw` strategy) throw `EncodingError.invalidValue`.

**Why:** a test meant to prove "a body this build can't encode is a refusal" passed the request instead and cost a
build round trip.

**How to apply:** for an unencodable SwiftData-backed document use `.infinity`; and NaN is never a value the app
needs to defend against after a save (it's already nil). Related: [[project-swift-testing-macro-pitfalls]].
