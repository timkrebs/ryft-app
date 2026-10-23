---
name: ryft-app-conventions
description: The RYFT iOS app's non-negotiable conventions — project layout, contract with the platform, concurrency, strings, design, signing, git. Preloaded by every RYFT app agent; read it before changing anything in app/.
---

# RYFT iOS — conventions every agent follows

`CLAUDE.md` is the source of truth; this is the condensed working set. If they disagree, `CLAUDE.md` wins
and you report the drift.

## Where things are
- `Ryft/App` entry, state, settings · `Auth/` Supabase · `Environment/` seams (`AppEnvironment`,
  `PlatformAPI`, `HealthStore`, `AppClock`, flags) · `Health/` HealthKit · `Sync/` engine, coordinator,
  background work · `Networking/` `APIClient`, `Models.swift` (wire mirror), status · `Persistence/`
  SwiftData read models + `Repository` · `Features/<Tab>/` views + `@Observable` view models ·
  `Design/` theme, components, `ChartStyle` · `StateMachines/` · `Preview/` mock data ·
  `Resources/` fonts, `Localizable.xcstrings`.
- Tests: `RyftTests/` (Swift Testing + XCTest), `RyftUITests/`. Test plans `Unit`, `UISmoke`, `Full`.
- `Ryft/`, `RyftTests/`, `RyftWidgets/` and `RyftUITests/` are synchronized folders (all four since 2026-10-23, #39):
  a new file belongs to its folder's target with no project-file edit, so new types get their own files. Every non-Swift
  file in `Ryft/` is copied into the app bundle; keep notes and drafts out of it (Xcode excludes only `Info.plist` and
  `Resources/Fonts/.gitkeep`). A file that both the app and the widget compile needs a second target membership, set in
  Xcode (a user step); until then such types stay duplicated and `scripts/check-shared-types.py` keeps them identical.
- Docs: `docs/STATUS.md`, `docs/ARCHITECTURE.md`, `docs/API_REQUESTS.md`, `docs/CHART_STYLE.md`,
  `docs/CI.md`, `docs/RELEASING.md`, `docs/APP_STORE.md`, `CHANGELOG.md`.

## Hard rules
1. **Never edit** `Ryft.xcodeproj/project.pbxproj` or `*.entitlements` by hand. Capabilities go through
   the user in Xcode (+ Capability); print the exact steps. Build settings that must change: ask.
2. **Never write in `../plattform/`.** The contract is `../plattform/docs/API.md`; mirror it exactly in
   `Networking/Models.swift` (snake_case via the shared decoder), one fixture-decoding test per shape from
   the JSON examples. Missing data → `docs/API_REQUESTS.md`, never invented fields.
3. **The phone computes no scores.** It shows what the platform returns; raw HealthKit totals may be shown
   only when labelled as unscored.
4. **Dependencies:** only `supabase-swift`. No analytics, crash or tracking SDKs.
5. **Concurrency:** UI state is `@MainActor @Observable`; HealthKit reading, mapping, JSON encoding and
   uploads never run on the main actor (the target uses approachable concurrency — nonisolated async runs
   on the caller's actor; use an actor or `@concurrent` for heavy work). No `Task.detached` without a
   reason in a comment.
6. **Errors:** status handling per `API.md` → Errors: `401` refresh once then sign out; `403` with
   `code` routes to the invite/consent gate; `429`/`503` honour `Retry-After` and never sign out; keep the
   request ID in every user-visible error's Details. Never "log in again" for anything but a final `401`.
7. **Strings:** every user-facing string in `Localizable.xcstrings`, English and German (du-form), complete
   (`make lint`). Never the name of another wearable brand as a comparison; data sources (Apple Health,
   Garmin Connect, Oura …) only factually.
8. **Design:** colours, type and spacing only from `Design/Theme.swift` / `Typography.swift` /
   `ChartStyle`; dark first, light complete; contrast ≥ 4.5:1; Dynamic Type to AX3; VoiceOver labels on
   gauges and charts; reduced motion respected. Every view has `#Preview`s in dark and light with mock data.
9. **Honest states:** never a blank screen or a blocking spinner; pending, calibrating, offline, stale and
   gated states say what is happening and what (if anything) the user can do.
10. **Git:** branch `feat|fix|chore|test|docs|ci/…` from fresh `main`, PR with `gh pr create --fill`,
    title `area: what changed`, CI green, squash. Never commit to `main`, never force-push. User-visible
    change → line in `CHANGELOG.md` → Unreleased. Session end → `docs/STATUS.md`.

## Commands
- Build: `xcodebuild -scheme Ryft -destination "$(sh scripts/ci-simulator.sh)" build`
- Tests: `… test -testPlan Unit` · `-testPlan UISmoke`
- Lint/style: `make lint` (strings, entitlements) · `make style` · `make format`
- Screenshots: `make screenshots` · `xcrun simctl io booted screenshot <file>`
- If the simulator can't launch in your sandbox, say so and rely on CI (`gh pr checks --watch`).
