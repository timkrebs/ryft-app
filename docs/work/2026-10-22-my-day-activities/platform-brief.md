# RYFT Platform — activities (manual, RYFT-recorded with GPS) and manual sleep — brief for `platform-lead`

Run: `claude --agent platform-lead` → "Run `CLAUDE_FOLLOWUP_ACTIVITIES.md`". Owners: **platform-architect** (design note),
**api-contract-owner** (first), **database-engineer**, **backend-engineer**, **scoring-scientist**,
**security-privacy-reviewer**, **web-engineer** (privacy text), **test-engineer**. The app half:
`../app/CLAUDE_FOLLOWUP_MY_DAY_ACTIVITIES.md` (My Day, Add activity, Start activity with GPS).

## Contract (`API.md` → Activities; additive)

- `Activity`: `id` (uuid from the app, idempotent), `sport` (closed enum matching the app catalogue: `running`,
  `trail_running`, `walking`, `hiking`, `cycling`, `mountain_biking`, `gravel`, `indoor_running`, `indoor_cycling`, `rowing`,
  `swimming`, `strength`, `hiit`, `yoga`, `mobility`, `climbing`, `skiing`, `ski_touring`, `football`, `tennis`, `padel`,
  `other`), `origin` (`manual` | `recorded`), `start`, `end`, `moving_sec`, `distance_m?`, `ascent_m?`, `descent_m?`,
  `perceived_effort?` (1–10), `notes?` (≤ 500), `splits?` ([{index, distance_m, duration_sec, ascent_m}]),
  `route?` (encoded polyline, optional, only when the user opted in; already trimmed by privacy zones on the device),
  `hr_samples?` (live HR from a BLE sensor: [{t, bpm}]), `client_updated_at`. Server adds: `strain?`, `strain_source`
  (`heart_rate` | `perceived_effort` | `none`), `hr_source?` (source name), `merged_with?` (workout id), `scoring_state`.
- `PUT /v1/activities/{id}` (create/update, idempotent, 256 KiB limit, `422` validation: end > start, ≤ 24 h, not in the
  future, sport in enum), `GET /v1/activities?from&to`, `GET /v1/activities/{id}`, `DELETE /v1/activities/{id}`.
- `GET /v1/days/{day}` / a new `GET /v1/my-day/{day}` (architect decides): today's items in one list — sleep, tracker
  workouts, Train sessions, activities — each with type, times, strain, source(s), so the app's My Day is one call.
- Manual sleep: `PUT /v1/sleep/manual/{day} {bed, wake}` / `DELETE` → a sleep segment `origin: manual`, used only when no
  tracker sleep exists for that night (tracker sleep wins if it arrives later; document), shown as "added by you".
- Error codes, examples, changelog, Swift mirror, `make check-swift`.

## Data and scoring

- Migration: `activities` (+ `activity_routes` separate table for the polyline so it can be excluded, purged and audited),
  `activity_hr_samples`; grants per role; RLS; covered by account deletion and export; retention documented.
- **Strain for an activity:** heart rate in its window from any source after de-dup (tracker HR that syncs later through
  HealthKit, or the activity's BLE `hr_samples`) → TRIMP → strain as for workouts; rescore when HR for the window arrives
  later (ingest marks the day touched). Without HR: `strain_source: perceived_effort` using a documented, conservative
  mapping (scoring-scientist: e.g. session-RPE × duration → load, capped), or `none` — decide, document in `SCORING.md`,
  calibration tests, model version + changelog if day strain changes.
- **Merging:** an activity overlapping a tracker workout (same sport family, ≥ 60 % overlap) is merged: one item, strain from
  the better HR source, distance from the recording with GPS if the tracker workout has none; `merged_with` set; never count
  load twice. Tests for overlap edge cases.
- Day strain includes activities (no double counting with workouts/Train).
- Events through the outbox (`activity.saved`) → scoring; idempotent handler.

## Privacy

Routes are location data: opt-in, minimal (already trimmed), deletable, exported, never logged, not sent to monitoring.
**web-engineer**: privacy policy section for activities, routes and manual sleep (en + de, versioned — new
`PRIVACY_POLICY_VERSION` if the change is material; users re-consent), and App Privacy notes for the app session.
security-privacy-reviewer signs off before merge.

## Done when

Contract published; activities and manual sleep stored, scored, merged and deleted correctly with tests; My Day endpoint (or
day-detail extension) live; privacy texts updated; STATUS lists the app's next step and the user's (policy publish, rescore if
the model changed).
