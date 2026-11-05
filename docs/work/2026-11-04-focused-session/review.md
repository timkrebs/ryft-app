# The focused session screen: review log

## PR 1 (T1), code-reviewer on `464554f..53e65e6`

No blocking finding. Flag off is unchanged: verified by reading and probing. Everything below happens only with the flag on.

| # | Finding | Decision |
| --- | --- | --- |
| S1 | `pinPage()` writes after the session ended, to a deleted row on Discard | Fix: guard on `isUnderway` |
| S2 | `clearPage()` is undone 15 ms later by the re-pin and moves the stored page during the dismissal | Fix: delete it, amend ADR 0014 decision 5 |
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

Fixed: S1, S2, N1–N5, N6a, the L23 announcement, and `undoReplace`'s stale `lastCheckedExercise`, the same class as N4. Left for the hand VoiceOver pass in T5: a swipe within 350 ms of a focus move doesn't cancel it, and the `.allDone` announcement doesn't go through the task handle. Both are timing edges only a real run can judge.

## PR 2 (T2), code-reviewer re-verification on `ea0c131`

S1, S2, N1–N5 and N6a are fixed, and List is unchanged.

| # | Finding | Decision |
| --- | --- | --- |
| 1 | The N1 fix stamped the 3 s window on every tap, so a tap followed by a check held legitimate advances and `.allDone`. The lead's instruction caused this | Fix: stamp only during the delay. A test pinned the wrong behaviour and changed with it |
| 2 | The L23 announcement has no German | Already fixed in `a930484` |
| 3 | After a remove, "Next" can name the superset partner of the page | T5 |
| 4 | `remove` reads `ex.id` after the delete | Fix: read it first |
| 5 | `EmptyCheck.setID` is unused by the view | Keep: a test reads it |
| — | ✓ on an empty upcoming row logs a set with no values | Fix: L24. `checkActive` became `checkRow`, and the view holds no state logic any more |
| — | After any check, "Next" follows the last checked exercise, not the page | No change: that's what the planner does next, so the label is right |

## PR 2 (T2), ui-validator on `ea0c131`

No blocking finding. Flag off matches `origin/main` in dark and light, English and German, over seven checkpoints of a List tour: only the clocks, the home indicator and the L22 wording differ. Not covered with the flag off: 320 pt, Dynamic Type, offline, time and distance, Replace, Undo. A run with ✓ taps only reaches All sets done in all four appearances.

| # | Finding | Decision |
| --- | --- | --- |
| 1 | Light: the active row's fields and `#` measure 1.01:1 on the tint | Fix: `surface` in light. The brief says raised white |
| 2 | Light: ghost text on those fields is 4.49:1 | Fixed by 1 |
| N1 | A first tap on an upcoming row only activates it | No change: the brief asks for this |
| N2 | The rest card's "Next:" truncates in German | T3 replaces it |
| N3 | The chip row clips the pencil in German | No change: same as T1, the fade is there |
| N4 | The upcoming ✓ outline measures 1.14:1 in light | T5 |

## PR 3 (T3), code-reviewer on `3852960..8776ade`

One blocking finding, in the tests only. Flag-off List unchanged: `restBarState` guards on `layout == .list`, `settleRestOver` returns early there, and the strings diff is 8 keys added, all with German.

| # | Finding | Decision |
| --- | --- | --- |
| 1 | Blocking, test only: hosted tests started a rest before waiting for the shared window, so the margin on an exact "left" string shrank with the queue | Fixed in `34f5c83`: rests start inside `run` |
| 2 | Deleting the last open set while a rest runs hides the pill; the lock screen keeps counting and the haptic fires with nothing on screen | Fixed in `62f9d71`: `edited()` skips the rest in Focused when no exercises or every set is done, the same rule `startRest(after:)` applies |
| 3 | `keepRowInView` treated any shrink as a reason to pull the page, so the offline banner could drag a reader back | Fixed in `52aa2b6`: `followsResize` reveals only for the keypad, a toast and the pill row returning. A toast can still move a reader; accepted, it is one move per toast |
| 4 | `.height(426)` runs out above default text | Fixed in `339aa09`: any size above `.large` opens at `.large`, default and below offer both |
| 5 | `settle` quiet window equals the scroll animation; `withKnownIssue` is non-intermittent | Fixed in `34f5c83` and `52aa2b6`: 10 polls 50 ms apart, the known issue removed with the 18 pt bug |
| 6 | The footer read as describing the button above it | Fixed in `339aa09`: caption moved above "Set as rest for this exercise" |
| 7 | Start had no input labels | Fixed in `339aa09` |
| Known | The active row 18 pt out at 320 with a keypad and a rest | Fixed in `52aa2b6`: no-anchor `scrollTo`, re-run on growth while the keypad is on this page. The real-frame measure was up to +189 pt below the page before, 0 after |

Left for T5: the page is 138 pt rather than 220 at 320 with keypad and rest; VoiceOver focus when the pill swaps branches at a Skip or run-out; a page `TabView` preloaded doesn't reveal its row on arrival.

## PR 3 (T3), ui-validator on `3021225`

No blocking finding. German sheet at default, XL and XXL, English at XXL and XXXL: the save button stays reachable and the caption stays above it. Pill strings read right in both languages. Flag off: List and `RestBar` render as before, and `RestBar.swift` is unchanged. No pixel diff against `main`.

| # | Finding | Decision |
| --- | --- | --- |
| 1 | The header's Finish breaks over lines at AX3, in German and at 320 pt | T5 |
| 2 | −15 and +15 stay 17 pt in a 64 pt key at AX3 | T5 |

## PR 4 (T4), code-reviewer on `2691484..31f3fb3`

No blocking finding, and no bug in the maths, the default rule, persistence or flag off. Strings: 7 keys added, none changed or removed.

| # | Finding | Decision |
| --- | --- | --- |
| 1 | The UI tests aren't in the PR smoke plan, so the header button had no PR coverage | Fixed: a hosted test on `HostedWindow` reads and activates the button. T5 adds the UI class to the smoke plan |
| 2 | Nothing tested that last time follows the column, and a comment claimed it | Fixed: the UI test waits on the card after each tap, and a mutant is killed |
| 3 | Voice Control couldn't use the name on screen | Fixed: input labels for the title and spoken title |
| 4 | The estimate cell was a dead spot on an upcoming row | Fixed: a tap activates the row, the value stays read-only |
| 5 | The AX rules for the column were in no ticket | T5 |
| 6 | A test name claimed to measure width | Renamed |

Left for T5: `HostedWindow` turns automation off rather than restoring it, and one local UI run straight after Unit on the same simulator failed with `kAXErrorAPIDisabled`. CI runs the same order and passed on #95.
