# RYFT app — instructions for Claude Code (Xcode)

You are the **app agent** for RYFT, working inside Xcode. The platform (Go services,
API) is built by a separate agent in VS Code under `../plattform`; you never edit files
there. Its API contract is `../plattform/docs/API.md` — read it at the start of every
session.

## What this folder is
`Ryft.xcodeproj` exists and carries the development team and the supabase-swift package;
it is the source of truth. Change targets, capabilities and packages in Xcode itself —
do not regenerate with xcodegen (it would drop those settings) and do not edit the
pbxproj by hand. `project.yml` is kept only as documentation of the original setup. Sources in `Ryft/`:
`App/` (entry, state, settings), `Auth/` (Supabase), `Design/` (theme, components),
`Features/<Tab>/`, `Health/` (HealthKit), `Sync/`, `Networking/`, `Preview/` (mock data),
`Resources/` (fonts, strings). The visual spec is `design/brand-board.png`. The roadmap
is `../ROADMAP.md`; the user pastes one milestone per session.

## Rules
- Swift 5.10, SwiftUI, iOS 17+, async/await, Swift Charts. Dependencies: only
  `supabase-swift`. Dark theme first; palette and type live in `Design/Theme.swift`.
- Wire models in `Networking/Models.swift` mirror `docs/API.md` exactly (snake_case via
  the shared decoder). For every new shape add a fixture-decoding test using the JSON
  example from `API.md`. If you need data the API does not provide, write the request
  into `docs/API_REQUESTS.md` — do not invent fields.
- Keep the sync design: anchored HealthKit queries, page → upload → persist anchor,
  background delivery, `BGAppRefreshTask`. Extend `HealthKitManager` only for new types.
- Every screen and component gets a `#Preview` with mock data in dark and light.
  **Before committing UI, capture the Previews and compare with the brand board**
  (hierarchy, spacing, colours, the orbit mark). Fix what differs, then commit.
- Build must succeed with zero warnings in our code; HealthKit only works on a device,
  so previews and the simulator must work from `Preview/MockData.swift` without a server.
- Accessibility: dynamic type, VoiceOver labels on rings and charts, reduced motion.
  Strings go through `Localizable.xcstrings` (en, de) from milestone M5 on.
- Never put keys in Swift: Supabase URL/anon key come from git-ignored xcconfig files.
- End each session with `docs/STATUS.md` (done / open / blocked-on-Apple-or-Supabase
  config) and a commit per milestone.

## Workflow
Build → run in simulator → open the Preview of the changed view → capture → compare →
iterate. Device test for HealthKit, push and Sign in with Apple; note in STATUS.md what
was only simulator-verified.
