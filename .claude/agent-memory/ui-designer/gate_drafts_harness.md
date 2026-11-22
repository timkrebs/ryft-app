---
name: Gate draft harness
description: Rendering design drafts as a scratch hosted test (RyftTests), not committed
type: reference
---
Draft renders = a scratch `RyftTests/ZZ*.swift` Swift Testing suite: UIHostingController in a UIWindow on the test host's scene, `Color.clear.sheet(isPresented: .constant(true))` for real iOS sheet chrome, `drawHierarchy` at scale 3, env var `TEST_RUNNER_<NAME>` for the output dir. Copy kept as gate-drafts/ZZGateDrafts.swift.txt.
- Presented sheet content does NOT inherit `.environment(\.dynamicTypeSize)` from outside: set it inside the sheet closure (AX3 shots were identical to default until then).
- `DotNumeral` needs `accessibilityLabel:`; `.light` style is the fallback look, default is dots.
- Build: derived data outside the worktree (`-derivedDataPath <scratch>/dd`), `CODE_SIGNING_ALLOWED=NO`; `xcodebuild -list` in the worktree is harmless. The shared-Mac gate (no booted "RYFT CI") can hold a build 15+ minutes: write the doc meanwhile.
