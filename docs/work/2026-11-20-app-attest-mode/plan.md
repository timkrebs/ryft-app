# App Attest follow-up: X-RYFT-App-Build and the mode from the config (2026-11-20)

Brief: the App Attest follow-up (PR 1 of 2). Contract: platform D247 (platform PR #227, merged 2026-11-20), API.md →
Conventions → App Attest, App build, `GET /v1/config` → `app_attest`. Answers `docs/API_REQUESTS.md` → App Attest AA1–AA4.
Design: `design.md` (ios-architect). ADR 0023 updated.

Branch `feat/app-build-header` from `origin/main`. One PR: "networking: X-RYFT-App-Build, and the App Attest mode from
the config".

## Tickets

| # | What | Owner | Depends on |
|---|---|---|---|
| T0 | Design note, ADR 0023 update | ios-architect | — |
| T1 | `X-RYFT-App-Build` on every request; `RemoteConfig.appAttest`; the mode reaches `AppAttestor`; `off`/`warn`/`on`/absent | sync-engineer | T0 |
| T2 | Tests from the acceptance criteria below; fixture `remote_config` = API.md's example | test-engineer | T0 (interfaces), T1 |
| T3 | `docs/API_REQUESTS.md` AA1–AA4 answered; `CHANGELOG.md` | ios-lead | T1 |
| T4 | Review: code-reviewer; security-privacy-reviewer (networking, headers) | reviewers | T1, T2 |

## Acceptance criteria (each one a test)

1. Every request to api and ingest carries `X-RYFT-App-Build: <CFBundleVersion>`: foreground, background session,
   `singleAttempt`, `POST /v1/sync` (ingest), the three App Attest routes, the exempt routes, and each retry.
2. A build value that fails `^[0-9]+(\.[0-9]+){0,3}$` or is over 24 characters is never sent (no header).
3. `RemoteConfig` decodes `app_attest` `"off"`, `"warn"`, `"on"`, absent, `null` and an unknown string; none fails the
   decode; unknown and `null` read as absent.
4. Mode `off`: no `POST /v1/app-attest/challenge`, no key generated, no 3 s first-token wait.
5. Mode `warn` and `on`: attestation runs as before.
6. Mode absent: today's behaviour (probe; `404`/`501` → 6 h not-served pause).
7. `501` (or `404` without a `code`) from the challenge under `warn`: not served, no header (the route stays
   authoritative).
8. Cached `off`, then `403 app_attest_required`: one renewal and one retry (the server went `on`).
9. An account switch or sign-out forgets the mode (back to absent).

## Risks
- The mode must be known at a background launch (from the cached config) before the first request.
- Shared files with PR 2 (`Models.swift` → `RemoteConfig`, the fixture): PR 1 sets the fixture to API.md's full example
  so PR 2 only adds `analytics`.
- The Mac is the CI runner: targeted suites only while `xcodebuild` or CI runs.
