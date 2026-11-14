---
name: review-checks-session-ui
description: RYFT review checks for live-session UI planners and pinned controls (T2 jump-to-next, 2026-10-29) — planner vs nextUp warm-up mismatch, impossible test inputs, children:.ignore hiding buttons from Voice Control, collapsing the VO-focused row
metadata:
  type: feedback
---

Found in the T2 jump-to-next review (2026-10-29); the suite was green:
- **The planner and the order owner must agree on "open".** `SessionAdvance.isFinished` ignored open warm-ups, but
  `SessionController.nextUp` (which the planner gets as `next`, and which drives `isAllDone`, the highlight and the
  rest bar's "Next:") counts them. Result: one unchecked warm-up makes every later jump go back to it, and "All sets
  done" never shows. The planner test passed `next = B`, an input the controller can't produce. **Check that pure
  planner tests use inputs built by the real controller**; a temporary probe `@Test` reporting via `Issue.record`
  through the controller settles it in one run (xcresulttool `get test-results tests`, "Failure Message" nodes).
- **"First open set globally" as the jump target** goes back up to a deliberately skipped set after every exercise.
- **`.accessibilityElement(children: .ignore)` over real buttons** removes them from Voice Control too;
  `accessibilityInputLabels` on those children don't do anything. A VO double-tap on an element with no default
  action lands on its centre point, which can be a child button.
- **Auto-collapse removes the element VoiceOver is focused on**; a bare `LayoutChanged()` doesn't put focus anywhere.
- New delayed tasks on a controller: check that `stop()` / `finish()` / `discard()` cancel them (T2 didn't).

**Why:** none of these showed up in the PR's own tests. **How to apply:** use these on any session/workout UI that has a
pure planner, a pinned control or an auto-collapse. See [[review-checks-multistep-flows]], [[review-checks-dark-launch]].

Re-review (d14868e / f4cabb2, 2026-10-29):
- **A "one definition" fix can miss a call site.** `nextUp` moved to `SessionAdvance.next` (working sets only), but
  `startRest`'s superset check still counted any open set. A leftover warm-up on a partner skipped the rest after
  the round. Grep each old predicate (`!$0.isCompleted`) after this kind of refactor.
- **A collapse without a scroll** above the viewport moves the rows under the user's thumb, because ScrollView keeps
  its content offset.
- **Merge hazard:** T2's `var nextUp { nextUp(after: nil) }` plus T1's old `nextUp(after:)` body (`return nextUp`)
  recurse forever. Flag which side of the conflict to take.
- **Probe mechanics:** `Issue.record` failures make xcodebuild collect simulator diagnostics into the xcresult, and
  that once filled the disk. Have the probes append to a scratchpad file (the simulator can write host paths) and pass.
  In zsh, put `-only-testing` flags in an array (`O+=(…)`, `"${O[@]}"`) because a string isn't word-split.

Final review on the merged state (51cfc28, 2026-10-30):
- **A derived guard hides a stale membership but doesn't remove it.** `isCollapsed = collapsed.contains && finished`
  hid ids whose card had an open set again (add set after a carried collapse; Undo of a split after a jump). The
  next finishing tap then collapsed the card at once, without the 0.6 s delay and even with the setting off. Probe
  the "id stays in the set" case, not just what is rendered.
- **Hiding a running timer** (rest bar hidden when all done) brings it back later as a "Rest over" banner, and the
  lock screen keeps counting. Check what happens when the hidden state ends.
- Line-survival and per-key xcstrings merge checks were clean. Running them in the background
  (`run_in_background`) avoids the 120 s timeout.
- **`.id(counter)` bumped on `scenePhase == .active`** to re-run a check (T1 hint card, 2026-10-31): declaring
  `@Environment(\.scenePhase)` already invalidates the body, so the id bump mostly adds identity churn (VoiceOver
  focus on a rebuilt button after returning from the App Store/app). Check animation scope too: a `.animation(value:)`
  on the parent would turn the swap into a cross-fade.

Focused session PR 1 review (53e65e6, 2026-11-04), confirmed with UI probes in a private copy (`-RyftFlags <flag>` in DEBUG,
`-testPlan UISmoke`, since the default plan rejects `RyftUITests`; append to a scratchpad log from the app):
- **A cover keeps updating while it dismisses.** `live = nil` doesn't stop `.onChange` in the presented view. A view-side
  "pin the derived value" `.onChange` undid `clearPage()` 15 ms later, and after Discard it wrote and saved on the deleted
  row. Any write from `.onChange` needs a phase guard.
- **Folding hides what the keypad is on.** Check every way a row leaves the screen (pill, auto-fold) against `focus`,
  not only page changes.
- **Custom `isPresented` binding that nils the item, action reads the item:** on iOS 27 the action runs first (probed), so
  this is not a bug there. Don't report it without a probe; iOS 17 is unverified.
