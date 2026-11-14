---
name: review-checks-shared-widget-gauges
description: RYFT review checks for gauges shared between the app and the widget via Shared/ (OrbitGauge PR 1-2, 2026-10-29/30) — number fit at widget dials, fixed-size captions, String-enum keys, parity exceptions, legacy-removal field loss, task ids vs env flags, phaseAnimator facts
metadata:
  type: feedback
---

Found in the OrbitGauge PR 1 review (2026-10-29); the whole Unit plan was green:
- **Number fit at widget dials.** A number sized `dial * k` inside a ring with a *fixed* inset (`centreInnerDiameter - 10`)
  shrinks past `minimumScaleFactor` at small dials. Probe with `ImageRenderer(Text(..).fixedSize()).cgImage.width` per dial
  (44/60/64/72) for "71" and "100": the circular complication (dial ≈ side − 12) truncated "100", and the home-screen
  number fell from 32 pt to ~13 pt. Compare against main's widget, not just the app's `.large`.
- **Fixed-size labels that moved.** `ryftNumber(size:)` is `fixedSize`; fine inside a gauge, a Dynamic Type miss once the
  label sits under it. Check that the AX3 preview actually passes the caption (it used a stand-in Text).
- **String-raw enums in a persisted snapshot.** "Only add cases" is wrong for older readers: an unknown raw value fails the
  whole `JSONDecoder` decode (widget shows "Open RYFT"). Within one bundle it's downgrade-only; say so, suggest lenient decode.
- **Parity tests with an exception branch** (`if case .readiness = p.gauge, widget.kind != .score { return }`) accept any
  regression into the excepted kind. Ask for the exact exception predicate.
- **Snapshot field cost.** Fields written for kinds that don't draw them (today's strain on a calibrating day) rewrite the
  file and spend background widget reloads after every `refreshDays`.

Re-review (a0c6766, 2026-10-30), locked widget via `.privacySensitive()` / `.privacy` redaction:
- **Redaction placeholders keep the text's width.** Probed with ImageRenderer + `.redacted(reason: .privacy)`: caption2
  "High" 21 pt, "Moderate" 43, "Low" 16; "100" 32 vs "71" 21. A redacted band word or number still tells the band. When
  locked, swap the *content* for a constant before redacting; check every family (inline too) and whether a family's
  layout (gauge present or not) differs by kind while locked.
- `@Environment(\.redactionReasons)` does reach plain children of `.redacted(reason: .privacy)` (probe confirmed).

OrbitGauge PR 2 (2026-10-30), calibrating/pending, legacy drawings removed:
- **Legacy removal drops a field.** List every snapshot field the removed widget drawing read (`previousReadiness` in
  the pending outline) and check the new mapping still draws it in every kind/orbit combo: `.waitingForSleep` with
  `orbit == nil` (row A/N2 without readiness, a calibrating file after `asOf`) became `.pending(previous: nil)`, a dash,
  while `Words.spoken` still said "Last readiness 64".
- **`.task(id:)` keyed on the value but guarded by an environment flag** (`reduceMotion`, `animatesFill`): the flag
  flipping doesn't re-run the task, so state seeded only by the task (`shownNights`) stays nil and the view draws 0.
  Put the flag in the id. Same family (PR 3 entrance): an animated clock whose *end value* depends on Reduce Motion
  (fade ends at 0.25 s, choreography at 0.85 s) leaves the view in a mid-choreography frame when RM flips later. Always
  end latched animations at one value, or render "done" from an explicit flag.
- **phaseAnimator facts (macOS swiftc probe, NSHostingView + RunLoop):** a single-phase array calls content twice and
  stops (no churn); switching `[1, 0.5]` → `[1]` mid-breath settles on 1.0. No need to re-probe.
- **Text fit facts (same probe style, ImageRenderer + proposedSize):** `lineLimit(n) + minimumScaleFactor` shrinks
  rather than breaking a word mid-word even when n leaves spare lines ("a b GESAMTBEREITSCHAFT", n 3 → 2 lines, smaller);
  without a scale factor the long word breaks. English two-word captions at normal width keep full size.

OrbitGauge PR 4 (strain band, 2026-10-30):
- **Wedge/arc clips with `to` from a live sweep.** `Path.addArc(clockwise: false)` with end < start wraps the long way
  (swiftc probe: a wedge `split...sweep+4` during the entrance glide covered the whole arc, so it drew alert until it passed
  the split). Check every clip/Shape fed `sweep * glide` for to < from.
- **Non-animatable parts beside an animated Shape.** Only `animatableData` (sweep) interpolates: a clip Shape without it, or
  an `OrbitDot(start: head, sweep: 0)` cut, jumps to the end value while the arc/dot animate. An `if/else` choosing the arc
  view by value (plain vs split) swaps identity mid-animation (fade, no trim). Ask for the animated case explicitly.
- **"Parity" tests inside one build** (undrawable band vs nil) only prove both take one branch; nil == main needs a pinned
  golden/hash. Also: CI Lint ran swiftformat on a double blank line; run `.build/tools/swiftformat --lint` early.

**Why:** these were the non-obvious parts; mapping/round-trip logic itself was right. **How to apply:** any PR that
touches `Shared/`, `ReadinessSnapshot` or widget families. See [[review-checks-today-state]], [[review-checks-dark-launch]].

Alpine PR 1 (level by shape, 2026-11-06):
- **A new drawing keyed on the score also reaches `.pending`,** because `drawnValues` includes the previous day. Parity and
  level tests use `.scored`, and pending tests use `previewScored` (71, solid), so nothing sees it. Render pending at 50 and 20.
- **Contrast pinned on the app's ground isn't the widget's:** `Brand.background` is hard-coded in `RyftWidgets.swift`, not a
  colour set. Recompute any light ratio on it. **Worth grepping:** spec lines repeated in a later section (8.1 "Same:" columns).
