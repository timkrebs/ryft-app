# W3 review, 2026-11-06

Reviewed at `74d428b` by code-reviewer and security-privacy-reviewer, then re-verified at `9b6a609` by code-reviewer, by reading the code. No route publishes an account over a wipe that returned false, a held account gets no token, and flows with no debt are unchanged.

## Fixed in W3

| Finding | Fix |
|---|---|
| A wipe after a failed save can return true and leave an inserted row, so a held account could be released on it | Once a pass is refused in a process, nothing in that process ends the debt. Proved by `aTruePassAfterARefusalDoesntEndTheDebt` on the real store |
| A held recovery link lost the new-password screen | `auth.recoveringAccount`, written before `publish`, asks once at that account's next publish |
| The hold message could outlive the debt | `endDebt()` clears it when the entry ends with nobody stored |
| Each held sign-in ran a pass twice | A held account runs none after a refusal |
| A return's entry could wipe that account's live work at a launch that couldn't read it | A written `publishedOver` field, read before the `isRestoring` hold |
| A failed write of that mark would bring the wipe back | `update` reports failure, and the return removes the file |
| `auth.recoveringAccount` could ask long after the link | `apply(nil)` removes it when nothing is stored |

## Decided by the lead

- **A held B narrowing A's parked entry stays,** as an exception to Goal 3. The next launch with B stored narrows it anyway, and the approved policy says another account signing in removes them.
- **In-process release:** stopped, rather than making W6 a release condition. It matches the approved copy, "Close RYFT and open it again".
- **`!passRefused` on the published-over clear** goes beyond the ask and is right: it's the same rule.

## Release gate

W2 and W3 ship in the same build. `endsOwnSession` trusts entries written by W2 builds, so W2 alone must never reach testers.

## Moved to later tickets

- **W4:** delivered notifications, and a hold over a published A leaving A's push registration.
- **W7:** decide what a scrub owed in a process with a refused pass means. `clearTheWay` ends a scrub at any publish.
- **W9:** a durable deletion marker before the DELETE.
- **W10:** a held Sign in with Apple loses its authorization code, so the grant can't be revoked later.
- **W8:** the ADR draft's "Applies to" line, decision 1 and decision 3, and `AccountScope` in `docs/ARCHITECTURE.md`.

## Open for the user

Everything under "Open for the user" in `review-w2.md`, and:

1. **Stuck on Welcome.** Files that never go leave a sign-in held for good, including a support folder holding files, and the message says to reopen, which won't help. Deleting the app should, but that's unverified.
2. **A full disk can lose the debt.** The ledger write can fail just as the wipe is refused, so "finishes the next time you open RYFT" isn't true there. A U5 full-disk check should cover it, and it's a fifth exception for the policy wording.

The sheet for a held recovery link at the launch that publishes it is proved by value only: check it once by hand.
