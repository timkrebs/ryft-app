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

## Round 2 (7eb7c8c..4062619, strings ff3dc95)

The runs on HEAD (sync-engineer, after the merge with #129): Unit 7,722 passed, 0 failed; UISmoke 55 passed, 1 skipped; Release OK; 0 warnings; lint and style clean; M1–M14 killed.

### localization-editor: `HIDDEN_PREVIEW_WAKE` added ("Wake-up time")
- **Nit:** BEDTIME's hidden-preview placeholder uses the plain key "Bedtime reminder" (`PushRegistrar.swift:279`). That is also the visible Sleep toggle's label (`SleepPlannerView.swift:487`), so a change to either moves both. **Lead decision:** add `HIDDEN_PREVIEW_BEDTIME` with the same value and a "No sleep need or goal" comment, and update `PushPresentationTests.swift:19`. This goes into the fix round if the re-reviews ask for one, otherwise into N4.
- **Nit:** "Time to get up" and "Your wake time from Bedtime & wake." have no comments. Add them with N4's strings.

### security-privacy-reviewer: approve, one should-fix (APNs after an expiry)
Round 1's B-1, S-1, S-3, S-4 and N-1 to N-7 are fixed. Nothing local reaches another account or a signed-out lock screen.

| # | Finding | Lead decision |
|---|---|---|
| S-1 | **After an expiry, the next account can bring A's server alerts back.** The platform keeps A's token, because there's no session for the `DELETE`. B signs in, `registerForRemoteNotifications()` often returns the same token, and B's `POST /v1/devices/{id}/push` is refused (`403 invite_required`, offline, a 5xx). The token is live again but still A's, so A's `MORNING_SCORE` shows on B's lock screen, and B's passes can't clear it (no `ryft.account` on server alerts yet, NT1). The CHANGELOG, NT7 and the `AuthService` comment claim more than this. | **Fix in this PR, before `push.enabled` widens:** (1) the CHANGELOG, NT7 and the comment say what's true; NT7's priority goes up. (2) `refresh()` doesn't register while the account is invite-blocked. `send()` unregisters again after a non-cancellation failure when no record is accepted for this account. (3) NT7 asks the platform to drop other accounts' tokens for a device when an account authenticates with `X-RYFT-Device-ID` (or to exempt the push POST from the invite gate). It also adds the failed-DELETE-at-sign-out case. |
| N-1 | A wipe resumed after the first frame (expiry, app killed during `client.signOut()`) leaves APNs registered until a foreground frame. The comment at `AuthService.swift:956` overclaims. | **Fix:** run the notification step at launch in that branch (it touches no parked rows), and correct the comment. |
| N-2 | Wake is still silent in the foreground in Demo, below iOS 26. | **Fix:** WAKE presents when its account matches, Demo or not (its content carries no data). |
| N-3 | Delivered journal and "not syncing" notifications stay after a gate shuts. | **Fix:** with a gate known shut, `removeDelivered` for `sync.stale.1`, `sync.stale.2` and the journal ids for yesterday and today. |
| N-4 | A parked account's journal setting outlives its parked rows (UserDefaults and backups). | **Fix:** in `accountWillChange` with `to != nil`, drop the journal keys of accounts that aren't current. |
| Policy | If ryftlab.de/privacy says the push token is deleted at sign-out, an expiry is the exception until NT7. | **Needs the user:** check the policy text. |

### code-reviewer: approve, two small should-fixes
Every round-1 finding is fixed. All five departures from the brief are sound (the lock guard only where it must be, "not asked yet" counts as not allowed, Notification Center cleared once per signed-out spell, only earlier builds' bedtime kept, the background read fetching iOS's answer itself).

| # | Finding | Lead decision |
|---|---|---|
| 1 | Nothing tests the gates on the background journal read (`ReminderScheduler.swift:247-248`). Dropping them would make a journal request on every BG refresh while dark, and the suite would stay green. | **Fix:** one test with three cases (flag known off, flag not known, consent withdrawn), each expecting `api.count("journal") == 0`, plus a mutant. |
| 2 | S3 can leak for one pass: app active or the offer sets `authorization = nil` while a pass waits on `delivered()`, and the pass resumes with `allowed == nil`, so bedtime adds are tried. | **Fix:** the pass copies `allowed` into a local once, right after reading it. Test. |
| 3 | `forgetAccount` runs on every Demo switch and sign-in, not only in the wipe's turn; harmless. | **Fix the comment,** and add a wiring test. |
| 4 | Docs drift: design.md §3.4:194, §3.2:169, §9.1; ADR 0024:48 and Consequences; STATUS:34. | **Fix:** text alignment only, no new decisions. |
| 5 | "M1–M14 killed": M1–M6 are from round 1. | **Re-run M1–M6 on HEAD** with round 3. |
| 6–7 | Untested: the unlock retry (through `ConsentState.reload()` → `revision`), the offer's re-read (`:151`), the `clearedSignedOut = false` reset (`:334`). | **Fix:** three small tests. |
| 8 | Device step: sign out and sign in as another account without relaunching; `didRegister` fires again and a server alert arrives. | **Into STATUS's device steps.** |

## Round 3 (8a95823..538ea17, strings c45fa70)

Final local run on 538ea17 + c45fa70:
- **Build:** strict, 0 warnings.
- **Unit:** 7 736 passed. One `eventually` timeout at load 400 (`TodayPendingPathTests/pullToRefreshShowsTheNightBeingScoredUntilItLands`) passed 3/3 alone.
- **UISmoke:** 56 tests, 0 failures.
- **Release, lint, style and strings:** all clean.

The catalog lacked `HIDDEN_PREVIEW_BEDTIME`; c45fa70 adds it by targeted insertion only.

### security-privacy-reviewer: approve, S-1 and N-1 to N-4 closed, three nits
- **Nit 1 (fix in round 4):** a sign-out while the push POST is out. The success branch saves the record without checking the account (`PushRegistrar.swift:155`), so the token stays under the account that left. Don't save when the account changed. Add the case to NT7's failed-DELETE bullet.
- **Nit 2 (fix):** pass `ScreenModels`' `apiStatus` to `PushRegistrar` (`ScreenModels.swift:84`).
- **Nit 3 (fix):** STATUS still says `HIDDEN_PREVIEW_BEDTIME` waits for the catalog.
- **Needs the user:** the ryftlab.de/privacy push-token wording (already on the list).

### code-reviewer: approve, every round-2 item closed, one should-fix
- **Should-fix (fix):** nothing calls `refresh()` when the invite gate opens (`RyftApp.swift:444`). An account that redeems its code has no APNs registration until the next app active. Call `screens.push.refresh()` when `BootstrapKey.inviteBlocked` flips to open, with a test.
- **Nit 1 (fix):** docs drift.
  - `STATUS.md:22` and `:39-40`, `ARCHITECTURE.md:588-589` and `AppDelegate.swift:15-16` still say every local notification is hidden in Demo; WAKE is the exception.
  - ARCHITECTURE's push "Registering" bullet doesn't mention the invite-gate hold or the unregister after a refused POST.
- **Nit 2 (fix):** the launch repair in `AppState.bindAccountHooks` (`:437-440`) drops other accounts' journal keys too (`JournalReminderStore.wipe(keeping:)`).
- **Nit 3 (fix, test only):** the `account == self.account` guard at `PushRegistrar.swift:171`. The account changes while `registerPush` is in flight and the POST fails, and B stays registered.
