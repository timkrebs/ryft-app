# API requests from the app

What the iOS app needs that `../plattform/docs/API.md` does not (yet) provide.
The platform agent owns the contract; the app never invents fields silently.

## M3b Train (2026-10-19)

`API.md` has no Train section yet. The app is built against the shapes in
`CLAUDE_FOLLOWUP_TRAIN.md` §4 and the platform brief
(`plattform/CLAUDE_FOLLOWUP_TRAIN.md` §1 and §4: enum values, paths, 409 and
completion bodies). It switches to `API.md` and regenerates
`RyftTests/Fixtures/train_*.json` once the contract lands. Please confirm or
correct each point below in `API.md`.

### Assumed, please confirm

1. **`PlanSummary`** (`GET /v1/plans` → `builtin[]`, `mine[]`) is read as `Plan`
   without `days`. Needed: `id, name, goal, weeks, days_per_week, description,
   progression, is_builtin`.
2. **`SessionSummary`** (`GET /v1/sessions`, `DayDetail.strain.sessions[]`) is
   read as `Session` with `exercises` optional. Needed for History and Strain:
   `id, title, started_at, ended_at, status, plan_day_id, workout_id,
   muscular_trimp, strain, volume_kg`.
3. **`PlanExercise.exercise`** is the resolved `Exercise` object ("resolved
   names"). `PUT /v1/plans/{id}` sends it back the same way. If the server wants
   `exercise_id` on write, say so and the app sends that instead.
4. **`POST /v1/plans/{id}/enroll`** answers with the new `Enrollment`.
5. **`409` on `PUT /v1/sessions/{id}`**: the body is the server's whole `Session`
   (not `{"error": …}`). The app merges by set id (later `updated_at` wins, the
   local set on a tie) and PUTs again, at most three rounds.
6. **`POST /v1/sessions/{id}/complete`**: the body is the `Session` plus
   `"prs": [PR]` at the top level.
7. **`ExerciseHistory.sessions[].date`**: the app accepts a day (`YYYY-MM-DD`)
   or an RFC 3339 timestamp; please fix one.
8. **`Workout.session_id`, `Workout.muscular_load`**: the Strain list merges a
   Garmin workout and its session into one row when `session_id` matches.

### Missing, please add

1. **Pause / resume an enrolment.** The brief has enrol and
   `DELETE /v1/plans/enrollment`, but status `paused` has no endpoint. The app
   calls **`PATCH /v1/plans/enrollment {"status": "paused" | "active"}`** →
   `Enrollment`.
2. **Deleting a set while a session is in progress.** The `PUT` "never deletes
   sets the client omitted while `in_progress`", so a set removed on the phone
   reappears on the server. Proposal: a set tombstone, e.g. `"deleted": true` on
   the set (kept until completion), or `DELETE
   /v1/sessions/{id}/sets/{set_id}`. Until then the app keeps removed sets out
   of its own 409 merges, but the server copy still has them.
3. **"Muscular load" on the Today card.** The brief shows "Done · load 11.2"
   (strain scale), while `muscular_trimp` for a typical session is ≈ 85. The app
   shows `muscular_trimp` as *Muscular load* and `strain` as *Strain*. If a
   per-session strain-scale "load" is intended, please name the field.
