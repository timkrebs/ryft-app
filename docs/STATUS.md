# Status — 2026-10-19

## Done

- **Brand**: `Theme` palette as asset-catalog colour sets with light variants; `Font.ryft`
  (Satoshi with SF Pro Rounded fallback, Dynamic Type); vector `RyftMark`; wordmark header.
- **App icon**: light, dark and tinted 1024 px PNGs rendered from `RyftMark` (`make icon`).
- **Components**: RyftMark, RyftHeader, ScoreRing, MetricTile, Card, SegmentedPicker,
  StageBar, Hypnogram, InsightCard, TrendChart, InlineMessage (with request-ID Details),
  UpdatedLabel, SetupCard. Each has a `#Preview` in dark and light.
- **Screens**: Today, Sleep (Day with stage bar and hypnogram, Week/Month), Strain (ring,
  steps and active-kcal tiles, zones, activities, WorkoutDetail), Insights (cards, charts for
  all nine trend metrics), Profile, all with previews.
- **Accounts (Supabase Auth)**, in the WHOOP style:
  - **Welcome**: mark, wordmark, tagline, three value lines in the board's style,
    *Continue with Apple*, *Create account*, *Log in*.
  - **Create account**: name, email, password ≥ 10 with show/hide, consent line. Then
    *Check your inbox* (Open Mail, Resend) when the project requires confirmation.
  - **Log in**, **Forgot password**, **Set new password**. Errors are calm and never reveal
    whether an email has an account.
  - **Continue with Apple**: native `ASAuthorization` with a SHA-256 nonce. The name from
    the first authorisation is saved as `full_name` (via `update(user:)`, then a session
    refresh, because `signInWithIdToken` takes no metadata).
  - **Deep links**: `ryft://auth/callback` (PKCE). Reset links open *Set new password*.
  - **Session**: SDK-managed in the Keychain (readable after first unlock, so background
    sync works) and restored synchronously at launch.
  - **First sign-in**: `GET /v1/me`, then `PATCH /v1/me {"tz": …}`.
  - **Profile → Account**: name → email → "Apple ID", provider badge, Change password (email
    accounts), Log out, and Delete account (`DELETE /v1/me`, then log out). The
    confirmation names what is deleted.
  - **Log out and deletion** clear the session, `ResponseCache`, HealthKit anchors and
    per-user defaults. A different account on the phone also starts from scratch.
- **Configuration**: `Config/Production.xcconfig` (committed) carries `RYFT_API_URL`
  (`https://api.ryftapp.de`), `RYFT_SUPABASE_URL` and `RYFT_SUPABASE_PUBLISHABLE_KEY`,
  exposed via Info.plist. Per-user server fields are gone. A missing value shows an in-app
  message.
  - Debug-only **Profile → Developer**: API/ingest URL overrides, API key mode for
    `AUTH_MODE=apikey` compose, Show request IDs, Test connection.
- **Status handling** per `API.md`:
  - `401` → refresh once, retry once, then log out.
  - `503` → never log out; wait `Retry-After` with "RYFT is catching up, retrying in N s".
  - `429` → wait, retry once.
  - `413` → halve the HealthKit page size for the rest of the sync.
  - Request IDs are kept: inline *Details*, and the Developer log.
- **Contract cleanup**: models mirror `API.md`.
  - Typed fields: `baseline_days`, the baselines, `steps`/`active_kcal`, `DayStrain`,
    `SleepDetail.segments`, `SleepRange` with absent nights, `User.email`/`provider`,
    `APIErrorBody.request_id`, `AccountDeleted`.
  - Removed: `details`/`JSONValue`, the "endpoint missing" shims (`Derived.swift`) and the
    0–1 → % branch in `SleepMath` (the 1 % → 100 % bug).
  - Trends gain `sleep_min`, `steps` and `active_kcal`. `sleep` is now read as performance
    (%), as the API defines it.
  - `calibrating` copy covers both D4 cases: building the baseline ("N nights to go", a
    plural variation), and baseline complete with no readiness yet.
- **Tests**: 93 Swift Testing tests in 7 suites, all passing on the iPhone 18 Pro
  simulator (iOS 27.1). They cover:
  - fixtures regenerated from the `API.md` examples
  - nonce and hash
  - `AuthService` transitions with `MockAuthClient`: sign-up with and without a session,
    log in, wrong password, the reset flow, deep links, revoked session, account switch,
    deletion
  - `APIClient` 200/401/503/429/413 handling against a stub `URLProtocol`
  - sleep maths and copy
- **Build**: zero warnings in app and test code (simulator, Debug).
- **Localisation**: German (`de`) added to the project. Welcome/Auth, Today and Sleep
  strings are being translated in `Localizable.xcstrings`; the rest follows in M5.

## Blocked on Apple / Supabase configuration (can't be done from here)

- **Paid Apple Developer team.** `DEVELOPMENT_TEAM = M77SKHKG63` is a free Personal Team,
  and those can't provision Sign in with Apple. Every **device** build fails at signing
  until the project uses a paid team. Simulator builds and tests are unaffected. Then:
  - an App ID with Sign in with Apple and HealthKit
  - a Services ID, the Team ID, a Key ID and the `.p8` for Supabase's Apple provider
- **Supabase values.** Fill `RYFT_SUPABASE_URL` and `RYFT_SUPABASE_PUBLISHABLE_KEY` in
  `Config/Production.xcconfig`. They are placeholders, so Welcome currently says they're
  missing.
- **Supabase project settings.**
  - Add `ryft://auth/callback` to Authentication → URL Configuration → Redirect URLs.
  - Email provider on, minimum password length ≤ 10, Confirm email as wanted.
  - Apple provider with the bundle ID `dev.timkrebs.ryft`.
- **Release configuration → `Config/Production.xcconfig`.** Set it in Xcode (Project → Info
  → Configurations); per `CLAUDE.md` the project file isn't edited by hand. Until then,
  Release uses the git-ignored `Config/Release.xcconfig`, which includes it.
- **Legal pages.** The consent line links `https://ryftapp.de/terms` and
  `https://ryftapp.de/privacy`. Both must exist before release.

## Open

- **Not verified on a device.** None of the §5 run has been done:
  - fresh install → Welcome → create account → inbox → confirm → HealthKit prompt → first
    90-day sync → Today
  - log out, log in with Apple, delete account, confirm the `401` afterwards
  This is blocked by the signing issue above and the missing Supabase values. Everything
  was verified with unit tests, previews and the simulator in demo mode only. No device
  screenshots yet.
- **`make check-swift` in `../plattform`** should be run against the new models. It
  compiles the API.md Swift mirror and decodes a live stack.
- **Apple token revocation on account deletion** isn't covered (platform side;
  `SUPABASE.md` → Account deletion).
- **Package pin**: `swift-clocks` must stay at 1.1.0 (see README). `Ryft.xcodeproj` is
  git-ignored, so the pin and the project settings aren't versioned. Consider tracking the
  project now that it's the source of truth.
- German for the remaining screens (Strain, Insights, Profile) in M5.
- Insight dismissal is stored per device (UserDefaults), not synced to the platform.

## Known issues

- Satoshi isn't committed because of its licence (see README). Fresh clones render in SF
  Pro Rounded until `scripts/fetch-fonts.sh` runs.
- Welcome and the auth screens are always dark (Graphite, as on the board), also in light
  mode.
- The ring and strain numbers inside rings use fixed sizes so they fit the ring geometry.
- On iOS 26+ the tab bar uses the system Liquid Glass style; the opaque Graphite bar applies
  on iOS 17–18 only.
- "Open Health permissions" opens the Health app; iOS has no deep link to the per-app read
  permissions.
