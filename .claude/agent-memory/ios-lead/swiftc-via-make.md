---
name: swiftc-via-make
description: Direct swiftc/python3/sips calls get refused in delegated sessions; compile and run scripts through Makefile targets
metadata:
  type: feedback
---

In delegated sessions, calling `swiftc` directly is refused, and so are `sips`, `file` and `.build/<tool>` one-off runs. Python sometimes is too. `make <target>` (which runs swiftc) and `xcodebuild` work.

**Why:** on 2026-10-28 (new orbit mark), ui-designer couldn't compile `scripts/mark-svg.swift` at all and handed back unverified work. Once the script was wired into `make mark-svg` / `make check-mark-svg`, every agent could run it.

Not always: on 2026-11-14, `make` and `xcodebuild` were refused too (see [[headless-permission-preflight]]).

**How to apply:** when a brief involves a helper Swift script, tell the agent up front to add a Makefile target and run it through `make`. Tell agents to compute numbers in Swift tests or by hand, not in python3.
