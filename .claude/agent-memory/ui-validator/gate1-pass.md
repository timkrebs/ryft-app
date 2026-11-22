---
name: Nocturne gate part 1 pass (fe69399) driver notes
description: What the gate-1 validation needed beyond the PR 6 notes: ids, launch args, hosted renders, gate waits
type: reference
---
- Use scratchpad/r3/harness/ZZValUITests.swift (has tapprefix, type, list); the uiv-6c copy lacks them. Copy it into the rsync'd src, add ZZValHostedTests, one build-for-testing.
- `-RyftScreen notifications` is the reachable Notifications page in demo (profile.notifications row does not exist in demo). `-RyftScreen syncDetails` is a `.root` debug harness (no Back/Close); the real Sync details sheet: Today -> tap `today.syncLine`.
- "What do you wear?" sheet: Profile > Devices & sync > `devices.edit`. `-RyftScreen wear` is the onboarding step (no close, by design).
- My Day: `-RyftTab today -RyftOpenMyDay 0`; activity page `tapprefix:myday.view.row.activity.` then `activityDetail.menu`; workout detail `-RyftTab strain -RyftOpenWorkout YES`; live workout More = `session.more` (focused or list both fine).
- Journal sheet: Today `journal.card` (date strip). Habit sheet: Profile > journal > `journal.add`. Report typing: `report.message` then `type:`.
- Hosted (teal-free Today cards, push card, watch hint, insight tiles per metric): HostedWindow + drawHierarchy; ids `TodayView().previewEnvironment(.preview(empty:true))` (setup card), `.preview(scenario:.importing)`; hosted host is de_DE (84.213 readings is the harness).
- Pushed header at AX1+ is leading-aligned under Back (PushedHeader.stacked); SheetHeader keeps the title inline/centred until narrower than 120 pt. Known mismatch with "title under the buttons from AX1" for sheets.
- Shared-Mac gate: another agent's "RYFT CI" sim was booted for 30+ min runs; budget the wait. Kill only own pids (`ps | grep uiv-gate1`), a broad pkill/xargs kill is denied by the classifier.
- Montage: scratchpad/uiv-6c/montage out.png maxHeightPx in...; sips -c then --out into an existing dir (a missing dir turns the target into a file).
