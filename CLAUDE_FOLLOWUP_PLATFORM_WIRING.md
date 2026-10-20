# RYFT iOS — wire every platform function into the app — follow-up for the Xcode session

State (2026-10-19, from both repos). The platform is ahead of the app. Deployed on
`https://api.ryftapp.de` with the Apple and APNs keys active: the sleep upgrades (M4),
remote config + push (M7 core), Train (M3b), accounts and deletion. Committed and
documented but **not deployed yet**: the journal with behavior impact (M5) — check
`../plattform/docs/STATUS.md` before relying on it, and treat `404` on `/v1/behaviors*`
and `/v1/journal/*` as "not live yet" (hide the feature, no error).

The app (20 commits) has accounts, Train, the chart language, the App Store pass and
the first three `arch:` commits (seams, `@Observable` view models, SwiftData read models
behind `Repository`). The working tree holds the **uncommitted** fourth step:
`SyncCoordinator` driving every sync, `BackgroundWork` (refresh + nightly
`repository.compact()`, new `processing` background mode and
`dev.timkrebs.ryft.compact` identifier), and the Associated Domains entitlement emptied
(the user removed it on purpose — no AASA is hosted yet; keep it empty).

`Environment/PlatformAPI.swift` already *declares* `config()`, `registerPush`,
`unregisterPush`, `patchNotifications`, and `Models.swift` has `RemoteConfig`,
`NotificationPrefs`, `NotificationPatch`, `PushRegistration` — but nothing calls them:
flags come from `StaticFlags`, there is no `UNUserNotificationCenter` code, no
notification settings screen, and no push localisation keys. The M4 sleep fields, the
sleep planner, `Workout.muscular_load`, and all of M5 are missing from the mirror.

Read first, in this order: `../plattform/docs/API.md` (Screens → endpoints, Conventions,
Errors, then the sections named below and the Swift mirror), `../plattform/docs/STATUS.md`
(what is deployed), `CLAUDE.md`, `docs/STATUS.md`, `docs/API_REQUESTS.md`,
`docs/CHART_STYLE.md`. Then run through the sections below in order; each ends in a
commit. `Ryft.xcodeproj` is the source of truth — add files through the project, never
regenerate it. Command-line `xcodebuild test` does not work from your environment
(pseudo-terminal EPERM), so write the tests, build with `xcodebuild build`, and ask the
user to run the test plan in Xcode once per section.

Goal: every endpoint and every field in `API.md` has a reader in the app, and every
screen in its "Screens → endpoints" table exists. Numbers first, AI last; the design
rules from `docs/CHART_STYLE.md` apply to everything new.

## 0. Land the uncommitted architecture step

Review the diff (`git diff --stat`), finish what is half done (the deleted tests in
`EnvironmentTests` / `SyncCoordinatorTests` need replacements that exercise the new
`BackgroundWork` + coordinator path), make sure `BGTaskSchedulerPermittedIdentifiers`
and `UIBackgroundModes` match the code, build, and commit:
`arch: SyncCoordinator owns every sync; BackgroundWork refresh and compaction`.
Nothing below starts on a dirty tree.

## 1. Mirror catch-up (`Networking/Models.swift`, fixtures)

Add what `API.md`'s Swift mirror has and the app lacks. Field names are the JSON names
in `snake_case` → `camelCase` through the existing decoder; everything new is optional
unless the mirror says otherwise.

- `DailyScore`: `napMin`, `sleepQuality`, `sleepConsistency`, `sleepNeedBaseMin`,
  `sleepNeedStrainMin`, `sleepNeedDebtMin`, `sleepNeedNapMin`.
- `SleepDetail` (in `DayDetail.sleep`): `need: SleepNeed` (`base, strain, debt,
  napCredit, total`), `restorative`, `qualityLabel` if not yet typed (closed enum
  `good|fair|poor`).
- `SleepRange`: `avgConsistency`, `bedtimes: [SleepBedtime]` (`day, bed, wake`);
  `SleepDay`: `consistency`, `napMin`.
- `SleepPlan` (`GET /v1/sleep/plan`): `wake, needMin, inBedMin, efficiency, bedtime100,
  bedtime85, bedtime70, basis {base, strainTopup, debtTopup, napCredit, efficiency}`.
- `User`: `sleepBaseSource` (closed enum `default|learned|manual`),
  `sleepBaseLearnedMin`, `sleepBaseLearnedAt`, `notifications: NotificationPrefs`.
  `UserPatch`: `sleepBaseManual: Bool?`.
- `Workout`: `muscularLoad`, `sessionId`. `DayStrain`: `muscularTrimp`, `sessions`.
- Trend metrics: `sleep_quality`, `sleep_consistency`, `nap_min` join `TrendMetric`.
- `Insight.kind` must tolerate unknown values (decode to a `.other(String)` case or keep
  it a `String` with a known-kinds helper) — the platform has added
  `sleep-consistency-low`, `nap-credit`, `baseline-learned`, `pr`, `behavior-impact`
  and will add more. Give each known kind an SF Symbol; unknown kinds get `info.circle`.
- Journal (`API.md` → Journal): `BehaviorKind` (`yes_no|count|time`),
  `BehaviorCategory` (7 values), `ImpactStatus` (`locked|unlocked`), `Behavior`,
  `BehaviorsPatch` (`enabled: [UUID: Bool]`), `BehaviorInput` (`id, name, nameDe?,
  kind, category?`), `JournalEntry` (`behaviorId, valueBool, valueNum?, valueTime?`),
  `JournalDay` (`day, answered, answeredAt?, editable, entries`), `JournalPut`
  (`entries`), `BehaviorEffect` (`delta, ciLo, ciHi, significant, nYes, nNo`),
  `ImpactNeeded` (`yes, no`), `BehaviorImpact`, `BehaviorImpacts` (`windowDays,
  computedAt, impacts`).
- `RemoteConfig.ttlSec` is decoded and used (it is in the JSON; the app ignores it today).
- Regenerate `RyftTests/Fixtures/*.json` from the JSON examples in `API.md` for every
  touched type (`/v1/me`, `/v1/days/{day}`, `/v1/sleep`, `/v1/sleep/plan`, `/v1/config`,
  `/v1/me/notifications`, `/v1/behaviors`, `/v1/journal/{day}`,
  `/v1/behaviors/impact`), one decode test each, and ask the user to run
  `make check-swift` in `../plattform` afterwards.
- `Environment/PlatformAPI.swift`: add `sleepPlan(wake:)`, `behaviors()`,
  `patchBehaviors(_:)`, `createBehavior(_:)`, `deleteBehavior(id:)`, `journal(day:)`,
  `putJournal(day:_:)`, `behaviorImpact()`. Every new method also lands on the protocol
  seam and the in-memory fake used by the view-model tests.

Commit: `contract: M4 sleep, M5 journal, push and config fields mirror API.md`.

## 2. Remote config for real (`GET /v1/config`)

Replace `StaticFlags` as the live provider with `RemoteFlags: FeatureFlagProvider`:
- Load on launch (after a session exists), again when `evaluated_at + ttl_sec` has
  passed and the app becomes active, and on sign-in. Persist the last answer in
  `Repository` (SwiftData, per user) so a cold offline start uses it; with none, the
  compiled defaults in `FeatureFlag.compiledDefault`. Unknown keys are kept but unread;
  a missing known key falls back to the compiled default — exactly as `API.md` says.
- `source(of:)` reports `.remote`, `.compiled` or `.override`; the Debug-only developer
  section lists every flag with its source and lets the user override one locally.
- Gate with it: `train.enabled` → the Train section and tab entry; `sleep.planner` →
  the planner (§4); `today.redesign` → the Today layout variant when it exists;
  `push.enabled` → §3's permission prompt and the Notifications settings;
  `coach.enabled`, `physiology.card` → reserved, read but unused (a `TODO` with the
  flag name, nothing else).
- A flag flip takes effect on the next screen appearance, never mid-interaction (a
  running Train session finishes regardless of `train.enabled`).
- Tests: TTL expiry, fallback order (override > remote > compiled), unknown keys,
  offline cold start.

Commit: `config: remote feature flags with TTL, persisted per user`.

## 3. Push notifications end to end

Capability and entitlement: add **Push Notifications** to the Ryft target (this writes
`aps-environment` into `Ryft.entitlements`; `development` in Debug, `production` in
Release/TestFlight — map it to `PushRegistration.env` `sandbox` / `production` by
reading the entitlement at runtime, not by build flag alone). Leave Associated Domains
empty.

Registration (`API.md` → `POST /v1/devices/{id}/push`):
- Ask for permission **after the first successful sync** and only when `push.enabled`
  is on for this user — never at launch, never on Welcome. The pre-prompt is one
  sentence on Today ("Get your recovery each morning") with "Allow" / "Not now";
  "Not now" is remembered per user and the question returns after 14 days at most once.
- On `didRegisterForRemoteNotificationsWithDeviceToken`: hex-encode, send
  `{token, env, locale}` with the install's `device_id` (the same UUID `/v1/sync` uses).
  Re-send whenever the token, the language or the signed-in user changes; it is
  idempotent. `DELETE /v1/devices/{id}/push` on sign-out and before account deletion
  (both tolerate failure — log and continue). Store `lastRegisteredToken` + `locale` in
  `Repository` so a restart does not re-register needlessly.
- Silent push `{"aps":{"content-available":1},"ryft":{"kind":"refresh","day":"…"}}` →
  `coordinator.run(.silentPush(day))`: refresh that day and Today, finish within the
  30 s background budget, call the completion handler always.
- `UNNotificationCategory` for `MORNING_SCORE`, `SESSION_SCORED`, `PR`, `SYNC_STALE`
  (no actions yet). Tapping a notification routes by `ryft.url` (§6); `SYNC_STALE` has
  no URL and opens Today and starts a sync.
- Localisation: add all 18 keys from the table in `API.md` → Push notifications to
  `Localizable.xcstrings` **exactly** as listed (`%@`, positional `%1$@ %2$@`), en and
  de, marked "manual" so `make lint` does not prune them.
- Notification Service Extension (the ring image via `mutable-content`): **not now**;
  note it in `docs/STATUS.md` as a later item.

Settings (`User.notifications`, `PATCH /v1/me/notifications`): Profile → Notifications
with one toggle per category (names + a one-line "when" each, from the API table), quiet
hours (two time pickers; equal times = off, from > to spans midnight — say so in the
footer), and the system permission state with a link to Settings when denied. Edits are
optimistic and send only the changed field; `422` reverts and shows the inline error.
When `push.enabled` is off the screen explains that notifications are being rolled out
and keeps the toggles disabled.

Tests: token hex encoding, env mapping, re-register conditions, silent-push payload
parsing, `NotificationPatch` encoding (only changed fields, `quiet_hours: null` clears),
category registration. Device verification is in §9.

Commit: `push: registration, silent refresh, categories, notification settings`.

## 4. Sleep upgrades (M4) in Sleep and Profile

Sleep → Day:
- **Need breakdown** under the night's total: a single segmented `RangeBar`-style bar
  `base + strain + debt − nap credit = total` with the four numbers labelled (from
  `DayDetail.sleep.need`), and the sentence "You needed 8 h 58 min: 7 h 40 min baseline,
  +37 min for yesterday's strain, +41 min of debt". Numbers from the API, no rounding
  beyond minutes.
- Quality is its own score now: show `quality` (with `quality_label`) and `restorative`
  as two small tiles next to performance and efficiency; the copy explains quality as
  60 % performance / 20 % efficiency / 20 % restorative (exact weights from `API.md`).
- `nap_min` > 0 → a "Nap · 35 min" chip and a footnote that it lowers tonight's need.
- `consistency` as a third tile when present.

Sleep → Week / Month:
- **Bedtime / wake strip**: one `RangeBar` per night from `bedtimes[]`, aligned on a
  shared clock axis (e.g. 20:00 → 10:00), the mean bed/wake as thin markers; this is
  the consistency visual. `avg_consistency` as the headline number beside
  `avg_quality`.
- Per-night `consistency` and `nap_min` in the per-night detail; trend charts for
  `sleep_quality`, `sleep_consistency`, `nap_min` join the metric picker.

Sleep → Planner (`GET /v1/sleep/plan?wake=HH:MM`, flag `sleep.planner`):
- A wake-time picker (default: the most recent wake time from `bedtimes`, else 07:00),
  the three bedtimes as a vertical list with 100 % / 85 % / 70 % labels and the
  resulting sleep, `in_bed_min` and `efficiency` as the footer, and a "why" disclosure
  with `basis` (base, strain top-up so far, debt top-up, nap credit). Re-query on wake
  change with a 300 ms debounce; offline → the last plan with an "as of" stamp.
  `422` only from a malformed time — the picker cannot produce one, so treat it as a bug.

Profile → Sleep baseline:
- Show `sleep_base_min` with its `sleep_base_source`: "Learned · 7 h 35 min (updated
  Mon)" / "Set by you · 7 h 50 min · learned 7 h 35 min" / "Default · 7 h 40 min". A
  stepper sets a manual value (`PATCH /v1/me {sleep_base_min}` → source becomes
  `manual`); "Use the learned value" sends `{sleep_base_manual: false}`. Follow the
  existing "apply & recompute" pattern; a change does not rescore until the user taps
  recompute (say so).

Insights: render the new kinds (`sleep-consistency-low`, `nap-credit`,
`baseline-learned`) with the chart behind each (`metric` from the insight).

Commit: `sleep: need breakdown, quality and restorative, bedtime strip, planner, baseline source`.

## 5. Journal and behavior impact (M5)

Everything here is behind "the endpoints answer" (a `404` on `GET /v1/behaviors` hides
the Today card and the Profile entry until the platform deploys M5). Cache
`[Behavior]`, each `JournalDay` and the last `BehaviorImpacts` in `Repository`
(offline-first reads; writes need the network and show the Offline pill otherwise).

Today → Journal card: "How was yesterday?" until yesterday's `JournalDay.answered`;
afterwards a compact summary ("Alcohol · 2 drinks, Sauna, Last caffeine 16:30 · Edit").
Tap → the sheet:
- One row per **enabled** behavior, grouped by `category` in `sort` order. `yes_no` →
  toggle; `count` → toggle + stepper (≥ 1 when on); `time` → toggle + time picker
  (`HH:MM`, local). Unanswered rows start off.
- Save → `PUT /v1/journal/{day}` with **every row shown** (off rows as
  `value_bool: false`) — that is what makes a "no"; never send a partial list. `422`
  shows which row (`editable` false → the sheet is read-only with the reason).
- The `DateStrip` lets the user step back up to 14 days (`editable`); days beyond are
  read-only.
- After saving yesterday, refresh `BehaviorImpacts` in the background.

Profile → Journal: the catalog from `GET /v1/behaviors` grouped by category, a toggle per
behavior → `PATCH /v1/behaviors {enabled: {...}}` (whole list back → replace cache).
"Add a behavior": name (1–60), German name (optional), kind, category → `POST
/v1/behaviors` with an app-generated UUID (`201`, or `200` when repeated — both fine;
`409` → "that id is taken", regenerate once; `422` inline). Swipe-to-delete for
`is_custom` only (`DELETE`, `204`); built-ins cannot be deleted (`403`) — do not offer
it.

Insights → Behaviors: a section fed by `GET /v1/behaviors/impact`:
- Unlocked first: "Alcohol · −14 recovery" (delta as **points**, one decimal only when
  |delta| < 10), `n = 12/31`, and the 90 % interval as a thin `RangeBar` centred on 0;
  `significant` → the delta in the metric colour, else muted. Expand → `hrv_pct`
  (percent of the "no" mean) and `sleep_performance` rows the same way; `null` rows
  say "needs 5 nights with HRV".
- Locked: "Sauna · 3 more days with it to unlock" from `needed` (`yes` and/or `no`).
- Footer: `window_days`, `computed_at` ("Last 90 days · computed 06:45").
- The `behavior-impact` insight kind deep-links into this section.

Tests: `JournalPut` always contains every shown behavior; kind → control mapping;
locked/unlocked ordering is taken from the server, not re-sorted; `404` → feature
hidden, no error surfaced.

Commit: `journal: morning sheet, behavior catalog, impact section`.

## 6. Routing from notifications and links

One `AppRoute` enum, one parser, used by `.onOpenURL`, notification taps and the
`behavior-impact` / `pr` insights:
- `https://ryftapp.de/day/YYYY-MM-DD` and `ryft://day/…` → Today on that day;
  `…/train/sessions/{id}` → the session summary; `…/train/exercises/{id}` → exercise
  history; `…/insights/behaviors` → §5's section; `…/sleep/plan` → the planner; `…/auth/…`
  stays with Supabase (`session(from:)`). Unknown paths → Today.
- Universal links stay off until an AASA is hosted (empty Associated Domains); the
  `ryft://` scheme and notification payloads work today. Record the AASA as a platform
  request in `docs/API_REQUESTS.md` (path, team id + bundle id, the paths above).
- Tests: every example URL in `API.md`'s push table parses to the expected route.

Commit: `routes: one parser for links, pushes and insights`.

## 7. Train and Strain leftovers

- `Workout.muscular_load` / `session_id`: the activity row shows the load and links to
  the session; `DayStrain.muscular_trimp` and `sessions` feed the Strain breakdown
  ("Cardio 9.2 · Strength 4.1").
- `GET /v1/exercises/{id}/history` is already wired; make sure PRs from `records` render
  the same four kinds as the `PR_BODY_*` push keys (e1RM, max weight, max reps, max
  volume) with the same wording.

Commit: `strain: muscular load in activities and the day breakdown`.

## 8. Status handling additions (`APIClient`, `APIStatus.swift`)

Extend the status matrix and its tests: `422` carries a field error → inline, never a
sign-out or retry; `409` on `POST /v1/behaviors` (id taken) as a distinct case next to
the existing `409 Session`; `404` on a route the app knows → `.notLive` (feature hidden)
instead of a generic error; `204` on `GET /v1/plans/today` stays "no plan". The
`request_id` reaches every inline error's Details as before.

## 9. Device verification, docs, strings

On a real iPhone, Debug build (sandbox APNs), fresh install: sign in → sync → the
pre-prompt appears → allow → `POST /v1/devices/{id}/push` is `204` (Debug developer
section shows the last status) → the user flips `push.enabled` and allow-lists the
account on the platform side (`OPERATIONS.md` → Feature flags) → the next morning's
`MORNING_SCORE` arrives in German with the ring colour category, the silent push
refreshed Today before the alert, tapping it opens that day. Then: planner with three
bedtimes, need breakdown on a real night, the journal saved for yesterday and read back,
one custom behavior created and deleted, notification toggles round-trip, sign-out
deletes the token (`204`). Record all of it with screenshots in `docs/STATUS.md`
(device vs simulator, what is blocked on M5 deployment).

- German for every new string; `make lint` → 0.
- `docs/STATUS.md`: a "Platform wiring" section with the endpoint → screen coverage
  table (every row of `API.md`'s Screens → endpoints with ✓ / where), the push setup,
  what waits for M5 deployment and the AASA.
- `docs/API_REQUESTS.md`: keep the open Train/chart items (strain band, strain target,
  baseline σ, resp/SpO₂ trends — still not in `API.md`); add the AASA request.
- `README.md`: Push Notifications capability, the `push.enabled` allow-list step, how to
  test the journal against compose before M5 is live.
- Preview captures (dark + light): Sleep Day with the need bar, Week with the bedtime
  strip, Planner, Journal sheet, Behaviors section, Notifications settings.

## Done when

- `git status` clean; every endpoint in `API.md`'s table has a caller and every field
  in the Swift mirror a decoder; fixtures regenerated and `make check-swift` green in
  `../plattform`.
- Flags come from `/v1/config` with TTL and offline fallback; push registers, silent
  pushes refresh, a real `MORNING_SCORE` was received on device.
- Sleep need breakdown, quality/restorative, bedtime strip, planner and baseline source
  are on screen; the journal and behavior impact work against compose (and production
  once M5 is deployed).
- Commits as named per section, plus `docs: platform wiring status`.
