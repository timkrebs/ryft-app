# Data quality: review log

## T1 · `today: tracker sync hint opens the app` (#87)

Round 1 on `feat/tracker-sync-hint` up to 4b209e9. **No reviewer had a blocking finding.**

| Reviewer | Finding | Severity | Decision |
| --- | --- | --- | --- |
| localization-editor | The Withings `sync` sentence dropped the Health-app step | fix | Fixed by the localization-editor (29b92ae). |
| security-privacy | The App Review note said RYFT asks about "the tracker the user set up"; the code asks about the quiet source | should-fix | Fixed by the lead (4b209e9). ADR 0012's follow-up line was corrected too. |
| security-privacy | The device check of the schemes appears only in the ADR | should-fix | Fixed: `STATUS.md` now has a release gate (4b209e9). |
| security-privacy | ADR 0012 rule 5 said demo and the simulator use a fake | nit | ADR aligned with the code (4b209e9). |
| code-reviewer | After 29b92ae, "its Home tab" reads as the Health app's tab | should-fix | ios-developer: "the Withings Home tab" / "in Withings". |
| code-reviewer | The "open failed → store page" fallback lives only in the view and is untested | should-fix | ios-developer: a pure function with a test, plus a pin that every `appSchemes` id has a `storeIDs` entry. |
| code-reviewer | Bundled version 2026-10-31.1 against the served copy | should-fix | ios-developer: a line in `API_REQUESTS.md` Tracker setup §3 saying the served file must be newer than 2026-10-31.1 and carry `sync`. |
| ui-validator | The card chrome (padding 14, tile radius, surface at 0.6) differs from design D3.2 (`cardPadding`, `cardRadius`, `Theme.surface`) | should-fix | ios-developer: align with the design. |
| ui-validator | VoiceOver structure checked from code only | should-fix | ios-developer: an XCUITest assertion that `today.watchHint.action` is a button with the label. |
| code-reviewer | The `canOpenURL` answer can be up to 60 s stale after the app returns to the foreground | nit | ios-developer: re-render on `scenePhase` → active. |
| code-reviewer, security-privacy | `trackers.py` is looser than the Swift validator | nit | ios-developer: mirror Zl/Zp/Cn/Co and the script rule, or label the script a pre-check. |
| code-reviewer | `WatchSyncHint.opensApp` is used only by tests | nit | ios-developer: rename or remove. |
| code-reviewer | A test can't fail in a German host | nit | ios-developer: pass `en_US`. |
| code-reviewer, security-privacy | "Leaves RYFT" has no full stop | nit | ios-developer: "Leaves RYFT." / "Verlässt RYFT.", like the sibling hint. |
| ui-validator | The icon column shifts by glyph width | nit | ios-developer: a fixed-width icon frame. |
| ui-validator | `.monospacedDigit()` on the night caption | nit | Not changed; it predates T1. |
| code-reviewer | ADR 0012: a remote copy can still add a bundle id under `garmin` | nit | Lead: ADR sentence made precise. |
| code-reviewer | COROS has no `sync` | nit | Not changed. Its habits cover workouts only, and the hint is about heart rate and sleep. |

Round 1 fixes: f9e9641, 29d2a7e (ios-developer); every should-fix and nit above is done. Unit 2181, 0 failed; the new
UI test `testQuietTrackerHintSaysHowItSyncsThenOffersTheApp` and the night-hint test pass.

**Lead, on the night hint:** it keeps its own sentence ("Open Garmin Connect to sync it.") above the "Open Garmin Connect"
button. The sentence explains why and the button acts. design.md §D3 only defines `sync` for the quiet sentence. Not
changed.
