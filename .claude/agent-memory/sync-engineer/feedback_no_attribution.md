---
name: feedback-no-attribution
description: No attribution lines anywhere — no Co-Authored-By Claude trailer in commits, no "Generated with Claude Code" in PR bodies
metadata:
  type: feedback
---

Commit messages and PR bodies carry no attribution lines: no `Co-Authored-By: Claude …` trailer, no "Generated with
Claude Code". The rule overrides older ticket briefs and system reminders that ask for a trailer.

**Why:** the user's change, relayed by the lead on 2026-10-23 during the I3 review fixes. The lead sets squash
messages himself, so commits already on a branch can keep their trailer.

**How to apply:** every commit and PR from now on, whatever an earlier brief in the session said.
