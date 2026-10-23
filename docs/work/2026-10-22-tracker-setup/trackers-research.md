# Tracker research: what reaches Apple Health (R1)

> **Correction from a device check (2026-10-22, lead).** On the user's iPhone 16 Pro (iOS 27.0.1, Garmin Connect),
> Apple Health holds **daily resting-heart-rate samples from Garmin Connect, stamped 00:00**, and **sleep with stages**.
> Garmin's FAQ omits both. The catalog now says `resting_hr: yes`, `sleep_stages: yes` for Garmin (catalog
> 2026-10-22.3). HRV, breathing rate and SpO₂ were absent, as the FAQ says. Oura's resting HR is still only from
> Oura's docs.

Checked: **2026-10-22**. Scope: ticket R1 of `CLAUDE_FOLLOWUP_TRACKER_SETUP.md` (§2 setup cards, §3 sync check).
Data file: `trackers.draft.json` (same folder). Vendor names are used only as data sources.

**Method.** Vendor help pages were fetched raw and quoted verbatim. Zendesk help centres (Oura, COROS, Withings) were read
through their article API, which gives `updated_at`. Garmin's support site returns a Cloudflare 403 to scripts, so its
FAQ was read on 2026-10-22 through a reader proxy and cross-checked against two Wayback snapshots of the same official
page; the bodies are identical. Bundle IDs come from Apple's iTunes Lookup API (`https://itunes.apple.com/lookup?id=…`).
Anything only third parties state is marked `unverified`.

---

## 0. Corrections to the brief

| Brief says | Current fact (source) |
|---|---|
| "Fitbit … don't write to Apple Health natively" | **Outdated.** The Fitbit app is now **Google Health** (App Store: "Google Health (Fitbit)"). Google's help page documents writing HR, resting HR, SpO₂, respiratory rate, sleep and stages, exercise and steps to Apple Health. It **reads HRV but does not write it.** ([Google](https://support.google.com/googlehealth/answer/17037331?hl=en)) |
| Garmin: "More → Settings → **Connected** Apps" | Garmin's FAQ says **"Connect Apps"** → Apple Health under "Available Apps" → **Connect with Apple Health**. |
| iOS: "Settings → Health → Data Access & Devices" | Apple's current iPhone User Guide (iOS 26 and **iOS 27**) and its 2026-09-14 support article document only **Health app → Summary → your picture → Privacy: Apps**. Withings (2026-10-20) documents **Settings → Apps → Health → Data Access & Devices**; Oura still writes "Settings > Health > Data Access & Devices". Use the Health-app route in the copy. |
| Garmin/Polar/COROS/Suunto: "enable Background App Refresh" | Garmin says the opposite: it sends **only while Connect is open in the foreground**. Polar, COROS and Suunto don't document Background App Refresh (unverified). Only **Oura** documents Background App Refresh and Low Power Mode. |
| Garmin HRV not in Apple Health | **Confirmed** (below). Garmin also doesn't send **resting heart rate**, respiration or Pulse Ox. |
| Oura HRV export "reported missing" | **Confirmed by Oura's own list** (below). Oura doesn't send resting HR or SpO₂ either. |
| (new) | Garmin: "After enabling sharing, the Health app imports your past data going back **up to two weeks**." A newly connected Garmin user therefore has at most ~14 days of history in Apple Health. |
| (new) | Withings: accounts created **on or after 2026-10-13** need **Withings+** to export to Apple Health. |
| (new) | Oura: Apple Health needs **Gen2**, or **Gen3 or later with active membership**. |

### Verdicts on the two key facts

- **Garmin HRV: not written.** Garmin's FAQ "Sharing Your Garmin Connect Data With Apple Health" (KB `KM1009574`,
  <https://support.garmin.com/en-US/?faq=lK5FPB9iPF5PXFkIpFlFPA>) lists everything Apple Health receives: *"Active
  Energy · Body Fat Percentage · Body Mass Index · Flights Climbed · Heart Rate · Resting Energy · Sleep Analysis · Steps
  · Walking + Running Distance · Water · Weight · Workouts (activities uploaded to Garmin Connect)"*. HRV, resting heart
  rate, respiration and SpO₂ are absent. Text verified live on 2026-10-22 and identical in snapshots of 2026-03-19
  (contentVersion 32) and 2026-05-16 (contentVersion 36).
- **Oura HRV: not written.** Oura's "Apple Health Integration" (last updated 2026-10-14,
  <https://support.ouraring.com/hc/en-us/articles/360025438734-Apple-Health-Integration>), section *"Exported from Oura
  to Apple Health"*: *"Active Energy … Heart Rate: in one-minute intervals · Height · Mindful Minutes · Respiratory Rate:
  average nighttime respiratory rate · Sleep (Sleep Duration, Start Time, End Time, Sleep Stages) · Steps · Weight ·
  Workout Routes · Workouts"*. HRV, resting HR and SpO₂ are absent.

---

## 1. Summary matrix

Legend: ✓ yes · ◐ partial · ✗ no · ? unverified. "Breath." = respiratoryRate, "Stages" = REM/Core/Deep values.

| Tracker | HR | HRV | Rest. HR | Sleep | Stages | Breath. | SpO₂ | Workouts | Steps |
|---|---|---|---|---|---|---|---|---|---|
| Apple Watch | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ◐ | ✓ | ✓ |
| Garmin | ✓ | ✗ | ✗ | ✓ | ? | ✗ | ✗ | ✓ | ✓ |
| Oura | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ |
| Polar | ◐ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ |
| Suunto | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| COROS | ✓ | ✗ | ✗ | ✓ | ? | ✗ | ✗ | ✓ | ✓ |
| Withings | ◐ | ? | ? | ? | ? | ? | ? | ? | ? |
| Amazfit (Zepp) | ? | ◐ | ? | ? | ? | ? | ? | ✓ | ? |
| Ultrahuman | ✓ | ? | ? | ? | ? | ? | ? | ✓ | ? |
| Fitbit (Google Health) | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Samsung Galaxy Watch | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Other | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Just my iPhone | ◐ | ✗ | ✗ | ◐ | ✗ | ✗ | ✗ | ◐ | ✓ |

**HRV on iPhone (for Readiness):** documented only for Apple Watch, plus Amazfit Balance 2. Ultrahuman is unverified.
Every other tracker here documents **no HRV** in Apple Health.

---

## 2. Proposed schema (`trackers.draft.json`)

```jsonc
{
  "schema_version": 1,                 // bump on breaking change; app rejects unknown major
  "checked": "2026-10-22",             // newest check across entries
  "status_values": ["yes","partial","no","unverified"],
  "trackers": [ {
    "id": "garmin",                    // stable slug; stored in User.trackers; never renamed
    "name": "Garmin",                  // tile label (brand as data source)
    "app_name": "Garmin Connect",      // for "Open <app_name>"; null when there's no app to open
    "integration": "vendor_app",       // apple_builtin | vendor_app | none | unknown
    "healthkit": {
      "bundle_ids": ["com.garmin.connect.mobile"],      // exact HKSource.bundleIdentifier
      "bundle_id_prefixes": ["com.garmin.connect.mobile"], // prefix match (covers watch/extension targets)
      "source_names": ["Connect"],     // HKSource.name as shown in Health (fallback match + display mapping)
      "device_models": [],             // HKDevice.model for Apple devices ("Watch", "iPhone")
      "verified": { "bundle_ids": true, "source_names": true }
    },
    "app_store_id": "583446403",       // string; link https://apps.apple.com/app/id<id>
    "app_store_url": "https://apps.apple.com/us/app/garmin-connect/id583446403",
    "capabilities": { "heart_rate": "yes", "hrv": "no", "resting_hr": "no", "sleep": "yes",
                      "sleep_stages": "unverified", "respiratory_rate": "no", "spo2": "no",
                      "workouts": "yes", "steps": "yes" },
    "capability_notes": { "hrv": "…" },// optional, en, keyed like capabilities
    "setup_steps": ["…"],              // en, imperative, ordered; vendor app first, then the Health app check
    "habits": ["…"],                   // en; only vendor-documented or clearly established
    "limits": ["…"],                   // en, optional
    "help_url": "https://…",           // primary vendor page
    "sources": [ { "url": "…", "covers": "…" } ],  // provenance per fact group
    "checked": "2026-10-22"
  } ]
}
```

Notes for the app (§3 sync check):
- **Expected vs unexpected ✗:** `no` means "the vendor documents that it isn't sent", so treat it as expected ✗. `yes` or
  `partial` with nothing in 48 h is an unexpected ✗: show the setup steps again. `unverified` with nothing should read
  "not seen yet", never an error.
- **Matching:** match `HKSource.bundleIdentifier` by `bundle_id_prefixes` first, then `source_names`. Apple devices
  have no stable bundle ID: match `HKDevice.model` (`"Watch"` / `"iPhone"`) plus the `com.apple.health.` prefix.
  Apple doesn't document this pattern, so treat it as unverified and test it on a device.
- **Display names:** map `source_names` → `app_name` ("Connect" → "Garmin Connect").
- **German:** `setup_steps`, `habits`, `limits` and `capability_notes` are English only; the localization-editor adds
  `_de` arrays or a keyed variant later. Suggestion: `"setup_steps": {"en": [...], "de": [...]}` from v2.

---

## 3. The iOS side (iOS 26 and iOS 27)

- **Documented by Apple, iOS 27** (iPhone User Guide "Share your data in Health on iPhone", `os_version: iOS 27`,
  article v15; same wording in the iOS 26 guide): *"Go to the Health app on your iPhone. Tap Summary, then tap your
  picture or initials. Below Privacy, tap Apps or Devices. … To change the access for an item, tap it, then turn on or
  off permission to write data to—or read data from—Health."*
  <https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios>
- Apple support article 108779 (published 2026-09-14): *"Tap the Profile button in the upper corner. Under Privacy,
  tap Apps … You might need to open the app and adjust its settings to allow it to share data with Health."*
  <https://support.apple.com/en-us/108779>
- **Settings route:** not in Apple's current docs. Withings (updated 2026-10-20): *"Open your iPhone Settings. Navigate
  to Apps > Health > Data Access & Devices."* Oura (2026-10-14): *"Settings > Health > Data Access & Devices > Oura"*.
  Unverified for iOS 27.
- Vendors name the Health-app row differently: Garmin "Apps and Services", Google "Sharing tab → Apps", Apple "Apps".
  The JSON uses Apple's wording: **"Health → Summary → your picture → Apps → <source> → Turn On All."**
- **Priority:** *"If multiple sources contribute the same data type, the data source at the top will take priority …
  New apps or devices that you add are listed at the top automatically."* (108779). Garmin and Polar both point users to
  this when data seems missing.

---

## 4. Per tracker

### Apple Watch
- **What reaches Health:** Apple's iOS 27 guide says *"periodic heart rate and blood oxygen measurements are
  automatically sent from Apple Watch to Health"*.
  - HRV: per HealthKit's `heartRateVariabilitySDNN` doc, *"HealthKit uses SDNN … The system automatically records
    samples on Apple Watch."*
  - Resting HR: *"the system estimates the resting heart rate by analyzing sedentary heart rate samples … the system
    may delete earlier samples and replace them with better estimates. Apple Watch replaces only the samples written by
    the watch for the current or previous day."* (HealthKit `restingHeartRate`) → the sync must handle deletions.
  - Respiratory rate: *"The system automatically records samples on Apple Watch."*
  - Sleep (108906): *"Stages: … Awake or in REM, Core, or Deep sleep"*, with heart rate and respiratory rate shown
    against sleep. *"Respiratory Rate is not available for users under 13 years old."*
  - SpO₂ (120358): Series 6 or later and all Ultra; *"not supported on Apple Watch SE"*. US watches bought on or after
    2024-01-18 with part numbers LW/A or LS/A: *"the Blood Oxygen data analysis is performed on iPhone, and results can be
    viewed in the Health app."* *"All blood oxygen measurements … are saved in the Health app."*
  - New in 2026: Series 12 and Ultra 4 show "Recovery HRV" and continuous green-LED heart rate (120277). This doesn't
    change what HealthKit receives.
- **Source identity:** samples come from the watch, and `HKSource.name` is the user's watch name. The bundle ID is
  `com.apple.health.<UUID>` by convention (**unverified**). Use `HKDevice.model == "Watch"`.
  App Store: Watch app `1069511734` (`com.apple.Bridge`); Health `1242545199` (`com.apple.Health`).
- **Setup:** Health → Summary → your picture → Devices → your Apple Watch → Privacy Settings → Fitness Tracking on
  (108779). Set a sleep schedule and turn on Track Sleep with Apple Watch (108906).
- **Habits:** wear it to bed; turn on Charging Reminders (Watch app → My Watch → Sleep).
- **Limits:** SpO₂ model limits; respiratory rate not available under 13.

### Garmin (Garmin Connect)
- **What reaches Health:** the list in §0.
  - *"Garmin syncs all-day heart rate to Apple Health, but only sends high/low HR values for timed activities."*
  - Workouts: *"Any associated GPS track will NOT be written to Apple Health."*
  - Sleep stages: Garmin doesn't say. Notebookcheck and gadgetsandwearables (Sept 2023) report stages since Connect
    4.71 → **unverified**. The sync check can confirm on a device.
- **Source identity:** source name **"Connect"**. Garmin: *"Select the Connect app"* and *"Connect will not appear as an
  option in Apple Health if you only have an Edge® cycling computer registered"*. Bundle ID
  `com.garmin.connect.mobile` (verified). App Store `583446403`.
- **Setup (Garmin):** *"Open the Garmin Connect app. Select More. Select Settings. Select Connect Apps. Select Apple
  Health under 'Available Apps.' Select Connect with Apple Health. Select the items that Garmin Connect can access.
  Select Allow."* Health side: Summary → Profile → Apps → Connect → toggle categories.
- **Keep it flowing:**
  - *"Garmin Connect must be open in the foreground to send data to Apple Health. If closed, the transfer pauses and
    completes only on the next sync performed while the app is open."*
  - *"Once enabled, Garmin Connect syncs data to Apple Health after each successful device sync."*
  - Backfill: *"the Health app imports your past data going back up to two weeks."*
  - Background App Refresh: not documented by Garmin; the foreground statement suggests it doesn't help.
- **Limits:** no HRV, resting HR, respiration or SpO₂; workout HR only as high/low values; no GPS tracks.

### Oura
- **What reaches Health:** export list in §0. Oura notes *"Your sleep stages and heart rate graphs may appear
  differently … Apple may apply slight rounding"*.
- **Source identity:** **"Oura"** (*"Data Access & Devices > Oura > Allow "Oura" to Write"*). Bundle ID
  `com.ouraring.oura` (verified). App Store `1043837948`.
- **Setup:** *"Tap the menu in the upper-left corner … Tap Settings. Under "Data sharing," tap Apple Health. Enable …
  Connect to Health; Save Mindful Minutes to Health"*.
- **Keep it flowing:**
  - Oura blog (2024-02-05): *"Your Apple Health data syncs only after opening Oura."*
  - Help page: *"might not import data from integrations if both apps were not opened before midnight, if "Background App
    Refresh" is disabled …, or if "Lower Power Mode" is enabled. Open both Oura and the integrated app at least once a
    day."* This sentence is about imports. We apply it to export as well, which Oura doesn't strictly say.
- **Limits:** no HRV, resting HR or SpO₂; respiratory rate is one nightly average. *"Apple Health integration is
  available for: Gen2; Gen3 or later with active membership; iOS only."*

### Polar (Polar Flow)
- **What reaches Health** (Polar, "Connecting Polar Flow with Apple Health"):
  - *"Heart rate: heart rate during workouts. Note! Continuous heart rate is not synced."*
  - *"Sleep Analysis: sleep duration, time of falling asleep, time of waking up."*
  - Steps: *"step amount measured by your Polar device"*.
  - Workouts: *"type …, duration, distance, start time, end time, workout samples (Total Active Energy & Average Heart
    Rate)"*.
  - Also Active Energy, Resting Energy and Weight. Nothing else is sent.
- **Source identity:** **"Polar Flow"** (*"Go to Apps and select Polar Flow"*). Bundle ID `fi.polar.polarflow`
  (verified). App Store `717172678`.
- **Setup:** *"Open Polar Flow app, tap More bottom right and go to General settings. Tap the Apple Health toggle …
  Select which categories … or tap Turn All Categories On. Tap Allow"*.
- **Keep it flowing:** *"all new data in Polar Flow app will be synced to Apple Health"*. Troubleshooting: *"Tap Sync
  now button under the Apple Health toggle. This will sync last two weeks data again"*. Foreground or background
  behaviour isn't documented (unverified).
- **Limits:** no all-day HR, HRV, resting HR, stages, respiration or SpO₂.

### Suunto
- **What reaches Health:** Suunto publishes no data-type list. Its App Store text says only *"The Suunto app connects
  with Apple Health. Go to app settings to start sharing your data."* Suunto's help site is behind a bot check, and its
  archived FAQ index (≈75 Suunto-app articles) has no Apple Health article. Suunto forum users (not official) report
  workouts (no GPS), steps, HR and calories arriving, and no sleep, HRV or SpO₂ → all **unverified**.
- **Source identity:** bundle ID `com.sports-tracker.suunto.iphone` (verified). Source name "Suunto" is
  **unverified** (App Store name; forum posts say "Sources > Suunto"). App Store `1230327951`.
- **Setup:** only the App Store sentence above; no documented menu path. **Habits:** none documented.

### COROS
- **What reaches Health** (COROS, updated 2026-10-19): *"Select "COROS" and enable supported data types. Cycling
  Distance · Heart Rate · Sleep Analysis · Steps · Swimming Distance · Walking + Running Distance"*.
  - Workouts: release notes V3.1.6 (2023-08-21): *"Your activities synced to Apple Health will now differentiate
    between indoor/outdoor running and cycling…"*.
  - **Conflict:** COROS "Exporting Workout Data…" (2026-09-29) lists Apple Health among platforms that receive newly
    recorded workouts *"when your COROS watch syncs"*, and says *"Daily data is not supported for integration or
    export."* The Apple Health article and the App Store text (*"Sync steps, heart rate and other data … using
    HealthKit"*) say daily HR and steps are sent. Treated as yes; the sync check will show the truth.
- **Source identity:** **"COROS"** (verified). Bundle ID `com.coros.coros` (verified). App Store `1277625343`. Note:
  `ai.coros.app` ("COROS AI") is a separate app.
- **Setup:** *"Go to the COROS app > Profile page > Setting > 3rd Party Apps > Data Sync > Apple Health"*, then select
  data types.
- **Keep it flowing:** workouts are pushed when the watch syncs; *"Please ensure that the internet connection is strong
  and stable when you sync"*.
- **Limits:** no HRV, resting HR, respiration or SpO₂.

### Withings
- **What reaches Health:** Withings lists the *"data categories that can be shared between the apps"* (updated
  2026-10-22) with no direction. The list includes Heart Rate, **Heart Rate Variability**, Resting Heart Rate, Blood
  Oxygen, Respiratory Rate, Sleep, Steps, Workouts, ECG and more. Per-type export is therefore **unverified**.
  Explicit: *"Sleep Analyzer heart rate data does not sync to Apple Health."* (and the same for "Sleep (U.S.)") →
  heart rate partial.
- **Source identity:** **"Withings"** (*"Select the Withings app"*); the app was formerly Health Mate, and the legacy
  source name "Health Mate" on old samples is **unverified**. Bundle ID `com.withings.wiScaleNG` (verified). App Store
  `542701020`.
- **Setup:** *"Go to your Profile … Tap Settings (gear icon) … Tap Export health data to Apple Health … Tap Next … Toggle
  any data on … tap Allow … tap Done."*
- **Keep it flowing:** *"Due to an iOS restriction, the syncing of data to and from Apple Health is not automatic. …
  Open the Withings App. Open Apple Health. Return to the Withings App and swipe down from the top of the Home tab to
  force a refresh."* *"wait at least 15 minutes after you have added data."*
- **Limits:** *"Any account created after October 13th, 2026 will be asked to sign up for a Withings+ subscription in
  order to export their Withings data to third party apps like Apple Health"*; sleep-mat HR excluded.

### Amazfit (Zepp)
- **What reaches Health:**
  - Amazfit (2026-08-26, Balance 2 series update): *"Amazfit Balance 2 Series now support syncing HRV data to Apple
    Health."* → HRV partial.
  - Helio Strap specs: *"Third-Party Workout Data Sync: Strava, adidas Running, … Apple Health"* → workouts yes.
  - No official per-type list exists. Third-party sites claim steps, HR, sleep and SpO₂, plus HRV for Helio Strap
    → unverified.
- **Source identity:** bundle ID `com.huami.watch` (verified). Source name "Zepp" is **unverified**; Amazfit says *"add
  Zepp app as the data source"*. App Store `1127269366`. `HM.wristband` is the separate legacy "Zepp Life" app.
- **Setup:** Amazfit (2024-12-19): *"For Apple Health/Google Fit, please add Zepp app as the data source in them."*
  Third parties name the in-app path "Profile → Connected Apps → Apple Health", which is **unverified**.
- **Habits:** none documented.

### Ultrahuman
- **What reaches Health:** Ultrahuman blog (2025-05-30): *"datapoints such as heart rate variability, temperature or
  energy expenditure, which are tracked by the Ultrahuman Ring AIR, can be found within the Apple Health app."* The
  same post's screenshot of the Health permission screen (uploaded 2024-06) shows **write** for *Active Energy, Heart
  Rate, Mindful Minutes, Walking + Running Distance, Workout Routes, Workouts*, with no HRV, sleep or steps. HR and
  workouts are therefore verified; **HRV is unverified** (vendor text and vendor screenshot conflict); the rest is
  unverified. App Store text: *"enjoy hassle-free data syncing with Apple Health"*.
- **Source identity:** **"Ultrahuman"** (verified from the screenshot). Bundle ID `com.ultrahuman.ios` (verified). App
  Store `1491286709`.
- **Setup (blog):** Health app → Profile → Apps → Ultrahuman → *"Turn All Categories On"*. **Habits:** none documented.

### Fitbit (Google Health app)
- **What reaches Health** (Google, "How do I use Apple Health with the Google Health app?"): *"Share data from Google
  Health to Apple Health."* The table *"Data types that Google Health can write to Apple Health"* covers Steps, VO2 max,
  Floors, Active calories, Distance, **Exercise**, Exercise routes, Body temperature, **Sleep session, Sleep stages**,
  **Heart rate, Oxygen saturation, Respiratory rate, Resting heart rate**, Blood glucose, Weight, Fat percentage,
  Nutrition, Water, Mindfulness and cycle data. The read-only column adds **Heart rate variability** and Skin
  temperature, so **HRV is not written.**
- **Source identity:** **"Google Health"**. Google: *"In the Apple Health app, tap the Sharing tab. Scroll, then tap Apps
  Google Health."* Bundle ID `com.fitbit.FitbitMobile` (verified; App Store name "Google Health (Fitbit)"). App Store
  `462638897`.
- **Setup:** *"Open the Google Health app. At the top left, tap Connections Apps and services. Under "Add connections"
  tap Apple Health … tap Get started … tap Agree … tap Turn All Categories On … tap Allow … tap Done."* Requirements:
  *"iOS 16.4 or higher"*; *"an adult Google Account"*.
- **Keep it flowing:** keep the app updated; grant permissions when *"New data types available"* appears. Whether the
  app must be opened to write is undocumented (unverified). Press reports (MacRumors, Droid-Life, 2026-08-03) name app
  version 5.05 as the release; Google's page doesn't name a version (unverified).
- **Note for sync-engineer:** Google Health also reads from Apple Health. Google doesn't document whether data it read
  is written back. Match on source and deduplicate.

### Samsung Galaxy Watch
- Samsung US support: *"Newer Samsung watches with Wear OS are not compatible with iOS."* *"Galaxy Watch4, Watch5,
  Watch6, Watch7, Watch Ultra, and Watch FE: These watches rely on Google Play services which is not supported on
  iOS."* Older Tizen models (Galaxy Watch 2018, Active, Active2, Watch3) pair through "Samsung Galaxy Watch (Gear S)"
  (`com.samsung.gearwatch`, last updated 2022). Samsung Health for iOS (`com.samsung.health`, `1224541484`) says it
  *"is currently compatible with … Galaxy Watch Active2, Galaxy Watch3 and Galaxy Fit2 only"* and only *reads* steps
  from Apple Health. No Samsung document mentions writing to Apple Health → all ✗ for current watches; older-model
  export is unverified.
- **Limit text:** "RYFT can't read Galaxy Watch data on iPhone today."

### Other
Generic steps only. Apple: *"You might need to open the app and adjust its settings to allow it to share data with
Health."* Capabilities are all `unverified`; the sync check is the source of truth.

### Just my iPhone
- Apple's iOS 27 guide, *"Health data from iPhone"*:
  - *"Steps, flights of stairs, and other walking data: Built-in sensors on your iPhone capture the number of steps you
    take, the number of flights of stairs you climb, your walking speed"*
  - Mobility: walking asymmetry, double support time, walking steadiness.
  - Headphone audio levels.
  - *"Sleep history: If you set up a sleep schedule in Health, iPhone estimates the periods you're lying in bed with the
    intention to sleep."* → in bed only, no stages.
- **No heart rate from iPhone itself.** Walking heart rate average is an Apple Watch metric. With **AirPods Pro 3**:
  *"You can view your heart rate data in the Health app"*. Workouts can be started from *"the Fitness app on your
  iPhone. Tap the Workout tab."* (123184). Hence HR and workouts are partial.
- Source identity: the iPhone's device name; `HKDevice.model == "iPhone"`; `com.apple.health.` prefix (unverified).
- Setup: Settings → Privacy & Security → Motion & Fitness → Fitness Tracking. Apple documents the Motion & Fitness
  category; Polar names the Fitness Tracking toggle. Set a sleep schedule.

---

## 5. Bundle IDs and App Store IDs

All verified with the iTunes Lookup API on 2026-10-22 (`https://itunes.apple.com/lookup?id=<id>`).

| Tracker | App (store name) | Bundle ID | App Store ID | HealthKit source name |
|---|---|---|---|---|
| Garmin | Garmin Connect™ | `com.garmin.connect.mobile` | 583446403 | Connect ✔ |
| Oura | Oura | `com.ouraring.oura` | 1043837948 | Oura ✔ |
| Polar | Polar Flow | `fi.polar.polarflow` | 717172678 | Polar Flow ✔ |
| Suunto | Suunto | `com.sports-tracker.suunto.iphone` | 1230327951 | Suunto (unverified) |
| COROS | COROS | `com.coros.coros` | 1277625343 | COROS ✔ |
| Withings | Withings | `com.withings.wiScaleNG` | 542701020 | Withings ✔ (legacy "Health Mate" unverified) |
| Amazfit | Zepp | `com.huami.watch` | 1127269366 | Zepp (unverified) |
| Ultrahuman | Ultrahuman | `com.ultrahuman.ios` | 1491286709 | Ultrahuman ✔ |
| Fitbit | Google Health (Fitbit) | `com.fitbit.FitbitMobile` | 462638897 | Google Health ✔ |
| Apple Watch | Watch | `com.apple.Bridge` (app); samples `com.apple.health.<UUID>` (unverified) | 1069511734 | device name |
| iPhone | Apple Health | `com.apple.Health` (app); samples as above (unverified) | 1242545199 | device name |
| Samsung | (none usable) | `com.samsung.gearwatch` / `com.samsung.health` (older models only) | 1117310635 / 1224541484 | n/a |

✔ = the vendor's help text shows that name inside Apple Health. Companion watch apps may write under a different bundle
ID (e.g. `<bundle>.watchkitapp`), so prefix matching is recommended.

---

## 6. Everything `unverified`

1. **Garmin sleep stages.** Only third-party reports (Connect 4.71, Sept 2023); Garmin says "Sleep Analysis".
2. **Garmin, Polar, COROS, Suunto, Zepp, Ultrahuman, Google Health and Background App Refresh.** Not documented.
   Garmin's foreground statement suggests Background App Refresh doesn't help Garmin.
3. **Suunto.** Every signal, its source name "Suunto", its setup path and its habits. No official doc beyond the App
   Store sentence.
4. **COROS.** Whether all-day HR and steps really arrive, given "Daily data is not supported…", and sleep stages.
5. **Withings.** Export direction for HRV, resting HR, SpO₂, respiratory rate, sleep and stages, workouts and steps;
   the legacy source name "Health Mate".
6. **Amazfit (Zepp).** HR, resting HR, sleep and stages, respiration, SpO₂ and steps; HRV for any model other than
   Balance 2 (a third-party claim names Helio Strap); the source name "Zepp"; the in-app setup path; habits.
7. **Ultrahuman.** HRV (vendor text and vendor screenshot conflict); resting HR, sleep and stages, respiration, SpO₂
   and steps; habits.
8. **Google Health.** Version 5.05 as the first version with export (press only); whether the app must be opened to
   write; whether data it read from Apple Health is written back.
9. **Samsung.** Apple Health export for older Tizen Galaxy Watch models.
10. **Apple devices.** `com.apple.health.<UUID>` as the sample bundle ID, and the source name being the device name
    (convention, not documented). Use `HKDevice.model`.
11. **iPhone.** Whether the Fitness app's Workout tab records workouts without AirPods Pro 3 (Apple documents it in the
    AirPods context).
12. **iOS Settings route** ("Settings → Apps → Health → Data Access & Devices") on iOS 27. Vendors document it; Apple
    doesn't.
13. **Oura export-side Background App Refresh and Low Power Mode.** Oura's sentence is about imports. That the data
    *"syncs only after opening Oura"* is verified.

---

## 7. Sources (all checked 2026-10-22)

- Apple:
  - <https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios> (iOS 27)
  - <https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/26.0/ios/26.0> (iOS 26)
  - <https://support.apple.com/guide/iphone/intro-to-health-data-iphbb8259c61/ios>
  - <https://support.apple.com/en-us/108779>
  - <https://support.apple.com/en-us/108906>
  - <https://support.apple.com/en-us/120277>
  - <https://support.apple.com/en-us/120358>
  - <https://support.apple.com/en-us/123184>
  - <https://support.apple.com/guide/watch/heart-rate-apda88aefe4c/watchos> (watchOS 27)
  - HealthKit docs: `heartRateVariabilitySDNN`, `restingHeartRate`, `respiratoryRate`
- Garmin:
  - <https://support.garmin.com/en-US/?faq=lK5FPB9iPF5PXFkIpFlFPA> (live via reader proxy; Wayback 2026-03-19 v32,
    2026-05-16 v36)
- Oura:
  - <https://support.ouraring.com/hc/en-us/articles/360025438734-Apple-Health-Integration> (updated 2026-10-14)
  - <https://ouraring.com/blog/apple-health/>
- Polar:
  - <https://support.polar.com/us-en/support/connecting_polar_flow_with_apple_health>
- COROS:
  - <https://support.coros.com/hc/en-us/articles/360041549551> (2026-10-19)
  - <https://support.coros.com/hc/en-us/articles/360043975752> (2026-09-29)
  - <https://support.coros.com/hc/en-us/articles/5146420791060> (2026-09-28)
- Withings:
  - <https://support.withings.com/hc/en-us/articles/46746224229777> (2026-10-21)
  - <https://support.withings.com/hc/en-us/articles/203934573> (2026-10-22)
  - <https://support.withings.com/hc/en-us/articles/203956733> (2026-10-20)
  - <https://support.withings.com/hc/en-us/articles/51884299827601> (2026-10-13)
  - <https://support.withings.com/hc/en-us/articles/360000158447>
  - <https://support.withings.com/hc/en-us/articles/4411186122641>
- Amazfit:
  - <https://us.amazfit.com/blogs/product-update/amazfit-balance-2-series-august-2026-update-a-smarter-training-experience-with-zepp-os-6>
  - <https://us.amazfit.com/products/helio-strap>
  - <https://support.amazfit.com/en/amazfit_gts_2_mini/docs/N6cUdJxDRo6rbfxiLs1cJDBrnRd>
- Ultrahuman:
  - <https://www.ultrahuman.com/blog/how-to-access-your-hrv-data-on-apple-health/>
- Google:
  - <https://support.google.com/googlehealth/answer/17037331?hl=en>
  - <https://support.google.com/googlehealth/answer/14236613?hl=en>
- Samsung:
  - <https://www.samsung.com/us/support/answer/ANS10004668/>
  - <https://www.samsung.com/ae/support/mobile-devices/galaxy-wearables-that-are-compatible-with-ios/>
- App Store: iTunes Lookup and Search APIs (bundle IDs, store names, descriptions).
- Third-party, cited only as `unverified` context:
  - Notebookcheck and gadgetsandwearables.com (Garmin sleep stages, 2023)
  - forum.suunto.com (user reports)
  - MacRumors and Droid-Life (Google Health 5.05, 2026-08-03)
