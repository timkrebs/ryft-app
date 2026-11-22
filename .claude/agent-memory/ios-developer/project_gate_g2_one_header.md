---
name: Gate G2 part 2: one header
description: D4/DG-6 in SubpageScaffold (pinned SheetHeader on sheet roots, PushedHeader row on pages), SubpageHeader deleted, test and run pitfalls
type: project
---
G2 part 2 (2026-11-21, feat/nocturne-gate-g2 85061c2..cd8b1ef): one header everywhere but the tab roots.

- `SubpageScaffold`: `.close` → `SheetHeader` pinned above the ScrollView (VStack, 26 top when `isSheet`, id
  `subpage.close`); `.back` / `.backAndClose` → `PushedHeader(identifierPrefix: "subpage")` as the scroll's first row
  (`subpage.back`, `subpage.header`); `.none` → `SheetHeader(...).closeHidden()`. `SubpageSpec.titleGap` is gone,
  `identifierPrefix` added. Back/Close labels now `CircleButton.backLabel` / `.closeLabel`.
- `PushedHeader` below AX1 is `SheetHeaderLayout(minTitleWidth: 0)` (title centred whatever the slots), not
  `ScreenHeader` three-slot; from AX1 unchanged (stacked).
- The import's steps 2–5 draw `PushedHeader` + xmark directly (not the scaffold), steps 1 and 6 `SheetHeader`
  (Close leading); its header still scrolls with the step rule. So `SubpageNavigation.backAndClose` has no production
  caller left (only tests/previews).
- WorkoutDetailView's hand-drawn row → `PushedHeader(prefix "workout")`; SleepView's header is the tab root's, kept.

**Why:** the user decided one header (D4 for sheets, DG-6 for pushed pages).

**How to apply / pitfalls:**
- A `PushedHeader` title is one element (`children: .ignore`): XCUITest can't find it as `staticTexts[title]`; use
  `descendants(matching: .any).matching(identifier: "subpage.header")` + label predicate.
- Hosted windows have a 62 pt top safe area (status bar): measure from `w.host.view.safeAreaInsets.top`.
- A 44 pt box on a fractional origin measures 43.99999999999997: `>= 44` checks need `- 0.5` slack.
- zsh doesn't word-split `$VAR` into several `-only-testing:` args: use a bash wrapper (`scratchpad/g2/suites.sh`).
- `until grep rc= log` matches a stale log from an earlier run with the same name: use fresh names.
- Mutants in one group can mask each other (a "no stacking" mutant hidden by one that removes the header): put
  each mutant whose only killer overlaps another's in its own group; include the `…HostedTests` suite, not only
  the spec suite of the same file.
- `@Test` display names must be single string literals (no `+`).
