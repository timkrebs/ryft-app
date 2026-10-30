# I1: duplicate "Last time" lists in a plan session

Read-only investigation. Counts only from the user's export; no content quoted.

## Symptom

Plan session, day "Upper": "Incline bench press" and "Bench press" show the same "Last time"; "Reverse pec deck" appears
twice, and its "Last time" lists five sets for a 3-set target. A greyed row "4 / 85 / 5" (unchecked) sits above the
second Reverse pec deck.

## How "Last time" is built (the chain)

1. Platform: `GET /v1/plans/today`, `cmd/api/train.go:424` calls `LastWorkingSets(user, pe.ExerciseID)` for every plan
   exercise. `store/train.go:874-896`: the completed working sets of that `exercise_id` in the newest completed
   session containing it, `ORDER BY e.position, st.set_index`. Two entries of one exercise in a session are
   concatenated. It is per `exercise_id`, not per plan exercise or occurrence.
2. App: `Ryft/Networking/Models.swift:1893` `PlanToday.target(for:)` matches by `planExerciseId`;
   `Ryft/Train/SessionFactory.swift:22` copies `target.lastTime` into `LocalSessionExercise.lastTime`
   (`Ryft/Train/Model/LocalSession.swift:172`, JSON blob).
3. Display: `Ryft/Features/Train/Session/ExerciseCard.swift:224-235` `lastTimeText` filters warm-ups and cuts at
   `prefix(5)`. No de-duplication, no per-occurrence split.

## Hypothesis A (mapping): evidence

- In the export, the plan day in question holds two different machine fly rows: a fly ("source row F") and a reverse
  fly ("source row R"). Each has 3 working sets in every session of that day. If both map to Reverse pec deck, the
  newest session holds 6 working sets of that id, and the card shows `prefix(5)`. That is exactly the "five sets for
  a 3-set target" in the report.
- The file's incline and flat barbell bench rows have 4 sets each in every session of that day. If both were one
  exercise, there would be 8 sets, cut to 5, and the lists would be identical. That matches "identical Last time". But
  the two cards would then have the same name (the name comes from the plan exercise's library exercise,
  `SessionFactory.swift:12`), and the report says the names differ.
- The default matcher does not do this. I ran `ExerciseMatcher` (`Train/Import/Mapping/ExerciseMatcher.swift`),
  `ExerciseNormalizer` and `Resources/exercise-aliases.json` by hand over the export's keys. Library: the platform seed
  `backend/internal/db/seed/exercises.json`.
  - Incline barbell bench row: exact tier → `incline-bench-press`. Alone.
  - Flat barbell bench row: exact → `bench-press`. Alone. (`machine-chest-press` has the alias "bench press" for
    machine only, and the equipment filter blocks it for barbell.)
  - Source row F: no exact match and no alias. Fuzzy Dice 0.5 with the German library name "Butterfly" → `pec-deck`
    (tier `.fuzzy`, "Possible match"; it needs a tap, `ExerciseMatch.needsReview`). `reverse-pec-deck` scores 0.40.
  - Source row R: fuzzy Dice 0.67 → `reverse-pec-deck`.
  By default the four rows map to four different exercises. A collision needs a user choice (the row is a "check"
  row) or a remembered match (`ImportMappingStore.remembered`, checked first in `ExerciseMatcher.match(key:)`).
- Nothing in the import warns when two source rows end up on one RYFT exercise. A grep of `Features/Train/Import` and
  `Train/Import` finds no such check (`ImportMapView`, `ImportMappingState`). Mappings are per key
  (`ImportFlowModel.swift:332`, `ImportMappingStore.remember`), so two keys on one exercise id is legal and silent.
  Such an import also writes both rows into the plan day (`ImportPlanAssembly.swift:56-75`; the ids differ because the
  source keys differ), and both sessions' rows go into one exercise id in history.
- **Lead's correction (2026-10-29):** the day name "Upper" in `brief.md` is the lead's redaction. The real day name is
  one the import creates from the file. So the plan in the screenshot is the imported plan, and the duplicate row most
  likely comes from A: source row F was resolved to Reverse pec deck, by a tap or a remembered match. The original
  version of this paragraph concluded "edited or built by hand"; that rested on the redacted name.

## Hypothesis B (real duplicate): evidence

- The plan builder has no duplicate rule: `Train/PlanValidation.swift` lists missingName, daysPerWeek, weeks, noDays,
  emptyDay, sets, reps, target, rest, lonelySuperset. The same exercise twice in a day is legal.
- Either way the result on the card is the same: two plan rows with one `exercise_id` each get the full concatenated
  list from step 1 above. So the *card symptom* is explained by "same exercise_id twice in a day" regardless of how
  it came about.

## Verdict

Both are consistent; neither is provable from code and the export alone. Strongest reading:
- Reverse pec deck: two plan rows with one id (A via import choice/remembered match, or B by hand). The 3 + 3 = 6 sets
  cut to 5 fits the export's set counts exactly. Cause of the second row is the one open question.
- Incline vs Bench identical: only explained if both rows carried one `exercise_id` (8 sets, cut to 5). The default
  matcher never maps them that way. If the screenshot truly shows two different names, no code path found makes two
  different ids return the same list (query is `e.exercise_id=$2`); that part is **unexplained** and needs the real
  ids.

To settle it (platform side, I don't touch `../plattform`): run `scripts/trace.sh <request id of GET /v1/plans/today>`
for the failing session, and compare `targets[].exercise_id` of the four plan exercises. Same id twice = A or B
confirmed; different ids with equal `last_time` = a platform bug in `LastWorkingSets` (not expected).
App side to settle it: a unit test that runs `ExerciseMatcher` with the seed library over these four keys (synthetic
names are enough) and asserts four distinct ids; it guards the default so a collision can only come from a choice.

## Ghost row "4 / 85 / 5" (unchecked)

It is the previous card's open 4th set, not a stale row. `ExerciseCard.swift:106-112` renders one `SetRow` per
`orderedSets` entry with `number: i + 1`; the 4-set plan gives rows 1-4 (Bench press / Incline have 4 target sets).
An unchecked row with no entered values shows `ghost` text in `Theme.textTertiary.opacity(0.7)` (`field(...)`,
`ExerciseCard.swift:97-111`), the ghost being `LocalSessionExercise.ghost(forSetAt:)`
(`LocalSession.swift:189-193`): last time's set at the same working index, else the target. With the concatenated
list the 4th ghost is the old set 4 and may even belong to the other exercise's sets. So it looks "finished" but is
only grey text: the check button is unchecked (`set.isCompleted == false`). No stale-row path found: rows are created
once in `SessionFactory.fromPlan` (`appendSet` per target set).

## Proposed fix (app side)

1. Make the collision visible at the source (import): in the match step (`ImportMapView` / `ImportMappingState`)
   when two source rows of one import resolve to the same RYFT exercise, show a notice on both rows ("Also used for X")
   and keep the choice possible. Also add the unit test above (matcher default keeps them apart).
2. Entry point to repair what already exists: "Re-map imported exercises" is not possible as an on-device
   rewrite: imported sessions are on the platform with their exercise ids, and the resend never overwrites
   (`newer_on_server`). The honest repair is what exists: Profile -> Data -> "Clear remembered matches"
   (`ImportProfileRows.swift`) plus an import of the same file; but ids are derived per key, so the same session ids
   come back as `unchanged`/`newer_on_server`, not as updated exercise ids. Needs a platform decision (see below). Do not
   build a re-map UI before that.
3. Display: the app can limit the damage without the platform. `Set.setIndex` restarts for the second occurrence
   (the query orders by position, then `set_index`), so `lastTimeText` and `ghost(forSetAt:)` can take only the first
   run (stop where `setIndex` does not increase) and, for the Nth plan row of one exercise in the day, the Nth run.
   This is a heuristic; it is wrong when the user deleted sets mid-session (indexes then still increase) but safe
   otherwise. Also: `prefix(5)` is a silent truncation; show "+N" or all sets (wrapping) so a 6-set list isn't read as a
   5-set list.
4. Proper fix: per-occurrence last time from the platform (below).

## API_REQUESTS.md entries needed

- **Per-occurrence `last_time`** (`GET /v1/plans/today`): for plan exercises sharing an `exercise_id` in one day, the
  Nth plan row (by `position`) gets the Nth occurrence's sets of the last session (or, as a minimal rule, the first
  occurrence for all), instead of the concatenation of all occurrences. No new field; behaviour of `PlanTarget.last_time`
  documented as such.
- **Re-map of imported history** (only if we want repair): a way to move an imported session exercise (or all rows of a
  source key) to another `exercise_id`, e.g. `POST /v1/train/import` accepting an item with changed exercise ids
  as `updated` when the session is still untouched by the app (today: `newer_on_server` blocks only changed items,
  so ask platform what a changed exercise id of an unchanged session does). Question, not a request yet.
- Nothing else: no new field is needed for the display fixes in items 1 and 3.
