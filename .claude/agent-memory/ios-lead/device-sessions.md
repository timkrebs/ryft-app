---
name: device-sessions
description: Rules for running checks on the user's own iPhone (devicectl install, launch, screenshots) without intruding on his private use
metadata:
  type: feedback
---

The user sometimes connects his personal iPhone so checks can run on a real device before CI. Find it with
`xcrun devicectl list devices` (Reality: physical). Don't write its identifiers into the repo.

**Rules:**
- Start a device session only after he says the phone is free. "I connected my iPhone" isn't that.
- Before every screenshot (`devicectl device capture screenshot`):
  - RYFT must be the foreground app: launch it in the same step and check that the launch succeeded;
  - never capture after a failed launch.
- **Calls:** another app can still be on screen, e.g. a call in picture-in-picture. Check
  `devicectl device info processes` for call services and ask if they're present. They can also idle without a call.
- If a capture shows anything that isn't RYFT, delete it at once, don't describe it, and tell him.
- A successful launch doesn't prove RYFT is on screen. The display can be off or locked, or another app can be in front.
  - Check the capture's pixel size before opening it: RYFT is portrait-only (1206×2622 on his iPhone 16 Pro).
  - A landscape size means delete it unopened (2026-10-23: a `--payload-url` launch captured a black landscape screen).
- **Notifications:** another app's notification banner can land in any capture (2026-10-26: a messenger banner over
  My Day). Before the first screenshot, ask him to turn on Do Not Disturb or a Focus for the session. If a banner
  slips through, delete that capture and any taken in the same batch without opening them.
- App arguments go after `--`:
  `devicectl device process launch --device <id> --terminate-existing dev.timkrebs.ryft -- -RyftFlags devices.setup …`.
- Use Debug launch arguments (`-RyftFlags`, `-RyftTrackers`, `-RyftScreen`) that never persist to his account.
- Relaunch RYFT without arguments at the end.

**Why:** in the first session (2026-10-22), two screenshots caught non-RYFT content: one taken after a failed launch, one
through picture-in-picture. Both were deleted at once.

**How to apply:** any work on a physical device. See [[parallel-worktrees]] for builds.
