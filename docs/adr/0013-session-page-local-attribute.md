# 0013 — The live session's page is a local-only attribute on the session row

- Status: accepted (2026-11-04, focused session D2, `docs/work/2026-11-04-focused-session/architecture.md` §1, §6)
- Deciders: ios-lead, on ios-architect's proposal (`plan.md`, L10)
- Applies to: `LocalSession.currentExerciseID`, `SessionController+Page.swift`, `SessionPage.swift`,
  `TrainOutboxSchemaUpgradeTests`

## Context

The Focused session layout shows one exercise per page. The page must come back after a relaunch and after a controller
rebuild, which is routine: minimising a session drops its controller. Reorder, remove and replace move indices, so L10
stores an exercise id. A swipe is not an edit: it must not reach `updatedAt`, the outbox or the platform.

`SessionController` keeps its UI state in memory (`collapsed`, `userExpanded`), which doesn't survive a rebuild. The
alternative to a stored attribute is a per-session entry in `Settings`. `TrainStore` has no versioned schema: an attribute
that fails to migrate sends the app to an in-memory store, and the user's local sessions seem to vanish.

## Decision

1. **`LocalSession.currentExerciseID: UUID?` holds the page.** It is optional, with no default.
2. **It is local only.** It isn't on `wire`, `SessionMerge` and `apply` never name it, and a change is saved with
   `store.save()` alone, never `sessionChanged`. `restEndsAt` is the precedent.
3. **It is written in one place** (`SessionController.showPage`), and only in the Focused layout.
4. **What is shown is resolved, not stored:** the row if it exists, else the first exercise with an open working set, else
   the last one. A nil value is pinned once when the screen appears, so the page never moves by itself.
5. **It is never cleared.** The value stays on the completed row, unread (`activeSession()` fetches in progress only, and
   `apply` never moves a session back), and goes with the row. Clearing it would flip the page behind Finish's wait or
   during the dismissal, so `pinPage()` also stops once the session has ended.
6. **Every new attribute of this kind extends `TrainOutboxSchemaUpgradeTests`** in the PR that adds it.

## Consequences

- The page's lifetime is the row's: discard and `TrainStore.wipe()` need no extra code, and no key is left in defaults.
- A page change costs one main-actor `context.save()`: 1 ms median, 10 ms at worst on a simulator with a one-model store.
  If that hitches on a device, the save moves to `pause()`; the attribute stays.
- Writes land at the halfway point of a swipe, where the pager reports them, so a drag and back saves twice.
- An upgrade from a build before this attribute is covered: nil resolves, then pins.
- Other in-memory session UI state stays in memory (`tappedSet`, `expandedWarmups`, `collapsed`). A rebuild resetting those
  is fine; only the page was asked to survive one.
- The server never learns the page, so a session continued on another device starts from the fallback.
- When the List layout goes, `showPage`'s layout guard goes with it. The attribute stays.
