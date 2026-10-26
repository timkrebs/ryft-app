---
name: reference-sf-symbol-availability
description: Where to look up which iOS release introduced an SF Symbol (the app targets iOS 17, simulators run iOS 27)
metadata:
  type: reference
---

`/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist` (on the Mac, and inside
the simulator runtime the unit-test process sees): `symbols` maps a name to a year ("2022"), `year_to_release` maps
the year to `{"iOS": "16.0", …}`. Read it with `plistlib` (dotted symbol names break `plutil -extract`).

`UIImage(systemName:)` on a simulator only proves the symbol exists on the simulator's iOS (27), not on the
deployment target (17.0). `SportCatalogTests.everySymbolExistsOnIOS17` reads this table at test time (found via
`Bundle(identifier: "com.apple.CoreGlyphs")` / `SIMULATOR_ROOT`; it ran, not skipped, on 2026-10-23).
Example catch: `figure.run.treadmill` and `figure.outdoor.rowing` are iOS 18.

**How to apply:** before choosing or reviewing any SF Symbol name in app code ([[project-simulator-and-tools]]).
