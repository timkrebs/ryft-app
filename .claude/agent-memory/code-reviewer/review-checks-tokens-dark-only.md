---
name: review-checks-tokens-dark-only
description: RYFT review checks for design-token / dark-only / font / icon PRs and colorset deletions (Nocturne PR 1 2026-11-16, gate part 2 2026-11-21) - Info.plist names deleted colorsets, global accent via project xcconfig, ADRs frozen mid-branch, dropped scheme asserts, tracking exposed, CI fetches fonts, tautological icon checks
metadata:
  type: feedback
---

Found in the Nocturne PR 1 review (2026-11-16); the token values and WCAG math were all right:
- **Docs written mid-branch.** A late commit (opaque `SurfaceRaised`) fixed the ADR's "Open" items and reverted test
  composites, but the ADR still said "one open item" and "tests composite the track". `git show --stat` each late commit
  and re-check every ADR sentence about tests against HEAD's test code, not the design note.
- **Removing a scheme loop.** Dropping `.light` from a loop can drop a scheme-only `#expect` (pending at 0.6 "< 3:1").
  Recompute it in the remaining scheme: dark had the same sub-3:1 case, so the assert had an equivalent.
- **Removing tracking/case from a shared style** (`ryftLabelStyle`) exposes call-site `.tracking(n)` that the inner
  modifier used to beat (WelcomeView went to 3 pt tracking on sentence case). Grep `.tracking(` after the style.
- **CI fetches Satoshi**: `.github/actions/setup/action.yml` runs `make fonts` for the test and TestFlight jobs; only
  the Lint job has no fonts. Correct "CI has no fonts" claims. The no-font fallback `.system(textStyle)` ignores role sizes.
- **Weight rules by size** (`ryftNumber` Light >= 20 pt): list callers by size; doc claims like "set inputs stay
  Regular" were false (kg/reps fields 20-30 pt went Light, RPE 17 pt stayed Regular).
- **Icon renderers:** a centring guard computed from the same metrics that placed the ink is tautological. Measure the
  committed PNG instead: `python3 -I` zlib PNG decoder in the scratchpad, bbox of pixels != tile colour.
- Stale-doc sweep for appearance/icon changes: README fonts + icon sections, README hero light screenshots,
  `.github/pull_request_template.md` "dark and light", `docs/CHART_STYLE.md` preview rule.

**Why:** each looked fine in its own section; only cross-reading HEAD caught them. **How to apply:** any PR that changes
colour sets, appearance, Typography or the icon. See [[review-checks-design-notes]], [[review-checks-shared-widget-gauges]].

Colorset deletions (gate part 2, 2026-11-21, `feat/nocturne-gate-2`): the Swift compiler and `check-accent-use.py` (Swift
only) passed, but `Ryft/Info.plist` `UILaunchScreen.UIColorName` still named the deleted `Graphite`. For any colorset
deletion: `git grep` the names in `*.plist`, `*.pbxproj`, `*.storyboard`, `*.json`, `*.xcconfig`, then compare the built
`Assets.car` (`xcrun --sdk iphonesimulator assetutil --info <app>/Assets.car`, AssetType Color) with the built Info.plist.
The implementer's DerivedData is usually `<worktree>/build/DerivedData`. `DarkOnlyTests` only checks UIUserInterfaceStyle.
Global accent: `Config/Production.xcconfig` is included by Debug/Release.xcconfig, the *project-level* base configs, so a
setting there reaches every target (app, widget, tests); `plutil -extract NSAccentColorName raw <built Info.plist>` proves it.
`check-shared-types.py` requires identical Contents.json for a colorset present in both catalogs (why the widget's
AccentColor had to change too).
