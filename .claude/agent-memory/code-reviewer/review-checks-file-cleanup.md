---
name: review-checks-file-cleanup
description: RYFT review checks for code that deletes files (old stores, exports): independent guard layers, untested failure/marker branches, simulator limits, share sheet timing
metadata:
  type: feedback
---

File-deletion guards (O1 orphaned-store review, 2026-10-23):
- A "by identity on disk" backstop built on `URL.resourceValues(.fileResourceIdentifierKey)` does **not** follow a symlink
  at the last component. Mutate the path layer away (drop `resolvingSymlinksInPath`) and see if the identity layer still
  holds; in O1 it didn't (live store deleted through a linked folder). Fix: resolve symlinks before reading the identifier.
- Mutate the "done marker" condition (`finished` ignoring failures): a failed removal that still sets the marker makes the
  leak permanent. A read-only folder (`posixPermissions 0o555`) makes `removeItem` fail inside the simulator test host.
- Case-respelled paths can't be tested on the simulator: the sandbox resolves paths case-sensitively (`fileExists` on a
  case variant is false) although the host APFS ignores case. Use an injected identity seam instead.

Share sheet (iOS 26 simulator probe): cancelling Save to Files returns to the still-open share sheet and does not fire
`completionWithItemsHandler`; Save fires it after the save. The Save-to-Files extension copies the item into its own tmp
(`NSIRD_SaveToFiles_*`) at selection, so the app deleting the original afterwards is safe, and those copies outlive any
app-side cleanup (don't let CHANGELOG claim "everything is cleared"). AirDrop: device only.

Tooling: xcodebuild can hang after a failing Swift Testing run; wrap runs in a watchdog that kills it after "Test run
with N tests". `-retry-tests-on-failure` takes no value; `-test-iterations 1` is rejected. App defaults on a simulator:
`simctl spawn <udid> defaults read <data container>/Library/Preferences/<bundle id> <key>` (not the bare domain).

Re-review (e7246de, 2026-10-23):
- SwiftData keeps persistent history on (`ATRANSACTION`/`ACHANGE` tables) even with `cloudKitDatabase: .automatic` and no
  iCloud entitlement; pinning `.none` doesn't flip it. Upgrade test on the simulator: install the old signed build, launch,
  install the new one over it, launch: `ATRANSACTION` kept growing and Core Data logged no read-only warning.
- Account-binding guards (`AccountBinding.isCurrent` before writing the export): mutate the *error* branch too. Removing it
  survived, so the next account could see the previous account's export error.
- "Mach error -308 (ipc/mig) server died" while launching the test runner is the simulator, not the mutant: boot it again
  and rerun before counting a result.

**Why:** none of these showed up in the implementer's 18 green tests; mutations and a UI probe found them.
**How to apply:** for any delete-at-launch or temp-file change, run the layer-removal and marker mutations first. See
[[review-checks-merges-and-wiring]] and the sync-engineer note [[project-swiftdata-group-container]].
