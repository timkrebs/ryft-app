# Tracker setup: review log

Findings from the read-only reviewers, the lead's decisions, and what went back to which owner. Newest at the bottom of each
ticket.

## T1 `fix: source names and the night-not-synced state` (`fix/source-names-night-gap`, 4071b6c)

The implementer (sync-engineer) reported:
- Unit tests 753/753 (30 new); UISmoke 9 passed, 1 skipped; `make lint` green; zero warnings.
- 8 departures from the design, all accepted by the lead: the night gap needs row C, the gauge's "Open X" line is
  dropped, Sync details carries no names, `other` may link to apple.com, Suunto has no help URL, the scoring-wait start is
  cleared more often, the line-length disable is emitted only when needed, the quiet hint gets the app button, and there
  are small edits outside the assigned regions.

### ui-validator (iPhone 17e, demo `nightGap` / `scoringSlow`): no blockers
- **Should-fix: the night state says it three times.** The header says "…hasn't reached RYFT", the gauge "It's scored as
  soon as Apple Health has it", the card "…hasn't reached Apple Health". → The header subtitle becomes "Yesterday's
  readiness is shown until last night is scored."; the gauge detail is dropped while the hint card shows. en + de.
- **Should-fix: "Open Garmin Connect" opens the App Store.** → The label becomes "Garmin Connect in the App Store" /
  "Garmin Connect im App Store", which stays true whether the app is installed or not. Update the UI test and the
  identifier assertions.
- **Should-fix: the card caption's light-mode contrast** is about 4.1:1 (`textTertiary`). → `textSecondary`.
- **Should-fix: the caption's date and time ignore the locale** ("Mi. 11:24 PM" in German, `TodayViewModel.swift:658`).
  → Format with the screen's locale (`Fmt.time` approach).
- **Nit: slow scoring repeats "Taking longer than usual".** → Gauge title "Still scoring your night"; the status line keeps
  Details.
- **Nits at AX3:** the German card leaves its full stop alone on the last line; the raw-night card header is cramped.
  → Stack the header at accessibility sizes.

### security-privacy-reviewer: nothing exploitable as shipped (bundled copy only); the validator must hold before T2
Lead decision: everything below is fixed in T1, because the validator is T1's code and T2 decodes the remote copy with it.
- **Blocking for T2: a ~900-byte document nested 440 levels deep overflows the stack** (`CatalogJSON.init(from:)`,
  recursive). → A byte-level depth scan before decoding (limit 8), or typed `Decodable`. Add a test.
- **Blocking for T2: the "com.apple. only for Apple" ownership rule can be bypassed.** `com.apple`, `com`, `COM.APPLE`
  prefixes pass, and `device_models` skips the ownership check. Verified end to end: the Apple Watch was renamed "Garmin
  Connect". → For non-Apple trackers, refuse prefixes or IDs that equal or cover `com` / `com.apple…`; prefixes need ≥ 3
  labels; `device_models` only on `apple_watch` / `iphone`.
- **Should-fix: `\#(…)` in content becomes a Swift interpolation** in the generated raw literal (verified: code ran at
  first read). → `region()` escapes every `#` in the dumped JSON as `#`; add a lint test.
- **Should-fix: the help-link allowlist uses suffix matching** (`sites.google.com`, Google's redirectors, `*.ryftapp.de`).
  → Exact hosts per tracker; `ryftapp.de` exactly; `other` → `support.apple.com` is added to design §2.5.
- **Should-fix: validation cost.** The arrays are uncapped and `checkOwnership` is quadratic: 36 s for a valid 153 KB
  copy. → Cap each array at 8 or fewer, lowercase once, compare `Set`s. `match()` on every Today render is to be
  measured (perf).
- **Should-fix: text rules.** Length is counted in graphemes (combining-mark bombs); private-use and line-separator
  characters pass; brand folding is missing (combining marks, fullwidth, Cyrillic look-alikes). → Cap the scalar count,
  allow only the Latin, Common and Inherited scripts, refuse Co/Cn/Zl/Zp, run NFKC + case + diacritic folding before the
  brand check, and check every string, including `id`, bundle IDs and URLs.
- **Nits, all to be done:**
  - add `@`, `mailto:` and `tel:` to the markup list;
  - make the action `title` a `String`, not a `LocalizedStringKey`;
  - pin `app_store_id` per tracker id (compiled);
  - require the percent-encoded host to be plain ASCII;
  - version format `YYYY-MM-DD.N`, compared as `(date, Int)`.
- **Nit: App Store screenshots must not show "Garmin Connect".** `docs/screenshots` aren't the store set, so no change.
- **Out of scope, but a T1 regression:** the quiet hint can name the iPhone ("Nothing new from Tim's iPhone… Wear it…")
  now that `newestRecords` includes iPhone sleep (`TodayViewModel.swift:810`). → Filter `isPhone` there.
- **Heads-up for the privacy policy:** T2's daily fetch sends an IP and User-Agent to ryftapp.de's host. If
  `User.trackers` is ever uploaded, that's new data, with a label row and a policy update.

### code-reviewer: build, 73 tests in 6 suites, 4 UI tests and lint all green; the suite encodes two of the bugs
All accepted by the lead, and the 8 departures are confirmed.
- **Should-fix: `latest.sleep` includes the iPhone's in-bed record** (`TodayViewModel.swift:840`). A Garmin user whose
  iPhone tracks bedtime never gets the night hint: the platform's `latest.sleep` is the max over all sources.
  → Ignore `latest["sleep"]` when a local `isPhone` source's newest record is within about a minute of it or newer. Add a
  test with in-bed at 07:05 locally and in `latest`; fix `ViewModelTests.swift:579`.
- **Should-fix: "Scoring your night" while the gauge waits for the night** (`:790`). `night` is true for any `.pending`
  hero. → Only when `!p.waitingForSleep`; `ViewModelTests.swift:653` expects `.scoring(night: false)`.
- **Should-fix: a cancelled wait keeps its start** (`SyncService.swift:97–113`). Hours later Today says "Taking longer" and
  VoiceOver announces it. → `.awaitingScores → .idle/.failed` clears the start unless the 300 s cut-off has passed.
  Add tests.
- **Nits, all to be done:**
  - The Timeline period depends on the line: with `expected_within_sec = 120`, "Taking longer" can't appear after the
    cut-off. → Tick every 15 s while `scoringSince != nil`.
  - There's no start after a relaunch, or when another device left days pending, which makes an endless "Scoring your
    night". → Fall back to `SyncStatus.lastSyncAt` when `pending_days` isn't empty.
  - `receive()` clears the start mid-wait on a stale status read. → Don't clear while `.awaitingScores`.
  - Sync details says "Nothing waiting" while the platform lists pending days. → Show the platform's pending days.
  - The comment at `SyncService.swift:108` is misleading. → Correct it.
  - The quiet hint shows offline (`:807–815`). → Guard `f.online`.
  - `hasButtons` is dead code (`StatusViews.swift:53`). → Remove it.
  - Body work: the line is evaluated twice, and a full `facts` rebuild runs every 15 s. → Read the line once; derive the
    period from `facts`.
- **Tests:** correct the two expectations; add `.awaitingScores → .idle`, `receive` during a wait, the `scoringSince`
  wiring in `TodayViewModel.facts`, the gauge going from breathing to static, and `trackers.py`.
- **For T4:** `PendingGauge.breathes` sits outside T4's `GaugeNote` region; T4 must keep it.

### performance-profiler
_(resumed after the usage limit)_

## T3 `feat: sync check` (`feat/sync-check`, a2cd709)

The implementer (sync-engineer) reports 753/753 unit tests (18 new), `SyncCheckUITests` 4/4, `make lint` green and zero
warnings. Deviations:
- RYFT's own source is excluded by bundle ID, because `HKSource.default()` throws in unsigned builds.
- `classify(catalog:alongside:)` and `.elsewhere(app:)`.
- The expected count includes signals that arrive although the catalog says otherwise.
- The fix steps show inline.
- `TrackerCheckRecord` is stored as entries.
- With no selection, the check falls back to the trackers seen in Apple Health.
- No `trackers` diagnostics key (T2 owns the selection).
- No reduced-motion previews.

### ui-validator (iPhone 17, AX2 and AX3): no layout blockers
- **Should-fix: the fix panel has no steps.** Garmin's `setup_steps` and `health_access.steps` are `[]` until T5's content.
  → The steps arrive with T5, which goes in before T3. Inline steps replace the "Show setup steps" button, so there's no
  dead end. The Devices & sync link comes with the T2 wiring.
- **Should-fix: the secondary button in the raised fix panel has no visible shape.** → Outline it, or put it on
  `surface`.
- **Should-fix: "Open Garmin Connect" opens the App Store.** → "Garmin Connect in the App Store" / "… im App Store",
  shared with T1. Update the UI test.
- **Should-fix: "Open Health permissions" opens the Health app's root** (`x-apple-health://`). → Label "Open Health" /
  "Health öffnen", and always show the path text from `health_access.steps`.
- **Should-fix: Garmin's tile shows an Apple Watch silhouette** (`applewatch`). → `applewatch` only for `apple_watch`;
  other watches `watch.analog`; the band gets a distinct glyph. One mapping, shared with T2. T2 was told while it builds.
- **Nit:** the glyphs don't scale at AX3. → `@ScaledMetric`.

### security-privacy-reviewer: nothing blocks the merge (dark, only reachable from DebugScreen); fix 1–3 before the flag flips
- **Should-fix: the Apple Watch glyph on non-Apple trackers** (`ProfileView.swift:1682–1689`). This goes against SF
  Symbols' terms and App Review 5.2.5, and ui.md prescribed it. → Glyphs by tracker id; ui.md errata 1; T2 told.
- **Should-fix: the permission card says iOS tells RYFT "what it may read"** (`:1447`). It doesn't. → ui.md errata 5,
  en + de.
- **Should-fix: the privacy texts don't mention `sync_check`** (`APP_STORE_METADATA.md:161`, the
  `PrivacyInfo.xcprivacy:106–110` comment, ryftapp.de/privacy). → T3 updates the two repo texts. The website goes on
  the user's Needs-you list. No label change.
- **Nits, all to be done:**
  - make the drift log's tracker id `.private` (`HealthStore.swift:697`);
  - show the "What's included" row only when a check exists (`ProfileView.swift:2046`);
  - drop a check older than 14 days from diagnostics;
  - capture the account at the start of `run` and skip the save if it changed;
  - "The check uploads nothing" plus a CHANGELOG note that result codes go with a report;
  - label "Open Health" (errata 3).
- **OK as is:** the check is kept per account and wiped on sign-out; `sync_check` carries day + ids + codes only;
  logging; the honest wording otherwise; the URLs; HealthKit types and purpose strings unchanged; nothing runs in the
  background.
