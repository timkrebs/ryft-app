# Review: P1 Profile groups

## ios-lead's line review of the Codex draft (2026-11-27)

| # | Finding | Fix |
|---|---|---|
| 1 | The new `devicesAndSync` and `helpAndFeedback` row cases duplicated the pre-P1 `devices` and `reportProblem` rows. One renamed the identifier `profile.devices` → `profile.devicesAndSync`, so five UI tests had to change; `home(of:)` needed a mapping table. | Removed both cases. The top rows are `.devices` and `.reportProblem`, with their identifiers kept. The UI tests are back on `profile.devices`. |
| 2 | `ProfilePage.sections(.devicesAndSync)` listed the Apple Health read card and Sync details even when tracker setup is on, where `DevicesAndSyncView` draws its own (`devices.*`). The page filtered them out, but `home(of:)` reported homes that weren't drawn. | Those two sections only exist without tracker setup. The inventory test treats them as covered by the tracker page when it's on. |
| 3 | `AnalyticsOptInRow`'s preview still used the removed `ProfileGroup.privacy`, which broke the build. | The preview now uses the Analytics card's title. |
| 4 | Strings: Codex couldn't sync the catalog. | `make strings`, then German added for 19 new keys by targeted edits. The sync also dropped 3 keys that were already stale on `main` (`Measure`, `Add %@ g of %@`, `%@ · %@ g`), which is what an Xcode build does. |
| 5 | The docs still named the old paths. | `APP_STORE.md` (legal links, Demo data, reviewer delete path), `APP_STORE_METADATA.md` (strength-to-Health toggle) and `ANALYTICS.md`'s privacy text (the analytics opt-out path, the Sync now line). |

Checked and kept as Codex wrote it:
- Prompts are hoisted into `ProfilePrompts`; dialogs stay on `ProfileView`, outside the stack.
- Sync now still calls `syncNowFromProfile()`; no new sync path, wait or "last sync" logic.
- The D6 hold is on the Log out pill, Account's Log out row, Demo data and the Debug overrides.
- The withdrawal-hold tests are redistributed per page, with no check lost.
- The `DevicesAndSyncView` generic slots have an `EmptyView` init, so the Today sheet and `RyftApp` are unchanged.

## code-reviewer

(pending)
