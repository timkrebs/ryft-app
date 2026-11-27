# Notifications: code facts (N0, 2026-11-22; ADR 0024)

- "Successful sync" = the one write `settings.lastSync = env.clock.now()` in `SyncService.run()` (past gates, upload done,
  not locked/paused). Silent push and `.daysChanged` don't reach it. `Settings.lastSync` is global, cleared by
  `clearPerUserState` in the wipe.
- `BedtimePlanner` (Features/Sleep/SleepPlannerViewModel.swift): one-shot `bedtime.<wakeDay>` x 7 nights, calls
  `pendingIDs()` on every reschedule; wake alarms = AlarmKit on 26+, `wake.0..6` repeating notifications below.
  The old `ReminderScheduler` in Sync/ScheduledWork.swift has no caller (one test only).
- Background launches: SwiftUI `.onChange` modifiers don't run; side effects for BG paths go through
  `BackgroundWork.register` closures or `ObservationWatch` (App/ObservationWatch.swift).
- Wipe: `AuthService.wipeSharedLocalData` (static, main) must not read `AppEnvironment.live` (ADR 0020 rule);
  `storeOnly` retries skip device steps, so per-launch reconciliation is needed for anything device-side.
- Quiet hours live in the cached user (`Repository.user()`), available offline and in BG launches.
- iOS with previews hidden shows only the category placeholder (no title) unless `.hiddenPreviewsShowTitle`.
- ARCHITECTURE.md drift seen: §4 ReminderScheduler line; §7 "en and de" loc-keys (CLAUDE.md: English only).
