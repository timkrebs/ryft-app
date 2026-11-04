# RYFT iOS — data quality: send deletions, show provisional scores and coverage, detect sources — brief for `ios-lead`

Run: `claude --agent ios-lead` → "Run `CLAUDE_FOLLOWUP_DATA_QUALITY.md`". Owners: **sync-engineer** (D1, D4),
**ios-developer** with **ui-designer** (D2, D3), **api-contract-keeper** (mirror, changelog gates), **test-engineer**,
**localization-editor**; reviewers per fleet. The platform half is `../plattform/CLAUDE_FOLLOWUP_DATA_QUALITY.md`; D1 and
D2 wait for its `API.md` changelog entries ("Deletions and HealthKit ids", "Coverage and provisional scores"). D3 and D4
need nothing new and can ship first.

## Why

Three things testers see as "RYFT's numbers are wrong" are stages we control:

- A Garmin run shows **7×** in My Day. Garmin Connect rewrites workouts under new UUIDs; the app already collects
  HealthKit's `deletedObjects` (`PendingDeletions`, `Sync/SyncService.swift`, 2,000 per stream) and has nowhere to send
  them. The platform is adding `SyncRequest.deleted` and `Sample.id` / `SleepSegment.id`.
- A **half night scores like a full one** when Garmin syncs at 03:00. The platform is adding `DailyScore.coverage`
  with `status: provisional | final` and holds the morning push until `final`. The app must show a provisional score as
  provisional and not make the later change look like a bug.
- **Nobody can see which source won.** The platform picks the densest source per hour and the longest-sleep source per
  night (`../plattform/docs/SCORING.md`), and the user never learns it.

Read first: `Sync/SyncService.swift` (`PendingDeletions`, the page builder, anchors), `Health/HealthKitManager.swift`
(the anchored reads), `Features/Today/TodayViewModel.swift` and `TodayView.swift` (the hero switch, `.pending`),
`Features/Today/ReadinessCopy.swift`, the explain sheet if one exists (search `Explain`), the tracker setup
(`CLAUDE_FOLLOWUP_TRACKER_SETUP.md`'s result: search `TrackerSetup`), `Networking/Models.swift` (`DailyScore`, `User.sources`),
`docs/API_REQUESTS.md` → Sync and performance §2 and Tracker setup, `../plattform/docs/API.md` → `POST /v1/sync`,
`GET /v1/me`, `GET /v1/days/{day}`.

## D1 · Send deletions and HealthKit ids (`sync-engineer`) — gated on the changelog

- From the changelog date on, every uploaded `Sample` and `SleepSegment` carries `id` = the HealthKit object UUID
  (workouts already do). Nothing else about the page changes.
- `PendingDeletions` drains into `SyncRequest.deleted` at the start of each sync run, ≤ 2,000 per request, oldest
  first, **before** the stream pages (so a rewritten workout's old id is gone before its new id arrives). Remove an id
  from the store only after the request that carried it answered `200`; `ignored.deleted.unknown_id` is fine (already
  gone, or uploaded before ids existed). A `4xx` other than `413` on a request with deletions: send the page once more
  without them and log it; never block a sync on deletions.
- Backfill: nothing to do for old copies (the platform's one-off fold handles them). But the app must not *re-create*
  them: an anchored read never re-delivers deleted objects, and the first-sync `recentDays` path re-reads what Health
  holds now, so it's safe. Say so in a code comment with the reasoning.
- Capability check: send `deleted` only when the mirrored `API.md` version has it (the flag or the changelog gate the
  fleet uses for new fields); older platforms get the old request shape.
- Tests: ids on records; drain order and the 2,000 cap; removal only after `200`; `unknown_id` ignored; a run with
  deletions and no new data still syncs; the Garmin rewrite sequence (insert A → delete A, insert B) produces one
  workout on the mock platform.

## D2 · Provisional and final on Today, the widget and the explain line (`ios-developer`, `ui-designer`) — gated

- `DailyScore.coverage` mirrored: `sleepHrMinutes`, `hrvReadings`, `sleepSource`, `hrSourceHours`, `nightComplete`,
  `status`.
- **Provisional:** Today's hero shows the readiness number as today, with the line under the gauge
  "Provisional · based on 2 h 50 m of heart rate so far" (en + de) in place of the band/delta line, and the gauge's
  dots at 70 % opacity (with the orbit gauge: its provisional treatment; before it: `MetricGauge` dimmed as `PendingGauge`
  does). Tiles unchanged. The silent refresh push already arrives when the day is re-scored; on `final`, the line goes
  back to normal with a cross-fade.
- **When final differs from provisional by ≥ 5 readiness points**, one line for that day, dismissable, under the gauge:
  "Updated after your watch synced the rest of the night (was 61)". Never a banner, never a push. Store the provisional
  value per day locally to compare; nothing goes to the platform.
- **Explain / coverage line:** wherever the score is explained today (the explain sheet; else a tap on the band line),
  add "Based on 6 h 40 m of heart rate from Garmin Connect · 5 HRV readings · sleep from Garmin Connect". Missing
  component because of a floor: "Resting heart rate: not enough overnight data (needs 2 h)". Sources are display names
  from `User.sources` by bundle id.
- **Provenance on Today**, small, under the tiles: "HRV: Apple Watch · Sleep: Garmin Connect · HR: Garmin Connect 14 h,
  Apple Watch 9 h". Tap opens the tracker setup's sources screen (D4). Hidden when one source did everything.
- Widget: provisional shows the number with "provisional" as the status line; no coverage detail.
- VoiceOver: the status and coverage are part of the gauge's value.

## D3 · Honest in-between states that need nothing new (`ios-developer`) — ship first

- The staleness line ("Nothing new from Connect since …") gets the tracker's sync habit from `trackers.json`'s new
  `sync` field when present, else today's text: "Garmin Connect writes to Apple Health when you open it. Open it, then
  pull to refresh." Make the line a button that opens the tracker's app via its URL scheme when `trackers.json` has one
  (`garminconnect://`, `oura://`; check the file; add the schemes to `LSApplicationQueriesSchemes`).
- After a sync that touched today, while `GET /v1/me/sync` still lists today in `pending_days`, the hero's `.pending`
  state already breathes. Confirm it is used on *every* path (pull-to-refresh, background delivery, foreground return),
  not only the first morning; the review found the import path bypassed it once.

## D4 · Detect sources instead of asking (`sync-engineer`, `ui-designer`)

- Tracker setup gains a **Sources** screen: `HKSourceQuery` per type over the last 7 days, plus counts per source and
  type from the anchored reads' bookkeeping (or `HKStatisticsQuery` with `.separateBySource` for HR/steps; a count per
  type is enough). Rows: source name, icon by bundle id when known, "HR · Sleep · Steps" chips, and a warning chip when a
  tracker the user picked in setup has written nothing in 7 days, or writes no HRV ("Garmin Connect doesn't share HRV
  with Apple Health; recovery uses resting heart rate and sleep").
- The wizard's "what do you wear" step pre-selects from what is detected; the user confirms instead of choosing.
- Platform side: `User.sources[].samples_7d` is coming (Q5); when present, prefer it for the counts (it's what the
  platform actually received), with HealthKit's view as the fallback and a mismatch note ("Apple Health has HRV from
  Oura; RYFT hasn't received it yet. Pull to refresh.").
- No per-metric pinning UI yet (platform M6b); leave the seam (a disclosure per metric) in the design note, not in code.

## Tests

- D1 as listed; D2: snapshot tests provisional/final, the ≥ 5-point line appears once and is dismissable, coverage
  strings in en + de with floors; widget provisional; D3: the staleness button opens the scheme (unit test on the URL
  builder), `.pending` on each refresh path (view-model tests with the mock `GET /v1/me/sync`); D4: source detection on
  seeded HealthKit data in the simulator (a Garmin-like bundle with HR and sleep, no HRV → the warning chip), the
  pre-selection.
- UISmoke: Today in provisional state (mock), tap the provenance line → Sources screen.

## Ship

PRs: `sync: HealthKit ids and deletions` · `today: provisional scores and coverage` · `today: source provenance` ·
`setup: detected sources` · `today: tracker sync hint opens the app`. Strings en + de. `docs/API_REQUESTS.md`: close
Sync and performance §2 when the changelog answers it; add nothing new unless the platform's shape differs from the
proposal. TestFlight note: "RYFT now shows when a score is provisional and which tracker each number came from, and
duplicate workouts from a watch app are gone."

Needs-you: after the platform's one-off fold, confirm your 2026-10-20 shows one run; a screenshot of the Sources screen
on your Garmin setup for the design note.
