---
name: PR 6 F-Journal fix round
description: Journal sheet isCurrent guards and dismissal, test seams for late reads/saves, DST wall times, single-send coordinator, and how to prove the launch tap in a UI test
type: project
---
- `JournalSheetModel.isCurrent` = `store.owns(opened)`; `staysOnItsSide()` sets `leftItsSide`. Guard every entry
  (load, loadDay top and after its await, select, requestSelect, habitsChanged, save before/after). The sheet
  dismisses with `.onChange(of: model.isCurrent, initial: true)`; `store.generation` is observable, so
  `store.accountChanged()` in a test is enough to drive it (hosted: `SheetHost` + `sheetNodes(w)`).
- Seams for late answers: `api.beforeJournalAnswer` ("journal", "putJournal"), `store.beforeApplying` (DEBUG,
  "behaviors"), `JournalTestGate` for a custom saver, `RequestHold` for holds.
- `JournalStore.time` parses HH:MM into `Fmt.time(hour:minute:locale:)` (2001-01-01, no DST). The DST test only
  fails against the old code where the process TZ is Europe/Berlin (this Mac's sims). en_GB formats 02:30 as
  "2:30" (no leading zero) — don't assert "02:30".
- `OnboardingCoordinator.perform` drops a second call while `isWorking`.
- Launch UI test: `XCUIApplication.launch()` returns 5.5-6.5 s after it is called and the overlay is first
  seen ~1.2 s later, ~4.1 s before it is gone; so "launched + 5.2 s" is already past. The proof that works is
  a control launch nobody taps, measured from its first sighting, then a tapped launch that must be gone
  `gap` sooner from its own first sighting.

**Why:** PR 6 review S1/N-2/N2-N7; the timing traps cost two calibration runs.
**How to apply:** reuse the control-launch pattern for any "a tap/gesture ends an animation" UI test.
