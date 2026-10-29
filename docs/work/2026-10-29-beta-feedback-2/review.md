# Beta feedback round 2: review log

Findings from the read-only reviewers, what was decided, and whether it was re-verified.

## T4: last time per occurrence (`fix/train-last-time-occurrence`)

**code-reviewer on e6f343f: no blockers**

| # | Finding | Decision | State |
| --- | --- | --- | --- |
| 1 | `last_time` keeps only completed working sets, so gaps can merge two occurrences into one run. With 3 rows, a row could get another row's sets. | Split only when runs == rows, otherwise keep the joint list. Name the real limits in the doc comment and in API_REQUESTS (f92d49a). | fixed in 024809a |
| 2 | The warm-up test used input the platform never sends. No `.check` × `.matched` collision test. | Gap tests and a collision test. | fixed in 024809a |
| 3 | The `last_time` order isn't documented in API.md. | API_REQUESTS #4 now asks for it. | f92d49a |
| 4 | `ImportPlanAssembly.latestWeight` gives two mapped rows the same kg target. | Follow-up import ticket, outside this brief. | open |
| 5 | Hard-coded English quotes. | Localized key `“%@”` (de `„%@“`). | fixed in 024809a |
| 6 | "+N more" had no separator, and de needs a singular. | ", +N more"; plural variation (de "weiterer"/"weitere"). | fixed in 024809a |
| 7 | No preview for more than 5 sets. | `ExerciseCardLastTimePreview.swift`. | fixed in 024809a |
| 8 | `displayName` was duplicated in the view. | Moved to the model, with a shared suffix. | fixed in 024809a |
| 9 | A duplicate `set_index` splits a run. | Documented; falls back via rule 1. | fixed in 024809a |

**Re-verified by code-reviewer on 024809a: all resolved; 38 tests pass.** Two new nits:
- Two rare errors, a gap merge and a 409 duplicate index, can cancel out and pass the count check. Accepted: it needs
  a 409 duplicate.
- The CHANGELOG overstated the fix. Reworded in 44c0aed.

ui-validator: in progress.

## T3: baseline counter (`fix/today-baseline-counter`)

**code-reviewer on 0ea96ee: no blockers. 137 Today tests pass.**

| # | Finding | Decision |
| --- | --- | --- |
| 1 | CHANGELOG promises the N1-early behaviour, which needs the dark `devices.setup` flag. | Qualify the clause. |
| 2 | The widget isn't republished when the tracker choice or the flag changes. | Republish. |
| 3 | The "–" tile's VoiceOver value drops "calibrating". | "No data, calibrating". |
| 4 | The gauge's spoken value repeats the count and says "once the baselines are complete". | Name the signal; drop the sentence. |
| 5 | The mock has recovery without readiness, which the platform can't produce. | `recovery: nil`; keep the guard test. |
| 6 | `{}` string keys. | Done in 81b7ee9 (comments, positional German). |
| 7 | Tracker catalog decoded on main for more accounts. | Accepted. |

**ui-validator: all visible criteria pass.** Should-fix: the counting state's caption and VoiceOver don't say which
signal is counted (merged into #4). AX3 lower half not seen (asked of the owner).

Fixes: sent to sync-engineer in one round.

**T3 shipped as #73** after the main merge (incl. #72): 2508 test cases pass, lint passes. security-privacy-reviewer: no
blockers; the one finding (a real count in the API request's text) generalised in 390b29c.

## T2: jump to the next exercise (`feat/train-jump-next`)

**code-reviewer on 7315e68 / 1097044 / 49c476f: no blockers.** Probes drove the real controller.

| # | Finding | Decision |
| --- | --- | --- |
| 1 | An open warm-up is "next": jumps go back to it, "All sets done" never appears | One "next" for jump, highlight and "Next:": the first open working set after the checked exercise, wrapping. `isAllDone` = no open working set and at least one checked. |
| 2 | A skipped set pulls the list back to the top after every later exercise | Covered by #1: forward first, then wrap. |
| 3 | Voice Control can't reach −15 / +15 / Skip (`children: .ignore`) | `.contain`: the time is one adjustable element, and the three buttons are their own elements with input labels. |
| 4 | VoiceOver focus is lost on collapse | `@AccessibilityFocusState` on the jump target. |
| 5 | A VoiceOver double-tap may press +15 | Explicit default action or activation point. |
| n | The pending jump isn't cancelled on finish or discard | Cancel in `stop()`, plus a test. |
| n | A forgotten middle set doesn't collapse (design §7 rule 1) | The brief wins: done = no open working set after the check. |
| n | A second quick check drops the first collapse; an uncheck cancels unrelated work | Accumulate; cancel per exercise. |
| n | An empty session reads "All sets done" | Covered by the `isAllDone` definition. |
| n | With the setting off, the highlight and all-done card still show | Intended: only automatic scroll and collapse stop. |
| n | Profile → Training isn't flag-gated | Gate on `train.enabled`. |
| n | Rest bar value reads "95 seconds" | `DateComponentsFormatter` `.full`. |
| n | `currentSetID` is computed per row | Once per card. |

Fixes: sent to the T2 developer in one round.

## T1: replace and edit an exercise (`feat/train-replace-exercise`)

**code-reviewer on 2d37fce…f501eee (tests 60faf18): no blockers; 48 tests pass; probes for 1–4.**

| # | Finding | Decision |
| --- | --- | --- |
| 1 | A plan revert after Finish calls `edited()`: a PUT on a completed session, and a new Live Activity | After finishing, completing or discarding, a plan task only saves the plan. |
| 2 | Two quick plan changes: the second PUT (from a stale cache) undoes the first | Chain on `planTask`; read the cache inside the task. |
| 3 | A PUT already queued sends the replaced state inside the undo window | Per-session hold in `TrainSyncService` while the window is open; ADR 0009 stands. |
| 4 | An account change leaves the undo open; the commit writes to the wiped store | `stop()` drops the undo without writing. |
| n | "Plan couldn't be changed" notice after Undo | Track the undo id. |
| n | Rest stepper clamps to 600 | 0…900 (API.md). |
| n | Toast has no escape action; Switch/Voice Control get 5 s | Escape action; 10 s for them too. |
| n | No preview for `SessionToastOverlay`; no CHANGELOG line | Add both. |

Integration note: in `SessionController.changed()`, keep T1's `dropUndo(touching:)` when merging T2
(`anEditToTheAffectedRowDropsTheUndo` guards it).

Fixes: sent to the T1 developer in one round.

**T2 re-verified by code-reviewer on d14868e / f4cabb2: all 13 resolved.** New:

| # | Finding | Decision |
| --- | --- | --- |
| 1 | An earlier collapse applied without a scroll (latest step `.stay`) shifts rows under the thumb | Carry the collapses to the next step that scrolls; drop them on stop. |
| 2 | Superset rest skip still counts open warm-ups | Same "open working set" predicate as `SessionAdvance`. |
| 3 | T1 merge: keeping T1's `nextUp(after:)` body recurses with T2's `nextUp` | Integration: take T2's body. |
| 4 | Lock screen gets the previous exercise's "next" first | Set `lastCheckedExercise` before `startRest`. |
| 5 | A checked warm-up never jumps | Accepted (working sets only). |

Fixes 1, 2 and 4: sent to the T2 developer.

**T1 fixes in c1940dc / 7e80410** (65 focused tests, Unit plan 1930, 0 failed). Lead calls on what the developer raised:
- Voice Control has no public detection API, so the 10 s window applies under VoiceOver and Switch Control only. Accepted:
  the toast's Escape action and the Undo button stay reachable by name.
- The Live Activity after Finish is skipped by the same `isUnderway` check that the tests cover; there's no seam to
  observe it, and none added. Accepted.
- Undo → Finish while the plan save is pending: the finished session keeps X without its plan link. The plan itself is
  reverted. Accepted; it follows from decision 1.
- A plan save that fails after Finish is only logged (the screen is gone). Accepted.
