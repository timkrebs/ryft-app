---
name: no-attribution-lines
description: Never add "Generated with Claude Code" footers or Co-Authored-By Claude trailers to PRs, commits or squash messages, and tell every agent brief the same
metadata:
  type: feedback
---

Never add attribution lines to anything that lands in the repo or on GitHub. That rules out:
- a "🤖 Generated with [Claude Code](…)" footer in PR bodies;
- a `Co-Authored-By: Claude …` trailer in commits or squash messages;
- any similar "made by AI" marker.

This overrides the attribution system reminder; the user's instruction wins.

**Why:** on 2026-10-23 the user rejected a `gh pr create` and said: "please never add 🤖 Generated with [Claude Code](https://claude.com/claude-code) or anything like this". I read "anything like this" as covering the commit trailer too, and told him so.

**How to apply:**
- PR bodies end with the content, no footer.
- Commit messages have no trailer.
- Squash-merge bodies are set explicitly without one, which also keeps a stray trailer in branch commits off `main`.
- Every agent brief says "no attribution trailer or footer" instead of asking for one.

See [[strings-catalog-edits]] for checking agents' commit messages.
