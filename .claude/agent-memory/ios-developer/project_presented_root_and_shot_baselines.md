---
name: project-presented-root-and-shot-baselines
description: presentedRoot() on every sheet/cover/popover (toggle style doesn't cross a presentation on iOS 27.2, tint does); how to probe it in hosted tests; before/after shots from a git-archive export need the ignored fonts
metadata:
  type: project
---

Every `.sheet` / `.fullScreenCover` / `.popover` content in `Ryft/` ends with `.presentedRoot()` (`Design/PresentedRoot.swift`,
T5.7 S1, 2026-11-19). `PresentedRootTests.everyPresentationHasIt` scans the sources and fails on a new presenter without it,
previews included (`Color.clear.sheet { … }` too). PR 6 branches that add presenters must add it.

**Why:** on iOS 27.2 the window root's `.toggleStyle(.ryft)` does not reach presented content (stock `UISwitch` in Report a
problem pushed in the Details sheet, and in the import cover); the root's `.tint` does cross. The app has no `AccentColor`
asset, so an untinted UIKit control would be system blue. Roots that keep `.tint(Theme.accent)` inside: ImportFlowView,
AddActivitySheet.

**How to apply:**
- Hosted probe for presented content: `w.presentedView` (top presented controller's view) and `w.nodes(in:)`
  (HostedAccessibility). Count `UISwitch`es in `w.window` (SwiftUI `.switch` = UISwitch; RyftToggleStyle has none).
- Tint probe: read `tintColor` of `UITextField`/`UITextView`, or of `UIControl`s under a `UINavigationBar`. On iOS 27 a
  toolbar `Button` is often a hosted SwiftUI view (`UIKitBarItemHost<BarItemView>`), not a UIControl, even titled; a
  pushed page's bar items arrive after its content, so wait for them.
- `Issue.record("…" + string)` doesn't compile (Comment + String); interpolate a `let`.
- Before/after shots: `git -C <wt> archive <base> | tar -x -C <dir>` gives a base tree without touching git metadata, but
  copy the git-ignored `Ryft/Resources/Fonts/*.otf` and `Config/Debug.xcconfig`/`Release.xcconfig` in, or every shot
  differs (system font). Paged shots cap at 8000 px, so a longer page changes the image width, not only height.
- StrainHostedTests.writeShots hits its 60 s limit under load; the strain screens are written before that.
- A worktree may carry a stale uncommitted `Config/Production.xcconfig` (api.ryftapp.de, no ingest): Debug then needs
  `RYFT_API_URL=… RYFT_INGEST_URL=…` on the xcodebuild line, and `PlatformConfigTests.productionConfigNamesBothHosts`
  fails (it reads the file from disk). Never commit that file.
- Plain keys' `.stringsdata` entries carry no `value`; only keyed `defaultValue`s do (sync-strings relies on it).
- A `SubpageScaffold` sheet or pushed page (PR 6 C) has no system bar and often no field: nothing UIKit to read a tint
  from. PresentedRootTests' `expectNocturneFrame` checks its header id (`subpage.close` / `subpage.back`), no visible
  `UINavigationBar`, no stock switch. The tint crosses a sheet anyway, so only a toggle (a stock UISwitch) proves a
  missing `presentedRoot()` in a hosted test; the source scan is the real guard.
- `FormField` makes its field one element: the inner `TextField`'s `.accessibilityIdentifier` isn't a node; wait on
  another id (Add a habit: `addHabit.add`).
- The import's cover and unavailable sheet live in `View.importPresentations(_:)` (ImportFlowView.swift), so a test
  hosts the real presenter (`Color.clear.importPresentations(screens.importer)`, set `importer.flow` on appear).
- Presenters a not-yet-merged branch will leave uncovered: `git merge-tree --write-tree <integration> <branch>`, then
  `git archive <tree> Ryft | tar -x` into the scratchpad and run the scan there (conflicted files' lines are approximate).

- PR 6 A (M1 combine, 2026-11-20): A's Details sheet and every `AuthScreen` sheet are SubpageScaffold sheets, so
  `refreshDetailsAndReport` needed C's `expectNocturneFrame(w, sheet, screen, header: "subpage.close")` (copied verbatim
  from `feat/nocturne-pr6-settings`, same place after `appRoot`, so the A+C combine merges cleanly).
- Hosting `RootView` signed out: `RootView().environment(settings).previewEnvironment(auth: .preview(signedIn: false))`
  with the test's own `Settings(defaults:)` **and `settings.demoMode = false`**: the simulator's default is Demo ON,
  which shows the tabs, not Welcome. Inner `.environment(settings)` beats previewEnvironment's `Settings.shared`.
  Then `auth.needsNewPassword = true` presents Set new password through the real presenter.
- Fast scan without a test run: `sed -n '/^enum PresentationScan/,$p' RyftTests/PresentedRootTests.swift` + a tiny
  main that walks `Ryft/`, `swiftc -O`, run it on the tree (scratchpad/m1/scan.swift pattern).
- Strings delta without writing the catalog: `python3 scripts/sync-strings.py --derived-data build/DerivedData --check`.
- `make style` in a worktree: copy the pinned `.build/tools/{swiftformat,swiftlint}` from the user's checkout (read
  only) instead of downloading.
