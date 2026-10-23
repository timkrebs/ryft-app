# RYFT iOS — "My Day" + Add activity + Start activity (GPS tracking) — brief for `ios-lead`

Run: `claude --agent ios-lead` → "Run `CLAUDE_FOLLOWUP_MY_DAY_ACTIVITIES.md`". The platform half is
`../plattform/CLAUDE_FOLLOWUP_ACTIVITIES.md`; the contract (`API.md` → Activities) must exist before §3–§4 upload
anything. Owners: **ios-architect** (design note first: tracking engine, location, data model), **ui-designer**,
**ios-developer**, **sync-engineer** (tracking engine, uploads, HealthKit), **api-contract-keeper**,
**security-privacy-reviewer** (location is personal data), **performance-profiler** (battery), **localization-editor**,
**test-engineer**.

## Why

Users see their day only as numbers; workouts are buried in Strain. And runs often don't reach RYFT: a run done with
the phone only, or with a tracker that doesn't hand workouts/routes to Apple Health, never shows up. RYFT needs a day view
that lists everything that happened, lets the user add what's missing, and can record an activity itself — with GPS
distance, pace and route.

Brand rule applies: RYFT's own names and look (Graphite/Teal, instrument style). No other wearable brand's wording or
layout; e.g. no "strain target" toggle (that's M3's future "Today's load" work, not this brief).

## 1. My Day (Today tab)

A card **My Day** on Today, below the scores and above Trends, and a full-screen **My Day** view (expand control):
- A chronological list of today's items: **Sleep** (last night: duration, bed–wake; tap → Sleep), **workouts from Apple
  Health** (source name via `trackers.json`), **Train sessions**, **RYFT-tracked activities** (§3), **manual
  activities** (§2). Each row: sport icon, name, time range, duration, distance if any, **strain** once scored (pending
  dot until then), source badge.
- **Empty and missing states:** no sleep → "No sleep recorded · Add sleep" (§2); nothing today → "Nothing yet today".
- Header **＋** and two buttons at the bottom of the card: **Add activity** and **Start activity**; the ＋ menu also
  offers **Start strength workout** (existing Train flow) and **Add sleep**.
- **Merged items:** when the platform reports that a RYFT-tracked or manual activity overlaps a tracker workout and they
  were merged (§P), show one row with both source badges.
- Day switching via the existing `DateStrip`; past days read-only except edit/delete of manual and RYFT-recorded items.
- Activity detail screen: map with route (if any), splits per km, pace/elevation charts (`ChartStyle`), HR curve and zones
  when the platform has heart rate for the window, strain and its source ("Heart rate from Garmin Connect"), notes, edit,
  delete. Strength sessions keep their existing summary.

## 2. Add activity / Add sleep (manual)

Sheet like the rest of RYFT (not a copy of any other app's form):
- **Sport** picker (searchable, recents first) from one catalogue shared with §3: Running, Trail running, Walking,
  Hiking, Cycling, Mountain biking, Gravel, Indoor run (treadmill), Indoor cycling, Rowing, Swimming, Strength (→ suggests
  Train), HIIT, Yoga, Mobility, Climbing, Skiing, Ski touring, Football, Tennis, Padel, Other. Each with SF Symbol, a
  `hasGPS` flag, an `HKWorkoutActivityType` mapping and an API `sport` value.
- **Start / end** (default: last hour, ending now; can't be in the future; max 24 h), optional **distance** and
  **perceived effort** (1–10), **notes**.
- Saved via the platform (§P). Strain comes from the heart rate the platform has for that window; without heart rate,
  the row says "No heart rate for this time" and uses perceived effort only if the platform supports it (§P).
- **Add sleep:** bed and wake time for last night (when no tracker recorded one) → platform manual sleep segment; it's
  marked "added by you" everywhere and can be deleted.

## 3. Start activity — recording with GPS

**Pre-start screen:** sport (recents first), a map centred on the user, **GPS accuracy indicator** (wait for ≤ 20 m before
the Start button turns active, with "Start anyway"), **Record route** toggle (default on for GPS sports), today's strain so
far as context, big **Start**. Indoor sports skip the map and use the pedometer.

**Recording engine** (`ActivityRecorder`, an actor; sync-engineer, design note first):
- **Location:** Core Location live updates with the **fitness** activity type (`CLLocationUpdate.liveUpdates(.fitness)`
  on iOS 17+, or `CLLocationManager` with `activityType = .fitness`, `distanceFilter` ~5 m, best accuracy), a
  **`CLBackgroundActivitySession`** (iOS 17+) so recording continues with the screen off, `showsBackgroundLocationIndicator`
  on. Permission: **When In Use** only — requested at the first Start, with a pre-prompt explaining why; no "Always".
  Info.plist: `NSLocationWhenInUseUsageDescription` (en + de) and background mode **location** (the user adds it in
  Xcode → Signing & Capabilities → Background Modes; print the step).
- **Distance and pace:** drop fixes with horizontal accuracy > 25 m or implausible speed for the sport; smooth (simple
  Kalman or moving window); sum geodesic distance; current pace (rolling 30 s), average pace, km splits.
- **Elevation:** `CMAltimeter` relative altitude (barometric), combined with GPS altitude for ascent/descent; needs
  Motion & Fitness permission (`NSMotionUsageDescription`, en + de) — ask only for sports where it matters (trail, hiking,
  MTB, ski touring).
- **Indoor / no GPS:** `CMPedometer` distance and cadence.
- **Auto-pause** (optional setting, default on for running/cycling): speed below a threshold for 10 s; manual pause/resume
  always available.
- **Heart rate live (optional, behind flag `activity.live_hr`):** the phone has no heart rate. If the user has a BLE heart-rate
  sensor or a watch that can broadcast heart rate (standard Bluetooth Heart Rate service 0x180D), connect via Core
  Bluetooth and show live HR. Otherwise show "Heart rate is added after your tracker syncs." Never fake HR.
- **Crash-safe:** checkpoint every 30 s to the user's SwiftData store (points, splits, state); a killed app resumes the
  recording on next launch ("Resume your run?") or lets the user finish/discard.
- **Battery:** measure with **performance-profiler** — target ≤ 8 %/hour on an iPhone 17 with screen off; reduce GPS
  frequency when stationary.

**Recording screen:** big numbers (time, distance, current pace, avg pace; for cycling speed; elevation gain for trail/hike),
map toggle, lap button, pause/resume, long-press Stop. **Live Activity / Dynamic Island** (reuse the rest-timer
infrastructure): time, distance, pace, paused state. Optional audio cues per km (AVSpeechSynthesizer, en/de, setting).

**Finish:** summary (map, distance, time, pace, splits, elevation), perceived effort 1–10, notes, **Save** / **Discard**
(discard needs confirmation). Save → upload to the platform (§P; queued offline, retried; idempotent by client id). Optional
**Save to Apple Health** as an `HKWorkout` with route (`HKWorkoutBuilder` + `HKWorkoutRouteBuilder`) — only if the user
enabled saving workouts (the opt-in from the beta-feedback brief); tag `HKMetadataKeyExternalUUID` = activity id and never
re-upload RYFT-written workouts as separate tracker workouts.

Entry points: My Day buttons; the ＋ menu; App Intent **Start activity** (sport parameter) next to Start strength workout;
the Control Center control gains "Start run".

## 4. Privacy (security-privacy-reviewer must sign off)

- Location is personal data and a route reveals home and habits. **Route storage is opt-in per activity** ("Record
  route" toggle) and a setting; distance/pace work without uploading the route (the app can compute them locally and send
  only totals and splits).
- **Privacy zone:** a setting (off by default; suggest it on first route save) that trims the first/last 200–500 m around
  user-chosen places before upload and before any export.
- Routes are deleted with the activity and with the account; included in "Export my data".
- Tell the user (Needs-you list) that the privacy policy, App Privacy answers (**Location → Precise Location, linked to user,
  App Functionality**) and `PrivacyInfo.xcprivacy` must be updated before shipping; the web text change goes to the platform
  session.

## 5. Contract and states (api-contract-keeper, sync-engineer)

Mirror `API.md` → Activities once published (§P). Until then build against the in-memory fake. States in My Day: pending
upload (cloud with arrow), uploaded/pending strain (hollow dot), scored (strain value), failed upload (retry; never lost —
the local copy stays until the platform confirms).

## 6. Tests and verification

- Unit: sport catalogue mapping; GPS filtering/smoothing/distance on recorded fixture tracks (a 5 km road run, a trail run
  with switchbacks and bad fixes, a stationary phone) with expected distances ±2 %; split computation; auto-pause; crash
  resume from checkpoint; upload queue idempotency; merged-item presentation; manual activity validation (future, > 24 h,
  end < start).
- Simulator: GPX playback (`xcrun simctl location … start` with a GPX file) for UI tests of Start → record → Finish → Save.
- Device (the user): a real 5 km run with the phone in a pocket and the screen off; compare distance with his tracker; check
  battery drain, the Live Activity, resume after force-quit, and the merged row once Garmin's workout arrives.

## Ship

PRs: `design: activities and recording engine` (note + ADR) · `today: My Day` · `activities: add activity and add sleep` ·
`activities: GPS recording engine` · `activities: recording UI, Live Activity, finish and upload` · `activities: privacy
zones and route opt-in` · `health: save activities with route to Apple Health` · `docs: activities`. Needs-you: Background
Modes → Location in Xcode, the platform brief first, privacy policy/App Privacy update, a device test run.

---

# Part P — paste into the platform session (`../plattform/CLAUDE_FOLLOWUP_ACTIVITIES.md` has the same text)

See that file.
