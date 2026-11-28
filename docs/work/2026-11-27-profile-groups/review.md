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

## code-reviewer (one pass, nothing blocking)

| # | Finding | Outcome |
|---|---|---|
| 1 | The Devices and sync status tile always pushed Sync details, ignoring the line's own tap (sign in, retry, gate). | Fixed: it goes through `model.tapStatus(status.tap)` and uses `status.hint`, like the identity row. It's disabled when the line has no tap. |
| 2 | `importTraining` had come to depend on `train.enabled`. | Fixed: a new `showsImport` fact (`train.import`). Training shows when either flag is on, with the import rows alone if Train is off. Tested. |
| 3 | The withdrawal-hold tests were weaker. | Fixed: `settle()` after the held Demo data tap. The failed-withdrawal test checks Withdraw and the main page's Log out are live again. Not added: a busy check on Account's Log out row (the pill's busy check is in the hosted shots). |
| 4 | Rate RYFT's `requestReview` may show nothing. | Kept: the brief asks for the system prompt, and the App Store ID isn't in the repo. The hint now says "Asks iOS to show the App Store rating prompt". |
| 5 | `RescoreStatus` showed only under Advanced. | Fixed: it's also in the Body and baselines footer. |
| 6 | `canAskForHealth` had a branch with no effect. | Fixed: it's the model's. |
| 7 | "Devices & sync" title vs "Devices and sync" row; the "Sync" card title shares Today's key. | Kept: "Devices & sync" is the existing page title on every entry point. "Sync" has the same German either way. |

Tests: `ConsentWithdrawalTests.aFailedWithdrawalShowsItsMessage` still looked on the top page and now uses Privacy and data. Codex missed it; the first unit run caught it.
