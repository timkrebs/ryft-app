# The focused session screen: plan

Brief: `brief.md` (redacted copy). Lead: ios-lead. Started 2026-11-04 from `origin/main` 0b6069b.

**Copy rule (public repo).** The reference screenshots show another app's photos and the user's real training; the
day name and the loads quoted in the original brief match his export. Neither is committed. Docs, fixtures, previews,
tests and PR bodies use synthetic values: day "Upper", loads such as 75 × 10 and 80 × 6. Reference screenshots stay
local, in the user's checkout, untracked.

## What changed since the brief was written

The brief predates #75 (replace, edit targets) and #77 (jump to next, pinned rest bar). `CLAUDE_FOLLOWUP_BETA_FEEDBACK_2`
landed, so the "supersedes" clause doesn't apply as written: this brief builds on that work.

## Lead decisions

| # | Decision | Why |
| --- | --- | --- |
| L1 | Focused reuses the #77 planner: `SessionAdvance` (and `nextUp`, `isAllDone`, the 0.6 s delay, the 3 s window, `AllSetsDoneCard`). `.advance(to:)` becomes a page change; `collapse` is ignored in Focused. | One definition of what's next. The brief's rules are the ones already in it. |
| L2 | "Rest card" means today's `RestBar`. `RestPill` replaces it in Focused; `RestBar` stays for List. `RestTimerView.swift` holds only `NumberPad` and `PlateCalculatorSheet` now; it stays. | The card the brief describes is gone. |
| L3 | The chips are live from PR 1: `⇄` opens the existing Replace sheet, reps `✎` opens Edit targets, Rest `✎` a rest sheet. | §1 landed; the display-only fallback isn't needed. |
| L4 | One setting. The existing toggle (`train.jumpToNext`) gets the brief's label ("Advance to the next exercise"). The key stays. | Same behaviour; a second toggle would be a bug, and anyone who turned it off stays off. |
| L5 | **Focused ships dark behind the remote flag `train.focused_session`**, and T5 is not a code flip. Flag off or absent: List, no picker, no change at all. Flag on: Focused by default, and Profile → Training → Session layout offers Focused / List. Flag off always means List, whatever was picked. The layout is read once when the controller is built, so a config refresh never changes a running session. Tests and shots force it through the app's existing flag override. | `CLAUDE.md`: an unfinished feature ships dark behind a remote flag. `main` stays releasable between PRs, turning it off is the rollback, and the iOS 17 run (L15) can happen before anyone sees it. Replaces my first version of this decision, a compiled default, after ios-architect's objection. |
| L6 | Warm-ups: the group starts folded. `activeSet` = the set the user tapped if it is open, else the first open warm-up **while the group is expanded**, else the first open working set. Folding the group changes which row is active but never any set's data. The group folds itself when its last warm-up is checked. | The brief contradicts itself: PR 2 says "warm-ups first while expanded", the test list says expanded/collapsed doesn't change the active set. PR 2 is the behaviour; the test becomes "folding changes no set". |
| L7 | The last-time card heads with the date only. The session's title is filed in `docs/API_REQUESTS.md`. | `PlanTarget.last_time` is `[Set]`: no title on the wire, nothing to invent. Date comes from `completed_at`, with a plain "Last time" when absent. |
| L8 | Tile glyphs come from `ExerciseKind`. | The brief's "muscle-group symbol set" doesn't exist (`Muscle` has titles only) and `LocalSessionExercise` has no muscles. `kind` is on the row, offline, custom and replaced exercises included. Designer may propose better. |
| L9 | "Snapshots" are `ImageRenderer` render tests and `make` shots, as the Orbit gauge did. | The only dependency allowed is `supabase-swift`. |
| L10 | The current page is stored as an exercise id, not an index, and never reaches the wire or `updatedAt`. Architect owns where. | Reorder, remove and replace move indices; a page swipe must not trigger an upload. |
| L11 | Accessibility is verified by ui-validator against ui-designer's checklist. | The brief names an `accessibility-reviewer`; the fleet has none. |
| L12 | The done-when session is Upper A. | The day the original brief named is not in the demo plan. |
| L13 | The RM column uses `E1RM.estimate` as it is, 12-rep cap included. `10RM = e1RM × 30 / 40`. | Same number as the platform's scoring; a 15-rep set reads as 12. |
| L14 | PRs are stacked; each targets the previous one until it merges. | The user merges, and every PR needs the one before. See the stacked-branch check after each squash. |
| L15 | The pager ships without an iOS 17 run; that run is a condition for turning the flag on. | `TabView(.page)` won the probe on iOS 27, but no iOS 17 runtime is on this Mac or in CI. |
| L16 | Focused has no swipe to delete on set rows. Delete stays in the row's context menu and the VoiceOver action. | Measured: inside a pager the row got 0 of 4 drags, and a gesture that wins kills page swipes and the vertical scroll. The feature stays; the gesture doesn't. |
| L17 | In Focused, ✓ on an active row that would log neither reps nor load opens the keypad on the first missing field (`checkRow`). List is unchanged. `toggleCheck` was unchanged here too; since the T5 follow-ups it logs a bodyweight row's added-load ghost in Focused. | An empty logged set helps nobody, and it can only happen without a plan target or history. A plan session stays one tap. |
| L18 | "All sets done" is "Alle Sätze geschafft" as the brief says, not the shipped "erledigt"; the one value changes for both layouts. | The user's copy wins; the designer's reason was consistency only. |
| L19 | T4 is the RM column only. The last-time table is in T1, and T1's fourth column is RPE until T4. | Design §7. |
| L20 | No T6: time and distance keep today's behaviour (a wide reps field, stored values read-only). Entry for them is not in this brief. | `SetFocus.Field` has no time or distance today, so parity holds. Noted as an open item. |
| L21 | Finish's capsule loses its fill in Focused until every set is done, in T5, checked on renders first. | Three filled teal controls otherwise (design §4). |
| L22 | Two wordings change with the flag off too: the German value of "All sets done" (L18, in T2) and the setting's label "Advance to the next exercise" (L4, in T5). Each PR that ships one names it in its body, and it gets a CHANGELOG line. | Copy only, it reveals nothing of the new layout, and holding them behind the flag means two keys for one meaning. "Nothing changes with the flag off" stays strict for layout and behaviour. Settles the conflict between the acceptance criterion and L4, L18. |
| L23 | VoiceOver's check on the active row follows L17 too: with nothing to log it opens the keypad instead of logging an empty set. | The brief's done-when: VoiceOver can do the same session. The ✓ and its VoiceOver action follow one rule. Replaces the architecture note's open point. Time and distance stay as L20 has them. |
| L24 | L17 holds on every open row in Focused, not only the active one: a set that would log nothing opens the keypad. A row with a value or a ghost still logs out of order in one tap. | The reason for L17, an empty logged set helps nobody, doesn't depend on which row it is. Asked by code-reviewer on T2. Time and distance stay as L20 has them. |

## Tickets

| # | Ticket | Owner | Branch / PR title | Depends on |
| --- | --- | --- | --- | --- |
| D1 | Design note: geometry, state table, tile legibility, copy, a11y checklist, PR 4 split call | ui-designer | `design.md`, in PR 1 | — |
| D2 | Architecture note: page state, active set, warm-up group state, focus across pages, paging container, rest start without a check | ios-architect | `architecture.md`, in PR 1 | — |
| C1 | `docs/API_REQUESTS.md`: the session title for `last_time` | api-contract-keeper | in PR 1 | — |
| T1 | Paged exercises, strip, page shell, chips, warm-up pill | ios-developer | `feat/focused-session-layout` · `train: focused session layout (paged exercises, exercise strip)` | D1, D2 |
| T2 | One active set, prefilled rows, auto-advance | ios-developer | `feat/focused-active-set` · `train: one active set, prefilled upcoming sets, auto-advance` | T1 |
| T3 | Rest pill | ios-developer | `feat/focused-rest-pill` · `train: the rest pill replaces the rest card` | T2 |
| T4 | RM column, `TrainMath` (L19) | ios-developer | `feat/focused-rm-column` · `train: last-time table and the RM column` | T2 |
| T5 | Polish, Profile picker, smoke replaced, TestFlight notes (the flag stays off) | ios-developer | `feat/focused-polish` · `train: focused session polish` | T2–T4 |
| Q1 | Tests from the acceptance criteria | test-engineer | inside each PR | D2 |
| L1 | de strings | localization-editor | inside each PR | each ticket |

UI tests and `set.<position>.<number>` identifiers: List keeps them; Focused rows reuse the same identifiers. The existing
UI tests run List unchanged until the flag is on by default for them in T5.

## Acceptance criteria

The brief's sections are the criteria, read with the decisions above. On top, for every PR:
- With the flag off nothing changes at all, for anyone, apart from the two wordings in L22.
- A page change writes nothing to the session's `updatedAt` and queues no upload.
- Strict build, zero warnings in our code, `make lint`, Unit plan green; Previews dark and light for every new view.
- Catalog diff in the tens of lines, no re-serialising, no attribution trailers or footers.

## Risks

- Page container: `TabView(.page)` keeps pages alive oddly and fights a nested `ScrollView`; insert and reorder shift its
  selection. Architect compares it with a paging `ScrollView` and `.scrollPosition(id:)`.
- The keypad across pages: focus on a set of a page you swipe away from; `focusBeforeReplace` and undo must land on the
  right page.
- The toast, `ManualScrollReporter` and VoiceOver focus were all built around one list.
- `nextLabel()` counts warm-ups in "set n of m" and offers them first, while the page's active set may skip a folded
  warm-up: the pill's "Next:" must name the row the user will see.
- `SwiftData`: any new stored attribute must open the shipped store (no versioned schema here); on-disk upgrade check.
- Time and distance exercises: the brief's table assumes kg and reps. Parity means their columns keep working.
