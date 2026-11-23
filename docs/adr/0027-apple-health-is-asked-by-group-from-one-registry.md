# 0027 — Apple Health is asked by group, from one registry, and "asked" is a per-account record

- Status: proposed (2026-11-23, H0 of `docs/work/2026-11-23-first-run/health-groups.md`)
- Deciders: ios-lead and the user; proposed by ios-architect. sync-engineer builds it.
- Applies to: `Ryft/Health/` (new `HealthPermissionGroup`, `HealthPermissionLedger`; `HealthKitManager.readTypes`,
  `observedTypes`, `enableBackgroundDelivery`, `startObserving`, `accessStatus`), `Ryft/Environment/HealthStore.swift`
  (the seam, `MockHealthStore`), every `requestAuthorization` call site, `Info.plist` / `InfoPlist.xcstrings`
  (`NSHealthShareUsageDescription`), `AuthService.wipeSharedLocalData`, and every future feature that reads a new
  HealthKit type
- Relates to: ADR 0008 (uploads fail closed on consent; unchanged), ADR 0024 (per-account key precedent)

## Context

- RYFT reads ten HealthKit types. They are listed in four places that nothing ties together: `quantities` and
  `readTypes`, `observedTypes`, `streams`, and the usage description, which has two copies.
- Coming features need about 20 more types (Fuel, journal autofill, the physiology card). Apple's review rules and the
  GDPR want each type asked for only when a feature uses it. A short sheet also earns trust.
- HealthKit grants are per install and never reveal a refused read. Only "the sheet would still show" is visible.

## Decision

1. **One registry.** `HealthPermissionGroup` (`core`, `about`, `body`, `fuel`, `habits`, `physiology`) is the only
   place a read type is declared. It is a plain `Sendable` enum without HealthKit. Each group lists its types, a
   one-line reason, its consumer and `isRequestable`. Types map to `HKObjectType` only inside `Health/`.
2. **Asked by group, by its feature.** `requestAuthorization(_ group:)` replaces the no-argument call. `core` is asked
   by the first run, Profile and bootstrap. Every other group is asked only by its own feature, after its primer. A
   group that is not requestable throws before HealthKit is reached.
3. **"Asked" is the app's record, per account.** It is kept in `health.asked.<account>` and written by the live store
   after a request returns. It survives sign-out and is removed on account deletion. It is never written without an
   account. It decides the derived sets and the UI state, and it never replaces a request: a read is always preceded
   by `requestAuthorization(group)`.
4. **Everything derives from the record.** `readTypes`, background delivery and the observers come from the asked
   groups. `core` yields exactly today's ten types and three observers. Characteristics (`about`) have no anchor, no
   observer and no upload.
5. **A value read from a characteristic leaves the seam in its minimal form.** The seam returns the birth year
   (`Int?`), never the date.
6. **Tests guard the registry.** Each type belongs to exactly one group. Requestable groups have a consumer in code.
   The usage description names every requestable type and none that is not requestable.

## Consequences

- Shipping a new group is a single, reviewable change: flip `isRequestable`, add its consumer, its primer and its words
  in the usage description. The tests fail until all of these are there.
- Existing installs migrate without a prompt: `healthIntroDone` implies `core`.
- Two accounts on one phone share HealthKit's grant but not each other's groups. B's sync never reads a group only A
  opted into.
- Once a group with sample types ships, `streams` and the observers have to follow the record mid-session. The paging
  engine doesn't change in H0.
- Every type is declared in the registry: a new type outside it is a review finding.
