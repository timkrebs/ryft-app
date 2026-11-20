---
name: review-checks-deployment-target
description: RYFT review checks for minimum-iOS bumps and Info.plist build settings (INFOPLIST_KEY_* inert without GENERATE_INFOPLIST_FILE, OS switch tables, Xcode-version claims)
metadata:
  type: feedback
---

From the iOS 18.6 minimum review (PR #122, ADR 0021, 2026-11-18); nothing blocked.

- **INFOPLIST_KEY_* on the Ryft app target is inert:** `GENERATE_INFOPLIST_FILE` resolves to NO there (it uses
  `Ryft/Info.plist`), so build-setting keys never reach the bundle (`LSApplicationCategoryType` too). Probed with a
  two-target scratch project: unset → the file's value; YES → the build setting *overrides* the file's value. At
  runtime `Ryft/Resources/InfoPlist.xcstrings` (en) overrides both for `CFBundleDisplayName`. The widget target does
  generate (YES). Check with `xcodebuild -project Ryft.xcodeproj -target <t> -showBuildSettings | grep GENERATE_INFOPLIST`.
- **Grep beyond `#available`:** tests switch on `ProcessInfo.operatingSystemVersion` (`ReadModelContextFactsTests`
  `TwoContainers.Runtime.current`, `(17, 0)` arm); a bump leaves those arms dead and new measurements unrecorded.
  Observation tests that assert only on one OS and print nothing can't "measure" anything on another runtime.
- **"Xcode N or newer" claims:** check `@available(iOS x.y, *)` SDK APIs used behind `#available` (the SDK must have
  them): `AlarmPresentation.Alert(title:secondaryButton:…)` is iOS 26.1, so Xcode 26.0 can't build the app.
- **Probes:** `swiftc -typecheck -application-extension -target arm64-apple-iosX-simulator RyftWidgets/*.swift Shared/**`
  (without `-application-extension`, `iOSApplicationExtension` checks don't refine). Swift never warns about a check
  made redundant by the deployment target, only inside an enclosing `@available` scope.

**Why:** these were the non-obvious parts; the pbxproj diff itself was clean and identical to the user's Xcode edit.
**How to apply:** any deployment-target, display-name or Info.plist PR. See [[review-checks-merges-and-wiring]].
