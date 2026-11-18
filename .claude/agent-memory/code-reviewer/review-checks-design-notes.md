---
name: review-checks-design-notes
description: Checks for reviewing plan/design/architecture notes before code exists - "only site" claims, token swaps that differ in dark, ticket order, Shared visibility
metadata:
  type: feedback
---

When reviewing notes rather than code, test each claim against the source. These missed in authors' own checks (a light-appearance design note, 2026-11-06).

- "It is the only such site": grep it. A rule proven for one site (inner `.tracking` beats outer) also hit `Wordmark`, which the same note's sample code kept in the broken form.
- "Light only" token swaps: compare the replacement's dark value, not just light. `separator` to `surfaceRaised` looks light-only and moves dark. Copy changes "used in both appearances" and new rows in shared sections (About) move dark too.
- Ticket order: a pin test listed in an early ticket can't name types or files from later tickets. Check it compiles at that ticket.
- New type in `Ryft/` used from `Shared/`: the widget can't see it (ADR 0010: no app types).
- When a plan moves tickets to another base branch, grep the notes for "on the branch" and "stays red": they keep the old assumption.
- Recompute derived pair ratios too, not only headline figures: grey-to-grey ratios were the wrong ones.
- `origin/<branch>` can lag a worktree's local merge: compare `git rev-parse HEAD` and `git ls-remote`.
- A plan that lists the failing pins to fix: also grep the green tests that pin the code it changes. A hatch and a pending-colour change turned 5 unlisted green render tests red (2026-11-06). Check interim pins in the appearance that isn't moving.

**Why:** the notes were written separately and before the decisions, and each author's numbers were checked only against their own section.
**How to apply:** on any notes review, do these before the agreement pass. In zsh, `echo ===` is an error that stops a chained script, so use quoted separators.
