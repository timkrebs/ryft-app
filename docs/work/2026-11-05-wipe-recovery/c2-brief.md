# C2 and the wipe: which policy sentences depend on which app tickets

**For:** head-architect, for the platform's next privacy version (C2). The app never edits `../plattform`.
**From:** the app fleet, 2026-11-18, with #107 (W2 + W3). Sources: `rebaseline-2026-11-18.md` §4, `design.md` §8,
ADR 0020. Wording is the user's as controller; this is not legal advice.

## The sentences

As the user decided on 2026-11-05 (U1 items 1 to 4, item 4 without its backup sentence), and confirmed on 2026-11-18:
no sentence for the rare residual cases (a full disk, a kill during a deletion), and old device backups aren't
mentioned, because External testers only ever get builds with W7. Placement is a suggestion against `2026-10-26`.

1. **§3, the end of the sentence on an unsent import**, replacing "signing out or deleting your account removes it at
   once.":

   > signing out or deleting your account removes it from your iPhone, normally at once; if RYFT can't finish or is
   > closed, it finishes the next time you open RYFT.

2. **§6, a new bullet on the iPhone:**

   > If your session ends without you signing out, activities and sleep entries not yet sent stay on your iPhone for up
   > to 30 days so you can sign in and send them. Another account signing in removes them.

3. **§6, right after it:**

   > These limits are applied by the app. If you don't open RYFT, the data stays on your iPhone until RYFT next runs or
   > you delete the app.

4. **§6, after that:**

   > Deleted data can remain in unused parts of the app's storage until RYFT next starts while signed out, or when you
   > switch accounts without closing RYFT, until that space is reused. It's not visible in the app.

## What makes each one true

| # | Depends on | Without it |
|---|---|---|
| 1 | **W2** (an owed wipe finishes at the next start, before the store opens), **W3** (no other account is signed in over it), **W4a** (nothing of the leaving account is written to the widget while the wipe is owed) | A failed wipe isn't finished by itself (W2), a second account could read the first one's data (W3), or the leaving account's readiness can come back on the lock screen after a refused wipe (W4a) |
| 2 | Nothing new: parking since #93's base. That deleting the app removes the App Group container is assumed (U5, a device check) | — |
| 3 | Parking, and W2's 30-day limit counted from the first attempt (`since`) | — |
| 4 | **W7**: the scrub, which replaces the files at the next start signed out, for its first clause; and the backup exclusion of `Train.store` and the ledger, which is why the sentence can stay silent on backups | The first clause is false, and a device backup can keep a copy the text doesn't mention |

**W2 and W3** are in #107. **W4a** and **W7** are separate PRs from `main`, after #107; neither is started.

## Timing

- C2 goes into force with the External build that carries **W2, W3, W4a and W7**: not earlier, because the text would be
  false for the builds before it, and not later, because testers would consent to the old text.
- That matches the plan's order: the wipe set reaches `main`, then C2 goes into force, then #109 merges, then the
  External build. Internal nightlies before that carry part of the set; C2 isn't in force for Internal testers yet.
- Head-architect to confirm that the platform's runbook step 15 ("before any tester") can hold C2's effective date to
  the External build's release day.

## Not covered

Residual cases the text stays silent on, recorded in `review-w2.md` and `review-w3.md`. The user decided on 2026-11-18
that these get no sentence:
- a kill during an account deletion, which reads later as an expiry (W9, after the launch);
- a full disk, which can lose the debt, and files that can't be removed, which keep a sign-in held;
- the demo over an owed wipe, which shows the leaving account's sessions (W11, after the launch).

These two follow from keeping the four sentences as decided:
- after an expiry with a lasting refusal, all of the account's data stays up to 30 days, not only the parked rows;
- "the next time you open RYFT" means the next start, not a return to a running app (`review-w2.md` 4).
