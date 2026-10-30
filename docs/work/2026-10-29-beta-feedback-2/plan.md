# Beta feedback round 2: plan

Brief: `brief.md` (a redacted copy of `CLAUDE_FOLLOWUP_BETA_FEEDBACK_2.md`). Lead: ios-lead. Started 2026-10-29 from
`origin/main` aadd751.

**Copy rule (public repo).** The feedback screenshots show the user's real training: plan day names, loads, exercise
order. Everything committed (docs, fixtures, previews, tests, PR bodies) uses synthetic values: day "Upper", loads such
as 70 × 8 / 80 × 6. No real `score` row values either: the F3 fixture keeps the *shape* of his row with made-up numbers.

## Tickets

| # | Ticket | Owner | Branch / PR title | Depends on |
| --- | --- | --- | --- | --- |
| D1 | Session-screen spec: Edit menu, replace sheet (Similar, split note, plan toggle), Edit targets sheet, undo toast, collapsed card, pinned rest bar vs large card, all-done prompt | ui-designer | → `ui.md` (this folder) | — |
| D2 | Design note: replace/undo/edit-targets semantics on SwiftData + upload, plan linkage (API.md progression), auto-advance planner + injectable clock | ios-architect | → `design.md` (this folder) | — |
| I1 | §4 "Last time" duplicates: mapping bug or real duplicate? | debugger (read-only) | → `investigation-last-time.md` | — |
| T1 | Replace and edit an exercise during a session (F1) | ios-developer | `feat/train-replace-exercise` · `train: replace and edit an exercise during a session` | D1, D2 |
| T2 | Jump to the next exercise, pinned rest bar (F2) | ios-developer (2nd) | `feat/train-jump-next` · `train: jump to the next exercise, pinned rest bar` | D1, D2 |
| T3 | Baseline counter counts what is filling (F3) | sync-engineer | `fix/today-baseline-counter` · `today: baseline counter counts what is filling` | — |
| T4 | Last time per occurrence / re-map (only if I1 finds an app-side cause) | tbd | `train: last time per exercise occurrence` | I1 |
| C1 | `docs/API_REQUESTS.md`: `no_hrv` early (T3); `movement_pattern` for Similar if needed (T1); per-occurrence last time (T4) | api-contract-keeper | inside T3 / T1 / T4 | — |
| L1 | de strings for T1–T3 | localization-editor | inside each PR, after implementation | T1–T3 |
| Q1 | Tests from the acceptance criteria below | test-engineer | inside each PR | D2 |

T1 and T2 both touch `SessionController`, `SessionView`, `ExerciseCard`. Regions: T1 owns the menus, the sheets and a new
`SessionController+Replace.swift`; T2 owns the scroll/rest-bar structure of `SessionView`, the collapsed card state and a
new `SessionAdvance.swift`. Conflicts are resolved once on an integration branch (T1 merges first).

## Acceptance criteria

**T1**
- Menu order: Replace · Edit targets · Plate calculator (barbell) · History · Rest ▸ · Superset with next · ─ · Remove;
  the same in the card's context menu. Notes entry if the card has none.
- Replace with no completed working sets: same position, superset group, set count, rep target, rest; `targetKg` nil;
  `planExerciseId` nil; ghosts/"Last time" from the new exercise's history (cached; offline → none).
- Replace with done sets: done sets stay on the old exercise (it keeps `planExerciseId`), the new one follows it with
  the remaining planned sets; the sheet shows the one-line split note.
- "Also change the plan" (plan sessions only, off by default) calls the plan save once, from the next session on.
- Undo toast 5 s restores exactly: exercises, sets and values, positions, superset groups, focus; upload follows.
- Live Activity and rest "Next:" follow at once.
- Edit targets: sets (removing only empty unchecked ones), rep range, target kg (kg/lb), rest; session only.
- Swipe-to-delete on unchecked set rows; a set with values asks first.

**T2**
- Checking the last open working set of an exercise (in order): after 0.6 s the card collapses to "✓ Name · N sets ·
  best W × R"; the list scrolls the next open set (`nextUp(after:)`, supersets alternate) to the top under the rest bar,
  highlighted, no keypad.
- No auto-scroll when the user scrolled in the last 3 s, the keypad is open, or the check was out of order. Unchecking
  on a collapsed card expands it. Reduce Motion: no animation. Setting off: nothing happens.
- All done → scroll to the bottom, "All sets done — Finish workout?" with the normal finish flow.
- Rest timer pinned outside the `ScrollView` as a compact bar (ring, time, Next, −15/+15/Skip); VoiceOver: one element,
  time + next as value, adjust as actions.
- Profile → Training → "Jump to next exercise", default on.

**T3**
- S1 with H = 0 and R > 0 (or the reverse): the gauge counts the filling signal, the note says why. Never a counter
  that can't move (app and widgets).
- Tracker setup says no HRV and H = 0: N1 now.
- Readiness while calibrating → the gauge shows it with the learning note; without readiness the Recovery tile shows
  "—" + "calibrating", never a percentage beside a counter.
- Fixtures: the user's row shape (synthetic), S1 H0/R3, S1 both 0, S1 with readiness, N1 early via tracker, legacy row.
- PR says whether build 20261021.141128 had `calibrating_reason` handling (7cae92f, 2026-10-23: it did not).

## Risks
- Replace + undo + 409 merge: removed exercises/sets must not come back from the server copy (`deletedSetIDs`).
- Auto-scroll fighting the user; timers in tests (injectable clock).
- The xcstrings catalog across three PRs (integration branch; strings-catalog rules).

## Lead decisions

1. **Rest card: drop the large card** (ui.md variant A). The brief leaves it to ui-designer, and a card that moves
   between two places at a scroll threshold would jump just as the auto-scroll fires. The PR still shows both variants.
2. **The Undo toast stays for 10 s with VoiceOver on** (5 s otherwise). A 5 s limit is too short to reach it by swiping.
3. **`movement_pattern`:** filed in `API_REQUESTS.md` as a nice-to-have with T1. Similar works without it (ui.md §2), so
   nothing waits on it.
4. **Undo after "Also change the plan":** decided with D2 (see design.md).
5. **Plate calculator:** barbell only (`kind == .barbell`), as in the brief. Today it keys on `usesWeight`.
   **Rest ▸** gets the `timer` symbol.
6. **§4 (I1, `investigation-last-time.md`):** the duplicate Reverse pec deck most likely comes from the import. Two
   machine fly rows of the file both landed on Reverse pec deck, by a tap on a "Possible match" or a remembered match.
   The default matcher keeps them apart, and nothing warns about the collision. **T4 goes ahead** (branch
   `fix/train-last-time-occurrence`):
   (a) import step 4 marks rows that share one RYFT exercise;
   (b) "Last time" per occurrence: the Nth row of one `exercise_id` gets the Nth run of the last session, split where
   `set_index` restarts. The app renumbers sets on delete, so the split is reliable for app sessions;
   (c) no silent cut at 5;
   (d) `API_REQUESTS.md`: per-occurrence `last_time` on `GET /v1/plans/today`.
   **Deferred:** "Re-map imported exercises". A re-import can't move stored history (`newer_on_server`), so it needs a
   platform decision first. That question goes to the user and the platform.
   **Incline vs flat bench showing identical lists is not explained by code.** Different names mean different ids.
   It needs the `GET /v1/plans/today` trace (Needs you).
7. **design.md accepted.**
   - Replace with no done sets mutates the row in place. "Done" includes checked warm-ups.
   - Replace with done sets splits the row; the old row's open sets go to `deletedSetIDs`.
   - Undo is a snapshot. The replace isn't uploaded until the 5 s window has passed.
   - New `deletedExerciseIDs`.
   - "Also change the plan" goes through `TrainLibrary.savePlan`, only for the user's own cached plans, and only online.
     Undo also reverts it, which settles item 4.
   - Weights stay in kg only, because the app has no kg/lb setting.
8. **Swipe-to-delete on set rows** (ui.md doesn't cover it): a trailing swipe that reveals "Delete" on unchecked rows,
   built with a horizontal drag that only starts once the gesture is clearly horizontal, so the vertical scroll still
   wins. The row's context menu also gets "Delete set", for VoiceOver and as a fallback. A row with values asks first.
   Checked rows can't be deleted by swiping.
9. **Platform requests:** C1 files design §4's needed entry with T1 (a replacement is counted twice by the
   progression fallback when the exercise is also planned that day) and `movement_pattern` as a nice-to-have.
   The fallback request goes in now, but the double count isn't confirmed yet: test-engineer turns design §4's
   scenario into a unit test against MockTrain first.
10. **Out of scope, reported:** a set deleted or an exercise removed while a session is in progress stays on the
    server, so it still counts at finish. This contradicts API_REQUESTS Train #1 / API.md, which say completion
    replaces the document whole. It's a platform bug, not an app workaround, and goes on the user's list for
    platform-lead. T1's `deletedExerciseIDs` fixes the local side, where a removed exercise came back after a 409.
11. **T3 open points (sync-engineer's report):**
    - **(1) Path L, long history, no readiness:** the HRV and resting-HR counter stays. It only shows on legacy rows,
      and those turn into `no_hrv` rows once rescored. Recovery shows "—" beside it now. Follow-up only if it's seen
      in the beta.
    - **(2) First week with no signal at all:** filed as the platform request "`no_hrv` before 7 days" (C1).
    - **(4) Widget says "Baselines n of 7" while counting resting-HR nights:** accepted for now. Naming the signal
      needs a snapshot field in both shared copies, so it's a follow-up.
    - **Build history:** 20261021.141128 = 2026-10-21 14:11 UTC. That is `main` at `1eb5192`, before both 9745392
      (one-decision Today) and 7cae92f (`calibrating_reason`). The stuck 0/7 next to 71 % High is exactly that build's
      behaviour.
    - **The user's account on 20261028:** today's row is `no_hrv` → N1, with no counter.
    - **Follow-up from the T4 review:** `ImportPlanAssembly.latestWeight` gives two source rows mapped to one exercise
      the same kg target. Import ticket, not in this brief.
12. **T1 copy (localization-editor's notes):**
    - German puts a space before the ellipsis ("Übung ersetzen …", "Ziele bearbeiten …"). The catalog does this
      18 times and omits it 4 times. This overrides the brief's spelling.
    - English: "Your done set stays with %@" instead of "stays as". The footer names the menu item, "Replace exercise".
    - These go back with the T1 review fixes, so the keys change only once.
13. **Merge order:** #72 (T4) first, because it's ready and small. Then T3, then T1, then T2 (via the integration
    branch).
14. **T2 copy:**
    - "Finish workout" stays "Workout beenden", the existing German.
    - The rest bar's "Next: %@" gets its own key, e.g. `train.rest.next` with the default "Next: %@" and a comment.
      Today it shares a key with Today's day subheading, and that key's comment is wrong for the rest bar.
    - This goes back with the T2 review fixes.
