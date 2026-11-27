---
name: onboarding-consent-seams
description: Existing mechanisms to reuse before adding new ones around consent, status reads and user re-reads
type: project
---
- `ScoringWord.statusCacheTime` (10 s) + `isAnswered(byStatusRequestedAt:)` already encode API.md's "GET /v1/me/sync cached 10 s per user"; reuse it for any "status may predate a local word" rule.
- `ReadScheduler.run(_:mode:storeAsked:)` hands the flight's start (a joiner gets the flight's, not its own); `ReadMode.changed(since:)` only counts flights started at/after `since`.
- `Repository.readUserBack(since:)` = one `/v1/me` asked >= since, stored; `store(fetchedUser:askedAt:)` calls `ConsentState.heard` (the hook for "a read asked after a local event decides").
- Flights await their store (Repository.swift ~1420), so a check's `await me` waits for the SwiftData commit behind the ADR 0018 drain.
- APIClient: default session vs fail-fast `backgroundSession` are separate URLSessions (separate connection pools); scheduled reads and `SettingsWrite` use the fail-fast one.
- Status gates enter through two doors: `OnboardingCoordinator.check()` (consent.refused) and `SyncCoordinator.syncStatus` (apiStatus.observe). Any gate rule must cover both.
- Today asks `onboarding.pendingGate`; Devices & sync reads `sync.pausedFor` directly (drift risk).
- Design note: docs/work/2026-11-22-consent-agree-lag/design.md; proposed ADR 0025 amends ADR 0008 (0024 = notifications) §5/§7.
