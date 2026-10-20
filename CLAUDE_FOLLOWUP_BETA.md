# RYFT iOS — Beta: external TestFlight for friends — follow-up for the Xcode session

State (2026-10-20). Every endpoint in `../plattform/docs/API.md` is wired
(`docs/STATUS.md` → Platform wiring), and the app runs on the user's iPhone against
production after a signing fix: `Ryft.entitlements` carried an empty
`com.apple.developer.associated-domains` array that the profile didn't grant, so iOS
refused to launch ("inadequate entitlements"). The key is gone now.

Goal: a build on **external TestFlight** that 5–10 friends with different devices (Apple
Watch, Oura, Garmin, iPhone only) can install, join with an invite code, consent, and get
correct numbers from — and that passes Beta App Review. The platform side is
`../plattform/CLAUDE_FOLLOWUP_BETA.md`; it adds consent, invite codes, model version,
birth year / max HR estimate, `User.sources`, feedback and new error codes. **Wait for
its `API.md` changelog entry "Beta"** before §1; §0 and the TestFlight docs can start now.

Read `CLAUDE.md`, `docs/STATUS.md`, `docs/APP_STORE.md`, `../plattform/docs/API.md`
(Errors, the Beta changelog entry, `GET /v1/config`, `GET /v1/me`), `../ROADMAP.md` → Beta.
Rules as before: the `.xcodeproj` is the source of truth; mirror `API.md`, fixture test per
new shape; German for every string; Preview captures dark + light; one commit per section.
`xcodebuild test` doesn't run from your environment — build, then ask the user to run the
test plan in Xcode.

## 0. Signing hygiene

- `CLAUDE.md`: replace the "keep Associated Domains as an empty array" rule with:
  **no `associated-domains` key until the AASA is live; capabilities are added only through
  Signing & Capabilities → + Capability, never by editing the entitlements file by hand;
  every key in `Ryft.entitlements` must have a matching capability.** Add a `make
  check-entitlements` that fails on an empty array value or on a key outside an allow-list
  (`aps-environment`, `applesignin`, `healthkit`, `healthkit.access`,
  `healthkit.background-delivery`), and run it in `make lint`.
- The platform is extending the AASA (§9 there). Once
  `curl -sI https://ryftapp.de/.well-known/apple-app-site-association` shows it with the app
  paths, tell the user to add Associated Domains `applinks:ryftapp.de` through + Capability;
  the `AppRoute` parser needs no change.

## 1. Mirror the Beta contract

From the Beta changelog entry: `APIErrorBody.code` (closed enum, unknown → `nil`),
`User.consent`, `User.beta_access`, `User.birth_year`, `User.max_hr_source`,
`UserPatch.birth_year` / `max_hr_manual`, `User.sources` (`DataSource`), `RemoteConfig`
`privacy_policy_version` / `privacy_policy_url`, `DailyScore.model_version`,
`Workout.model_version`, `ModelInfo` + `ModelChange` (`GET /v1/model`), `FeedbackInput`,
`SyncRequest.app_version` / `os_version` (send them). New `PlatformAPI` methods with fakes:
`consent(policyVersion:)`, `revokeConsent()`, `redeemInvite(code:)`, `model()`,
`sendFeedback(_:)`. `APIStatus`: `403` + `consent_required` → `.consentRequired`,
`invite_required` → `.inviteRequired` — routed to the gate (§2), never shown as an error.
Fixtures from `API.md`; ask the user for `make check-swift`.

## 2. First run for someone who isn't the user

One onboarding flow, state machine in `OnboardingCoordinator` (resumable after a kill, each
step skipped when the server already has it):

1. **Welcome → account** (exists).
2. **Invite code** when the server says `invite_required`: one field, auto-uppercase,
   paste-friendly (`RYFT-7K3M-QX9P`), `422` → "This code doesn't work. Ask the person who
   invited you for a new one." A `ryft://invite/<code>` link pre-fills it (add to
   `AppRoute`).
3. **Consent**, shown when `User.consent?.policy_version` ≠ `config.privacy_policy_version`:
   a plain-language summary (what RYFT reads from Apple Health, that it's stored in the EU,
   that only you and the operator can see it, delete and export anytime), the full policy in
   in-app Safari, and a **separate, unticked** checkbox "I agree that RYFT processes my health
   data to calculate my scores." → `POST /v1/me/consent`. No sync before this. A policy
   update later shows the same screen once, with "What changed" linked.
4. **About you**: birth year (prefilled from HealthKit `dateOfBirth` if the user grants that
   characteristic — add it to the read set and the purpose string; otherwise a picker), then
   the resulting max HR with "Estimated from your age · change" and the default sleep need with
   "RYFT learns this from your nights". → `PATCH /v1/me {birth_year}` (and `max_hr` if edited).
   Timezone patch stays where it is.
5. **Apple Health** explainer → permission (exists).
6. **First import** with real progress ("Importing 90 days · 34 %"), then Today in its
   calibrating state with "Scores sharpen over your first 7 nights · night 2 of 7".

Profile → Privacy: consent date + version, "Withdraw consent" (stops syncing; offers Export
my data and Delete account right there), policy link. Profile → About you: birth year, max HR
with its source and "Use estimate", sleep need source (exists).

Tests: coordinator transitions for every server state combination, resume after kill,
deep-link prefill, no sync call before consent.

## 3. Data sources and honest empty states

- Profile → Data sources from `User.sources`: name, what each provides (HR, HRV, sleep,
  steps …), last seen. A source not seen for 24 h is marked.
- Today / Sleep / Strain states per situation, each with one sentence and, if possible, one
  action:
  - no heart-rate source (`no-heart-rate-source` insight or no `hr` kind): "Recovery and
    strain need a watch or ring that writes heart rate to Apple Health." + which apps do;
  - sleep without stages: stage bar hidden, totals shown, "Your source doesn't record
    sleep stages";
  - no data yet / still importing / calibrating (exists — check the copy against the new
    flow);
  - a source stale > 24 h: the `SYNC_STALE` wording, with "Open Garmin Connect / Oura / Watch
    app" as text (no app-scheme guessing).
- **Debug-only scenario seeder** (Developer section): writes synthetic HealthKit samples for
  "Apple Watch + iPhone", "Oura", "iPhone only", "Garmin" into the **simulator's** Health store
  (`HKHealthStore.save`, write permission requested only in Debug, purpose string Debug-only)
  so every state can be captured in Previews and checked against the platform's fixtures.
  Not compiled into Release.

## 4. Report a problem

Profile → "Report a problem" (and a two-finger long-press on any screen in TestFlight builds
only): category, message, a toggle "Include diagnostics" (on by default, with "What's
included" listing it): app version + build, device model, iOS, the last 20 request IDs and
statuses from a ring buffer in `APIClient`, last sync result and time, sources, flags in effect,
and the latest MetricKit summary (§6). → `POST /v1/feedback`; offline → queued in SwiftData and
sent on reconnect. Confirmation: "Thanks — Tim reads every one." Also mention TestFlight's own
screenshot feedback in the beta notes.

## 5. Model version visible

- Every score surface's info footer shows "Model 2026.10.1"; tap → sheet from `GET /v1/model`
  with the changelog (localised summary, date, affected metrics).
- When the newest score's `model_version` differs from the last one the user saw, a one-time
  banner on Today: "Scores were recalculated (model 2026.10.2): <summary>. Past days were
  updated too." Dismissed per version.
- `null` version → no footer, no banner.

## 6. Diagnostics without third-party SDKs

`MXMetricManager` subscriber: keep the last 7 days of `MXDiagnosticPayload` summaries
(crash, hang, CPU/disk exception — signature and call-stack root only) in SwiftData; attach
the latest to feedback when the toggle is on. Nothing is sent automatically. Privacy manifest
unchanged (no new collected data type beyond what feedback declares — update
`PrivacyInfo.xcprivacy` and the App Privacy answers in `docs/APP_STORE.md` if "Customer
Support" / "Crash Data" now apply).

## 7. TestFlight build and Beta App Review

- `docs/TESTFLIGHT.md`: step-by-step for the user — archive (`make archive` or Organizer),
  upload, internal test on their own phone first, then an external group "Friends" with the
  public link; the App Store Connect fields: beta app description, feedback email, privacy
  policy URL (`https://ryftapp.de/privacy`), marketing URL, **review sign-in** (the platform's
  `seed_demo.sh` account — credentials only in App Store Connect), review notes (below), export
  compliance (already `NO`), 90-day build expiry.
- Review notes text (en): what RYFT is, that it reads Apple Health and needs a watch for full
  scores, that the demo account already has 60 days of data, that Sign in with Apple and email
  both work, that the invite code step does not appear for the demo account, where account
  deletion is.
- `docs/TESTFLIGHT_NOTES.md`: per-build "What to test" (en + de), newest first. Build 1: sign
  up with a code, consent, first import, Today after the first night, Train a workout, journal
  in the morning, report a problem once.
- **Production push on TestFlight:** the archive's entitlements say `aps-environment =
  production`; the Developer section (Debug) can't be used there, so log the registration's
  `env` once via `os_log` and add it to the diagnostics payload; verify on the internal build
  that `POST /v1/devices/{id}/push` sent `production` and that a test push arrives (ask the user
  to trigger one via the platform runbook).
- Version `1.0.0`, build number timestamp (exists). TestFlight-only UI (the long-press feedback)
  keyed on the sandbox receipt check, not on a build flag.

## 8. Quality gate before upload

- Zero warnings, `make lint` (incl. `check-entitlements`) clean, all unit tests and the UI smoke
  test green in Xcode (user runs), the new onboarding covered by a UI test with stubbed network.
- Fresh install on a **second device** if the user has one (or a device erased via Settings),
  in German and English, Dynamic Type at AX3, light and dark.
- Memory/energy: one Instruments Time Profiler run of the first 90-day import on device; the
  import must not block the main thread or exceed the background budget (pages already exist —
  confirm).

## 9. Docs

- `docs/STATUS.md`: Beta section — done, verified on device, waiting on the platform deploy,
  user-only items (App Store Connect fields, demo account credentials, external group, first
  codes).
- `README.md`: how to cut a beta build, where notes live.
- Preview captures (dark + light, en + de for the onboarding): invite code, consent, about you,
  first import, calibrating Today, no-HR state, data sources, report a problem, model sheet.

## Done when

- `make check-entitlements` guards the signing file; the CLAUDE.md rule is fixed.
- A new account walks code → consent → about you → Health → import without help, and nothing
  syncs before consent; `consent_required` / `invite_required` route to the gate, never to an
  error.
- Data sources, the honest empty states, feedback with diagnostics, model footer + banner all
  work; MetricKit summaries attach to feedback.
- An internal TestFlight build ran on the user's phone with production push verified;
  `docs/TESTFLIGHT.md` and the review notes are ready for the external submission.
- Commits: `chore: entitlements guard`, `contract: beta fields`, `onboarding: invite, consent,
  about you, first import`, `sources: data sources and empty states`, `feedback: report a
  problem with diagnostics`, `model: version footer and recalculation banner`, `diagnostics:
  MetricKit`, `docs: TestFlight and beta status`.
