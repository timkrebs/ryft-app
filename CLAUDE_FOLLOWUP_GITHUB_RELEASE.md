# RYFT iOS — professional GitHub repo, testing and release workflows — follow-up for the Xcode session

State (2026-10-20, from the repo). A lot is already in place: remote
`github.com/timkrebs/ryft-app`, `.github/workflows/{ios,nightly,weekly,release,_testflight}.yml`,
the composite action `.github/actions/setup`, `docs/CI.md`, SwiftFormat + SwiftLint configs,
`.xcode-version` (27.1), `VERSION` (1.0.0), the time-based build number
(`scripts/build-number.sh`, commits `fa7c9f6`, `34e60b3`, `41d9f02`), automatic signing in CI
with an App Store Connect API key, `scripts/testflight.py` for distribution. But:
- **25 local commits are not pushed**, and as far as the repo shows, **no workflow has ever
  run** on GitHub. Everything in `docs/CI.md` is untested.
- Agents commit straight to `main`; there is no branch protection, no PR flow.
- Missing repo basics: `CODEOWNERS`, PR/issue templates, `SECURITY.md`, license decision,
  `CHANGELOG.md`, Dependabot, a release guide for a human. `project.yml` is still committed
  although `CLAUDE.md` says the `.xcodeproj` is the source of truth. `.DS_Store` files exist
  locally.
- No coverage, no test plans, no contract check against the platform, no secret scanning,
  actions pinned by tag instead of SHA, no App Store (production) release path, no dSYM
  retention.

The user is new to professional app release practice. Goal: a repo that works like a small
professional iOS team's — every change through a PR with required checks, automatic internal
builds, a reviewed path to external testers and the App Store, reproducible versions,
symbolicated crashes — and a plain-language `docs/RELEASING.md` that explains it to him.
Keep the existing design decisions unless something below says otherwise (no fastlane, no
Ruby, one dependency `supabase-swift`, automatic signing with the ASC key, time-based build
numbers).

Read `CLAUDE.md`, `docs/CI.md`, `docs/TESTFLIGHT.md`, `docs/APP_STORE.md`, `docs/STATUS.md`,
every workflow and script first. You can run `git`, `gh` (ask the user to `gh auth login` if
it isn't authenticated) and `xcodebuild build`; `xcodebuild test` doesn't run from your
environment, so CI is where tests prove themselves. Never put secrets in files; print the
`gh secret set` commands for the user instead. Ask before anything that changes GitHub
settings (protection, environments, visibility) — print the `gh api` call and let the user
confirm.

## 0. Decide the runner budget first (ask the user)

macOS runners on a **private** repo cost 10× Linux minutes: the free 2,000 min/month of a
personal plan are ~200 macOS minutes — one or two nightlies plus a few PRs. Check
`gh repo view timkrebs/ryft-app --json visibility` and measure one full `ios.yml` run once it
works. Then put the options to the user with numbers:
1. keep private, pay for minutes (price per macOS minute from GitHub's current pricing page);
2. keep private, run the heavy jobs on a **self-hosted runner** on his Mac (label
   `self-hosted, macOS, xcode-27`; PR checks from forks never run there; document the risks);
3. Xcode Cloud for archive/TestFlight (25 compute hours/month included with the Developer
   Program) and GitHub Actions only for lint + unit tests;
4. make the repo public (only publishable values are committed — confirm with gitleaks first).
Implement whatever he picks; until he answers, make every macOS job cheap: SPM cache,
`concurrency` cancel-in-progress, path filters (docs-only PRs skip the build), nightly only
when `main` changed (exists).

## 1. Push and get CI green

- Branch `ci/first-run` from the current `main`, push it, open a PR with `gh pr create`.
  Watch the runs (`gh run watch`), fix until `ios.yml` is green: runner image vs Xcode 27.1
  (`.github/actions/setup` must fail with the list of installed Xcodes, as documented),
  simulator name, SwiftLint/SwiftFormat versions (pin them — `brew install` gives whatever is
  current; use the release binaries with a checksum, or `mint`-free direct downloads),
  warnings gate.
- Merge, then trigger `nightly.yml` manually once (needs the three `ASC_*` secrets — print the
  `gh secret set ASC_KEY_ID …` commands for the user and wait). The first upload proves signing,
  the build number and `testflight.py distribute`. Record the run URLs in `docs/STATUS.md`.

## 2. Branching and review model

Trunk-based, the way most app teams work:
- `main` is always releasable. Work happens on short branches (`feat/…`, `fix/…`, `chore/…`,
  `release/…`), merged by **squash** via PR; the PR title becomes the commit
  (`area: what changed`, the repo's existing style — add a tiny `pr-title.yml` check for
  `^[a-z0-9/-]+: .+`).
- **Branch protection / ruleset on `main`** (print the `gh api` call, user confirms): PR
  required, required checks `Lint` and `Build, unit tests, UI smoke` (and `Contract` from §4),
  up-to-date branch, linear history, no force-push, admins included; allow
  `github-actions[bot]` to push the release commit (or have `release.yml` open a PR instead —
  choose and document).
- **Agents follow it too**: update `CLAUDE.md` — every session works on a branch, pushes, opens
  a PR with `gh pr create --fill`, waits for checks, and either asks the user to merge or enables
  auto-merge (`gh pr merge --auto --squash`) if he says so. No more commits to `main`.
- Unfinished features ship dark behind the remote flags (`GET /v1/config`), not on long-lived
  branches. Note this in `RELEASING.md`.

## 3. Repo hygiene

- Delete `project.yml` (and any xcodegen mention outside history); `**/.DS_Store` in
  `.gitignore`, remove tracked ones.
- `.github/CODEOWNERS` (`* @timkrebs`), `.github/pull_request_template.md` (what/why, screenshots
  dark + light, test notes, checklist: strings en+de, API.md mirrored, no warnings, flags),
  `.github/ISSUE_TEMPLATE/{bug.yml,feature.yml,tester-feedback.yml,config.yml}` — the
  tester form asks for app version + build (Profile → About shows both), device, steps,
  request ID.
- `SECURITY.md` (how to report, health data note), license: ask the user — default for a
  private product is no open-source license and a `LICENSE` stating "All rights reserved";
  `docs/THIRD_PARTY.md` already covered by the Licences screen — link it.
- `CHANGELOG.md` in Keep a Changelog form with an `## [Unreleased]` section; the PR template
  reminds to add a line for user-visible changes; `release.yml` moves Unreleased under the new
  version and uses it for the GitHub Release and the App Store "What's New" (§6).
- `.github/dependabot.yml`: `github-actions` weekly and `swift` (SwiftPM) weekly, grouped,
  with `supabase-swift` minor/patch only. Dependabot PRs run the normal checks.
- `.editorconfig`, and confirm `Package.resolved` stays committed (reproducible builds).

## 4. Testing that a team would trust

- **Test plans** (`.xctestplan`, committed, shared scheme): `Unit` (RyftTests, parallel, random
  order, code coverage for the `Ryft` target only), `UISmoke` (StoreSmoke + the onboarding UI test,
  retry on failure ×2 — UI tests only), `Full` (everything, nightly). Workflows call
  `-testPlan`; local `make test` uses `Unit`.
- **Coverage**: `xcrun xccov view --report --json` → a short summary (overall + changed files)
  posted to the job summary (`$GITHUB_STEP_SUMMARY`), no third-party service. Start with a
  floor at today's number minus 2 % for `Networking/`, `Sync/`, `Persistence/`,
  `Features/*ViewModel*` and fail below it; never lower the floor in the same PR that drops it.
- **Contract job** (`Contract`): checks out `timkrebs/ryft-platform` (read-only deploy key or
  fine-grained token secret `PLATFORM_READ_TOKEN` — print the setup), extracts the JSON examples
  from `docs/API.md` with the same script the platform's `make check-swift` uses (or a port of
  it in `scripts/`), and runs the fixture decode tests against them. Runs on PRs touching
  `Networking/` and nightly; a red nightly means the platform changed the contract.
- **Snapshot-free UI checks**: keep Preview captures as the visual review (no snapshot library —
  dependency rule). The PR template asks for them.
- **Performance**: one `XCTMetric` test for decoding a 90-day `DayDetail` set and one for the
  sync page builder, baselines committed, run in `Full` only.
- **Static checks**: SwiftLint error-only stays; add `-warnings-as-errors` for the `Ryft`
  target in CI only (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on the command line) instead of the
  grep, and keep the grep for asset/plist warnings if needed.

## 5. Security in the pipeline

- Pin every third-party action to a full commit SHA with the version as a comment;
  Dependabot updates them.
- `permissions: contents: read` at workflow level, widened per job only where needed
  (`contents: write` for tagging, `pull-requests: write` for comments).
- `gitleaks` on every PR (Linux runner, cheap) with an allow-list for
  `Config/Production.xcconfig`'s publishable values.
- CodeQL for Swift weekly on `main` (macOS minutes — skip if the budget decision in §0 says so,
  and note it).
- The `.p8` is written to `$RUNNER_TEMP` with `umask 077` and deleted in an `always()` step;
  never echoed.

## 6. Releases: from commit to App Store

Write it as one picture in `docs/RELEASING.md` (with a small diagram) and implement the gaps:

| Stage | Trigger | Audience | Approval |
| --- | --- | --- | --- |
| PR checks | every PR | — | required checks |
| Internal TestFlight | nightly when `main` changed, or manual | Internal group (the user) | none |
| External TestFlight | weekly, or manual | External "Friends" | GitHub environment `external-testflight` with the user as required reviewer; Apple beta review |
| Release candidate | `release.yml` (manual: patch/minor/major) | Internal | — |
| App Store | new `appstore.yml` (manual, input: version) | everyone | environment `app-store` with required reviewer; Apple App Review; phased release |

- **Versions**: SemVer in `VERSION` (marketing version). MAJOR for breaking user-facing
  changes, MINOR for features, PATCH for fixes. Build numbers stay time-based. Tags: `vX.Y.Z`
  for releases (exists), `build/<n>` per upload (exists).
- **`release.yml`**: as today, plus — move `CHANGELOG.md` Unreleased to the version, create a
  **GitHub Release** with those notes and attach the **dSYMs** zip of the archived build
  (`Ryft.xcarchive/dSYMs`) and the `.xcarchive` itself as a workflow artifact (90 days), so
  crash reports from TestFlight/App Store can be symbolicated later.
- **`appstore.yml`** (ASC API in `scripts/testflight.py` → rename to `scripts/asc.py` with
  subcommands; stdlib only): create the App Store version if missing, set "What's New" (en-US,
  de-DE) from the changelog, attach the build of tag `vX.Y.Z`, enable **phased release**
  (7 days), set release type "after approval, manual" by default, submit for review. Stops before
  submission with `--dry-run`. Metadata (description, keywords, screenshots) stays in App Store
  Connect for now; note fastlane-free options for later.
- **Hotfix**: branch `release/X.Y` from tag `vX.Y.Z`, cherry-pick the fix, run `release.yml` on
  that branch with `patch`, merge the branch back. Document; make `release.yml` accept a branch.
- **Rollback reality** (explain in `RELEASING.md`): an App Store release can't be rolled back —
  pause the phased release, ship a patch, use remote flags to switch a feature off. TestFlight
  builds can be expired.
- **Environments + secrets**: move `ASC_*` from repository secrets to the environments that need
  them (`internal-testflight` without reviewer, `external-testflight`, `app-store` with reviewer);
  print the `gh api` calls; the user confirms.

## 7. After release: knowing it works

- Crash and hang data: Xcode Organizer (TestFlight + App Store) and the app's MetricKit summaries
  (beta work). Add a "Weekly health check" section to `RELEASING.md`: Organizer crashes per build,
  TestFlight feedback, `POST /v1/feedback` (platform `beta_report.sh`), App Store ratings.
- `weekly.yml` already writes What to Test from commits; make it use the `CHANGELOG.md`
  Unreleased section when it has entries, else the commit titles (filtering `chore:`/`ci:`/`docs:`).

## 8. Docs for the user

- `docs/RELEASING.md` — written for someone who has never shipped an app: the stages table, what
  happens automatically, what needs his click (environment approvals, App Store Connect fields),
  how to ship a hotfix, how to read a failed run, what each secret is, monthly cost of the chosen
  runner option.
- `docs/CI.md` updated (workflows, test plans, coverage, contract, security), `README.md` links
  both, `CLAUDE.md` has the branch/PR rule and "never push to main".
- `docs/STATUS.md`: first green runs with URLs, the first TestFlight upload from CI, open user
  items.

## Done when

- `main` is protected; this work itself landed through PRs with green required checks.
- `ios.yml`, `pr-title.yml`, `gitleaks`, `Contract` run on PRs; `nightly.yml` uploaded a build to
  Internal TestFlight from CI; `release.yml` produced a tagged GitHub Release with notes and dSYMs
  (a `v1.0.0` dry run is fine if no release is wanted yet — ask).
- Test plans, coverage floor, performance baselines committed; actions SHA-pinned; Dependabot on.
- `appstore.yml --dry-run` reaches "ready to submit" without submitting.
- `RELEASING.md` explains the whole flow; the runner budget decision is recorded.
- PRs (squash titles): `ci: first green run`, `chore: repo hygiene and templates`,
  `ci: branch protection and PR flow`, `test: test plans, coverage, contract job`,
  `ci: pinned actions, least privilege, secret scanning`, `release: changelog, GitHub releases,
  dSYMs, App Store workflow, environments`, `docs: releasing guide`.
