# The focused session screen: review log

## PR 1 (T1), code-reviewer on `464554f..53e65e6`

No blocking finding. Flag off is unchanged: verified by reading and probing. Everything below happens only with the flag on.

| # | Finding | Decision |
| --- | --- | --- |
| S1 | `pinPage()` writes after the session ended, to a deleted row on Discard | Fix: guard on `isUnderway` |
| S2 | `clearPage()` is undone 15 ms later by the re-pin and moves the stored page during the dismissal | Fix: delete it, amend ADR 0013 decision 5 |
| S3 | The keypad stays on a warm-up that folding hid; digits go to an invisible row | Fix: close focus on fold |
| S4 | Auto-fold removes the row VoiceOver is on | T2, with the VoiceOver focus work |
| S5 | Time and distance rows are editable through "Edit reps" and keypad Next | Fix; the ghost-fill in `toggleCheck` stays L20's open item |
| N1 | `nextField`, `nextLabel`, the pad header count hidden warm-ups | T2, pad header added to its list |
| N2 | Layout closure called once; unused preview parameter | Fix: pass a value. `tappedSet`, `follow` stay for T2 |
| N3 | Dead `ExercisePage.usesWeight` | Fix |
| N4 | `currentSetID` per row; `pageExerciseID` builds planner states needlessly | Fix |
| N5 | "A refresh never changes a running session" overclaims: reopening does, which suits a rollback | Fix the wording |
| N6 | Shots use the wrong UIKit trait for AX3 | Fix |
| N7 | Warm-up and working set share `set.0.1`, and the delete dialog's wording | Fix, Focused only |

localization-editor: `SessionPagerPreview` strings sit outside `#Preview` and would enter the catalog: wrap them in `#if DEBUG`.

test-engineer: all five mutants killed. UI first launch ignored its arguments in 3 of 6 runs on a loaded Mac; guarded in the new test, cause unknown.

## PR 1 (T1), ui-validator on `7eb6233`

No blocking finding. Flag off matches `origin/main`: the page below the header hashes the same in dark English and light German, the header was compared by eye. Run on the real app at 390 pt on iOS 27.0. The 320 pt width has only the `make focused-shots` renders, no device at that width exists here.

| # | Finding | Decision |
| --- | --- | --- |
| 1 | The rest card sits above the strip, so the strip drops about 270 pt on a check | T3, named in the PR body |
| 2 | Chip row cut off with no fade | No change: the 16 pt mask is there and shows in the screenshot, the report misread it |
| 3 | Chips touch each other and the table header at AX3 | Fix: 6 pt between chips, 8 pt under the stack |
| 4 | Finish wraps per syllable and the title truncates at AX3 | T5; `origin/main` does the same with the flag off |
| N1 | The warm-up marker reads "A" in German, `design.md` says `W` | No change: the shipped translation, History uses it too. `design.md` meant the English value |
| N2 | A long strip has no jump to the first tile | No change: scrolling the strip reaches it |
| N3 | A scrolled page is clipped hard at the strip edge | T5 |
| N4 | Warm-up "W" contrast on light, about 4.5:1 estimated by eye | T5: measure the token |
| N5 | The target chip's label holds "@" and "×" | T5: hear it with VoiceOver by hand |

Still unverified: real VoiceOver, Reduce Motion at runtime, the offline banner in the app, 320 pt in the app, Dynamic Type at exactly XL.

## PR 1 (T1), Copilot on #90

All three checked against the code before fixing. All three are real and only happen with the flag on.

| # | Finding | Decision |
| --- | --- | --- |
| C1 | A stored time or distance row speaks the ghost's reps next to its value | Fix: no reps ghost when the row has a stored value |
| C2 | Reorder moves the current tile off the strip, because the page doesn't change | Fix: recentre when the order changes |
| C3 | Undo of a replace reopens the keypad on a warm-up that folded in the meantime | Fix: open the group first. Same class as S3, which only covered folding |

C1, C2 and C3 each have a test that fails without the fix. `FocusedSessionUITests` 12 of 12; the reorder test passed 3 of 3 on its own, because it depends on the Reorder sheet's layout and runs outside the smoke plan.

## PR 2 (T2), code-reviewer on `ec33197..e532b6d`

No blocking finding. List is unchanged with the flag off: by reading, and `ExerciseCard` renders the same pixels in 4 states in one appearance. The planner to page path works, and no path loses typed digits. Everything below happens only with the flag on.

| # | Finding | Decision |
| --- | --- | --- |
| S1 | The Live Activity's "Next" goes stale after a row tap, a keypad move or a swipe | Fix: refresh in `activate`, `showPage`, `edit` |
| S2 | Unchecking a set leaves the keypad on another row, so digits go to a row that isn't active | Fix: close it in the Focused uncheck branch |
| S3 | Undo can put the keypad back on a folded warm-up | Already fixed as C3 on T1 |
| N1 | A tap during the 0.6 s delay is lost on a superset flip | Fix: `activate` stamps the manual window |
| N2 | An in-place replace keeps the old tap, so the new exercise starts on set 3 | Fix: clear `tappedSet` |
| N3 | Next off the end of the table leaves the last row active while earlier sets are open | Fix: clear `tappedSet` where the pad closes |
| N4 | Removing the last-checked exercise skips the page fallback | Fix: clear `lastCheckedExercise` in `remove` |
| N5 | `moveVoiceOver` starts an uncancelled task, it can post after a minimise or a swipe | Fix: one handle, cancelled on a new move and on disappear |
| N6a | The `checkActive` comment says time and distance have no field; a non-stored row has one | Fix the comment: they keep today's behaviour under L20, so ✓ on an empty one logs |
| N6b | Nothing scrolls the active row into view | Recheck in T3, where the pill changes the numbers, and at 320 pt |

From the implementer on L23: on an empty active row, VoiceOver's "Check off" opens the keypad with no announcement. Fix: announce it.
