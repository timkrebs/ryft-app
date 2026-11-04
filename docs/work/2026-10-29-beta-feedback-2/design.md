# D2: SessionController for replace / edit targets / undo (F1) and jump to next (F2)

Owner: ios-architect. Inputs: `brief.md` §1, §2, Tests; `plan.md`. Lasting part: ADR 0009. Synthetic values only.

## Facts this rests on (read in the code)

- **In-progress `PUT /v1/sessions/{id}`** merges by id and **keeps** rows the body leaves out (`train.Merge`). An
  existing row id is updated in place, `exercise_id` and `plan_exercise_id` included (`ON CONFLICT … DO UPDATE`).
- **The 409 path** (`SessionMerge.merge`): the local exercise fields win and only sets merge. Server-only exercises
  are **appended**, since no exercise tombstone exists. `LocalSession.apply` never changes the `exerciseId`/`name` of
  an existing row.
- **`LastWorkingSets`** picks the newest completed session that has *a row* of the exercise. A leftover empty row of
  exercise E on the server makes E's next "Last time" `[]`.
- **Progression** (`PlanExerciseAttempts`) counts `plan_exercise_id = pe.id`. Fallback: `plan_exercise_id IS NULL AND
  plan_day_id = day AND exercise_id = pe.exercise_id`. "Today" advances by the session's `plan_day_id` only.
- **`PUT /v1/plans/{id}`** replaces the plan whole and deletes plan exercises left out. Session links to them become
  `NULL` (`ON DELETE SET NULL`). A session `PUT` that names a deleted plan exercise is a **422**, and the outbox drops
  that op. Built-in plans are a 403.
- Targets, `restSec` and `supersetGroup` of a `LocalSessionExercise` are local only (not on the wire).
  `TrainLibrary.savePlan` is online-only. The app has no kg/lb setting.

## 1. Replace, nothing done: mutate the row in place (chosen)

| | A: mutate the row (same id) | B: delete + insert a new row |
| --- | --- | --- |
| Server | The same row gets the new `exercise_id` and `plan_exercise_id: null`. Nothing is left over. | The old row stays with the old exercise and plan link. It blanks that exercise's "Last time", and the fallback can count it. |
| 409 | The local fields win. | The old row returns as an empty card unless a new tombstone is added. |
| Set ids, view | Kept. `.id(ex.id)`, focus and scroll anchors stay valid. | New sets plus tombstones; the view re-mounts. |

**A.** "Nothing done" means **no completed set, warm-ups included**, so no logged set ever changes its exercise
(stricter than the brief's "working sets"). The mutation:

- `exerciseId`, `name`, `kindRaw`, `loadTypeRaw` ← the new exercise. `planExerciseId = nil`, `targetKg = nil`.
- `targetValue = nil` unless the target kind is `.rpe`.
- Keep `targetSets`, `targetRepsMin/Max`, `restSec`, `supersetGroup`, `position`, `notes`.
- Sets keep their ids. Their values typed but not checked are cleared (they were the old lift's), and
  `updatedAt = now`.
- `lastTime = library.cachedLastTime(new.id)` at once, then `await library.lastTime(new.id)`. That second result is
  applied only if `exerciseId == new.id` still holds. Offline with no cache: `[]`, so no ghosts.

## 2. Replace with done sets: split

- **Old row X** keeps its done sets, `planExerciseId`, targets and position. Its **open** sets are deleted (tombstoned
  in `deletedSetIDs`, as in `delete(_:from:)`). They are *not* moved: a set moved locally would come back under X from
  the 409 copy (per-exercise `mergeSets`) and collide with SwiftData's unique id.
- **New row Y:**
  - a new id at `X.position + 1`; `renumber()` shifts everything after it;
  - `supersetGroup = X.supersetGroup`, so the bracket and the `nextUp(after:)` alternation carry on;
  - `restSec`, `targetRepsMin/Max` and the same `targetValue` rule as §1;
  - `targetSets = X's open count`, `planExerciseId = nil`, and `lastTime` as in §1;
  - one new empty set (new id, `isWarmup` kept) per open set of X.
- **The sheet's line:** `replaceKind(for:) -> .inPlace | .split(done: 2, remaining: 2)`.
- **Progression:** X with 2 of 4 sets is a missed attempt (`attemptMet` needs every set), so the target repeats.
  That is correct for "did half, then switched".

## 3. Undo (5 s)

```swift
struct ExerciseSnapshot: Equatable {   // every stored field of LocalSessionExercise, as values
    let id, exerciseId: UUID; let name, kindRaw, loadTypeRaw, notes: String; let position, restSec: Int
    let supersetGroup: Int?; let planExerciseId: UUID?; let targetSets, targetRepsMin, targetRepsMax: Int?
    let targetKg, targetValue: Double?; let targetKindRaw: String?; let lastTimeData: Data?
    let sets: [SessionSet]              // LocalSet.wire, ids included
    init(_ ex: LocalSessionExercise)
}
struct ReplaceUndo: Identifiable {
    let id: UUID; let expiresAt: Date; let message: String          // "Replaced with Bench press"
    let before: ExerciseSnapshot; let inserted: UUID?; let focus: SetFocus?; let planBefore: Plan?
}
private(set) var undo: ReplaceUndo?    // one slot; a second replace commits the first
func undoReplace()
```

- **Restore:**
  - X's fields come back from `before`. Each snapshot set is written back by id with `update(from:)`.
  - A set the split deleted is re-inserted **with its old id** and taken out of `deletedSetIDs`. Replace calls
    `store.save()`, so the delete has reached the store first.
  - Y's set ids go to `deletedSetIDs`, its id to the new `deletedExerciseIDs`. Then delete Y and `renumber()`.
  - Focus via `edit(set, field)` if that set exists. Then `edited()`, which uploads and refreshes the Live Activity.
- **Restored sets get `updatedAt = now`.** Old stamps would lose to a server copy that already got the replaced state
  (the 409 keeps the newer set). Undo is a new edit, not a rewind.
- **Upload held for the window.** `replace` saves and refreshes the Live Activity, but queues the `put` only when the
  undo commits:
  - the 5 s run out (`clock.sleep`);
  - `pause()`;
  - any other edit, whose own `edited()` sends the whole doc.

  A quick undo never reaches the server, so there is no Y leftover blanking "Last time". If the app is killed in the
  window, the change is on disk and goes up with the next edit or Finish.
- **A `PUT` already in flight** finishes with the replaced state. `enqueuePut` sees `inFlightSeq` and queues a fresh
  one with the restored state. If that in-flight `PUT` gets a 409, `put()` merges `s.wire` read after the await, which
  is the restored state. The newer stamps win, and `deletedExerciseIDs` keeps Y out.
- **Edits during the 5 s:**
  - A set change on X or Y, or any structural edit (add, remove, move, superset, replace, edit targets on X/Y), drops
    `undo` and the toast. Restoring would discard what was just logged.
  - Other exercises, focus and the rest timer keep it.
  - Hook: `changed(_:)` checks `set.exercise?.id` against X and Y; the structural functions clear it.
- **Plan:** with `planBefore`, undo calls `savePlan(planBefore)`. X's old `planExerciseId` comes back only after that
  save succeeds (before it, a `PUT` naming it would 422). If the save fails, the session undo still happens, and the
  toast says the plan keeps the new exercise.

## 4. Plan linkage (API.md, store code)

- **Confirmed:** a row without `plan_exercise_id` counts only via the fallback (same day *and* same `exercise_id`).
  So a replacement is no attempt at the planned exercise. The planned one gets no attempt (in place) or a partial one
  (split). `last_time` is per `exercise_id`, so the replacement feeds its own history.
- **Gap, needs the platform:** the fallback double-counts when the replacement is **also planned that day**. That is
  the F1 screenshot (incline bench → bench press). Bench's plan exercise gets two attempts from one session, ordered by
  random `e.id`. Draft for `API_REQUESTS.md` → Train (C1):

  > **4. Progression fallback counts an unlinked exercise twice.** `PlanExerciseAttempts` counts a session exercise
  > with `plan_exercise_id: null` for every plan exercise of the session's plan day with the same `exercise_id`. When
  > the user replaces a planned exercise mid-session with one that is planned on the same day too, that plan exercise
  > gets two attempts from one session. **Proposal:** the fallback applies only when no exercise of the same session
  > names that plan exercise. Sessions without links (older apps, unmapped imports) keep today's behaviour.

- **"Same lift, other equipment": no request.** Linear progression adds kg to that plan exercise's load. Dumbbells at
  2 × 30 kg say nothing about an 80 kg barbell target, so counting them would corrupt it. The plan toggle (§5) is how
  the new lift becomes the planned one.
- **"Similar" ships without the platform:** `ExerciseSimilarity.rank(for:in:)` (pure, `Ryft/Train/`).
  - Candidates share the first primary muscle.
  - Order: muscle overlap (Jaccard over primary ∪ secondary, primary ×2), then the same kind, then barbell → dumbbell
    → machine → cable.
  - Leave out the exercise itself and archived ones. At most 8.

  Muscles can't tell a press from a fly, so a request (nice to have):

  > **5. A movement pattern on `Exercise`.** For "Similar" when replacing an exercise mid-workout: `movement_pattern`
  > (string?, **open**, like `equipment`), e.g. `horizontal_press`, `incline_press`, `vertical_press`,
  > `horizontal_pull`, `vertical_pull`, `squat`, `hinge`, `lunge`, `fly`, `curl`, `triceps_extension`, `raise`,
  > `carry`. Set on built-ins, optional on `POST /v1/exercises`. The app ranks same-pattern exercises first and falls
  > back to muscles.

- **Extend Train #1** (deleted sets stay on the server while in progress) to **exercises**. Tombstones there would
  retire both local lists.

## 5. "Also change the plan"

- **Shown when:**
  - `session.planDayId != nil`;
  - X has a `planExerciseId`;
  - `library.editablePlan(containing:)` finds a cached, **non-built-in** plan with that plan exercise (a built-in plan
    is a 403, so the toggle is hidden).
- **Offline:** disabled with a reason. There is no plan outbox, and none is added here.
- **Change (pure):** `static func replacing(_ peID: UUID, with ex: Exercise, kg: Double?, in plan: Plan) -> Plan`.
  - The plan exercise gets a **new id** and `exerciseId`/`exercise` = new. Keeping the id would feed the old lift's
    attempts into the new lift's progression. The old links become `NULL`, and the fallback still finds them if the
    user switches back.
  - Kept: `position`, `sets`, reps, `restSec`, `supersetGroup`, `notes`, `targetKind`.
  - `targetValue`: unchanged for `rpe` and `pct_1rm`, `nil` for `bodyweight`. For `kg`: the top completed working
    weight of the new exercise's last history session, rounded to 2.5. With no history the old value stays, and the
    confirmation asks to check it (copy: D1).
- **Order:**
  1. Clear this session's links to the old id (X after a split) **first**, so no session `PUT` can 422.
  2. `await library.savePlan(…)`.
  3. On failure, restore X's link and report `.failed`.
- **"From the next session on":** the running session keeps its rows. After the save, `/plans/today` shows the new
  exercise, and this session's replacement row (`null`, same day, new `exercise_id`) becomes the new plan exercise's
  first attempt via the fallback. That is intended.
- The plan is the cached detail, replaced whole, as the plan editor does today.

## 6. Edit targets (session only)

```swift
struct SessionTargets: Equatable { var sets: Int; var repsMin: Int?; var repsMax: Int?; var kg: Double?; var restSec: Int }
func targets(of ex: LocalSessionExercise) -> SessionTargets
func minSets(for ex: LocalSessionExercise) -> Int        // sets.count − removable
func setTargets(_ t: SessionTargets, for ex: LocalSessionExercise)
```

- Fields: `targetSets`, `targetRepsMin/Max` (1 ≤ min ≤ max ≤ 100), `targetKg` (0–500, kg only), `restSec` (0–900).
  No plan change, no undo (the sheet has Cancel).
- **More sets:** `addSet(to:)`.
- **Fewer sets:** remove from the highest index, and only *removable* sets: not completed and all values nil. Use
  `delete(_:from:)`. The stepper's floor is `minSets`.
- **Swipe-to-delete:** `.swipeActions` needs a `List`, and the rows are in a `ScrollView`, so D1 picks the gesture.
  The controller part is the existing `delete(_:from:)` plus a computed `LocalSet.hasValues` for the confirmation.

## 7. Jump to next (F2): a pure planner

`Ryft/Features/Train/Session/SessionAdvance.swift` (T2):

```swift
enum SessionAdvance {
    struct SetState: Equatable { let id: UUID; let isWarmup: Bool; let isCompleted: Bool }
    struct ExerciseState: Equatable { let id: UUID; let supersetGroup: Int?; let sets: [SetState] } // setIndex order
    struct SetRef: Equatable { let exerciseID: UUID; let setID: UUID }
    struct Input {
        var exercises: [ExerciseState]; var checked: SetRef
        var next: SetRef?                 // controller.nextUp(after: checked exercise)
        var keypadOpen: Bool; var lastManualScroll: Date?; var userExpanded: Set<UUID>
        var enabled: Bool; var now: Date
    }
    enum Step: Equatable { case stay, advance(collapse: [UUID], to: SetRef), allDone(collapse: [UUID]) }
    static let delay: Duration = .milliseconds(600)
    static let manualScrollWindow: TimeInterval = 3
    static func step(_ input: Input) -> Step
}
```

**Rules, in order:**
1. **Stay** when:
   - the setting is off, or
   - the keypad is open, or
   - `now − lastManualScroll < 3 s`, or
   - the check was **out of order**: a completed working set has a higher index.
2. **Collapse:** an exercise is *finished* when it has no open working set (open warm-ups are ignored).
   - Not in a superset: collapse it if finished.
   - In a superset: collapse every member once the whole group is finished.
   - Never collapse a row in `userExpanded`.
3. **Superset with an open partner set:** `.advance` to `next` (A1 → B1 → A2), even when unfinished.
4. **Plain exercise:** advance only if it is finished, else `.stay`.
5. **All done:** `next == nil` → `.allDone`.

**Who owns what:**
- `nextUp(after:)` stays the controller's (it goes from `private` to internal) and is passed in, so the order has
  one owner.
- **Reduce Motion** is view-only (`accessibilityReduceMotion` picks the animation), so it isn't an input.
- **Collapsed is controller state** (UI state, not persisted). It survives a minimised view, the uncheck-expands rule
  is testable, and replace/undo can see it. It is rendered through a derived guard:
  `isCollapsed(ex) = collapsed.contains(ex.id) && ex has no open working set`. An undo, a new set or a 409 can then
  never leave a collapsed card with open sets.

**Controller wiring:**
```swift
// stored, SessionController.swift (T2 block)
private(set) var collapsed: Set<UUID> = []
private(set) var advance: (id: UUID, step: SessionAdvance.Step)?    // the view scrolls on id; `to` = highlight
@ObservationIgnored private var userExpanded: Set<UUID> = []
@ObservationIgnored private var advanceTask: Task<Void, Never>?
@ObservationIgnored private var lastManualScroll: Date?
@ObservationIgnored var jumpToNext: @MainActor () -> Bool = { true }  // the coordinator wires the setting
// SessionController+Advance.swift
func userScrolled()                                  // lastManualScroll = clock.now()
func expand(_ ex: LocalSessionExercise)              // collapsed −= id, userExpanded += id
func isCollapsed(_ ex: LocalSessionExercise) -> Bool
func scheduleAdvance(after set: LocalSet, in ex: LocalSessionExercise)
func checkUndone(in ex: LocalSessionExercise)        // cancel the pending task, collapsed −= ex.id
```

- `toggleCheck` calls `scheduleAdvance` (check) or `checkUndone` (uncheck).
- `scheduleAdvance` cancels the pending task, sleeps `clock.sleep(for: delay)`, and **then** builds `Input` from the
  live state (`keypadOpen = focus != nil`, `now = clock.now()`). A scroll or an uncheck within the 0.6 s therefore
  counts.
- The view:
  - scrolls with `proxy.scrollTo(setID, anchor: .top)`, or to a `"session.end"` anchor for `.allDone`;
  - highlights `to` while `focus == nil`;
  - reports drags with `.simultaneousGesture(DragGesture(minimumDistance: 10))`. That works on iOS 17, and
    `scrollTo` doesn't fire it.
- **The all-done row is derived:** `nextUp == nil && !exercises.isEmpty`.
- **Setting:** `Settings.jumpToNextExercise` (`train.jumpToNext`, default on).

## 8. Steps and the T1/T2 split

1. **T1, first commit, pushed at once; T2 cherry-picks it:**
   - `SessionController.init(…, clock: AppClock = SystemClock(), library: SessionLibrary? = nil)`. The coordinator
     passes the environment's clock and `TrainLibrary`.
   - `@MainActor protocol SessionLibrary` (`cachedLastTime`, `lastTime`, `editablePlan(containing:)`, `savePlan`), in
     `Ryft/Train/SessionLibrary.swift`, with `TrainLibrary` conforming.
   - Un-`private` what the extensions need: `store`, `refreshActivity`, `edited`, `changed`, `renumber`, `ungroup`,
     `nextUp(after:)`.
2. **T1, sync safety:**
   - `LocalSession.deletedExerciseIDs: [UUID] = []` (additive; add a case to `TrainOutboxSchemaUpgradeTests`).
   - Filter it in `SessionMerge.merge` and `LocalSession.apply`.
   - `remove(_:)` appends the id. This also fixes today's empty card that comes back after removing an exercise and
     a 409.
3. **T1:** `SessionController+Replace.swift` (§1–3, §5, §6) and `ExerciseSimilarity.swift`.
   - The `undo` stored property goes **right below `liveActivity`**.
   - In the main file: the undo-drop lines in `changed` and the structural functions, and the commit in `pause()`.
   - Views: in `ExerciseCard`, one `@ViewBuilder` for both the menu and `.contextMenu`, the sheets, and the `SetRow`
     delete confirmation. Also the replace mode of `AddExerciseSheet`, and in `SessionView` one
     `.overlay(alignment: .bottom)` for the toast.
4. **T2:** `SessionAdvance.swift` and `SessionController+Advance.swift`.
   - The stored block goes **right below `lastActivityNext`**; in the main file only the two calls in `toggleCheck`.
   - It owns the structure of `SessionView`: the rest bar out of the `ScrollView`, `onChange(of: advance?.id)`, the
     gesture, the end anchor and the all-done row.
   - It owns `card(for:)`, which switches to a new `CollapsedExerciseRow.swift`.
   - In `ExerciseCard`, only a highlight modifier after `.id(set.id)` in the `ForEach`, which T1 doesn't touch.
   - Also `RestTimerView.swift`, `Settings` and the Profile row.
5. **Expected conflicts** (integration branch, T1 first): `Localizable.xcstrings`, and T1's one overlay line in
   `SessionView`.

## Tests

- **`SessionReplaceTests` (T1):** in-memory `TrainStore`, a stub source returning 409s, `TestClock`, and
  `FakeSessionLibrary` recording `savePlan`.
  - **In place:** id, position, superset, set ids and count kept; `targetKg` and `planExerciseId` nil; values
    cleared; the wire carries the new `exercise_id`.
  - **A done warm-up:** splits.
  - **Split (2 of 4):** X keeps 2 sets and its link; Y has 2 new sets at `X.position + 1` in X's group.
  - **Undo, both kinds:** `ExerciseSnapshot` equals the state before (focus too); the restored stamps are later than
    the replace.
  - **Undo after the held `put` went, then a 409** whose server copy holds Y and the replaced X: the restored state
    stays, and Y doesn't return.
  - **An edit on Y in the window:** `undo == nil`. An edit elsewhere keeps it. After 5 s on the clock: one `put`.
  - **Plan:** `savePlan` called once, with a new plan-exercise id and the kept targets; no toggle for a built-in plan;
    a failure restores X's link.
  - **Edit targets:** never removes a checked or filled set.
- **`SessionAdvanceTests` (T2):** table tests per rule (last set, A1→B1→A2, out of order, scroll at 2.9 s and 3.1 s,
  keypad, setting off, user-expanded, all done).
  - Controller tests: nothing at 599 ms; one request at 600 ms; an uncheck inside the delay cancels it.

## What could go wrong

- **SwiftData re-insert of a deleted unique id on undo:** this relies on the save after the split. Tested; the
  fallback is new ids with a focus map.
- **The double-count of §4** stays until the platform answers. It is rare: the replacement must also be planned
  that day.
- **A stale cached plan** overwrites a newer edit from another device. The plan editor does the same today.
- **Server leftovers remain** after an undo that follows another edit, and after `remove` (until Train #1).
  Possible follow-up for sync-engineer: one `put` with status `completed` after `…/complete` when tombstones exist,
  which replaces the document whole.
- **Fighting the user:** the planner runs at fire time, and any drag within 3 s wins.
