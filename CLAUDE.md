# RYFT app — instructions for Claude Code (Xcode)

You are the **app agent** for RYFT, working inside Xcode. The platform (Go services,
API) is built by a separate agent in VS Code under `../plattform`; you never edit files
there. Its API contract is `../plattform/docs/API.md` — read it at the start of every
session.

## What this folder is
`Ryft.xcodeproj` exists and carries the development team and the supabase-swift package;
it is the source of truth. Change targets, capabilities and packages in Xcode itself —
and do not edit the pbxproj by hand. Sources in `Ryft/`:
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
- Signing: capabilities are added only through Signing & Capabilities → + Capability,
  never by editing `Ryft.entitlements` by hand, and every key in it must have a matching
  capability (`make check-entitlements`, part of `make lint`). No `associated-domains` key
  until the AASA on ryftapp.de lists the app's paths — an empty array once stopped iOS from
  launching the app.
- Never put keys in Swift: Supabase URL/anon key come from git-ignored xcconfig files.
- End each session with `docs/STATUS.md` (done / open / blocked-on-Apple-or-Supabase
  config) and a commit per milestone.

## Workflow
Build → run in simulator → open the Preview of the changed view → capture → compare →
iterate. Device test for HealthKit, push and Sign in with Apple; note in STATUS.md what
was only simulator-verified.

## Git: branches and pull requests (never push to `main`)
`main` is protected and always releasable (`docs/RELEASING.md`). Every session:
1. Starts from an up-to-date `main` on a short branch: `feat/…`, `fix/…`, `chore/…`,
   `ci/…`, `docs/…`, `test/…`, or `release/X.Y` for a hotfix.
2. Commits there, pushes, and opens a PR with `gh pr create --fill`. The **PR title** is
   the squash commit (`area: what changed`, checked by `pr-title.yml`).
3. Waits for the required checks (`gh pr checks --watch`) and fixes until they're green.
4. Asks the user to merge, or runs `gh pr merge --auto --squash` only if he said so for
   that session.

Never commit to `main` directly, never force-push, never bypass the ruleset. An
unfinished feature ships dark behind a remote flag (`GET /v1/config`), not on a
long-lived branch. Add a line to `CHANGELOG.md` → Unreleased for anything users notice.
