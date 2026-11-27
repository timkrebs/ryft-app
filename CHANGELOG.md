# Changelog

User-visible changes to the RYFT iOS app. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/) (see `docs/RELEASING.md`).

Add a line under **Unreleased** in the PR that makes the change. `make release` moves
these lines under the new version (`docs/CI.md` → Versions and build numbers). They become the GitHub Release notes and the App
Store "What's New".

## [Unreleased]

### Security
- An account deletion stops if the signed-in account changes while the request is being prepared.

### Added
- Today shows your sync status in the header. Tap to sync Apple Health or long press to see when each source last synced.
- Nutrition search shows reusable portions and calories when the catalog supplies them. Tap plus to add a portion, or open the amount picker to choose a size, fraction or metric amount.
- German Nutrition logging, with household portions and a preview of the selected amount. The diary rollout can leave coaching and optional health imports off.
- Nutrition diary with food search and barcode lookup, meal editing, nutrient totals, and score details.
- Nutrition coaching with fueling targets, recovery guidance, training goals, and optional Apple Health imports.
- Devices & sync shows Garmin and Suunto direct connection availability from RYFT and gives
  connected accounts a way to refresh status, reconnect and disconnect.
- Today, Sleep, Strain and Insights from your watch or ring through Apple Health:
  readiness, recovery, strain and sleep against your own baseline.
- Sleep need broken down (baseline, strain, debt, nap credit), sleep quality and
  restorative sleep, bedtime consistency, and a sleep planner for tonight.
- Strength training: plans, a live session with rest timer, records and history.
- Import plans and workouts from another training app's CSV export (read on your iPhone; only what you confirm is
  sent). Not switched on yet.
- A focused workout screen: one exercise at a time with the next set ready to check, a strip of exercises, an estimated
  1RM or 10RM column, and the rest timer as a pill at the bottom. Not switched on yet.
- Morning journal ("How was yesterday?") and how habits change the morning after.
- A journal reminder, on by default at 09:00 once you've chosen habits: one notification each morning asking about
  yesterday, none once it's answered (also on another device), held until quiet hours end. A tap opens the journal on
  that day. Not switched on yet.
- When RYFT hasn't synced for about 20 hours (and again after about three days), your iPhone says so, between 09:00 and
  21:00 and outside quiet hours, unless RYFT's server can already reach this iPhone with that notification. Not switched
  on yet.
- Signing out, or a session that ends, removes RYFT's notifications from Notification Center and unregisters this
  iPhone from push notifications. With previews hidden, each notification says only what kind it is.
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
  Training → Advance to the next exercise, on by default). The rest timer is a compact bar pinned under the clock.
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
- RYFT proves to its servers that requests come from the genuine app on your iPhone (Apple's App Attest). Nothing
  changes until the servers start checking; a workout or sync they refuse for it stays queued and goes again.
- Optional usage analytics, off unless you opt in, never with health data (not active yet).

### Changed
- Agree and continue moves on as soon as RYFT has your consent. Your data starts syncing once this iPhone hears back
  from RYFT; until then Devices & sync and a training import say Paused, and Profile → Privacy says your consent is
  given, with Check with RYFT and Withdraw consent. While a withdrawal is on its way, nothing syncs, and if RYFT
  doesn't answer it, nothing syncs until RYFT says where your consent stands, also after a relaunch.
- RYFT's website, privacy policy, terms and support moved to ryftlab.de.
- RYFT now needs iOS 18.6 or later.
- A new look begins: RYFT is dark only (Profile → Appearance is gone), with new colours for recovery, sleep and strain,
  lighter type, labels in sentence case, and a new app icon, the RYFT wordmark.
- The app is called RYFT on the Home Screen, in notifications and in Settings, as on its icon.
- RYFT is English only: on a device set to German, the app shows English. Numbers and dates keep your region's format.
- Profile → Training: "Jump to next exercise" is now "Advance to the next exercise". It works as before, and your
  choice stays.
- Today: when your tracker's app has gone quiet, the hint says how it syncs and opens the app in one tap (the App
  Store page when it isn't installed).
- The app icon (light and dark) now carries the readiness gauge's colours and sits 5 % smaller on its tile.
- The readiness gauge is redrawn: tick rings for strain and readiness, recovery and sleep as two arcs, glowing end
  dots, and the score in dot numerals on large gauges. The widget draws the same gauge.
- A short launch animation on a cold start: the gauge folds into the RYFT mark. Tap to skip; it doesn't play when you
  return to the app within ten minutes, and Reduce Motion or VoiceOver show the still mark instead.
- Today in the new look: the readiness gauge on top, Recovery and Sleep as two tiles with their last seven days, and
  strain on a ruler. At the end of the launch animation the mark flies into Today's header.
- Sleep in the new look: time asleep in large numerals against your need, the night as a hypnogram, and the stages
  below. While last night is being scored, Sleep shows Apple Health's night marked "not scored yet".
- Strain, Insights and Profile in the new look, with a new tab bar. Tap the open tab again to go back to its start.
- Strain: the day's strain in large numerals with its change against the last 7 days, your heart-rate zones and the
  day's activities.
- Insights: your trends over 7, 30 or 90 days, with your usual range shaded once there are 7 days of data. Offline,
  Insights says so and shows when each card is from.
- Sleep's Week, Month and Bedtime in the new look. "vs 7 d" now means the same on Today, Sleep, Strain and Insights:
  the day against the 7 days ending on it.
- Profile: grouped lists, and every link says where it opens. With Demo data on while signed in, Profile still shows
  your own account.
- Switches and buttons in sheets now match the new look.
- A button at work shows a spinner and keeps its title ("Log in", "Send", "Check again"), instead of changing to
  "Logging in…" or "Sending…"; it takes no second tap, and VoiceOver says "In progress".
- Onboarding and sign-in in the new look: Welcome, Log in, Create account, the invite code, consent, About you, Apple
  Health and "What do you wear?".
- Train, My Day, Activities and the morning journal in the new look: the live workout (list and focused), the rest
  timer, the summary, History, an exercise's page, Plans and the plan builder; My Day on Today; Add activity and an
  activity's page; the journal's card and sheet.
- Profile's pages in the new look: About you and body settings, Sleep need, Devices & sync, Sync details, Check sync,
  Notifications, Journal, Bedtime & wake, Licences, Report a problem, and the training import. The widgets and the
  rest timer on the Lock Screen follow.
- The journal says "habits" everywhere, where it said "behaviors".
- Train's History, a workout, an exercise's page and a plan open at once when you're offline with what's on your
  iPhone, and load again by themselves when you're back. When one can't load, Details shows what failed and its
  request ID, as on Today.
- At the largest text sizes, a page's title sits on its own line under Back, and summaries list one part per line.
  The rest bar in a workout shows its time and Skip; ±15 s are in the rest timer it opens.
- With Reduce Motion on, Train and the journal change without animation.
- One header on every page: a sheet has Close on the left and its title centred; a page you open from Profile, Train or
  My Day has Back on the left and its title centred.
- No teal outside recovery: Today's setup, import and sync-hint cards and the notification question are in the new
  look, and an insight takes its metric's colour.
- Report a problem: Done sits beside Send above the keyboard. At larger text sizes rulers keep their ends, About you
  offers your birth year as a menu, and the journal's days stay readable.
- At the largest text sizes a sheet's title sits on its own line under Close (and Save), as a page's does under Back.
  Text scrolled under a sheet's header stops at a thin rule below it, and the first import's steps wrap instead of
  being cut off.
- Today and Sleep: a failed load says what happened in plain words and offers the step that helps (Sign in, Try again,
  or none when the app is too old).
- RYFT's tagline is now "Engineered for peak.", on the launch, Welcome and About.
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
- German: the end of a workout reads „Alle Sätze geschafft“ instead of „Alle Sätze erledigt“.
- Launch is smoother: saving data no longer holds up the screen.
- Turning off Demo data now discards the workouts logged with it, after asking. If they can't be read, Demo data stays
  on and Profile says so. Workouts logged with Demo data before this update are discarded too if nobody is signed in
  when it first opens; if you're signed in then, they stay.

### Fixed
- Back exits a new or reopened Nutrition meal, including while food search has the keyboard open.
- A workout without a duration in Apple Health (from another app, or entered by hand) no longer stops syncing. RYFT
  now leaves such a record out, like a sleep stage or reading that ends before it starts, and syncs everything else.
- Below iOS 26, the wake-up notification from Bedtime & wake now shows and sounds while RYFT is open, with Demo data on
  or off (it stayed silent), and with previews hidden it says "Wake-up time".
- At the largest text sizes, Sleep's stage card keeps each stage's name, time and share whole (they broke as "Awak" / "e"
  and "20" / "%"), and the first-run tips on Today stay on screen, their text scrolling when the tip is taller than the
  room (the first tip's title sat under the status bar).
- Importing from another training app: the list of warnings reads "The rest imports normally, and 2 notes." (it said
  "normally. and 2 notes").
- While your consent withdrawal is on its way, Profile holds Demo data and Log out and says why: using either before
  RYFT confirms it could drop the withdrawal without a word. Offline, the withdrawal now fails at once and says so,
  instead of waiting for a connection; with no answer in time, Profile asks RYFT again and shows whether it arrived.
  VoiceOver now hears when the withdrawal is confirmed.
- Log out shows it's working while it signs you out, and Withdraw consent waits until it's done: a withdrawal started
  then could be dropped by the sign-out.
- Train's History, exercise page and workout detail no longer ask you to go online when a read failed while you were
  online: they say it couldn't be loaded, with Try again.
- "Logged session" on a workout opens that session again, also from Today and My Day.
- The journal sheet closes when its account signs out or you switch Demo data while it's open, instead of dropping
  your answers when you save.
- After you sign out, switch accounts or turn Demo data on or off, Train no longer shows what belonged to the other
  side: a workout list, an exercise's history, the plan and last workout in Start workout, or a plan action's error.
- Copy request ID stays on this iPhone, as Copy details does (it no longer reaches your other devices).
- A workout that uses a custom exercise you made offline now syncs once you're back online, and a workout the server
  turns down stays on your iPhone, queued, instead of being dropped.
- Welcome and the live workout work at the largest text sizes: Welcome scrolls to its Privacy Policy link, words in
  the workout are no longer broken or cut, and the Start workout options show their whole detail.
- Removing an exercise in a workout closes the keypad if it was open on that exercise. It stayed up with keys that did nothing.
- A sign-out that RYFT couldn't finish on this iPhone, because the app was closed or the iPhone refused, finishes the
  next time you open RYFT, and so does removing a deleted account's data once the deletion has gone through. Until it
  has, a different account can't sign in on this iPhone, and RYFT says so.
- A workout started just as you're signed out no longer opens afterwards.
- Today: after a sync, last night shows as being scored on every path (a background sync, a relaunch, a pull),
  and a calibrating day no longer stays on "Scoring your night…" after its score arrives.
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
