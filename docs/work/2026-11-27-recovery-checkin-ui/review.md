# Review — recovery check-in UI

One code-reviewer pass on the Codex draft (`3d172e2`), read-only. Verdicts by ios-lead.

| # | Finding | Severity | Decision |
|---|---|---|---|
| 1 | Editing a check-in in another time zone rebuilt its times on the device clock, moving them silently (Berlin → New York: 6 h) | blocking | **Fixed.** One clock rule (`SleepDialMath.clock(ofCheckinOffset:wakeTime:current:)`): the device zone when it had the stored offset at the wake, else the fixed offset. The sheet reads, composes and sends on it; answers alone send the stored instants. Test `editInAnotherTimeZoneKeepsTheTimes`. |
| 2 | DST night: bedtime shown/sent on the wake's offset (23:00 CEST shown as 22:00) | should | **Fixed** by the same rule (device zone when it matches), card too. Test `checkinClockFollowsTheStoredOffset`. |
| 3 | A `404` on a live save dropped the answer | should | **Fixed.** Kept in the outbox (not counted as `saved`), sent once the status answers again. Test `a404OnSaveKeepsTheAnswer`. A flag flip to off mid-request still ends the save (CancellationError): rare, the sheet stays open with its draft only if the user hasn't closed it. Follow-up. |
| 4 | The consent copy changes with the flag off | should | **Kept, by the brief.** The brief asks the consent text to cover what the user types *before* the flag goes on, with nothing bumped server-side; platform #252 (R12) asks the same and bumps the policy version itself. Copy is neutral ("Where it's available to you…"). |
| 5 | Consent-held answer said "sent when you're online" while online | should | **Fixed.** `CardState.waitingForConsent` with its own line (en + de). |
| 6 | Device zone ≠ account zone: the sheet uses `status.date` (the account's today) on the device clock | should | **Follow-up.** The contract defines `date` as the account's today and `{date}` as the wake time's local date; they differ only while the account timezone lags a trip. Recorded in STATUS open items. |
| 7 | A load started while consent was missing is joined by the gate-opened load, so the retry waits for the next trigger | nit | Follow-up (the next scene-active or Today appearance sends it). |
| 8 | UI test depended on the wall clock (drag before 06:55) | nit | **Fixed.** The wake pre-fill never starts in the future (ios-lead change, `prefilledWake`, tested), so the test needs no drag. |
| 9 | Demo Train never sets `workout_id`, so the summary's RPE row can't show in Demo | nit | Accepted: the row shows only with a real `workout_id`; covered by `SessionRPEModelTests`, device checklist item. |
| 10 | CLAUDE.md on main vs the main checkout disagree on German | nit | `origin/main`'s CLAUDE.md requires English + German; followed. |

Invariants the reviewer confirmed: flag off sends nothing and shows nothing (store, env, APIClient re-check, Train summary,
app hooks); wearable wins; queue never double-sends, is per account, expires at 14 days; `consent_required` reported once;
analytics carries tokens only; every new string has German; no diagnostic words.
