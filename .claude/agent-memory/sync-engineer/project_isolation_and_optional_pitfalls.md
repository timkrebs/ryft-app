---
name: project-isolation-and-optional-pitfalls
description: Swift 5.10 pitfalls — MainActor values in default arguments fail; `await self?.f() ?? fallback` swallows f's nil; UserDefaults captured in a @Sendable observer warns under strict
metadata:
  type: project
---

Compile/logic traps (P2 2026-10-26, P1b 2026-11-18), each cost a build or a test cycle:
- **Default arguments are evaluated nonisolated** under this project's settings: `init(persistence: TrainStore = TrainStore(inMemory: true))`
  or `func f(status: APIStatus = .shared)` on a `@MainActor` type fails ("call to main actor-isolated initializer in a
  synchronous nonisolated context"). Use an optional parameter and `?? .shared` / `?? TrainStore(inMemory: true)` in
  the body (the pattern ProfileViewModel already uses).
- **Optional chaining flattens:** for `gate: () -> UploadGate?`, `await self?.gate() ?? .gate(.consentRequired)`
  maps both "self gone" and "gate open (nil)" to the fallback, closing every page. Write
  `guard let self else { return fallback }; return await self.gate()`.
- **`UserDefaults` isn't Sendable here** (P1b review, 2026-11-18): capturing it in a `NotificationCenter` observer
  closure (`ModelContext.willSave`) is a strict-build warning (#SendableClosureCaptures). The note is posted on the
  saving thread, main for TrainStore: capture the `@MainActor` rig instead and read it in
  `MainActor.assumeIsolated { … }`. Static lets on a `@MainActor` class need `nonisolated static let` to be read there.

**Why:** the optional one passed the strict build and only showed as four sync tests holding at consent.

**How to apply:** any closure that forwards an Optional-returning gate or lookup through `[weak self]`. Related:
[[project-sync-machine-silent-edges]].
