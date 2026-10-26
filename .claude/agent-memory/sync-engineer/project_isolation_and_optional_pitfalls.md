---
name: project-isolation-and-optional-pitfalls
description: Swift 5.10 pitfalls hit in P2 — MainActor values in default arguments fail; `await self?.f() ?? fallback` turns f's nil (open gate) into the fallback
metadata:
  type: project
---

Two compile/logic traps from P2 (2026-10-26), both cost a build or a test cycle:
- **Default arguments are evaluated nonisolated** under this project's settings: `init(persistence: TrainStore = TrainStore(inMemory: true))`
  or `func f(status: APIStatus = .shared)` on a `@MainActor` type fails ("call to main actor-isolated initializer in a
  synchronous nonisolated context"). Use an optional parameter and `?? .shared` / `?? TrainStore(inMemory: true)` in
  the body (the pattern ProfileViewModel already uses).
- **Optional chaining flattens:** for `gate: () -> UploadGate?`, `await self?.gate() ?? .gate(.consentRequired)`
  maps both "self gone" and "gate open (nil)" to the fallback, closing every page. Write
  `guard let self else { return fallback }; return await self.gate()`.

**Why:** the second one passed the strict build and only showed as four sync tests holding at consent.

**How to apply:** any closure that forwards an Optional-returning gate or lookup through `[weak self]`. Related:
[[project-sync-machine-silent-edges]].
