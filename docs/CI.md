# CI/CD

GitHub Actions on macOS runners. The Xcode version is pinned in `.xcode-version`
(27.1), and every job selects `/Applications/Xcode_<version>.app`. If the runner image
doesn't have that Xcode, the job stops with a list of the installed ones. Then either
change the `runs-on` image in the workflows or update `.xcode-version`.

| Workflow | When | What |
| --- | --- | --- |
| `ios.yml` | every PR, every push to `main` | `make lint` (strings), `make style` (SwiftFormat, SwiftLint), build-for-testing with zero warnings in our code, unit tests, UI smoke |
| `nightly.yml` | 01:00 UTC daily, or manually | archive `main`, upload, TestFlight group **Internal**; skipped when nothing landed since the last build |
| `weekly.yml` | Mondays 07:00 Europe/Berlin, or manually | the newest processed build to group **External**, with the week's commits as What to Test, submitted for beta review |
| `release.yml` | manually | bump `VERSION`, commit, tag `vX.Y.Z`, archive the tag, upload, group **Internal** |
| `_testflight.yml` | called by nightly and release | the shared archive → upload → distribute job |

## PR checks (`ios.yml`)

- **Strings:** `scripts/lint-strings.py` requires English and German to be complete
  and nothing stale.
- **Style:** `.swiftformat` is a small rule set the code already follows
  (`swiftformat --lint .`; `make format` applies it). `.swiftlint.yml` fails only on
  errors, and the disabled rules each have a reason in the file. To widen either one,
  use its own commit: enable the rule, run `make format`, and commit the result.
- **Build:** `xcodebuild build-for-testing` without signing. The step fails if the log
  has a warning in `Ryft`, `RyftTests`, `RyftUITests` or `RyftWidgets` (the rule from
  CLAUDE.md); package warnings don't count.
- **Tests:**
  - `test-without-building -only-testing:RyftTests`
  - the UI smoke test `RyftUITests/StoreSmokeUITests`, which runs in demo mode and
    needs no server or HealthKit
  - the simulator comes from `scripts/ci-simulator.sh`: `$SIMULATOR`
    (default iPhone 17 Pro), else the newest available iPhone
  - on failure the `.xcresult` bundles are uploaded as artifacts

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

### Secrets (repository → Settings → Secrets and variables → Actions)

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | Key ID of an App Store Connect API key with the **App Manager** role |
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

- **Build number** (`CURRENT_PROJECT_VERSION`): the workflow run's `github.run_id`.
  Run IDs only increase, across every workflow in the repository, so nightly and
  release builds never collide. Each uploaded build is tagged `build/<number>`.
- **Marketing version** (`MARKETING_VERSION`): the committed `VERSION` file, passed on
  the xcodebuild command line, so the pbxproj isn't edited. Only `release.yml` raises it:
  - patch, minor (default) or major, or an explicit `X.Y.Z`
  - commits `release: X.Y.Z`, tags `vX.Y.Z` and builds that tag

  If `main` is protected, allow `github-actions[bot]` to push, or run the release from a
  branch.
- `make archive` (local) reads `VERSION` too. Its default build number
  (`yyyyMMddHHmm`) is larger than a run ID, so pass `BUILD_NUMBER` if you ever upload
  locally after CI has.

## TestFlight distribution (`scripts/testflight.py`)

The script uses only the Python standard library; `openssl` signs the ES256 JWT.

- `distribute --build N --group NAME [--notes FILE] [--external]`:
  1. waits until build N has processed (`VALID`, up to 60 min)
  2. sets What to Test in `en-US` and `de-DE`
  3. adds the build to the group
  4. with `--external`, submits it for beta review (an existing submission is fine)
- `latest-build` prints the newest processed build number.

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
