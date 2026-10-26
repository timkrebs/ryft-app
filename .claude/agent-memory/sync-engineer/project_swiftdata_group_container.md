---
name: project-swiftdata-group-container
description: SwiftData .automatic copies an app-container store into an empty App Group container on open; how to test store/entitlement behaviour and read launch signposts on a simulator
metadata:
  type: project
---

Seen 2026-10-23 (O1, orphaned `Train.store`, commit fcd3695 on `fix/orphaned-store`):

- **SwiftData migrates by copy.** With `groupContainer: .automatic` and the App Group entitlement, opening a store
  whose group file doesn't exist yet copies the app container's `Library/Application Support/<name>.store` (+ wal)
  into the group (md5-identical), and leaves the source in place. That is how the pre-App-Group store became the
  orphan on the user's iPhone, and why a left-over copy can come back if the group's files vanish.
  **How to apply:** any cleanup of an old store path runs *after* `TrainStore` opened, never before (an upgrader's
  data would be lost); a future `groupContainer: .none` move must handle the old path first (comment in `TrainStore.init`).
- **Entitlements on the simulator.** `CODE_SIGNING_ALLOWED=NO` (CI, test host) embeds no entitlements: the App Group
  doesn't resolve and SwiftData puts the store in the app container. A plain `xcodebuild build` (no that flag) signs
  "to Run Locally" with a `__TEXT,__entitlements` section incl. the group (`otool -s __TEXT __entitlements`).
  Installing an unsigned build in between makes the simulator drop the group container; the next signed install
  gets a new, empty one (and SwiftData then copies whatever is in the app container into it).
- **Launch numbers without Instruments.** `xcrun simctl spawn <udid> log show --start "<t>" --info --signpost
  --predicate 'subsystem == "dev.timkrebs.ryft"'` lists OSSignposter intervals with thread ids; demo mode
  (`-demoMode YES`) ends the `launch` interval on Today. Cold launch (Debug, iPhone 18 Pro sim) was ~470–590 ms.

- **`cloudKitDatabase: .none` is open-compatible.** A store written with the default (`.automatic`, persistent history
  tables present) opens with `.none` on the simulator: no read-only warning, writes go through (O1 review, 2026-10-23).
- **External storage and batch deletes** (I5 review, 2026-10-26): `PendingImport.payload` is `.externalStorage`
  (files in `.<store>_SUPPORT/_EXTERNAL_DATA/` beside the store). On the iOS 27 simulator both `context.delete(model:)`
  and deleting objects one by one removed the file at `save()` (probe: 0 files immediately). The wipe deletes jobs one
  by one anyway (iOS 17 target). Test on disk with `TrainStore(url:)` in a temp folder, never the app's own store.
- **Flaky Unit test seen:** `SyncSeamTests/drainsEveryStreamAndCommitsAfterUpload` failed once in the full plan (passed on
  rerun); it asserts `Settings.shared.lastSync`, which parallel syncs in other tests also write.

Related: [[project-unsigned-host-and-simulators]], [[project-simulator-and-tools]].
