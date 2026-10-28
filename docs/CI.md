# CI/CD

GitHub Actions. `ios.yml`'s macOS jobs (Lint, Build/unit/UI smoke, Contract) run on the
self-hosted Mac (`[self-hosted, macOS, ARM64]`, see below), and its `Changes` job runs on
`ubuntu-latest`, which is free for a public repository. The TestFlight and CodeQL workflows
still use GitHub's `xcode-27` runner.

The Xcode version is pinned in `.xcode-version` (27.1). `scripts/select-xcode.sh` finds an
`/Applications/Xcode*.app` with that version: `Xcode_<version>.app` on GitHub's images,
`Xcode.app` on the Mac. Jobs export it as `DEVELOPER_DIR` rather than running
`sudo xcode-select`. If no installed Xcode matches, the job stops with a list of the
installed ones. Then install it, change `runs-on`, or update `.xcode-version`.

| Workflow | When | What |
| --- | --- | --- |
| `ios.yml` | every PR, every push to `main`; 00:30 UTC nightly, or manually | `make lint` (strings), `make style` (SwiftFormat, SwiftLint), build-for-testing with warnings as errors, test plans `Unit` + `UISmoke` (nightly: `Full`), coverage floor, API contract |
| `nightly.yml` | 01:00 UTC daily, or manually | archive `main`, upload, TestFlight group **Internal**; skipped when nothing landed since the last build. A manual run takes optional `notes` (max 4000 characters, English block then German: the script sends one text to `en-US` and `de-DE`) instead of the commit list: `gh workflow run nightly.yml -f notes="$(cat notes.txt)"` |
| `weekly.yml` | Mondays 07:00 Europe/Berlin, or manually | the newest processed build to group **External**, with the week's commits as What to Test (a manual run can pass `notes` as in `nightly.yml`), submitted for beta review |
| `release.yml` | a push to `main` that changes `VERSION` (a merged `make release` PR) | tag `vX.Y.Z` on that commit, archive the tag, upload, group **Internal**; see [Versions](#versions-and-build-numbers) |
| `_testflight.yml` | called by nightly and release | the shared archive → upload → distribute job |

## The self-hosted Mac
- **Registration.** The runner must be registered to *this* repository (Settings → Actions →
  Runners). A runner registered to `ryft-platform` doesn't serve it. Until one is online,
  the macOS jobs wait in the queue, and so do the required checks.
- **Forks.** The repository is public, and a fork's code must never run on a machine that
  holds the account's files. Two settings keep it off:
  - The real protection is Settings → Actions → General → "Fork pull request workflows from
    outside collaborators" → **Require approval for all outside collaborators**. A fork's
    pull request runs the workflow file from its own branch, so it could edit `runs-on`
    back to the Mac. Approve a fork's run only after reading its changes to `.github/`.
  - The `runs-on` expression in `ios.yml` sends an unmodified fork's jobs to `xcode-27`, so
    approving a harmless fork PR never puts it on the Mac.
- **One job at a time.** Lint, the tests and the contract check run one after another, and
  so do runs for different PRs. A second runner on the same Mac (its own directory and
  service) would run two jobs at once.
- **Awake for the nightly.** The 00:30 UTC run waits until the Mac is awake.
- **Its simulator.** `scripts/ci-simulator.sh` creates "RYFT CI" in the Mac's own simulator
  set and reuses it.
- **Load.** Builds on the Mac compete with whatever else it is doing. The test time limits
  (60 s per unit test, 3 minutes per UI test) were set for GitHub's runners.

## PR checks (`ios.yml`)

- **Strings:** `scripts/lint-strings.py` requires English and German to be complete
  and nothing stale.
- **Style:** `.swiftformat` is a small rule set the code already follows
  (`swiftformat --lint .`; `make format` applies it). `.swiftlint.yml` fails only on
  errors, and the disabled rules each have a reason in the file. To widen either one,
  use its own commit: enable the rule, run `make format`, and commit the result.
- **Build:** `xcodebuild build-for-testing` without signing, with
  `RYFT_STRICT_WARNINGS=YES`. That switch (in `Config/Production.xcconfig`, which only
  our targets see) sets `SWIFT_TREAT_WARNINGS_AS_ERRORS`. Passing that setting on the
  command line directly would also reach the Swift packages, which build with
  `-suppress-warnings` and reject both flags together. The step also fails if the log has any
  warning in `Ryft`, `RyftTests`, `RyftUITests` or `RyftWidgets` (asset catalogs,
  scripts); package warnings don't count.
- **Tests:** `test-without-building -testPlan …` with the plans in `TestPlans/`
  (the scheme references all three; `Unit` is the default, and `make test` uses it):

  | Plan | Runs | Settings |
  | --- | --- | --- |
  | `Unit` | PRs, `main` | `RyftTests` without `PerformanceTests`; parallel, random order, 60 s per test, coverage of the `Ryft` target only |
  | `UISmoke` | PRs, `main` | `RyftUITests/StoreSmokeUITests` (demo mode, no server or HealthKit); a failing test is retried up to twice |
  | `Full` | nightly, manual | every unit and UI test plus `PerformanceTests` |

  - Swift Testing parallelism is capped at 4 tests in flight (`Unit` and `Full`,
    `environmentVariableEntries` → `SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH`). Uncapped,
    it starts every test (about 1,800) at once, and the ones marked `@MainActor` (most) queue
    on the one main actor: a test polling with `eventually` waits behind the whole backlog on
    every hop, so on a runner where that backlog took 30+ s the waits timed out and some tests
    hit the 60 s cap (2026-10-23 to 26). The cap is "experimental" in Xcode 27.1; if a newer Xcode
    ignores it, the flake returns as `await eventually { clock.pendingSleeps == 1 }` failures.
  - the simulator comes from `scripts/ci-simulator.sh`: a device of its own, "RYFT CI",
    created on the newest iOS runtime (`$SIMULATOR`'s type, default iPhone 17 Pro, else
    the newest iPhone) and reused when it exists. A fresh device has no paired Apple
    Watch: parallel testing clones the device, and cloning a paired one fails on runner
    images without the watchOS runtime. It is booted before the tests start.
  - on failure (and always for `Full`) the `.xcresult` bundles are uploaded as
    artifacts
- **Coverage:** `scripts/coverage.py` reads `xccov`'s report of the `Unit` run, writes
  a table to the job summary and fails when an area falls below its floor in
  `scripts/coverage-floor.json`. The areas are `Networking/`, `Sync/`, `Persistence/`
  and `Features/*ViewModel*`. The floors were set on 2026-10-20 at the measured value
  minus 2 points (78.1, 72.1, 92.8, 65.0 → 76.1, 70.1, 90.8, 63.0). Raise a floor in
  the PR that raises coverage for good. Never lower one to get a PR through.
- **Performance:** `RyftTests/PerformanceTests` (XCTest, `XCTClockMetric` +
  `XCTMemoryMetric`) decodes 90 days of `DayDetail`, builds and encodes one full
  20 000-record sync page, and decodes cached reads (a `DayDetail`, 50 workouts) in the
  shape the read-model cache stores them. It runs only in `Full`; compare the numbers
  across nightly result bundles.
- **Contract:** `scripts/contract/run.sh` checks out `timkrebs/ryft-platform`'s
  `docs/API.md`. `extract.py` pulls each response example out by its heading
  (the `MAP` table) and expands API.md's shorthand: `…`, `[ X, … ]`, and type
  placeholders, which are filled in from that type's own example. `main.swift` is compiled with
  `Ryft/Networking/Models.swift` (and the `DateParsing.swift` it uses) and decodes every example with the app's decoder
  settings. It runs on PRs that touch `Ryft/Networking/` or `scripts/contract/`, and every
  night, so a platform-side contract change fails here the next morning. To cover a
  new endpoint, add a row to `MAP` and a line to `types` in `main.swift`.

## Signing: `-allowProvisioningUpdates` with the ASC API key

The choice is automatic signing with an App Store Connect API key, not fastlane match:
- The project already uses automatic signing (team `M77SKHKG63`).
- There's no certificates repository or passphrase to maintain, and no Ruby toolchain.
- The app's dependency rule (only `supabase-swift`) stays intact.

`xcodebuild archive` and `-exportArchive` get `-allowProvisioningUpdates`,
`-authenticationKeyPath`, `-authenticationKeyID` and `-authenticationKeyIssuerID`. With
these, Xcode creates or renews the distribution certificate and profiles in the cloud.
`scripts/ExportOptions-upload.plist` (`destination: upload`) sends the build straight to
App Store Connect.

### Secrets (Settings → Environments → `internal-testflight` and `external-testflight`)

Each environment holds the same three secrets; `external-testflight` asks for approval per run.
Set them with `gh secret set <NAME> --env <environment>` (it prompts for the value).

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | Key ID of an App Store Connect **Team** API key with the **Admin** role. The export signs with Apple's cloud-managed distribution certificate, which an App Manager key may not use ("Cloud signing permission error", 2026-10-26) |
| `ASC_ISSUER_ID` | Issuer ID (App Store Connect → Users and Access → Integrations) |
| `ASC_KEY_P8` | The contents of `AuthKey_<id>.p8`, including the BEGIN/END lines |

Nothing else is secret. `Config/Production.xcconfig` (API URL, Supabase URL,
publishable key) is committed on purpose, and `make config` builds the local
xcconfigs from the examples.

### App Store Connect setup (once)

1. Apple Developer Program membership, and the app record for `dev.timkrebs.ryft`.
2. Two TestFlight groups:
   - **Internal**: App Store Connect users.
   - **External**: testers by email or public link; it needs Test Information, i.e.
     a beta description, feedback email and privacy URL.
3. The API key above.

## Versions and build numbers

- **Build number** (`CURRENT_PROJECT_VERSION`): the UTC build time,
  `yyyyMMdd.HHmmss` (e.g. `20261020.094512`), from `scripts/build-number.sh`. CI and
  `make archive` use the same script, so the number only goes up whichever side
  uploads: no counter to share, no App Store Connect lookup. App Store Connect compares
  the two parts as integers, and keeping them small avoids tools that choke on a 14-digit
  number. Each uploaded build is tagged `build/<number>`.
- **Marketing version** (`MARKETING_VERSION`): the committed `VERSION` file, passed on
  the xcodebuild command line, so the pbxproj isn't edited. It changes only through a
  release PR, because `main`'s ruleset takes nothing else (a PR, linear history, the checks
  `Lint`, `Build, unit tests, UI smoke` and `PR title`, no bypass):
  1. **Start, on your Mac:** from a clean, up-to-date `main`,
     `make release BUMP=patch|minor|major` (or `make release VERSION=X.Y.Z`).
     `scripts/release.sh` computes the version (it must be above `VERSION`), refuses if the
     tag `vX.Y.Z` or the branch exists, and creates `release/vX.Y.Z` with `VERSION` raised and
     `CHANGELOG.md`'s Unreleased entries moved under `## [X.Y.Z] - <date>`. It pushes the branch
     and opens the PR `release: X.Y.Z` with your `gh` login. `DRY_RUN=1` shows the commit and the
     PR text, then puts `main` back without pushing.
  2. **Checks and merge:** the PR runs the required checks because a person opened it. A PR
     opened by a workflow with `GITHUB_TOKEN` starts no workflows, so its checks would never
     run; that's why the first half stays on your Mac. Merge it like any other PR (squash).
  3. **After the merge:** `release.yml` runs on the push to `main` that changed `VERSION`. It
     refuses a version that isn't a raise (a reverted release PR) and a `vX.Y.Z` tag on another
     commit, tags the merge commit, and calls `_testflight.yml` for that tag: group **Internal**,
     What to Test "RYFT X.Y.Z" plus the commits since the previous `v*` tag. A re-run finds its
     own tag and carries on. The tag push uses `GITHUB_TOKEN`, as the `build/<number>` tags do.
  - It shares the concurrency group `testflight` with the nightly, so it waits for an upload
    in progress.
  - A hotfix from a `release/X.Y` branch isn't covered yet: `release.yml` only watches `main`.
- `make archive` (local) reads `VERSION` and uses the same build-number script.

## TestFlight distribution (`scripts/testflight.py`)

The script uses only the Python standard library; `openssl` signs the ES256 JWT.

- `distribute --build N --group NAME [--notes FILE] [--external]`:
  1. waits until build N has processed (`VALID`, up to 60 min)
  2. sets What to Test in `en-US` and `de-DE`
  3. adds the build to the group, except an internal group with "access to all builds": App Store
     Connect adds every build there itself and refuses a manual assignment, so the script logs
     "Internal gets every build automatically" and moves on
  4. with `--external`, submits it for beta review (an existing submission is fine)
- `latest-build` prints the newest processed build number.
- `--self-test` checks the internal-group logic offline.

**Weekly notes:** the commits between the tag `testflight-external` (the last external
build) and `build/<number>`. After distributing, the tag moves.

**The 07:00 Berlin schedule:** GitHub cron runs in UTC. `weekly.yml` is scheduled at
05:00 and 06:00 UTC, and its first step continues only when it's 07 in Europe/Berlin.
That's one run in summer (CEST) and one in winter (CET).

## Runbook

- **A nightly didn't arrive:**
  - the `changes` job skips when there were no new commits
  - check the run's Archive and upload step
  - a build stuck in processing times out after 60 min in Distribute
- **External group, first build:** Apple's beta review takes about a day. Later builds
  of the same version usually pass at once.
- **Re-run the weekly by hand:** Actions → Weekly external TestFlight → Run workflow
  (skips the hour check).
