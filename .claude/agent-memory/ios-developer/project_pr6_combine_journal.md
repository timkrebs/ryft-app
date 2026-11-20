---
name: project-pr6-combine-journal
description: M3 PR 6 combine (A + B into C) — how the Journal sheet was resolved, which tests broke on C's demo/account split, About you seams, ids and Train meta joins
metadata:
  type: project
---

M3 (2026-11-20): `feat/nocturne-pr6` = C + A (`feat/nocturne-pr6-onboarding`) + B (`feat/nocturne-pr6-train`), worktree
scratchpad/wt-pr6. Only two textual conflicts per merge; the rest were semantic.

**Why:** the next tickets (accent lint, strings pass, reviews) and any re-merge land on the same seams.

**How to apply:**
- Journal: B's `JournalSheetModel`/`JournalViews` (phases, save guards, edits counter, isDirty + discard dialog, saver seam)
  plus C's `opened: JournalStore.Owner` + `leftItsSide` (also set when the store's save throws CancellationError for a
  gone owner). The sheet takes the network from `model.isOnline` (store: `env.isDemo || connectivity`), not the
  environment's `ConnectivityMonitor`. C's `journalPreviewStore` (`seedForPreview` on demo, `accountDocuments` on account)
  and its `#if DEBUG` around the previews stay.
- C's split breaks any test that builds an "offline" journal on `AppState.preview` (demo: never offline) or seeds
  `env.persistence` on a demo graph (the store ignores it): use `AppState(env: .test(clock:online:))` (account) or
  `store.seedForPreview(behaviors:days:)`. `AppEnvironment.test` is the account side (demoOverride false).
- Two helpers named `expectNocturneFrame` merged silently as overloads; now one `(…, header:)` async throws:
  `subpage.close` / `subpage.back` (C's SubpageScaffold) or `sheet.close` (B's SheetHeader).
- Sheet answer switches are `journal.answer.<key>`; Profile → Journal keeps `journal.habit.<key>` (its UI test uses it).
- Sheet Try again = `JournalSheetModel.retry()` → `store.load/loadDay(userInitiated: true)`; test it by seeding
  `env.reads.seed([.journal: ResourceState(consecutiveFailures: 1, retryNotBefore: now + 300)])`.
- Offline pill copy is `JournalOfflinePill.message(keepsAnswers:)` from `JournalStore.keepsOfflineAnswers` (false until O6).
- 032bc9d (C + PR 5) did not compile: PR 5's `reminderPercentKeepsItsSign` called `scheduleReminders(…calendar:)`, which C
  made private; read the body from `BedtimePlanner.reminders(schedule:plan:now:calendar:)`.
- About you (onboarding) shows `editor.errorMissed` in the card's footer (`aboutYou.bodySettingsError`); hosted test
  pattern: `C3Platform.api()` + `Gate`, save the birth year first, then set `platform.onPatch` to hold and throw.
- Busy rule left elsewhere (title swaps to a gerund while busy): invite Continue "Checking…", SetNewPassword "Saving…",
  ForgotPassword "Sending…", TrackerCheck "Checking…", ReportProblem "Sending…" (C's spec §2.6 says gerund; lead rule says
  keep the title).
- Train meta lines use `MyDayText.join`; an `ActivityListRow` meta stacks from AX1 by itself; a plain Text needs
  `ActivityListRow.metaLines(_, stacked:)` (Today's done card does).
