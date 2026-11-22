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
