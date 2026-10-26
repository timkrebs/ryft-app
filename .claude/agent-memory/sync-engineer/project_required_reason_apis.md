---
name: project-required-reason-apis
description: RYFT's privacy manifest declares only UserDefaults (CA92.1); file timestamps, boot time, disk space are off-limits; how to prove it with nm
metadata:
  type: project
---

`Ryft/PrivacyInfo.xcprivacy` declares only `UserDefaults` (CA92.1), and `docs/APP_STORE.md` (§1) claims "No file
timestamps, boot time, disk space or keyboards". Using one undeclared makes `main` unreleasable (ITMS-91053).

**Why:** on 2026-10-23 the privacy re-check of O1 made an mtime cutoff in the export sweep
(`attributesOfItem(...)[.modificationDate]`) a must-fix before merge; it became an in-process set of written paths.

**How to apply:** never `.modificationDate`/`.creationDate`, `contentModificationDateKey`/`creationDateKey`,
`stat`/`lstat`/`fstat`/`getattrlist`, `systemUptime`-style boot time or volume-capacity keys in app or widget code; decide
by names, sets or markers instead. `attributesOfItem` for `.size`/`.type` and `fileResourceIdentifierKey` aren't listed.
Proof on a build: `nm -u <App>.app/Ryft.debug.dylib | grep -E '_NSFileModificationDate|_NSFileCreationDate|DateKey|^_l?stat|^_fstat|getattrlist'`
(empty) — the same command shows `_NSFileSize` when that key is used, so it does see attribute keys.
Related: [[project-swiftdata-group-container]].
