---
name: review-checks-trend-cards
description: RYFT review checks for trend cards / sparklines with deltas and bands (Insights T5.3, 2026-11-18) - min-max bands that contain the latest point, delta rules that differ by range and from Today, "No data" for never-loaded series, unpinned window bounds
metadata:
  type: feedback
---

Found in the Nocturne T5.3 Insights review (2026-11-18). The suite and the build were green:
- **A band computed as the min-max of a window that contains the latest point is degenerate.** With a y domain of
  series ∪ band, it fills the whole chart in 7 D and 30 D (visible in the shots), and "ending above/below its usual range"
  can never happen. The implementer's test reached `.above` only with a monthly series that omitted the latest value,
  which the API never sends. Check whether the band's source includes the plotted points, and require the test input to be
  API-shaped.
- **"vs 7 d" deltas must agree across ranges and with Today.** Today's `MetricDelta.vsSevenDayMean(readinessWeek)` gets
  a 7-day series, so it uses at most 6 priors and needs only 1. A card computed from the selected range uses 6 priors in
  7 D and 7 priors in 30/90 D. The demo shots showed "Steady" in 30 D and a red "▼ −12m" in 7 D for the same night.
  Diff the 7 D and 30 D shots of the same data; any delta that changes between them is a bug.
- **`series == nil && !isLoading` is "never loaded", not "no data".** That covers offline (`refreshIssue` is nil while
  offline), a failed first read, and the gap before `load()` starts its reads (Insights awaits the journal's impacts
  first). Check what note and spoken value that case gets.
- **Window-bound tests:** put distinct values exactly N and N+1 days back. Otherwise a mutated `>=` or an N±1 window
  still passes, because the means are equal.
- Shots taken with `.environment(\.locale, en_US)` still format model-side strings (`Date.formatted`) in the
  simulator's locale ("18. Nov"). This is harmless in the app, but don't read it as a bug.

**Why:** each of these was a data-rule defect that the implementer's own tests encoded. **How to apply:** use these on
any card that shows a latest value, a delta or a personal range. See [[review-checks-derived-states]],
[[review-checks-design-components]], [[review-checks-screen-loads]] (a VM-owned "loading" flag needs its generation token).

Recurred in T5.5 (Sleep Week/Month, 2026-11-18): `.vsSevenDayMean(summary.totals)` on the range on screen gave Week
"▼ −12m · −2 %" (6 priors) and Month "Steady" (7 priors) for the same night, and needs only 1 prior (Strain/Insights need 3).
The implementer's test compared the board with the same function (a tautology). Also check the delta's *label*: `SleepRange.days`
holds only nights with data and the range has a 1 h TTL with no invalidation on scoring, so "Last night" names an older night in
the morning, after a night off the watch, or for up to an hour after scoring. Offline: `state.refreshIssue` is nil (`guard online`)
and covers only today/history, so a cached range shows with no "as of". Clock strings built from stored "HH:MM"
(`BedtimePlanner.summary`, `BedtimeLayout.spoken`) ignore the 12/24-hour setting; grep `String(format: "%02d:%02d"`.
