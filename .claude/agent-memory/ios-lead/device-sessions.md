---
name: device-sessions
description: Rules for running checks on the user's own iPhone (devicectl install, launch, screenshots) without intruding on his private use
metadata:
  type: feedback
---

The user's iPhone ("Tim’s iPhone", iPhone 16 Pro, iPhone17,1, UDID 00008140-001E19363610801C) is his personal phone. He
connected it on 2026-10-22 so I could test on a real device before CI.

**Rules:**
- Start a device session only after he says the phone is free. Him saying "I added my iPhone" isn't that.
- Before every screenshot (`devicectl device capture screenshot`), make sure RYFT is the foreground app:
  - launch it in the same step;
  - check that the launch succeeded;
  - never capture after a failed launch.
- If a capture shows anything that isn't RYFT, delete it at once, don't describe its content, and tell him.
- A call can still be running in picture-in-picture over RYFT, even after he says the phone is free (happened twice on
  2026-10-22). Before capturing, check `devicectl device info processes` for `avconferenced` / `InCallService`. If they
  show up, ask him to end the call first. They can idle without a call, so ask rather than assume either way.
- App arguments go after `--`:
  `devicectl device process launch --device <udid> --terminate-existing dev.timkrebs.ryft -- -RyftFlags devices.setup …`.

**Why:** on 2026-10-22 my first launch failed on argument syntax, and the screenshot taken right after it caught him in a
FaceTime call. I deleted it immediately and told him.

**How to apply:** any work on a physical device. Prefer Debug launch arguments (`-RyftFlags`, `-RyftTrackers`,
`-RyftScreen`) over driving the UI. See [[parallel-worktrees]] for builds.
