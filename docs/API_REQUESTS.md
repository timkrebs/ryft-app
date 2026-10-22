# API requests from the app

What the iOS app needs that `../plattform/docs/API.md` does not (yet) provide.
The platform agent owns the contract; the app never invents fields silently.

## Activities and My Day (open, 2026-10-22)

For `CLAUDE_FOLLOWUP_MY_DAY_ACTIVITIES.md` (app) and `../plattform/CLAUDE_FOLLOWUP_ACTIVITIES.md` (platform). The app builds
against an in-memory fake until `API.md` → Activities is published, and mirrors it then in its own contract PR. These are
the questions and additions from the app's design note (`docs/work/2026-10-22-my-day-activities/design.md` §13). The
first one decides how the app reads My Day.

| # | Request |
| --- | --- |
| R1 | **My Day read.** Prefer extending `GET /v1/days/{day}` (additive): `activities: [Activity]` (no route, no `hr_samples`), `merged_with`, and the sleep fields in R11. Today's existing read and refresh paths then carry My Day with no new resource. If `GET /v1/my-day/{day}` is chosen instead, the app needs per item: `type`, `id`, `start`, `end`, `sport` or `activity`, `title`, `distance_m`, `strain`, `scoring_state`, `sources: [{name, bundle_id?}]`, `origin`, and `merged: [{type, id}]`. |
| R2 | `scoring_state` values for activities (`pending`, `scored`, …) and when `strain_source: none` is final. |
| R3 | After `PUT /v1/activities/{id}` or `/v1/sleep/manual/{day}`: the response carries `days_touched` and `scoring.expected_within_sec` (as `POST /v1/sync`), and the day is in `GET /v1/me/sync` `pending_days` until rescored. Is the silent push sent for it? |
| R4 | Route encoding: polyline precision (5 or 6), max points, whether `route` may carry altitude. |
| R5 | Route segments: `route` as an array of polylines (privacy-zone gaps), or a documented separator. |
| R6 | `GET /v1/activities/{id}`: `hr` and `zone_min` for the window (like `WorkoutDetail`) when the platform has heart rate, so the detail screen shows the curve for unmerged activities. |
| R7 | Laps (the lap button) aren't in the contract: local and Apple Health only for now. Add `laps?` if wanted. |
| R8 | `hr_source` as `{name, bundle_id}` (or a tracker id), so the app shows the catalogue's display name. |
| R9 | A downsampled `profile?` (t, distance, altitude) for charts on other devices. Otherwise charts come from splits there. |
| R10 | The sport families of the merge rule, published, so Apple Health's overlap rule (§5) matches. |
| R11 | `SleepDetail.origin` (`manual` / `tracker`) and its source (`name`, `bundle_id`), for "added by you" and the source badge. The manual sleep's day convention (wake day?), its validation, and tracker-wins behaviour in examples. |
| R12 | `PUT` semantics: the response body (the stored `Activity`?), `200` vs `201`, conflicts by `client_updated_at`? `DELETE` idempotent (`404` = gone)? |
| R13 | `hr_samples` size: 1 Hz for 2 h is about 7 200 entries, near the 256 KiB cap. Accept 5 s means (the app's plan), or a compact `{start, interval_sec, bpm: []}`. |
| R14 | Export: `GET /v1/activities?from&to&include=route` (or the export endpoint) so "Export my data" includes routes without one GET per activity. |
| R15 | How far back a manual activity may start, and `notes` ≤ 500 counted in characters or bytes. |
| — | Naming only: API.md `Activity` is `SportActivity` in the app (ActivityKit owns `Activity`). |

## Train (open, 2026-10-19)

The app now mirrors `API.md` → Train and its Swift block. Two divergences are
naming only: `Session` is `TrainSession` in the app, because Supabase's `Session`
is the auth session, and `Set` is `SessionSet` as in the mirror.

1. **Deleting a set while a session is in progress.** `PUT /v1/sessions/{id}`
   keeps the sets the body leaves out while `in_progress`, so a set deleted on the
   phone stays on the server until the session is completed. Completion then
   replaces the document whole, and its sets disappear. During the session it
   still counts in `/sessions` summaries, and in a 409 copy (the app drops it from
   its own merges).
   - **Proposal:** a tombstone, `"deleted": true` on the set, or
     `DELETE /v1/sessions/{id}/sets/{set_id}`.
2. **A paused enrolment in `GET /v1/plans`.** `active` is "the active enrolment,
   or `null`", so after `DELETE /v1/plans/enrollment` the app can't tell which plan
   was paused. It remembers the plan id locally to offer Resume, which re-enrols
   via `POST /v1/plans/{id}/enroll`. A second phone, or a reinstall, loses that.
   - **Proposal:** return the paused enrolment too, e.g. as `active` with
     `status: "paused"`, or a separate `paused: Enrollment?`.
3. **Workouts RYFT writes to Apple Health (opt-in, 2026-10-21).** With "Save strength
   workouts to Apple Health" on, the app writes one `HKWorkout` per completed session
   (`traditional_strength_training`, the session's start and end, brand "RYFT",
   `HKMetadataKeyExternalUUID` = the session id). Not when a strength workout from the
   watch or another app covers at least half of the session, and it deletes its own when
   one arrives later. The sync **skips** RYFT's own workouts (by source bundle), so the
   platform keeps attaching the load as `API.md` → sessions describes.
   - **Please confirm** that skipping is what you want. The alternative is to send them and
     have the platform link a workout to its session by `session_id` (the external UUID)
     instead of creating a `ryft-session` workout. Then a second phone would see it as the
     session's too.

## Charts and gauges (open, 2026-10-19)

The Today / chart redesign asked for fields `API.md` doesn't have. The app doesn't
invent them; these are the stand-ins until the platform serves them.

1. **Strain band on the score: `DailyScore.strain_band`.** A string (`light`,
   `moderate`, `high`, `all_out`) from the platform's own thresholds. Until then the app
   derives the band from `strain` at 10 / 14 / 18 (`MetricSpec.strainBand`).
2. **Strain target: `DailyScore.strain_target_lo` / `strain_target_hi`.** Numbers on
   the 0–21 scale: the range recommended for today given recovery. `MetricGauge` has
   the target arc built in, but it stays empty until these exist.
3. **Baseline spread: σ for HRV and resting HR.** For example `hrv_baseline_sd_ms` /
   `rhr_baseline_sd` on `DailyScore`, and `baseline_sd` on `GET /v1/trends` for `hrv`
   and `rhr`: the standard deviation over the same 30 days as the baseline. The
   personal-range bands would then be baseline ± σ. Until then they use the 30-day
   trend's `min` / `max` (Insights), and `RangeBar` shades the inter-quartile range of
   the 30-day points.
4. **Respiratory rate and SpO₂ trends.** `GET /v1/trends?metric=resp_rate|spo2`, so
   `RangeBar` can show them against a personal range like HRV and resting HR.
   `DailyScore` already has today's values.

## Sync and performance (open, 2026-10-21)

From `CLAUDE_FOLLOWUP_SYNC_PERFORMANCE.md` §5. The app side of each is built and waits
for the platform; nothing here is sent before the platform says it takes it.

1. **`Content-Encoding: gzip` on `POST /v1/sync`.** A page of 10 000 samples is ~2 MB of
   JSON that repeats `"type"`, `"unit"`, `"source"` in every record; gzip makes it about
   a tenth (measured in `SyncGzipTests`: more than 8×).
   - **Proposal:** ingest accepts `Content-Encoding: gzip` (and still plain JSON), applies
     the 32 MiB limit to the decompressed body, and answers `415` for an encoding it
     doesn't take.
   - **How the app learns it:** the flag `sync.gzip` in `GET /v1/config` (flags are open
     keys; the app's compiled default is off). The app gzips while it's on and falls back
     to plain JSON for the rest of a sync on a `400` or `415`.
2. **HealthKit UUIDs, so deletions can reach the platform.** Samples and sleep segments go
   up without the HealthKit UUID (workouts already use it as `id`), so a record deleted in
   Apple Health, or rewritten by a watch app, stays on the platform. The app now collects
   the anchored reads' `deletedObjects` per account (bounded) and keeps them for this.
   - **Proposal:** `Sample.id` and `SleepSegment.id` (uuid?, the HealthKit sample's UUID;
     records without one keep today's uniqueness), and on `SyncRequest`
     `deleted: [{"kind": "sample" | "sleep" | "workout", "id": uuid}]`. The platform
     removes what it has under those ids (unknown ids are fine, counted in
     `ignored.*.unknown_id`) and queues the days for rescoring.
3. **Pre-aggregated high-volume samples.** An Apple Watch writes steps and active energy
   in tiny samples (tens of thousands a day). Scoring takes steps from one source per hour
   and sums energy per day (`SCORING.md`), so per-source hourly sums carry the same
   information at a fraction of the size.
   - **Proposal:** `Sample.agg` (`"sum"`) and `Sample.bucket` (`"PT1H"`), with `start` /
     `end` the hour, `value` the hour's sum for that `source`. The app re-reads the last
     48 hours on each sync (`HKStatisticsCollectionQuery`, `.separateBySource`), so a
     bucket's value grows: the platform keeps the latest value per `(type, start, source)`.
   - **Question for scoring:** are 1-minute heart-rate averages outside workouts good
     enough for TRIMP? If yes, the same shape with `agg: "avg"`, `bucket: "PT1M"`.
     Please decide and document it in `SCORING.md`; until then the app sends raw samples.
4. **The in-between states on Today** (import card, pending gauge, watch-sync hint) need
   nothing new: `GET /v1/me/sync` (`today.state`, `pending_days`, `expected_within_sec`,
   `latest`) and HealthKit's own counts are enough. If a reinstalled phone should show
   what the platform already holds per category, `SyncStatus.counts` (records per
   `SourceKind`) would do; not requested yet.

## Universal links: the AASA (open, 2026-10-20)

1. **`applinks` for the app's paths.** `https://ryftapp.de/.well-known/apple-app-site-association`
   lists `applinks` only for `/auth/*` (OPERATIONS.md → Apex site). The app parses
   these paths with one `AppRoute` parser, for links, push `ryft.url`s and insights:
   - `/day/*`
   - `/sleep/*` (also `/sleep/plan`)
   - `/insights/*` (also `/insights/behaviors`)
   - `/train/sessions/*` and `/train/session/*` (the push table's form)
   - `/train/exercises/*`
   - `/train/plan/*`
   - `/train/history`
   - `/invite/*` (`ryft://invite/<code>` fills in the invite step; added 2026-10-21)

   **App ID:** `M77SKHKG63.dev.timkrebs.ryft` (team `M77SKHKG63`, bundle
   `dev.timkrebs.ryft`).

   **Proposal:** one `applinks.details` entry with that `appID` and the components
   above next to `/auth/*`, served as `application/json` with no redirect.
   Optionally, a small "Open in RYFT" page at each path for phones without the app.

   **Until then:** the app has no `associated-domains` entitlement at all; an empty array made iOS refuse to launch it.
   `https://` links open in Safari. `ryft://…` links and notification taps (the app
   reads `ryft.url` itself) work today. Once the AASA is live, the app adds
   `applinks:ryftapp.de` in Xcode (Signing & Capabilities); no code change is needed.

## Bedtime & wake (open, 2026-10-21)

The app plans tonight with `GET /v1/sleep/plan?wake=HH:MM` and keeps the rest on the phone,
behind `sleep.planner`.

1. **The sleep schedule on the account.** Per weekday wake times (Monday first, `HH:MM`),
   the goal (`100`, `85` or `70`, i.e. which of `bedtime_100/85/70`), the wind-down
   (15, 30, 45 or 60 min) and whether the reminder and the alarm are on. Today it lives in
   `UserDefaults` per account, so a second phone or a reinstall starts without it.
   - **Proposal:** `User.sleep_schedule: SleepSchedule?` and `PATCH /v1/me`
     (`sleep_schedule`), e.g.
     `{ "wake": ["06:30","06:30","06:30","06:30","06:30","08:00","08:00"], "goal": 85, "wind_down_min": 30, "reminder": true, "alarm": false }`.
2. **Planned vs actual.** The morning shows "Planned 22:41–06:30 · actual 23:12–06:28". The
   app keeps the planned bedtime per night (the last 14) on the phone, frozen once that
   bedtime passes (after midnight `strain_topup` starts again from zero).
   - **Proposal:** the platform keeps what it planned per night, e.g. `SleepDetail.planned:
     { bed, wake, goal }?`, filled from the last plan asked for before the planned bedtime
     (or from the schedule in 1).
3. **A server-sent `BEDTIME` push.** The reminder is local: it moves when the app plans
   again (after syncs that touch today and in the evening refresh), and later nights use
   tonight's time in bed. A strain that arrives while the app sleeps doesn't move it.
   - **Proposal (optional):** with 1 in place, a `BEDTIME` category in the push table, sent
     `wind_down_min` before the planned bedtime when it moved by 10 minutes or more. The
     app would then drop its local reminder for that night.
4. **Which night `wake` means.** `wake=HH:MM` resolves to the next time it occurs. On a
   morning when tomorrow's wake time is later than now (Friday 07:30 with Saturday at
   08:00) the app needs tomorrow's 08:00 but gets today's. It moves the bedtimes by that
   day, which holds because the need is tonight's either way and the bedtimes are
   `wake − share · in_bed_min`. When `users.tz` isn't the phone's time zone (travel), the
   answer is for another time zone and the app shows no plan.
   - **Proposal:** `GET /v1/sleep/plan?wake=HH:MM&day=YYYY-MM-DD` (the wake's day), and
     optionally `tz=` (IANA) to plan in the phone's time zone.

## Refresh resilience (open, 2026-10-21)

From TestFlight feedback on 1.0.0 (`20261021.141128`). The account has about 90 days of history. Today showed
"Baselines · 0 of 7 nights" beside a scored day (recovery 75, readiness 80, strain 0.9). The app now decides
Today from its own history (`TodayPresentation`, `docs/work/2026-10-21-refresh-resilience/design.md` §7), but the
platform's row is the root of it (`STATUS.md` → Incidents).

1. **`calibrating: true, baseline_days: 0` on a scored day for an account with history.** Reporter: user
   `<short id>` (to fill in from `scripts/user.sh`). Today, 2026-10-21: `calibrating: true`, `baseline_days: 0`,
   `recovery: 75`, `readiness: 80`, with ~90 days of history. `compute.go` takes
   `baseline_days = min(N_lnHRV, N_rhr)` over the 30 scored days before, and migration 0006 defaulted the column to
   0 "until rescored". Either today was scored before the days before it (backfill order, or the account
   merge/rescore), or the account has no HRV/RHR nights at all.
   - **Ask:** check the reporter's rows (`calibrating`, `baseline_days`, `computed_at`, `hrv_ms`, `rhr`,
     `hrv_baseline_ms`, `rhr_baseline` from 2026-07-24 to 2026-10-21). If the earlier rows have their baselines, rescore
     oldest-first after a merge or backfill, so no day is scored before the 30 days it depends on. Rescore every row
     still at the 0006 default.
2. **Why a day is calibrating.** Today the app can't tell "history is short" from "no HRV or resting HR at
   night" (phone-only, or a watch that doesn't write HRV to Apple Health). The second never ends by waiting.
   - **Proposal:** `DailyScore.calibrating_reason: "short_history" | "no_hrv" | "no_rhr" | null`, and optionally
     `baseline_hrv_days` / `baseline_rhr_days` (the two N's whose minimum is `baseline_days`). Until then the app
     infers it from the history it has (nights with `hrv_ms` and `rhr`).
3. **"This app is too old."** There's no signal for it, so the app can't tell a user to update.
   - **Proposal:** `426` with `code: "app_update_required"` on any `/v1/*` route for builds below a minimum, and/or
     `GET /v1/config` → `min_build` (the build number as a string, compared numerically). The app has the card
     ready and reserved (`FailureKind.appTooOld`).
4. **An idempotency key for `POST /v1/feedback`.** The app queues a report offline and resends it after a timeout or a
   lost connection. If the platform had already stored it, the user's report arrives twice and uses up 2 of the 10 a day.
   - **Proposal:** accept an optional `Idempotency-Key` header (or `client_id` in the body; the app sends the queued
     report's UUID) and answer `204` without storing again when it has seen the key in the last 24 h.

## Resolved by API.md (2026-10-19)

- `PlanSummary` and `SessionSummary` are their own shapes. They are mirrored.
- Pausing is `DELETE /v1/plans/enrollment`. Resuming is enrolling in the same
  plan again (`200`, it continues where it stopped). There is no PATCH and no
  "leave".
- A `409` on `PUT /v1/sessions/{id}` carries the server's `Session`.
- `…/complete` returns the `Session` with `prs`, and takes `ended_at`. The app
  sends it when replaying from the offline queue.
- `status: completed` on `PUT` only for an already completed session. The app now
  PUTs a session finished offline as `in_progress` until `…/complete` succeeds.
- `ExerciseHistory.sessions[].date` is a day (`YYYY-MM-DD`), with `started_at`
  alongside.
- `Workout.session_id` and `Workout.muscular_load`.
- **"load" on the Today card:** `Session.strain` is "the muscular load alone on
  the strain scale". The card shows that ("Done · load 10.6"). The summary shows
  `muscular_trimp` as *Muscular load* and `strain` as *Strain*.
