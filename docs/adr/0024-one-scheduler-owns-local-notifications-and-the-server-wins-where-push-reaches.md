# 0024 — One scheduler owns RYFT's local notifications, and the server's "not syncing" wins where push reaches

- Status: accepted (2026-11-22, N0 of `docs/work/2026-11-22-notifications/plan.md`; lead decisions there)
- Deciders: ios-lead; proposed by ios-architect; sync-engineer builds it (N3). Q1, Q2 and Q4 of the design note are the
  user's and the security-privacy reviewer's to confirm.
- Designed in `docs/work/2026-11-22-notifications/design.md` (§2, §3, §5.2, §9).
- Applies to: `Ryft/Push/ReminderScheduler.swift` (new), `Ryft/Push/ReminderPlans.swift` (new),
  `Ryft/Environment/Seams.swift` (`Notifier`, `MockNotifier`), `Ryft/Features/Sleep/SleepPlannerViewModel.swift`
  (`BedtimePlanner`'s reminders, `SystemWakeAlarms.cancelAll`), `Ryft/Auth/AuthService.swift`
  (`wipeSharedLocalData`, `finishOwedWipe`), `Ryft/Push/AppDelegate.swift`, `Ryft/Push/PushRegistrar.swift`
  (`PushCategories`), `Ryft/Sync/ScheduledWork.swift` (the old `ReminderScheduler` goes), and every future local
  notification kind
- Relates to: ADR 0020 (the wipe; a notification is a lock-screen surface), ADR 0013 (one owner per fact)

## Context

- RYFT's notifications come from two places. The platform sends `MORNING_SCORE`, `SESSION_SCORED`, `PR` and `SYNC_STALE`
  over APNs behind `push.enabled`. `BedtimePlanner` writes local `BEDTIME` requests and enumerates
  `pendingNotificationRequests()` on every reschedule.
- Two more local kinds are coming: a daily journal reminder, and a "not syncing" reminder that moves forward with every
  successful sync. Without a rule, each would get its own writer, teardown, account and demo rule, and quiet-hours
  logic. Sign-out would then be three paths to get right, and a sync every few minutes would cost three enumerations.
- iOS keeps 64 pending requests per app and drops the rest silently. Nothing of RYFT runs when a notification is shown
  (no Notification Service Extension), so a wrong request can't be caught at delivery. It has to never be pending.
- The platform's `SYNC_STALE` reaches a force-quit app, because alert pushes don't need the app. It also sees a case the
  phone can't: the app syncs, but no heart rate or steps arrive. The phone alone sees whether it synced, and reaches the
  user when push can't (the flag is off, or nothing is registered).

## Decision

1. **One writer.** `ReminderScheduler` (`@MainActor`) is the only code that adds or removes RYFT's local notification
   requests (prefixes `bedtime.`, `journal.`, `sync.stale.`). Each kind is a pure plan returning a `ReminderWish`. The
   scheduler diffs the wishes against its ledger of what it put on iOS, and adds and removes only the difference, one
   pass at a time.
   - `BedtimePlanner` keeps the planning (the plan, the 10-minute rule, its owner and demo rules) and hands its requests
     to `offerBedtime`. `WakeAlarms` stays a separate seam: alarms are AlarmKit on iOS 26+. Its notifications below 26
     count against the budget.
   - iOS is read back (`pending()`) once per process, at the first pass. A pass that changes nothing makes no system
     call. The budget for the scheduler's kinds is 32 (19 at most today, wake included).
2. **Unknown never removes.** A kind whose inputs aren't known yet is left exactly as it is, as in a background launch
   before the journal's catalog is read or before the planner's first pass. Only a known wish removes.
3. **Accounts.**
   - The sign-out wipe removes every pending and every delivered RYFT notification, synchronously, in
     `wipeSharedLocalData`'s device step, without reading `AppEnvironment.live` (ADR 0020's rule). AlarmKit's alarms
     go in the same step.
   - The scheduler forgets its ledger and cancels its pass in the wipe's turn.
   - Every pass re-checks the owner (`AccountBinding` and the store epoch) after each await.
   - Each launch's first pass removes ours when `notifications.owner` isn't the current account.
   - Demo data freezes the account's requests, adding, moving and removing nothing, as `BedtimePlanner` already does.
   - A local request carries `ryft.account`. A mismatch isn't presented in the foreground, and its tap opens Today.
4. **Quiet hours** (`User.notifications.quiet_hours`, cached with the user, used offline as last fetched) move the
   journal reminder to their end and the not-syncing reminder to the first allowed minute inside 09:00–21:00. They
   **don't** hold the bedtime reminder or the wake alarm. Those are timers the user set for that minute, and the default
   window (22:30–07:00) would silently hold most bedtimes until the morning.
5. **"Not syncing" has one switch and one delivery path at a time.** `SyncStaleRoute.decide` gives `.off` when
   `categories.SYNC_STALE` is off. It gives `.server` when `push.enabled` is on, notifications are allowed and this
   account's push registration was accepted. Otherwise it gives `.thisIPhone`. The local reminder exists only for
   `.thisIPhone`. It fires 20 h after the last successful sync (the server's threshold), again at 72 h, and moves only
   when the new time is at least 1 h later.
6. **No notice at termination.** A suspended app swiped away runs no code. A running one can't tell a force-quit from a
   system termination, and has seconds at most. The moving reminder is the mechanism.

## Consequences

**Good:**
- One place answers "what is pending and whose is it". Sign-out is one synchronous call, and no reminder survives for
  the wrong account. Previously delivered alerts with health values leave Notification Center at sign-out, too.
- Rescheduling on every sync is free in the common case: no enumeration, and at most one `add` per hour of syncing.
- A new local kind is one pure plan, one prefix and one row in the budget.
- The user never gets two "not syncing" notifications for one gap, and the server keeps the case only it can see.

**Costs:**
- `BedtimePlanner`'s reminder writes change hands. The planner's tests are the regression net, and their assertions
  don't change.
- The local fallback trusts the app's belief that push reaches. A token the platform dropped without telling the app
  means neither path fires. That is rare, and the opposite of a duplicate.
- Quiet hours mean two things on the page, one for news and one for the user's own timers. The page has to say so in
  one line.
- One more per-install key (`notifications.owner`) and one per-account key (`notifications.journal.<account>`), both
  wiped.

**Rules:**
- No code outside `ReminderScheduler` calls `Notifier.add` or `removePending` for a local request, and none calls
  `pending()` on a hot path.
- A new kind declares its prefix, window and maximum, and its plan returns `.unknown` until its inputs are known.
- A notification is a lock-screen surface: once W4a's ledger gate exists, the scheduler asks it before adding.
- No local request puts a health value in its title or a habit name anywhere. Categories set a
  `hiddenPreviewsBodyPlaceholder` and never `.hiddenPreviewsShowTitle`.

## Alternatives

- **Each feature schedules its own.** Three teardowns, three account rules, an enumeration per reschedule, no shared
  budget.
- **The wake alarms in the scheduler too.** AlarmKit is another system with its own seam; nothing would be shared.
- **Both "not syncing" paths, the local one later (a backstop).** Two notifications in the commonest outage, a
  force-quit with push working, since the phone can't see that the push arrived.
- **The phone turns the server's `SYNC_STALE` off and keeps only its own.** It loses "syncing, but nothing from the
  watch", and changes a server preference the user didn't touch.
- **Quiet hours for every local kind.** A working bedtime reminder would stop arriving at bedtime for anyone with the
  default window.
- **A repeating daily trigger for the journal** (the old `ReminderScheduler`). It can't skip a day that is already
  answered.
