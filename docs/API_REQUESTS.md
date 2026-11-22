# API requests from the app

What the iOS app needs that `../plattform/docs/API.md` does not (yet) provide.
The platform agent owns the contract; the app never invents fields silently.

## Notifications (open, 2026-11-22)

From the notifications plan (`docs/work/2026-11-22-notifications/plan.md`, decision 3; ticket N2). Today only a Train
session sends a workout alert (`SESSION_SCORED`); a workout the watch recorded, or detected by itself, syncs, is scored
and tells the user nothing. The app builds its side behind the category and ships its local kinds first, so nothing
here blocks a release. Written against API.md as of the 2026-11-20 changelog entry.

1. **NT1: a new push category `ACTIVITY_SCORED` (P2).**
   - **Why.** The brief: RYFT tells the user when a workout was detected and processed, so they can review it, name it or
     correct its type, never during the workout. The platform is the one that knows when the workout has been synced,
     de-duplicated and scored (`Workout.strain` filled); the phone can't know the last two, and it computes no scores.
   - **Screens affected.** Profile → Notifications (one switch under "Training"), the notification's tap (opens the
     activity page), and the lock screen. Nothing else.
   - **Where it fits.** One more row in the push-notifications category table, one more `NotificationPrefs` key.
     Everything below is the platform's to adjust; where a rule is a guess, it says so.

   **When it is sent.** A workout row (`source` not `ryft-session`, no `session_id`) that has just been scored:
   - **After scoring.** Once scoring has run for its day and the workout has a `strain` (also `0.x`), so the body can name
     it. A workout that scoring leaves unscored sends nothing, never "strain n/a".
   - **Hiding and folding are decided first.** Hiding a cross-source duplicate happens when the day is scored (API.md →
     Duplicate workouts), so the alert waits for it and goes for the **primary** only. A hidden duplicate sends nothing.
   - **Never while it is going.** Only when `end` is not after the server's now (`outside_window` allows a start up to
     24 h ahead; a workout with a future `end` waits for it and is dropped if the window below passed). HealthKit writes
     a workout when it is saved, so in practice the alert follows the end by the sync and scoring delay.
   - **Not Train's own sessions.** A workout with a `session_id` (a Train session attached to it) or `source`
     `ryft-session` is covered by `SESSION_SCORED` / `PR`, so it sends no `ACTIVITY_SCORED`. The attach is decided at
     scoring, which is why this check comes after it.
   - **Not an import, not a manual or recorded activity.** The user already knows these, and `POST /v1/train/import`
     already sends no alert. Only a workout that arrived through `POST /v1/sync` (HealthKit, any source: a watch, a
     Garmin workout written to Apple Health) is eligible. (Once API.md publishes `PUT /v1/activities/{id}`: an
     activity with `origin` `manual` or `ryft` is never eligible.)
   - **How many.** Every eligible workout, at most **3 per local day** and account; the fourth and later are dropped,
     not held. At most one alert per workout ever: a re-score, a changed `strain` or a new `model_version` never sends a
     second. A same-source copy that replaces an older one (the 120 s fold, a Garmin rewrite under a new UUID) inherits
     the older copy's "alerted" mark, so the rewrite doesn't alert again. Likewise the primary of a duplicate group that
     has been alerted for one of its members.
   - **Minimum.** Duration of at least 10 minutes (a guess; a watch's detection also catches short walks).
   - **Quiet hours.** `NotificationPrefs.quiet_hours` is respected as for `SESSION_SCORED`: **dropped**, not held.
     A workout alert is stale after a night (the expiry below), and the workout is in the app when the user looks.
   - **Within 12 h of its end**, as `SESSION_SCORED`: scoring later than that sends nothing.
   - **Silent for backfilled history.** The 12 h window already keeps old workouts quiet. In addition, nothing for the
     workouts of a device's first sync: the pages uploaded while that `device_id` is new, until scoring has finished
     the days they touched (the cut is the platform's; "the device row is under 1 h old" is the app's guess). A phone
     that was offline for days uploads workouts older than the window and they stay quiet; one that was offline for
     hours uploads a workout still within the window, and it **does** alert once scored: it is recent news.
   - **Push preference.** `categories.ACTIVITY_SCORED`, **default on** (like `SESSION_SCORED`). The same silent
     `refresh` push after every sync is unchanged and also covers the new workout.

   **Category table row, in the form of the existing one:**

   | Category | Sent when | Title · body keys (arguments) | Opens (`ryft.url`) |
   | --- | --- | --- | --- |
   | `ACTIVITY_SCORED` | A workout synced from Apple Health (a watch, or a Health-connected tracker) has its strain (scoring has run, duplicates decided), within 12 h of its end and at least 10 min long. Not a Train session, import or manual activity; not backfilled history; at most 3 a day, one per workout; not during quiet hours (dropped). | `ACTIVITY_SCORED_TITLE` (sport name) or `ACTIVITY_SCORED_TITLE_UNTITLED` (`activity` is `other` or unknown) · `ACTIVITY_SCORED_BODY` (strain, duration) | `https://ryftlab.de/activity/<workout id>` |

   **Keys** (same form as API.md's key table; the app ships `en` only, RYFT has no German localisation, so the `de` column
   stays the platform's for its own `locale` handling and the app's catalog takes `en`):

   | Key | en | de |
   | --- | --- | --- |
   | `ACTIVITY_SCORED_TITLE` | %@ scored | %@ ausgewertet |
   | `ACTIVITY_SCORED_TITLE_UNTITLED` | Activity scored | Aktivität ausgewertet |
   | `ACTIVITY_SCORED_BODY` | Strain %1$@ · %2$@ | Belastung %1$@ · %2$@ |

   - **Arguments** (formatted for the registered `locale`, like the other categories): title `%@` the sport's name
     from `Workout.activity` (`running` → "Run" / "Lauf"); `ACTIVITY_SCORED_TITLE_UNTITLED` when it is `other` or a
     value the platform has no name for. The user's own title can't be there: it is set after the alert. Body `%1$@`
     the workout's `strain` to one decimal (`12.8` / `12,8`), `%2$@` its duration (`56 min`, `1 h 12 min` /
     `56 Min.`, `1 Std. 12 Min.`), with a no-break space (U+00A0) between each number and its unit, as the app's catalog does. "Activity scored", not "Workout scored", when there is no sport name: the latter is `SESSION_SCORED`'s, and the two would look the same on the lock screen.
   - **Lock screen.** The title carries no health value (a sport name only); the strain is in the body, which iOS
     hides with previews off. The same rule as `SESSION_SCORED`.
   - **The "detected by your watch" variant** is NT2, optional.

   **Payload**, as the existing example:

   ```json
   { "aps": { "alert": { "title-loc-key": "ACTIVITY_SCORED_TITLE", "title-loc-args": ["Run"],
                         "loc-key": "ACTIVITY_SCORED_BODY", "loc-args": ["12.8", "56 min"] },
              "sound": "default", "category": "ACTIVITY_SCORED", "thread-id": "ACTIVITY_SCORED",
              "mutable-content": 1 },
     "ryft": { "category": "ACTIVITY_SCORED", "day": "2026-10-20",
               "url": "https://ryftlab.de/activity/7d1b6c3e-2c1a-4b8e-9d3a-5a0e4f6b8c12",
               "account": "<User.id>" } }
   ```

   - **`ryft.url` path.** `/activity/<id>`, `<id>` the `Workout.id` of the primary (the HealthKit workout UUID,
     lower case), the id `GET /v1/workouts/{id}` takes. The app's `AppRoute` has no such path yet (it knows
     `/day/`, `/sleep/`, `/train/…`); it adds `/activity/<uuid>` in its own PR, so the platform needs nothing from the
     app first. An id the platform later hid or folded still opens (a hidden duplicate answers `200`; a folded same-source copy
     answers `404`, and the app then shows that workout's day).
   - **`ryft.day`** the local day the workout starts on, as `MORNING_SCORE`'s (the app refreshes that day when it opens).
   - **`ryft.account`** the `User.id`, as "Sync and performance" §5 asks for the `refresh` push. Here it matters more:
     the alert opens a page with health data, and a late alert for account A must not open on account B's phone (a
     shared iPhone). The app drops an alert whose `account` isn't the signed-in one and treats a missing one as
     today. Please add it to every alert, not only this category.
   - **Collapse and expiry.** `apns-collapse-id` `ACTIVITY_SCORED-<workout id>` (52 bytes, under APNs' 64) so a repeat
     for the same workout replaces an undelivered one; `apns-expiration` at the workout's end plus 12 h; priority 10.
   - **`NotificationPrefs.categories`** gains `ACTIVITY_SCORED` (`GET /v1/me`, `PATCH /v1/me/notifications` accept it,
     `422` for it today). The app shows the switch only when the key is in `GET /v1/me`'s `categories`, and
     never sends it before then, so the platform can ship it whenever it is ready. A phone that doesn't know the key
     keeps working: `NotificationPrefs.isOn` treats a missing category as on.
   - **What the app does.** Registers the `ACTIVITY_SCORED` `UNNotificationCategory`, routes the tap to the activity page
     (`AppRoute.activity(UUID)`), and adds the switch in Profile → Notifications → Training. The Activities draft
     (R1–R26 above, not in API.md yet) is where naming and changing the type of an Apple Health workout is written;
     the page is useful for review without it (the workout, strain, heart rate), and gains naming when those endpoints land.

2. **NT2 (optional): tell a watch-detected workout from a started one.**
   - **The question.** "Detected by your watch. Strain 12.8. Tap to review." is better copy for a workout the user did
     not start, but the platform can't tell it today. `Workout` carries `activity`, `start`, `end`, `avg_hr`,
     `max_hr`, `energy_kcal`, `distance_m`, `source`, `source_bundle_id`, nothing about how it began; the app's mapper
     reads no `HKWorkout.metadata` at all and has no field for it. The platform therefore can't, from what it has.
   - **What the app can send.** Apple documents `HKMetadataKeyWasUserEntered` (a workout typed in by hand) and
     `HKMetadataKeyIndoorWorkout`, nothing that marks a watch-detected session. The app will inspect
     real watch workouts on a device before promising a signal (the workout reminder starts the same workout type the
     user confirms, so there may be none). **Don't build this until the app reports a key that works.**
   - **Proposal if it does:** `Workout.detected` (bool?, optional, omitted when unknown) on `POST /v1/sync`, stored
     and returned on `Workout`; `ACTIVITY_SCORED_BODY_DETECTED` ("Detected by your watch. Strain %@. Tap to review." /
     "Von deiner Uhr erkannt. Belastung %@. Zum Prüfen öffnen.") used when `detected` is `true`. Ingest rejects unknown
     fields (`400`), so the field must be accepted before the app sends it; the app then sends it only
     behind a flag in `GET /v1/config` (like `sync.deletions`).
   - **Until then:** every alert uses `ACTIVITY_SCORED_BODY`; the page it opens is the review.

3. **NT3 (question): an activity the user recorded in RYFT.** NT1 sends nothing for one (the Activities draft, R1–R26
   above; `origin` is not HealthKit), because the user just ended it. Please confirm that, and that a workout the app
   writes to Apple Health for such a recording (if it ever does) doesn't alert a second time as an Apple Health
   workout: the same workout would arrive under the other `id` and `source`.
4. **NT4 (question): workout alerts during quiet hours.**
   - **What API.md says:** `SESSION_SCORED` and `PR` are sent "not during quiet hours". It doesn't say whether an alert is dropped or held until the window ends, while `MORNING_SCORE` explicitly holds.
   - **The app's reading:** dropped, the same as NT1. The Notifications page now says "Workout alerts are skipped".
   - **Request:** please confirm, or tell us they are held. The page's sentence would change.
5. **NT5 (flag): `notifications.reminders` (P1, operator).**
   - **What it gates:** the app's two new local reminders, the morning journal reminder and the "not syncing" fallback on the phone. Bedtime & wake's reminder is not gated.
   - **Default:** off. `GET /v1/config` → `flags` has open keys, and the app's compiled default is off, so nothing changes until the flag exists and is on for an account.
   - **Request:** create the flag at 0 % with an allow-list, like `train.import` and `analytics.enabled`. The operator raises it once the Notifications page with its switches (N4) has shipped.
   - **Turning it off later** removes the reminders already scheduled on each phone at its next config read.
6. **NT6 (later, optional): the journal reminder's setting on the account.**
   - **Today:** the switch and the time live on the phone, per account. They survive a session expiry, and a sign-out clears them.
   - **Later:** if users ask for the setting to follow them across devices, `NotificationPrefs` could gain `journal_reminder: {on: bool, minute: int}`.
   - **Status:** nothing is needed now. This is filed so the shape is agreed before anyone builds it.

## App Attest (answered, 2026-11-20)

From the App Attest client (`docs/work/2026-11-19-app-attest/design.md`, "Contract gaps"; ADR 0023), against API.md's
App Attest section (D245). All four answered by D247 (platform PR #227, 2026-11-20); the app side is
`docs/work/2026-11-20-app-attest-mode/`.

1. **AA1: tell this build from old builds in the `warn` lines.** Answered: API.md → Conventions → App build. The app
   sends `X-RYFT-App-Build: <CFBundleVersion>` on every request to both hosts; the server takes
   `^[0-9]+(\.[0-9]+){0,3}$`, at most 24 characters, ignores anything else and writes it only into its warn line. The app
   never sends a value that fails the pattern.
2. **AA2: a mode or "served" signal.** Answered: `GET /v1/config` → `app_attest` (`"off"`, `"warn"`, `"on"`, always
   present; absent on a server before D247). Under `"off"` the app skips the probe; a `501` or a `404` without a `code`
   from `POST /v1/app-attest/challenge` stays authoritative in every mode; under `"on"` an app without a token learns it
   from `403 app_attest_required`.
3. **AA3: a floor for `ttl_sec`.** Answered: 3600 today, never below 600 (a server test pins it). The app's renewal at
   `min(300, ttl_sec / 2)` left stays.
4. **AA4: no echoed values in error bodies.** Answered: the three routes' `error` texts are fixed sentences; none holds
   the `challenge`, `key_id`, `assertion`, `attestation` or a token, and neither do the server's logs of these routes.

## Offline-first (open, 2026-11-19)

From the offline-first plan (`docs/work/2026-11-19-offline-first/plan.md`, §(d)). The owner's rule: everything shows
offline, and every write made offline is kept and sent once the API is reachable.

1. **P1: `sync.deletions` in `GET /v1/config`.** Already filed under "Sync and performance" §2. Please add the flag row
   and turn it on per environment after the ingest deploy (ADR 0011). The app's O11 sends deletions only behind it.
2. **P2: late writes keep their window.**
   - `PUT /v1/journal/{day}` answers `422` once the day is past `editable` (14 days). Manual activities may start at
     most 14 days back (R15).
   - An item saved offline in time can arrive after the window.
   - **Proposal:** accept an optional `saved_at` (RFC 3339, the phone's time of the edit) and check the window against
     it, bounded by `now` and a short grace (for example 3 days).
   - **Until then:** the app shows such an item as refused, with Retry and Discard. It never drops it silently.
3. **P3: consent on journal writes.** Please answer `PUT /v1/journal/{day}` and `PATCH /v1/behaviors` with
   `403 consent_required` without a current consent, as `POST /v1/sync` does (extends R25(1)). The app also gates them
   in its outbox.
4. **P4 (optional): one report per resend.** `POST /v1/feedback` takes an optional client `id` (uuid), and a repeat
   answers `204`, so a resend after a lost answer files one report.

## Nocturne restyle (open, 2026-11-17)

From Nocturne PR 4 (`docs/work/2026-11-16-nocturne/design.md` §P4-4, rows R-N1 and R-N2). The screens ship without
these; each has a fallback that invents nothing.

1. **R-N1: a personal strain target.** The board marks "target 10–14" on Today's compact strain ruler, on Strain's
   ruler and on the gauge's band rail. `DailyScore` has no target, so the app shades the fixed moderate band from
   `MetricSpec` (10–14) and labels it with the band word ("moderate"), never "target".
   - **Proposal:** `DailyScore.strain_target_min` and `strain_target_max` (number?, the day's recommended strain range;
     `null` until the baselines exist).
   - **Until then:** the fixed moderate band, labelled as a band. Nothing waits on this.
2. **R-N2: an editable display name.** Today greets with the first word of `User.name` ("Good evening, Alex"). For a
   Sign in with Apple account the platform stores `""` when Apple sent no name, and `PATCH /v1/me` can't set one.
   - **Proposal:** `PATCH /v1/me` accepts `name` (string, trimmed, 1–40 characters, `422` otherwise). Profile (Nocturne
     PR 5) would offer to edit it.
   - **Until then:** "Good evening" without a name or comma.

Not filed: a platform "slept enough" flag (R-N3). The app counts a night as enough when the time asleep is at least
90 % of the need (plan decision L24); the rule can move to the platform later if both sides should agree on it.

## Training import (closed, 2026-10-27)

All thirteen questions (T1–T13) from the app's design (`docs/work/2026-10-23-train-csv-import/design.md` §13) are
answered in the platform's API.md → "Training import: answers to T1–T13" (anchor `training-import-answers`; on branch
`feat/train-import-api` until the platform PR merges). Nothing is open. Where the answer differs from what the app asked for, it is noted.

| # | Question | Answer (API.md anchor) |
| --- | --- | --- |
| T1 | Origin belongs to the endpoint | Yes; `origin`/`import_source` in the request is `400`, the app encodes them absent (`#t1`) |
| T2 | No `skipped` flag | Yes; a sent set was done, `completed_at: null` is `invalid` in an import (`#t2`) |
| T3 | Bodyweight convention, `null` = `0` | Confirmed; stored as sent, compared as equal (`#t3`) |
| T4 | Assisted sets | `assist_kg` 0–200 on `Set` instead of a negative load (`#t4`); the app's import of it is a follow-up |
| T5 | Plan references in a batch | Validated, but a `rejected` item `unknown_plan_reference` rather than `422`; resend the session without references (`#t5`) |
| T6 | No enrolment move, no push | Confirmed (`#t6`) |
| T7 | Rescore answer | `days_touched` + `scoring` as in `SyncResponse` (`#t7`) |
| T8 | Enrol where the user is | `EnrollPost` on `POST /v1/plans/{id}/enroll` (`#t8`); mirrored in C2 |
| T9 | Limits and the second import | In Conventions: 1 MiB, ≤ 5 plans, ≤ 50 sessions, `429 import_in_progress` + `Retry-After: 10` (`#t9`) |
| T10 | "Identical content" | Server fields excluded, everything else compared; `newer_on_server` protects edits (`#t10`) |
| T11 | Bodyweight plan target | Docs were wrong; `null` or added kg 0–500 (`#t11`) |
| T12 | Archived custom exercise | `POST /v1/exercises` un-archives it (`#t12`) |
| T13 | One result per item; `X-Request-ID` on `2xx` | Both hold: "One entry per submitted item" under the endpoint, and Conventions → Request IDs (`#t13`) |

Also confirmed in the platform's Conventions → UUIDs: every id in the import body is parsed as a UUID (upper case is
fine); `results[].id` comes back lower case, so the app matches by `UUID` value.

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
| R4 | Route encoding: polyline precision (5 or 6) and max points. The app sends latitude and longitude only (simplified ≥ 3 m), never altitude or timestamps. |
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
| R15 | How far back a manual activity may start (the app allows 14 days), and `notes` ≤ 500 counted in characters or bytes. |
| R16 | `route` and `hr_samples` appear **only** in `GET /v1/activities/{id}` (and R14's export), never in `GET /v1/activities?from&to`, the day detail, `GET /v1/my-day` or `PUT` answers. |
| R17 | A final `401` for an account deleted on the web carries a distinct `code` (e.g. `account_deleted`), so the app deletes parked activities at once instead of after 30 days (§8.4). |
| R18 | `GET /v1/activities?from&to`: the parameters as RFC 3339 instants with offset, matched `[from, to)` on `start`, so the app asks for one local day (the phone's midnight to midnight, as it does against the fake). If the platform prefers `YYYY-MM-DD` like `GET /v1/days`, say which time zone decides an activity's day (`GET /v1/me` → `tz`?). Either way, an activity across midnight belongs to the day it starts on. (A1, 2026-10-23) |
| R19 | **`PUT /v1/activities/{id}`: missing vs `null`.** A field the body leaves out keeps what the platform stores; an explicit `null` clears it. The app relies on both: it leaves out `route` and `hr_samples` when it has none to send (an edit of effort or notes after the route went up, or a route the user withheld), and it sends `null` for an editable field the user cleared (`notes`, `perceived_effort`, `distance_m`, `ascent_m`, `descent_m`). Please document it under the endpoint with an example of each, and say how the app removes a route it already sent (Remove route, design §8.6): `"route": null`, or a dedicated call. (A1 review, 2026-10-23) |
| R20 | **Splits: the index base and what a split covers.** The app numbers splits from 1 (the first kilometre is `index: 1`); please state the platform's convention with an example. Please confirm: `distance_m` is 1000 except for the last split, which may be partial with its real distance; a remainder under 50 m isn't sent as a split, so the splits can sum to up to 50 m less than the activity's `distance_m` (and `duration_sec` to less than `moving_sec`); `duration_sec` is moving time within the split, pauses excluded; `ascent_m` is null without elevation. (A3a, 2026-10-23) |
| R21 | **New `sport` and `origin` values, and manual sleep's `DELETE`.** (A2, 2026-10-26) (1) Please say whether `sport` and `origin` may gain values later. The app keeps an unknown `sport` exactly as received and sends it back on an edit, unless the user picks a sport; it shows an activity with an unknown `origin` read-only (no edit, no delete). If the platform ever needs older apps not to edit a new kind, a new `origin` value is the way. (2) `DELETE /v1/sleep/manual/{day}`: please confirm `404` means "nothing stored for that day" (the app then treats the night as deleted), as R12 asks for activities. (3) After a confirmed `PUT` or `DELETE` of either, the app waits for scoring of the day (and of the day an edit moved an activity from) through `GET /v1/me/sync` → `pending_days`, as R3 asks. Until the platform lists those days there, the wait ends at the first status answer that doesn't (after `expected_within_sec`, 30 s by default), so the refresh can still show the day's old strain. |
| R22 | **Writes during an account deletion.** (A2, 2026-10-26) While `DELETE /v1/me` is in progress for an account, please refuse `PUT`/`DELETE` on `/v1/activities/{id}` and `/v1/sleep/manual/{day}` for it (e.g. `409` or the deletion's own code). The app stops its uploader before it calls `DELETE /v1/me`, but a request already on the wire can still land after the data was deleted. |
| R23 | **Consent on activity and manual-sleep writes.** (A2, 2026-10-26) Please confirm that `PUT` and `DELETE` on `/v1/activities/{id}` and `/v1/sleep/manual/{day}` answer `403 consent_required` when the account's consent is to an older `privacy_policy_version`, as `POST /v1/sync` does (API.md, sync). The app holds these uploads until it knows the policy in force, but a cached version can be one bump behind, and then the platform's refusal is what keeps the item out. For `DELETE`, R25 (2) replaces this request: the app now sends deletes without a current consent. |
| R24 | **Announce a privacy-policy bump before it applies.** (P2, 2026-10-26; not blocking) **Why.** A new `privacy_policy_version` applies to `POST /v1/sync` at once. A phone that read `/v1/config` up to `ttl_sec` earlier still sends one page under the old consent before `403 consent_required` stops it. **(1) Announce the next version.** Please consider `privacy_policy_next_version` and `privacy_policy_effective_at` in `GET /v1/config` (null when nothing is scheduled), published at least `ttl_sec` ahead. The app would ask for consent ahead and hold uploads from `effective_at`. **(2) Tell the other phones about a withdrawal.** When an account's consent is withdrawn, please send the silent refresh push with the gate (e.g. `"gate": "consent_required"`), so the account's other phones hold without sending a page. |
| R25 | **Consent on Train writes; deletes without consent; training data received without it.** (P2, 2026-10-26) **Why.** The app treats training logs as health data (Art. 9): body weight, effort, notes, and their use in strain and recovery scoring. It holds `PUT /v1/sessions/{id}`, `POST /v1/sessions/{id}/complete` and `POST /v1/train/import` until the account has consented to the policy in force. **(1) Refuse writes without consent.** Please answer these with `403 consent_required` for a missing or outdated consent, as `POST /v1/sync` does. **(2) Accept deletes without consent.** The app sends DELETEs without a current consent (erasure, Art. 17); please accept them: `DELETE` on `/v1/sessions/{id}`, `/v1/activities/{id}` and `/v1/sleep/manual/{day}`, regardless of consent. Today the app records a `consent_required` answer to a `DELETE` as a refusal and keeps the delete queued. **(3) Check the data already received.** Please check whether training data was stored for accounts without a consent at the time, and say what happens to it. **(4) The import refuses as a whole.** For `POST /v1/train/import` (draft, C2), a missing or outdated consent is the whole request's `403 consent_required`, never a per-item `rejected` in `results`: the app holds a `403` and sends the job again once consent is there, but it lists a `rejected` item as not imported and sends it only on the user's Retry (I5 review, 2026-10-26). |
| R26 | **A refused body is never stored, and consent is checked before the body is read.** (P2, 2026-10-26) For every write that can answer `403 consent_required` or `invite_required` (`POST /v1/sync`, activities, manual sleep, Train, the import), please confirm two things: the gate is decided from the token before the body is read, decompressed or parsed; and a refused body is neither stored, queued nor logged. Then a refused page leaves no trace beyond the access-log line. |
| — | Naming only: API.md `Activity` is `SportActivity` in the app (ActivityKit owns `Activity`), and `strain_source: "none"` is `StrainSource.noSource` (a case called `none` would read as `Optional.none`). |

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
   - **Same for exercises (2026-10-29).** The same merge keeps an *exercise* the body
     leaves out, and its sets with it. A user who removes an exercise, or replaces one
     before doing a set (ticket T1), leaves a server row that still counts at finish
     (a sets-less row also makes that exercise's next "Last time" empty). That
     contradicts Train #1 / `API.md`, which say completion replaces the document whole.
     The app can't observe this either; it rests on reading `train.Merge` (called at
     `backend/internal/store/train.go:498`).
   - **Proposal (extended):** exercise tombstones next to the set ones
     (`"deleted": true` on the exercise, or `DELETE /v1/sessions/{id}/exercises/{exercise_id}`),
     and on completion the documented behaviour: the body is the whole document, so
     rows it leaves out are dropped.
2. **A paused enrolment in `GET /v1/plans`.** `active` is "the active enrolment,
   or `null`", so after `DELETE /v1/plans/enrollment` the app can't tell which plan
   was paused. It remembers the plan id locally to offer Resume, which re-enrols
   via `POST /v1/plans/{id}/enroll`. A second phone, or a reinstall, loses that.
   - **Proposal:** return the paused enrolment too, e.g. as `active` with
     `status: "paused"`, or a separate `paused: Enrollment?`.
   - **Nocturne PR 6 B (2026-11-19):** `GET /v1/plans` should return the paused enrolment with `paused_at`, its week and
     its next day, so Plans' paused tile can say "since Nov 3" and "Next: Upper A · week 6"; until then it says only
     "Resume continues where you stopped."
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
4. **`last_time` per occurrence when a day holds an exercise more than once.** (P2, 2026-10-29;
   beta feedback round 2 §4, T4) **Why.** `PlanTarget.last_time` is built per `exercise_id`
   (`LastWorkingSets`, called once per plan exercise in `GET /v1/plans/today`): every completed
   working set of that exercise in the newest completed session, ordered by the session exercise's
   position, then `set_index`. If a day has the same exercise on two rows (synthetic example: "Face
   pull" twice, 3 sets each), and the last session logged it twice, both rows get the same 6 sets.
   The card then shows the joint list (cut at five) and the ghost values of the second row come
   from the first row's sets. Same-exercise rows are legal in the plan builder and arise from
   imports too.
   - **What.** No new field, only the content of `last_time`. For plan exercises that share an
     `exercise_id` in the day, the k-th plan row (by `position`) gets the working sets of the k-th
     `session_exercise` of that exercise in the last session (by position). If the last session's
     `session_exercise` carries the same `plan_exercise_id` as the row, prefer that one. If the
     session has fewer occurrences than the day has rows, the rows past the last occurrence get
     the last occurrence (or `[]`, your choice; please say which in API.md). A day with the
     exercise once is unchanged. Please also document the order of `last_time` in API.md (today
     `ORDER BY position, set_index` in `LastWorkingSets`, an implementation detail the app relies on).
   - **Screens.** Train: the session card's "Last time" line and its ghost values (from a plan
     day); the plan day preview.
   - **App stop-gap (branch `fix/train-last-time-occurrence`).** The app splits the concatenated
     list where `set_index` stops increasing, and gives the k-th row of the exercise the k-th run,
     only when the number of runs equals the number of rows; otherwise it keeps the joint list.
     Limit: it is a heuristic. `last_time` keeps only completed working sets, so an occurrence that
     starts with an unchecked or warm-up set after a short occurrence continues the previous run
     (the two merge, and the app falls back to the joint list); an occurrence with no working sets
     disappears; a duplicate `set_index` after a merge splits a run; and it cannot use
     `plan_exercise_id`. It is a no-op once you ship this: each row then gets one run.
   - **Old clients.** Unchanged: they read `last_time` as before, and for a day with the exercise
     once the content is identical.
5. **Question, not a request: can an import move an untouched session row to another
   `exercise_id`?** (2026-10-29) A future "re-map imported exercises" repair would need an
   imported session's exercise rows to point to another exercise (a wrong match on import, e.g.
   two source rows on one RYFT exercise). A resend of the same file today yields ids derived per
   account and key, so we expect `unchanged` or, if the app touched the session, `newer_on_server`.
   - **Question.** If a `POST /v1/train/import` item has the same session id but a changed
     `exercise_id` on one or more rows, and the session is untouched since the import (no
     `PUT`/edit by the app), does the server return `updated` and move the rows? Or is
     `unchanged`/`newer_on_server` the answer regardless? If it is not possible, is there a
     better way you would offer (a re-map endpoint, or deleting the imported sessions and
     importing them again)?
   - **Why we ask now.** To decide whether the repair is worth a design. Nothing in the app
     depends on it yet.

6. **Progression fallback counts an unlinked exercise twice (needed, P2, 2026-10-29).**
   `PlanExerciseAttempts` counts a session exercise with `plan_exercise_id: null` as an
   attempt for every plan exercise of the session's plan day with the same
   `exercise_id` (`backend/internal/store/train.go:848`). When a user replaces planned
   exercise A by B mid-session and B is also planned that day, the app sends one B row
   linked to B's plan exercise and one B row with `plan_exercise_id: null` on the same
   `plan_day_id`. Both count for B, so `NextTargetKG`
   (`backend/internal/scoring/strength.go:476`) sees two attempts from one session and
   can step up, or deload, twice. Which one of the two it counts first is arbitrary.
   The app can't observe progression itself; this request rests on reading the platform
   code at the lines above.
   - **Proposal:** the fallback applies only when no exercise of the same session names
     that plan exercise. Sessions without links (older apps, unmapped imports) keep
     today's behaviour.
   - **Screens affected:** Train > Today and the plan's next targets, after a replaced
     exercise.
7. **A movement pattern on `Exercise` (nice to have, 2026-10-29).** For "Similar" in the
   replace sheet. Muscles alone can't tell a press from a fly. Until then the app ranks
   by muscles, load type and kind (`Ryft/Train/ExerciseSimilarity.swift`).
   - **Proposal:** `movement_pattern` (string?, **open** like `equipment`, the app must
     tolerate unknown values), e.g. `horizontal_press`, `incline_press`,
     `vertical_press`, `horizontal_pull`, `vertical_pull`, `squat`, `hinge`, `lunge`,
     `fly`, `curl`, `triceps_extension`, `raise`, `carry`. Set on built-ins, optional on
     `POST /v1/exercises`. The app ranks same-pattern exercises first and falls back to
     muscles.
   - **Screens affected:** the replace-exercise sheet in an active session.

## Focused session (open, 2026-11-04)

1. **Which session `last_time` came from.** The workout screen's last-time card heads its table with the date and the
   session's title ("Tue 3 Nov · Upper"). `PlanTarget.last_time` is `[Set]`, so the app has no title, and only a date
   when `completed_at` is set.
   - **Proposal:** add `PlanTarget.last_time_session`: `{ "id": "…", "title": "Upper", "started_at": "…" }`, or `null`
     with an empty `last_time`. The same on whatever serves a single exercise's last time, for exercises added or
     replaced during a session.
   - **Until then:** the card shows the date from `completed_at`, and a plain "Last time" without one. Nothing waits on
     this.

## Charts and gauges (open, 2026-10-19)

The Today / chart redesign asked for fields `API.md` doesn't have. The app doesn't
invent them; these are the stand-ins until the platform serves them.

1. **Strain band on the score: `DailyScore.strain_band`.** A string (`light`,
   `moderate`, `high`, `all_out`) from the platform's own thresholds. Until then the app
   derives the band from `strain` at 10 / 14 / 18 (`MetricSpec.strainBand`).
2. **Readiness → recommended strain range per day: `DailyScore.strain_target_lo` /
   `strain_target_hi`.** Checked 2026-10-30 (plattform 7f0f8db): `API.md` and `SCORING.md`
   have no per-day strain recommendation.
   - **Why:** the readiness bands already tell people what to do with the day, in the
     `MORNING_SCORE_BODY_*` push copy: "a good day to push" for `balanced`, "Keep the
     load moderate today" for `strained`, "Take it easy today" for `depleted`. A full
     outer orbit is strain 21, which is all-out rather than good, so the Today gauge
     needs the range to show what today's budget is. The app won't invent the weights
     that turn a readiness into a range.
   - **Proposed shape:** two nullable numbers on `DailyScore`, on the 0–21 strain scale
     with one decimal, `strain_target_lo ≤ strain_target_hi`. Both `null` when there is
     no readiness or the `state` is `calibrating`; both set or both `null`.
   - **Screens:** the Today `OrbitGauge` (the band on the outer track, and the arc
     colour past the upper end; built and hidden) and the Strain tab's `MetricGauge`
     target arc (built, empty).
   - **How the app picks it up:** decode and a fixture test, then one mapping line into
     `OrbitGaugeValues.strainBand`. Until then the band stays hidden.
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
   - **Confirmed bug, 2026-10-27, now the priority of this section.** A Garmin run that Apple Health holds once
     (checked by the user) shows 7 times in My Day: 6 on 2026-10-20, 7 a week later. The day reads "7 activities ·
     63.3 km". Garmin Connect rewrites its workouts in Apple Health under a new UUID and deletes the old one. The
     app uploads each new UUID as a new workout, and the deleted copies stay on the platform. My Day already shows
     one row per workout id, so these are 7 distinct ids from the platform.
   - **Also needed:** a one-off cleanup of the copies uploaded before the app began collecting `deletedObjects`
     (e.g. same user, source, activity type, start and end), since the app can't name those ids.
   - **Proposal:** `Sample.id` and `SleepSegment.id` (uuid?, the HealthKit sample's UUID;
     records without one keep today's uniqueness), and on `SyncRequest`
     `deleted: [{"kind": "sample" | "sleep" | "workout", "id": uuid}]`. The platform
     removes what it has under those ids (unknown ids are fine, counted in
     `ignored.*.unknown_id`) and queues the days for rescoring.
   - **(New 2026-10-31) Why a flag is needed.** Ingest decodes with `DisallowUnknownFields`
     (`backend/internal/httpx/httpx.go:143`; `API.md` Conventions: "Request bodies reject unknown fields (`400`)"). A
     `deleted` key or a record `id` sent before the ingest deploy is live would answer `400` for every page, and a `400`
     isn't retried, so every sync would fail on the same page.
   - **How the app learns it:** the flag `sync.deletions` in `GET /v1/config` (an open key; the app's compiled default
     is off). Please add it, off, and turn it on in an environment only once the ingest deploy that takes `deleted` and
     the record `id`s is live there. Ingest should take the fields whatever the flag says (the flag only tells the app
     when to send them). While it's on, the app sends `Sample.id`, `SleepSegment.id` and `SyncRequest.deleted`. On a
     `400` to a request that carries them, it sends that request once more without them and uses the old shape for the
     rest of that sync. Please also: list the flag in API.md → `GET /v1/config` → Shipped with; include the days a
     deletion touched in `days_touched` / `scoring.queued_days`; and fill `hk_id` on a stored row that has none when a
     record with an `id` matches it on the natural key, so rows stored before ids existed become deletable.
   - **Also:** confirm the 10 s cache on `GET /v1/me/sync`, or invalidate it on ingest and scoring, so the app's
     scoring wait doesn't read a stale answer after a deletion.
   - **The orphan gap.** A record the first sync's recent window uploaded and Apple Health deleted before the first
     anchored read is never reported (that read starts without an anchor too). The workout fold (Q2) covers workouts;
     sleep segments from one source could double. Please say whether Q2's fold or a sleep equivalent covers it.
   - **What the app does meanwhile.** The deletion code lands only after the changelog entry "Deletions and HealthKit
     ids" and sends the new fields only while `sync.deletions` is on.
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
5. **(New 2026-11-04) Which account a silent scoring push is for.** The refresh push carries only the day (`{"ryft":
   {"kind": "refresh", "day": "2026-10-19"}}`). APNs can deliver it late, so a push for account A can arrive after a
   direct change to account B on the same phone, and the app can't tell. It then takes that day as scored for B: no data
   of A's, but it can hold back B's "being scored" until a later status read (ADR 0013, "A delayed push from another
   account").
   - **Proposal:** an additive `ryft.account` on the `refresh` push, the id the app knows as `User.id`. If that id
     shouldn't pass through APNs, an opaque per-account value that `GET /v1/me` also returns does the same job.
   - **What the app does with it:** drops a push whose `account` isn't the signed-in one, and treats a push without it
     as today, so old and new payloads work during a rollout.

## Universal links: the AASA (open, 2026-10-20)

1. **`applinks` for the app's paths.** `https://ryftlab.de/.well-known/apple-app-site-association`
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
   `applinks:ryftlab.de` in Xcode (Signing & Capabilities); no code change is needed.

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

## Tracker setup (open, 2026-10-22)

From TestFlight feedback on 1.0.0 (`20261021.141128`, the same tester as Refresh resilience §1): "The Baseline counter is
not moving after 1 day." The tester wears a Garmin. App brief: `CLAUDE_FOLLOWUP_TRACKER_SETUP.md`; platform brief:
`../plattform/CLAUDE_FOLLOWUP_BASELINE_WITHOUT_HRV.md`. The vendor facts below are from
`docs/work/2026-10-22-tracker-setup/trackers-research.md`, checked 2026-10-22.

1. **Count baseline nights from resting heart rate, as the platform brief plans. That is enough for Garmin, which does
   write resting heart rate.** *(Corrected 2026-10-22 after a check on a real iPhone. The first version of this
   request said Garmin writes none.)*
   - **What the device shows.** On the user's iPhone 16 Pro (iOS 27.0.1), Apple Health has **daily resting-heart-rate
     samples from Garmin Connect, stamped 00:00**, plus heart rate, sleep with stages, steps and workouts. There is **no
     HRV**, no respiration and no SpO₂.
     - Garmin's FAQ omits resting heart rate from its list
       (<https://support.garmin.com/en-US/?faq=lK5FPB9iPF5PXFkIpFlFPA>), but the device data beats the FAQ.
     - So `rhrBase.N` fills for Garmin users and only `lnHRVBase.N` stays 0. The brief's change (baseline nights from
       resting HR; HRV counted on its own as `hrv_baseline_days`; calibrating only on HRV when there is an HRV source)
       gets this tester to 7/7.
   - **Answered in part, 2026-10-22.** API.md now has `DailyScore.calibrating_reason` (`short_history` | `no_hrv` |
     `no_rhr`), `baseline_hrv_days` and `baseline_rhr_days` (`baseline_days = min(...)`), see
     [`calibrating_reason`](../../plattform/docs/API.md#calibrating_reason). The app mirrors them in `Models.swift`
     (`DailyScore.calibratingReason`, `baselineHrvDays`, `baselineRhrDays`). These names replace the draft's
     `hrv_baseline_days`. **Still open, as a smaller request:** `recovery_inputs` (which inputs Recovery actually used,
     e.g. `rhr_source`), which the Insights sentence needs. It was not provided and the app invents nothing for it.
   - **Daily samples stamped 00:00.** Garmin's resting HR is one value per calendar day, not a night measurement. Please
     check that `e.last(… SampleRestingHR, dayStart, dayEnd)` (`compute.go:166`) attributes it to the intended day.
   - **A fallback, lower priority.** Oura's export list has no HRV and no resting HR
     (<https://support.ouraring.com/hc/en-us/articles/360025438734-Apple-Health-Integration>; not yet checked on a device).
     For trackers that really write no resting HR, derive a night's resting HR from heart-rate samples in the main sleep
     (method chosen by the scoring-scientist, documented in `SCORING.md`), and say so in `recovery_inputs` (e.g.
     `rhr_source: "tracker" | "derived"`). Apple Watch numbers must not change.
   - **Also:** build the planned Insights sentence "Recovery uses resting heart rate, sleep and breathing rate" from the
     actual inputs. Garmin shares no breathing rate.
2. **`User.trackers: [string]` via `PATCH /v1/me`:** what the user says they wear, the ids from `trackers.json`
   (`apple_watch`, `garmin`, `oura`, …, `other`, `iphone`), validated against a closed set. Shown in
   `GET /v1/admin/users` and `beta_report.sh`. The app stores the choice locally until this exists.
3. **Serve `https://ryftlab.de/trackers.json`** from `web/` (`web/content/trackers/`), cached with an `ETag`. The
   draft content and its schema are in `docs/work/2026-10-22-tracker-setup/trackers.draft.json` and
   `trackers-research.md` (en; de follows). Every entry carries `help_url` and `checked`. Optionally render
   `/setup/<tracker>` pages from the same file. The brand rule applies.
   - **(New 2026-10-31)** The app's catalog schema gains an optional `sync` text per tracker (en + de, plain text under
     ADR 0002's rules), filled in the bundled copy. The served `trackers.json` should carry it when the web side
     publishes the file. URL schemes are compiled in the app and never served (ADR 0012).
     - **The served file must use a `version` later than `2026-10-31.1` and carry `sync`.** The app keeps the newest
       valid copy (ADR 0002 rule 4, "Versions"): a served file at that version or older is outranked by the bundled
       copy and never used, and a newer one without `sync` silently drops the sentences from Today's hint.
4. **Supersedes Refresh resilience §2** (`calibrating_reason`). Done on 2026-10-22: `calibrating_reason`,
   `baseline_hrv_days` and `baseline_rhr_days` are in `API.md`; only `recovery_inputs` stays open (§1).

5. **(New 2026-10-23) A Garmin account never leaves calibrating.**
   - **What happens.** The published contract keeps `calibrating = min(H, R) < 7`. A source that writes no HRV (Garmin, verified
     on a device) gives `no_hrv` with H = 0 forever. So `state` stays `calibrating` for good: no band, and no "vs 7 d" delta
     on Today. That holds even though the account's resting-HR and sleep baselines are personal after 7 nights.
   - **Why it matters.** The brief that started this (§1, "gets this tester to 7/7") isn't met. The app now explains the
     state honestly (design.md §7 rev. 2), but it can't end it.
   - **Ask.** On a `no_hrv` row with R ≥ 7, end calibration (`calibrating: false`, `state` banded from readiness), with
     `calibrating_reason` kept or a new field saying HRV is absent. If that's not the plan, document why `no_hrv` must stay
     calibrating, so the app copy can say so.

6. **(New 2026-10-29, priority: medium) Calibration: `no_hrv` before 7 days of data when no source has ever delivered HRV.**
   - **Why.** `no_hrv` needs `W >= 7` (API.md, `calibrating_reason`, rule 3). Before that, an account whose watch never writes
     HRV to Apple Health (e.g. a Garmin, whose app does not share HRV) gets `short_history` with H = 0 for the whole first
     week, and the app can't tell "HRV will come" from "HRV never comes". Seen in the beta with a Garmin: weeks of scored days without any HRV.
     Screens affected: Today (the baseline counter and the learning note), the Today widget.
   - **What (ask).** Decide `no_hrv` (or a new hint) earlier when the account has never received any HRV sample from any
     source, e.g. after N >= 3 days with data, H = 0 and no HRV on the day. The platform picks the rule and documents it in
     `calibrating_reason`. `calibrating_reason` is a closed enum, so a new value needs /v2; a hint would be a new optional
     field (e.g. a bool on `DailyScore`). Reusing `no_hrv` needs no new shape.
   - **What the app does meanwhile.**
     - It counts the filling signal (resting HR, n of 7) with a note.
     - It shows the "no HRV" state (N1) at once when the user's tracker setup says the source doesn't share HRV.
     - Otherwise it still shows "0 of 7" when both counts are 0 and the day has neither signal.
   - **Old clients.** An earlier `no_hrv` makes them show N1 earlier, which is correct. A new optional field is ignored.

**Corrections to the evidence commands in the brief (from the debugger, T0):**
- `scripts/user.sh <id>` prints `with HRV N` (`days_with_hrv_14d`) and the newest record per kind, not
  `User.sources`. Use `scripts/beta_report.sh` for source kinds.
- No operator route serves `GET /v1/days` for another user. Use the read-only SQL in
  `docs/work/2026-10-22-tracker-setup/t0.md`.
- The kind `hr` also covers resting HR, so the sources alone can't prove resting HR arrives.

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
2. **Superseded 2026-10-22 (answered by API.md: `calibrating_reason`, `baseline_hrv_days`, `baseline_rhr_days`; see
   Tracker setup §1 and §4).** Why a day is calibrating. Today the app can't tell "history is short" from "no HRV or resting HR at
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
