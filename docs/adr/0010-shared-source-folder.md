# 0010 — One `Shared/` folder for code the app and the widget both compile

- Status: proposed (2026-10-29, OrbitGauge 1b, `docs/work/2026-10-29-orbit-gauge/architecture.md`)
- Deciders: ios-lead, on ios-architect's proposal; the user performs the one Xcode step
- Applies to: `Shared/` (new, repo root), `scripts/check-shared-types.py`, `.swiftlint.yml`, `.github/workflows/ios.yml`,
  `RyftWidgets/Assets.xcassets`

## Context

The app and the widget extension share types by copy: `ReadinessSnapshot`, `RestTimerAttributes`, `OpenWorkoutIntent`
and `WakeAlarmMetadata`. `check-shared-types.py` keeps them identical. Copying was chosen because a second target
membership is a project-file change, `project.pbxproj` is never hand-edited, and agents cannot drive Xcode. That worked
for small Codable shapes. The OrbitGauge needs a model, geometry and a SwiftUI drawing that must render identically in
both targets. Copying a drawing means every change twice and a checker comparing whole files.

All four folders are synchronized roots (#39). Once a synchronized folder belongs to both targets, every file added to it
later is compiled by both, with no further project edits.

## Decision

- A top-level `Shared/` synchronized folder, members **Ryft** and **RyftWidgetsExtension** (not the test targets: they
  see it through `@testable import Ryft`). Added once by the user in Xcode.
- `Shared/` holds Swift only. Allowed imports: Foundation, CoreGraphics and SwiftUI only. No user-facing strings
  (each target's catalog owns its copy; wrappers add text and accessibility). No fonts. No `Theme`, no app types. Colours
  by asset name, with the colorsets copied into the widget catalog. The checker compares those colorsets and rejects
  strings in `Shared/`.
- New types both targets compile go into `Shared/`, not into copies. `ReadinessSnapshot` moves now (its shape changes
  anyway). The other three move when next touched: `OpenWorkoutIntent` and `WakeAlarmMetadata` are matched by the
  system by name/shape, and a move doesn't change that. Each move removes its checker rule.

## Consequences

- One source for shared code; parity holds by construction. Tests of shared code live in RyftTests (there is no widget
  test target, and none is needed for this).
- One Xcode step per new shared *folder*, never per file.
- Shared code compiles under the stricter of both targets' settings. Widget memory limits apply to anything shared:
  keep it value types and drawing.
- Tooling that lists source folders (`.swiftlint.yml` `included`, the zero-warnings grep in `ios.yml`) must list
  `Shared` too.
- Fallback if the step is impossible: byte-identical copies, whole-file comparison in the checker (the old pattern,
  scaled up).
