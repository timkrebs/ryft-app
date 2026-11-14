# Plan: the domain moves to ryftlab.de (hard cut), 2026-11-14

Brief: from the head-architect, 2026-11-14. Owner: ios-lead.

`ryftlab.de` replaces `ryftapp.de` everywhere, with no fallback:
- API `https://api.ryftlab.de`
- `https://ryftlab.de/{privacy,terms,support}`
- `https://ryftlab.de/trackers.json`
- contact `support@ryftlab.de`

Only the base URL changes. No fields change, so there is no API-contract work.

**State of this plan:** written first in a headless run that couldn't create branches, commit or build. Implemented later the same day, once the permissions were widened:
- T1 by sync-engineer;
- T2 by ios-lead (a 6-line change, too small to hand off);
- T3 by ios-lead.

Deviation: `.claude/agents/security-privacy-reviewer.md:39` keeps `ryftapp.de/privacy`. Agent definitions can't be edited from a session, so it goes with the next fleet-config PR.

## Order
0. Fleet config (`.claude/**`) → `chore/fleet-config-2026-11-14`, PR, no merge. Back to `main`.
1. `chore/domain-ryftlab` from an up-to-date `main`.
2. T1 and T2 in parallel (separate files). T3 after them.
3. Verify (below), then PR `app: domain ryftlab.de (hard cut)`. No merge, no attribution.

No ios-architect note: this changes host constants and comments only, and nothing structural in `Environment/`.

## T1: code, config, tests (sync-engineer)
Replace `ryftapp.de` with `ryftlab.de`; the paths stay. Files:

| Area | Files |
| --- | --- |
| Config | `Config/Production.xcconfig:13`: `RYFT_API_URL = https:/$()/api.ryftlab.de`. The `.example` files have no domain. |
| App | `RyftApp.swift:296` (comment); `SupabaseConfig.swift:31–34`: `universalRedirectURL` → `https://ryftlab.de/auth/callback`, comments `applinks:ryftlab.de`. **`redirectURL` stays `ryft://auth/callback`.** |
| Design | `SafariView.swift:12,13` (URLs), `:19` (`url.host == "ryftlab.de"`) |
| Environment | `PlatformAPI.swift:150` (`privacyPolicyUrl`); `AppEnvironment.swift:30,41`; `Seams.swift:178,199,200,256,266,304,388` (comments), `:203` (`static let host`) |
| Health | `HealthKitManager+Status.swift:29,280` (comments), `:378` (`anyHelpHost`) |
| Navigation | `AppRoute.swift:5` (comment), `:37` (`static let host`; `www.` keeps working through the existing rule) |
| Profile | `FeatureFlagsDebugView.swift:65` (comment); `ProfileView.swift:229` (placeholder `https://api.ryftlab.de`, not a catalog key) |
| Tests | `AccountScopeTests`, `AuthServiceTests`, `ConsentGateTests`, `DecodingTests`, `EnvironmentTests`, `MirrorDecodingTests`, `PlatformConfigTests`, `PushAndDeepLinkTests`, and the fixtures `push_alert.json`, `remote_config.json`. Rename `aRedirectWithinRyftappIsFollowed` → `aRedirectWithinRyftlabIsFollowed`. `evil.`/`www.`/`.example.com`/`:8443`/`http:` cases move to the new host. |

Don't touch: entitlements (Associated Domains stays off), signing, bundle IDs, `Models.swift`, the pbxproj.

**Done when:**
- `git grep -n -i 'ryftapp\.de'` finds nothing in `Ryft/`, `RyftTests/`, `RyftUITests/`, `Config/`.
- `xcodebuild test` (Unit plan) passes in the foreground.
- `make lint` is clean.

## T2: strings (localization-editor)
`AuthComponents.swift:202`, `CreateAccountView.swift:30–31`, `WelcomeView.swift:84`, and their three keys in `Localizable.xcstrings` (lines 1482, 4429, 6894).
- Rename only the key lines and keep their values (`{}` or the `comment` block).
- No re-serialisation, no `en` entries.
- The catalog diff is 6 lines (3 −, 3 +).

## T3: docs, STATUS, CHANGELOG (ios-lead)
- **Change:** `README.md`, `SECURITY.md`, `CLAUDE.md:36`, `CLAUDE_FOLLOWUP_TRACKER_SETUP.md`, `.claude/agents/security-privacy-reviewer.md:39`, `docs/API_REQUESTS.md`, `docs/APP_STORE.md`, `docs/APP_STORE_METADATA.md`, `docs/ARCHITECTURE.md`, `docs/TESTFLIGHT.md`.
- **ADR 0002:** change it, plus one line "Amended 2026-11-14: the host is ryftlab.de", because an ADR describes current behaviour.
- **STATUS:** every open item and every statement of current behaviour moves to ryftlab.de. The dated section "Session 2026-10-23 → 26" (lines 275, 310) keeps the old name.
- **Kept as dated history:** `docs/work/2026-10-*`, `docs/work/2026-11-06-alpine/plan.md`.
- **New STATUS entry on top:**
  > **Domain: ryftlab.de (2026-11-14).** The API (`api.ryftlab.de`), the legal pages, support, `trackers.json` and universal links moved from `ryftapp.de`, which isn't served anymore (hard cut, no fallback). Older entries and `docs/work/2026-10-*` name the old domain. Simulator-verified only, until a device build talks to `api.ryftlab.de`.
- **CHANGELOG → Unreleased → Changed:** "RYFT's website, privacy policy, terms and support moved to ryftlab.de."
- **Email decisions:**
  - `security@ryftapp.de` → `support@ryftlab.de` (the only contact the brief names).
  - `review@` / `beta@` in the docs → `@ryftlab.de` only after the platform confirms the seeded demo account; until then `support@ryftlab.de` as the feedback email.

## Verify (read-only, parallel)
- **code-reviewer:** always.
- **security-privacy-reviewer:** host allowlists (web content, help links, legal pages), deep links, the redirect URL.
- **ui-validator:** one visible text, the account-hint sheet's "ryftlab.de/support".

## Remaining `ryftapp` hits after the cut
- `git grep -i ryftapp` keeps about 63 lines of the Swift type `RyftApp` (the `@main` struct and `RyftApp.swift`). That's not the domain, and renaming the entry point is out of scope.
- The domain check is `git grep -n -i 'ryftapp\.de'`.
- Not touched: open PR #100 adds one line naming ryftapp.de (`CLAUDE_FOLLOWUP_ALPINE_LIGHT.md`). #106 and #107 add none.

## TestFlight: how this build reaches testers (nothing is triggered by this PR)
- **Internal:** `nightly.yml` runs at 01:00 UTC whenever `main` moved since the last `build/*` tag. It calls `_testflight.yml` (environment `internal-testflight`, **no approval**), which archives Release with `Production.xcconfig`, uploads, and hands the build to group Internal. **So merging this PR ships it that night.** The merge is the gate.
- **External:** `weekly.yml` runs Mondays 07:00 Berlin (next: 2026-11-16), or by hand. It sends the newest processed build to group External with beta review. Environment `external-testflight` waits for approval per run.
- **What testers get:**
  - Marketing version `1.0.0` (the `VERSION` file).
  - Build number: the UTC archive time, `yyyyMMdd.HHmmss` (e.g. `20261115.01xxxx` from the first nightly after the merge).
  - Last uploads by tag: `build/20261101.071450` (Internal) and `testflight-external` → `build/20261028.103045`.
  - No `build/*` tag since 11-01 although `main` moved 20 commits, so the nightly may be failing or disabled. Unchecked: `gh run list` was refused.
- **Version bump: not in this PR.**
  - By `docs/CI.md` → Versions, `VERSION` changes only through a release PR (`make release`, `release/vX.Y.Z`, title `release: X.Y.Z`).
  - `release.yml` uploads on that merge, so a bump here would turn the merge into a second upload trigger.
  - TestFlight takes a new build number on 1.0.0, as long as 1.0.0 isn't released on the App Store.
