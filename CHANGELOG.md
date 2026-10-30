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
- Import plans and workouts from another training app's CSV export (read on your iPhone; only what you confirm is
  sent). Not switched on yet.
- Morning journal ("How was yesterday?") and how habits change the morning after.
- Notifications for the morning score, scored workouts, records and missing data, with
  quiet hours.
- Account with Sign in with Apple or email, data export and account deletion.
- Beta onboarding: invite code, consent to health-data processing, birth year for a
  maximum heart-rate estimate. Profile → Privacy to see or withdraw the consent, and
  Profile → Sign-in methods to add Sign in with Apple to an email account.
- RYFT is for people aged 16 and over: the consent screen says so, and onboarding and
  Profile offer birth years up to this year − 16.
- A readiness widget for the home and lock screen: today's readiness, or "Scoring your
  night…" until it's ready.
- Start a strength workout from anywhere: Today (today's plan, or an empty workout or your
  last one again), the app icon's quick action, Siri, Shortcuts, Spotlight, the Action Button
  and a Control Center / Lock Screen control. A workout in progress is resumed, never doubled.
- The workout on the Lock Screen and in the Dynamic Island for the whole session: elapsed time
  and the next set (e.g. "Bench press · set 3 of 4 · 5 × 80 kg"), the rest countdown between.
- After the last set of an exercise the workout folds it into one line and scrolls to the next set (Profile →
  Training → Jump to next exercise, on by default). The rest timer is a compact bar pinned under the clock.
- Save your strength workouts to Apple Health, if you want: asked once after your first
  logged workout, and in Profile → Data. RYFT writes only the workout, nothing else, and
  not when your watch recorded the session too. The workout summary says where its heart
  rate came from.
- Bedtime & wake: set when you want to wake up (weekdays and weekend, or each day) and how much
  of your sleep need you aim for. RYFT tells you when to be in bed tonight (Today from 17:00,
  Sleep → Bedtime, the widget), reminds you to wind down, and can wake you with a real alarm
  (iOS 26). The next morning, Sleep shows how close the night came to the plan.
- Profile → Report a problem: write to RYFT from the app, optionally with diagnostics (app version,
  device, the last requests, per-area load times and request durations, and the sync status, never
  health values). Saved and sent later when you're offline.
- From Today's error card, Details → Send to RYFT opens Report a problem with what failed.
- Tell RYFT what you wear: "What do you wear?" in onboarding and Profile → Data → Devices & sync
  show, per tracker, what reaches RYFT through Apple Health and what that means for Strain, Sleep,
  Recovery and Readiness, how to set it up and keep it flowing, and what Apple Health has seen.
  Ships dark behind the remote flag `devices.setup` until it's turned on.
- Check sync shows whether your tracker's data arrives in Apple Health, signal by signal over the last 48
  hours: what arrived and when, what your tracker doesn't share (that's normal), and the fix for what should
  arrive and doesn't. The check uploads nothing. Report a problem includes the check's result codes when you
  include diagnostics.
- Replace an exercise during a workout (your done sets stay with the old one, with Undo and optionally in your
  plan too), and edit its sets, reps, weight, rest and notes for this workout; swipe a set row to delete it.

### Changed
- A new app icon and RYFT mark: three orbits, three moons.
- Today's readiness is now the RYFT orbit: readiness in the centre, Recovery and Sleep on the inner ring, Strain on
  the outer. The readiness widget on the home and lock screen draws the same orbit.
- Today: while RYFT learns your baselines, the readiness orbit fills night by night; while last night is scored, it
  shows the previous day dimmed.
- Today: the readiness orbit assembles when you open the app (a simple fade with Reduce Motion or Low Power Mode).
- Your baseline sleep need and maximum heart rate can be changed where you see them: in
  onboarding, from the sleep need on Sleep, and in Profile → Sleep and Body. A change saves
  at once; past days are rescored when you ask.
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
- Today now says why baselines are still forming. When your tracker doesn't share HRV or
  resting heart rate with Apple Health, it names the signal instead of a counter that can't
  move.
- Health data, activities and workouts go up only under your consent to the privacy policy
  in force, also from the background and after a long time offline; a refusal is remembered
  until you agree. Deleting an activity, a night or a workout reaches RYFT even without it.

### Fixed
- Today's baseline counter no longer sits at 0 of 7 when your tracker sends no HRV: it counts the resting-heart-rate
  nights that are filling and says why, shows your readiness when there is one, and never puts a recovery percentage
  beside the counter. With a tracker that doesn't share HRV chosen in setup, Today says so from the first week
  (once Devices & sync is on).
- Train: when a plan day has the same exercise twice, each card shows its own sets from last time when they can
  be told apart, instead of both lists joined; a long "Last time" ends in "+N more" instead of being cut at five.
  The training import says when two exercises from the file map to one RYFT exercise.
- Today names your tracker's app as you know it ("Garmin Connect", not Apple Health's "Connect"). In
  the morning it says when your night hasn't reached Apple Health yet, with the app to open, instead
  of "Scoring your latest data"; scoring that takes longer than usual says so, with Details.
- Refreshing no longer shows an error when one part of your data is briefly unavailable: each
  part loads on its own, short outages are retried quietly, and Today says how old its data is
  ("Showing data from 14:05") only when it stays out of date.
- Profile → Notifications no longer shows switches that look on while notifications are
  still being rolled out to your account: it says what you'll get, and when iOS has them
  turned off it says so with a way to Settings.
- A missing consent or invite code no longer shows as "RYFT didn't accept your sign-in";
  the app asks for what's missing and syncs once it's done.
- Demo data (and a first launch that opened Strain or Sleep first) showed only today:
  the earlier days load again.
- Today no longer shows calibration ("Baselines · 0 of 7") while your scores exist: the gauge,
  tiles and widget tell one story, a night that isn't scored yet shows the last scored day dimmed
  with its date, and a change that's under 2 % reads "Steady" instead of a dash.
- This update removes a copy of local data that earlier versions left behind, which signing out
  didn't reach.
