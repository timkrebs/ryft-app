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
