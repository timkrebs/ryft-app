---
name: project-ax-layouts-and-mutation-runs
description: The shared components' accessibility-size layouts (C §2.9, 6c9 N7) and how to prove a layout test with a scripted mutation run
metadata:
  type: project
---

From AX1 (`typeSize.isAccessibilitySize`) the shared pieces stack on their own, so pages need no per-page fix (6c9 N7,
2026-11-19):
- `SubpageHeader`: always `stacked` (buttons' row, then the title), not only when `ViewThatFits` says the row is too
  narrow; reading order then is Back, trailing, title (on one row it is Back, title, trailing).
- `InlineMessage`: glyph above the sentence (`InlineMessageSpec.glyphGapAbove` 6), sentence from the card's inset.
- `GroupedRowValue` takes an alignment; under its title it is `.leading` (its own `.trailing` used to win over the
  label's, centring-looking wraps in Sync details).
- Report a problem: the pinned bar's caption and footnote end the page; the bar keeps only Send.

**Why:** a short title passes `ViewThatFits` at AX3 and stayed squeezed between Back and +; the lead's review flagged
Journal, Notifications, Licences, Sync details, Import 2 and 3.

**How to apply:**
- A test of text alignment can read pixels: render the window (`drawHierarchy`), and per band of lit rows inside the
  row's frame take the leftmost lit x (`NocturneStructuresHostedTests.lineStarts`). Use a value without descenders.
- Prove a new layout test by a mutation run: a scratch script (`6c9/mut/mutate.py`) copies each file to `mut/orig`,
  undoes the fix, then build + run the suites + `restore.sh` in one background command. Mutate with a value that
  can't warn under strict builds (`typeSize > .accessibility5`, not `if false`). Anchor replacements on unique text:
  `"                }\n"` also matches inside a deeper-indented line, and `let layout = typeSize.isAccessibilitySize`
  occurs 4 times in StatusViews.
- A check that passes under its mutant proves nothing: drop it (6c9 dropped a "bar under 30 %" check).
- "Nothing teal on this page" as a test: render the window at 1x and count pixels within 0.15 (sum of |dr|+|dg|+|db|) of
  `Theme.teal`/`accent`/`recovery`, with a teal swatch first as the probe's own control
  (`ProfileSubpagesHostedTests.reportDrawsNoTeal`). The source scan (`noTeal`) catches tokens; this catches what renders.
- A paged shot (`PagedWindowShot`) redraws a pinned bar on every page and leaves seams; crop with scratchpad `crop`
  (`crop IN OUT Y HEIGHT`) before comparing, and don't read the repeats as app bugs.
- Staging by hunk without `git add -p`: build a patch from `git diff -U3` hunks and `git apply --cached`. With `-U1` and
  `--recount` a hunk whose context is only `}` / `    }` lands at the wrong function's end (6c9 put a test block into the
  next test). After splitting, check each later whole-file commit shows only its own topic, and compare `HEAD^{tree}`
  before and after any `--autosquash` (`GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash <base>`, local commits only).
