---
name: project-main130-into-pr6-merge
description: M6 (2026-11-20) — merging main's #130 (analytics phase 1) into PR 6; where the auto-merge misplaces, ConsentPoint vs area A's scan, the old OnboardingScreen API, a per-line checklist script
metadata:
  type: project
---

M6: `feat/nocturne-pr6-main130` (worktree scratchpad/wt-m6, scripts in scratchpad/m6) merged origin/main 4bc1800 (#130)
into PR 6 d2ab1fb. 8 conflicts, as the lead predicted.

**Why:** the analytics gate PR (phase 2) and any later main→PR 6 merge touch the same files.

**How to apply:**
- `git checkout --conflict=diff3 -- <files>` gives the base side; `m6/resolve.py` takes `ours`, `theirs`, `both`,
  `theirs+ours` and `ours+line:<substring>` (ours plus the theirs lines containing it) per hunk.
- The auto-merge put `.analyticsScreen(.journal)` on PR 6's loading placeholder in JournalViews (a conflict, luckily):
  #130's place is JournalSheet's NavigationStack. Any one-line modifier "after the last modifier of a body" can land in
  another struct when PR 6 rewrote the file.
- `SignedOutOnboardingTests.noTealNoOldControls` bans `Theme.accent` and `PrimaryButton(` in area A's files
  (OnboardingSteps.swift among them): #130's shared `ConsentPoint` (default `symbolColor = Theme.accent`) can't stay
  there. Moved verbatim to `Features/Profile/AnalyticsOptInSheet.swift`, its only user.
- PR 6 A replaced `OnboardingScreen(symbol:title:text:)` with `(title: Text, lead: Text, showsLockup:)` and spacing 0
  content. #130's sheet used the old API: a private `AnalyticsPromptFrame` (main's old layout) keeps its look until the
  gate PR restyles it.
- Checklist: `m6/checklist.py <wt>` (each #130 line matching `analytics\.track\(|\.analyticsScreen\(|analytics:|AnalyticsEvent`,
  175 lines, counted per file in main and in the merge) and `m6/cmp.py <wt>` (per-file +/- multisets of #130 vs the
  merge's delta from PR 6; "outside #130 files" must be empty). Equal multisets prove nothing of PR 6 was reverted, but
  not placement: read `git diff -U6 d2ab1fb -- <file>` for every file both sides touched.
- Catalog: compare key sets in Python (base/main/pr6/merged); #130 added 11 keys, 33 lines.
- Strict build of the merge: 0 warnings first time. `sh scripts/install-tools.sh` fetches the pinned tools into the
  worktree's `.build/tools` (no need to copy from another tree).
