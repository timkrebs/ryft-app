---
name: project-mock-notifier-authorization
description: MockNotifier starts .notDetermined; since N3 round 2 (S3) the reminder scheduler adds nothing unless allowed, so bedtime tests' graphs must authorize it
metadata:
  type: project
---

`MockNotifier.status` defaults to `.notDetermined`, and `AppEnvironment.test()` creates one when no notifier is passed.
Since N3 round 2 (review S3, 2026-11-22) `ReminderScheduler` adds nothing while `allowed == false` (denied or not asked
yet, as iOS refuses both), so any test that expects bedtime's requests on iOS needs `.authorized`. The shared helpers
set it: `makeState` in SleepUpgradeTests and BedtimeNocturneTests, `sideGraph` in DemoDataSideTests,
`scheduleReminders` in StoreResetTests. A test about the prompt itself sets `.notDetermined` back.

**Why:** the reminder suites passed, but the full Unit plan then failed 16 bedtime tests in five files. Only the full
run found them.

**How to apply:** when a rule keyed on authorization (or any shared mock default) changes, run the full Unit plan before
committing, not only the suites you touched. Related: [[project-repetitions-and-mock-calls]].
