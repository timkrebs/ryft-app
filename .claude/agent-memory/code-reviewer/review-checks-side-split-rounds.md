---
name: review-checks-side-split-rounds
description: RYFT checks for a fix round that splits Demo data from the account per feature (PR 6 C round 2, 2026-11-19) - read-backs that take the cache after a refresh that sent nothing, one concern wired three ways (self-registering store, ScreenModels forgetter, RyftApp onChange Task), preview graph swaps (.preview to .test) losing coach-marks-done, isLive-gated rows vanishing on forget, nil-for-demo seams
metadata:
  type: feedback
---

From the PR 6 C round-2 re-check (read-only, no build, 2026-11-19). Every listed item was done; these were what the fixes left:
- **A read-back that trusts the cache after `refreshUser`.** `Repository.refreshUser` does `_ = try await env.reads.run(...)`;
  `ReadScheduler.enter` returns nil (nothing sent, no throw) offline or while `.me` has `retryNotBefore` (a 429/503 with a long
  `Retry-After`, up to 300 s). A caller that then takes `state.user?.x` as "what RYFT holds" (Notifications' `readSettingsBack`,
  the older `askAgain`) puts the pre-save cache over a PATCH the platform just confirmed. Ask for "fetched or not" from the
  refresh; keep the PATCH's answer and the mark when nothing went.
- **One concern, three wirings.** JournalStore registers its own forgetter (`convenience init(state:)`), Sleep → Bedtime's is
  registered in `ScreenModels`, Tonight's `BedtimePlanner` runs from RyftApp's `onChange(of: settings.demoMode)` in a `Task`.
  Only the first two run inside `state.reset()`, so only they are unit-testable; the RyftApp one is tested by calling
  `accountChanged()` by hand. Ask for the sync part (generation, cache, plan) as a forgetter and the async teardown kept outside.
- **Preview graphs swapped from `.preview` to `.test`** lose `.preview`'s defaults: `CoachMarks.doneKey` is set only there, so a
  scored Today on `.test` shows coach mark 1 of 3; `hasDataSource` then also needs `settings.isConfigured` (xcconfig URL).
- **Forget-now, restore-on-next-load** leaves `isLive`-gated UI empty until some screen calls `load()`: Profile's Journal row
  (`ProfileRows` `.settings` group) vanishes on the Demo switch and only Today/Insights bring it back. Grep every `isLive` reader.
- **`AppEnvironment.accountDocuments` (nil in demo)**: each feature grows its own memory cache (`demoCached` x2, JournalStore's
  restore + `seedForPreview`), and `env.persistence` stays open for new call sites. A demo in-memory document store would be uniform.
- Not findings here (checked): the sign-out wipe runs before every forgetter, synchronously, in `AuthService.apply`, so a
  restore can't read a pre-wipe store; `APIClient(session:)` falls back to the injected session for the fail-fast path, so a
  URLProtocol stub does see `singleAttempt` requests.

**Why:** each needed the read scheduler's nil path, the preview env's defaults, or the Profile row list, none in the diff.
**How to apply:** any round that moves a feature's cache, forgetter or online rule across the Demo/account split. See
[[review-checks-shared-write-waits]], [[review-checks-presented-styles]], [[review-checks-setting-editors]].
