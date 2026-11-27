---
name: project-launch-ab-on-shared-mac
description: Launch before/after numbers on the shared Mac drift with load between passes; use procstart->init as the control, run passes in both orders, and attribute with traces
metadata:
  type: project
---

What happened during P1 (read-model writes off main, 2026-11-17, PR 3's harness on my own iPhone 17 Pro iOS 27.2 sim):

- **The absolute numbers drift a lot.** main's init→first-screen came out at 728 ms, then 639 ms in a second pass the
  same morning. PR 3 measured 442 ms. The load average fell from 115 to 15 while I was measuring.
- **A pass that runs before and then after can show a false regression.** Pass 2 showed the branch +65 ms (skip) and
  +119 ms (play). But `procstart->init` moved +130 ms too, CI [+10, +242], and no app code runs in that stretch. The
  traces settled it: main-thread samples before first-screen were equal (≈ 740 per launch) and so were the
  persistence frames.
- **The skip variant has no `.active` signpost.** Anchor AC windows on `first-screen` (the `launch` category).
- **What's left in 0–0.3 s after first-screen is not persistence.** After P1 the longest gap there (100–127 ms, about
  190–315 ms after the anchor) is the Today and MyDay SwiftUI render after the first commit, plus about 15–19 samples
  of `publishWidget` inside `committed`. P2 removes only the widget part, so AC3's ≤ 90 ms target needs the Today
  render follow-up as well.

**Why:** AC5 gates every PR at "+10 ms". On this machine, the drift between two passes is larger than that.

**How to apply:**
- Run passes in both orders (A then B, B then A) and report each one.
- Check `procstart->init` as the load control.
- Back any launch claim with trace sample counts before first-screen.
- Never compare against an older session's baseline.

Related: [[project-simctl-spawn-harness]], [[project-dev-machine-disk]].
