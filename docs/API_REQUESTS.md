# API requests from the app

What the iOS app needs that `../plattform/docs/API.md` does not (yet) provide.
The platform agent owns the contract; the app never invents fields silently.

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
