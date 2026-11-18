---
name: reference-sf-symbol-availability
description: Where to look up which iOS release introduced an SF Symbol (the app targets iOS 18.6, simulators run iOS 27)
metadata:
  type: reference
---

`/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist` (on the Mac, and inside
the simulator runtime the unit-test process sees): `symbols` maps a name to a year ("2022"), `year_to_release` maps
the year to `{"iOS": "16.0", …}`. Read it with `plistlib` (dotted symbol names break `plutil -extract`).

`UIImage(systemName:)` on a simulator only proves the symbol exists on the simulator's iOS (27), not on the
deployment target (18.6). `SportCatalogTests.everySymbolExistsOnTheDeploymentTarget` reads this table at test time
(found via `Bundle(identifier: "com.apple.CoreGlyphs")` / `SIMULATOR_ROOT`; it ran, not skipped, on 2026-10-23).
`figure.run.treadmill` and `figure.outdoor.rowing` were the example catch: both are iOS 18.0, allowed since ADR 0021; a
catch now is an iOS 26+ symbol.

**How to apply:** before choosing or reviewing any SF Symbol name in app code ([[project-simulator-and-tools]]).
