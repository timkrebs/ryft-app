# Notifications — review log

## PR 2 (N3, `feat/reminder-scheduler`), round 1 (0d9b463)

### security-privacy-reviewer: 1 blocker (merge gate), 4 should-fix, 7 nits
The account boundaries, the in-flight guard, the placeholders, the logging and the deep-link parsing are sound. No App Privacy change.

| # | Finding | Lead decision |
|---|---|---|
| B-1 | On `main`, the journal reminder (default on) and the local "not syncing" fallback would reach users with no in-app switch. The fallback's only switch, `SYNC_STALE`, is hidden while push is rolling out. | **Ship dark behind a remote flag, `notifications.reminders`.** Its compiled default is off. Off makes both plans `.these([])`, so turning it off removes what's scheduled. Bedtime is unaffected. N4 lands the switches; the operator then opens the flag (allow-list first). Requested in `docs/API_REQUESTS.md`. This follows CLAUDE.md: an unfinished feature ships dark behind a remote flag. |
| S-1 | The fallback fires after a deliberate consent withdrawal ("Open RYFT to bring it up to date"). | **Fix:** both local kinds are gated. Neither the fallback nor the journal reminder goes while consent is withdrawn, or while a standing `consent_required` / `invite_required` refusal holds. The scheduler watches `ConsentState`. Pausing the journal too is the conservative call: no nudge to log habits after a withdrawal. |
| S-2 | After a session expiry, A's server alerts keep arriving, and they are still there when B signs in. The CHANGELOG overclaims. | **Fix:** remove delivered in the signed-out and owner-mismatch branches (guarded by `isProtectedDataAvailable`). Unregister APNs and drop the record on every wipe reason. Reword the CHANGELOG. |
| S-3 | Below iOS 26 the wake notification is silenced while RYFT is open: `wake.*` carries no account. | **Fix:** wake requests carry `ryft.account` (and a category with a placeholder). Add a test. |
| S-4 | A user's journal "off" is lost on a session-expiry wipe, so the reminder comes back on. | **Fix:** keep `notifications.journal.<account>` through the parking (`sessionExpired`) wipe. A server field for it (Q7) is filed as NT5. |
| N-1–N-7 | Nobody signed in counts as a mismatch for server alerts; no auth or invite route from a notification; `requestedJournalDay` is forgotten on an account change; the journal read passes the real `allowed`; a wipe-wiring test; comment drift; an `isProtectedDataAvailable` guard on the teardown. | **All fixed in round 2.** |

### code-reviewer: changes requested (the blocker is the same as B-1)
The core holds: account boundaries, the in-flight re-check, coalescing, hysteresis, quiet hours across midnight and DST.

| # | Finding | Lead decision |
|---|---|---|
| B-1 check | A flag value not yet known (a background launch with no cached config) must give `.unknown`, not `.these([])`, or "unknown never removes" breaks. | **Yes.** Unknown flag → `.unknown`; known off → `.these([])`. |
| S1 | **Upgrade window.** The first launch after the update has no owner key, so all `bedtime.*` are removed. After a background launch (HealthKit delivery) nothing offers them again until the app opens, so tonight's wind-down can be lost silently. | **Fix:** with no owner key and someone signed in, read-back `bedtime.*` without `ryft.account` (only pre-N3 builds wrote them) count as bedtime's `.unknown` and stay until the planner's first offer. Compare each request's own `ryft.account` with the current account. That upgrade pass removes no delivered notifications (S-2 interplay). Test. |
| S2 | The calendar is a launch-time snapshot: a time-zone change moves nothing; the fallback fires early after an eastward trip; a pending journal reminder can escape removal; "yesterday" disagrees near midnight. | **Fix:** `.autoupdatingCurrent` in production, plus observe `NSSystemTimeZoneDidChange`. Test with the zone changed between passes. Amend design §3.1. |
| S3 | With permission denied, every pass retries up to 7 bedtime adds (a throw and a log line each). | **Fix:** no adds while `allowed == false`; removals still apply. Test. |
| S4 | STATUS's cost numbers came from a pass without the journal. The app's pass does 3+ SwiftData fetches on the main actor (unmemoized misses) and decodes settings each time. | **Fix:** memoize the misses and keep the accepted record in memory. Re-measure with the journal connected, and correct STATUS. |
| S5 | Wake silenced below iOS 26. | Same as security S-3, already decided. |
| Nits | Write the owner key only when it changes; Demo on during an add keeps the landed requests (the old `keepsTheAccounts` rule); `readYesterdayIfOwed` with the real `allowed` and on the background session; a wipe-line test; the mock's `adds` counted after the append; a vacuous `eventually`; docs wording (CHANGELOG, ARCHITECTURE §4 "after every forget", STATUS strings line); `JournalReminderStore` `@Observable` for N4. | **All fixed in round 2.** |
