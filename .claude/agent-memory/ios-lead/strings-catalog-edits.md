---
name: strings-catalog-edits
description: Briefs that touch Localizable.xcstrings must forbid re-serialising the catalog and require a small diff; check every strings commit's --stat and trailer
metadata:
  type: feedback
---

Every brief that lets an agent edit `Ryft/Resources/Localizable.xcstrings` says:
- Keep Xcode's formatting (`"key" : value`, the same key order).
- Never `json.dump` the whole file. Make targeted edits, or use the repo's `scripts/sync-strings.py`.
- Don't add source-language (`en`) entries.
- The `git diff --stat` for the catalog stays in the tens of lines.
- Commits carry no attribution trailer or footer (see [[no-attribution-lines]]).

After every strings commit, check two things:
- `git show <sha> --stat`;
- a semantic diff of the catalog JSON between the parent and the commit (keys added, removed or changed).

**Why:** on 2026-10-23, localization-editor re-serialised the whole catalog with `": "` separators. That was 18,530 changed lines for a change that only added redundant `en` "new" entries. Every parallel branch that adds strings would have conflicted. The commit also carried a model trailer, which the user has since ruled out entirely. I restored the file from the parent (9d4dd87 on `fix/honest-calibration`).

**How to apply:**
- any localization-editor brief, and any agent allowed to touch the catalog;
- at squash-merge time, set the PR body explicitly, so a trailer in a branch commit doesn't land on `main`.

See [[integration-branch]] for merging catalogs across PRs.
