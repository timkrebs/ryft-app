# W2 review, 2026-11-06

Reviewed at `927be85` by code-reviewer and security-privacy-reviewer, both by reading the code. Neither found a new route for one account's data to reach another, or a way to delete a live store in a W2 and W3 build.

## Fixed in W2

| Finding | Fix |
|---|---|
| A retry skips `ReadinessSnapshot.clear()`, so a score can stay in the widget after the debt is done | Clear it in the store step, first, with a test on the refused-then-retried path |
| `finishOwedWipe` can run over a session the Keychain hasn't been read for, when the entry first reads after unlock | Guard on `client?.currentSession == nil`, with a test. A session this launch is ending doesn't count. W3's held session is covered: the retry waits, as `apply` and the next launch handle it |
| An interrupted sign-out clears the entry before `client.signOut()` runs | Keep the entry until `client.signOut()` has run, for a wipe at launch and for one at the first frame |
| The replace's outcome is dropped: leftover files or a refused guard look like success | Failures, in the store or the app-container copy, keep the entry, a scrub's too. They reach `AuthService` as `WipeLedger.storeStepLeftFiles`, not through `TrainStore.wipe`, because a scrub has no wipe. A refused guard logs an error |
| The live configuration's file name and the `.task` body aren't tested | A test on the live URL, and `AuthService.finishOwedWipe(train:bedtime:)`, which both sites call. The compaction closure is now async, so its task ends after the wipe |
| The design says A's reminders stay until the next account change, and I2 and the ADR draft miss `.forget` | Design corrected |

## Decided by the lead

- **A launch with no scene:** no extra line in `RyftApp.init`. Reminders and alarms go at the next foreground or background refresh through `planTonight`, and they hold no health values.
- **A UI test with a planted entry:** not in this PR. The planted-entry run by hand is repeated on the final head and goes in the PR body.
- **`TrainSyncService.accountChanged()` crash:** it's live on `main`, and W2 fixes it. If a build has to go out before W2, the one-line change can be cherry-picked.

## Release gate

W2 must not ship without W3. Until W3, a build can publish an account over an entry, and the next launch would then replace live work. No TestFlight build from `main` until W3 is merged.

## Moved to later tickets

- **W4:** delivered notifications are never removed, so a morning score can stay in Notification Center. Add it to W4's device steps.
- **W4 in the same build as W2 and W3:** kept in the plan as a release question, since the widget fix now sits in W2.

## Open for the user

1. **A kill during an account deletion** leaves no entry, because the first `begin` follows the server call, so the deletion later reads as an expiry. Already on `main`. Needs a new ticket: a deletion marker written before the DELETE.
2. **After an expiry with a lasting refusal,** everything of the account stays up to 30 days, not only the parked rows. Widen the policy wording, or add a recovery.
3. **Demo mode** shows the tabs without a sign-in, and Train isn't in memory under demo, so a pending wipe's sessions can show. W3's hold doesn't close this. Show Welcome while a wipe is owed, or turn demo off in a wipe.
4. **"The next time you open RYFT"** means the next start, not a return to a running app. The approved wording may need "starts".

Items 1, 2 and 4 each touch the policy text, so they need an answer before W8 fixes the one policy version.
