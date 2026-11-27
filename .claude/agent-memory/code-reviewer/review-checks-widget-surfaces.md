---
name: review-checks-widget-surfaces
description: RYFT review checks for widget families and Live Activities (Nocturne W, 2026-11-19) - privacySensitive escapes placeholder redaction (probed), per-device accessory sizes, test-only layout models, Volt claims vs the shared orbit, "as of" ages
metadata:
  type: feedback
---

From the W review (widget + Live Activities in Nocturne, 6c54eb6, 2026-11-19); Unit and strict build were green:
- **`.privacySensitive()` exempts its subtree from `.placeholder` redaction** (macOS swiftc + ImageRenderer probe, lit-pixel
  fill of the text bbox: placeholder 0.98 = box, placeholder + privacySensitive 0.47 = glyphs, `[.placeholder, .privacy]`
  0.98). The iOS hosted harness agreed: the placeholder drew "71 High" before and "00 Readiness" after. So a "constant under
  the redaction" (`Words.lockedNumber` "00") is *visible* in WidgetKit's placeholder. Judge placeholder content as if
  unredacted; for the placeholder prefer the dash, keep "00" for `.privacy` only. No need to re-probe.
- **Accessory sizes vary by device** (HIG table: circle 76/72/68, rectangle 172x76 / 160x72 / 153x68, small 170..148).
  A constant pinned to the largest (`76 - circularAir == 62`) hides threshold crossings: `side - 14` on a 68 circle is 54,
  under `minDialForNumber` 56, so the SE's circle lost its number (the old `side - 12` kept 56). Check every size.
- **Test-only "models" in Shared** (`smallDial`, `rectangularStack`, `lockScreenHeight`) that the views never call: the
  Dynamic Type cap tests prove arithmetic with `UIFont.lineHeight`, not the rendered view. Ask the view to call them or
  for a hosted render.
- **"Only Volt in the extension" claims** miss the shared orbit: `OrbitGaugePalette.signal` draws the readiness marker
  in every family, dimmed on pending/stale. The brief allows the marker; check the comment and the scan's scope.
- **Ages from `updatedAt`:** `days <= 0` (time-zone travel, clock change) fell into "yesterday"; a year-old date lacked
  the year ("As of Nov 19" on Nov 19). `publish` skips unchanged writes but `day` forces one per day, so `updatedAt` is
  the last day the app wrote.
- Look at the implementer's own harness shots for the honest-state tiles (placeholder, locked) before trusting a grep test.

**Why:** each passed the PR's tests; only probes, the shots and the size table showed them. **How to apply:** any PR
touching `RyftWidgets/`, `Shared/` widget code or Live Activities. See [[review-checks-shared-widget-gauges]],
[[review-checks-large-text]], [[review-checks-today-state]].
