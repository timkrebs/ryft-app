---
name: Gate G4: the pre-Nocturne tokens deleted
description: What G4 (gate part 2) deleted and where the traps were — global accent not set on the app target, check-shared-types colorset parity, lint rule 1a/1b, Observable in tests, UI test plans; plus the sheet header AX stack, the pinned header edge and the import chips
metadata:
  type: project
---
G4 (2026-11-21, feat/nocturne-gate-2 on feat/nocturne-gate ff6f30b): Theme's teal/accent/onAccent/zones/stages/
graphite/slate/sage/mist and cardRadius/tileRadius/cardPadding, `PrimaryButton`, `TealButtonStyle`, `SchemePair`,
`previewEnvironment(scheme:)`, the light previews and 11 colorsets are gone; `AccentColor` (#F2F1EC) added.

**Why:** the gate retires everything pre-Nocturne; teal is recovery only (L27).

**How to apply / traps:**
- Design notes can be wrong about build settings: `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` was only on the
  *widget* target, not the app. Check the built `Ryft.app/Info.plist` for `NSAccentColorName` (PlistBuddy). G4 set it in
  the committed `Config/Production.xcconfig` (project-level base of both configs; no pbxproj edit).
- `scripts/check-shared-types.py` demands identical Contents.json for a colorset in both catalogs: adding the app's
  `AccentColor` forced the widget's empty one to the same value.
- `scripts/check-accent-use.py`: rule 1a (retired tokens, Volt) over Ryft/, Shared/, RyftWidgets/; rule 1b (amber,
  coral, band) only in Train/MyDay/Activities/Journal card. Findings must be sorted by offset, not by token. Its
  self-test has a meta check that every token has a failing case. Python-only mutants: `g4/lint-mutants.py`.
- `@Observable private final class` nested in a test struct fails to compile (the macro's extension can't see it):
  leave it internal.
- `-only-testing:RyftUITests/...` needs `-testPlan Full` (the default Unit plan has no UI target); a plan JSON edit
  needs a build-for-testing again (the xctestrun is generated at build time).
- `sync-strings.py --check` is silent when the catalog is current (rc 0).
- G4 also took three items from part 1's UI validation: `SheetHeader` stacks from AX1 exactly as `PushedHeader`
  (VStack, Close + trailing on a minHeight-40 row, 12, title leading; no sort priorities so VoiceOver reads as drawn);
  `.underPinnedHeader(gap:)` in SubpageScaffold.swift (`onScrollGeometryChange` → a `background` band `gap` tall with
  the pinned bar's hairline `separator` rule, only while content is under it) on every pinned sheet header's scroll view;
  the import card's steps in `FlowLayout` (SourceBadge.swift) with each chevron kept with its chip.
- Hosted pixel checks that held up: the rule's row within ±1 pt of `scrollTop + gap` at 3 x positions; a text's ink
  pixel count and ink box vs the same text drawn alone by `ControlRender` at the same scale (catches cut, shrunk and
  wrapped names). `#require(x, someString)` fails to compile: the comment must be a literal/interpolation.
- "The test runner hung before establishing connection" twice in a row on a shut-down sim: booting it first
  (`simctl boot` + `bootstatus -b`) fixed it.

**Round 2 (code review of G4), traps:**
- A deleted colour set can still be *named*: `Info.plist` `UILaunchScreen.UIColorName` held `Graphite` after the set was
  gone (the launch screen fell back to system). Grep plists for `UIColorName`/`NSAccentColorName` when deleting sets;
  `DarkOnlyTests.launchScreenColourIsTheBackground` reads `Bundle.main` (the hosted app) and resolves it.
- Extension code that can't read the catalog spells colours out (`NotificationRing`): test each literal against its
  token (`PushAndDeepLinkTests.theRingsColoursAreTheAppsTokens`).
- A ViewBuilder `if` without `else` hands a generic slot `Optional<V>`. `trailing as? any SomeProtocol` looks *through*
  the Optional (nil fails the cast), so a protocol on Optional can't spot `.none`: use `Mirror(reflecting:)`
  (`displayStyle == .optional && children.isEmpty`).
- `scrollTo(id)` to a view under the content's top padding leaves the offset > 0 (an edge appears): scroll to a
  zero-height anchor above the padding (`VStack(spacing: 0) { Color.clear.frame(height: 0).id(...) ... }`).
- A hosted window over 2 730 pt tall at 3x makes a layer over 8 192 px: it draws *nothing* (all-white snapshot).
- Accessibility frames of a combined element are the union of what is drawn (fill or words), so strips in different
  phases differ in size: place per-chip rects relative to a stable sibling (the card title), not the strip.
- A List reports `onScrollGeometryChange` like a ScrollView (Reorder took `.underPinnedHeader` without an exception);
  `HostedWindow.pageScrollView()` skips collection views, so find the largest UIScrollView yourself.
- A hosted `SubpageScaffold` root's scroll view starts under the window's 62 pt safe area: add
  `adjustedContentInset.top` to its top.

**Round 3 (UI validation's AX findings), patterns that held:**
- `StageRow` stacks from AX1 (`dynamicTypeSize.isAccessibilitySize`): name line, then duration + share under it in a
  `ViewThatFits(in: .horizontal)` (side by side, else stacked); every text `lineLimit(1).fixedSize()`.
- Hosted "one line, whole" check for texts inside a combined accessibility element (no per-text frames): scan the row's
  pixel rows for ink lines (`count(in:)` on 1-px strips), compare each line's ink box and pixel count with the text drawn
  alone by `ControlRender` at the window scale. For a textSecondary text next to textPrimary, search only right of the
  primary ink's box (anti-aliased primary edges match textSecondary).
- An overlay that must stay in the safe area while its dim covers the screen: two `GeometryReader`s in a ZStack, the dim one
  `.ignoresSafeArea()`, the card one not (its space *is* the safe area; `proxy[anchor]` converts the target into it), plus a
  custom `Layout` that measures the card unconstrained (`sizeThatFits(width, nil)`) and places it with a capped height;
  the card's text is `ViewThatFits(in: .vertical) { words; ScrollView { words } }` so the cap turns it into a scroll.
  A 280 pt cap floor read as a sliver at AX3; half the room worked. The pure `frame(height:hole:room:)` is unit-tested.
- `AppState.preview(coachMarks: true, scenario: .watch)` + `TodayView` in a 402×874 `HostedWindow` (bottomInset 0) walks the
  coach steps; `w.host.view.safeAreaInsets` gives the window's real insets (top 62).
- zsh globs `-only-testing:Suite/test()`: quote it. A whole-file mutant: old text = the file, new = `git show <base>:path`.
