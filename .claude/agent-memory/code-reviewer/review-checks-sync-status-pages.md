---
name: review-checks-sync-status-pages
description: RYFT review checks for pages that state sync freshness (Nocturne PR 6 C2 Devices & sync, Check sync, Sync details, 2026-11-19) - "Up to date" keyed on a last-good timestamp, freshness deciders that miss gated reads, incomplete "waiting to send" counts, placement enums vs every presenter, pushed pages inside sheets
metadata:
  type: feedback
---

Found in the C2 review (read-only, 2026-11-19); suite, UISmoke and shots were green:
- **"Up to date" from a last-GOOD timestamp.** `phaseText` said "Up to date" when `engine.phase == .idle && settings.lastSync != nil`.
  The engine sets `phase = .idle` on *every* exit (error, gate refusal, stop-early backlog: `SyncService.swift` ~765-807) and
  `lastSync` is only the last success, so a failed or gate-paused run still reads "Up to date" while Today says "Health sync
  paused" / "Action needed". Walk every catch branch of the engine run and ask what the word becomes; compare with Today's
  `SyncLine` decide order (actionNeeded, paused, backlog). `engine.lastError` is cleared at run start: a reliable "last run failed".
- **Freshness deciders keyed on `consecutiveFailures`** miss gated reads: `ReadScheduler.failed` does not count `.gate`
  (`Repository.swift` ~1522), only sets `lastError`. Under a consent/invite gate the cached list reads "fresh" and an empty one
  "Loading…" forever. Also check the nil-timestamp fallback copy ("Offline." while online-but-failing).
- **"N waiting to send" rows:** enumerate every outbox: activities+nights (`ActivityStore.unconfirmedCount`, which also counts a
  running recording), Train ops (`TrainSyncService.pendingCount`, `heldAt`), queued reports (`ReportProblemModel.waiting`); journal
  writes are online-only (nothing queues). A row that counts one of three is honest only by its title.
- **Placement enums** (`.pushed/.sheet/.root`): grep every presenter, including DEBUG `-RyftScreen` hosts (`RyftApp.swift`) that
  put a page at a stack root (dead Back) and the screenshot script that captures them; an enum case no caller passes is dead.
- **A page pushed inside a sheet** with a hidden bar loses the sheet root's 26 pt top inset when `isSheet` is only per page.
- Hosted tile tests: `SelectableTile` is a Button with `children: .ignore`, so hosted `activate()` fails (run1 log) and the
  implementer dropped the edit step; check the XCUITest (`DevicesUITests`, UISmoke) proves the edited choice is what Done saves.
- Mock request paths: the sync is `POST /v1/sync` on the ingest host; mocks showed `/v1/ingest/samples` (never served).

**Why:** none of these showed in green tests or matching shots; they needed the engine's catch branches, the read recorder,
and the outbox list. **How to apply:** any page that says "Up to date", "Last sync", "waiting to send" or "last loaded".
See [[review-checks-local-overrides]], [[review-checks-screen-restyles]], [[review-checks-settings-subpages]], [[review-checks-list-and-sheets]].
