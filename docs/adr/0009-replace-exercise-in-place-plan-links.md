# 0009 — Replacing an exercise mid-session reuses the row; the replacement has no plan link

- Status: proposed (2026-10-29, beta feedback 2 F1, `docs/work/2026-10-29-beta-feedback-2/design.md` §1–§5)
- Deciders: ios-lead, on ios-architect's proposal. The progression rules are the platform's.
- Applies to: `SessionController+Replace.swift`, `LocalSession` (`deletedExerciseIDs`), `SessionMerge`,
  `TrainLibrary.savePlan` callers that change a plan exercise's exercise

## Context

Users want to swap an exercise during a workout. A session is uploaded whole with `PUT /v1/sessions/{id}`, and while
it is in progress the server **keeps rows the body leaves out**. The app's 409 merge also re-adds server-only
exercises. A leftover row has two effects:
- it blanks that exercise's next "Last time" (`LastWorkingSets` picks the newest session with any row of it);
- it can count for progression through the plan-day fallback (`plan_exercise_id IS NULL`, same day, same exercise).

A plan `PUT` deletes plan exercises left out. Sessions that named one get `NULL`, and a later session `PUT` that
still names it is a 422.

## Decision

1. **No completed set (warm-ups included): the row is mutated in place.**
   - It keeps its id and its set ids, and gets the new `exercise_id` with `plan_exercise_id` null.
   - `targetKg` and load targets are cleared, and unchecked values are cleared.
   - No delete and insert: that leaves a row on the server.
2. **Some sets completed: split.**
   - The old row keeps its done sets and its plan link, and its open sets are tombstoned.
   - A new row right after it gets fresh sets, `plan_exercise_id` null, and the same superset group.
   - Sets are never moved between rows.
3. **A replacement never carries a `plan_exercise_id`.** It is not an attempt at the planned exercise, not even for
   "the same lift with other equipment", because loads across implements aren't comparable.
4. **"Also change the plan" gives the plan exercise a new id**, so the old lift's attempts don't drive the new lift's
   progression.
   - This session's links to the old id are cleared before the plan is saved.
   - Built-in plans are never changed.
5. **Removed session exercises get a local tombstone** (`LocalSession.deletedExerciseIDs`), honoured by the 409 merge
   and `apply`, like `deletedSetIDs`.
6. **Undo is a new edit.** Restored sets get a fresh `updated_at`, and the replace's own upload waits for the
   5 s undo window.

## Consequences

- No server leftovers from replacing in the common paths (in place; split; undo without other edits).
- Done sets always stay with the exercise they were done on. A split counts as a missed attempt for the planned
  exercise (the target repeats).
- The plan-day fallback double-counts when the replacement is also planned that day. Filed as Train #4 in
  `docs/API_REQUESTS.md`; until then it is a known, rare inaccuracy.
- Changing the plan drops the old plan exercise's explicit links. The fallback still finds them by day and exercise.
- If the platform adds exercise and set tombstones (Train #1), points 5 and 6 can move to the wire and the local
  lists go.
