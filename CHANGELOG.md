# Changelog

User-visible changes to the RYFT iOS app. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/) (see `docs/RELEASING.md`).

Add a line under **Unreleased** in the PR that makes the change. `release.yml` moves
these lines under the new version. They become the GitHub Release notes and the App
Store "What's New".

## [Unreleased]

### Added
- Today, Sleep, Strain and Insights from your watch or ring through Apple Health:
  readiness, recovery, strain and sleep against your own baseline.
- Sleep need broken down (baseline, strain, debt, nap credit), sleep quality and
  restorative sleep, bedtime consistency, and a sleep planner for tonight.
- Strength training: plans, a live session with rest timer, records and history.
- Morning journal ("How was yesterday?") and how habits change the morning after.
- Notifications for the morning score, scored workouts, records and missing data, with
  quiet hours.
- Account with Sign in with Apple or email, data export and account deletion.
- Beta onboarding: invite code, consent to health-data processing, birth year for a
  maximum heart-rate estimate. Profile → Privacy to see or withdraw the consent, and
  Profile → Sign-in methods to add Sign in with Apple to an email account.
- A readiness widget for the home and lock screen: today's readiness, or "Scoring your
  night…" until it's ready.

### Changed
- The first sync shows scores for the last few days first and imports the rest after;
  every sync sends last night before the day's heart rate.
- Leaving the app no longer stops an import: it continues in the background. A sync that
  finds the iPhone locked waits for the unlock instead of failing.
- New scores appear as soon as the platform has computed them, instead of after a fixed
  wait.
- Today says what's true while your data is on its way: a "Setting up RYFT" card with real
  counts during the first import, the baseline nights while RYFT learns your normal, and
  "Scoring your night…" with last night from Apple Health until the score lands. One
  status line under the greeting says what the sync is doing; a hint names the watch app
  that hasn't synced to Apple Health. Strain and Sleep mark days that aren't scored yet.
- Profile → Data → Sync details: each stream's progress, the last requests with their IDs,
  "Sync last 3 days again" and "Copy diagnostics" for support.

### Fixed
- Profile → Notifications no longer shows switches that look on while notifications are
  still being rolled out to your account: it says what you'll get, and when iOS has them
  turned off it says so with a way to Settings.
- A missing consent or invite code no longer shows as "RYFT didn't accept your sign-in";
  the app asks for what's missing and syncs once it's done.
- Demo data (and a first launch that opened Strain or Sleep first) showed only today:
  the earlier days load again.
