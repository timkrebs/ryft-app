---
name: project-swiftdata-upgrade-test
description: How to prove a SwiftData model change is a lightweight migration in RyftTests — old @Model classes nested in a private enum, a store at a temp URL, reopened with TrainStore.schema
metadata:
  type: project
---

On 2026-10-26 (A2 round 2) review asked that `sentAt` be added to `LocalActivity`/`LocalManualSleep` only if the change
is lightweight, "proven by a schema-upgrade test". No such test existed (N-7 had been a device check), so I wrote
`RyftTests/Activities/ActivitySchemaUpgradeTests.swift`:
- the A1 models copied as `@Model` classes nested in a `private enum ActivitySchemaA1` (the entity names stay
  `LocalActivity` etc., and they don't clash with the app module's classes);
- a `ModelContainer` over just those (plus the unchanged `ActivityTrackChunk`) with `ModelConfiguration(schema:url:)`
  at a temp folder, insert rows, save, let it go out of scope;
- reopen the same URL with `TrainStore.schema`: rows are all there, and the new optional attribute reads nil and saves.
Passed on the iOS 27 simulator with no migration plan: SwiftData infers a lightweight migration.

**Why:** a store that won't open falls back to memory (`isDurable == false`), so a schema mistake loses unsent rows.

**How to apply:** for any later change to the activity models (A3b–A6), extend this test with a new nested old schema
instead of relying on a device check alone. Related: [[project-swiftdata-group-container]].
