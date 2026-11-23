# Reviews: the first run (PR 2) and Apple Health by group (PR 3)

## PR 3, #144 (`feat/health-groups`), round 1 (2026-11-23)

### code-reviewer: no blockers
| # | Severity | Finding | Owner | Status |
|---|---|---|---|---|
| C1 | should-fix | `RyftApp.swift:470/:121`: after Not now, a later Allow (Profile, Devices, Check sync) records `core` but doesn't re-run `observeHealthKit` or start a sync; `BootstrapKey` is unchanged, so background delivery and the first sync wait for a relaunch or the next foreground | sync-engineer | fixed (round 1) |
| C2 | should-fix | `OnboardingSteps.swift:556`: `.filled` shown as `.askedBefore` on a re-shown step, and `fillingFromHealth`/`onChange`, are untested | sync-engineer | fixed (round 1) |
| C3 | should-fix | `HealthStore.swift:543`: the mock's `asked` is one set for all accounts, so the per-account path through the seam is untested | sync-engineer | fixed (round 1) |
| C4 | nit | `HealthPermissionGroup.reason` strings have no catalog comment | sync-engineer | fixed (round 1) |
| C5 | nit | `MockBirthYearPrefill.swift:47`: one persistent defaults suite shared by previews and tests | sync-engineer | fixed (round 1) |
| C6 | nit | §9 test 12 ("no analytics event carries a year") has no test | sync-engineer | fixed (round 1) |

### security-privacy-reviewer: no blockers
| # | Severity | Finding | Owner | Status |
|---|---|---|---|---|
| S1 | should-fix | `Makefile:96`: `check-date-of-birth` matches only `dateOfBirthComponents`; `dateOfBirth()` and `HKCharacteristicType(.dateOfBirth` would pass lint | sync-engineer | fixed (round 1) |
| S2 | note | Shared phone: HealthKit grants are per install, so account B inherits A's grant (core and about). ADR 0027 should say the record means "asked in RYFT", not "granted by this person" | sync-engineer | fixed (round 1) |
| S3 | note | `docs/APP_STORE.md:103,154` still list Associated Domains (older drift, not this PR) | — | later |

Checked and sound (both reviewers): `core` is unchanged (types, observers, paging); there's no sheet after Not now on any path; the asked record is per account and wiped only on deletion; only the year reaches the view, and nothing is sent before Continue; the merge with #141 is clean; no entitlement or pbxproj change.

For the user: the privacy policy (ryftlab.de) should say the birth year can come from Apple Health's date of birth, on tap, and that only the year is kept. Legal should confirm the basis. App Store Connect needs no change.
