# Widget / Live Activity privacy model (RYFT) — as of PR 6 C (2026-11-19)

- Snapshot: App Group `group.dev.timkrebs.ryft`, `readiness.json`; written with
  completeFileProtectionUntilFirstUserAuthentication + isExcludedFromBackup (Repository.swift ReadinessSnapshot.publish).
  Holds readiness, previousReadiness, baselineNights, updatedAt, bedtime, orbit (recovery, sleep perf, strain).
  `sharesWithWidget` = demoOverride == nil, so test/preview envs never write it.
- Concealment: Shared/WidgetLook.swift `WidgetConcealment` (.none/.locked/.placeholder). When hidden, every family
  computes constants only ("00", "Readiness", tracks, no bedtime/age, VoiceOver "Readiness") — robust even if
  privacySensitive misbehaves. Unit-pinned in RyftTests/WidgetNocturneTests.swift.
- Gallery (getSnapshot isPreview) shows the REAL latest snapshot since PR 6 C; synthetic only when none. Gallery is
  only reachable unlocked -> acceptable.
- Live Activities: rest timer session title + "Next:" line are privacySensitive; whether iOS redacts Live Activity
  content on a locked device is a device check (never verified). Snooze activity shows no personal data.
- Bedtime reminder body includes the sleep need; category BEDTIME has hiddenPreviewsBodyPlaceholder (PushRegistrar).
