---
name: review-checks-presented-styles
description: Root style modifiers vs sheets/covers, the app target's missing global accent, shared metric rules (vs 7 d) and demo-aware online checks; checks for integration reviews of restyle PRs
metadata:
  type: feedback
---

Integration reviews of a restyle PR (Nocturne PR 5, 2026-11-19) need these checks on top of the per-ticket reviews.

- **Root styles don't reach presented roots.** `.tint(Theme.textPrimary)` and `.toggleStyle(.ryft)` sit on the WindowGroup
  root (RyftApp). PR 6 C found that on iOS 27.2 they don't reach `.sheet`/`.fullScreenCover` content, while
  `.environment(model)` objects do. Previews (`previewEnvironment`) and hosted tests set the styles themselves, which
  hides the gap. The app target has no `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` (only the widget has one), so an
  untinted control in a sheet is system blue.
  **Why:** a review that only reads the root missed it until the device showed it.
  **How to apply:** grep `.sheet(`/`.fullScreenCover(` and list each root that has a Toggle, a toolbar Button, a
  DatePicker or a NavigationLink without its own style. Shared parts that wrap a Toggle (GroupedRow `.toggle`) should set
  `.toggleStyle(.ryft)` themselves. Sheet scaffolds (SubpageScaffold `isSheet`) are the place to set both.
- **One rule per label.** A label that several screens share ("vs 7 d") must come from one helper. Strain used the prior 7
  days with at least 3; Today, Insights and Sleep used the 7-day window ending on the day with at least 1.
  **How to apply:** grep the label's literal and every `MetricDelta` constructor.
- **Online checks are demo-aware.** `isDemo || connectivity.isOnline` is the rule (AppState). Grep
  `connectivity.isOnline` without `isDemo` in models that fetch: a bare check leaves demo stuck on "Planning…" while
  offline.
- Related: [[review-checks-area-integration]], [[review-checks-merges-and-wiring]].
