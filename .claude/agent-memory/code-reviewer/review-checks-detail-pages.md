---
name: review-checks-detail-pages
description: RYFT review checks for pushed list/detail pages (Nocturne T6B.5 History, session detail, exercise page, 2026-11-19) - try? loaders feeding "none yet" copy, re-reads that drop shown data, counts over windowed lists, plural keys in shots, two roundings of one number, per-kind pages, macOS probe limits
metadata:
  type: feedback
---

Found in the T6B.5 review (read-only, 2026-11-19); the suite and shots were green:
- **Swallowing loaders feed "nothing yet" copy (recurred, see [[review-checks-screen-loads]]).** `TrainLibrary.sessions()` returns
  the cache or `[]` on any error; `history(for:)` returns nil. With no cache, offline/5xx/429 shows "No workouts logged yet." and
  "No sets logged for this exercise yet." For each empty sentence, trace the loader to its `try?` and ask "failed or empty?".
- **A re-read that overwrites shown data.** `session = await library.session(id:)` with no `?? session`: `.task` without an id
  re-runs when a pushed page pops (iOS), so offline the exercise cards turn into the failure line. Compare with sibling VMs
  (`ExerciseDetailViewModel` had `?? history`).
- **Counts over a windowed list** ("25 workouts" from `sessions(days: 90)`) read as totals; importers with years of data think it
  is lost. Also check the first paint's source has the same window (`cachedSessions()` had none).
- **Plurals:** grep each new `%lld` key in the catalog for `variations`; then look in the after-shots for "1 sessions".
- **Two roundings of one number on a page:** `E1RM.rounded` (0.5 kg) in a row vs the API's one decimal in the hero/records.
  Mocks rounding differently from API.md made a declared deviation look like a real choice (93.3 vs 93.5).
- **Per-kind pages:** an e1RM page opened for time/distance/unloaded bodyweight exercises (API sends no points) says
  "log it twice". Enumerate `LoadType` for any metric-first page.
- **Probe limit:** macOS `NavigationStack` does not call `onDisappear` on the covered root (probed), so push/pop lifecycle
  claims need an iOS hosted test, not the swiftc probe.
- Check file mtimes against the after-shots folder (ExerciseDetailView changed 90 s after the shots, no logs).

**Why:** none of these was covered by the tests; most needed the shots or the library's loaders. **How to apply:** any pushed
list/detail page or "honest states" ticket. See [[review-checks-screen-restyles]], [[review-checks-list-rewrites]].
