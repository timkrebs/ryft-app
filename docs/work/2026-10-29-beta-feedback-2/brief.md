# RYFT iOS — beta feedback round 2: swap exercises mid-workout, jump to the next exercise, the stuck baseline counter — brief for `ios-lead`

Run: `claude --agent ios-lead` → "Run `CLAUDE_FOLLOWUP_BETA_FEEDBACK_2.md`". Owners: **ui-designer** → **ios-developer**
(session screen), **ios-architect** (SessionController changes, one short design note), **sync-engineer** (Today
calibration path), **api-contract-keeper** (anything that needs the platform → `docs/API_REQUESTS.md`), **test-engineer**,
**localization-editor** (en + de); reviewers per fleet. Branch per item, PR names below.

## The feedback (TestFlight, iPhone 16 Pro, iOS 27.0.1)

| # | Build | Comment | Screenshot |
| --- | --- | --- | --- |
| F1 | 20261028.131801 | "It would be nice to have the ability to swap/change/edit the exercise during the workout" | Exercise `…` menu: Plate calculator · History · Rest 1:15 · Superset with next · Remove exercise — **no replace** |
| F2 | 20261028.131801 | "It would be nice … if you finish a exercise in workouts and the display jumps to the next exercise" | Incline bench press 4/4 checked, rest card "Next: Bench press · set 1 of 4", but the screen stays on the finished card |
| F3 | 20261021.141128 | "The Baseline counter is not moving after 1 Day. Please look into this issue" | Today: "Learning your baseline — 7 nights to go", gauge **0 / 7**, while the Recovery tile shows **71 % High** and Sleep 6 h 50 m (Garmin via Apple Health) |

Read first: `Ryft/Features/Train/Session/{SessionView,SessionController,ExerciseCard,AddExerciseSheet,RestTimerView}.swift`,
`Ryft/Train/SessionFactory.swift`, `Ryft/Train/Model/LocalSession.swift`, `Ryft/Features/Today/TodayViewModel.swift`
(calibration presentation, paths S1/S2/N1/N2/L), `Ryft/Features/Today/ReadinessCopy.swift`, `Models.swift` (`DailyScore`
calibration fields), `../plattform/docs/API.md` → Train (sessions, `plan_exercise_id`, plan progression, `GET
/v1/plans/today`, `GET /v1/exercises/{id}/history`) and → Days (`baseline_days`, `baseline_hrv_days`,
`baseline_rhr_days`, `calibrating_reason`).

## 1. Replace / edit an exercise during a workout (F1)

**Menu.** In the exercise `…` menu (and the card's context menu), add, above "Superset with next":
- **Replace exercise…** (`arrow.triangle.2.circlepath`)
- **Edit targets…** (sets, rep range, target kg, rest; `slider.horizontal.3`)
- **Notes** (if the card has no visible notes entry yet)

Order: Replace · Edit targets · Plate calculator (barbell only) · History · Rest ▸ · Superset with next · ─ · Remove exercise.

**Replace flow.** Opens `AddExerciseSheet` in a *replace mode* (title "Replace Incline bench press"):
- A **"Similar"** section on top: same primary muscle and movement pattern, the same equipment first, then the
  alternatives (barbell → dumbbell → machine → cable). Then the normal search and filters.
- After the pick:
  - **No completed working sets** → swap in place: same position, same superset group, same number of sets and rep
    target, same rest. Clear `targetKg` (the plan's load belongs to the old exercise), keep the set count. Ghost values and
    "Last time" come from the new exercise's history (`GET /v1/exercises/{id}/history`, cached; offline → no ghost).
  - **Some sets already done** → the done sets stay with the old exercise (it's history). The new exercise is inserted
    right after it with the *remaining* planned sets. Show a one-line confirmation in the sheet: "Your 2 done sets stay as
    Incline bench press. Bench press continues with 2 sets."
- **Plan linkage.** The replacement carries **no `plan_exercise_id`** (it must not count as an attempt at the planned
  exercise's progression). The old one keeps it if it has done sets. Check in `API.md` how progression and "today"
  read attempts. If a replacement *should* count (e.g. "same lift, other equipment"), don't invent it: file it in
  `API_REQUESTS.md`.
- **"Also change the plan"** toggle in the sheet (off by default, only when the session comes from a plan): updates
  that plan day's exercise via the existing plan update path, from the next session on. Confirm with "Changed in your plan
  from the next Upper day".
- **Undo**: a toast "Replaced with Bench press · Undo" for 5 s, restoring the exact previous state (sets, values, focus).
- The Live Activity and the rest card's "Next:" update immediately.

**Edit targets.** A small sheet: sets (stepper; removing sets only removes empty, unchecked ones), rep range, target kg
(per kg/lb setting), rest. These are session-only changes; no plan change here (that's Replace's toggle or the plan
editor).

**Also check while you're in there.** Swipe-to-delete on an unchecked set row (if not present). Removing a set with values
asks for confirmation.

## 2. Jump to the next exercise when one is done (F2)

**Behaviour.** When the user checks the **last open working set** of an exercise:
1. After ~0.6 s (let the check animation and haptic land), the finished card **collapses** into a compact summary row:
   "✓ Incline bench press · 4 sets · best 80 × 6". Tap expands it again; it never re-collapses on its own while
   expanded.
2. The list scrolls so that the **next exercise's first open set** sits near the top (anchor `.top`, under the pinned rest
   bar, see 3.). The row gets a subtle "current set" highlight; it does **not** open the number pad (no focus change), so
   nothing pops up while the user is resting.
3. "Next" follows the controller's existing next-up logic (`nextUp` / `nextLabel()`), including **supersets** (A1 → B1
   → A2 …: inside a superset, scroll to the partner's next set instead of collapsing). If every exercise is done →
   scroll to the bottom where Finish / Add exercise lives and show "All sets done — Finish workout?" (button = the same
   finish flow).

**Don't fight the user.** No auto-scroll if the user scrolled manually in the last 3 s, if the number pad is open, or if
they checked a set *out of order* (checking set 4 while set 2 is open is not "finished"). Unchecking a set on a collapsed
exercise expands it again. Reduce Motion: jump without animation.

**Setting.** Profile → Training → **"Jump to next exercise"** (default on), stored like the other training prefs.

**3. Pin the rest timer** (needed for 2., and it's what the screenshot shows taking a third of the screen): while a rest
runs, the big `RestTimerView` lives at the top of the scroll content and scrolls away when we jump. Move it out of the
`ScrollView`: a **compact pinned bar** under the header (ring + 1:37 + "Next: Bench press · set 1 of 4" + −15 / +15 /
Skip). Keep the large card only when the list is scrolled to the top, or drop it entirely; ui-designer decides and shows
both in the PR with screenshots (light/dark, Dynamic Type XL). VoiceOver: the bar is one element with the remaining time
and the next set as value; the adjust buttons are actions.

## 3. Baseline counter stuck at 0 / 7 (F3)

**Symptom.** A Garmin user (no HRV in Apple Health). After days of use, Today still shows "Learning your baseline — 7 nights
to go" with the gauge at **0 / 7**, while the Recovery tile already shows **71 % High**. That is two contradictions: a
counter that can't move, and a score shown next to "we can't score you yet".

**Likely cause (verify).** `baseline_days = min(baseline_hrv_days, baseline_rhr_days)`. Without HRV it stays 0. Until
the platform has 7 days of any data in the window (`W ≥ 7`), it reports `calibrating_reason: short_history`, not
`no_hrv`. So path **S1** in `TodayViewModel` draws `.baselines(nights: today.baselineDays)` = 0 for the whole first week
and then flips to N1. The feedback build (20261021) may also predate the `calibrating_reason` handling: check git
history for when S1/S2/N1 landed, and say in the PR whether this build had it.

**Fix (app):**
- **Count what is actually filling.** In S1, when `baseline_hrv_days == 0` and `baseline_rhr_days > 0` (or the reverse),
  the gauge counts the filling signal (`fillingSignals` / `CalibrationProgress` already exist: use them). The line
  under it says why: "Resting heart rate 3 of 7 nights · HRV isn't coming from Garmin, so recovery uses resting heart
  rate and sleep". Never show a counter that can't move.
- **Know earlier.** If the tracker setup says the user's source doesn't deliver HRV (`CalibrationBlocker` / trackers
  from the setup wizard) and `baseline_hrv_days == 0`, present it like N1 *now*, not after 7 days.
- **One story on the screen.** If the platform returned a `readiness` while calibrating, show it in the gauge with the
  "learning" note (like S2), and the tiles agree. If there is no readiness, the Recovery tile shows "—" plus "calibrating",
  never a percentage next to a 0/7 counter. Check `Tiles(source:calibrating:)`: today it lets the tile show 71 % in S1.
- Widgets use the same presentation (no counter there either when it can't move).

**Reproduce with the user's real row.** Ask the user (needs-you) to run `scripts/admin/user.sh` for his account and
paste today's `score` fields (`calibrating`, `calibrating_reason`, `baseline_days`, `baseline_hrv_days`,
`baseline_rhr_days`, `readiness`, `hrv_ms`, `rhr`). Turn that shape into a fixture. Also add fixtures for: S1 with HRV
0 / RHR 3, S1 with both 0 (a real first night), S1 with readiness present, N1 early via tracker, and the legacy row
without a reason.

**If the platform should decide `no_hrv` earlier** (e.g. "the user's sources never wrote HRV" rather than waiting for
`W ≥ 7`), don't patch around it in the app. Add a request to `docs/API_REQUESTS.md` ("Calibration: `no_hrv` before 7
days of data when no source has ever delivered HRV"), and ship the app-side fix above anyway.

## 4. Two things in the screenshots to investigate (report, fix if app-side)

- **Identical "Last time" for different exercises.** Incline bench press and Bench press both show "70 × 8, 80 × 6,
  80 × 6, 80 × 6". "Reverse pec deck" appears **twice** in the Upper session, and its "Last time" lists **five** 60 × 10 sets
  for a 3-set target. The platform's `LastWorkingSets` (`plattform/backend/internal/store/train.go`) returns *all*
  completed working sets of that `exercise_id` in the last session, so two entries of the same exercise in one session are
  concatenated. `lastTimeText` then cuts at 5. Hypothesis: the CSV import mapped two different Alpha Progression
  exercises to one RYFT exercise (check the alias table and the user's saved mapping for "Incline Bench Press · Barbell"
  and the pec-deck/rear-delt variants), or the plan really contains the exercise twice. Find which:
  - **Mapping bug:** fix the alias, and add a "Re-map imported exercises" entry point (Profile → Data).
  - **Real duplicate:** the app should show last time per occurrence. File the per-`session_exercise` shape in
    `API_REQUESTS.md`.
- The finished-set ghost row ("4 · 85 · 5", unchecked) above Reverse pec deck: confirm it's the previous exercise's open
  4th set and not a stale row.

## Tests

- `SessionController` unit tests:
  - replace with no done sets (in place, superset kept, `targetKg` cleared, no `plan_exercise_id`)
  - replace with 2 done sets (split, remaining count right)
  - undo restores exactly
  - "also change the plan" calls the plan update once
  - edit targets never deletes checked sets
- Auto-advance:
  - last set → collapse + scroll target = next open set
  - superset alternation
  - out-of-order check doesn't advance
  - manual scroll suppresses
  - setting off
  - all done → finish prompt
- Use an injectable clock for the 0.6 s / 3 s timers.
- Today presentation: the F3 fixtures above, snapshot of each state (light/dark).
- UISmoke: start the demo plan, check all sets of the first exercise, assert the next exercise's first set is hittable
  and the rest bar is visible. Replace an exercise via the menu.

## Ship

PRs:
- `train: replace and edit an exercise during a session`
- `train: jump to the next exercise, pinned rest bar`
- `today: baseline counter counts what is filling` (+ `docs/API_REQUESTS.md` entry if needed)
- `train: last time per exercise occurrence` (only if §4 finds an app-side cause)

Strings en + de (de: "Übung ersetzen…", "Ziele bearbeiten…", "Zur nächsten Übung springen", "Auch im Plan ändern").

TestFlight "What to test": "Replace an exercise mid-workout (… → Replace). After your last set, RYFT jumps to the next
exercise. The baseline counter now shows real progress if your tracker doesn't provide HRV."

Needs-you: the `user.sh` output for F3; reply to the three feedback entries in App Store Connect once the build is out.

> Copy note: plan day name, loads, readiness and sleep values are replaced with synthetic ones (public repo).
