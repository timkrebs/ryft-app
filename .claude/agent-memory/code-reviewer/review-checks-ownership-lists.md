---
name: review-checks-ownership-lists
description: RYFT review checks for "which rows are X's" marker lists in UserDefaults (P1b demo exit, 2026-11-18) - marker written after the row, pruning against a fallback store, unobserved view reads, pre-upgrade rows, ADR amendments left describing dropped work
metadata:
  type: feedback
---

From the P1b review ("ending the demo discards its workouts", PR #121, 2026-11-18), by reading:
- **Marker after the row.** `TrainCoordinator.start` lists the id, but every `SessionFactory` call has already saved the
  row. A crash in between leaves an unlisted row, which is exactly the leak the list exists to stop. Ask for the marker first,
  then the row: a stale id is harmless, a missing one isn't.
- **Pruning against "what the store finds"** also runs on `TrainStore`'s in-memory fallback (`lostItsFile`), which finds
  nothing, so it empties the list. The file then opens later with the rows still in it. Prune only ids that were found and
  deleted, or skip pruning when the store isn't its file.
- **Body-time reads of UserDefaults or a SwiftData fetch aren't observed.** A hint or count computed in `body` from them goes
  stale until something else re-renders (tab content isn't rebuilt on selection). It also costs one fetch per render.
- **Rows from before the list existed** aren't on it. Ask for a STATUS/CHANGELOG note or a one-time migration.
- **A decision dropped mid-branch** leaves "Amended by" lines in *other* ADRs describing the dropped work (ADR 0018 still
  said the container is reopened), and the minimum-OS wording may drift (18.0 vs 18.6).
- Account data safety held up: one writer (`start`), checked against `owner()` at creation, and `resume` never lists.
  Check this first next time.

Fix-round re-review (8763ed5, 2026-11-18), by reading:
- **Fail closed needs a visible state.** `endDemo` returning early on a refused discard changes nothing observable, so the
  switch's custom Binding never re-renders: the flipped switch can show off while Demo data stays on, and nobody is told.
  Ask for an observable error on the model, which also snaps the control back.
- **A "nil = nothing to confirm" getter that also means "couldn't read"** lets a transient failure skip the dialog
  and the next read discard without asking.
- **One-time seeds:** check every branch that sets the done flag. Here the flag is set on a launch whose store
  is the fallback, if Demo data reads off (a pre-unlock launch), so the seed can be lost. A seed keyed on "demo on" misses
  upgraders who were signed out with Demo data already off. The account-safety invariant held: `auth.lastUserID` is
  removed only after a successful wipe (`AuthService.wipeLeaving`).
- Moving a shared mock from an actor to a lock: check that no `await` runs inside `withLock` and that locked calls never nest.
  Then ask who else shares `.shared`: unit tests use `MockPlatformAPI()`'s default.

**Why:** the PR's tests (list, discard, held 409, account kept, sweep) covered none of these. **How to apply:** any
"remember which rows came from mode X" design. See [[review-checks-undo-windows]], [[review-checks-file-cleanup]],
[[review-checks-tokens-dark-only]] (mid-branch ADRs).
