# Product analytics, PostHog, opt-in (A1), phase 1 (2026-11-20)

Brief: the App Attest follow-up and PostHog analytics (PR 2 of 2). Contract: platform D231 (platform PR #191),
`GET /v1/config` → `flags["analytics.enabled"]`, `analytics`. The user's decisions of 2026-11-16 are binding.
Design: `design.md` (ios-architect), `ui.md` (ui-designer). Branch `feat/analytics-posthog` from `origin/main`, opened as
a **draft** PR. Phase 2 (a follow-up session): the SDK adapter, `PrivacyInfo.xcprivacy`, the new ADR, `CLAUDE.md` →
Rules, `docs/APP_STORE.md`.

## Tickets

| # | What | Owner | Depends on |
|---|---|---|---|
| T0 | Design note; UI spec | ios-architect; ui-designer | — |
| T1 | Phase 1: config field, flag, `Ryft/Analytics/` (gate, owner, events, no-op sink), call sites, sheet, row, strings | ios-developer | T0 |
| T2 | Tests from design.md's list with a fake sink | test-engineer | T1 |
| T3 | Review: code-reviewer; security-privacy-reviewer | reviewers | T1, T2 |
| T4 | The exact Xcode step for the user (package URL, version, target) | ios-lead | — |

## Acceptance criteria (each one a test)
1. No event before the opt-in, after a decline, with the flag off, with `analytics` null, in demo mode.
2. All three hold → events go to the newest config's host and key.
3. When any of the three stops holding: stop and drop what's queued, at once (the newest answer, not the shown one).
4. Opt-out and sign-out reset the analytics id.
5. Every property value is on the allow-list (closed enums, booleans, buckets); no event can carry a `String`, a
   number or a date.
6. The project key never appears in a description, a dump or a log.
7. Previews, tests, demo mode and the simulator use the no-op sink; the app compiles without the SDK.
8. Zero warnings; CI green.

## Risks
- `onboarding_step`, `health_access_requested` and often `first_sync_completed` rarely fire: the opt-in comes after the
  onboarding and nothing is buffered before consent (design.md, "What could go wrong"). The user's call.
- Sign-out clears the opt-in answer (design.md §10), beyond the brief's "reset the id". Flagged for the user.
- PR #127 (nocturne) touches Profile and the tab bar: our edits there are single separable lines.
- `RemoteConfig` and its fixture are shared with PR 1: PR 1 owns the fixture; this PR adds only `analytics`.
