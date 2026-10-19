# Status — 2026-10-19

## M3b Train — done

Built against the M3b shapes and the platform's Train brief
(`plattform/CLAUDE_FOLLOWUP_TRAIN.md`), because `API.md` has no Train section yet. Open
contract points are in `docs/API_REQUESTS.md`.

- **Wire models** in `Networking/Models.swift`: Exercise, Plan / PlanDay / PlanExercise,
  Progression, Enrollment, PlanCatalog, PlanToday / PlanTarget, TrainSession / exercises /
  TrainSet, PersonalRecord, CompletedSession (Session + `prs`), ExerciseHistory.
  - Workout gains `session_id` and `muscular_load`; DayStrain gains `sessions`.
  - Unknown enum values fall back to a neutral case.
- **Endpoints** (`APIClient+Train.swift`):
  - exercises (+ custom, history)
  - plans (list, detail, PUT, DELETE, enrol, leave, pause)
  - `plans/today` (`204` → nil)
  - sessions (list, GET, PUT with `409` → `.conflict`, complete, DELETE)
  - `APIClient.exchange(accepting:)` returns accepted statuses with their body.
- **Local-first store** (SwiftData, `Train/Model/`):
  - `LocalSession`, `LocalSessionExercise`, `LocalSet`, `CachedExercise`, `CachedPlan`, plus
    a persisted outbox (`PendingTrainOp`).
  - Wiped on log out and account switch.
- **TrainSyncService**:
  - 2 s debounced whole-document PUT; one queued PUT per session.
  - Ordered replay on reconnect (`NWPathMonitor`, app active).
  - `409` → merge by set id (later `updated_at` wins, the local set on a tie; locally deleted
    sets stay deleted) → PUT again, at most 3 rounds.
  - Finish → PUT + complete. Offline it marks `pendingCompletion` and the UI says "will sync".
  - 4xx ops are set aside; 401/408/429/5xx and transport errors keep the queue.
- **TrainLibrary**: exercises, plans, enrolment, today's plan and recent sessions, cached for
  offline browsing and refreshed on app active.
- **Screens** (`Features/Train/`), each with dark and light `#Preview`s:
  - Strain → Train section: Start workout / resume, Today's plan, My plans, History.
  - Start sheet: today's plan, repeat last, a plan day, empty.
  - **Live session**:
    - elapsed time and the rest timer: auto-start after a check, per-exercise rest, ±15 s,
      skip; inside a superset the rest comes after the round
    - targets ("4 × 5 @ 80 kg") and ghosted last-time values
    - 56 pt set rows (kg / reps / RPE / warm-up / check) and the custom keypad (±2.5 kg,
      ±1 rep, Next, locale decimal separator)
    - plate calculator (20 kg bar, 2.5–25 kg plates)
    - add exercise (search, muscle/kind filters, custom form), reorder, superset bracket
    - summary (duration, volume, muscular load, strain, PRs with a small celebration,
      notes); discard only after confirmation
    - haptics on set check and rest end; the screen stays awake
    - VoiceOver: "Set 2 of 5, 8 reps at 80 kilograms, completed", with actions
  - **Rest timer Live Activity**: `RyftWidgetsExtension`, lock screen + Dynamic Island,
    countdown, next set, Done → `ryft://train/session`. Local only:
    `NSSupportsLiveActivities`, no push.
  - **Plans**: list (built-in, mine, active) with pause / resume / leave. Detail by week →
    day → exercises with Start. **Builder**: goal, days/week, weeks or repeating,
    progression (linear / percent / none), per-day exercises (sets, rep range, % 1RM / RPE /
    kg / bodyweight target, rest, superset), live validation. Enrol / switch with
    confirmation.
  - **History** by week (volume, load), session detail. **Exercise detail**: 90-day e1RM
    chart, PR badges, recent sets.
  - **Today card**: "Today: Upper A · 5 exercises · ~55 min" → Start; in progress → Resume;
    afterwards "Done · load 85.0 · 2 PRs".
  - **Strain activities**: sessions with a dumbbell and load chip; a Garmin workout whose
    `session_id` matches is merged into one row.
- **Demo mode**: `MockTrainSource` plays the platform:
  - 28 exercises, the 4 built-in templates from the brief plus 1 custom plan, an active
    Upper/Lower enrolment
  - 90 days of progressive history linked to MockData's strength workouts
  - completion returns a demo load (calibrated to ≈ 85 / strain ≈ 11) and PRs
- **Tests**: 137 Swift Testing tests in 14 suites (44 new) plus 1 UI test. All of them pass on
  the iPhone 18 Pro simulator (iOS 27).
  - fixtures for every new shape
  - e1RM display maths (Epley, capped at 12 reps, as the platform scores)
  - plate calculator
  - rest-timer state machine
  - plan-builder validation
  - offline queue replay order, debounce, 409 merge and re-PUT, and refused ops, against a
    stub `URLProtocol`
  - UI test (`RyftUITests` scheme): start → log 2 sets → kill → resume → finish
- **German** for all Train screens (269 strings, plural variants) and the widget's own
  catalog.
- **Preview captures** in `docs/screenshots/train-*.png`: live session (dark, light, keypad),
  plan builder (dark, light), exercise detail (dark, light), summary, Strain section, Live
  Activity (lock screen, Dynamic Island). Compared with the brand board: Graphite / Slate
  surfaces, Teal accents, Satoshi, tracked labels. Fixed during review:
  - the keypad covered the focused set
  - summary icons animated off-centre
  - the demo load was too high
- **Build**: zero warnings in app, widget and test code (simulator, Debug).

## M3b Train — open

- **Switch to `API.md`** once the platform commits the Train contract. Then regenerate
  `RyftTests/Fixtures/train_*.json` from its examples and resolve `docs/API_REQUESTS.md`:
  - PlanSummary and SessionSummary shapes
  - pausing an enrolment
  - deleting a set mid-session (the server keeps omitted sets while `in_progress`)
  - "load" on the Today card: `muscular_trimp` vs a strain-scale value
- **Device test, not done.** Blocked by the signing issue below.
  - One real session in airplane mode; reconnect; verify it lands in `/v1/sessions` and the
    day's strain rises.
  - Live Activity on the lock screen and in the Dynamic Island, and its Done deep link. The
    simulator doesn't run Live Activities from previews.
  - Haptics.
  - Everything Train was verified with unit tests, previews and the UI test in the
    simulator's demo mode only.
- **`RestTimerAttributes` is declared twice** (app and extension, identical). Prefer one file
  with membership in both targets (Xcode File inspector).
- **UI test target** has no *Target Application* (the tool couldn't set `TEST_TARGET_NAME`),
  so it launches the app by bundle ID. It runs on its own `RyftUITests` scheme, not in the
  `Ryft` scheme's test action.
- **Log out drops unsynced sessions** with the rest of the per-user data. A warning in the
  log-out confirmation when `TrainSyncService.pendingCount > 0` would help.
- German for Train is machine translated like the rest of `de`; it needs a native review.
  Exercise names come from the server's `name` (the platform has `name_de`).
- Intermediate Train commits reference each other (session ↔ history ↔ plans); only the last
  one builds on its own.
- `AuthServiceTests/authFailureOnTokenSignsOut` failed once in a full parallel run and passes
  alone and with its suite. It looks like a race on shared state in the auth tests, older
  than Train. Watch it.

## Blocked on Apple configuration (Train)

- The widget extension needs an App ID (`dev.timkrebs.ryft.RyftWidgets`) under a **paid**
  team, like the app. Live Activities themselves need no capability.

## Done (before M3b)

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
