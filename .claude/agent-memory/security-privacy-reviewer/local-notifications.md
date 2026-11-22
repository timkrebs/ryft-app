---
name: local-notifications
description: ReminderScheduler (ADR 0024, N3) account/lock-screen model, where to look, and the gaps found 2026-11-22
type: project
---
Where: Ryft/Push/ReminderScheduler.swift (one writer; pass() captures gen+AccountBinding+store epoch, current() after
every await, break before each add, landed removed if owner changed; passes serialized via running/again, so A's
post-check removal can't hit B's adds even though ids (journal.<day>, sync.stale.1/2, bedtime.<day>) are not per account).
ReminderPlans.swift (pure plans, ReminderCopy static words), JournalReminderSettings.swift (UserDefaults
notifications.journal.<uuid>, default ON 09:00, wipe by prefix), PushRegistrar.swift (PushCategories.placeholder for 7
ids, options [], PushPresentation.accountMatches/options/route), AppDelegate willPresent/didReceive use them.
Wipe: AuthService.wipeSharedLocalData `before` step -> ReminderScheduler.wipe(UNUserNotificationCenter.current()) =
removeAllPending + removeAllDelivered + owner key + journal keys; AlarmKitWake.cancelAll. storeOnly retry == device step
already ran (deviceStepsDone). forget() via AppState forgetters (onWipe, same turn; also reset() on Demo flip).
Owner key notifications.owner = auth.accountID (Supabase UUID; "apikey" DEBUG). Mismatch/nil -> tearDown (PENDING only).

Gaps found N3 review (wt-n3 @ 0d9b463):
- No in-app off switch in N3 for journal reminder (no JournalReminderStore.set caller) nor for the local SYNC_STALE
  fallback when push.enabled off (page = rollingOut, no switches). Ranked blocker as merge gate (flag or land with N4).
- Fallback ignores ConsentState: after a withdrawal sync.stale.* still fire ("Open RYFT to bring it up to date").
- Session expiry skips beforeSignOut (AuthService ~633 reason == .user): push registration + APNs stay; A's server
  alerts keep landing and survive B's sign-in (owner-mismatch branch removes pending only). Suggested removeAllDelivered there.
- wake.* (iOS<26) has no ryft.account -> willPresent [] (foreground alarm silenced). Functional.
- Journal "off" lost on any wipe -> back ON (only default-on device pref).
- 'always matches' for server alerts w/o account: acceptable; nit to treat currentAccount == nil as mismatch.
- PushPresentation.route still lets ryft.url reach .authCallback (pre-existing).
