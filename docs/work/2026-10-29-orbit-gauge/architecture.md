# OrbitGauge: architecture (ticket 1b)

Owner: ios-architect. Against `main` (aadd751) plus `fix/today-baseline-counter` (T3). Read with `brief.md`, `plan.md`
and the designer's `Ryft/Design/OrbitGaugeModel.swift` / `OrbitGaugeGeometry.swift`. ADR: `docs/adr/0010-shared-source-folder.md`.

## Problem and constraints

Today and the widget must draw the same orbit from the same values. Neither target shares a source file now: the
four shared types (`ReadinessSnapshot`, `RestTimerAttributes`, `OpenWorkoutIntent`, `WakeAlarmMetadata`) are copies,
kept in step by `scripts/check-shared-types.py` (`make lint`), because a second target membership is a project-file
change and `project.pbxproj` is never hand-edited. Both folders are synchronized roots (`objectVersion 77`), so a new
file in `RyftWidgets/` needs no project edit, but a file compiled by **both** targets does, once, in Xcode.
The widget bundle has neither the app's asset colours nor its fonts (`Brand` exists for that reason) nor its
`Localizable.xcstrings`. And `CalibrationProgress` / `CalibrationSignal` are app-only (catalog `TrackerSignal`, copy).

## 1 · Where the model and the drawing live

**Options.** (A) Copy the model and drawing into `RyftWidgets/`, byte-identical, the script comparing whole files. No
Xcode step; every change is made twice. (B) A top-level `Shared/` synchronized folder in both targets: one Xcode step,
then any file dropped there is compiled by both, with no further project edits. (C) Per-file membership of a file
in `Ryft/Design/`: one Xcode step per file, and the next shared file needs another one.

**Choice: B.** One user step, lasting (ADR 0010). A is the fallback if the step can't happen before 1c.

`Shared/` holds Swift only (no strings, no assets; `Ryft/` copies non-Swift files into the bundle, `Shared/` must not
grow any) and imports Foundation, CoreGraphics and SwiftUI only. Contents for PR 1:

| File | What | Owner |
| --- | --- | --- |
| `Shared/OrbitGaugeModel.swift` | `OrbitGaugeValues`, `OrbitGaugeCalibration`, `OrbitGaugeMode` (moved from `Ryft/Design/`) | ui-designer |
| `Shared/OrbitGaugeGeometry.swift` | angles, metrics, points (moved) | ui-designer |
| `Shared/OrbitGaugeDrawing.swift` | the `Shape`s and the static drawing: tracks, arcs, dots, segments, centre ring | ui-designer |
| `Shared/OrbitGaugePalette.swift` | colours by asset name (`Color("MetricSleep")` …), the 67/34 band rule | ui-designer |
| `Shared/ReadinessSnapshot.swift` | the snapshot's Codable core, `load`, `asOf`, `bedtimeShown`, `dayString`, `gauge` | ios-developer |

**The drawing is shared; the wrappers are not.** `OrbitGaugeDrawing(mode:size:palette:centre:)` is static and
deterministic: no strings, no fonts, no accessibility, no timers. Its centre number is a `@ViewBuilder` slot. It
takes animation inputs (track trim, dot entry offset/angle, dimming) that default to settled.
- App: `Ryft/Design/OrbitGauge.swift` adds the `.ryft` number, band word, VoiceOver label/value, `Theme.Motion` value
  animation, reduce-motion and the PR 3 entrance.
- Widget: `RyftWidgets/WidgetOrbitGauge.swift` (thin) adds the system-rounded number, `Words.spoken`, and
  `.widgetAccentable()` on arcs for the tinted home screen.

**Colours.** `Theme` reads asset colours the widget lacks. Copy the palette's colorsets (designer's final list; e.g.
SurfaceRaised, TextPrimary, Accent, MetricSleep, MetricStrain, Warning, Alert) into `RyftWidgets/Assets.xcassets`
under the same names. That's a file copy into a synchronized folder, no project edit. The script compares their
`Contents.json`. This is the one documented place outside `Theme.swift` that names colours.

**Model changes (designer's file, before 1c):**
- `OrbitGaugeCalibration.Signal` gains T3's counted signals: `anyNight, heartRateNights, hrv, restingHR`, with a
  `String` raw value and `Codable` (the snapshot stores it).
- `.scored(OrbitGaugeValues, learning: OrbitGaugeCalibration? = nil)`: S2's faint segments (PR 2, if legible).
- `.pending(previous: OrbitGaugeValues?)`, not `Int?`: PR 2 draws the previous day's scored gauge dimmed.
- `.assembling` leaves the mode (§4). The mode is data; the entrance is presentation.
- `OrbitGaugeValues.init(readiness:recoveryScore:sleepPerformance:strain:)` takes the API's 0–100 / 0–21 values.
  It's the one place they become fractions.

## 2 · The snapshot extension

One additive, optional nested field. No new `Kind`, no version integer:

```swift
/// The orbit's scores of the day the tiles show (today; the latest scored day while pending, waiting or after
/// `asOf`). Absent in a file written before the orbit: the widget draws tracks only until the app writes again.
var orbit: Orbit?
struct Orbit: Codable, Equatable {
    var recovery: Int?           // 0–100, nil while withheld (T3's `Tiles.withholdsRecovery`) or unscored
    var sleepPerformance: Int?   // 0–100
    var strain: Double?          // 0–21
    var counted: OrbitGaugeCalibration.Signal?   // with `baselineNights`: what the count counts
}
```

- **Readiness and nights keep one owner each.** `readiness`, `previousReadiness` and `baselineNights` stay where they
  are. `kind == .calibrating` + `baselineNights` is S1. `kind == .score` + `baselineNights` is S2's learning count.
  `ReadinessSnapshot.gauge: OrbitGaugeMode` (shared) assembles the mode from these.
- **Compatibility.** Synthesized `Codable` decodes a missing optional as nil, so an old file decodes with
  `orbit == nil`. Presence of `orbit` is the version marker: nil means "unknown", not "missing scores", and draws
  tracks only, never three hollow dots that would lie. An old widget (a downgrade) ignores the unknown key. Rule for
  later: only add optional keys; a breaking change takes a new key or file name, because a failed decode shows "Open RYFT".
- **Rewrite after update.** `publish` compares `shown`, a hand-listed array. Replace it with equality on a copy whose
  `updatedAt` is zeroed, so `orbit` (and any later field) counts, and the first `publishWidget` after the update rewrites
  the file. Strain moves with every workout sync. Values are the platform's (one decimal), so reloads happen only
  when the tile would change too.
- **The two copies become one.** `Shared/ReadinessSnapshot.swift` replaces `RyftWidgets/ReadinessSnapshot.swift` and the
  struct in `Repository.swift`. The app-only part (`make`, `publish`, `clear`, coders) stays an `extension` in
  `Repository.swift`, and `preview(_:)` stays in the widget. `check-shared-types.py` drops its `ReadinessSnapshot` rule
  and gains two: the orbit colorsets match, and `Shared/` has no `String(localized` / `Text("`.

## 3 · One mapping: `TodayPresentation` → `OrbitGaugeMode`

`extension OrbitGaugeMode { init(_ p: TodayPresentation) }` in a new app-only file
`Ryft/Features/Today/OrbitGaugeMode+Today.swift`. `TodayContent.orbit` calls it, and so does
`ReadinessSnapshot.make(day:presentation:now:bedtime:)` (its signature is unchanged; it fills `orbit` from the mode).
`TodayView` never maps. Values always come from `p.tiles` (`source`, T3's `recovery`), so gauge and tiles are one day.

| Path | `p.gauge` / note | Mode | Snapshot |
| --- | --- | --- | --- |
| A | `.readiness(r)`, nil | `.scored(v)` | `.score`, orbit |
| S1 · L-B short | `.baselines(n)`, nil or `.learning` (T3 counted) | `.calibrating(n, counted ?? .anyNight)` | `.calibrating`, nights, counted |
| L-B long | `.baselines(n)`, `.needsVitals` | `.calibrating(n, .heartRateNights)` | same |
| S2 | `.readiness(r)`, `.learning(prog)` | `.scored(v, learning: prog.nights, counted)` | `.score`, nights, counted |
| N1 | `.readiness(r)`, `.blocked` | `.scored(v)` (Recovery from what was scored) | `.score`, orbit |
| N2 | `.readiness(nil)`, `.blocked` | `.scored(v)` with nil readiness/recovery/sleep: hollow dots | `.waitingForSleep`, orbit |
| L-B + r | `.readiness(r)`, `.needsVitals` | `.scored(v)` | `.score` |
| L-D | `.readiness`, `.recalculating`, maybe earlier day | `.scored(v of source)`, dimmed when earlier | earlier day → `.waitingForSleep` (as now) |
| C | `.pending(night)` | `.pending(previous: v of latest prior)` | `.pending` / `.waitingForSleep` |
| E | `.firstImport` | `.scored(.empty)` (hero `.importing` covers the import) | nil, file removed |

**Test (replaces "one test in each target").** There is no widget test target, and an appex can't be imported. Shared
files are one source, so parity is the round trip, in RyftTests, for every `TodayScenario` and the decision-table
fixtures: `JSONDecoder(encode(make(p))).gauge == OrbitGaugeMode(p)`. L-D from an earlier day is the one documented
exception. Add one render test of `OrbitGaugeDrawing` per mode.

## 4 · The entrance (PR 3)

- **Not a mode.** `OrbitGauge(mode:entrance:)` with `entrance: .assemble | .none`. Today's first frame already has a
  decided `TodayContent` (synchronous SwiftData read), so the entrance always ends ≤ 900 ms in the real mode. Brief
  step 4 (endless orbit while "not available") has no state in which it would run: first-run is the import card, and
  pending breathes, it doesn't rotate (it can last hours). Lead: confirm, or name the state that should orbit.
- **The flag.** `TodayViewModel.private(set) var assemblesGauge = true` and `func gaugeDidAssemble()`. No UserDefaults.
  `ScreenModels` is built once per process in `RyftApp.init`, background launches included. So the flag is per process.
  Sign-out doesn't rebuild it either.
- **Consumed on the first appearance while `scenePhase == .active`, not at init.** A process launched in the background
  (HealthKit delivery, `BGAppRefreshTask`) and opened later still plays it once: the user hasn't seen Today yet.
  Foreground returns, tab switches and pull-to-refresh find it consumed. A launch onto another tab (deep link) plays it
  on the first Today visit; accepted. Reduce Motion / Low Power consume it and fade. Something covering Today in the
  first frames (the "Open in" import cover, a gate sheet, a system alert) lets it play unseen and consumes it;
  accepted too (lead, PR 3 review), because detecting cover state on Today isn't worth one animation.
- **Main actor.** The entrance is view state only: `TimelineView`/`withAnimation`, no tasks, no reads. Measure as the
  brief says.

## 5 · PR sequence and file ownership

0. **T3 merges** (`TodayViewModel`, `Calibration`, `MetricGauge`, `Repository.widgetFacts`, `ScreenModels`, `TodayView`).
1. **1a (now, no conflicts with T3):** the designer works in `Ryft/Design/OrbitGauge*.swift` and adds colorsets to the
   widget catalog. Nothing else.
2. **1c, after T3 is on `main`, `main` merged in:** `git mv` the model, geometry, drawing and palette into `Shared/`.
   Create `Shared/ReadinessSnapshot.swift` and remove both old copies. **User does the Xcode step (below) on this
   branch**, and Xcode's pbxproj diff is committed. Then the ios-developer adds `OrbitGaugeMode+Today.swift`, one
   property on `TodayContent`, `.score` in `TodayView`, `make`/`shown` in `Repository.swift`, `ReadinessWidget`,
   `WidgetOrbitGauge.swift`, the check script, `.swiftlint.yml` `included` and `ios.yml`'s warning grep (`Shared`).
   The hunks are disjoint from T3's: the struct at the end of `Repository.swift`, `widgetFacts` untouched.
3. **PR 2:** drawing (designer). Today's `.calibrating`/`.pending` branches, removal of `BaselineGauge`/`PendingGauge`
   (developer). The snapshot shape doesn't change: it all landed in 1c.
4. **PR 3:** `TodayViewModel` flag, `OrbitGauge` entrance. **PR 4:** `Orbit.strainBand` as an optional key once the API has it.

**What could go wrong.** The Xcode step adds `Shared` to a test target too (duplicate symbols with `@testable`): tick
only Ryft and RyftWidgetsExtension. Colorsets drift: the script catches it. `systemMedium` isn't in
`supportedFamilies` yet: adding it is a layout decision for the designer. Tinted/clear home screens desaturate arc
colours: `widgetAccentable` on arcs, tracks not, checked in the widget preview.

## User step in Xcode (once, on the 1c branch)

1. Pull the branch; `Shared/` already exists at the repo root (beside `Ryft/`) with its Swift files.
2. Xcode → File → Add Files to "Ryft"… → select `Shared`. Action: **Reference files in place**. Groups: **Create
   folders**. Targets: tick **Ryft** and **RyftWidgetsExtension** only. Add.
3. Check: `Shared` shows as a blue folder; File inspector → Target Membership lists both targets. Build the `Ryft`
   scheme (it embeds the widget). Hand the pbxproj diff to the lead to commit.
