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

### T1: performance-profiler, verdict ship (Release, simulator, demo)
| Metric | d9fc265 | T1 |
| --- | --- | --- |
| Cold launch to the first Today frame (12 runs, median) | 473 ms | 450 ms |
| `.app` size | 62,556 KB | 63,276 KB (+720 KB, the catalog literal) |
| Idle CPU on Today over 10 s | 0.00–0.15 s | 0.00–0.01 s |
| Catalog decode (Debug, upper bound) | — | 6–7 ms warm, 11 ms first, off the main actor on the live path |
| `SourceApp.resolve` per `facts` access (Debug) | — | 5 µs (2 refs) to 55 µs (5 refs) |

- Optional item taken: cache the resolved `SourceApp` per refs, and assert or warm the decode off-main.
- Not measurable in the simulator: the real HealthKit queries. → iPhone check.
- **T3's performance check is skipped on the simulator** (HealthKit is unavailable there). The check runs only on a tap, in
  the foreground, off-main. → The `check`, `check-newest` and `check-visible` signposts go on the iPhone checklist.

### T1 fix batch (lead → sync-engineer)
Items 1–28: everything above from UI, security, code and performance, plus the glyph rule. The guide text (T5,
`content/tracker-guides` c4e312c) is applied by the lead after the batch.

### code-reviewer: one blocker; the 8 deviations accepted with notes
- **Blocking: with no selection, the trackers are resolved once** (`ProfileViewModel.swift:1108`). "Check again" never finds
  a tracker that synced after the first run. → Recompute on every run, and add a run → sync → run test.
- **Should-fix:**
  - The night window after midnight produces `nightMissing` at 00:30, also for the iPhone. → Previous night counts; no
    night verdict for the iPhone; a table test at 00:30, 05:00, 08:00 and 23:30.
  - The label is "{app} in the App Store" (shared key with T2).
  - Apple devices claim a fault ("Open Watch…", silent plus the permission card, when the device model is missing).
    → Silent copy without "Open X"; a neutral state without a model; the device test is recorded before the flag goes on.
  - Edits outside the assigned regions (`FeedbackPayload`, `make`, `payload`) are resolved on the integration branch.
- **Nits, to be done:**
  - the "What's included" row only with a saved check;
  - the silent announcement;
  - `hasStages` on the newest night;
  - no concurrent runs;
  - `catalog:` required;
  - plurals;
  - tests for the `visibleTypes` fallback and the UI wait;
  - the Copy diagnostics line;
  - hygiene: kebab-case, doc time, the flag name in CHANGELOG, German previews.

### T3 fix batch (lead → sync-engineer)
Items 1–21: everything above from the code, security and UI reviews. Integration with T1 and T2 happens on a separate
branch.
- **Done (840b3d3, a6baeeb, f60e6e3, 7efbc5d): all 21, none declined.** Unit 762/762, `SyncCheckUITests` 4/4, lint green,
  zero warnings.
  - New neutral state `unidentified` for Apple records without a device model.
  - Until 08:00 the previous night counts.
  - The privacy texts are updated in the repo; ryftapp.de is the user's to update.

## T2 `feat: tracker setup and devices & sync` (`feat/tracker-setup`, a9e3d5f)

The implementer (ios-developer) reports 781/781 unit tests, `DevicesUITests` 5/5, `make lint` green and zero warnings.

### security-privacy-reviewer: merge dark after #2; flag on only after #1 and #3–#7 and the rebase onto T1's fixes
- **Blocking before merge, #2: Demo data writes `devices.setup: true` into the real account's flag cache.** The config
  fetch in demo mode is saved under the signed-in account (`FeatureFlags.swift:79`, `PlatformAPI.swift:145`). After
  Demo data is turned off, the dark feature is on for the real account. → Demo config only in memory or under
  `cacheKey("demo")`; reload the account's cache when Demo data is toggled; test demo on → off → flag off.
- **Blocking before the flag goes on, #1: no crash guard around decoding.** A copy that crashes the decoder would crash
  every launch (cache path), or every app-active (download). → Before each decode, write a marker file with the body's
  SHA-256 (`.atomic`); at `load()`, a leftover marker drops the cache and ETag, remembers the hash and records `crashed`;
  `refresh` refuses remembered hashes. Add a test.
- **Should-fix before the flag goes on:**
  - **#3:** with the flag off, `current` returns `.bundled` and `load()` skips the cache.
  - **#4:** rebase onto T1's validator fixes and delete `TrackerCatalogStore.isNewer` in favour of T1's.
  - **#5:** cap the ETag (≤ 128 visible ASCII characters, no spaces). Clean `describe` output; key paths are T1 item 29.
  - **#6:** key the iPhone glyph and behaviour on `id == iphone`; the catalog rule is T1 item 30.
  - **#7:** privacy texts:
    - add "tracker ids, with tracker setup on" to the `PrivacyInfo.xcprivacy` comment and `APP_STORE.md:37`;
    - restate the age-rating answer at `APP_STORE.md:142` (vendor pages open in the in-app Safari);
    - three lines on ryftapp.de/privacy (a user action).
- **Separate ticket, #8:** the whole SwiftData store sits in the widget's App Group (`TrainStore.swift:22`, `.automatic`).
  It predates T2. → Follow-up: `groupContainer: .none` with a one-time move. Recorded in STATUS.
- **Nits, to be done:**
  - cancel the stream on overflow;
  - reset catalog state on account change;
  - remove `onboarding.*.<uuid>` keys on account deletion.
- **Moved to T1:** the ryftapp.de help-path prefix (item 31). The User-Agent stays as it is.

### ui-validator (iPhone 18 Pro Max, 28 screenshots, `DevicesUITests` 5/5): no blockers
- **Should-fix: German "Ruheherzfrequenz" vs the app's "Ruhepuls".** → `Resting heart rate` and `resting heart rate` (de) →
  Ruhepuls; the guide text too.
- **Should-fix: glyphs (errata 1).** The Devices & sync row and the picker header use `watch.analog`. → Use
  `antenna.radiowaves.left.and.right`. The iPhone glyph is chosen by id (security #6).
- **Should-fix: `NumberedStep`'s 18 pt badge clips at AX3.** → `@ScaledMetric`; tile glyphs scale too.
- **Should-fix: the bundled catalog has no guide text.** → T5's content goes into T1 before T2 rebases; the flag stays off
  until it's in.
- **Should-fix: two "Show me again later" buttons with different meanings.** → The one in the card becomes "Set up
  {tracker} later".
- **Nits, to be done:**
  - about 6 pt of padding on capability rows that carry a detail line;
  - a no-break space before "✓" in the features line;
  - Profile → Data's "Open Health permissions" → "Open Health" with the path, per errata 3;
  - recapture the German screenshots (the implementer's `*-de.png` are English).
- **Nits, left as they are:** step 4 combines the iOS part (catalog content); no store caption; Apple sources keep
  HealthKit's device names; 12-hour time follows the region.

### T1 fix batch: done (8893694, 528c3ab, fc7b379), 31 items
Unit 769/769, `TodayStatesUITests` 4/4, lint green, zero warnings. Two items done differently, both accepted:
- **14:** pending days with no local start are timed from when the app first sees them, on the phone's clock. Comparing the
  server's `last_sync_at` with the phone's clock would break the clock rule. "Taking longer" can come up to about 75 s later
  after a relaunch.
- **20d:** no main-thread assertion, because previews, demo and tests decode on main legitimately. The live path warms the
  catalog in `loadBundled()`.

The guide text (T5) passes the hardened validator unchanged. The lead re-applied it onto fc7b379 (version 2026-10-22.2,
region regenerated with the `#` escaping).

### T2: code-reviewer (iPhone 17; unit 834/834; `DevicesUITests` 4/5)
- **Blocking: `testThePickerTakesSeveralButJustMyIPhoneAlone` fails 3/3.** The iPhone tile sits under the pinned bar and
  still reports as hittable. → Scroll until the tile is above the Continue button (or `-RyftScrollBottom`), then re-run
  UISmoke.
- **Should-fix:**
  - Tile names break mid-word ("Ultrahuma/n"). → The check goes into a corner overlay, and/or `ViewThatFits` falls back to
    one column. Re-check on iPhone 17e.
  - With the flag on, `showsTrackerSetup` can decode the bundled catalog on main at launch. → Check `phase == .ready`
    first; return `[]` without the catalog when nothing is chosen.
  - **With the flag off, Today's Garmin setup step changed:** main's Garmin sentence and key are gone, and VoiceOver loses
    the step number. → Keep main's text and key with the flag off; `total: 3`.
  - Samsung's card says "Apple's guide" for samsung.com, and "Good to know" repeats the limit. → Label the guide by
    integration; no "Set it up" heading for `none`; drop repeated limits.
  - The iPhone glyph and behaviour are keyed on `form` (also security #6). → Key on the id.
  - Merge friction: the parameter order in `FeedbackPayload.make` and `payload()` (T2 `trackers:` before `context:`, T3
    `syncCheck:` last); `SetupCard`'s doc line beside T3's `CheckRow`. → Agreed order: `…, trackers:, syncCheck:, context:`.
    T2 leaves the `SetupCard` doc line alone.
  - The store tests depend on fixed dates. → Derive them from `TrackerCatalog.bundled.version` and the newest `checked`
    date.
  - The `MockData.trackerCatalog` fixture is a second copy of the content, shipping in Release. → After the rebase, use
    `.bundled` and delete the text literal and `-RyftCatalog preview`.
  - The diagnostics allow-list test is weaker. → Run it with the flag on and a selection, with a template for `trackers`;
    the privacy texts gain `trackers` (with T3's).
- **Nits, to be done:**
  - wire the selection into Today's `facts` after the rebase (§9.3);
  - localized names in the Devices row, and "Nicht festgelegt";
  - the row glyph per errata 1;
  - previews for `TrackerPickerSheet` and `TrackerDetailView`;
  - `saveDocument` off main;
  - `isDue` when the clock moved backwards;
  - a forced reload doesn't join an unforced one.
- **Accepted:** the catalog line in Copy diagnostics with the flag off. T1 uses the catalog regardless.
- **The 9 deviations are accepted with those conditions.**


### T1: security re-verification at d1e6dfe
- **Fixed:** the nesting bomb (refused in 0 ms, before parsing), the Apple Watch hijack (all 6 prefixes, exact IDs,
  `device_models` and the store ID), the generator injection (`--check` plus `--self-test` in lint), the CPU blow-up (44 ms
  for 261 KB), and the earlier nits. The guide text (382 strings) is clean.
- **Partly fixed → items 32–35 back to the implementer:**
  - dot segments and `%2F` get past the path prefixes (`/setup/../auth/callback`);
  - Fitbit's prefix narrows to `/googlehealth/answer/`;
  - U+F8FF (renders as the Apple logo) passes ICU's `\p{Co}` → add a `generalCategory == .privateUse` check;
  - at most 3 combining marks per grapheme;
  - `integration` pinned per id;
  - no bundle ID that belongs to another known tracker.

### T2 fix batch: done (merges fb0b586 and cb8f580 onto T1 85c5368; 6e6246b, b9cada2, a30aed3, a5a0249), items 0–24
Unit 830/830; UISmoke 14 passed, 1 skipped (`DevicesUITests` 5/5, `TodayStatesUITests` 4/4); lint green; zero warnings.
- **Item 1 goes further than asked:** answers fetched before an account or demo switch are dropped (a generation
  counter), and the Demo data toggle refetches.
- **Item 10, changed:** no `ViewThatFits`. The picker measures each name's widest word against the tile's room and falls
  back to one column. Unit-tested; the 375 pt check is with the code reviewer.
- **Item 19:** "Open Health" with the path text only with the flag on. Flag off, Profile is as on main.
- The `MockData` copy of the content is gone; previews use `.bundled`.

PRs:
- **#33** `fix: source names and the night-not-synced state` (T1 + T5 content), draft.
  - CI failed once on the hostile-copy timing bound: over 1 s on the runner against 45 ms locally.
  - The lead loosened the bound to 2 s, which still catches the quadratic check (adc270c).
- **#34** `feat: tracker setup and devices & sync` (T2), a draft stacked on #33.

### T2: security re-verification at a5a0249
- **Fixed:** #2 (demo flags), #3, #4, #5, #6, #9, #10, #12. Nothing new is unsafe.
- **#1, partly fixed.** The marker is app-only and written before both decodes, and remembered hashes are refused unread.
  - **Gap:** the refused-hash list lives in the `content.trackers` document, which sign-out wipes. That allows one crash
    per sign-out.
  - → Keep the hashes in a file next to the marker, and merge them rather than assign (T2 follow-up batch).
- **#7:** the repo texts are done; the three ryftapp.de/privacy lines are the user's to add.
- **#8:** deferred (the store sits in the App Group). #11 is partly fixed: the older onboarding keys (`firstRunDone`,
  `aboutYouDone`, `hintSeen`) predate this work. → Both go in the STATUS follow-ups.

### T1: code re-verification at d1e6dfe
- **Fixed:** #1, #2, #3, #4, #6, #7, #9, #10, #11. No regressions to rows A–E or the status line.
- **#5, partly fixed:** the phone-clock start is sound, but a first-sight start never gets a follow-up status read. A user
  without notification permission sees a false "Taking longer" until they pull. → Item 36: one scheduled
  `refreshStatus()` at start + threshold; "slow" needs a read taken after the threshold that still lists the days.
- **#8:** a comment is still incomplete. → Item 37.
- **Row C header copy:** "Yesterday's readiness, until last night is scored." now shows for every row-C waiting state.
  **The lead confirms it:** it's true whenever row C shows yesterday's readiness, and the gauge title still says it's
  waiting for last night.
- **Known red test:** `PullToRefreshTests.thePullReturnsAfterThreeSecondsAtMost` fails locally 10/10 on the branch and
  2/3 on `d9fc265` (it passed on #33's CI). → The debugger is finding the cause and whether T1 makes it worse.
