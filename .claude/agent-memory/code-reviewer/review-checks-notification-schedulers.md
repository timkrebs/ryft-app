---
name: review-checks-notification-schedulers
description: RYFT review checks for local-notification schedulers (N3 ReminderScheduler, 2026-11-22) - stored Calendar.current snapshots vs time-change passes, owner-key teardowns on upgrade hit by HealthKit background launches, denied-permission add retries breaking "zero system calls", costs measured on unwired rigs, id-only local requests (wake.*) silenced by an account check, default-on kinds shipping before their switch
metadata:
  type: feedback
---

From the N3 review (read-only, no build, 2026-11-22). The suite and the mutants M1–M7 were green, and none of these had a test:
- **A stored `Calendar = .current` is a snapshot, and its time zone never changes.** `DayFormat` and the tests' `local` use
  `.autoupdatingCurrent`. A scheduler that keeps `.current` from launch turns its `significantTimeChangeNotification` pass
  into a no-op. Floating triggers then fire off by the zone offset (an eastward trip fires "not syncing" early), and
  `fireDate(in:)` marks a still-pending request as fired, so it drops out of the ledger and escapes a later removal.
  Grep `calendar: Calendar = .current` in stored properties and inits.
- **An owner-key teardown removes everything on the upgrade launch** (no key yet). Ask which process makes the first pass.
  The HealthKit observers and the `lastSync` watch are installed in `RyftApp.init`, so a background delivery runs a pass
  with no scene modifiers. Bedtime is offered again only from the scene or the BG refresh, and its offer waits for
  `api.sleepPlan` on the default session (`waitsForConnectivity`, a 300 s resource timeout). Before the upgrade, no
  request carried `ryft.account`, so adopting those requests is safer than a blanket teardown.
- **"Zero system calls for a pass that changes nothing" needs a denied-permission check.** A known wish that iOS refuses
  (`notificationsNotAllowed`) stays out of the ledger and is tried again on every pass, not only at the next app active.
- **Measured costs: check what the rig wired.** "First pass: 2 adds" meant the journal wasn't connected. The app's pass
  also ran `JournalStore.cachedDay`, whose misses aren't memoized, plus `persistence.document`: SwiftData fetches on the
  main actor on every sync.
- **A foreground check keyed to `userInfo` silences every local request without it.** `wake.*` below iOS 26 has no
  `ryft.account`, so `willPresent` returned `[]`. List every writer of local requests, not only the scheduler's kinds.
- **A default-on kind whose switch is in the next PR** violates "unfinished ships dark" if main is released in between.
- A docs commit can land during the review (here: the security review's log and an `API_REQUESTS` flag request). Read
  `git log` again before reporting, and point out overlaps instead of filing the same finding twice.

**Why:** these needed the launch wiring, the `Foundation` calendar semantics or the rig's inputs, not the diff.
**How to apply:** any PR that schedules local notifications, owns a ledger of system state, or claims costs and call
counts. See [[review-checks-side-effect-passes]], [[review-checks-mutant-evidence]], [[review-checks-control-holds]].
