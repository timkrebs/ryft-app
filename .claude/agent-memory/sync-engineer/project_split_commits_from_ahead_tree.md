---
name: project-split-commits-from-ahead-tree
description: Committing a brief's ordered commits (a)–(f) when the tree already holds later ones — per-stage file writer, stash --keep-index to build exactly the index, pop by sha
metadata:
  type: project
---

Briefs give a commit order (design.md §12: (a) seam, (b) plans, (c) scheduler, (d) bedtime, (e) presentation, (f)
docs), and each commit must build. Work often runs ahead: (d)/(e) edits sit in files (c) also changed. What worked
(N3, 2026-11-22):

- Copy the full versions of the shared files to the scratchpad first. A small python "stage" script then writes each
  shared file as it is at stage c, d or e: it undoes the later hunks by exact-text replacement (each `assert count == 1`)
  or splices a block back from `git show HEAD:<file>`. Never `git checkout` a file to get back to an earlier state.
- `git add` only that commit's files, then `git stash push --keep-index --include-untracked`. The tree now equals the
  index, so `build-for-testing` plus the stage's suites test exactly what gets committed. Commit, then
  `git stash pop --index <ref>`, where `<ref>` is found by the sha saved at push time: other sessions' stashes share
  the list. `cmp` the restored files against the backups.
- A test-without-building run started before later edits still tests the earlier build products, which is useful for the
  big Unit run on the first stage.
- Existing tests that pin a count or a set (here, the registered categories in two places in
  `PushAndDeepLinkTests`) fail in the stage that adds to it, so run the neighbouring suites per stage, not only the
  new ones.

**Why:** a later stage's symbols (`PushPresentation`) are already used by files the earlier stage commits. Building
the tree as it stands instead of the index commits a broken (c).
**How to apply:** any brief with an ordered commit list where the tree is ahead of HEAD. Related:
[[project-mutation-runner]] (commit first, then mutate).
